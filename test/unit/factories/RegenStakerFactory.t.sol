// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { AccessMode } from "src/constants.sol";
import { Test } from "forge-std/Test.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockEarningPowerCalculator } from "test/mocks/MockEarningPowerCalculator.sol";

contract RegenStakerFactoryTest is Test {
    RegenStakerFactory public factory;

    IERC20 public rewardsToken;
    IERC20Staking public stakeToken;
    IEarningPowerCalculator public earningPowerCalculator;

    address public admin;
    address public deployer1;
    address public deployer2;

    IAddressSet public stakerAllowset;
    IAddressSet public contributionAllowset;
    IAddressSet public allocationMechanismAllowset;

    uint256 public constant MAX_BUMP_TIP = 1000e18;
    uint256 public constant MAX_CLAIM_FEE = 500;
    uint256 public constant MINIMUM_STAKE_AMOUNT = 100e18;
    uint256 public constant REWARD_DURATION = 30 days;

    event StakerDeploy(
        address indexed deployer,
        address indexed admin,
        address indexed stakerAddress,
        bytes32 salt,
        RegenStakerFactory.RegenStakerVariant variant,
        address calculatorAddress
    );

    function setUp() public {
        admin = address(0x1);
        deployer1 = address(0x2);
        deployer2 = address(0x3);

        rewardsToken = new MockERC20(18);
        stakeToken = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        stakerAllowset = new AddressSet();
        contributionAllowset = new AddressSet();
        allocationMechanismAllowset = new AddressSet();

        // Deploy the factory with both variants' bytecode hashes (this test contract is the deployer)
        bytes32 regenStakerBytecodeHash = keccak256(type(RegenStaker).creationCode);
        bytes32 noDelegationBytecodeHash = keccak256(type(RegenStakerWithoutDelegateSurrogateVotes).creationCode);
        factory = new RegenStakerFactory(regenStakerBytecodeHash, noDelegationBytecodeHash);

        vm.label(address(factory), "RegenStakerFactory");
        vm.label(address(rewardsToken), "RewardsToken");
        vm.label(address(stakeToken), "StakeToken");
        vm.label(admin, "Admin");
        vm.label(deployer1, "Deployer1");
        vm.label(deployer2, "Deployer2");
    }

    function getRegenStakerBytecode() internal pure returns (bytes memory) {
        return type(RegenStaker).creationCode;
    }

    function testCreateStaker() public {
        bytes32 salt = keccak256("TEST_STAKER_SALT");

        // Build constructor params and bytecode for prediction
        bytes memory constructorParams = abi.encode(
            rewardsToken,
            stakeToken,
            earningPowerCalculator,
            MAX_BUMP_TIP,
            admin,
            REWARD_DURATION,
            MINIMUM_STAKE_AMOUNT,
            stakerAllowset,
            IAddressSet(address(0)), // stakerBlockset
            AccessMode.NONE,
            allocationMechanismAllowset
        );
        bytes memory bytecode = bytes.concat(getRegenStakerBytecode(), constructorParams);

        vm.startPrank(deployer1);
        address predictedAddress = factory.predictStakerAddress(salt, deployer1, bytecode);

        vm.expectEmit(true, true, true, true);
        emit StakerDeploy(
            deployer1,
            admin,
            predictedAddress,
            salt,
            RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION,
            address(earningPowerCalculator)
        );

        address stakerAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );
        vm.stopPrank();

        assertTrue(stakerAddress != address(0), "Staker address should not be zero");

        RegenStaker staker = RegenStaker(stakerAddress);
        assertEq(address(staker.REWARD_TOKEN()), address(rewardsToken), "Rewards token should be set correctly");
        assertEq(address(staker.STAKE_TOKEN()), address(stakeToken), "Stake token should be set correctly");
        assertEq(staker.minimumStakeAmount(), MINIMUM_STAKE_AMOUNT, "Minimum stake amount should be set correctly");
    }

    function testCreateMultipleStakers() public {
        bytes32 salt1 = keccak256("FIRST_STAKER_SALT");
        bytes32 salt2 = keccak256("SECOND_STAKER_SALT");

        vm.startPrank(deployer1);
        address firstStaker = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1,
            getRegenStakerBytecode()
        );

        address secondStaker = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP + 100,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT + 50e18,
                rewardDuration: REWARD_DURATION
            }),
            salt2,
            getRegenStakerBytecode()
        );
        vm.stopPrank();

        assertTrue(firstStaker != secondStaker, "Stakers should have different addresses");
    }

    function testCreateStakersForDifferentDeployers() public {
        bytes32 salt1 = keccak256("DEPLOYER1_SALT");
        bytes32 salt2 = keccak256("DEPLOYER2_SALT");

        vm.prank(deployer1);
        address staker1 = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1,
            getRegenStakerBytecode()
        );

        vm.prank(deployer2);
        address staker2 = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt2,
            getRegenStakerBytecode()
        );

        assertTrue(staker1 != staker2, "Stakers should have different addresses");
    }

    function testDeterministicAddressing() public {
        bytes32 salt = keccak256("DETERMINISTIC_SALT");

        // Build constructor params and bytecode for prediction
        bytes memory constructorParams = abi.encode(
            rewardsToken,
            stakeToken,
            earningPowerCalculator,
            MAX_BUMP_TIP,
            admin,
            REWARD_DURATION,
            MINIMUM_STAKE_AMOUNT,
            stakerAllowset,
            IAddressSet(address(0)), // stakerBlockset
            AccessMode.NONE,
            allocationMechanismAllowset
        );
        bytes memory bytecode = bytes.concat(getRegenStakerBytecode(), constructorParams);

        vm.prank(deployer1);
        address predictedAddress = factory.predictStakerAddress(salt, deployer1, bytecode);

        vm.prank(deployer1);
        address actualAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );

        assertEq(predictedAddress, actualAddress, "Predicted address should match actual address");
    }

    function testCreateStakerWithNullAllowsets() public {
        bytes32 salt = keccak256("NULL_ALLOWSET_SALT");

        vm.prank(deployer1);
        address stakerAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: IAddressSet(address(0)),
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );

        assertTrue(stakerAddress != address(0), "Staker should be created with null allowsets");

        RegenStaker staker = RegenStaker(stakerAddress);
        assertEq(
            address(staker.stakerAllowset()),
            address(0),
            "Staker allowset should be null when address(0) is passed"
        );
    }

    function testGetStakersByDeployer_EmptyInitially() public view {
        RegenStakerFactory.StakerInfo[] memory infos = factory.getStakersByDeployer(deployer1);
        assertEq(infos.length, 0, "Should be empty initially");
    }

    function testGetStakersByDeployer_RecordsCorrectData() public {
        bytes32 salt = keccak256("RECORD_SALT");

        vm.prank(deployer1);
        address stakerAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );

        RegenStakerFactory.StakerInfo[] memory infos = factory.getStakersByDeployer(deployer1);
        assertEq(infos.length, 1, "Should have one staker");
        assertEq(infos[0].deployerAddress, deployer1, "Deployer should be recorded");
        assertEq(infos[0].admin, admin, "Admin should be recorded");
        assertEq(infos[0].stakerAddress, stakerAddress, "Staker address should be recorded");
        assertEq(
            uint(infos[0].variant),
            uint(RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION),
            "Variant should be WITH_DELEGATION"
        );
        assertEq(infos[0].calculatorAddress, address(earningPowerCalculator), "Calculator should be recorded");
        assertEq(infos[0].salt, salt, "Salt should be recorded");
        assertTrue(infos[0].timestamp > 0, "Timestamp should be set");
    }

    function testGetStakersByDeployer_MultipleStakers() public {
        bytes32 salt1 = keccak256("MULTI_SALT_1");
        bytes32 salt2 = keccak256("MULTI_SALT_2");

        vm.startPrank(deployer1);
        factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1,
            getRegenStakerBytecode()
        );

        factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP + 100,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT + 50e18,
                rewardDuration: REWARD_DURATION
            }),
            salt2,
            getRegenStakerBytecode()
        );
        vm.stopPrank();

        RegenStakerFactory.StakerInfo[] memory infos = factory.getStakersByDeployer(deployer1);
        assertEq(infos.length, 2, "Should have two stakers");
        assertEq(infos[0].salt, salt1, "First salt should match");
        assertEq(infos[1].salt, salt2, "Second salt should match");
    }

    function testGetStakersByDeployer_IndependentPerDeployer() public {
        bytes32 salt1 = keccak256("DEPLOYER1_INDEPENDENT");
        bytes32 salt2 = keccak256("DEPLOYER2_INDEPENDENT");

        vm.prank(deployer1);
        factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt1,
            getRegenStakerBytecode()
        );

        vm.prank(deployer2);
        factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt2,
            getRegenStakerBytecode()
        );

        RegenStakerFactory.StakerInfo[] memory infos1 = factory.getStakersByDeployer(deployer1);
        RegenStakerFactory.StakerInfo[] memory infos2 = factory.getStakersByDeployer(deployer2);

        assertEq(infos1.length, 1, "Deployer1 should have 1 staker");
        assertEq(infos2.length, 1, "Deployer2 should have 1 staker");
        assertEq(infos1[0].deployerAddress, deployer1);
        assertEq(infos2[0].deployerAddress, deployer2);
    }

    function testStakersPublicAccessor() public {
        bytes32 salt = keccak256("ACCESSOR_SALT");

        vm.prank(deployer1);
        address stakerAddress = factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            getRegenStakerBytecode()
        );

        (
            address deployerAddress,
            uint256 timestamp,
            address infoAdmin,
            address infoStakerAddress,
            RegenStakerFactory.RegenStakerVariant variant,
            address calculatorAddress,
            bytes32 infoSalt
        ) = factory.stakers(deployer1, 0);

        assertEq(deployerAddress, deployer1);
        assertTrue(timestamp > 0);
        assertEq(infoAdmin, admin);
        assertEq(infoStakerAddress, stakerAddress);
        assertEq(uint(variant), uint(RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION));
        assertEq(calculatorAddress, address(earningPowerCalculator));
        assertEq(infoSalt, salt);
    }

    // ========================================================
    //  Branch coverage: _validateBytecode untested branches
    // ========================================================

    /// @notice _validateBytecode reverts with InvalidBytecode for empty code (WITH_DELEGATION)
    function testCreateStakerWithDelegation_RevertIf_EmptyBytecode() public {
        bytes32 salt = keccak256("EMPTY_BYTECODE_SALT");
        bytes memory emptyCode = "";

        vm.prank(deployer1);
        vm.expectRevert(RegenStakerFactory.InvalidBytecode.selector);
        factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            emptyCode
        );
    }

    /// @notice _validateBytecode reverts with InvalidBytecode for empty code (WITHOUT_DELEGATION)
    function testCreateStakerWithoutDelegation_RevertIf_EmptyBytecode() public {
        bytes32 salt = keccak256("EMPTY_BYTECODE_NO_DEL_SALT");
        bytes memory emptyCode = "";

        vm.prank(deployer1);
        vm.expectRevert(RegenStakerFactory.InvalidBytecode.selector);
        factory.createStakerWithoutDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            emptyCode
        );
    }

    /// @notice _validateBytecode reverts with UnauthorizedBytecode for wrong hash (WITH_DELEGATION)
    function testCreateStakerWithDelegation_RevertIf_UnauthorizedBytecode() public {
        bytes32 salt = keccak256("UNAUTHORIZED_BYTECODE_SALT");
        // Use the WITHOUT_DELEGATION bytecode for WITH_DELEGATION variant -> hash mismatch
        bytes memory wrongCode = type(RegenStakerWithoutDelegateSurrogateVotes).creationCode;
        bytes32 expectedHash = factory.canonicalBytecodeHash(RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION);
        bytes32 providedHash = keccak256(wrongCode);

        vm.prank(deployer1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerFactory.UnauthorizedBytecode.selector,
                RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION,
                providedHash,
                expectedHash
            )
        );
        factory.createStakerWithDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            wrongCode
        );
    }

    /// @notice _validateBytecode reverts with UnauthorizedBytecode for wrong hash (WITHOUT_DELEGATION)
    function testCreateStakerWithoutDelegation_RevertIf_UnauthorizedBytecode() public {
        bytes32 salt = keccak256("UNAUTHORIZED_BYTECODE_NO_DEL_SALT");
        // Use the WITH_DELEGATION bytecode for WITHOUT_DELEGATION variant -> hash mismatch
        bytes memory wrongCode = type(RegenStaker).creationCode;
        bytes32 expectedHash = factory.canonicalBytecodeHash(RegenStakerFactory.RegenStakerVariant.WITHOUT_DELEGATION);
        bytes32 providedHash = keccak256(wrongCode);

        vm.prank(deployer1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerFactory.UnauthorizedBytecode.selector,
                RegenStakerFactory.RegenStakerVariant.WITHOUT_DELEGATION,
                providedHash,
                expectedHash
            )
        );
        factory.createStakerWithoutDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            wrongCode
        );
    }

    function testCreateStakerWithoutDelegation_RecordsCorrectVariant() public {
        bytes32 salt = keccak256("WITHOUT_DELEGATION_RECORD_SALT");

        vm.prank(deployer1);
        factory.createStakerWithoutDelegation(
            RegenStakerFactory.CreateStakerParams({
                rewardsToken: rewardsToken,
                stakeToken: stakeToken,
                admin: admin,
                stakerAllowset: stakerAllowset,
                stakerBlockset: IAddressSet(address(0)),
                stakerAccessMode: AccessMode.NONE,
                allocationMechanismAllowset: allocationMechanismAllowset,
                earningPowerCalculator: earningPowerCalculator,
                maxBumpTip: MAX_BUMP_TIP,
                minimumStakeAmount: MINIMUM_STAKE_AMOUNT,
                rewardDuration: REWARD_DURATION
            }),
            salt,
            type(RegenStakerWithoutDelegateSurrogateVotes).creationCode
        );

        RegenStakerFactory.StakerInfo[] memory infos = factory.getStakersByDeployer(deployer1);
        assertEq(infos.length, 1);
        assertEq(
            uint(infos[0].variant),
            uint(RegenStakerFactory.RegenStakerVariant.WITHOUT_DELEGATION),
            "Variant should be WITHOUT_DELEGATION"
        );
    }
}
