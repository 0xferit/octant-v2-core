// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";
import { AddressSet } from "src/utils/AddressSet.sol";

contract AddressSetFactoryTest is Test {
    AddressSetFactory public factory;

    address public owner;
    address public deployer1;
    address public deployer2;

    event AddressSetDeployed(address indexed deployer, address indexed addressSet, address indexed owner, bytes32 salt);

    function setUp() public {
        factory = new AddressSetFactory();
        owner = makeAddr("owner");
        deployer1 = makeAddr("deployer1");
        deployer2 = makeAddr("deployer2");
    }

    // --- deploy tests ---

    function test_Deploy_CreatesAddressSet() public {
        bytes32 salt = keccak256("SALT_1");

        vm.prank(deployer1);
        address addressSet = factory.deploy(salt, owner);

        assertTrue(addressSet != address(0), "AddressSet address should not be zero");
        assertTrue(addressSet.code.length > 0, "AddressSet should have code");
    }

    function test_Deploy_TransfersOwnership() public {
        bytes32 salt = keccak256("SALT_2");

        vm.prank(deployer1);
        address addressSet = factory.deploy(salt, owner);

        assertEq(AddressSet(addressSet).owner(), owner, "Owner should be transferred to specified owner");
    }

    function test_Deploy_RecordsDeployment() public {
        bytes32 salt = keccak256("SALT_3");

        vm.prank(deployer1);
        address addressSet = factory.deploy(salt, owner);

        AddressSetFactory.AddressSetInfo[] memory infos = factory.getAddressSetsByDeployer(deployer1);
        assertEq(infos.length, 1, "Should have one deployment recorded");
        assertEq(infos[0].deployerAddress, deployer1, "Deployer should be recorded");
        assertEq(infos[0].owner, owner, "Owner should be recorded");
        assertEq(infos[0].addressSet, addressSet, "AddressSet address should be recorded");
        assertEq(infos[0].salt, salt, "Salt should be recorded");
        assertTrue(infos[0].timestamp > 0, "Timestamp should be set");
    }

    function test_Deploy_EmitsEvent() public {
        bytes32 salt = keccak256("SALT_4");

        // Predict the address first
        address predicted = factory.predictAddress(salt, owner);

        vm.prank(deployer1);
        vm.expectEmit(true, true, true, true);
        emit AddressSetDeployed(deployer1, predicted, owner, salt);
        factory.deploy(salt, owner);
    }

    function test_Deploy_MultipleDeployments() public {
        bytes32 salt1 = keccak256("SALT_A");
        bytes32 salt2 = keccak256("SALT_B");

        vm.startPrank(deployer1);
        address set1 = factory.deploy(salt1, owner);
        address set2 = factory.deploy(salt2, owner);
        vm.stopPrank();

        assertTrue(set1 != set2, "Different salts should produce different addresses");

        AddressSetFactory.AddressSetInfo[] memory infos = factory.getAddressSetsByDeployer(deployer1);
        assertEq(infos.length, 2, "Should have two deployments recorded");
    }

    function test_Deploy_DifferentDeployersSameSalt() public {
        bytes32 salt = keccak256("SHARED_SALT");

        vm.prank(deployer1);
        factory.deploy(salt, owner);

        vm.prank(deployer2);
        vm.expectRevert();
        factory.deploy(salt, owner);
    }

    function test_Deploy_DifferentOwnersSameSalt() public {
        bytes32 salt = keccak256("SHARED_SALT");
        address owner2 = makeAddr("owner2");

        vm.prank(deployer1);
        address set1 = factory.deploy(salt, owner);

        vm.prank(deployer1);
        address set2 = factory.deploy(salt, owner2);

        assertTrue(set1 != set2, "Different owners should produce different addresses");
    }

    // --- predictAddress tests ---

    function test_PredictAddress_MatchesDeploy() public {
        bytes32 salt = keccak256("PREDICT_SALT");

        address predicted = factory.predictAddress(salt, owner);

        vm.prank(deployer1);
        address actual = factory.deploy(salt, owner);

        assertEq(predicted, actual, "Predicted address should match deployed address");
    }

    function test_PredictAddress_DifferentSalts() public view {
        bytes32 salt1 = keccak256("SALT_X");
        bytes32 salt2 = keccak256("SALT_Y");

        address predicted1 = factory.predictAddress(salt1, owner);
        address predicted2 = factory.predictAddress(salt2, owner);

        assertTrue(predicted1 != predicted2, "Different salts should predict different addresses");
    }

    function test_PredictAddress_DifferentOwners() public view {
        bytes32 salt = keccak256("SAME_SALT");
        address owner2 = address(0x9999);

        address predicted1 = factory.predictAddress(salt, owner);
        address predicted2 = factory.predictAddress(salt, owner2);

        assertTrue(predicted1 != predicted2, "Different owners should predict different addresses");
    }

    function test_PredictAddress_Deterministic() public view {
        bytes32 salt = keccak256("DET_SALT");

        address predicted1 = factory.predictAddress(salt, owner);
        address predicted2 = factory.predictAddress(salt, owner);

        assertEq(predicted1, predicted2, "Same inputs should always predict the same address");
    }

    // --- getAddressSetsByDeployer tests ---

    function test_GetAddressSetsByDeployer_EmptyInitially() public view {
        AddressSetFactory.AddressSetInfo[] memory infos = factory.getAddressSetsByDeployer(deployer1);
        assertEq(infos.length, 0, "Should be empty initially");
    }

    function test_GetAddressSetsByDeployer_ReturnsCorrectData() public {
        bytes32 salt1 = keccak256("GET_SALT_1");
        bytes32 salt2 = keccak256("GET_SALT_2");
        address owner2 = makeAddr("owner2");

        vm.startPrank(deployer1);
        address set1 = factory.deploy(salt1, owner);
        address set2 = factory.deploy(salt2, owner2);
        vm.stopPrank();

        AddressSetFactory.AddressSetInfo[] memory infos = factory.getAddressSetsByDeployer(deployer1);
        assertEq(infos.length, 2, "Should have two entries");

        assertEq(infos[0].addressSet, set1);
        assertEq(infos[0].owner, owner);
        assertEq(infos[0].salt, salt1);

        assertEq(infos[1].addressSet, set2);
        assertEq(infos[1].owner, owner2);
        assertEq(infos[1].salt, salt2);
    }

    function test_GetAddressSetsByDeployer_IndependentPerDeployer() public {
        bytes32 salt = keccak256("INDEPENDENT_SALT");
        address owner2 = makeAddr("owner2");

        vm.prank(deployer1);
        factory.deploy(salt, owner);

        vm.prank(deployer2);
        factory.deploy(salt, owner2);

        AddressSetFactory.AddressSetInfo[] memory infos1 = factory.getAddressSetsByDeployer(deployer1);
        AddressSetFactory.AddressSetInfo[] memory infos2 = factory.getAddressSetsByDeployer(deployer2);

        assertEq(infos1.length, 1, "Deployer1 should have one entry");
        assertEq(infos2.length, 1, "Deployer2 should have one entry");
        assertEq(infos1[0].deployerAddress, deployer1);
        assertEq(infos2[0].deployerAddress, deployer2);
    }

    // --- addressSets mapping public accessor ---

    function test_AddressSets_PublicAccessor() public {
        bytes32 salt = keccak256("ACCESSOR_SALT");

        vm.prank(deployer1);
        address addressSet = factory.deploy(salt, owner);

        (
            address deployerAddress,
            uint256 timestamp,
            address infoOwner,
            address infoAddressSet,
            bytes32 infoSalt
        ) = factory.addressSets(deployer1, 0);

        assertEq(deployerAddress, deployer1);
        assertTrue(timestamp > 0);
        assertEq(infoOwner, owner);
        assertEq(infoAddressSet, addressSet);
        assertEq(infoSalt, salt);
    }

    // --- Deployed AddressSet is functional ---

    function test_Deploy_FunctionalAddressSet() public {
        bytes32 salt = keccak256("FUNCTIONAL_SALT");

        vm.prank(deployer1);
        address addressSet = factory.deploy(salt, owner);

        AddressSet set = AddressSet(addressSet);
        address user = makeAddr("user");

        // Owner can add addresses
        vm.prank(owner);
        set.add(user);

        assertTrue(set.contains(user), "Should contain added address");
        assertEq(set.length(), 1, "Should have length 1");
    }
}
