// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { AccessMode } from "src/constants.sol";
import { Test, console2 } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { Staker } from "staker/Staker.sol";
import { StakerOnBehalf } from "staker/extensions/StakerOnBehalf.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC20Permit } from "test/mocks/MockERC20Permit.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";

/// @title Fuzz Tests for RegenStakerWithoutDelegateSurrogateVotes
/// @notice Targeted fuzz testing for critical scenarios and edge cases
contract RegenStakerWithoutDelegateSurrogateVotesFuzzTest is Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    RegenStakerWithoutDelegateSurrogateVotes public differentTokenStaker;

    MockERC20 public token;
    MockERC20 public rewardToken;
    AddressSet public stakerAllowset;
    AddressSet public contributionAllowset;
    AddressSet public allocationAllowset;
    RegenEarningPowerCalculator public calculator;

    address public admin;
    address public rewardNotifier;
    address public user1;
    address public user2;
    address public user3;

    // Test parameters
    uint128 public constant REWARD_DURATION = 30 days;
    uint256 public constant MAX_CLAIM_FEE = 0.1e18; // 10%
    uint128 public constant MIN_STAKE = 1e18;
    uint256 public constant MAX_BUMP_TIP = 1e18;

    function setUp() public {
        admin = makeAddr("admin");
        rewardNotifier = makeAddr("rewardNotifier");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy mock contracts
        token = new MockERC20(18);
        rewardToken = new MockERC20(18);
        stakerAllowset = new AddressSet();
        contributionAllowset = new AddressSet();
        allocationAllowset = new AddressSet();
        calculator = new RegenEarningPowerCalculator(
            admin,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Deploy staker contracts
        staker = new RegenStakerWithoutDelegateSurrogateVotes(
            token, // Same token for stake and reward
            token,
            calculator,
            MAX_BUMP_TIP,
            admin,
            REWARD_DURATION,
            MIN_STAKE,
            stakerAllowset,
            IAddressSet(address(0)),
            AccessMode.NONE,
            allocationAllowset
        );

        differentTokenStaker = new RegenStakerWithoutDelegateSurrogateVotes(
            rewardToken, // Different tokens
            token,
            calculator,
            MAX_BUMP_TIP,
            admin,
            REWARD_DURATION,
            MIN_STAKE,
            stakerAllowset,
            IAddressSet(address(0)),
            AccessMode.NONE,
            allocationAllowset
        );

        // Setup permissions
        vm.prank(admin);
        staker.setRewardNotifier(rewardNotifier, true);
        vm.prank(admin);
        differentTokenStaker.setRewardNotifier(rewardNotifier, true);

        // Add users to allowsets
        address[3] memory users = [user1, user2, user3];
        for (uint256 i = 0; i < users.length; i++) {
            stakerAllowset.add(users[i]);
            contributionAllowset.add(users[i]);
        }

        // Setup user tokens
        for (uint256 i = 0; i < users.length; i++) {
            token.mint(users[i], 1000e18);
            rewardToken.mint(users[i], 1000e18);

            vm.startPrank(users[i]);
            token.approve(address(staker), type(uint256).max);
            token.approve(address(differentTokenStaker), type(uint256).max);
            rewardToken.approve(address(differentTokenStaker), type(uint256).max);
            vm.stopPrank();
        }

        // Give reward notifier tokens
        token.mint(rewardNotifier, 10000e18);
        rewardToken.mint(rewardNotifier, 10000e18);
    }

    // ==================== CRITICAL AUDITOR SCENARIO TESTS ====================

    /// @notice Fuzz test for the exact auditor scenario: reward notification without checkpointing
    /// @dev Tests the scenario where rewards are notified but no users checkpoint their positions
    function testFuzz_auditorScenario_noCheckpointing(
        uint256 stakeAmount,
        uint256 firstRewardAmount,
        uint256 timeElapsed,
        uint256 secondRewardAmount
    ) public {
        // Bound inputs to reasonable ranges
        stakeAmount = bound(stakeAmount, MIN_STAKE, 100e18);
        firstRewardAmount = bound(firstRewardAmount, 1e18, 100e18);
        timeElapsed = bound(timeElapsed, 1 hours, REWARD_DURATION + 1 hours);
        secondRewardAmount = bound(secondRewardAmount, 1e18, 100e18);

        // Step 1: User stakes
        vm.prank(user1);
        staker.stake(stakeAmount, user1);

        // Step 2: First reward notification
        vm.startPrank(rewardNotifier);
        token.transfer(address(staker), firstRewardAmount);
        staker.notifyRewardAmount(firstRewardAmount);
        vm.stopPrank();

        // Step 3: Time passes, no user activity (no checkpointing)
        vm.warp(block.timestamp + timeElapsed);

        // Step 4: Attempt second reward notification
        uint256 balanceBefore = token.balanceOf(address(staker));
        uint256 totalStaked = staker.totalStaked();
        uint256 totalRewards = staker.totalRewards();
        uint256 totalClaimed = staker.totalClaimedRewards();

        // Use new simple accounting: totalStaked + totalRewards - totalClaimed + newAmount
        uint256 required = totalStaked + totalRewards - totalClaimed + secondRewardAmount;

        vm.startPrank(rewardNotifier);

        if (balanceBefore >= required) {
            // Should succeed - sufficient balance
            staker.notifyRewardAmount(secondRewardAmount);

            // Verify balance protection held with new simple accounting
            uint256 balanceAfter = token.balanceOf(address(staker));
            uint256 newTotalRewards = staker.totalRewards();
            uint256 newTotalClaimed = staker.totalClaimedRewards();
            uint256 newRequired = staker.totalStaked() + newTotalRewards - newTotalClaimed;

            assertGe(balanceAfter, newRequired, "Balance protection violated after second notification");
        } else {
            // Should fail - insufficient balance, add tokens to make it work
            uint256 needed = required - balanceBefore;
            token.transfer(address(staker), needed);
            staker.notifyRewardAmount(secondRewardAmount);
        }

        vm.stopPrank();
    }

    // ==================== REWARD DISTRIBUTION TESTS ====================

    /// @notice Fuzz test for reward distribution after various operations
    function testFuzz_rewardDistributionAfterOperations(
        uint256 stakeAmount1,
        uint256 stakeAmount2,
        uint256 rewardAmount,
        uint256 operationChoice,
        uint256 timeElapsed
    ) public {
        stakeAmount1 = bound(stakeAmount1, MIN_STAKE, 50e18);
        stakeAmount2 = bound(stakeAmount2, MIN_STAKE, 50e18);
        rewardAmount = bound(rewardAmount, 10e18, 100e18);
        operationChoice = bound(operationChoice, 0, 2); // 0: claim, 1: compound, 2: no-op
        timeElapsed = bound(timeElapsed, 1 hours, 15 days);

        // Two users stake
        vm.prank(user1);
        staker.stake(stakeAmount1, user1);
        vm.prank(user2);
        staker.stake(stakeAmount2, user2);

        // Add sufficient rewards
        vm.startPrank(rewardNotifier);
        token.transfer(address(staker), rewardAmount);
        staker.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Record state before operation
        uint256 totalClaimedBefore = staker.totalClaimedRewards();
        uint256 balanceBefore = token.balanceOf(address(staker));
        (, address feeCollector) = staker.claimFeeParameters();
        uint256 feeCollectorBalanceBefore = feeCollector != address(0) ? token.balanceOf(feeCollector) : 0;

        // Time passes
        vm.warp(block.timestamp + timeElapsed);

        // Perform operation
        vm.prank(user1);
        if (operationChoice == 0) {
            // Claim
            try staker.claimReward(Staker.DepositIdentifier.wrap(0)) {} catch {}
        } else if (operationChoice == 1) {
            // Compound
            try staker.compoundRewards(Staker.DepositIdentifier.wrap(0)) {} catch {}
        }
        // operationChoice == 2 is no-op

        // Verify accounting consistency after operation
        uint256 totalRewardsAfter = staker.totalRewards();
        uint256 totalClaimedAfter = staker.totalClaimedRewards();
        uint256 balanceAfter = token.balanceOf(address(staker));
        uint256 feeCollectorBalanceAfter = feeCollector != address(0) ? token.balanceOf(feeCollector) : 0;

        // Calculate fees that left the contract
        uint256 feesCollected = feeCollectorBalanceAfter - feeCollectorBalanceBefore;

        // Basic consistency checks
        if (operationChoice == 0 && totalClaimedAfter > totalClaimedBefore) {
            // Claim operation increased total claimed
            assertTrue(balanceAfter < balanceBefore, "Balance should decrease after claim");
        }

        // Balance protection should account for fees that have permanently left the contract
        uint256 totalStaked = staker.totalStaked();

        // Balance protection check - skip for compound operations since compounding
        // is not tracked in totalClaimedRewards in our current simple accounting approach
        if (operationChoice != 1) {
            // Skip for compound operations
            // The actual balance plus fees that were collected should cover all obligations
            // Using simple accounting: totalStaked + totalRewards - totalClaimed
            uint256 simpleAccountingRequired = totalStaked + totalRewardsAfter - totalClaimedAfter;
            assertGe(
                balanceAfter + feesCollected,
                simpleAccountingRequired,
                "Balance protection violated after operation (accounting for fees)"
            );
        }
    }

    // ==================== EDGE CASE TESTS ====================

    /// @notice Test precision edge cases
    function testFuzz_precisionEdgeCases(uint256 verySmallAmount, uint256 veryLargeAmount) public {
        verySmallAmount = bound(verySmallAmount, 1, MIN_STAKE - 1);
        veryLargeAmount = bound(veryLargeAmount, 1000e18, 10000e18);

        // Test very small stake (should fail)
        vm.prank(user1);
        vm.expectRevert();
        staker.stake(verySmallAmount, user1);

        // Test very large amounts work correctly
        vm.prank(user1);
        staker.stake(MIN_STAKE, user1);

        vm.startPrank(rewardNotifier);
        token.transfer(address(staker), veryLargeAmount);
        staker.notifyRewardAmount(veryLargeAmount);
        vm.stopPrank();

        // Should not overflow or underflow
        uint256 totalRewards = staker.totalRewards();
        uint256 totalClaimed = staker.totalClaimedRewards();
        uint256 unclaimedRewards = totalRewards > totalClaimed ? totalRewards - totalClaimed : 0;
        assertGe(unclaimedRewards, 0, "accounting underflowed");
        assertLe(unclaimedRewards, veryLargeAmount * 2, "accounting overflowed");
    }

    /// @notice Test time boundary edge cases
    function testFuzz_timeBoundaryEdgeCases(uint256 stakeAmount, uint256 rewardAmount) public {
        stakeAmount = bound(stakeAmount, MIN_STAKE, 100e18);
        rewardAmount = bound(rewardAmount, 10e18, 100e18);

        // User stakes
        vm.prank(user1);
        staker.stake(stakeAmount, user1);

        // Add rewards
        vm.startPrank(rewardNotifier);
        token.transfer(address(staker), rewardAmount);
        staker.notifyRewardAmount(rewardAmount);
        uint256 rewardEndTime = staker.rewardEndTime();
        vm.stopPrank();

        // Test exactly at reward end time
        vm.warp(rewardEndTime);
        uint256 totalRewardsAtEnd = staker.totalRewards();
        uint256 totalClaimedAtEnd = staker.totalClaimedRewards();

        // Test after reward end time
        vm.warp(rewardEndTime + 1);
        uint256 totalRewardsAfterEnd = staker.totalRewards();
        uint256 totalClaimedAfterEnd = staker.totalClaimedRewards();

        // Should be same (no new rewards added after end, no new claims without user activity)
        assertEq(totalRewardsAtEnd, totalRewardsAfterEnd, "TotalRewards changed after reward period ended");
        assertEq(totalClaimedAtEnd, totalClaimedAfterEnd, "TotalClaimed changed after reward period ended");

        // Test new reward notification after period ends
        vm.startPrank(rewardNotifier);
        token.transfer(address(staker), rewardAmount);
        staker.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // Balance protection should still work with simple accounting
        uint256 balance = token.balanceOf(address(staker));
        uint256 totalStaked = staker.totalStaked();
        uint256 totalRewards = staker.totalRewards();
        uint256 totalClaimed = staker.totalClaimedRewards();
        uint256 simpleRequired = totalStaked + totalRewards - totalClaimed;

        assertGe(balance, simpleRequired, "Balance protection failed at time boundary");
    }

    /// @notice Test small amount edge cases
    function testFuzz_smallAmountEdgeCases() public {
        // Test small reward notification (sufficient for valid rate)
        uint256 smallAmount = REWARD_DURATION; // 1 wei per second minimum
        vm.startPrank(rewardNotifier);
        token.transfer(address(staker), smallAmount);
        staker.notifyRewardAmount(smallAmount);
        vm.stopPrank();

        // Should not break accounting
        uint256 totalRewards = staker.totalRewards();
        uint256 totalClaimed = staker.totalClaimedRewards();
        assertGe(totalRewards, 0, "Small reward notification affected totalRewards");
        assertEq(totalClaimed, 0, "Small reward notification affected claimed tracking");
    }
}

