// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Setup, IMockStrategy } from "./utils/Setup.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";
import { MockStrategySkimming } from "test/mocks/core/tokenized-strategies/MockStrategySkimming.sol";

/// @notice `finalizeDragonRouterChange` previously evaluated solvency
///         on the OLD state (before debt migration). That misclassified both
///         directions:
///           - Migrations that would RESTORE solvency (new dragon holds user shares
///             whose conversion to dragon debt drops user debt below vault value)
///             were blocked because the old state was insolvent.
///           - Migrations that would CAUSE insolvency (old dragon balance becoming
///             user debt pushes user debt above vault value) were allowed because
///             the old state was solvent.
///         The fix runs the solvency check after debt migration so the post-state
///         drives the decision.
contract YieldSkimmingDragonRouterMigrationSolvencyTest is Setup {
    address internal alice;
    address internal bob;
    address internal charlie;

    uint256 internal constant DEPOSIT = 100e18;
    uint256 internal constant DUST_SHARES = 1;

    function setUp() public override {
        super.setUp();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // Issue 29's check only fires when burning is enabled — mirror the existing
        // suite's pattern of enabling it before exercising migration logic.
        vm.prank(management);
        strategy.setEnableBurning(true);
    }

    /// @notice Migration that would RESTORE solvency must succeed under the fix.
    ///         Pre-fix code reverts with "Dragon cannot operate during insolvency"
    ///         because the pre-migration state is still insolvent; post-fix code
    ///         executes the migration first, which moves new-dragon shares from
    ///         user debt to dragon debt and drops user debt back below vault value.
    function test_finalize_succeedsWhenMigrationRestoresSolvency() public {
        // 1. Alice deposits at rate 1.0 → userDebt = 100, totalAssets = 100
        mintAndDepositIntoStrategy(strategy, alice, DEPOSIT);

        // 2. Rate climbs to 1.5; bob deposits 200 → bob shares = 200 * 1.5 = 300,
        //    userDebt = 100 + 300 = 400, totalAssets = 300.
        MockStrategySkimming(address(strategy)).updateExchangeRate(15e17);
        mintAndDepositIntoStrategy(strategy, bob, 200e18);

        // 3. Report at rate 1.5 mints profit shares to old dragon (donationAddress).
        //    currentValue = 300 * 1.5 = 450, totalDebt = 400, profit = 50.
        vm.prank(keeper);
        strategy.report();
        uint256 oldDragonShares = strategy.balanceOf(donationAddress);
        assertGt(oldDragonShares, 0, "old dragon must hold shares for the bug to trigger");

        // 4. Pending migration to bob (who currently holds 300 user shares).
        vm.prank(management);
        strategy.setDragonRouter(bob);
        skip(14 days);

        // 5. Rate drops to 0.6 → vault value = 300 * 0.6 = 180.
        //    userDebt = 400 (still > 180) → vault tracked-insolvent.
        MockStrategySkimming(address(strategy)).updateExchangeRate(6e17);
        assertTrue(
            IYieldSkimmingStrategy(address(strategy)).isVaultInsolvent(),
            "vault must be insolvent in the pre-migration state"
        );

        // 6. Post-fix: migration runs first.
        //      userDebt = 400 + oldDragonShares - 300  (≈ 150 once oldDragonShares ≈ 50)
        //    vault value 180 > userDebt → solvent → migration succeeds.
        //    Pre-fix this call would revert with "Dragon cannot operate during insolvency".
        strategy.finalizeDragonRouterChange();

        assertEq(strategy.dragonRouter(), bob, "router migrated");
        assertFalse(
            IYieldSkimmingStrategy(address(strategy)).isVaultInsolvent(),
            "post-migration state must be solvent"
        );
    }

    /// @notice Migration that would CAUSE insolvency must revert under the fix.
    ///         Pre-fix code lets it through because the pre-migration state is solvent,
    ///         leaving the vault permanently undercollateralised after finalize. The
    ///         fix evaluates the post-migration state and rejects the change.
    function test_finalize_revertsWhenMigrationWouldCauseInsolvency() public {
        // 1. Alice deposits at rate 1.0 → userDebt = 100, totalAssets = 100
        mintAndDepositIntoStrategy(strategy, alice, DEPOSIT);

        // 2. Profit cycle: rate to 2.0 → currentValue = 200, profit = 100, dragon
        //    receives 100 shares, dragonDebt = 100. totalSupply = 200.
        MockStrategySkimming(address(strategy)).updateExchangeRate(2e18);
        vm.prank(keeper);
        strategy.report();
        uint256 oldDragonShares = strategy.balanceOf(donationAddress);
        assertGt(oldDragonShares, 0, "dragon must hold shares for migration to convert");

        // 3. Migrate to charlie (fresh address with no shares).
        vm.prank(management);
        strategy.setDragonRouter(charlie);
        skip(14 days);

        // 4. Rate dips to 1.4 → vault value = 100 * 1.4 = 140.
        //    Pre-migration: userDebt = 100 < 140 → SOLVENT. Pre-fix would let migration through.
        //    Post-migration: userDebt = 100 + oldDragonShares ≈ 200 > 140 → INSOLVENT.
        MockStrategySkimming(address(strategy)).updateExchangeRate(14e17);
        assertFalse(
            IYieldSkimmingStrategy(address(strategy)).isVaultInsolvent(),
            "pre-migration state should still be solvent (the bug)"
        );

        // 5. Post-fix: revert because the migration would push user debt above vault value.
        vm.expectRevert("Router change would cause insolvency");
        strategy.finalizeDragonRouterChange();

        // Assert no state mutation happened (router unchanged, pending preserved).
        assertEq(strategy.dragonRouter(), donationAddress, "router unchanged on revert");
        assertEq(strategy.pendingDragonRouter(), charlie, "pending preserved on revert");
    }

    /// @notice Bailsec #25: a dust transfer to the old dragon must not leave
    ///         stale junior shares behind to affect migration. When burning is
    ///         enabled and the vault is insolvent, finalize first applies the
    ///         same lazy dragon burn used by user exits, then snapshots balances.
    function test_finalize_burnsOldDragonDustBeforeMigrationWhenBurningEnabled() public {
        // Alice and Bob deposit at rate 1.0. Bob will become the new dragon.
        mintAndDepositIntoStrategy(strategy, alice, DEPOSIT);
        mintAndDepositIntoStrategy(strategy, bob, 50e18);

        vm.prank(management);
        strategy.setDragonRouter(bob);
        skip(14 days);

        // Rate drops: pre-migration user debt is 150, vault value is 120, so
        // the vault is insolvent. Migrating Bob's 50 shares to dragon debt
        // restores user-debt coverage.
        MockStrategySkimming(address(strategy)).updateExchangeRate(8e17);
        assertTrue(IYieldSkimmingStrategy(address(strategy)).isVaultInsolvent(), "pre-migration insolvent");

        vm.prank(alice);
        strategy.transfer(donationAddress, DUST_SHARES);

        assertEq(strategy.balanceOf(donationAddress), DUST_SHARES, "old dragon has attacker dust");
        assertEq(
            IYieldSkimmingStrategy(address(strategy)).getDragonRouterDebtInAssetValue(),
            DUST_SHARES,
            "dust was classified as dragon debt"
        );

        strategy.finalizeDragonRouterChange();

        assertEq(strategy.dragonRouter(), bob, "router migrated");
        assertEq(strategy.balanceOf(donationAddress), 0, "old dragon dust was burned before migration");
        assertEq(
            IYieldSkimmingStrategy(address(strategy)).gettotalDebtOwedToUserInAssetValue(),
            DEPOSIT - DUST_SHARES,
            "burned dust is not reclassified back into user debt"
        );
        assertFalse(IYieldSkimmingStrategy(address(strategy)).isVaultInsolvent(), "post-migration solvent");
    }

    /// @notice The issue #25 burn is gated by `enableBurning`. With burning
    ///         disabled, finalize preserves the old dragon balance and follows
    ///         the existing unrestricted dragon-operation policy.
    function test_finalize_doesNotBurnOldDragonDustWhenBurningDisabled() public {
        vm.prank(management);
        strategy.setEnableBurning(false);

        mintAndDepositIntoStrategy(strategy, alice, DEPOSIT);
        mintAndDepositIntoStrategy(strategy, bob, 50e18);

        vm.prank(management);
        strategy.setDragonRouter(bob);
        skip(14 days);

        MockStrategySkimming(address(strategy)).updateExchangeRate(8e17);

        vm.prank(alice);
        strategy.transfer(donationAddress, DUST_SHARES);

        strategy.finalizeDragonRouterChange();

        assertEq(strategy.dragonRouter(), bob, "router migrated");
        assertEq(strategy.balanceOf(donationAddress), DUST_SHARES, "old dragon dust is preserved");
    }
}
