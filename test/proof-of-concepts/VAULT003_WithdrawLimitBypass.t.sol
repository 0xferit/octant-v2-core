// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MultistrategyVault } from "src/core/MultistrategyVault.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockYieldStrategy } from "test/mocks/zodiac-core/MockYieldStrategy.sol";

contract QueueSensitiveWithdrawLimitModule {
    address public blockedStrategy;

    constructor(address _blockedStrategy) {
        blockedStrategy = _blockedStrategy;
    }

    function availableWithdrawLimit(address, uint256, address[] calldata strategies) external view returns (uint256) {
        if (strategies.length == 1 && strategies[0] == blockedStrategy) {
            return 0;
        }
        return type(uint256).max;
    }
}

contract VAULT003_WithdrawLimitBypass is Test {
    MultistrategyVault vault;
    MultistrategyVaultFactory vaultFactory;
    MultistrategyVault vaultImplementation;
    MockERC20 asset;

    address gov;
    address user;

    function setUp() public {
        gov = address(this);
        user = address(0xBEEF);

        asset = new MockERC20(18);

        vaultImplementation = new MultistrategyVault();
        vaultFactory = new MultistrategyVaultFactory("Test Vault", address(vaultImplementation), gov);
        vault = MultistrategyVault(vaultFactory.deployNewVault(address(asset), "Test Vault", "tvTEST", gov, 7 days));

        vault.add_role(gov, IMultistrategyVault.Roles.ADD_STRATEGY_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.DEBT_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.MAX_DEBT_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.DEPOSIT_LIMIT_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.QUEUE_MANAGER);
        vault.add_role(gov, IMultistrategyVault.Roles.WITHDRAW_LIMIT_MANAGER);

        vault.set_deposit_limit(type(uint256).max, false);
    }

    function test_withdrawLimitModule_UsesDefaultQueueForEmptyParam() public {
        uint256 amount = 1e18;

        // Arrange: user deposits and strategy is in default queue
        userDeposit(user, amount);

        MockYieldStrategy strategy = new MockYieldStrategy(address(asset), address(vault));
        vault.add_strategy(address(strategy), true);
        addDebtToStrategy(address(strategy), amount);

        vault.set_use_default_queue(true);

        QueueSensitiveWithdrawLimitModule limitModule = new QueueSensitiveWithdrawLimitModule(address(strategy));
        vault.set_withdraw_limit_module(address(limitModule));

        address[] memory defaultQueue = new address[](1);
        defaultQueue[0] = address(strategy);

        // Act + Assert: both explicit and empty queues are blocked by the module
        vm.prank(user);
        vm.expectRevert(IMultistrategyVault.ExceedWithdrawLimit.selector);
        vault.withdraw(amount, user, user, 0, defaultQueue);

        vm.prank(user);
        vm.expectRevert(IMultistrategyVault.ExceedWithdrawLimit.selector);
        vault.withdraw(amount, user, user, 0, new address[](0));
    }

    function userDeposit(address depositor, uint256 amount) internal {
        asset.mint(depositor, amount);
        vm.startPrank(depositor);
        asset.approve(address(vault), amount);
        vault.deposit(amount, depositor);
        vm.stopPrank();
    }

    function addDebtToStrategy(address strategyAddress, uint256 amount) internal {
        vault.update_max_debt_for_strategy(strategyAddress, type(uint256).max);
        vault.update_debt(strategyAddress, amount, 0);
    }
}
