// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { AccessMode } from "src/constants.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AllocationMechanismFactoryTest is Test {
    AllocationMechanismFactory public factory;
    ERC20Mock public token;
    AddressSet public allowset;
    AddressSet public blockset;

    address public deployer = makeAddr("deployer");
    address public anotherDeployer = makeAddr("anotherDeployer");

    uint256 constant VOTING_DELAY = 1;
    uint256 constant VOTING_PERIOD = 100;
    uint256 constant QUORUM_SHARES = 10_000e18;
    uint256 constant TIMELOCK_DELAY = 50;
    uint256 constant GRACE_PERIOD = 100;
    uint256 constant ALPHA_NUMERATOR = 10_000;
    uint256 constant ALPHA_DENOMINATOR = 10_000;

    function setUp() public {
        factory = new AllocationMechanismFactory();
        token = new ERC20Mock();
        allowset = new AddressSet();
        blockset = new AddressSet();
    }

    function _baseConfig() internal view returns (AllocationConfig memory) {
        return AllocationConfig({
            asset: IERC20(address(token)),
            name: "Octant QF",
            symbol: "OQF",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_SHARES,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            owner: address(0) // factory overwrites this with msg.sender
        });
    }

    // ============================================
    // 1. predictOctantQFMechanismAddress matches deployOctantQFMechanism
    // ============================================

    function test_predictAddressMatchesDeployedAddress() public {
        AllocationConfig memory config = _baseConfig();

        address predicted = factory.predictOctantQFMechanismAddress(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE,
            deployer
        );

        vm.prank(deployer);
        address deployed = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        assertEq(predicted, deployed);
    }

    function test_predictAddressMatchesDeployedAddress_allowsetMode() public {
        AllocationConfig memory config = _baseConfig();

        address predicted = factory.predictOctantQFMechanismAddress(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET,
            deployer
        );

        vm.prank(deployer);
        address deployed = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        assertEq(predicted, deployed);
    }

    // ============================================
    // 2. Duplicate deployment reverts with MechanismAlreadyExists
    // ============================================

    function test_duplicateDeploymentReverts() public {
        AllocationConfig memory config = _baseConfig();

        address predicted = factory.predictOctantQFMechanismAddress(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE,
            deployer
        );

        vm.startPrank(deployer);
        factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        vm.expectRevert(abi.encodeWithSelector(AllocationMechanismFactory.MechanismAlreadyExists.selector, predicted));
        factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );
        vm.stopPrank();
    }

    // ============================================
    // 3. Registry tracking (deployedMechanisms / isMechanism)
    // ============================================

    function test_registryTracking_singleDeployment() public {
        AllocationConfig memory config = _baseConfig();

        assertEq(factory.getDeployedCount(), 0);

        vm.prank(deployer);
        address mechanism = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        assertEq(factory.getDeployedCount(), 1);
        assertTrue(factory.isMechanism(mechanism));
        assertEq(factory.deployedMechanisms(0), mechanism);
        assertFalse(factory.isMechanism(address(0xdead)));
    }

    function test_registryTracking_multipleDeployments() public {
        AllocationConfig memory config1 = _baseConfig();
        AllocationConfig memory config2 = AllocationConfig({
            asset: IERC20(address(token)),
            name: "Octant QF 2",
            symbol: "OQF2",
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            quorumShares: QUORUM_SHARES,
            timelockDelay: TIMELOCK_DELAY,
            gracePeriod: GRACE_PERIOD,
            owner: address(0)
        });

        vm.prank(deployer);
        address mechanism1 = factory.deployOctantQFMechanism(
            config1,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        vm.prank(deployer);
        address mechanism2 = factory.deployOctantQFMechanism(
            config2,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        assertEq(factory.getDeployedCount(), 2);
        assertTrue(factory.isMechanism(mechanism1));
        assertTrue(factory.isMechanism(mechanism2));
        assertEq(factory.deployedMechanisms(0), mechanism1);
        assertEq(factory.deployedMechanisms(1), mechanism2);
    }

    // ============================================
    // 4. Constructor param passthrough
    // ============================================

    function test_ownerIsSetToDeployer() public {
        AllocationConfig memory config = _baseConfig();

        vm.prank(deployer);
        address mechanism = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        assertEq(TokenizedAllocationMechanism(mechanism).owner(), deployer);
    }

    function test_ownerIsSetToDeployer_differentDeployers() public {
        AllocationConfig memory config = _baseConfig();

        vm.prank(deployer);
        address mechanism1 = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        vm.prank(anotherDeployer);
        address mechanism2 = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        assertNotEq(mechanism1, mechanism2);
        assertEq(TokenizedAllocationMechanism(mechanism1).owner(), deployer);
        assertEq(TokenizedAllocationMechanism(mechanism2).owner(), anotherDeployer);
    }

    function test_allowsetPassthrough() public {
        AllocationConfig memory config = _baseConfig();

        vm.prank(deployer);
        address mechanism = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        assertEq(address(OctantQFMechanism(payable(mechanism)).contributionAllowset()), address(allowset));
    }

    function test_blocksetPassthrough() public {
        AllocationConfig memory config = _baseConfig();

        vm.prank(deployer);
        address mechanism = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.BLOCKSET
        );

        assertEq(address(OctantQFMechanism(payable(mechanism)).contributionBlockset()), address(blockset));
    }

    function test_accessModePassthrough_none() public {
        AllocationConfig memory config = _baseConfig();

        vm.prank(deployer);
        address mechanism = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.NONE
        );

        assertEq(uint8(OctantQFMechanism(payable(mechanism)).contributionAccessMode()), uint8(AccessMode.NONE));
    }

    function test_accessModePassthrough_allowset() public {
        AllocationConfig memory config = _baseConfig();

        vm.prank(deployer);
        address mechanism = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        assertEq(uint8(OctantQFMechanism(payable(mechanism)).contributionAccessMode()), uint8(AccessMode.ALLOWSET));
    }

    function test_accessModePassthrough_blockset() public {
        AllocationConfig memory config = _baseConfig();

        vm.prank(deployer);
        address mechanism = factory.deployOctantQFMechanism(
            config,
            ALPHA_NUMERATOR,
            ALPHA_DENOMINATOR,
            IAddressSet(address(0)),
            IAddressSet(address(blockset)),
            AccessMode.BLOCKSET
        );

        assertEq(uint8(OctantQFMechanism(payable(mechanism)).contributionAccessMode()), uint8(AccessMode.BLOCKSET));
    }
}
