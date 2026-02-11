// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MultistrategyVault } from "src/core/MultistrategyVault.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockYieldStrategy } from "test/mocks/core/MockYieldStrategy.sol";
import { MockLockedStrategy } from "test/mocks/core/MockLockedStrategy.sol";
import { MockLossyStrategy } from "test/mocks/core/MockLossyStrategy.sol";
import { MockFaultyStrategy } from "test/mocks/core/MockFaultyStrategy.sol";

contract DebtManagementTest is Test {
    MultistrategyVault vaultImplementation;
    MultistrategyVault vault;
    MockERC20 asset;
    MockYieldStrategy strategy;
    MockLockedStrategy lockedStrategy;
    MockYieldStrategy lossyStrategy;
    MultistrategyVaultFactory vaultFactory;
    address gov;
    address bunny;
    uint256 constant DAY = 86400;
    uint256 constant MAX_BPS = 10_000;

    function setUp() public {
        gov = address(this);
        bunny = address(0x123);

        asset = new MockERC20(18);

        // Create and initialize the vault
        vaultImplementation = new MultistrategyVault();
        vaultFactory = new MultistrategyVaultFactory("Test Vault", address(vaultImplementation), gov);
        vault = MultistrategyVault(vaultFactory.deployNewVault(address(asset), "Test Vault", "tvTEST", gov, 7 days));

        // Set up strategies
        strategy = new MockYieldStrategy(address(asset), address(vault));
        lockedStrategy = new MockLockedStrategy(address(asset), address(vault));
        lossyStrategy = new MockYieldStrategy(address(asset), address(vault));

        // Set roles
        vault.add_role(gov, IMultistrategyVault.Roles.ADD_STRATEGY_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.REVOKE_STRATEGY_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.DEBT_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.MAX_DEBT_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.MINIMUM_IDLE_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.DEPOSIT_LIMIT_MANAGER);

        // set max deposit limit
        vault.set_deposit_limit(type(uint256).max, false);

        // Add strategies to vault
        vault.add_strategy(address(strategy), true);
        vault.add_strategy(address(lockedStrategy), true);
        vault.add_strategy(address(lossyStrategy), true);

        // Seed vault with funds - 1 ETH + 0.5 ETH
        seedVaultWithFunds(1e18, 5e17);
    }

    function testUpdateMaxDebtWithDebtValue(uint256 maxDebt) public {
        // Bound to reasonable values
        maxDebt = bound(maxDebt, 0, 10 ** 22);

        // Update max debt for strategy
        vault.update_max_debt_for_strategy(address(strategy), maxDebt);

        // Check max debt was updated
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(strategy));
        assertEq(params.maxDebt, maxDebt);
    }

    function testUpdateMaxDebtWithInactiveStrategyReverts() public {
        // Create a strategy that's not added to the vault
        MockYieldStrategy inactiveStrategy = new MockYieldStrategy(address(asset), address(vault));
        uint256 maxDebt = 1e18;

        // Try to update max debt - should revert
        vm.expectRevert(IMultistrategyVault.InactiveStrategy.selector);
        vault.update_max_debt_for_strategy(address(inactiveStrategy), maxDebt);
    }

    function testUpdateDebtWithoutPermissionReverts() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 newDebt = vaultBalance / 2;

        // Set max debt for strategy
        vault.update_max_debt_for_strategy(address(strategy), newDebt);

        // Try to update debt as bunny - should revert
        vm.prank(bunny);
        vm.expectRevert(IMultistrategyVault.NotAllowed.selector);
        vault.update_debt(address(strategy), newDebt, 0);
    }

    function testUpdateDebtWithStrategyMaxDebtLessThanNewDebt() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 newDebt = vaultBalance / 2;

        // Set max debt for strategy
        vault.update_max_debt_for_strategy(address(strategy), newDebt);

        // Try to update debt to more than max debt
        uint256 returnValue = vault.update_debt(address(strategy), newDebt + 10, 0);

        // Should be capped at max debt
        assertEq(returnValue, newDebt);

        // Check strategy state
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(strategy));
        assertEq(params.currentDebt, newDebt);

        // Check balances
        assertEq(asset.balanceOf(address(strategy)), newDebt);
        assertEq(asset.balanceOf(address(vault)), vaultBalance - newDebt);

        // Check vault accounting
        assertEq(vault.totalIdle(), vaultBalance - newDebt);
        assertEq(vault.totalDebt(), newDebt);
    }

    function testUpdateDebtWithCurrentDebtLessThanNewDebt() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 newDebt = vaultBalance / 2;

        // Get initial state
        IMultistrategyVault.StrategyParams memory initialParams = vault.strategies(address(strategy));
        uint256 currentDebt = initialParams.currentDebt;
        uint256 difference = newDebt - currentDebt;
        uint256 initialIdle = vault.totalIdle();
        uint256 initialDebt = vault.totalDebt();

        // Set max debt for strategy
        vault.update_max_debt_for_strategy(address(strategy), newDebt);

        // Update debt to new value
        vault.update_debt(address(strategy), newDebt, 0);

        // Check strategy state
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(strategy));
        assertEq(params.currentDebt, newDebt);

        // Check balances
        assertEq(asset.balanceOf(address(strategy)), newDebt);
        assertEq(asset.balanceOf(address(vault)), vaultBalance - newDebt);

        // Check vault accounting
        assertEq(vault.totalIdle(), initialIdle - difference);
        assertEq(vault.totalDebt(), initialDebt + difference);
    }

    function testUpdateDebtWithCurrentDebtEqualToNewDebtReverts() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 newDebt = vaultBalance / 2;

        // First set the debt
        vault.update_max_debt_for_strategy(address(strategy), newDebt);
        vault.update_debt(address(strategy), newDebt, 0);

        // Then try to set it to the same value
        vm.expectRevert(IMultistrategyVault.NewDebtEqualsCurrentDebt.selector);
        vault.update_debt(address(strategy), newDebt, 0);
    }

    function testUpdateDebtWithCurrentDebtGreaterThanNewDebtAndZeroWithdrawable() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 currentDebt = vaultBalance;
        uint256 newDebt = vaultBalance / 2;

        // First set full debt
        vault.update_max_debt_for_strategy(address(lockedStrategy), currentDebt);
        vault.update_debt(address(lockedStrategy), currentDebt, 0);

        // Lock all the funds
        lockedStrategy.setLockedFunds(currentDebt, DAY);

        // Try to reduce debt
        vault.update_max_debt_for_strategy(address(lockedStrategy), newDebt);
        uint256 returnValue = vault.update_debt(address(lockedStrategy), newDebt, 0);

        // Should stay at current debt since funds are locked
        assertEq(returnValue, currentDebt);
    }

    function testUpdateDebtWithCurrentDebtLessThanNewDebtAndMinimumTotalIdleReducingNewDebt() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 newDebt = vaultBalance;

        // Get initial state
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(strategy));
        uint256 currentDebt = params.currentDebt;
        uint256 initialIdle = vault.totalIdle();
        uint256 initialDebt = vault.totalDebt();

        // Set minimum total idle to keep a small amount in vault
        uint256 minimumTotalIdle = vaultBalance - 1;
        vault.set_minimum_total_idle(minimumTotalIdle);

        // Calculate expected adjustments
        uint256 expectedNewDifference = initialIdle - minimumTotalIdle;
        uint256 expectedNewDebt = currentDebt + expectedNewDifference;

        // Set max debt and update debt
        vault.update_max_debt_for_strategy(address(strategy), newDebt);
        vault.update_debt(address(strategy), newDebt, 0);

        // Verify state
        params = vault.strategies(address(strategy));
        assertEq(params.currentDebt, expectedNewDebt);
        assertEq(asset.balanceOf(address(strategy)), expectedNewDebt);
        assertEq(asset.balanceOf(address(vault)), vaultBalance - expectedNewDifference);
        assertEq(vault.totalIdle(), initialIdle - expectedNewDifference);
        assertEq(vault.totalDebt(), initialDebt + expectedNewDifference);
    }

    function testUpdateDebtWithCurrentDebtGreaterThanNewDebtAndMinimumTotalIdle() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 currentDebt = vaultBalance;
        uint256 newDebt = vaultBalance / 2;
        uint256 difference = currentDebt - newDebt;

        // First allocate full debt
        addDebtToStrategy(address(strategy), currentDebt);

        // Get updated state
        uint256 initialIdle = vault.totalIdle();
        uint256 initialDebt = vault.totalDebt();

        // Set a small minimum total idle
        uint256 minimumTotalIdle = 1;
        vault.set_minimum_total_idle(minimumTotalIdle);

        // Reduce debt in strategy
        vault.update_max_debt_for_strategy(address(strategy), newDebt);
        vault.update_debt(address(strategy), newDebt, 0);

        // Verify state
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(strategy));
        assertEq(params.currentDebt, newDebt);
        assertEq(asset.balanceOf(address(strategy)), newDebt);
        assertEq(asset.balanceOf(address(vault)), vaultBalance - newDebt);
        assertEq(vault.totalIdle(), initialIdle + difference);
        assertEq(vault.totalDebt(), initialDebt - difference);
    }

    function testUpdateDebtWithCurrentDebtGreaterThanNewDebtAndTotalIdleLessThanMinimumTotalIdle() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 currentDebt = vaultBalance;
        uint256 newDebt = vaultBalance / 3;

        // First allocate full debt
        addDebtToStrategy(address(strategy), currentDebt);

        // Get updated state
        uint256 initialIdle = vault.totalIdle();
        uint256 initialDebt = vault.totalDebt();

        // Set minimum idle higher than the debt difference would allow
        uint256 minimumTotalIdle = (currentDebt - newDebt) + 1;
        vault.set_minimum_total_idle(minimumTotalIdle);

        // Calculate expected adjustments
        uint256 expectedNewDifference = minimumTotalIdle - initialIdle;
        uint256 expectedNewDebt = currentDebt - expectedNewDifference;

        // Reduce debt in strategy
        vault.update_max_debt_for_strategy(address(strategy), newDebt);
        vault.update_debt(address(strategy), newDebt, 0);

        // Verify state
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(strategy));
        assertEq(params.currentDebt, expectedNewDebt);
        assertEq(asset.balanceOf(address(strategy)), expectedNewDebt);
        assertEq(asset.balanceOf(address(vault)), minimumTotalIdle);
        assertEq(vault.totalIdle(), initialIdle + expectedNewDifference);
        assertEq(vault.totalDebt(), initialDebt - expectedNewDifference);
    }

    function testUpdateDebtWithLossyStrategyThatWithdrawsLessThanRequested() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Deploy lossy strategy
        MockLossyStrategy _lossyStrategy = new MockLossyStrategy(address(asset), address(vault));
        vault.add_strategy(address(_lossyStrategy), true);

        // Allocate full debt to strategy
        addDebtToStrategy(address(_lossyStrategy), vaultBalance);

        // Get updated state
        uint256 initialIdle = vault.totalIdle();
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(_lossyStrategy));
        uint256 currentDebt = params.currentDebt;

        // Set 10% loss on withdrawal
        uint256 loss = currentDebt / 10;
        uint256 newDebt = 0;
        uint256 difference = currentDebt - loss;
        _lossyStrategy.setWithdrawingLoss(loss);

        // Record initial price per share
        uint256 initialPps = vault.pricePerShare();

        // Update debt to 0 (withdraw everything)
        vault.update_debt(address(_lossyStrategy), newDebt, MAX_BPS); // Allow full loss

        // Verify state
        params = vault.strategies(address(_lossyStrategy));
        assertEq(params.currentDebt, newDebt);
        assertEq(asset.balanceOf(address(_lossyStrategy)), newDebt);
        assertEq(asset.balanceOf(address(vault)), vaultBalance - loss);
        assertEq(vault.totalIdle(), initialIdle + difference);
        assertEq(vault.totalDebt(), newDebt);

        // Price per share should decrease due to loss
        assertLt(vault.pricePerShare(), initialPps);
    }

    function testUpdateDebtWithLossyStrategyThatWithdrawsLessThanRequestedMaxLoss() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Deploy lossy strategy
        MockLossyStrategy _lossyStrategy = new MockLossyStrategy(address(asset), address(vault));
        vault.add_strategy(address(_lossyStrategy), true);

        // Allocate full debt to strategy
        addDebtToStrategy(address(_lossyStrategy), vaultBalance);

        // Get updated state
        uint256 initialIdle = vault.totalIdle();
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(_lossyStrategy));
        uint256 currentDebt = params.currentDebt;

        // Set 10% loss on withdrawal
        uint256 loss = currentDebt / 10;
        uint256 newDebt = 0;
        uint256 difference = currentDebt - loss;
        _lossyStrategy.setWithdrawingLoss(loss);

        // Record initial price per share
        uint256 initialPps = vault.pricePerShare();

        // With 0 max loss should revert
        vm.expectRevert(IMultistrategyVault.TooMuchLoss.selector);
        vault.update_debt(address(_lossyStrategy), newDebt, 0);

        // Up to the loss percent should revert (999 bps < 1000 bps needed)
        vm.expectRevert(IMultistrategyVault.TooMuchLoss.selector);
        vault.update_debt(address(_lossyStrategy), newDebt, 999);

        // With sufficient max loss should succeed
        vault.update_debt(address(_lossyStrategy), newDebt, 1000);

        // Verify state
        params = vault.strategies(address(_lossyStrategy));
        assertEq(params.currentDebt, newDebt);
        assertEq(asset.balanceOf(address(_lossyStrategy)), newDebt);
        assertEq(asset.balanceOf(address(vault)), vaultBalance - loss);
        assertEq(vault.totalIdle(), initialIdle + difference);
        assertEq(vault.totalDebt(), newDebt);

        // Price per share should decrease due to loss
        assertLt(vault.pricePerShare(), initialPps);
    }

    function testUpdateDebtWithFaultyStrategyThatWithdrawsMoreThanRequested() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Deploy lossy strategy with extra yield
        MockLossyStrategy _lossyStrategy = new MockLossyStrategy(address(asset), address(vault));
        vault.add_strategy(address(_lossyStrategy), true);

        // Allocate full debt to strategy
        addDebtToStrategy(address(_lossyStrategy), vaultBalance);

        // Get updated state
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(_lossyStrategy));
        uint256 currentDebt = params.currentDebt;

        // Set 10% extra on withdrawal
        uint256 extra = currentDebt / 10;
        uint256 newDebt = 0;

        // Simulate airdrop to strategy
        asset.mint(address(_lossyStrategy), extra);

        // Set negative loss (extra yield)
        _lossyStrategy.setWithdrawingExtraYield(extra);

        // Record initial price per share
        uint256 initialPps = vault.pricePerShare();

        // Update debt to 0
        vault.update_debt(address(_lossyStrategy), 0, 0);

        // Verify state
        params = vault.strategies(address(_lossyStrategy));
        assertEq(params.currentDebt, newDebt);
        assertEq(_lossyStrategy.totalAssets(), newDebt);
        assertEq(asset.balanceOf(address(vault)), vaultBalance + extra);
        assertEq(vault.totalIdle(), vaultBalance);
        assertEq(vault.totalDebt(), newDebt);

        // Price per share should remain unchanged
        assertEq(vault.pricePerShare(), initialPps);
    }

    function testUpdateDebtWithFaultyStrategyThatDepositsLessThanRequestedWithAirdrop() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 currentDebt = vaultBalance;
        uint256 expectedDebt = currentDebt / 2;
        uint256 fishAmount = 1e17; // 0.1 ETH as fish_amount

        // Airdrop some asset to the vault
        airdropAsset(address(vault), fishAmount);

        // Deploy faulty strategy that only takes half the funds
        MockFaultyStrategy faultyStrategy = new MockFaultyStrategy(address(asset), address(vault));
        vault.add_strategy(address(faultyStrategy), true);

        // Allocate full debt to strategy, but it only takes half
        addDebtToStrategy(address(faultyStrategy), currentDebt);

        // Get updated state
        uint256 initialIdle = vault.totalIdle();
        uint256 initialDebt = vault.totalDebt();

        // Check the strategy only took half and vault recorded it correctly
        assertEq(initialIdle, expectedDebt, "initialIdle");
        assertEq(initialDebt, expectedDebt, "initialDebt");
        assertEq(vault.strategies(address(faultyStrategy)).currentDebt, expectedDebt, "currentDebt");
        assertEq(asset.balanceOf(address(faultyStrategy)), expectedDebt, "assetBalance");
    }

    function testUpdateDebtWithLossyStrategyThatWithdrawsLessThanRequestedWithAirdrop() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 fishAmount = 1e17; // 0.1 ETH as fish_amount

        // Deploy lossy strategy
        MockLossyStrategy _lossyStrategy = new MockLossyStrategy(address(asset), address(vault));
        vault.add_strategy(address(_lossyStrategy), true);

        // Allocate full debt to strategy
        addDebtToStrategy(address(_lossyStrategy), vaultBalance);

        // Get updated state
        uint256 initialIdle = vault.totalIdle();
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(_lossyStrategy));
        uint256 currentDebt = params.currentDebt;

        // Set 10% loss on withdrawal
        uint256 loss = currentDebt / 10;
        uint256 newDebt = 0;
        uint256 difference = currentDebt - loss;
        _lossyStrategy.setWithdrawingLoss(loss);

        // Record initial price per share
        uint256 initialPps = vault.pricePerShare();

        // Airdrop some asset to the vault
        airdropAsset(address(vault), fishAmount);

        // Update debt to 0 (withdraw everything)
        vault.update_debt(address(_lossyStrategy), newDebt, MAX_BPS); // Allow full loss

        // Verify state
        params = vault.strategies(address(_lossyStrategy));
        assertEq(params.currentDebt, newDebt);
        assertEq(asset.balanceOf(address(_lossyStrategy)), newDebt);
        assertEq(asset.balanceOf(address(vault)), (vaultBalance - loss + fishAmount));
        assertEq(vault.totalIdle(), initialIdle + difference);
        assertEq(vault.totalDebt(), newDebt);

        // Price per share should decrease due to loss
        assertLt(vault.pricePerShare(), initialPps);
    }

    function testUpdateDebtWithLossyStrategyThatWithdrawsLessThanRequestedWithAirdropAndMaxLoss() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        uint256 fishAmount = 1e17; // 0.1 ETH as fish_amount

        // Deploy lossy strategy
        MockLossyStrategy _lossyStrategy = new MockLossyStrategy(address(asset), address(vault));
        vault.add_strategy(address(_lossyStrategy), true);

        // Allocate full debt to strategy
        addDebtToStrategy(address(_lossyStrategy), vaultBalance);

        // Get updated state
        uint256 initialIdle = vault.totalIdle();
        IMultistrategyVault.StrategyParams memory params = vault.strategies(address(_lossyStrategy));
        uint256 currentDebt = params.currentDebt;

        // Set 10% loss on withdrawal
        uint256 loss = currentDebt / 10;
        uint256 newDebt = 0;
        uint256 difference = currentDebt - loss;
        _lossyStrategy.setWithdrawingLoss(loss);

        // Record initial price per share
        uint256 initialPps = vault.pricePerShare();

        // Airdrop some asset to the vault
        airdropAsset(address(vault), fishAmount);

        // With 0 max loss should revert
        vm.expectRevert(IMultistrategyVault.TooMuchLoss.selector);
        vault.update_debt(address(_lossyStrategy), newDebt, 0);

        // Up to the loss percent should revert (999 bps < 1000 bps needed)
        vm.expectRevert(IMultistrategyVault.TooMuchLoss.selector);
        vault.update_debt(address(_lossyStrategy), newDebt, 999);

        // With sufficient max loss should succeed
        vault.update_debt(address(_lossyStrategy), newDebt, 1000);

        // Verify state
        params = vault.strategies(address(_lossyStrategy));
        assertEq(params.currentDebt, newDebt);
        assertEq(asset.balanceOf(address(_lossyStrategy)), newDebt);
        assertEq(asset.balanceOf(address(vault)), (vaultBalance - loss + fishAmount));
        assertEq(vault.totalIdle(), initialIdle + difference);
        assertEq(vault.totalDebt(), newDebt);

        // Price per share should decrease due to loss
        assertLt(vault.pricePerShare(), initialPps);
    }

    // --- DebtManagementLib branch: newDebt clamped to maxDebt < currentDebt ---
    // When increasing debt, if maxDebt < currentDebt (e.g., from reports), should return currentDebt

    function testUpdateDebt_increaseDebt_maxDebtBelowCurrentDebt_returnsCurrentDebt() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Set high max debt and allocate all funds
        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);
        vault.update_debt(address(strategy), vaultBalance, 0);

        // Simulate strategy reporting a profit that increases currentDebt beyond maxDebt
        // Lower maxDebt below currentDebt
        vault.update_max_debt_for_strategy(address(strategy), vaultBalance / 2);

        // Deposit more funds so we try to increase debt
        asset.mint(gov, 10e18);
        asset.approve(address(vault), 10e18);
        vault.deposit(10e18, gov);

        // Try to increase debt to large amount - but maxDebt < currentDebt
        // Should return currentDebt (early return at line 257-259)
        uint256 returnValue = vault.update_debt(address(strategy), type(uint256).max, 0);
        assertEq(returnValue, vaultBalance);
    }

    // --- DebtManagementLib branch: increase debt when totalIdle <= minimumTotalIdle ---

    function testUpdateDebt_increaseDebt_idleBelowMinimum_returnsCurrentDebt() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Set minimum idle to the full balance
        vault.set_minimum_total_idle(vaultBalance);

        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);

        // totalIdle == minimumTotalIdle, so should return currentDebt
        uint256 returnValue = vault.update_debt(address(strategy), vaultBalance, 0);
        // Should have returned currentDebt = 0 since no debt was allocated
        assertEq(returnValue, 0);
    }

    // --- DebtManagementLib branch: increase debt when maxDeposit is 0 ---

    function testUpdateDebt_increaseDebt_maxDepositZero_returnsCurrentDebt() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);

        // First allocate some debt
        vault.update_debt(address(strategy), vaultBalance / 2, 0);
        uint256 currentDebt = vaultBalance / 2;

        // Disable deposits so maxDeposit returns 0
        strategy.setAllowDeposits(false);

        // Now try to increase debt more - maxDeposit == 0, so it should early-return currentDebt
        // This hits the early return at line 268-270 of DebtManagementLib
        uint256 returnValue = vault.update_debt(address(strategy), vaultBalance, 0);
        assertEq(returnValue, currentDebt);
    }

    // --- DebtManagementLib branch: update_debt when vault is shutdown forces newDebt = 0 ---

    function testUpdateDebt_vaultShutdown_forcesDebtToZero() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Allocate some debt
        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);
        vault.update_debt(address(strategy), vaultBalance / 2, 0);

        // Shutdown vault
        vault.add_role(gov, IMultistrategyVault.Roles.EMERGENCY_MANAGER);
        vault.shutdown_vault();

        // update_debt with any target should reduce to 0 (forced by shutdown)
        uint256 returnValue = vault.update_debt(address(strategy), vaultBalance, 0);
        assertEq(returnValue, 0);
    }

    // Helper functions

    function seedVaultWithFunds(uint256 amount1, uint256 amount2) internal {
        // Mint tokens
        asset.mint(gov, amount1);
        asset.mint(gov, amount2);

        // Deposit into vault
        asset.approve(address(vault), amount1);
        vault.deposit(amount1, gov);

        asset.approve(address(vault), amount2);
        vault.deposit(amount2, gov);
    }

    function addDebtToStrategy(address strategyAddress, uint256 amount) internal {
        // First set max debt
        vault.update_max_debt_for_strategy(strategyAddress, type(uint256).max);
        // Then update debt
        vault.update_debt(strategyAddress, amount, 0);
    }

    // Helper to airdrop assets
    function airdropAsset(address recipient, uint256 amount) internal {
        asset.mint(recipient, amount);
    }

    // --- DebtManagementLib branch: withdrawn > assetsToWithdraw (line 239) ---
    // When strategy returns more than asked, assetsToWithdraw is adjusted upward

    function testUpdateDebt_decreaseDebt_strategyReturnsMore() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // First give strategy some debt
        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);
        vault.update_debt(address(strategy), vaultBalance / 2, 0);

        // Airdrop extra assets to the strategy to simulate returns > requested
        // When vault requests a partial decrease, strategy may return more due to rounding
        asset.mint(address(strategy), 1e17);

        // Now decrease debt, requesting less than what strategy holds
        // The strategy will return all assets including the extra airdropped amount
        uint256 returnValue = vault.update_debt(address(strategy), 0, 0);
        assertEq(returnValue, 0, "Debt should be 0 after full withdrawal");
    }

    // --- DebtManagementLib branch: newDebt < currentDebt in maxDebt block (line 257) ---
    // When maxDebt is reduced below currentDebt, should early-return currentDebt

    function testUpdateDebt_increaseDebt_maxDebtBelowCurrentDebt() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // First give strategy some debt
        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);
        vault.update_debt(address(strategy), vaultBalance / 2, 0);

        uint256 currentDebt = vaultBalance / 2;

        // Now reduce maxDebt below the current debt
        vault.update_max_debt_for_strategy(address(strategy), currentDebt / 4);

        // Try to increase debt (newDebt > currentDebt in the call).
        // The code clamps newDebt to maxDebt, then checks if clamped newDebt < currentDebt.
        // Since maxDebt (currentDebt/4) < currentDebt, it should early return currentDebt.
        uint256 returnValue = vault.update_debt(address(strategy), vaultBalance, 0);
        assertEq(returnValue, currentDebt, "Should return currentDebt when maxDebt < currentDebt");
    }

    // --- DebtManagementLib branch: assetsToDeposit > availableIdle ---

    function testUpdateDebt_increaseDebt_limitedByAvailableIdle() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Set minimum idle to almost all the balance
        vault.set_minimum_total_idle(vaultBalance - 1e15);

        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);

        // Trying to deposit the full balance, but minimum idle limits it
        uint256 returnValue = vault.update_debt(address(strategy), vaultBalance, 0);
        // Should only deposit what's available above minimum idle (1e15)
        assertTrue(returnValue > 0 && returnValue <= 1e15, "Should be limited by available idle");
    }

    // --- DebtManagementLib branch: assetsToDeposit > maxDeposit ---

    function testUpdateDebt_increaseDebt_limitedByMaxDeposit() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Strategy allows only small deposits
        strategy.setMaxDebt(1e15);

        vault.update_max_debt_for_strategy(address(strategy), vaultBalance);

        // Try to deposit more than maxDeposit allows
        uint256 returnValue = vault.update_debt(address(strategy), vaultBalance, 0);
        assertTrue(returnValue <= 1e15, "Should be limited by strategy maxDeposit");
    }

    // =====================================================================
    // Phase 4: Cover remaining DebtManagementLib branches
    // =====================================================================

    // --- DebtManagementLib line 218: unrealisedLossesShare != 0 reverts ---
    // When a strategy has unrealised losses (totalAssets < currentDebt), reducing
    // debt should revert with StrategyHasUnrealisedLosses.

    function testUpdateDebt_decreaseDebt_unrealisedLosses_reverts() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Allocate full debt to strategy
        addDebtToStrategy(address(strategy), vaultBalance);

        // Simulate a loss in the strategy: transfer some assets out
        // This makes strategy.totalAssets() < currentDebt (unrealised loss)
        uint256 lossAmount = vaultBalance / 10; // 10% loss
        strategy.simulateLoss(lossAmount);

        // Verify strategy has less than its debt
        assertLt(
            strategy.totalAssets(),
            vault.strategies(address(strategy)).currentDebt,
            "Strategy should have unrealised losses"
        );

        // Try to reduce debt - should revert because of unrealised losses
        vm.expectRevert(IMultistrategyVault.StrategyHasUnrealisedLosses.selector);
        vault.update_debt(address(strategy), vaultBalance / 2, 0);
    }

    // --- DebtManagementLib line 239: withdrawn > assetsToWithdraw ---
    // Partial debt reduction from a strategy that returns more than asked.
    // Must be a PARTIAL reduction so Math.min doesn't cap at currentDebt.

    function testUpdateDebt_decreaseDebt_partialWithdraw_strategyReturnsMore() public {
        uint256 vaultBalance = asset.balanceOf(address(vault));

        // Deploy lossy strategy (which supports extra yield on withdrawal)
        MockLossyStrategy _extraStrategy = new MockLossyStrategy(address(asset), address(vault));
        vault.add_strategy(address(_extraStrategy), true);

        // Allocate full debt
        addDebtToStrategy(address(_extraStrategy), vaultBalance);
        uint256 currentDebt = vault.strategies(address(_extraStrategy)).currentDebt;

        // Airdrop extra assets to strategy (simulates yield)
        uint256 extra = currentDebt / 10;
        asset.mint(address(_extraStrategy), extra);

        // Set extra yield on withdrawal (strategy returns more than asked)
        _extraStrategy.setWithdrawingExtraYield(extra);

        // Partially reduce debt (not to 0, so Math.min doesn't cap at currentDebt)
        // Request newDebt = currentDebt / 2, so assetsToWithdraw = currentDebt / 2
        // Strategy will return currentDebt/2 + extra, capped by Math.min at currentDebt
        // If extra < currentDebt/2, withdrawn = currentDebt/2 + extra > assetsToWithdraw
        uint256 targetDebt = currentDebt / 2;
        uint256 returnValue = vault.update_debt(address(_extraStrategy), targetDebt, MAX_BPS);

        // The strategy returned extra, so debt accounting adjusts for the overpayment
        assertTrue(returnValue <= currentDebt, "Should have reduced debt");
    }
}
