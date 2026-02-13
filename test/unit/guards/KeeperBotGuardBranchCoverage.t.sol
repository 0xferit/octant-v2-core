// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { KeeperBotGuard } from "src/guards/KeeperBotGuard.sol";
import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

/// @notice Mock safe that always returns true for execTransactionFromModule
contract MockSafe {
    function execTransactionFromModule(
        address,
        uint256,
        bytes memory,
        Enum.Operation
    ) external pure returns (bool success) {
        return true;
    }
}

/// @notice Mock safe that always returns false for execTransactionFromModule
contract MockFailingSafe {
    function execTransactionFromModule(
        address,
        uint256,
        bytes memory,
        Enum.Operation
    ) external pure returns (bool success) {
        return false;
    }
}

/// @notice Mock strategy that does NOT implement doHealthCheck (no IBaseHealthCheck)
contract MockNoHealthCheckStrategy {
    function report() external pure returns (uint256, uint256) {
        return (0, 0);
    }
}

/// @notice Mock strategy that implements doHealthCheck returning false
contract MockHealthCheckDisabledStrategy {
    function doHealthCheck() external pure returns (bool) {
        return false;
    }

    function report() external pure returns (uint256, uint256) {
        return (0, 0);
    }
}

/// @title KeeperBotGuard Branch Coverage Tests
/// @notice Covers untested branches in KeeperBotGuard (constructor, health check paths)
contract KeeperBotGuardBranchCoverageTest is Test {
    address owner = address(this);
    address bot = address(0x10);

    // --- Constructor with zero safe address ---

    function test_constructor_zeroSafe_reverts() public {
        vm.expectRevert(KeeperBotGuard.KeeperBotGuard__InvalidSafe.selector);
        new KeeperBotGuard(owner, address(0));
    }

    // --- setBotAuthorizationBatch onlyOwner ---

    function test_setBotAuthorizationBatch_notOwner_reverts() public {
        MockSafe safe = new MockSafe();
        KeeperBotGuard guard = new KeeperBotGuard(owner, address(safe));

        address[] memory bots = new address[](1);
        bots[0] = bot;
        bool[] memory authorized = new bool[](1);
        authorized[0] = true;

        vm.prank(bot);
        vm.expectRevert();
        guard.setBotAuthorizationBatch(bots, authorized);
    }

    // --- callStrategyReport with strategy that doesn't implement doHealthCheck ---

    function test_callStrategyReport_noHealthCheck_succeeds() public {
        MockSafe safe = new MockSafe();
        KeeperBotGuard guard = new KeeperBotGuard(owner, address(safe));

        guard.setBotAuthorization(bot, true);

        MockNoHealthCheckStrategy strategy = new MockNoHealthCheckStrategy();

        // Should succeed - the try/catch in doHealthCheck() catches the revert
        vm.prank(bot);
        guard.callStrategyReport(address(strategy));
    }

    // --- callStrategyReport with strategy where doHealthCheck returns false ---

    function test_callStrategyReport_healthCheckDisabled_succeeds() public {
        MockSafe safe = new MockSafe();
        KeeperBotGuard guard = new KeeperBotGuard(owner, address(safe));

        guard.setBotAuthorization(bot, true);

        MockHealthCheckDisabledStrategy strategy = new MockHealthCheckDisabledStrategy();

        // Should succeed - healthCheckActive is false so no disable call is made
        vm.prank(bot);
        guard.callStrategyReport(address(strategy));
    }

    // --- callStrategyReport when safe returns false ---

    function test_callStrategyReport_safeFails_reverts() public {
        MockFailingSafe safe = new MockFailingSafe();
        KeeperBotGuard guard = new KeeperBotGuard(owner, address(safe));

        guard.setBotAuthorization(bot, true);

        MockNoHealthCheckStrategy strategy = new MockNoHealthCheckStrategy();

        vm.prank(bot);
        vm.expectRevert(KeeperBotGuard.KeeperBotGuard__ModuleTransactionFailed.selector);
        guard.callStrategyReport(address(strategy));
    }

    // --- isBotAuthorized view ---

    function test_isBotAuthorized_returnsCorrectly() public {
        MockSafe safe = new MockSafe();
        KeeperBotGuard guard = new KeeperBotGuard(owner, address(safe));

        assertFalse(guard.isBotAuthorized(bot));

        guard.setBotAuthorization(bot, true);
        assertTrue(guard.isBotAuthorized(bot));

        guard.setBotAuthorization(bot, false);
        assertFalse(guard.isBotAuthorized(bot));
    }
}
