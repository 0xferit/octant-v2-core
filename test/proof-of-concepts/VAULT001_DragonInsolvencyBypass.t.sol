// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { Setup } from "test/unit/strategies/yieldSkimming/utils/Setup.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";
import { MockStrategySkimming } from "test/mocks/core/tokenized-strategies/MockStrategySkimming.sol";

/**
 * @title VAULT001 Dragon Router Insolvency Bypass (Regression Test)
 * @notice Ensures finalizeDragonRouterChange() cannot be used to bypass insolvency checks.
 */
contract VAULT001_DragonInsolvencyBypass is Setup {
    function test_finalizeDragonRouterChange_RevertsWhenInsolventAndOldDragonHasShares() external {
        address alice = makeAddr("alice");
        address newDragon = makeAddr("newDragon");

        // Arrange: user deposit and profit, dragon accrues shares
        uint256 depositAmount = 100e18;
        mintAndDepositIntoStrategy(strategy, alice, depositAmount);

        MockStrategySkimming(address(strategy)).updateExchangeRate(15e17);
        vm.prank(keeper);
        strategy.report();
        uint256 dragonShares = strategy.balanceOf(donationAddress);
        assertGt(dragonShares, 0, "dragon should have shares");

        vm.prank(management);
        strategy.setDragonRouter(newDragon);

        // Arrange: crash and report to mark insolvent
        MockStrategySkimming(address(strategy)).updateExchangeRate(6e17);
        vm.prank(keeper);
        strategy.report();
        assertTrue(IYieldSkimmingStrategy(address(strategy)).isVaultInsolvent(), "vault should be insolvent");

        // Act + Assert: finalize should revert while old dragon holds shares
        vm.warp(block.timestamp + 14 days + 1);
        vm.expectRevert("Dragon cannot operate during insolvency");
        strategy.finalizeDragonRouterChange();
    }
}
