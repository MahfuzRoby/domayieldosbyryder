// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DUSDCVault} from "../contracts/DUSDCVault.sol";
import {DomainVault} from "../contracts/DomainVault.sol";
import {MockDomainNFT} from "../contracts/mocks/MockDomainNFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDCe2 is ERC20 {
    constructor() ERC20("Bridged USDC", "USDC.e") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract DomainVaultTest is Test {
    MockUSDCe2 internal usdc;
    DUSDCVault internal pool;
    MockDomainNFT internal nft;
    DomainVault internal vault;

    address internal admin = makeAddr("admin");
    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");
    address internal liquidator = makeAddr("liquidator");

    uint256 internal constant ONE_USDC = 1e6;
    uint256 internal tokenId;

    function setUp() public {
        usdc = new MockUSDCe2();
        pool = new DUSDCVault(IERC20(address(usdc)), "Doma USDC Vault", "dUSDC", admin);
        nft = new MockDomainNFT();
        vault = new DomainVault(address(nft), payable(address(pool)), admin);

        vm.startPrank(admin);
        pool.grantRole(pool.ALLOCATOR_ROLE(), address(vault));
        vm.stopPrank();

        // Seed the lending pool with lender capital.
        usdc.mint(lender, 100_000 * ONE_USDC);
        vm.startPrank(lender);
        usdc.approve(address(pool), type(uint256).max);
        pool.deposit(50_000 * ONE_USDC, lender);
        vm.stopPrank();

        // Mint a domain to the borrower, valid for 1 year, priced at $10,000.
        tokenId = nft.mintDomain(borrower, 365);
        vm.prank(admin);
        vault.setPrice(tokenId, 10_000 * ONE_USDC);

        // Give the borrower/liquidator USDC for repayments.
        usdc.mint(borrower, 10_000 * ONE_USDC);
        usdc.mint(liquidator, 10_000 * ONE_USDC);
    }

    function test_DepositBorrowRepayWithdraw() public {
        vm.startPrank(borrower);
        nft.approve(address(vault), tokenId);
        vault.depositCollateral(tokenId);

        vault.borrow(tokenId, 3_000 * ONE_USDC); // 30% LTV, under the 40% cap
        assertEq(usdc.balanceOf(borrower), 13_000 * ONE_USDC);

        usdc.approve(address(vault), type(uint256).max);
        vault.repay(tokenId, 3_000 * ONE_USDC);

        vault.withdrawCollateral(tokenId);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), borrower);
    }

    function test_BorrowRevertsAboveLTV() public {
        vm.startPrank(borrower);
        nft.approve(address(vault), tokenId);
        vault.depositCollateral(tokenId);

        vm.expectRevert(); // 4,001 > 40% of 10,000
        vault.borrow(tokenId, 4_001 * ONE_USDC);
        vm.stopPrank();
    }

    function test_LiquidationWhenUnderwater() public {
        vm.startPrank(borrower);
        nft.approve(address(vault), tokenId);
        vault.depositCollateral(tokenId);
        vault.borrow(tokenId, 4_000 * ONE_USDC); // right at the 40% LTV cap
        vm.stopPrank();

        // Price crashes: domain revalued to $6,000 -> debt/adjustedCollateral now underwater
        // (adjustedCollateral = 6,000 * 50% = 3,000 < 4,000 debt).
        vm.prank(admin);
        vault.setPrice(tokenId, 6_000 * ONE_USDC);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), type(uint256).max);
        vault.liquidate(tokenId);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), liquidator);
        (, uint256 debt, bool active) = vault.positions(tokenId);
        assertEq(debt, 0);
        assertFalse(active);
    }

    function test_LiquidationWhenExpiringSoon() public {
        vm.startPrank(borrower);
        nft.approve(address(vault), tokenId);
        vault.depositCollateral(tokenId);
        vault.borrow(tokenId, 1_000 * ONE_USDC); // healthy debt, well under LTV cap
        vm.stopPrank();

        // Fast-forward so the domain is within the 14-day expiry buffer, though still valid.
        vm.warp(block.timestamp + 365 days - 10 days);

        vm.startPrank(liquidator);
        usdc.approve(address(vault), type(uint256).max);
        vault.liquidate(tokenId); // healthy debt-wise, but liquidatable due to nearing expiry
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), liquidator);
    }

    function test_CannotDepositExpiringDomain() public {
        uint256 shortLived = nft.mintDomain(borrower, 10); // only 10 days validity
        vm.prank(admin);
        vault.setPrice(shortLived, 1_000 * ONE_USDC);

        vm.startPrank(borrower);
        nft.approve(address(vault), shortLived);
        vm.expectRevert(); // fails minValidityPeriod (30 days) check
        vault.depositCollateral(shortLived);
        vm.stopPrank();
    }
}