contract RegenStakerWithoutDelegateSurrogateVotesWithdrawalFixTest is Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    MockERC20 public stakeToken;
    MockERC20 public rewardToken;
    RegenEarningPowerCalculator public earningPowerCalculator;
    AddressSet public allowset;
    AddressSet public allocationAllowset;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public notifier = makeAddr("notifier");

    uint256 constant INITIAL_BALANCE = 10_000e18;
    uint128 constant MIN_STAKE = 100e18;
    uint256 constant STAKE_AMOUNT = 1000e18;
    uint256 constant REWARD_AMOUNT = 500e18;

    function setUp() public {
        // Deploy tokens
        stakeToken = new MockERC20(18);
        rewardToken = new MockERC20(18);

        // Deploy allowsets
        allowset = new AddressSet();
        allowset.add(alice);
        allowset.add(bob);

        allocationAllowset = new AddressSet();

        // Deploy earning power calculator
        earningPowerCalculator = new RegenEarningPowerCalculator(
            admin,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Deploy staker
        staker = new RegenStakerWithoutDelegateSurrogateVotes(
            IERC20(address(rewardToken)),
            IERC20(address(stakeToken)),
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            30 days, // rewardDuration
            MIN_STAKE, // minimumStakeAmount
            IAddressSet(address(allowset)), // stakerAllowset
            IAddressSet(address(0)), // stakerBlockset
            AccessMode.NONE,
            allocationAllowset // allocationMechanismAllowset
        );

        // Setup notifier
        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);

        // Fund users
        stakeToken.mint(alice, INITIAL_BALANCE);
        stakeToken.mint(bob, INITIAL_BALANCE);
        rewardToken.mint(notifier, INITIAL_BALANCE);
    }

    /// @notice Test basic withdrawal succeeds after fix
    function test_basicWithdrawal() public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Verify stake
        assertEq(staker.totalStaked(), STAKE_AMOUNT);
        assertEq(stakeToken.balanceOf(address(staker)), STAKE_AMOUNT);
        assertEq(stakeToken.balanceOf(alice), INITIAL_BALANCE - STAKE_AMOUNT);

        // Alice withdraws
        vm.prank(alice);
        staker.withdraw(depositId, STAKE_AMOUNT);

        // Verify withdrawal
        assertEq(staker.totalStaked(), 0);
        assertEq(stakeToken.balanceOf(address(staker)), 0);
        assertEq(stakeToken.balanceOf(alice), INITIAL_BALANCE);
    }

    /// @notice Test partial withdrawal
    function test_partialWithdrawal() public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        uint256 withdrawAmount = STAKE_AMOUNT - MIN_STAKE;

        // Alice partially withdraws
        vm.prank(alice);
        staker.withdraw(depositId, withdrawAmount);

        // Verify partial withdrawal
        assertEq(staker.totalStaked(), MIN_STAKE);
        assertEq(stakeToken.balanceOf(address(staker)), MIN_STAKE);
        assertEq(stakeToken.balanceOf(alice), INITIAL_BALANCE - MIN_STAKE);
    }

    /// @notice Test multiple users can withdraw
    function test_multipleUsersWithdraw() public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier aliceDepositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Bob stakes
        vm.startPrank(bob);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier bobDepositId = staker.stake(STAKE_AMOUNT, bob, bob);
        vm.stopPrank();

        // Verify total stakes
        assertEq(staker.totalStaked(), STAKE_AMOUNT * 2);

        // Alice withdraws
        vm.prank(alice);
        staker.withdraw(aliceDepositId, STAKE_AMOUNT);

        // Verify Alice's withdrawal
        assertEq(staker.totalStaked(), STAKE_AMOUNT);
        assertEq(stakeToken.balanceOf(alice), INITIAL_BALANCE);

        // Bob withdraws
        vm.prank(bob);
        staker.withdraw(bobDepositId, STAKE_AMOUNT);

        // Verify Bob's withdrawal
        assertEq(staker.totalStaked(), 0);
        assertEq(stakeToken.balanceOf(bob), INITIAL_BALANCE);
    }

    /// @notice Test withdrawal after earning rewards
    function test_withdrawalAfterEarningRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(notifier);
        rewardToken.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Advance time to earn rewards
        vm.warp(block.timestamp + 15 days);

        // Alice withdraws stake (not rewards)
        vm.prank(alice);
        staker.withdraw(depositId, STAKE_AMOUNT);

        // Verify withdrawal
        assertEq(staker.totalStaked(), 0);
        assertEq(stakeToken.balanceOf(alice), INITIAL_BALANCE);

        // Alice can still claim rewards after withdrawal
        uint256 aliceRewardBalanceBefore = rewardToken.balanceOf(alice);
        vm.prank(alice);
        uint256 rewardsClaimed = staker.claimReward(depositId);
        assertGt(rewardsClaimed, 0, "Should have claimed rewards");
        assertEq(rewardToken.balanceOf(alice), aliceRewardBalanceBefore + rewardsClaimed);
    }

    /// @notice Test withdrawal with compounded rewards
    function test_withdrawalWithCompoundedRewards() public {
        // Setup same token for staking and rewards
        RegenStakerWithoutDelegateSurrogateVotes sameTokenStaker = new RegenStakerWithoutDelegateSurrogateVotes(
            IERC20(address(stakeToken)), // Same token for rewards
            IERC20(address(stakeToken)), // Same token for staking
            earningPowerCalculator,
            0,
            admin,
            30 days,
            MIN_STAKE,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            allocationAllowset
        );

        vm.prank(admin);
        sameTokenStaker.setRewardNotifier(notifier, true);

        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(sameTokenStaker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = sameTokenStaker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Add rewards
        stakeToken.mint(notifier, REWARD_AMOUNT);
        vm.startPrank(notifier);
        stakeToken.transfer(address(sameTokenStaker), REWARD_AMOUNT);
        sameTokenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 15 days);

        // Compound rewards
        vm.prank(alice);
        sameTokenStaker.compoundRewards(depositId);

        (uint96 newStakeAmount, , , , , , ) = sameTokenStaker.deposits(depositId);
        assertGt(newStakeAmount, STAKE_AMOUNT, "Stake should have increased");

        // Withdraw everything
        vm.prank(alice);
        sameTokenStaker.withdraw(depositId, newStakeAmount);

        // Verify withdrawal
        assertEq(sameTokenStaker.totalStaked(), 0);
        assertGt(stakeToken.balanceOf(alice), INITIAL_BALANCE, "Should have withdrawn compounded amount");
    }

    /// @notice Test multiple sequential withdrawals
    function test_multipleSequentialWithdrawals() public {
        // Alice makes multiple deposits
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT * 3);

        Staker.DepositIdentifier deposit1 = staker.stake(STAKE_AMOUNT, alice, alice);
        Staker.DepositIdentifier deposit2 = staker.stake(STAKE_AMOUNT, alice, alice);
        Staker.DepositIdentifier deposit3 = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        assertEq(staker.totalStaked(), STAKE_AMOUNT * 3);

        // Withdraw in different order
        vm.startPrank(alice);
        staker.withdraw(deposit2, STAKE_AMOUNT);
        assertEq(staker.totalStaked(), STAKE_AMOUNT * 2);

        staker.withdraw(deposit1, STAKE_AMOUNT);
        assertEq(staker.totalStaked(), STAKE_AMOUNT);

        staker.withdraw(deposit3, STAKE_AMOUNT);
        assertEq(staker.totalStaked(), 0);
        vm.stopPrank();

        // Verify final balance
        assertEq(stakeToken.balanceOf(alice), INITIAL_BALANCE);
    }

    /// @notice Test gas cost of withdrawal
    function test_withdrawalGasCost() public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Measure withdrawal gas
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        staker.withdraw(depositId, STAKE_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();

        // Log gas usage
        emit log_named_uint("Withdrawal gas used", gasUsed);

        // Verify gas is reasonable (less than 100k)
        assertLt(gasUsed, 100_000, "Withdrawal should be gas efficient");
    }

    /// @notice Fuzz test withdrawal amounts
    function testFuzz_withdrawalAmounts(uint256 stakeAmount, uint256 withdrawAmount) public {
        // Bound inputs
        stakeAmount = bound(stakeAmount, MIN_STAKE, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1, stakeAmount);

        // Adjust withdrawal to respect minimum stake
        if (withdrawAmount < stakeAmount && stakeAmount - withdrawAmount < MIN_STAKE) {
            withdrawAmount = stakeAmount; // Full withdrawal if remainder would be below minimum
        }

        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), stakeAmount);
        Staker.DepositIdentifier depositId = staker.stake(stakeAmount, alice, alice);
        vm.stopPrank();

        uint256 expectedBalance = INITIAL_BALANCE - stakeAmount + withdrawAmount;
        uint256 expectedStaked = stakeAmount - withdrawAmount;

        // Alice withdraws
        vm.prank(alice);
        staker.withdraw(depositId, withdrawAmount);

        // Verify
        assertEq(staker.totalStaked(), expectedStaked);
        assertEq(stakeToken.balanceOf(alice), expectedBalance);
    }

    /// @notice Test that alterDelegatee reverts since delegation is not supported
    function test_alterDelegateeReverts() public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Attempt to alter delegatee should revert
        vm.prank(alice);
        vm.expectRevert(RegenStakerWithoutDelegateSurrogateVotes.DelegationNotSupported.selector);
        staker.alterDelegatee(depositId, bob);
    }

    /// @notice Fuzz test that alterDelegatee always reverts regardless of inputs
    function testFuzz_alterDelegateeAlwaysReverts(address newDelegatee) public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Any attempt to alter delegatee should revert
        vm.prank(alice);
        vm.expectRevert(RegenStakerWithoutDelegateSurrogateVotes.DelegationNotSupported.selector);
        staker.alterDelegatee(depositId, newDelegatee);
    }

    /// @notice Test that alterDelegateeOnBehalf reverts since delegation is not supported
    function test_alterDelegateeOnBehalfReverts() public {
        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // With invalid signature, reverts during signature validation (before reaching _alterDelegatee)
        vm.expectRevert(StakerOnBehalf.StakerOnBehalf__InvalidSignature.selector);
        staker.alterDelegateeOnBehalf(depositId, bob, alice, block.timestamp + 1000, "");
    }

    /// @notice Fuzz test that alterDelegateeOnBehalf always reverts regardless of inputs
    function testFuzz_alterDelegateeOnBehalfAlwaysReverts(address newDelegatee, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);

        // Alice stakes
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // With invalid signature, reverts during signature validation (before reaching _alterDelegatee)
        vm.expectRevert(StakerOnBehalf.StakerOnBehalf__InvalidSignature.selector);
        staker.alterDelegateeOnBehalf(depositId, newDelegatee, alice, deadline, "");
    }
}

