// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { AccessMode } from "src/constants.sol";
import "forge-std/Test.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { Staker } from "staker/Staker.sol";

/// @title RegenStakerGovernanceProtectionTest
/// @dev Tests setEarningPowerCalculator governance protection during active reward periods
contract RegenStakerGovernanceProtectionTest is Test {
    RegenStaker public regenStaker;
    RegenEarningPowerCalculator public earningPowerCalculator;
    MockERC20 public rewardToken;
    MockERC20Staking public stakeToken;
    AddressSet public allowset;
    AddressSet public allocationAllowset;

    address public admin = makeAddr("admin");
    address public rewardNotifier = makeAddr("rewardNotifier");
    address public user = makeAddr("user");

    uint256 public constant INITIAL_REWARD_AMOUNT = 100 ether;
    uint256 public constant REWARD_DURATION = 30 days;
    uint256 public constant INITIAL_MIN_STAKE = 1 ether;
    uint256 public constant INITIAL_MAX_BUMP_TIP = 1000;

    function setUp() public {
        rewardToken = new MockERC20(18);
        stakeToken = new MockERC20Staking(18);

        // Deploy allowset and calculator
        vm.startPrank(admin);
        allowset = new AddressSet();
        allocationAllowset = new AddressSet();
        earningPowerCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Deploy RegenStaker
        regenStaker = new RegenStaker(
            rewardToken,
            stakeToken,
            earningPowerCalculator,
            1000,
            admin,
            uint128(REWARD_DURATION),
            uint128(INITIAL_MIN_STAKE),
            allowset,
            IAddressSet(address(0)),
            AccessMode.NONE,
            allocationAllowset
        );
        regenStaker.setRewardNotifier(rewardNotifier, true);
        allowset.add(user);
        vm.stopPrank();

        rewardToken.mint(rewardNotifier, INITIAL_REWARD_AMOUNT);
        stakeToken.mint(user, 10 ether);

        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), 10 ether);
        regenStaker.stake(10 ether, user);
        vm.stopPrank();
    }

    function _deployNewCalculator() internal returns (RegenEarningPowerCalculator) {
        return new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);
    }

    function _startRewards() internal {
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();
    }

    function test_RevertWhen_SetEarningPowerCalculatorDuringActiveReward() public {
        RegenEarningPowerCalculator newCalculator = _deployNewCalculator();
        _startRewards();

        vm.prank(admin);
        vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
        regenStaker.setEarningPowerCalculator(address(newCalculator));
    }

    function test_SetEarningPowerCalculatorAfterRewardPeriod() public {
        RegenEarningPowerCalculator newCalculator = _deployNewCalculator();
        _startRewards();
        vm.warp(regenStaker.rewardEndTime() + 1);

        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        assertEq(address(regenStaker.earningPowerCalculator()), address(newCalculator));
    }

    function test_SetEarningPowerCalculatorBeforeFirstReward() public {
        RegenEarningPowerCalculator newCalculator = _deployNewCalculator();

        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        assertEq(address(regenStaker.earningPowerCalculator()), address(newCalculator));
    }

    function test_RevertWhen_NonAdminSetsEarningPowerCalculator() public {
        RegenEarningPowerCalculator newCalculator = _deployNewCalculator();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), user));
        regenStaker.setEarningPowerCalculator(address(newCalculator));
    }

    function test_RevertWhen_SetEarningPowerCalculatorExactlyAtRewardEndTime() public {
        RegenEarningPowerCalculator newCalculator = _deployNewCalculator();
        _startRewards();
        uint256 rewardEndTime = regenStaker.rewardEndTime();

        vm.warp(rewardEndTime);
        vm.prank(admin);
        vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        vm.warp(rewardEndTime + 1);
        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(newCalculator));
        assertEq(address(regenStaker.earningPowerCalculator()), address(newCalculator));
    }

    function testFuzz_SetEarningPowerCalculatorProtectionTiming(uint256 timeOffset) public {
        RegenEarningPowerCalculator newCalculator = _deployNewCalculator();
        _startRewards();
        uint256 rewardEndTime = regenStaker.rewardEndTime();
        timeOffset = bound(timeOffset, 0, REWARD_DURATION + 1 days);
        vm.warp(block.timestamp + timeOffset);

        vm.prank(admin);
        if (block.timestamp <= rewardEndTime) {
            vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
            regenStaker.setEarningPowerCalculator(address(newCalculator));
        } else {
            regenStaker.setEarningPowerCalculator(address(newCalculator));
            assertEq(address(regenStaker.earningPowerCalculator()), address(newCalculator));
        }
    }

    function test_AdminCanAssignRewardNotifierToArbitraryAddress() public {
        address newNotifier = makeAddr("newNotifier");
        uint256 rewardAmount = 50 ether;
        rewardToken.mint(newNotifier, rewardAmount);

        vm.prank(admin);
        regenStaker.setRewardNotifier(newNotifier, true);

        assertTrue(regenStaker.isRewardNotifier(newNotifier));

        vm.startPrank(newNotifier);
        rewardToken.transfer(address(regenStaker), rewardAmount);
        regenStaker.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        assertGt(regenStaker.rewardEndTime(), block.timestamp);
    }

    /**
     * @dev Test setEarningPowerCalculator reverts during active reward period
     */
    function test_setEarningPowerCalculator_revertsDuringActiveReward() public {
        // Deploy alternative calculator
        RegenEarningPowerCalculator newCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Start reward period
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();

        // Verify we're in active reward period
        assertGt(regenStaker.rewardEndTime(), block.timestamp, "Should be in active reward period");

        // Try to change calculator during active rewards - should revert
        vm.prank(admin);
        vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
        regenStaker.setEarningPowerCalculator(address(newCalculator));
    }

    /**
     * @dev Test setEarningPowerCalculator succeeds after reward period ends
     */
    function test_setEarningPowerCalculator_succeedsAfterRewardPeriod() public {
        // Deploy alternative calculator
        RegenEarningPowerCalculator newCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Start reward period
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();

        // Fast forward past reward end time
        vm.warp(regenStaker.rewardEndTime() + 1);

        // Now setEarningPowerCalculator should succeed
        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        // Verify change was applied
        assertEq(address(regenStaker.earningPowerCalculator()), address(newCalculator), "Calculator should be updated");
    }

    /**
     * @dev Test setEarningPowerCalculator works before any rewards are notified
     */
    function test_setEarningPowerCalculator_worksBeforeFirstReward() public {
        // Deploy alternative calculator
        RegenEarningPowerCalculator newCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // No rewards notified yet, rewardEndTime should be 0
        assertEq(regenStaker.rewardEndTime(), 0, "No active reward period");

        // setEarningPowerCalculator should work
        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        assertEq(address(regenStaker.earningPowerCalculator()), address(newCalculator), "Calculator should be updated");
    }

    /**
     * @dev Test only admin can call setEarningPowerCalculator (existing access control still works)
     */
    function test_setEarningPowerCalculator_onlyAdmin() public {
        // Deploy alternative calculator
        RegenEarningPowerCalculator newCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Fast forward past any potential reward period
        vm.warp(block.timestamp + REWARD_DURATION + 1);

        // Non-admin should fail
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), user));
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        // Admin should succeed
        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(newCalculator));
        assertEq(
            address(regenStaker.earningPowerCalculator()),
            address(newCalculator),
            "Admin should be able to set calculator"
        );
    }

    /**
     * @dev Test governance protection consistency includes setEarningPowerCalculator
     */
    function test_setEarningPowerCalculator_governanceProtectionConsistency() public {
        // Deploy alternative calculator
        RegenEarningPowerCalculator newCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Start reward period
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();

        uint256 rewardEndTime = regenStaker.rewardEndTime();
        assertGt(rewardEndTime, block.timestamp, "Should be in active reward period");

        // All governance functions should be protected during active rewards
        vm.startPrank(admin);

        // setEarningPowerCalculator protection
        vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        // setMaxBumpTip protection (increases revert)
        vm.expectRevert(RegenStakerBase.CannotRaiseMaxBumpTipDuringActiveReward.selector);
        regenStaker.setMaxBumpTip(INITIAL_MAX_BUMP_TIP + 1);

        // setMinimumStakeAmount protection (increases revert)
        vm.expectRevert(RegenStakerBase.CannotRaiseMinimumStakeAmountDuringActiveReward.selector);
        regenStaker.setMinimumStakeAmount(2 ether);

        vm.stopPrank();

        // Fast forward past reward period
        vm.warp(rewardEndTime + 1);

        // All should work after reward period
        vm.startPrank(admin);

        regenStaker.setEarningPowerCalculator(address(newCalculator));
        assertEq(
            address(regenStaker.earningPowerCalculator()),
            address(newCalculator),
            "Calculator should update after reward period"
        );

        regenStaker.setMaxBumpTip(10000);
        assertEq(regenStaker.maxBumpTip(), 10000, "MaxBumpTip should update after reward period");

        regenStaker.setMinimumStakeAmount(1 ether);
        assertEq(regenStaker.minimumStakeAmount(), 1 ether, "MinimumStake should update after reward period");

        vm.stopPrank();
    }

    /**
     * @dev Fuzz test: setEarningPowerCalculator protection across various time points
     */
    function testFuzz_setEarningPowerCalculator_protectionTiming(uint256 timeOffset) public {
        // Deploy alternative calculator
        RegenEarningPowerCalculator newCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Start reward period
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();

        uint256 rewardEndTime = regenStaker.rewardEndTime();

        // Bound time offset to be within or after reward period
        timeOffset = bound(timeOffset, 0, REWARD_DURATION + 1 days);
        vm.warp(block.timestamp + timeOffset);

        vm.prank(admin);
        if (block.timestamp <= rewardEndTime) {
            // During reward period - should revert
            vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
            regenStaker.setEarningPowerCalculator(address(newCalculator));
        } else {
            // After reward period - should succeed
            regenStaker.setEarningPowerCalculator(address(newCalculator));
            assertEq(
                address(regenStaker.earningPowerCalculator()),
                address(newCalculator),
                "Should update after reward period"
            );
        }
    }

    /**
     * @dev Test multiple reward cycles with setEarningPowerCalculator protection
     */
    function test_setEarningPowerCalculator_multipleRewardCycles() public {
        // Deploy alternative calculators
        RegenEarningPowerCalculator calculator2 = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        RegenEarningPowerCalculator calculator3 = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // First reward cycle
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT / 2);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT / 2);
        vm.stopPrank();

        // Cannot change during first cycle
        vm.prank(admin);
        vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
        regenStaker.setEarningPowerCalculator(address(calculator2));

        // Fast forward to between cycles
        vm.warp(regenStaker.rewardEndTime() + 1);

        // Can change between cycles
        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(calculator2));
        assertEq(address(regenStaker.earningPowerCalculator()), address(calculator2), "Should update between cycles");

        // Second reward cycle
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT / 2);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT / 2);
        vm.stopPrank();

        // Cannot change during second cycle
        vm.prank(admin);
        vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
        regenStaker.setEarningPowerCalculator(address(calculator3));

        // Fast forward past second cycle
        vm.warp(regenStaker.rewardEndTime() + 1);

        // Can change after all cycles
        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(calculator3));
        assertEq(address(regenStaker.earningPowerCalculator()), address(calculator3), "Should update after all cycles");
    }

    /**
     * @dev Test setEarningPowerCalculator protection with edge case timing (exactly at rewardEndTime)
     */
    function test_setEarningPowerCalculator_exactlyAtRewardEndTime() public {
        // Deploy alternative calculator
        RegenEarningPowerCalculator newCalculator = new RegenEarningPowerCalculator(
            admin,
            allowset,
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Start reward period
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), INITIAL_REWARD_AMOUNT);
        regenStaker.notifyRewardAmount(INITIAL_REWARD_AMOUNT);
        vm.stopPrank();

        uint256 rewardEndTime = regenStaker.rewardEndTime();

        // Warp to exactly rewardEndTime (boundary condition)
        vm.warp(rewardEndTime);

        // At rewardEndTime, should still revert (require is block.timestamp > rewardEndTime)
        vm.prank(admin);
        vm.expectRevert(RegenStakerBase.CannotChangeEarningPowerCalculatorDuringActiveReward.selector);
        regenStaker.setEarningPowerCalculator(address(newCalculator));

        // Move 1 second past rewardEndTime
        vm.warp(rewardEndTime + 1);

        // Now should succeed
        vm.prank(admin);
        regenStaker.setEarningPowerCalculator(address(newCalculator));
        assertEq(
            address(regenStaker.earningPowerCalculator()),
            address(newCalculator),
            "Should succeed after rewardEndTime"
        );
    }
}
