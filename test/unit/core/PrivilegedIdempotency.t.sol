// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { Privileged } from "src/core/Privileged.sol";

/// @notice Thin harness that exposes Privileged internals for testing.
contract PrivilegedHarness is Privileged {
    function setPrivileged(address _account, bool _status) external {
        _setPrivileged(_account, _status);
    }

    function setPrivilegedBatch(address[] calldata _accounts, bool _status) external {
        _setPrivilegedBatch(_accounts, _status);
    }
}

/// @notice Regression suite for `_setPrivileged` idempotency: neither `_setPrivileged`
///         nor `_setPrivilegedBatch` may emit `PrivilegedUpdated` (or SSTORE) when the
///         stored flag already matches the requested value.
contract PrivilegedIdempotencyTest is Test {
    PrivilegedHarness internal harness;

    bytes32 internal constant PRIVILEGED_UPDATED_SIG = keccak256("PrivilegedUpdated(address,bool)");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        harness = new PrivilegedHarness();
    }

    function _countPrivilegedUpdatedLogs(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == PRIVILEGED_UPDATED_SIG) {
                count++;
            }
        }
    }

    function test_setPrivileged_emitsOnFalseToTrue() public {
        assertFalse(harness.isPrivileged(alice), "alice starts non-privileged");

        vm.recordLogs();
        harness.setPrivileged(alice, true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countPrivilegedUpdatedLogs(logs), 1, "exactly one event on real change");
        assertTrue(harness.isPrivileged(alice), "alice now privileged");
    }

    function test_setPrivileged_emitsOnTrueToFalse() public {
        harness.setPrivileged(alice, true);

        vm.recordLogs();
        harness.setPrivileged(alice, false);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countPrivilegedUpdatedLogs(logs), 1, "exactly one event on real revocation");
        assertFalse(harness.isPrivileged(alice), "alice revoked");
    }

    function test_setPrivileged_skipsNoOpWhenAlreadyTrue() public {
        harness.setPrivileged(alice, true);

        vm.recordLogs();
        harness.setPrivileged(alice, true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countPrivilegedUpdatedLogs(logs), 0, "no event on no-op");
        assertTrue(harness.isPrivileged(alice), "state unchanged");
    }

    function test_setPrivileged_skipsNoOpWhenAlreadyFalse() public {
        // alice has never been set, so the mapping default is false.
        vm.recordLogs();
        harness.setPrivileged(alice, false);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countPrivilegedUpdatedLogs(logs), 0, "no event when setting default value");
        assertFalse(harness.isPrivileged(alice), "state unchanged");
    }

    function test_setPrivilegedBatch_emitsOnlyForRealChanges() public {
        // Pre-set alice and bob to true; carol stays at default (false).
        harness.setPrivileged(alice, true);
        harness.setPrivileged(bob, true);

        address[] memory batch = new address[](3);
        batch[0] = alice; // already true, no-op
        batch[1] = bob; // already true, no-op
        batch[2] = carol; // false -> true, real change

        vm.recordLogs();
        harness.setPrivilegedBatch(batch, true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countPrivilegedUpdatedLogs(logs), 1, "only carol emits");
        assertTrue(harness.isPrivileged(alice), "alice still privileged");
        assertTrue(harness.isPrivileged(bob), "bob still privileged");
        assertTrue(harness.isPrivileged(carol), "carol now privileged");
    }

    function test_setPrivilegedBatch_allNoOpsEmitNothing() public {
        // Default state: all three accounts are false. Setting them to false again is a no-op batch.
        address[] memory batch = new address[](3);
        batch[0] = alice;
        batch[1] = bob;
        batch[2] = carol;

        vm.recordLogs();
        harness.setPrivilegedBatch(batch, false);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countPrivilegedUpdatedLogs(logs), 0, "no events when every entry matches");
    }

    function test_setPrivilegedBatch_emitsOnlyOnceForRevokedSubset() public {
        harness.setPrivileged(alice, true);
        harness.setPrivileged(carol, true);
        // bob stays false.

        address[] memory batch = new address[](3);
        batch[0] = alice; // true -> false, real change
        batch[1] = bob; // false -> false, no-op
        batch[2] = carol; // true -> false, real change

        vm.recordLogs();
        harness.setPrivilegedBatch(batch, false);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countPrivilegedUpdatedLogs(logs), 2, "emits for alice and carol only");
        assertFalse(harness.isPrivileged(alice), "alice revoked");
        assertFalse(harness.isPrivileged(bob), "bob unchanged");
        assertFalse(harness.isPrivileged(carol), "carol revoked");
    }
}
