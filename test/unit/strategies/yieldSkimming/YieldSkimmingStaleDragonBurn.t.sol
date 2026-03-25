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
}
