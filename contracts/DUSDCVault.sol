// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DUSDCVault
 * @notice ERC-4626 vault for idle USDC.e held by Doma Protocol traders. Deposits mint
 *         `dUSDC` shares. Idle liquidity above a local buffer is periodically swept by
 *         an off-chain keeper, bridged to Base, and deployed into a Morpho vault to earn
 *         yield. `dUSDC` is designed to be spendable directly as a Doma Marketplace
 *         payment currency (via Seaport orders) — sellers who receive it keep earning
 *         yield without needing to redeem.
 *
 * ARCHITECTURE NOTE (cross-chain NAV):
 * The vault's shares live on Doma chain, but a portion of the underlying assets live on
 * Base inside a Morpho vault. This contract does NOT itself bridge or call Morpho — it
 * only accounts for value that a trusted off-chain system reports. Concretely:
 *
 *   totalAssets() = (USDC.e held locally) + (remoteReportedValue)
 *
 * `remoteReportedValue` is set by an address holding NAV_REPORTER_ROLE (expected to be a
 * multisig or an oracle/relayer contract fed by a verified cross-chain message — see
 * README.md). To bound the damage a compromised/misbehaving reporter can do, every
 * report is: (a) capped to a max percentage change from the last accepted value, and
 * (b) subject to a timelock before it takes effect. This is a deliberately simple v1;
 * see README.md for the upgrade path to a fully message-passing oracle (Chainlink CCIP /
 * LayerZero) that removes the reporter trust assumption entirely.
 *
 * LIQUIDITY MODEL:
 * `withdraw`/`redeem` succeed instantly only up to the local USDC.e balance. If the
 * vault can't cover a redemption locally (because assets are deployed to Morpho on
 * Base), the depositor calls `requestRedeem` instead, which escrows their shares (they
 * keep accruing value, since escrowed shares are only transferred to this contract, not
 * burned) and queues a claim. An ALLOCATOR_ROLE keeper calls `fulfillQueuedRedemptions`
 * once it has bridged enough USDC.e back to Doma chain.
 *
 * This contract intentionally does NOT implement the bridge/Morpho integration itself —
 * that lives in an off-chain keeper (see the TypeScript service planned alongside this
 * contract) and/or a separate on-chain adapter. Keeping this contract's surface area
 * small is deliberate: it only needs to trust that ALLOCATOR_ROLE moves real USDC.e in
 * and out, and that NAV_REPORTER_ROLE reports honestly within the guardrails below.
 */
