// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { YieldForwarderFactory } from "src/factories/YieldForwarderFactory.sol";
import { YieldForwarder } from "src/core/YieldForwarder.sol";

contract YieldForwarderFactoryTest is Test {
    YieldForwarderFactory public factory;

    address public receiver = address(0xBEEF);
    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        factory = new YieldForwarderFactory();

        vm.label(receiver, "Receiver");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
    }

    // ═══════════════════════════════════════════════════════════
    // CREATION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_createYieldForwarder_createsWithCorrectReceiver() public {
        bytes32 salt = keccak256("test-salt-v1");

        address forwarderAddr = factory.createYieldForwarder(receiver, salt);

        assertTrue(forwarderAddr != address(0));
        assertEq(YieldForwarder(forwarderAddr).receiver(), receiver);
    }

    function test_createYieldForwarder_create2PredictionMatchesActual() public {
        bytes32 salt = keccak256("predict-test-v1");

        address predicted = factory.computeYieldForwarderAddress(receiver, salt, address(this));
        address actual = factory.createYieldForwarder(receiver, salt);

        assertEq(actual, predicted, "CREATE2 prediction should match actual deployment");
    }

    function test_createYieldForwarder_duplicateReverts() public {
        bytes32 salt = keccak256("unique-salt");

        // First deployment succeeds
        factory.createYieldForwarder(receiver, salt);

        // Second deployment with same salt should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldForwarderFactory.ForwarderAlreadyExists.selector,
                factory.computeYieldForwarderAddress(receiver, salt, address(this))
            )
        );
        factory.createYieldForwarder(receiver, salt);
    }

    function test_createYieldForwarder_differentSaltsProduceDifferentAddresses() public {
        bytes32 salt1 = keccak256("salt-1");
        bytes32 salt2 = keccak256("salt-2");

        address addr1 = factory.createYieldForwarder(receiver, salt1);
        address addr2 = factory.createYieldForwarder(receiver, salt2);

        assertTrue(addr1 != addr2, "Different salts should produce different addresses");
    }

    function test_createYieldForwarder_differentDeployersProduceDifferentAddresses() public {
        bytes32 salt = keccak256("shared-salt");

        // Deploy from this contract
        address addr1 = factory.createYieldForwarder(receiver, salt);

        // Deploy from alice with same salt and receiver
        vm.prank(alice);
        address addr2 = factory.createYieldForwarder(receiver, salt);

        assertTrue(addr1 != addr2, "Different deployers should get different addresses");
    }

    // ═══════════════════════════════════════════════════════════
    // TRACKING TESTS
    // ═══════════════════════════════════════════════════════════

    function test_getForwardersByDeployer_returnsCorrectData() public {
        bytes32 salt1 = keccak256("track-1");
        bytes32 salt2 = keccak256("track-2");

        address receiver2 = address(0xDEAD);

        address addr1 = factory.createYieldForwarder(receiver, salt1);
        address addr2 = factory.createYieldForwarder(receiver2, salt2);

        YieldForwarderFactory.ForwarderInfo[] memory forwarders = factory.getForwardersByDeployer(address(this));

        assertEq(forwarders.length, 2, "Should have 2 forwarders");
        assertEq(forwarders[0].forwarderAddress, addr1);
        assertEq(forwarders[0].receiver, receiver);
        assertEq(forwarders[1].forwarderAddress, addr2);
        assertEq(forwarders[1].receiver, receiver2);
    }

    function test_getForwardersByDeployer_emptyForUnknownDeployer() public view {
        YieldForwarderFactory.ForwarderInfo[] memory forwarders = factory.getForwardersByDeployer(address(0xDEAD));
        assertEq(forwarders.length, 0);
    }

    // ═══════════════════════════════════════════════════════════
    // EVENT TESTS
    // ═══════════════════════════════════════════════════════════

    function test_createYieldForwarder_emitsEvent() public {
        bytes32 salt = keccak256("event-test-salt");
        address predicted = factory.computeYieldForwarderAddress(receiver, salt, address(this));

        vm.expectEmit(true, true, true, true);
        emit YieldForwarderFactory.YieldForwarderCreated(address(this), predicted, salt, receiver);

        factory.createYieldForwarder(receiver, salt);
    }

    // ═══════════════════════════════════════════════════════════
    // VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_createYieldForwarder_revertsOnZeroReceiver() public {
        bytes32 salt = keccak256("zero-receiver-test");

        // Should bubble up InvalidReceiver from YieldForwarder constructor
        vm.expectRevert();
        factory.createYieldForwarder(address(0), salt);
    }
}
