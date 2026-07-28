// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DUSDCVault} from "../contracts/DUSDCVault.sol";

contract MockUSDCe is ERC20 {
    constructor() ERC20("Bridged USDC", "USDC.e") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DUSDCVaultTest is Test {
    MockUSDCe internal usdc;
    DUSDCVault internal vault;

    address internal admin = makeAddr("admin");
    address internal allocator = makeAddr("allocator");
    address internal navReporter = makeAddr("navReporter");
    address internal guardian = makeAddr("guardian");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant ONE_USDC = 1e6;

    function setUp() public {
        usdc = new MockUSDCe();
        vault = new DUSDCVault(IERC20(address(usdc)), "Doma Yield USDC", "dUSDC", admin);

        vm.startPrank(admin);
        vault.grantRole(vault.ALLOCATOR_ROLE(), allocator);
        vault.grantRole(vault.NAV_REPORTER_ROLE(), navReporter);
        vault.grantRole(vault.GUARDIAN_ROLE(), guardian);
        vm.stopPrank();

        usdc.mint(alice, 100_000 * ONE_USDC);
        usdc.mint(bob, 100_000 * ONE_USDC);
    }

    function _deposit(address user, uint256 assets) internal returns (uint256 shares) {
        vm.startPrank(user);
        usdc.approve(address(vault), assets);
        shares = vault.deposit(assets, user);
        vm.stopPrank();
    }

    // -- Deposits / instant withdrawals --------------------------------

    function test_DepositMintsSharesOneToOneInitially() public {
        uint256 shares = _deposit(alice, 1_000 * ONE_USDC);
        assertEq(shares, 1_000 * ONE_USDC);
        assertEq(vault.totalAssets(), 1_000 * ONE_USDC);
    }

    function test_InstantWithdrawWithinLocalLiquidity() public {
        _deposit(alice, 1_000 * ONE_USDC);

        vm.prank(alice);
        vault.withdraw(400 * ONE_USDC, alice, alice);

        assertEq(usdc.balanceOf(alice), 99_400 * ONE_USDC);
        assertEq(vault.localLiquidity(), 600 * ONE_USDC);
    }

    function test_InstantWithdrawRevertsBeyondLocalLiquidity() public {
        _deposit(alice, 1_000 * ONE_USDC);

        vm.prank(allocator);
        vault.allocate(900 * ONE_USDC, allocator); // leaves 100 local (10% buffer, above 5% floor)

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DUSDCVault.InsufficientLocalLiquidity.selector, 200 * ONE_USDC, 100 * ONE_USDC)
        );
        vault.withdraw(200 * ONE_USDC, alice, alice);
    }

    // -- Allocation / buffer floor ---------------------------------------

    function test_AllocateRevertsIfBufferFloorBreached() public {
        _deposit(alice, 1_000 * ONE_USDC);

        // min buffer is 5% by default -> can allocate at most 950 USDC.e
        vm.prank(allocator);
        vm.expectRevert(
            abi.encodeWithSelector(DUSDCVault.BufferFloorBreached.selector, 0, 50 * ONE_USDC)
        );
        vault.allocate(1_000 * ONE_USDC, allocator);
    }

    function test_AllocateAndReclaimAccounting() public {
        _deposit(alice, 1_000 * ONE_USDC);

        vm.prank(allocator);
        vault.allocate(900 * ONE_USDC, allocator);
        assertEq(vault.totalAllocatedToRemote(), 900 * ONE_USDC);

        // Simulate the keeper bridging funds back + reporting nav before reclaim.
        vm.prank(navReporter);
        vault.reportRemoteValue(900 * ONE_USDC);
        vm.warp(block.timestamp + vault.navReportDelay());
        vault.applyPendingNavReport();
        assertEq(vault.totalAssets(), 1_000 * ONE_USDC);

        vm.startPrank(allocator);
        usdc.transfer(address(vault), 900 * ONE_USDC);
        vault.reclaim(900 * ONE_USDC);
        vm.stopPrank();

        assertEq(vault.totalAllocatedToRemote(), 0);
        assertEq(vault.remoteReportedValue(), 0);
        assertEq(vault.totalAssets(), 1_000 * ONE_USDC); // unchanged: local balance now covers it
    }

    // -- NAV reporting: timelock + deviation cap --------------------------

    function test_NavReportAppliesOnlyAfterTimelock() public {
        vm.prank(navReporter);
        vault.reportRemoteValue(1_000 * ONE_USDC);

        vm.expectRevert(
            abi.encodeWithSelector(
                DUSDCVault.NavReportNotReady.selector, block.timestamp + vault.navReportDelay(), block.timestamp
            )
        );
        vault.applyPendingNavReport();

        vm.warp(block.timestamp + vault.navReportDelay());
        vault.applyPendingNavReport();
        assertEq(vault.remoteReportedValue(), 1_000 * ONE_USDC);
    }

    function test_NavReportRevertsOnExcessiveDeviation() public {
        vm.startPrank(navReporter);
        vault.reportRemoteValue(1_000 * ONE_USDC);
        vm.stopPrank();
        vm.warp(block.timestamp + vault.navReportDelay());
        vault.applyPendingNavReport();

        // default max deviation is 5% -> jumping to 2000 (100% up) should revert
        vm.prank(navReporter);
        vm.expectRevert(
            abi.encodeWithSelector(DUSDCVault.NavDeviationTooLarge.selector, 2_000 * ONE_USDC, 1_050 * ONE_USDC)
        );
        vault.reportRemoteValue(2_000 * ONE_USDC);
    }

    // -- Async redemption queue -------------------------------------------

    function test_RequestRedeemQueuesAndFulfillsFIFO() public {
        _deposit(alice, 1_000 * ONE_USDC);
        _deposit(bob, 1_000 * ONE_USDC);

        vm.prank(allocator);
        vault.allocate(1_900 * ONE_USDC, allocator); // leaves 100 local, below what alice+bob need

        uint256 aliceShares = vault.balanceOf(alice);
        assertEq(aliceShares, 1_000 * ONE_USDC); // 1:1 rate, no yield accrued yet

        vm.prank(alice);
        uint256 reqId = vault.requestRedeem(aliceShares, alice);
        assertEq(reqId, 0);

        // Not enough local liquidity yet -> fulfillment is a no-op.
        vm.prank(allocator);
        uint256 processed = vault.fulfillQueuedRedemptions(10);
        assertEq(processed, 0);

        // Keeper bridges funds back and updates accounting.
        vm.startPrank(allocator);
        usdc.transfer(address(vault), 1_900 * ONE_USDC);
        vault.reclaim(1_900 * ONE_USDC);
        processed = vault.fulfillQueuedRedemptions(10);
        vm.stopPrank();

        assertEq(processed, 1);
        assertEq(usdc.balanceOf(alice), 100_000 * ONE_USDC); // original 99k left + 1k redeemed back
    }

    // -- Access control / safety rails ------------------------------------

    function test_RescueTokenCannotPullVaultAsset() public {
        vm.prank(admin);
        vm.expectRevert(DUSDCVault.CannotRescueVaultAsset.selector);
        vault.rescueToken(address(usdc), admin, 1);
    }

    function test_OnlyGuardianCanPause() public {
        vm.prank(alice);
        vm.expectRevert(); // AccessControl unauthorized
        vault.pause();

        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_AllocateDoesNotChangeTotalAssets() public {
        _deposit(alice, 1_000 * ONE_USDC);
        _deposit(bob, 1_000 * ONE_USDC);

        uint256 totalBefore = vault.totalAssets();

        vm.prank(allocator);
        vault.allocate(1_900 * ONE_USDC, allocator);

        assertEq(vault.totalAssets(), totalBefore, "allocate() must not change totalAssets()");
    }
}