contract DUSDCVault is ERC4626, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Roles
    // ---------------------------------------------------------------------

    /// @notice Can pull idle USDC.e out for bridging/deployment, and can pay out the
    /// queued-redemption backlog once funds are bridged back. Expected to be a keeper
    /// bot / automation contract, NOT an EOA held by a single person in production.
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @notice Can report the value of assets currently deployed on Base. Expected to be
    /// a multisig or oracle/relayer contract, not a single EOA.
    bytes32 public constant NAV_REPORTER_ROLE = keccak256("NAV_REPORTER_ROLE");

    /// @notice Can pause/unpause in an emergency. Separate from DEFAULT_ADMIN_ROLE so an
    /// incident-response multisig can react without full admin rights.
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    uint256 private constant BPS_DENOMINATOR = 10_000;

    // ---------------------------------------------------------------------
    // Cross-chain NAV accounting
    // ---------------------------------------------------------------------

    /// @notice Last accepted value (in asset terms, e.g. USDC.e with 6 decimals) of
    /// funds deployed off-chain into Morpho on Base.
    uint256 public remoteReportedValue;

    /// @notice A NAV report awaiting its timelock before it can be applied.
    uint256 public pendingRemoteValue;
    uint256 public pendingRemoteValueEffectiveAt;

    /// @notice Delay before a new NAV report takes effect. Gives observers/guardians a
    /// window to notice and pause if a report looks wrong.
    uint256 public navReportDelay = 6 hours;

    /// @notice Max allowed relative change per NAV report, in basis points, to bound the
    /// damage from a single bad/compromised report. Ignored for the very first report
    /// (when remoteReportedValue == 0).
    uint256 public maxNavDeviationBps = 500; // 5%

    /// @notice Running total of principal sent out via `allocate` minus principal
    /// returned via `reclaim`. Sanity-check bookkeeping only — NOT used in totalAssets().
    uint256 public totalAllocatedToRemote;

    // ---------------------------------------------------------------------
    // Local liquidity buffer parameters
    // ---------------------------------------------------------------------

    /// @notice Floor, in basis points of totalAssets(), below which `allocate` will
    /// refuse to push more USDC.e out to the keeper. Enforced on-chain.
    uint256 public minLocalBufferBps = 500; // 5% hard floor

    /// @notice Informational target buffer for the off-chain keeper to aim for. Not
    /// enforced on-chain (the keeper reads this to decide how much idle cash to sweep).
    uint256 public targetBufferBps = 1500; // 15% target

    /// @notice Optional cap on total deposits (0 = uncapped), for a cautious v1 launch.
    uint256 public depositCap;

    // ---------------------------------------------------------------------
    // Async redemption queue
    // ---------------------------------------------------------------------

    struct RedemptionRequest {
        address owner;
        address receiver;
        uint256 shares;
        bool fulfilled;
    }

    RedemptionRequest[] public redemptionQueue;

    /// @notice Index of the first not-yet-fulfilled request. Requests are fulfilled
    /// strictly in FIFO order.
    uint256 public nextRedemptionIndexToFulfill;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error InsufficientLocalLiquidity(uint256 requested, uint256 available);
    error BufferFloorBreached(uint256 remainingAfter, uint256 requiredBuffer);
    error ReclaimExceedsAllocated(uint256 amount, uint256 totalAllocated);
    error NavDeviationTooLarge(uint256 attempted, uint256 maxAllowed);
    error NavReportNotReady(uint256 effectiveAt, uint256 nowTs);
    error NoPendingNavReport();
    error DepositCapExceeded(uint256 attemptedTotal, uint256 cap);
    error CannotRescueVaultAsset();
    error ZeroAddress();

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event Allocated(address indexed to, uint256 amount);
    event Reclaimed(uint256 amount);
    event NavReportQueued(uint256 newValue, uint256 effectiveAt);
    event NavReportApplied(uint256 newValue);
    event RedeemQueued(uint256 indexed requestId, address indexed owner, address indexed receiver, uint256 shares);
    event RedeemFulfilled(uint256 indexed requestId, address indexed receiver, uint256 assets);
    event BufferParamsUpdated(uint256 minLocalBufferBps, uint256 targetBufferBps);
    event NavReportParamsUpdated(uint256 navReportDelay, uint256 maxNavDeviationBps);
    event DepositCapUpdated(uint256 newCap);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(
        IERC20 usdcE,
        string memory name_,
        string memory symbol_,
        address admin
    ) ERC20(name_, symbol_) ERC4626(usdcE) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ---------------------------------------------------------------------
    // ERC-4626 overrides
    // ---------------------------------------------------------------------

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + remoteReportedValue;
    }

    /// @notice USDC.e sitting in this contract right now, available for instant
    /// withdrawal/redeem and for `allocate`.
    function localLiquidity() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;
        if (depositCap == 0) return type(uint256).max;
        uint256 assets = totalAssets();
        return assets >= depositCap ? 0 : depositCap - assets;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (maxAssets == type(uint256).max) return type(uint256).max;
        return previewDeposit(maxAssets);
    }

    /// @dev Instant withdrawal is only available up to local liquidity; otherwise the
    /// caller should use `requestRedeem`.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        uint256 available = localLiquidity();
        if (assets > available) revert InsufficientLocalLiquidity(assets, available);
        return super.withdraw(assets, receiver, owner);
    }

    /// @dev Instant redeem is only available up to local liquidity; otherwise the caller
    /// should use `requestRedeem`.
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        assets = previewRedeem(shares);
        uint256 available = localLiquidity();
        if (assets > available) revert InsufficientLocalLiquidity(assets, available);
        return super.redeem(shares, receiver, owner);
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    // ---------------------------------------------------------------------
    // Async redemption queue (for when local liquidity is insufficient)
    // ---------------------------------------------------------------------

    /**
     * @notice Escrow `shares` and queue a redemption for `receiver`, to be paid out once
     *         the keeper bridges enough USDC.e back to this contract. Escrowed shares
     *         are held by the vault (not burned), so they keep accruing value at the
     *         current share price until the request is fulfilled.
     * @return requestId Index into `redemptionQueue`; poll `redemptionQueue[requestId]`
     *         to check `fulfilled`.
     */
    function requestRedeem(uint256 shares, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 requestId)
    {
        if (receiver == address(0)) revert ZeroAddress();
        _transfer(_msgSender(), address(this), shares);

        redemptionQueue.push(
            RedemptionRequest({owner: _msgSender(), receiver: receiver, shares: shares, fulfilled: false})
        );
        requestId = redemptionQueue.length - 1;
        emit RedeemQueued(requestId, _msgSender(), receiver, shares);
    }

    /**
     * @notice Pay out queued redemptions in FIFO order, up to `maxRequests`, stopping
     *         early if local liquidity runs out. Callable only by the allocator keeper,
     *         which is expected to call this right after bridging USDC.e back.
     */
    function fulfillQueuedRedemptions(uint256 maxRequests)
        external
        onlyRole(ALLOCATOR_ROLE)
        nonReentrant
        returns (uint256 processed)
    {
        uint256 i = nextRedemptionIndexToFulfill;
        uint256 queueLength = redemptionQueue.length;

        while (i < queueLength && processed < maxRequests) {
            RedemptionRequest storage req = redemptionQueue[i];
            uint256 assetsOwed = previewRedeem(req.shares);

            if (assetsOwed > localLiquidity()) break;

            _burn(address(this), req.shares);
            IERC20(asset()).safeTransfer(req.receiver, assetsOwed);
            req.fulfilled = true;

            emit RedeemFulfilled(i, req.receiver, assetsOwed);

            unchecked {
                ++i;
                ++processed;
            }
        }

        nextRedemptionIndexToFulfill = i;
    }

    /// @notice Number of queued requests not yet fulfilled.
    function pendingRedemptionCount() external view returns (uint256) {
        return redemptionQueue.length - nextRedemptionIndexToFulfill;
    }

    // ---------------------------------------------------------------------
    // Allocator (bridge / Morpho deployment) integration points
    // ---------------------------------------------------------------------

    /**
     * @notice Send idle USDC.e out to the allocator/bridge for deployment into Morpho on
     *         Base. Reverts if it would push local liquidity below `minLocalBufferBps`
     *         of totalAssets(). Does NOT change totalAssets() by itself — the keeper is
     *         expected to follow up with a `reportRemoteValue` call once the funds are
     *         confirmed deployed, otherwise those assets temporarily disappear from
     *         accounting (fail safe: undercounts value, never overcounts).
     */
    function allocate(uint256 amount, address to) external onlyRole(ALLOCATOR_ROLE) nonReentrant whenNotPaused {
        if (to == address(0)) revert ZeroAddress();

        uint256 available = localLiquidity();
        if (amount > available) revert InsufficientLocalLiquidity(amount, available);

        uint256 remainingAfter = available - amount;
        uint256 requiredBuffer = (totalAssets() * minLocalBufferBps) / BPS_DENOMINATOR;
        if (remainingAfter < requiredBuffer) revert BufferFloorBreached(remainingAfter, requiredBuffer);

        totalAllocatedToRemote += amount;
        remoteReportedValue += amount;
        IERC20(asset()).safeTransfer(to, amount);

        emit Allocated(to, amount);
    }

    /**
     * @notice Record that `amount` of previously-deployed principal has been bridged
     *         back and is now sitting in this contract as local USDC.e again. Must be
     *         called AFTER the actual token transfer lands, and decrements
     *         `remoteReportedValue` by the same amount so `totalAssets()` doesn't double
     *         count (the tokens are now counted via local balance instead).
     */
    function reclaim(uint256 amount) external onlyRole(ALLOCATOR_ROLE) {
        if (amount > totalAllocatedToRemote) revert ReclaimExceedsAllocated(amount, totalAllocatedToRemote);

        totalAllocatedToRemote -= amount;
        remoteReportedValue = amount > remoteReportedValue ? 0 : remoteReportedValue - amount;

        emit Reclaimed(amount);
    }

    // ---------------------------------------------------------------------
    // Cross-chain NAV reporting
    // ---------------------------------------------------------------------

    /**
     * @notice Queue a new remote-value report. Takes effect after `navReportDelay`,
     *         unless it exceeds `maxNavDeviationBps` relative change from the current
     *         accepted value (the very first report is exempt, since current == 0).
     */
    function reportRemoteValue(uint256 newValue) external onlyRole(NAV_REPORTER_ROLE) {
        uint256 current = remoteReportedValue;

        if (current > 0) {
            uint256 diff = newValue > current ? newValue - current : current - newValue;
            uint256 maxDiff = (current * maxNavDeviationBps) / BPS_DENOMINATOR;
            if (diff > maxDiff) revert NavDeviationTooLarge(newValue, current + maxDiff);
        }

        pendingRemoteValue = newValue;
        pendingRemoteValueEffectiveAt = block.timestamp + navReportDelay;

        emit NavReportQueued(newValue, pendingRemoteValueEffectiveAt);
    }

    /**
     * @notice Apply a queued NAV report once its timelock has elapsed. Permissionless on
     *         purpose, so finalization can't be censored by whoever holds the reporter
     *         role.
     */
    function applyPendingNavReport() external {
        if (pendingRemoteValueEffectiveAt == 0) revert NoPendingNavReport();
        if (block.timestamp < pendingRemoteValueEffectiveAt) {
            revert NavReportNotReady(pendingRemoteValueEffectiveAt, block.timestamp);
        }

        remoteReportedValue = pendingRemoteValue;
        pendingRemoteValueEffectiveAt = 0;

        emit NavReportApplied(remoteReportedValue);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setBufferParams(uint256 newMinLocalBufferBps, uint256 newTargetBufferBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newMinLocalBufferBps <= newTargetBufferBps, "min buffer must be <= target buffer");
        require(newTargetBufferBps <= BPS_DENOMINATOR, "target buffer must be <= 100%");
        minLocalBufferBps = newMinLocalBufferBps;
        targetBufferBps = newTargetBufferBps;
        emit BufferParamsUpdated(newMinLocalBufferBps, newTargetBufferBps);
    }

    function setNavReportParams(uint256 newNavReportDelay, uint256 newMaxNavDeviationBps)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newMaxNavDeviationBps <= BPS_DENOMINATOR, "deviation must be <= 100%");
        navReportDelay = newNavReportDelay;
        maxNavDeviationBps = newMaxNavDeviationBps;
        emit NavReportParamsUpdated(newNavReportDelay, newMaxNavDeviationBps);
    }

    function setDepositCap(uint256 newCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        depositCap = newCap;
        emit DepositCapUpdated(newCap);
    }

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
    }

    /// @notice Rescue tokens accidentally sent to this contract. Cannot be used to pull
    /// out the vault's own asset (USDC.e) or its own share token — those are only ever
    /// moved via `allocate`/`withdraw`/`redeem`/queue fulfillment.
    function rescueToken(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == asset() || token == address(this)) revert CannotRescueVaultAsset();
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit TokenRescued(token, to, amount);
    }
}
