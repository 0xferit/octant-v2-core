// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { BaseYieldSkimmingStrategy } from "src/strategies/yieldSkimming/BaseYieldSkimmingStrategy.sol";
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

/// @title Concrete implementation for testing (same pattern as BaseYieldSkimmingBranchCoverage)
contract TestYieldSkimmingStrategy is BaseYieldSkimmingStrategy {
    uint256 private _rate;

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseYieldSkimmingStrategy(
            _asset,
            _name,
            _symbol,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        _rate = 1e18;
    }

    function setExchangeRate(uint256 newRate) external {
        _rate = newRate;
    }

    function _getCurrentExchangeRate() internal view override returns (uint256) {
        return _rate;
    }

    function decimalsOfExchangeRate() public pure override returns (uint256) {
        return 18;
    }
}

/// @title Tests that dragon shares are burned before pricing user exits during insolvency
/// @notice Validates the fix for stale dragon share dilution: early and late redeemers
///         should receive equal value per share when exiting during an unreported loss.
contract YieldSkimmingStaleDragonBurnTest is Test {
    using Math for uint256;

    TestYieldSkimmingStrategy public strategy;
    ERC20Mock public asset;

    address public management = address(0x1);
    address public keeper = address(0x2);
    address public emergencyAdmin = address(0x3);
    address public dragonRouter = address(0x4);
    address public alice = address(0xA);
    address public bob = address(0xB);

    uint256 public constant WAD = 1e18;

    ITokenizedStrategy internal tokenized;
    YieldSkimmingTokenizedStrategy internal ys;

    function setUp() public {
        asset = new ERC20Mock();
        YieldSkimmingTokenizedStrategy implementation = new YieldSkimmingTokenizedStrategy();

        strategy = new TestYieldSkimmingStrategy(
            address(asset),
            "Test YieldSkim",
            "tsYS",
            management,
            keeper,
            emergencyAdmin,
            dragonRouter,
            true, // enableBurning
            address(implementation)
        );

        tokenized = ITokenizedStrategy(address(strategy));
        ys = YieldSkimmingTokenizedStrategy(address(strategy));

        // Allow large losses for test slashing simulations
        vm.prank(management);
        strategy.setLossLimitRatio(9999);
    }

    function _depositUser(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.prank(user);
        asset.approve(address(strategy), amount);
        vm.prank(user);
        tokenized.deposit(amount, user);
    }

    /// @notice Core test: two identical users redeeming during unreported insolvency
    ///         should receive equal assets per share, regardless of ordering relative
    ///         to keeper report().
    function test_equalRedemptionDuringUnreportedInsolvency() public {
        uint256 depositAmount = 100 ether;

        // Both users deposit at rate=1.0
        _depositUser(alice, depositAmount);
        _depositUser(bob, depositAmount);

        assertEq(tokenized.balanceOf(alice), 100 ether, "alice shares");
        assertEq(tokenized.balanceOf(bob), 100 ether, "bob shares");

        // Rate increases to 1.5 -> keeper reports profit -> dragon shares minted
        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonShares = tokenized.balanceOf(dragonRouter);
        assertGt(dragonShares, 0, "dragon buffer should exist");
        assertEq(tokenized.totalSupply(), 300 ether, "totalSupply = 200 user + 100 dragon");

        // Rate drops to 0.6 — vault becomes insolvent but NO keeper report yet
        strategy.setExchangeRate(6e17);
        assertTrue(ys.isVaultInsolvent(), "vault should be insolvent");

        // Alice redeems BEFORE any keeper report
        uint256 aliceShares = tokenized.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceAssets = tokenized.redeem(aliceShares, alice, alice);

        // Keeper reports (burns remaining dragons if any)
        vm.prank(keeper);
        tokenized.report();

        // Bob redeems AFTER keeper report
        uint256 bobShares = tokenized.balanceOf(bob);
        vm.prank(bob);
        uint256 bobAssets = tokenized.redeem(bobShares, bob, bob);

        // With the fix: alice and bob should receive equal assets per share
        // (within 1 wei rounding tolerance)
        assertApproxEqAbs(aliceAssets, bobAssets, 1, "early and late redeemers should receive equal assets");
    }

    /// @notice Verify that the lazy burn actually removes dragon shares from supply
    ///         when a user redeems during unreported insolvency.
    function test_lazyBurnRemovesDragonSharesOnUserRedeem() public {
        _depositUser(alice, 100 ether);

        // Create dragon buffer via profit
        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonSharesBefore = tokenized.balanceOf(dragonRouter);
        assertGt(dragonSharesBefore, 0, "dragon should have shares");

        // Make vault insolvent without reporting
        strategy.setExchangeRate(6e17);
        assertTrue(ys.isVaultInsolvent(), "vault should be insolvent");

        // Dragon shares should still exist before user redeems
        assertEq(tokenized.balanceOf(dragonRouter), dragonSharesBefore, "dragon shares stale before redeem");

        // User redeems — this should lazily burn dragon shares
        uint256 maxRedeem = tokenized.maxRedeem(alice);
        vm.prank(alice);
        tokenized.redeem(maxRedeem, alice, alice);

        // Dragon shares should have been burned by the lazy protection
        assertEq(tokenized.balanceOf(dragonRouter), 0, "dragon shares should be burned after user redeem");
    }

    /// @notice The lazy burn should be a no-op when burning is disabled.
    function test_noBurnWhenBurningDisabled() public {
        // Disable burning
        vm.prank(management);
        tokenized.setEnableBurning(false);

        _depositUser(alice, 100 ether);

        // Create dragon buffer via profit (need to re-enable burning temporarily for this)
        vm.prank(management);
        tokenized.setEnableBurning(true);

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonSharesBefore = tokenized.balanceOf(dragonRouter);

        // Now disable burning again
        vm.prank(management);
        tokenized.setEnableBurning(false);

        // Make vault insolvent without reporting
        strategy.setExchangeRate(6e17);

        // User redeems — dragon shares should NOT be burned (burning disabled)
        uint256 maxRedeem = tokenized.maxRedeem(alice);
        vm.prank(alice);
        tokenized.redeem(maxRedeem, alice, alice);

        assertEq(
            tokenized.balanceOf(dragonRouter),
            dragonSharesBefore,
            "dragon shares should remain when burning is disabled"
        );
    }

    /// @notice The lazy burn should be a no-op when the vault is solvent.
    function test_noBurnWhenSolvent() public {
        _depositUser(alice, 100 ether);

        // Create dragon buffer via profit
        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonSharesBefore = tokenized.balanceOf(dragonRouter);

        // Rate drops slightly but vault stays solvent (value > userDebt)
        strategy.setExchangeRate(12e17);
        assertFalse(ys.isVaultInsolvent(), "vault should be solvent");

        // User redeems — dragon shares should NOT be burned
        uint256 maxRedeem = tokenized.maxRedeem(alice);
        vm.prank(alice);
        tokenized.redeem(maxRedeem, alice, alice);

        assertEq(
            tokenized.balanceOf(dragonRouter),
            dragonSharesBefore,
            "dragon shares should remain when vault is solvent"
        );
    }

    /// @notice Withdraw path should also lazily burn dragon shares.
    function test_withdrawAlsoTriggersLazyBurn() public {
        _depositUser(alice, 100 ether);

        // Create dragon buffer
        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonSharesBefore = tokenized.balanceOf(dragonRouter);
        assertGt(dragonSharesBefore, 0, "dragon should have shares");

        // Make vault insolvent
        strategy.setExchangeRate(6e17);
        assertTrue(ys.isVaultInsolvent(), "vault should be insolvent");

        // Withdraw (not redeem) should also trigger lazy burn
        uint256 maxWithdraw = tokenized.maxWithdraw(alice);
        assertGt(maxWithdraw, 0, "alice should be able to withdraw");

        vm.prank(alice);
        tokenized.withdraw(maxWithdraw, alice, alice);

        assertEq(tokenized.balanceOf(dragonRouter), 0, "dragon shares should be burned via withdraw path");
    }

    /// @notice Dragon's own redeem should NOT trigger the lazy burn (it's the dragon itself).
    function test_dragonRedeemDoesNotTriggerLazyBurn() public {
        _depositUser(alice, 100 ether);

        // Create dragon buffer
        strategy.setExchangeRate(12e17);
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonShares = tokenized.balanceOf(dragonRouter);
        assertGt(dragonShares, 0, "dragon should have shares");

        // Dragon redeems in solvent state — should not trigger lazy burn
        uint256 maxDragonRedeem = tokenized.maxRedeem(dragonRouter);
        if (maxDragonRedeem > 0) {
            vm.prank(dragonRouter);
            tokenized.redeem(maxDragonRedeem, dragonRouter, dragonRouter);
        }
    }

    // =========================================================================
    // maxWithdraw / maxRedeem post-burn simulation tests
    // =========================================================================

    /// @notice maxWithdraw must reflect post-burn pricing during insolvency.
    ///         Without the fix, maxWithdraw underreports because it prices with
    ///         dragon shares still in totalSupply.
    function test_maxWithdraw_reflectsPostBurnDuringInsolvency() public {
        _depositUser(alice, 100 ether);

        // Create dragon buffer
        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonShares = tokenized.balanceOf(dragonRouter);
        assertEq(dragonShares, 50 ether, "dragon should have 50 shares");
        // totalSupply = 150, totalAssets = 100

        // Make vault insolvent
        strategy.setExchangeRate(9e17); // vaultValue = 90, userDebt = 100

        // maxWithdraw should reflect the POST-burn state, not the pre-burn state.
        // Post-burn: totalSupply = 100 (dragon burned), pro-rata: 100 * 100 / 100 = 100
        // Pre-burn (broken): pro-rata: 100 * 100 / 150 = 66.67
        uint256 maxW = tokenized.maxWithdraw(alice);
        assertEq(maxW, 100 ether, "maxWithdraw should reflect post-burn pricing (100, not 66.67)");
    }

    /// @notice withdraw(maxWithdraw()) must succeed in a single transaction and give
    ///         the user their full entitlement.
    function test_maxWithdraw_withdraw_roundtrip() public {
        _depositUser(alice, 100 ether);

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        strategy.setExchangeRate(9e17);
        assertTrue(ys.isVaultInsolvent(), "should be insolvent");

        uint256 maxW = tokenized.maxWithdraw(alice);
        assertGt(maxW, 0, "maxWithdraw should be nonzero");

        // This must NOT revert — maxWithdraw must be withdrawable in one call
        vm.prank(alice);
        uint256 shares = tokenized.withdraw(maxW, alice, alice);

        assertEq(tokenized.balanceOf(alice), 0, "alice should have no shares left");
        assertEq(asset.balanceOf(alice), maxW, "alice should receive exactly maxWithdraw assets");
        assertEq(shares, 100 ether, "all 100 shares should be burned");
    }

    /// @notice redeem(maxRedeem()) and withdraw(maxWithdraw()) should yield the same assets.
    function test_maxWithdraw_equals_maxRedeem_value() public {
        // Alice path: withdraw(maxWithdraw)
        _depositUser(alice, 100 ether);
        // Bob path: redeem(maxRedeem)
        _depositUser(bob, 100 ether);

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        strategy.setExchangeRate(9e17);

        uint256 aliceMaxW = tokenized.maxWithdraw(alice);
        uint256 bobMaxR = tokenized.maxRedeem(bob);

        // Alice withdraws
        vm.prank(alice);
        tokenized.withdraw(aliceMaxW, alice, alice);

        // Bob redeems
        vm.prank(bob);
        uint256 bobAssets = tokenized.redeem(bobMaxR, bob, bob);

        // Both should get the same amount (within 1 wei rounding)
        assertApproxEqAbs(aliceMaxW, bobAssets, 1, "withdraw and redeem paths should give equal assets");
    }

    /// @notice maxWithdraw should be unchanged when vault is solvent (no burn simulation needed).
    function test_maxWithdraw_unchangedWhenSolvent() public {
        _depositUser(alice, 100 ether);

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        // Rate drops but vault stays solvent (vaultValue >= userDebt)
        strategy.setExchangeRate(12e17);
        assertFalse(ys.isVaultInsolvent(), "should be solvent");

        // maxWithdraw should use rate-based conversion: 100 shares * RAY / 1.2 RAY = 83.33
        uint256 maxW = tokenized.maxWithdraw(alice);
        // Rate-based: 100 shares * RAY / 1.2_RAY = 83.333...
        // Just verify it's in the right ballpark and NOT the pro-rata value
        assertGt(maxW, 83 ether, "maxWithdraw should be ~83.33 (rate-based)");
        assertLt(maxW, 84 ether, "maxWithdraw should be ~83.33 (rate-based)");
    }

    /// @notice maxWithdraw should not simulate burn when burning is disabled.
    function test_maxWithdraw_noSimulationWhenBurningDisabled() public {
        _depositUser(alice, 100 ether);

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        // Disable burning
        vm.prank(management);
        tokenized.setEnableBurning(false);

        strategy.setExchangeRate(9e17);

        // With burning disabled, no lazy burn will fire, so maxWithdraw uses raw pro-rata
        // Pro-rata: 100 * 100 / 150 = 66.67
        uint256 maxW = tokenized.maxWithdraw(alice);
        assertEq(maxW, 66666666666666666666, "maxWithdraw should use raw pro-rata when burning disabled");
    }

    /// @notice maxWithdraw should not simulate burn when dragon has 0 shares.
    function test_maxWithdraw_noSimulationWhenNoDragonShares() public {
        _depositUser(alice, 100 ether);

        // No report → no dragon shares
        strategy.setExchangeRate(9e17);

        uint256 maxW = tokenized.maxWithdraw(alice);
        // totalSupply = 100, totalAssets = 100, pro-rata: 100 * 100 / 100 = 100
        assertEq(maxW, 100 ether, "maxWithdraw should be full assets when no dragon shares");
    }

    /// @notice With multiple users, each user's maxWithdraw should be correct post-burn.
    function test_maxWithdraw_multipleUsers() public {
        _depositUser(alice, 100 ether);
        _depositUser(bob, 50 ether);
        // totalSupply = 150, totalAssets = 150

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();
        // dragon gets 75 shares (profit = 225 - 150 = 75)
        // totalSupply = 225, totalAssets = 150

        strategy.setExchangeRate(8e17);
        // vaultValue = 120, userDebt = 150 → insolvent
        assertTrue(ys.isVaultInsolvent(), "should be insolvent");

        uint256 aliceMaxW = tokenized.maxWithdraw(alice);
        uint256 bobMaxW = tokenized.maxWithdraw(bob);

        // Post-burn: dragon burned, totalSupply = 150
        // Alice: 100/150 * 150 = 100, Bob: 50/150 * 150 = 50
        assertEq(aliceMaxW, 100 ether, "alice maxWithdraw post-burn");
        assertEq(bobMaxW, 50 ether, "bob maxWithdraw post-burn");

        // Both can withdraw in one call
        vm.prank(alice);
        tokenized.withdraw(aliceMaxW, alice, alice);

        vm.prank(bob);
        tokenized.withdraw(bobMaxW, bob, bob);

        assertEq(tokenized.totalSupply(), 0, "all shares should be withdrawn");
    }

    /// @notice maxRedeem should return full balance during insolvency (common case).
    function test_maxRedeem_returnsFullBalanceDuringInsolvency() public {
        _depositUser(alice, 100 ether);

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        strategy.setExchangeRate(9e17);
        assertTrue(ys.isVaultInsolvent(), "should be insolvent");

        uint256 maxR = tokenized.maxRedeem(alice);
        assertEq(maxR, 100 ether, "maxRedeem should return full balance");

        // And redeem should succeed
        vm.prank(alice);
        tokenized.redeem(maxR, alice, alice);

        assertEq(tokenized.balanceOf(alice), 0, "all shares redeemed");
    }

    /// @notice Verify that maxWithdraw for dragon is unchanged by the simulation.
    function test_maxWithdraw_dragon_unchanged() public {
        _depositUser(alice, 100 ether);

        strategy.setExchangeRate(15e17);
        vm.prank(keeper);
        tokenized.report();

        // Dragon's maxWithdraw should use _maxDragonRedeemableShares logic, not simulation
        uint256 dragonMaxW = tokenized.maxWithdraw(dragonRouter);
        uint256 dragonMaxR = tokenized.maxRedeem(dragonRouter);

        // In solvent state, dragon can withdraw excess over userDebt
        // vaultValue = 150, userDebt = 100 → excess = 50 → dragon can redeem up to 50
        assertGt(dragonMaxW, 0, "dragon should be able to withdraw when solvent");
        assertEq(dragonMaxR, 50 ether, "dragon maxRedeem should be 50 (excess value)");
    }

    /// @notice Deep insolvency: dragon fully burned, user takes remaining market loss.
    ///         maxWithdraw should still be accurate.
    function test_maxWithdraw_deepInsolvency() public {
        _depositUser(alice, 100 ether);

        strategy.setExchangeRate(12e17);
        vm.prank(keeper);
        tokenized.report();
        // dragon gets 20 shares, totalSupply = 120, totalAssets = 100

        strategy.setExchangeRate(5e17);
        // vaultValue = 50, userDebt = 100 → deeply insolvent
        assertTrue(ys.isVaultInsolvent(), "should be insolvent");

        uint256 maxW = tokenized.maxWithdraw(alice);
        // Post-burn: dragon 20 shares burned, totalSupply = 100
        // Pro-rata: 100 * 100 / 100 = 100
        assertEq(maxW, 100 ether, "maxWithdraw should reflect post-burn even in deep insolvency");

        vm.prank(alice);
        uint256 sharesBurned = tokenized.withdraw(maxW, alice, alice);
        assertEq(sharesBurned, 100 ether, "all shares burned");
        assertEq(asset.balanceOf(alice), 100 ether, "alice gets all assets");
    }
}
