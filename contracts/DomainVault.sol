// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDomainOwnershipToken} from "./interfaces/IDomainOwnershipToken.sol";
import {DUSDCVault} from "./DUSDCVault.sol";

/**
 * @title DomainVault
 * @notice Overcollateralized lending: deposit a tokenized Doma domain (Ownership
 *         Token) as collateral, borrow USDC.e against it, drawn from a shared
 *         DUSDCVault liquidity pool. Positions become liquidatable if the health
 *         factor drops below 1, OR if the domain is approaching expiration
 *         (an expired Doma domain becomes non-transferable, so the vault must
 *         force resolution before that happens).
 */
contract DomainVault is IERC721Receiver, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant PRICE_SETTER_ROLE = keccak256("PRICE_SETTER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    uint256 public constant BPS_DENOMINATOR = 10_000;

    IDomainOwnershipToken public immutable domainNFT;
    DUSDCVault public immutable lendingPool;
    IERC20 public immutable asset;

    /// @notice Max borrowable value as a fraction of collateral value, in bps.
    uint256 public loanToValueBps = 4_000; // 40%

    /// @notice Health-factor threshold below which a position is liquidatable, in bps
    /// terms relative to collateral value (i.e. debt / (collateralValue * threshold/10000) > 1).
    uint256 public liquidationThresholdBps = 5_000; // 50%

    /// @notice Minimum remaining validity a domain must have to be deposited or borrowed against.
    uint256 public minValidityPeriod = 30 days;

    /// @notice If a domain's remaining validity drops below this, any outstanding position
    /// becomes liquidatable regardless of health factor, to force resolution before expiry.
    uint256 public expiryLiquidationBuffer = 14 days;

    struct Position {
        address borrower;
        uint256 debt;
        bool active;
    }

    /// @notice tokenId => Position
    mapping(uint256 => Position) public positions;

    /// @notice tokenId => committee/oracle-set USD value of the domain, 1e18-scaled.
    mapping(uint256 => uint256) public collateralValue;

    event PriceSet(uint256 indexed tokenId, uint256 value);
    event CollateralDeposited(uint256 indexed tokenId, address indexed borrower);
    event Borrowed(uint256 indexed tokenId, address indexed borrower, uint256 amount);
    event Repaid(uint256 indexed tokenId, address indexed payer, uint256 amount);
    event CollateralWithdrawn(uint256 indexed tokenId, address indexed borrower);
    event Liquidated(uint256 indexed tokenId, address indexed liquidator, uint256 debtRepaid);
    event ParamsUpdated(uint256 loanToValueBps, uint256 liquidationThresholdBps);

    error ZeroAddress();
    error ZeroAmount();
    error NotBorrower();
    error PositionNotActive();
    error PositionAlreadyActive();
    error InsufficientValidity(uint256 remaining, uint256 required);
    error HealthFactorTooLow(uint256 healthFactorBps);
    error DebtNotZero(uint256 debt);
    error PositionHealthy();
    error NoPriceSet(uint256 tokenId);

    constructor(address _domainNFT, address payable _lendingPool, address admin) {
        if (_domainNFT == address(0) || _lendingPool == address(0) || admin == address(0)) revert ZeroAddress();
        domainNFT = IDomainOwnershipToken(_domainNFT);
        lendingPool = DUSDCVault(_lendingPool);
        asset = IERC20(lendingPool.asset());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PRICE_SETTER_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, admin);
    }

    // ---------------------------------------------------------------------
    // Price oracle (simple committee-set for MVP; swap for TWAP/Doma
    // fractionalization pool price feed later)
    // ---------------------------------------------------------------------

    function setPrice(uint256 tokenId, uint256 value) external onlyRole(PRICE_SETTER_ROLE) {
        if (value == 0) revert ZeroAmount();
        collateralValue[tokenId] = value;
        emit PriceSet(tokenId, value);
    }

    // ---------------------------------------------------------------------
    // Core position lifecycle
    // ---------------------------------------------------------------------

    function depositCollateral(uint256 tokenId) external nonReentrant whenNotPaused {
        if (positions[tokenId].active) revert PositionAlreadyActive();
        if (collateralValue[tokenId] == 0) revert NoPriceSet(tokenId);

        _checkValidity(tokenId);

        domainNFT.safeTransferFrom(msg.sender, address(this), tokenId);

        positions[tokenId] = Position({borrower: msg.sender, debt: 0, active: true});

        emit CollateralDeposited(tokenId, msg.sender);
    }

    function borrow(uint256 tokenId, uint256 amount) external nonReentrant whenNotPaused {
        Position storage pos = positions[tokenId];
        if (!pos.active) revert PositionNotActive();
        if (pos.borrower != msg.sender) revert NotBorrower();
        if (amount == 0) revert ZeroAmount();

        _checkValidity(tokenId);

        pos.debt += amount;

        uint256 maxDebt = (collateralValue[tokenId] * loanToValueBps) / BPS_DENOMINATOR;
        if (pos.debt > maxDebt) revert HealthFactorTooLow(_healthFactorBps(tokenId));

        // Pull liquidity from the shared USDC pool straight to the borrower.
        lendingPool.allocate(amount, msg.sender);

        emit Borrowed(tokenId, msg.sender, amount);
    }

    function repay(uint256 tokenId, uint256 amount) external nonReentrant {
        Position storage pos = positions[tokenId];
        if (!pos.active) revert PositionNotActive();
        if (amount == 0) revert ZeroAmount();

        uint256 payment = amount > pos.debt ? pos.debt : amount;
        pos.debt -= payment;

        // Route repayment back into the shared pool's accounting.
        asset.safeTransferFrom(msg.sender, address(lendingPool), payment);
        lendingPool.reclaim(payment);

        emit Repaid(tokenId, msg.sender, payment);
    }

    function withdrawCollateral(uint256 tokenId) external nonReentrant {
        Position storage pos = positions[tokenId];
        if (!pos.active) revert PositionNotActive();
        if (pos.borrower != msg.sender) revert NotBorrower();
        if (pos.debt != 0) revert DebtNotZero(pos.debt);

        pos.active = false;
        domainNFT.safeTransferFrom(address(this), msg.sender, tokenId);

        emit CollateralWithdrawn(tokenId, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Liquidation
    // ---------------------------------------------------------------------

    /// @notice Anyone can liquidate an unhealthy or soon-to-expire position by
    /// repaying its full outstanding debt, in exchange for the collateral NFT.
    function liquidate(uint256 tokenId) external nonReentrant {
        Position storage pos = positions[tokenId];
        if (!pos.active) revert PositionNotActive();

        bool unhealthy = _healthFactorBps(tokenId) < BPS_DENOMINATOR;
        bool expiringSoon = domainNFT.expirationOf(tokenId) <= block.timestamp + expiryLiquidationBuffer;

        if (!unhealthy && !expiringSoon) revert PositionHealthy();

        uint256 debt = pos.debt;
        pos.active = false;
        pos.debt = 0;

        if (debt > 0) {
            asset.safeTransferFrom(msg.sender, address(lendingPool), debt);
            lendingPool.reclaim(debt);
        }

        domainNFT.safeTransferFrom(address(this), msg.sender, tokenId);

        emit Liquidated(tokenId, msg.sender, debt);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Health factor in bps: (collateralValue * liquidationThresholdBps / debt).
    /// Returns type(uint256).max if there's no debt.
    function healthFactorBps(uint256 tokenId) external view returns (uint256) {
        return _healthFactorBps(tokenId);
    }

    function _healthFactorBps(uint256 tokenId) internal view returns (uint256) {
        uint256 debt = positions[tokenId].debt;
        if (debt == 0) return type(uint256).max;
        uint256 adjustedCollateral = (collateralValue[tokenId] * liquidationThresholdBps) / BPS_DENOMINATOR;
        return (adjustedCollateral * BPS_DENOMINATOR) / debt;
    }

    function _checkValidity(uint256 tokenId) internal view {
        uint256 expiry = domainNFT.expirationOf(tokenId);
        if (expiry < block.timestamp + minValidityPeriod) {
            uint256 remaining = expiry > block.timestamp ? expiry - block.timestamp : 0;
            revert InsufficientValidity(remaining, minValidityPeriod);
        }
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setParams(uint256 newLoanToValueBps, uint256 newLiquidationThresholdBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newLoanToValueBps <= newLiquidationThresholdBps, "LTV must be <= liquidation threshold");
        require(newLiquidationThresholdBps <= BPS_DENOMINATOR, "threshold must be <= 100%");
        loanToValueBps = newLoanToValueBps;
        liquidationThresholdBps = newLiquidationThresholdBps;
        emit ParamsUpdated(newLoanToValueBps, newLiquidationThresholdBps);
    }

    function setValidityParams(uint256 newMinValidityPeriod, uint256 newExpiryLiquidationBuffer)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        minValidityPeriod = newMinValidityPeriod;
        expiryLiquidationBuffer = newExpiryLiquidationBuffer;
    }

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
