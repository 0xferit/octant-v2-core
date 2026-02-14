// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { RegenEarningPowerCalculatorFactory } from "src/factories/RegenEarningPowerCalculatorFactory.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { AccessMode } from "src/constants.sol";

contract RegenEarningPowerCalculatorFactoryTest is Test {
    RegenEarningPowerCalculatorFactory public factory;

    address public owner;
    address public deployer1;
    address public deployer2;

    IAddressSet public allowset;
    IAddressSet public blockset;

    event CalculatorDeployed(address indexed deployer, address indexed calculator, address indexed owner, bytes32 salt);

    function setUp() public {
        factory = new RegenEarningPowerCalculatorFactory();
        owner = makeAddr("owner");
        deployer1 = makeAddr("deployer1");
        deployer2 = makeAddr("deployer2");

        allowset = IAddressSet(address(new AddressSet()));
        blockset = IAddressSet(address(new AddressSet()));
    }

    // --- deploy tests ---

    function test_Deploy_CreatesCalculator() public {
        bytes32 salt = keccak256("SALT_1");

        vm.prank(deployer1);
        address calc = factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        assertTrue(calc != address(0), "Calculator address should not be zero");
        assertTrue(calc.code.length > 0, "Calculator should have code");
    }

    function test_Deploy_TransfersOwnership() public {
        bytes32 salt = keccak256("SALT_2");

        vm.prank(deployer1);
        address calc = factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        assertEq(RegenEarningPowerCalculator(calc).owner(), owner, "Owner should be transferred to specified owner");
    }

    function test_Deploy_RecordsDeployment() public {
        bytes32 salt = keccak256("SALT_3");

        vm.prank(deployer1);
        address calc = factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        RegenEarningPowerCalculatorFactory.CalculatorInfo[] memory infos = factory.getCalculatorsByDeployer(deployer1);
        assertEq(infos.length, 1, "Should have one deployment recorded");
        assertEq(infos[0].deployerAddress, deployer1, "Deployer should be recorded");
        assertEq(infos[0].owner, owner, "Owner should be recorded");
        assertEq(infos[0].calculatorAddress, calc, "Calculator address should be recorded");
        assertEq(infos[0].salt, salt, "Salt should be recorded");
        assertTrue(infos[0].timestamp > 0, "Timestamp should be set");
    }

    function test_Deploy_EmitsEvent() public {
        bytes32 salt = keccak256("SALT_4");

        address predicted = factory.predictAddress(
            salt,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        vm.prank(deployer1);
        vm.expectEmit(true, true, true, true);
        emit CalculatorDeployed(deployer1, predicted, owner, salt);
        factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);
    }

    function test_Deploy_MultipleDeployments() public {
        bytes32 salt1 = keccak256("SALT_A");
        bytes32 salt2 = keccak256("SALT_B");

        vm.startPrank(deployer1);
        address calc1 = factory.deploy(salt1, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);
        address calc2 = factory.deploy(salt2, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);
        vm.stopPrank();

        assertTrue(calc1 != calc2, "Different salts should produce different addresses");

        RegenEarningPowerCalculatorFactory.CalculatorInfo[] memory infos = factory.getCalculatorsByDeployer(deployer1);
        assertEq(infos.length, 2, "Should have two deployments recorded");
    }

    function test_Deploy_DifferentOwnersSameSalt() public {
        bytes32 salt = keccak256("SHARED_SALT");
        address owner2 = makeAddr("owner2");

        vm.prank(deployer1);
        address calc1 = factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        vm.prank(deployer1);
        address calc2 = factory.deploy(salt, owner2, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        assertTrue(calc1 != calc2, "Different owners should produce different addresses");
    }

    // --- predictAddress tests ---

    function test_PredictAddress_MatchesDeploy() public {
        bytes32 salt = keccak256("PREDICT_SALT");

        address predicted = factory.predictAddress(
            salt,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        vm.prank(deployer1);
        address actual = factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        assertEq(predicted, actual, "Predicted address should match deployed address");
    }

    function test_PredictAddress_DifferentSalts() public view {
        bytes32 salt1 = keccak256("SALT_X");
        bytes32 salt2 = keccak256("SALT_Y");

        address predicted1 = factory.predictAddress(
            salt1,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        address predicted2 = factory.predictAddress(
            salt2,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        assertTrue(predicted1 != predicted2, "Different salts should predict different addresses");
    }

    function test_PredictAddress_DifferentOwners() public view {
        bytes32 salt = keccak256("SAME_SALT");
        address owner2 = address(0x9999);

        address predicted1 = factory.predictAddress(
            salt,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        address predicted2 = factory.predictAddress(
            salt,
            owner2,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        assertTrue(predicted1 != predicted2, "Different owners should predict different addresses");
    }

    function test_PredictAddress_Deterministic() public view {
        bytes32 salt = keccak256("DET_SALT");

        address predicted1 = factory.predictAddress(
            salt,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        address predicted2 = factory.predictAddress(
            salt,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        assertEq(predicted1, predicted2, "Same inputs should always predict the same address");
    }

    // --- getCalculatorsByDeployer tests ---

    function test_GetCalculatorsByDeployer_EmptyInitially() public view {
        RegenEarningPowerCalculatorFactory.CalculatorInfo[] memory infos = factory.getCalculatorsByDeployer(deployer1);
        assertEq(infos.length, 0, "Should be empty initially");
    }

    function test_GetCalculatorsByDeployer_ReturnsCorrectData() public {
        bytes32 salt1 = keccak256("GET_SALT_1");
        bytes32 salt2 = keccak256("GET_SALT_2");
        address owner2 = makeAddr("owner2");

        vm.startPrank(deployer1);
        address calc1 = factory.deploy(salt1, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);
        address calc2 = factory.deploy(
            salt2,
            owner2,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        vm.stopPrank();

        RegenEarningPowerCalculatorFactory.CalculatorInfo[] memory infos = factory.getCalculatorsByDeployer(deployer1);
        assertEq(infos.length, 2, "Should have two entries");

        assertEq(infos[0].calculatorAddress, calc1);
        assertEq(infos[0].owner, owner);
        assertEq(infos[0].salt, salt1);

        assertEq(infos[1].calculatorAddress, calc2);
        assertEq(infos[1].owner, owner2);
        assertEq(infos[1].salt, salt2);
    }

    function test_GetCalculatorsByDeployer_IndependentPerDeployer() public {
        bytes32 salt = keccak256("INDEPENDENT_SALT");
        address owner2 = makeAddr("owner2");

        vm.prank(deployer1);
        factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        vm.prank(deployer2);
        factory.deploy(salt, owner2, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        RegenEarningPowerCalculatorFactory.CalculatorInfo[] memory infos1 = factory.getCalculatorsByDeployer(deployer1);
        RegenEarningPowerCalculatorFactory.CalculatorInfo[] memory infos2 = factory.getCalculatorsByDeployer(deployer2);

        assertEq(infos1.length, 1, "Deployer1 should have one entry");
        assertEq(infos2.length, 1, "Deployer2 should have one entry");
        assertEq(infos1[0].deployerAddress, deployer1);
        assertEq(infos2[0].deployerAddress, deployer2);
    }

    // --- calculators mapping public accessor ---

    function test_Calculators_PublicAccessor() public {
        bytes32 salt = keccak256("ACCESSOR_SALT");

        vm.prank(deployer1);
        address calc = factory.deploy(salt, owner, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        (address deployerAddress, uint256 timestamp, address infoOwner, address infoCalc, bytes32 infoSalt) = factory
            .calculators(deployer1, 0);

        assertEq(deployerAddress, deployer1);
        assertTrue(timestamp > 0);
        assertEq(infoOwner, owner);
        assertEq(infoCalc, calc);
        assertEq(infoSalt, salt);
    }

    // --- Deployed calculator is functional ---

    function test_Deploy_FunctionalCalculator_NoneModeFullPower() public {
        bytes32 salt = keccak256("FUNCTIONAL_NONE");

        vm.prank(deployer1);
        address calcAddr = factory.deploy(
            salt,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        RegenEarningPowerCalculator calc = RegenEarningPowerCalculator(calcAddr);
        address user = makeAddr("user");
        uint256 stakeAmount = 1000e18;

        assertTrue(calc.accessMode() == AccessMode.NONE, "Access mode should be NONE");
        assertEq(address(calc.allowset()), address(0), "Allowset should be zero");
        assertEq(address(calc.blockset()), address(0), "Blockset should be zero");

        uint256 ep = calc.getEarningPower(stakeAmount, user, user);
        assertEq(ep, stakeAmount, "Earning power should equal staked amount in NONE mode");
    }

    function test_Deploy_FunctionalCalculator_AllowsetMode() public {
        bytes32 salt = keccak256("FUNCTIONAL_ALLOWSET");

        vm.prank(deployer1);
        address calcAddr = factory.deploy(salt, owner, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

        RegenEarningPowerCalculator calc = RegenEarningPowerCalculator(calcAddr);
        address user = makeAddr("user");
        uint256 stakeAmount = 500e18;

        // User not in allowset -> zero earning power
        uint256 epBefore = calc.getEarningPower(stakeAmount, user, user);
        assertEq(epBefore, 0, "Earning power should be 0 when not in allowset");

        // Add user to allowset
        AddressSet(address(allowset)).add(user);

        // User in allowset -> full earning power
        uint256 epAfter = calc.getEarningPower(stakeAmount, user, user);
        assertEq(epAfter, stakeAmount, "Earning power should equal stake when in allowset");
    }

    function test_Deploy_FunctionalCalculator_GetNewEarningPower() public {
        bytes32 salt = keccak256("FUNCTIONAL_BUMP");

        vm.prank(deployer1);
        address calcAddr = factory.deploy(
            salt,
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        RegenEarningPowerCalculator calc = RegenEarningPowerCalculator(calcAddr);
        address user = makeAddr("user");
        uint256 stakeAmount = 1000e18;

        // old < new -> qualifies for bump
        (uint256 newEP, bool qualifies) = calc.getNewEarningPower(stakeAmount, user, user, 500e18);
        assertEq(newEP, stakeAmount, "New earning power mismatch");
        assertTrue(qualifies, "Should qualify for bump when EP changed");

        // old == new -> no bump
        (uint256 sameEP, bool noBump) = calc.getNewEarningPower(stakeAmount, user, user, stakeAmount);
        assertEq(sameEP, stakeAmount, "Same earning power mismatch");
        assertFalse(noBump, "Should not qualify for bump when EP unchanged");
    }
}