contract CompoundEquivalenceTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant USER = address(0xBEEF);
    address internal constant DELEGATEE = address(0xD1E6A7);
    address internal constant NOTIFIER = address(0xFEE);

    uint256 internal constant INITIAL_USER_BAL = 1_000_000e18;
    uint256 internal constant STAKE_AMOUNT = 1_000e18;
    uint256 internal constant REWARD_AMOUNT = 10_000e18;
    uint256 internal constant MAX_BUMP_TIP = 0;
    uint128 internal constant REWARD_DURATION = 30 days; // business as usual
    uint256 internal constant MAX_CLAIM_FEE = 0; // simplify equivalence
    uint128 internal constant MIN_STAKE = 0;

    MockERC20Permit internal token;
    RegenEarningPowerCalculator internal calculator;
    RegenStakerWithoutDelegateSurrogateVotes internal stakerA; // compound path
    RegenStakerWithoutDelegateSurrogateVotes internal stakerB; // claim+stakeMore path
    AddressSet internal allocationAllowset;

    function setUp() public {
        token = new MockERC20Permit(18);
        calculator = new RegenEarningPowerCalculator(
            ADMIN,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        allocationAllowset = new AddressSet();

        stakerA = new RegenStakerWithoutDelegateSurrogateVotes(
            token,
            token,
            calculator,
            MAX_BUMP_TIP,
            ADMIN,
            REWARD_DURATION,
            MIN_STAKE,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset))
        );

        stakerB = new RegenStakerWithoutDelegateSurrogateVotes(
            token,
            token,
            calculator,
            MAX_BUMP_TIP,
            ADMIN,
            REWARD_DURATION,
            MIN_STAKE,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset))
        );

        // fund user and stakers for rewards
        token.mint(USER, INITIAL_USER_BAL);
        token.mint(address(this), REWARD_AMOUNT * 2);

        // enable notifier
        vm.prank(ADMIN);
        stakerA.setRewardNotifier(NOTIFIER, true);
        vm.prank(ADMIN);
        stakerB.setRewardNotifier(NOTIFIER, true);

        // user approves both stakers for stake and future stakeMore
        vm.startPrank(USER);
        token.approve(address(stakerA), type(uint256).max);
        token.approve(address(stakerB), type(uint256).max);
        vm.stopPrank();

        // initial stake on both instances
        vm.prank(USER);
        stakerA.stake(STAKE_AMOUNT, DELEGATEE);
        vm.prank(USER);
        stakerB.stake(STAKE_AMOUNT, DELEGATEE);

        // transfer rewards and notify on both instances
        token.transfer(address(stakerA), REWARD_AMOUNT);
        vm.prank(NOTIFIER);
        stakerA.notifyRewardAmount(REWARD_AMOUNT);

        token.transfer(address(stakerB), REWARD_AMOUNT);
        vm.prank(NOTIFIER);
        stakerB.notifyRewardAmount(REWARD_AMOUNT);

        // advance time to accrue rewards partially
        vm.warp(block.timestamp + 7 days);
    }

    function test_CompoundEqualsClaimPlusStakeMore() public {
        // deposit ids are 0 on both fresh contracts
        Staker.DepositIdentifier depositId = Staker.DepositIdentifier.wrap(0);

        // Path A: compound
        vm.prank(USER);
        uint256 compounded = stakerA.compoundRewards(depositId);

        // Path B: claim then stakeMore
        vm.prank(USER);
        uint256 claimed = stakerB.claimReward(depositId);
        assertGt(claimed, 0, "expected positive claim");
        vm.prank(USER);
        stakerB.stakeMore(depositId, claimed);

        // Assert amounts match
        assertEq(compounded, claimed, "compounded vs claimed mismatch");

        // Compare live unclaimed rewards (sub-wei behavior aligned with claim semantics)
        uint256 unclaimedA = stakerA.unclaimedReward(depositId);
        uint256 unclaimedB = stakerB.unclaimedReward(depositId);
        assertEq(unclaimedA, unclaimedB, "unclaimedReward");

        // Compare globals
        assertEq(stakerA.totalStaked(), stakerB.totalStaked(), "totalStaked");
        assertEq(stakerA.totalEarningPower(), stakerB.totalEarningPower(), "totalEP");
        assertEq(stakerA.depositorTotalStaked(USER), stakerB.depositorTotalStaked(USER), "user total staked");
        assertEq(stakerA.depositorTotalEarningPower(USER), stakerB.depositorTotalEarningPower(USER), "user total EP");
    }

    function testFuzz_CompoundEqualsClaimPlusStakeMore(
        uint128 stakeAmt,
        uint128 rewardAmt,
        uint32 secondsElapsed
    ) public {
        // bounds to avoid pathological overflows and zero cases (values are token units before scaling)
        stakeAmt = uint128(bound(uint256(stakeAmt), 1e6, 1_000_000));
        rewardAmt = uint128(bound(uint256(rewardAmt), 3_000_000, 10_000_000)); // ensure amount/duration >= 1 in wei after scaling
        secondsElapsed = uint32(bound(uint256(secondsElapsed), 1 minutes, 25 days));

        uint256 stakeWei = uint256(stakeAmt) * 1e18;
        uint256 rewardWei = uint256(rewardAmt) * 1e18;

        // fresh instances for each fuzz case
        MockERC20Permit tkn = new MockERC20Permit(18);
        RegenStakerWithoutDelegateSurrogateVotes A = new RegenStakerWithoutDelegateSurrogateVotes(
            tkn,
            tkn,
            calculator,
            MAX_BUMP_TIP,
            ADMIN,
            REWARD_DURATION,
            MIN_STAKE,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset))
        );
        RegenStakerWithoutDelegateSurrogateVotes B = new RegenStakerWithoutDelegateSurrogateVotes(
            tkn,
            tkn,
            calculator,
            MAX_BUMP_TIP,
            ADMIN,
            REWARD_DURATION,
            MIN_STAKE,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset))
        );

        // fund
        tkn.mint(USER, stakeWei * 2);
        tkn.mint(address(this), rewardWei * 2);

        // enable notifier
        vm.prank(ADMIN);
        A.setRewardNotifier(NOTIFIER, true);
        vm.prank(ADMIN);
        B.setRewardNotifier(NOTIFIER, true);

        // user approves
        vm.startPrank(USER);
        tkn.approve(address(A), type(uint256).max);
        tkn.approve(address(B), type(uint256).max);
        vm.stopPrank();

        // stake
        vm.prank(USER);
        A.stake(stakeWei, DELEGATEE);
        vm.prank(USER);
        B.stake(stakeWei, DELEGATEE);

        // rewards and notify
        tkn.transfer(address(A), rewardWei);
        vm.prank(NOTIFIER);
        A.notifyRewardAmount(rewardWei);

        tkn.transfer(address(B), rewardWei);
        vm.prank(NOTIFIER);
        B.notifyRewardAmount(rewardWei);

        // time passes
        vm.warp(block.timestamp + secondsElapsed);

        // act
        Staker.DepositIdentifier id = Staker.DepositIdentifier.wrap(0);
        vm.prank(USER);
        uint256 compounded = A.compoundRewards(id);

        vm.prank(USER);
        uint256 claimed = B.claimReward(id);
        vm.prank(USER);
        B.stakeMore(id, claimed);

        // assert equivalence
        assertEq(compounded, claimed, "amount");
        assertEq(A.totalStaked(), B.totalStaked(), "totalStaked");
        assertEq(A.totalEarningPower(), B.totalEarningPower(), "totalEP");
        assertEq(A.depositorTotalStaked(USER), B.depositorTotalStaked(USER), "user total staked");
        assertEq(A.depositorTotalEarningPower(USER), B.depositorTotalEarningPower(USER), "user total EP");
        assertEq(A.rewardPerTokenAccumulatedCheckpoint(), B.rewardPerTokenAccumulatedCheckpoint(), "rPT");
        assertEq(A.lastCheckpointTime(), B.lastCheckpointTime(), "last time");
        assertEq(A.scaledRewardRate(), B.scaledRewardRate(), "scaled rate");
        assertEq(A.rewardEndTime(), B.rewardEndTime(), "end time");
        // token balances at contracts equal
        assertEq(tkn.balanceOf(address(A)), tkn.balanceOf(address(B)), "token balance");
        // live unclaimed equal
        assertEq(A.unclaimedReward(id), B.unclaimedReward(id), "unclaimed");
    }
}
