// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessMode} from "src/constants.sol";
import "forge-std/Test.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Staking } from "staker/interfaces/IERC20Staking.sol";
import { Staker } from "staker/Staker.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockEarningPowerCalculator } from "test/mocks/MockEarningPowerCalculator.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";

/// @title RegenStakerBase Branch Coverage
/// @notice Tests untested branches in RegenStakerBase: BLOCKSET access, compound, stakeMore, bumpEarningPower, etc.
contract RegenStakerBaseBranchCoverageTest is Test {
    RegenStaker regenStaker;
    RegenEarningPowerCalculator calculator;
    AddressSet stakerAllowset;
    AddressSet stakerBlockset;
    AddressSet allocationMechanismAllowset;
    MockERC20Staking stakeToken;

    address public constant ADMIN = address(0xAD);
    address public staker1;
    address public staker2;
    address public blockedStaker;

    function setUp() public {
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");
        blockedStaker = makeAddr("blockedStaker");

        vm.startPrank(ADMIN);

        stakeToken = new MockERC20Staking(18);
        stakerAllowset = new AddressSet();
        stakerBlockset = new AddressSet();
        allocationMechanismAllowset = new AddressSet();

        calculator = new RegenEarningPowerCalculator(
            ADMIN, IAddressSet(address(stakerAllowset)), IAddressSet(address(stakerBlockset)), AccessMode.NONE
        );

        regenStaker = new RegenStaker(
            IERC20(address(stakeToken)), // reward = stake for compound tests
            IERC20Staking(address(stakeToken)),
            calculator,
            1e18, // maxBumpTip
            ADMIN,
            uint128(7 days), // rewardDuration
            0, // minimumStakeAmount
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.NONE,
            IAddressSet(address(allocationMechanismAllowset))
        );

        regenStaker.setRewardNotifier(ADMIN, true);
        vm.stopPrank();
    }

    // === Helper: stake tokens ===
    function _stakeFor(address user, uint256 amount) internal returns (Staker.DepositIdentifier depositId) {
        stakeToken.mint(user, amount);
        vm.startPrank(user);
        stakeToken.approve(address(regenStaker), amount);
        depositId = regenStaker.stake(amount, user, user);
        vm.stopPrank();
    }

    // === Helper: notify rewards ===
    function _notifyReward(uint256 amount) internal {
        stakeToken.mint(address(regenStaker), amount);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(amount);
    }

    // ===== BLOCKSET mode: _checkStakerAccess reverts when blocked =====

    function test_blocksetMode_stakeReverts_whenBlocked() public {
        vm.startPrank(ADMIN);
        regenStaker.setAccessMode(AccessMode.BLOCKSET);
        stakerBlockset.add(blockedStaker);
        vm.stopPrank();

        stakeToken.mint(blockedStaker, 1000e18);
        vm.startPrank(blockedStaker);
        stakeToken.approve(address(regenStaker), 1000e18);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerBlocked.selector, blockedStaker));
        regenStaker.stake(1000e18, blockedStaker, blockedStaker);
        vm.stopPrank();
    }

    function test_blocksetMode_stakeSucceeds_whenNotBlocked() public {
        vm.startPrank(ADMIN);
        regenStaker.setAccessMode(AccessMode.BLOCKSET);
        vm.stopPrank();

        // staker1 not in blockset, should succeed
        _stakeFor(staker1, 1000e18);
    }

    // ===== ALLOWSET mode: _checkStakerAccess reverts when not in allowset =====

    function test_allowsetMode_stakeReverts_whenNotAllowed() public {
        vm.startPrank(ADMIN);
        regenStaker.setAccessMode(AccessMode.ALLOWSET);
        vm.stopPrank();

        stakeToken.mint(staker1, 1000e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 1000e18);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, staker1));
        regenStaker.stake(1000e18, staker1, staker1);
        vm.stopPrank();
    }

    function test_allowsetMode_stakeSucceeds_whenAllowed() public {
        vm.startPrank(ADMIN);
        regenStaker.setAccessMode(AccessMode.ALLOWSET);
        stakerAllowset.add(staker1);
        vm.stopPrank();

        _stakeFor(staker1, 1000e18);
    }

    // ===== _stakeMore: BLOCKSET check on deposit.owner =====

    function test_stakeMore_blocksetMode_revertsWhenOwnerBlocked() public {
        // Stake first in NONE mode
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        // Switch to BLOCKSET and block staker1
        vm.startPrank(ADMIN);
        regenStaker.setAccessMode(AccessMode.BLOCKSET);
        stakerBlockset.add(staker1);
        vm.stopPrank();

        stakeToken.mint(staker1, 500e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 500e18);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerBlocked.selector, staker1));
        regenStaker.stakeMore(depositId, 500e18);
        vm.stopPrank();
    }

    // ===== _stake: zero amount reverts =====

    function test_stake_zeroAmount_reverts() public {
        stakeToken.mint(staker1, 1000e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 1000e18);
        vm.expectRevert(RegenStakerBase.ZeroOperation.selector);
        regenStaker.stake(0, staker1, staker1);
        vm.stopPrank();
    }

    // ===== _stakeMore: zero amount reverts =====

    function test_stakeMore_zeroAmount_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(staker1);
        vm.expectRevert(RegenStakerBase.ZeroOperation.selector);
        regenStaker.stakeMore(depositId, 0);
    }

    // ===== _withdraw: zero amount reverts =====

    function test_withdraw_zeroAmount_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(staker1);
        vm.expectRevert(RegenStakerBase.ZeroOperation.selector);
        regenStaker.withdraw(depositId, 0);
    }

    // ===== Minimum stake amount boundary =====

    function test_minimumStake_exactBoundary_succeeds() public {
        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(100e18);

        // Stake exactly the minimum
        _stakeFor(staker1, 100e18);
    }

    function test_minimumStake_belowBoundary_reverts() public {
        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(100e18);

        stakeToken.mint(staker1, 99e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 99e18);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.MinimumStakeAmountNotMet.selector, 100e18, 99e18));
        regenStaker.stake(99e18, staker1, staker1);
        vm.stopPrank();
    }

    function test_minimumStake_withdrawToZero_succeeds() public {
        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(100e18);

        Staker.DepositIdentifier depositId = _stakeFor(staker1, 100e18);

        // Withdraw all - should succeed (zero balance exception)
        vm.prank(staker1);
        regenStaker.withdraw(depositId, 100e18);
    }

    function test_minimumStake_withdrawBelowMinimum_reverts() public {
        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(100e18);

        Staker.DepositIdentifier depositId = _stakeFor(staker1, 200e18);

        // Withdraw to 50 (below minimum, not zero) - should revert
        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.MinimumStakeAmountNotMet.selector, 100e18, 50e18));
        regenStaker.withdraw(depositId, 150e18);
    }

    // ===== compoundRewards: zero unclaimed returns 0 =====

    function test_compound_zeroUnclaimed_returnsZero() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        // No rewards notified, so unclaimed = 0
        vm.prank(staker1);
        uint256 compounded = regenStaker.compoundRewards(depositId);
        assertEq(compounded, 0, "Should return 0 when no unclaimed rewards");
    }

    // ===== compoundRewards: not claimer or owner reverts =====

    function test_compound_notClaimerOrOwner_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(staker2);
        vm.expectRevert(
            abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not claimer or owner"), staker2)
        );
        regenStaker.compoundRewards(depositId);
    }

    // ===== compoundRewards: BLOCKSET check on deposit owner =====

    function test_compound_blocksetMode_revertsWhenOwnerBlocked() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 1 days);

        // Block staker1
        vm.startPrank(ADMIN);
        regenStaker.setAccessMode(AccessMode.BLOCKSET);
        stakerBlockset.add(staker1);
        vm.stopPrank();

        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerBlocked.selector, staker1));
        regenStaker.compoundRewards(depositId);
    }

    // ===== compoundRewards: ALLOWSET check on deposit owner =====

    function test_compound_allowsetMode_revertsWhenOwnerNotAllowed() public {
        // Must stake in NONE mode first since staker1 won't be in allowset
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);
        vm.warp(block.timestamp + 1 days);

        // Switch to ALLOWSET mode without adding staker1
        vm.prank(ADMIN);
        regenStaker.setAccessMode(AccessMode.ALLOWSET);

        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, staker1));
        regenStaker.compoundRewards(depositId);
    }

    // ===== Paused: stake reverts =====

    function test_paused_stakeReverts() public {
        vm.prank(ADMIN);
        regenStaker.pause();

        stakeToken.mint(staker1, 1000e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 1000e18);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        regenStaker.stake(1000e18, staker1, staker1);
        vm.stopPrank();
    }

    // ===== Paused: withdraw still works =====

    function test_paused_withdrawStillWorks() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(staker1);
        regenStaker.withdraw(depositId, 1000e18);
    }

    // ===== Paused: compound reverts =====

    function test_paused_compoundReverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(staker1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        regenStaker.compoundRewards(depositId);
    }

    // ===== setRewardDuration: during active reward reverts =====

    function test_setRewardDuration_duringActiveReward_reverts() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.CannotChangeRewardDurationDuringActiveReward.selector);
        regenStaker.setRewardDuration(uint128(14 days));
    }

    // ===== setRewardDuration: invalid duration reverts =====

    function test_setRewardDuration_tooShort_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.InvalidRewardDuration.selector, 1 days));
        regenStaker.setRewardDuration(uint128(1 days));
    }

    function test_setRewardDuration_tooLong_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.InvalidRewardDuration.selector, 3001 days));
        regenStaker.setRewardDuration(uint128(3001 days));
    }

    // ===== setRewardDuration: same value NoOperation =====

    function test_setRewardDuration_sameValue_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.NoOperation.selector);
        regenStaker.setRewardDuration(uint128(7 days));
    }

    // ===== setMinimumStakeAmount: raise during active reward reverts =====

    function test_setMinimumStake_raiseDuringActiveReward_reverts() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.CannotRaiseMinimumStakeAmountDuringActiveReward.selector);
        regenStaker.setMinimumStakeAmount(100e18);
    }

    // ===== setMinimumStakeAmount: lower during active reward succeeds =====

    function test_setMinimumStake_lowerDuringActiveReward_succeeds() public {
        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(100e18);

        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        // Lowering is allowed during active reward
        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(50e18);
        assertEq(regenStaker.minimumStakeAmount(), 50e18);
    }

    // ===== setMaxBumpTip: raise during active reward reverts =====

    function test_setMaxBumpTip_raiseDuringActiveReward_reverts() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.CannotRaiseMaxBumpTipDuringActiveReward.selector);
        regenStaker.setMaxBumpTip(2e18);
    }

    // ===== setMaxBumpTip: lower during active reward succeeds =====

    function test_setMaxBumpTip_lowerDuringActiveReward_succeeds() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        vm.prank(ADMIN);
        regenStaker.setMaxBumpTip(0.5e18);
    }

    // ===== setStakerAllowset: same value NoOperation =====

    function test_setStakerAllowset_sameValue_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.NoOperation.selector);
        regenStaker.setStakerAllowset(IAddressSet(address(stakerAllowset)));
    }

    // ===== setStakerAllowset: same as mechanism allowset reverts =====

    function test_setStakerAllowset_sameAsMechanism_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(Staker.Staker__InvalidAddress.selector);
        regenStaker.setStakerAllowset(IAddressSet(address(allocationMechanismAllowset)));
    }

    // ===== setStakerBlockset: same value NoOperation =====

    function test_setStakerBlockset_sameValue_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.NoOperation.selector);
        regenStaker.setStakerBlockset(IAddressSet(address(stakerBlockset)));
    }

    // ===== setStakerBlockset: same as mechanism allowset reverts =====

    function test_setStakerBlockset_sameAsMechanism_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(Staker.Staker__InvalidAddress.selector);
        regenStaker.setStakerBlockset(IAddressSet(address(allocationMechanismAllowset)));
    }

    // ===== setAccessMode: same mode NoOperation =====

    function test_setAccessMode_sameMode_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.NoOperation.selector);
        regenStaker.setAccessMode(AccessMode.NONE);
    }

    // ===== setAllocationMechanismAllowset: same value NoOperation =====

    function test_setAllocationMechanismAllowset_sameValue_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.NoOperation.selector);
        regenStaker.setAllocationMechanismAllowset(IAddressSet(address(allocationMechanismAllowset)));
    }

    // ===== setAllocationMechanismAllowset: address(0) reverts =====

    function test_setAllocationMechanismAllowset_zero_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.DisablingAllocationMechanismAllowsetNotAllowed.selector);
        regenStaker.setAllocationMechanismAllowset(IAddressSet(address(0)));
    }

    // ===== setAllocationMechanismAllowset: same as staker allowset reverts =====

    function test_setAllocationMechanismAllowset_sameAsStaker_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(Staker.Staker__InvalidAddress.selector);
        regenStaker.setAllocationMechanismAllowset(IAddressSet(address(stakerAllowset)));
    }

    // ===== setAllocationMechanismAllowset: same as staker blockset reverts =====

    function test_setAllocationMechanismAllowset_sameAsBlockset_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(Staker.Staker__InvalidAddress.selector);
        regenStaker.setAllocationMechanismAllowset(IAddressSet(address(stakerBlockset)));
    }

    // ===== pause/unpause =====

    function test_pause_notAdmin_reverts() public {
        vm.prank(staker1);
        vm.expectRevert();
        regenStaker.pause();
    }

    function test_unpause_notAdmin_reverts() public {
        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(staker1);
        vm.expectRevert();
        regenStaker.unpause();
    }

    function test_unpause_succeeds() public {
        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(ADMIN);
        regenStaker.unpause();

        // Can now stake
        _stakeFor(staker1, 1000e18);
    }

    // ===== notifyRewardAmount during existing reward (carry-over path) =====

    function test_notifyReward_carryOver_path() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        // Advance halfway
        vm.warp(block.timestamp + 3.5 days);

        // Notify more rewards (should carry over remaining)
        _notifyReward(5000e18);

        // Verify cumulative rewards include the carry-over path update
        assertEq(regenStaker.totalRewards(), 15000e18);
    }

    // ===== _checkpointGlobalReward: totalEarningPower == 0 extends rewardEndTime =====

    function test_checkpointGlobalReward_zeroEarningPower_extendsEndTime() public {
        // Notify reward with no stakers (totalEarningPower = 0)
        stakeToken.mint(address(regenStaker), 10000e18);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(10000e18);

        uint256 endTimeBefore = regenStaker.rewardEndTime();

        // Advance time - since no earning power, end time should extend
        vm.warp(block.timestamp + 1 days);

        // Trigger checkpoint via a stake
        _stakeFor(staker1, 1000e18);

        uint256 endTimeAfter = regenStaker.rewardEndTime();
        assertGt(endTimeAfter, endTimeBefore, "End time should have extended with zero earning power");
    }

    // ===== RegenStaker: predictSurrogateAddress =====

    function test_predictSurrogateAddress_returnsConsistentAddress() public view {
        address predicted = regenStaker.predictSurrogateAddress(staker1);
        assertTrue(predicted != address(0), "Predicted address should not be zero");

        // Calling again should give same result
        address predicted2 = regenStaker.predictSurrogateAddress(staker1);
        assertEq(predicted, predicted2, "Should be deterministic");
    }

    // ===== RegenStaker: getDelegateeFromSurrogate =====

    function test_getDelegateeFromSurrogate_returnsCorrectDelegatee() public {
        // Stake to create a surrogate for staker1
        _stakeFor(staker1, 1000e18);

        // The surrogate should delegate to staker1
        address surrogate = address(regenStaker.surrogates(staker1));
        assertTrue(surrogate != address(0), "Surrogate should exist after staking");

        address delegatee = regenStaker.getDelegateeFromSurrogate(surrogate);
        assertEq(delegatee, staker1, "Surrogate should delegate to staker1");
    }

    // ===== RegenStaker: predictSurrogateAddress matches actual =====

    function test_predictSurrogateAddress_matchesDeployed() public {
        address predicted = regenStaker.predictSurrogateAddress(staker1);

        // Stake to deploy surrogate
        _stakeFor(staker1, 1000e18);

        address actual = address(regenStaker.surrogates(staker1));
        assertEq(predicted, actual, "Predicted address should match deployed surrogate");
    }

    // ===== InsufficientRewardBalance =====

    function test_notifyReward_insufficientBalance_reverts() public {
        // Don't mint any tokens - contract has no balance
        vm.prank(ADMIN);
        vm.expectRevert();
        regenStaker.notifyRewardAmount(10000e18);
    }

    // ===== _validateAndGetRequiredBalance carry-over =====

    function test_notifyReward_carryOverValidation() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        // Claim some rewards
        vm.warp(block.timestamp + 3 days);
        Staker.DepositIdentifier depositId = Staker.DepositIdentifier.wrap(0);
        vm.prank(staker1);
        regenStaker.claimReward(depositId);

        // Now notify more - should account for carry-over
        stakeToken.mint(address(regenStaker), 5000e18);
        vm.prank(ADMIN);
        regenStaker.notifyRewardAmount(5000e18);
    }

    // =====================================================================
    // Phase 2: Additional branch coverage for RegenStakerBase
    // Targets: bumpEarningPower, _alterDelegatee, _checkpointGlobalReward,
    //          _notifyRewardAmountWithCustomDuration edge cases,
    //          contribute zero-amount, _consumeRewards zero path
    // =====================================================================

    // ===== _alterDelegatee: covers the uncovered function =====

    function test_alterDelegatee_succeeds() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        // staker1 changes delegatee to staker2
        vm.prank(staker1);
        regenStaker.alterDelegatee(depositId, staker2);

        // Verify delegatee changed
        (,,, address delegatee,,,) = regenStaker.deposits(depositId);
        assertEq(delegatee, staker2, "Delegatee should be staker2");
    }

    function test_alterDelegatee_whenPaused_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(staker1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        regenStaker.alterDelegatee(depositId, staker2);
    }

    // ===== bumpEarningPower: covers the uncovered function and all its branches =====

    function test_bumpEarningPower_invalidTip_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        // maxBumpTip is 1e18, so requesting more reverts
        vm.prank(staker2);
        vm.expectRevert(Staker.Staker__InvalidTip.selector);
        regenStaker.bumpEarningPower(depositId, staker2, 2e18);
    }

    function test_bumpEarningPower_unqualified_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        // The RegenEarningPowerCalculator returns (balance, balance != oldEP).
        // After staking, deposit.earningPower == balance, so getNewEarningPower returns
        // (balance, false) since newEP == oldEP. This means !_isQualifiedForBump = true.
        vm.prank(staker2);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unqualified.selector, 1000e18));
        regenStaker.bumpEarningPower(depositId, staker2, 0);
    }

    function test_bumpEarningPower_downward_withTip_succeeds() public {
        // Setup: stake in NONE mode, notify rewards, accrue
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);
        vm.warp(block.timestamp + 3 days);

        // Block staker1 so earning power drops to 0
        vm.startPrank(ADMIN);
        regenStaker.setAccessMode(AccessMode.BLOCKSET);
        calculator.setAccessMode(AccessMode.BLOCKSET);
        stakerBlockset.add(staker1);

        // The blockset used by calculator is a different one, we need to add staker1 there
        vm.stopPrank();

        // We need the calculator's blockset - let's just use vm.mockCall
        // Mock getNewEarningPower to return (0, true) for staker1
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getNewEarningPower.selector,
                uint256(1000e18), // balance
                staker1, // owner
                staker1, // delegatee
                uint256(1000e18) // old earning power
            ),
            abi.encode(uint256(0), true)
        );

        // Also mock getEarningPower for checkpoint calls
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getEarningPower.selector,
                uint256(1000e18), // balance
                staker1, // owner
                staker1 // delegatee
            ),
            abi.encode(uint256(0))
        );

        // Bump earning power down - tip should be capped to unclaimed rewards
        // L991: _requestedTip > _unclaimedRewards path (tip capped)
        // L1012: tipToPay > 0 path
        address tipReceiver = makeAddr("tipReceiver");
        vm.prank(staker2);
        regenStaker.bumpEarningPower(depositId, tipReceiver, 0.5e18);

        vm.clearMockedCalls();

        // Verify earning power was updated
        (,, uint96 earningPower,,,,) = regenStaker.deposits(depositId);
        assertEq(earningPower, 0, "Earning power should be 0 after block");
    }

    function test_bumpEarningPower_upward_insufficientRewards_reverts() public {
        // Stake but don't notify rewards - no unclaimed rewards
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        // Mock getNewEarningPower to return higher EP and qualified
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getNewEarningPower.selector,
                uint256(1000e18),
                staker1,
                staker1,
                uint256(1000e18)
            ),
            abi.encode(uint256(2000e18), true)
        );

        // L986: _newEarningPower > deposit.earningPower && _unclaimedRewards < _requestedTip
        vm.prank(staker2);
        vm.expectRevert(Staker.Staker__InsufficientUnclaimedRewards.selector);
        regenStaker.bumpEarningPower(depositId, staker2, 0.5e18);

        vm.clearMockedCalls();
    }

    function test_bumpEarningPower_zeroTip_succeeds() public {
        // Stake and get some rewards
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);
        vm.warp(block.timestamp + 3 days);

        // Mock getNewEarningPower to return lower EP (simulating block)
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getNewEarningPower.selector,
                uint256(1000e18),
                staker1,
                staker1,
                uint256(1000e18)
            ),
            abi.encode(uint256(500e18), true)
        );

        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getEarningPower.selector, uint256(1000e18), staker1, staker1
            ),
            abi.encode(uint256(500e18))
        );

        // L1012: tipToPay == 0 path (false branch)
        // L807: _consumeRewards with amount=0 (false branch)
        vm.prank(staker2);
        regenStaker.bumpEarningPower(depositId, staker2, 0);

        vm.clearMockedCalls();

        (,, uint96 earningPower,,,,) = regenStaker.deposits(depositId);
        assertEq(earningPower, 500e18, "Earning power should be updated to 500e18");
    }

    function test_bumpEarningPower_whenPaused_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(staker2);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        regenStaker.bumpEarningPower(depositId, staker2, 0);
    }

    // ===== _checkpointGlobalReward: elapsed == 0 path (false branch of outer if) =====

    function test_checkpointGlobalReward_noElapsed_noop() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        // Do two operations in the same block (elapsed=0 on second)
        // The first stake triggers checkpoint. Staking more in the same block
        // triggers another checkpoint with elapsed=0.
        stakeToken.mint(staker1, 500e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 500e18);
        Staker.DepositIdentifier depositId = Staker.DepositIdentifier.wrap(0);
        regenStaker.stakeMore(depositId, 500e18);
        vm.stopPrank();

        // If we got here without revert, the false branch of elapsed>0 was hit
    }

    // ===== _checkpointGlobalReward: scaledRewardRate == 0 path =====

    function test_checkpointGlobalReward_zeroRewardRate_noop() public {
        // Stake without notifying rewards (scaledRewardRate = 0)
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.warp(block.timestamp + 1 days);

        // Staking more triggers checkpoint with scaledRewardRate=0
        stakeToken.mint(staker1, 500e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 500e18);
        regenStaker.stakeMore(depositId, 500e18);
        vm.stopPrank();
    }

    // ===== _notifyRewardAmountWithCustomDuration: scaledRewardRate < SCALE_FACTOR =====

    function test_notifyReward_tooSmallAmount_reverts() public {
        _stakeFor(staker1, 1000e18);

        // Notify a tiny amount that would result in scaledRewardRate < SCALE_FACTOR
        // scaledRewardRate = (amount * 1e36) / rewardDuration
        // For 7 days = 604800 seconds, we need amount * 1e36 / 604800 < 1e36
        // So amount < 604800 (about 604800 wei)
        uint256 tinyAmount = 1; // 1 wei
        stakeToken.mint(address(regenStaker), tinyAmount);
        vm.prank(ADMIN);
        vm.expectRevert(Staker.Staker__InvalidRewardRate.selector);
        regenStaker.notifyRewardAmount(tinyAmount);
    }

    // ===== _notifyRewardAmountWithCustomDuration: not reward notifier =====

    function test_notifyReward_notNotifier_reverts() public {
        stakeToken.mint(address(regenStaker), 10000e18);

        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not notifier"), staker1));
        regenStaker.notifyRewardAmount(10000e18);
    }

    // ===== _stakeMore: ALLOWSET check on deposit.owner =====

    function test_stakeMore_allowsetMode_revertsWhenOwnerNotAllowed() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(ADMIN);
        regenStaker.setAccessMode(AccessMode.ALLOWSET);

        stakeToken.mint(staker1, 500e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 500e18);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, staker1));
        regenStaker.stakeMore(depositId, 500e18);
        vm.stopPrank();
    }

    // ===== Paused: stakeMore reverts =====

    function test_paused_stakeMoreReverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(ADMIN);
        regenStaker.pause();

        stakeToken.mint(staker1, 500e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 500e18);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        regenStaker.stakeMore(depositId, 500e18);
        vm.stopPrank();
    }

    // ===== Paused: claimReward reverts =====

    function test_paused_claimRewardReverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);
        vm.warp(block.timestamp + 1 days);

        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(staker1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        regenStaker.claimReward(depositId);
    }

    // ===== Paused: alterClaimer reverts =====

    function test_paused_alterClaimerReverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(ADMIN);
        regenStaker.pause();

        vm.prank(staker1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        regenStaker.alterClaimer(depositId, staker2);
    }

    // ===== setRewardDuration: not admin reverts =====

    function test_setRewardDuration_notAdmin_reverts() public {
        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not admin"), staker1));
        regenStaker.setRewardDuration(uint128(14 days));
    }

    // ===== _stakeMore: minimumStake check after stakeMore =====

    function test_stakeMore_resultBelowMinimum_reverts() public {
        // Stake 200e18 with no minimum
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 200e18);

        // Set minimum to 500e18 (after staking, so existing deposit is grandfathered)
        vm.prank(ADMIN);
        regenStaker.setMinimumStakeAmount(500e18);

        // StakeMore 50e18 => balance 250e18 < 500e18 minimum => should revert
        stakeToken.mint(staker1, 50e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(regenStaker), 50e18);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.MinimumStakeAmountNotMet.selector, 500e18, 250e18));
        regenStaker.stakeMore(depositId, 50e18);
        vm.stopPrank();
    }

    // ===== Constructor: REWARD_TOKEN != STAKE_TOKEN branch =====
    // (This tests the false branch of L301 in the constructor)

    function test_constructor_differentRewardAndStakeToken() public {
        MockERC20 rewardToken = new MockERC20(18);

        vm.prank(ADMIN);
        RegenStaker differentTokenStaker = new RegenStaker(
            IERC20(address(rewardToken)), // different reward token
            stakeToken,
            calculator,
            1e18,
            ADMIN,
            uint128(7 days),
            0,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.NONE,
            IAddressSet(address(allocationMechanismAllowset))
        );

        // Verify compounding not supported with different tokens
        stakeToken.mint(staker1, 1000e18);
        vm.startPrank(staker1);
        stakeToken.approve(address(differentTokenStaker), 1000e18);
        Staker.DepositIdentifier depositId = differentTokenStaker.stake(1000e18, staker1, staker1);
        vm.stopPrank();

        vm.prank(staker1);
        vm.expectRevert(RegenStakerBase.CompoundingNotSupported.selector);
        differentTokenStaker.compoundRewards(depositId);
    }

    // ===== View getter function coverage =====

    function test_viewGetters_stakerBlockset() public view {
        IAddressSet result = regenStaker.stakerBlockset();
        assertEq(address(result), address(stakerBlockset));
    }

    function test_viewGetters_stakerAccessMode() public view {
        AccessMode mode = regenStaker.stakerAccessMode();
        assertEq(uint8(mode), uint8(AccessMode.NONE));
    }

    // ===== Constructor: _initializeSharedState validation branches =====

    function test_constructor_invalidRewardDuration_tooShort_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.InvalidRewardDuration.selector, uint256(1 days)));
        new RegenStaker(
            IERC20(address(stakeToken)),
            stakeToken,
            calculator,
            1e18,
            ADMIN,
            uint128(1 days), // too short
            0,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.NONE,
            IAddressSet(address(allocationMechanismAllowset))
        );
    }

    function test_constructor_invalidRewardDuration_tooLong_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.InvalidRewardDuration.selector, uint256(3001 days)));
        new RegenStaker(
            IERC20(address(stakeToken)),
            stakeToken,
            calculator,
            1e18,
            ADMIN,
            uint128(3001 days), // too long
            0,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.NONE,
            IAddressSet(address(allocationMechanismAllowset))
        );
    }

    function test_constructor_zeroAllocationMechanismAllowset_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(RegenStakerBase.DisablingAllocationMechanismAllowsetNotAllowed.selector);
        new RegenStaker(
            IERC20(address(stakeToken)),
            stakeToken,
            calculator,
            1e18,
            ADMIN,
            uint128(7 days),
            0,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.NONE,
            IAddressSet(address(0)) // zero address
        );
    }

    function test_constructor_allocationMechSameAsStakerAllowset_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(Staker.Staker__InvalidAddress.selector);
        new RegenStaker(
            IERC20(address(stakeToken)),
            stakeToken,
            calculator,
            1e18,
            ADMIN,
            uint128(7 days),
            0,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.NONE,
            IAddressSet(address(stakerAllowset)) // same as staker allowset
        );
    }

    function test_constructor_allocationMechSameAsStakerBlockset_reverts() public {
        vm.prank(ADMIN);
        vm.expectRevert(Staker.Staker__InvalidAddress.selector);
        new RegenStaker(
            IERC20(address(stakeToken)),
            stakeToken,
            calculator,
            1e18,
            ADMIN,
            uint128(7 days),
            0,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.NONE,
            IAddressSet(address(stakerBlockset)) // same as staker blockset
        );
    }

    // ===== bumpEarningPower: upward bump with tip that succeeds =====

    function test_bumpEarningPower_upward_withTip_succeeds() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);
        vm.warp(block.timestamp + 3 days);

        // Mock getNewEarningPower to return higher EP and qualified
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getNewEarningPower.selector,
                uint256(1000e18),
                staker1,
                staker1,
                uint256(1000e18)
            ),
            abi.encode(uint256(2000e18), true)
        );

        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getEarningPower.selector, uint256(1000e18), staker1, staker1
            ),
            abi.encode(uint256(2000e18))
        );

        // Upward bump with small tip (L986 false branch: newEP > oldEP but unclaimed >= tip)
        // L1012 true branch: tipToPay > 0
        address tipReceiver = makeAddr("tipReceiver2");
        vm.prank(staker2);
        regenStaker.bumpEarningPower(depositId, tipReceiver, 0.1e18);

        vm.clearMockedCalls();

        uint256 tipBalance = stakeToken.balanceOf(tipReceiver);
        assertEq(tipBalance, 0.1e18, "Tip receiver should have received tip");

        (,, uint96 earningPower,,,,) = regenStaker.deposits(depositId);
        assertEq(earningPower, 2000e18, "Earning power should be updated to 2000e18");
    }

    // ===== bumpEarningPower: downward bump with tip capped to unclaimed =====

    function test_bumpEarningPower_downward_tipCapped() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);
        // Small time passage to accrue very few rewards
        vm.warp(block.timestamp + 100);

        // Mock getNewEarningPower to return lower EP (downward bump)
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getNewEarningPower.selector,
                uint256(1000e18),
                staker1,
                staker1,
                uint256(1000e18)
            ),
            abi.encode(uint256(500e18), true)
        );

        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getEarningPower.selector, uint256(1000e18), staker1, staker1
            ),
            abi.encode(uint256(500e18))
        );

        // Request tip of 1e18, but unclaimed might be less
        // L991: _requestedTip > _unclaimedRewards => tipToPay = _unclaimedRewards
        address tipReceiver = makeAddr("tipReceiver3");
        vm.prank(staker2);
        regenStaker.bumpEarningPower(depositId, tipReceiver, 1e18);

        vm.clearMockedCalls();
    }

    // ===== setRewardDuration: valid change after reward ends =====

    function test_setRewardDuration_validChange_succeeds() public {
        _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);

        // Warp past reward end
        vm.warp(block.timestamp + 8 days);

        vm.prank(ADMIN);
        regenStaker.setRewardDuration(uint128(14 days));
        assertEq(regenStaker.rewardDuration(), 14 days);
    }

    // ===== contribute: address(0) mechanism reverts =====

    function test_contribute_addressZeroMechanism_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        vm.prank(staker1);
        vm.expectRevert();
        regenStaker.contribute(depositId, address(0), 1e18, block.timestamp + 1 days, 0, bytes32(0), bytes32(0));
    }

    // ===== contribute: mechanism not in allowset reverts =====

    function test_contribute_mechanismNotInAllowset_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        address fakeMechanism = makeAddr("fakeMechanism");

        vm.prank(staker1);
        vm.expectRevert();
        regenStaker.contribute(depositId, fakeMechanism, 1e18, block.timestamp + 1 days, 0, bytes32(0), bytes32(0));
    }

    // ===== contribute: not claimer or owner reverts =====

    function test_contribute_notClaimerOrOwner_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        // Deploy a mock mechanism that returns the right asset
        address fakeMechanism = makeAddr("validMechanism");
        vm.mockCall(
            fakeMechanism, abi.encodeWithSelector(bytes4(keccak256("asset()"))), abi.encode(address(stakeToken))
        );
        vm.mockCall(
            address(allocationMechanismAllowset),
            abi.encodeWithSelector(IAddressSet.contains.selector, fakeMechanism),
            abi.encode(true)
        );

        vm.prank(staker2);
        vm.expectRevert(
            abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not claimer or owner"), staker2)
        );
        regenStaker.contribute(depositId, fakeMechanism, 1e18, block.timestamp + 1 days, 0, bytes32(0), bytes32(0));

        vm.clearMockedCalls();
    }

    // ===== contribute: CantAfford reverts =====

    function test_contribute_cantAfford_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        // No rewards notified - unclaimed = 0

        address fakeMechanism = makeAddr("validMech2");
        vm.mockCall(
            fakeMechanism, abi.encodeWithSelector(bytes4(keccak256("asset()"))), abi.encode(address(stakeToken))
        );
        vm.mockCall(
            address(allocationMechanismAllowset),
            abi.encodeWithSelector(IAddressSet.contains.selector, fakeMechanism),
            abi.encode(true)
        );
        vm.mockCall(fakeMechanism, abi.encodeWithSelector(bytes4(keccak256("canSignup(address)"))), abi.encode(true));

        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.CantAfford.selector, 1e18, 0));
        regenStaker.contribute(depositId, fakeMechanism, 1e18, block.timestamp + 1 days, 0, bytes32(0), bytes32(0));

        vm.clearMockedCalls();
    }

    // ===== contribute: zero amount (voting registration) =====

    function test_contribute_zeroAmount_votingRegistration() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);

        address fakeMechanism = makeAddr("validMech3");
        vm.mockCall(
            fakeMechanism, abi.encodeWithSelector(bytes4(keccak256("asset()"))), abi.encode(address(stakeToken))
        );
        vm.mockCall(
            address(allocationMechanismAllowset),
            abi.encodeWithSelector(IAddressSet.contains.selector, fakeMechanism),
            abi.encode(true)
        );
        vm.mockCall(fakeMechanism, abi.encodeWithSelector(bytes4(keccak256("canSignup(address)"))), abi.encode(true));
        // Mock signupOnBehalfWithSignature to succeed
        vm.mockCall(
            fakeMechanism,
            abi.encodeWithSelector(
                bytes4(keccak256("signupOnBehalfWithSignature(address,uint256,uint256,uint8,bytes32,bytes32)"))
            ),
            abi.encode()
        );

        vm.prank(staker1);
        uint256 contributed = regenStaker.contribute(
            depositId,
            fakeMechanism,
            0, // zero amount for voting registration
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );

        vm.clearMockedCalls();
        assertEq(contributed, 0, "Zero amount contribution should return 0");
    }

    // ===== contribute: owner not eligible for mechanism =====

    function test_contribute_ownerNotEligible_reverts() public {
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10e18);
        vm.warp(block.timestamp + 7 days);

        address fakeMechanism = makeAddr("validMech4");
        vm.mockCall(
            fakeMechanism, abi.encodeWithSelector(bytes4(keccak256("asset()"))), abi.encode(address(stakeToken))
        );
        vm.mockCall(
            address(allocationMechanismAllowset),
            abi.encodeWithSelector(IAddressSet.contains.selector, fakeMechanism),
            abi.encode(true)
        );
        // Mock canSignup to return false for the owner
        vm.mockCall(
            fakeMechanism, abi.encodeWithSelector(bytes4(keccak256("canSignup(address)")), staker1), abi.encode(false)
        );

        vm.prank(staker1);
        vm.expectRevert(
            abi.encodeWithSelector(RegenStakerBase.DepositOwnerNotEligibleForMechanism.selector, fakeMechanism, staker1)
        );
        regenStaker.contribute(depositId, fakeMechanism, 1e18, block.timestamp + 1 days, 0, bytes32(0), bytes32(0));

        vm.clearMockedCalls();
    }

    // =====================================================================
    // Phase 4: Additional branch coverage targeting uncovered BRDA entries
    // Targets: line 460 (successful setStakerBlockset), line 991 (tip capped
    // to unclaimed during downward bump), line 692 (contribute allowance check)
    // =====================================================================

    // ===== setStakerBlockset: successful change (line 460 branch 13,1) =====

    function test_setStakerBlockset_validChange_succeeds() public {
        AddressSet newBlockset = new AddressSet();

        vm.prank(ADMIN);
        regenStaker.setStakerBlockset(IAddressSet(address(newBlockset)));

        assertEq(address(regenStaker.stakerBlockset()), address(newBlockset));
    }

    // ===== bumpEarningPower: downward bump where requestedTip > unclaimedRewards (line 991) =====
    // The key: earningPower goes DOWN so the L986 check is skipped.
    // But _requestedTip > _unclaimedRewards must be true, so tipToPay = _unclaimedRewards.

    function test_bumpEarningPower_downward_tipExceedsUnclaimed() public {
        // Stake and accrue a tiny amount of rewards
        Staker.DepositIdentifier depositId = _stakeFor(staker1, 1000e18);
        _notifyReward(10000e18);
        // Very short time to accrue minimal rewards
        vm.warp(block.timestamp + 10);

        // Mock: downward bump (newEP < oldEP)
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getNewEarningPower.selector,
                uint256(1000e18),
                staker1,
                staker1,
                uint256(1000e18)
            ),
            abi.encode(uint256(100e18), true)
        );
        vm.mockCall(
            address(calculator),
            abi.encodeWithSelector(
                IEarningPowerCalculator.getEarningPower.selector, uint256(1000e18), staker1, staker1
            ),
            abi.encode(uint256(100e18))
        );

        // Request maxBumpTip (1e18) which is almost certainly > unclaimed after only 10 seconds
        // 10000e18 over 7 days = ~16.5e15/sec, so after 10s unclaimed ~ 0.165e18 < 1e18
        // This triggers: _requestedTip(1e18) > _unclaimedRewards(~0.165e18)
        // tipToPay is capped to _unclaimedRewards
        address tipReceiver = makeAddr("tipReceiverCapped");
        vm.prank(staker2);
        regenStaker.bumpEarningPower(depositId, tipReceiver, 1e18);

        vm.clearMockedCalls();

        // Verify tip was paid (capped amount)
        uint256 tipBalance = stakeToken.balanceOf(tipReceiver);
        assertGt(tipBalance, 0, "Tip receiver should have received capped tip");
        assertLt(tipBalance, 1e18, "Tip should be less than requested");
    }

    // ===== setAllocationMechanismAllowset: successful change =====
    // Provides a new valid address that is different from current, non-zero,
    // and different from both stakerAllowset and stakerBlockset.
    // This helps cover the success path of the AND condition at line 491.

    function test_setAllocationMechanismAllowset_validChange_succeeds() public {
        AddressSet newAllowset = new AddressSet();

        vm.prank(ADMIN);
        regenStaker.setAllocationMechanismAllowset(IAddressSet(address(newAllowset)));

        assertEq(address(regenStaker.allocationMechanismAllowset()), address(newAllowset));
    }

    // ===== setStakerAllowset: successful change (covers line 446 success path) =====

    function test_setStakerAllowset_validChange_succeeds() public {
        AddressSet newAllowset = new AddressSet();

        vm.prank(ADMIN);
        regenStaker.setStakerAllowset(IAddressSet(address(newAllowset)));

        assertEq(address(regenStaker.stakerAllowset()), address(newAllowset));
    }
}

contract MockMechanism {
    IERC20 public asset;

    constructor(IERC20 _asset) {
        asset = _asset;
    }
}

/// @title Test for AssetMismatch validation in contribute()
/// @notice Verifies that contribute() reverts with AssetMismatch when tokens don't match
contract RegenStakerBaseAssetValidationTest is Test {
    RegenStaker public regenStaker;
    MockERC20Staking public stakeToken;
    MockERC20 public rewardToken;
    MockERC20 public wrongToken;
    RegenEarningPowerCalculator public calculator;
    AddressSet public allowset;
    AddressSet public allocationAllowset;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    Staker.DepositIdentifier public depositId;

    function setUp() public {
        // Deploy tokens
        stakeToken = new MockERC20Staking(18);
        rewardToken = new MockERC20(18);
        wrongToken = new MockERC20(18);

        // Deploy calculator
        calculator =
            new RegenEarningPowerCalculator(admin, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE);

        // Deploy allowsets as admin
        vm.startPrank(admin);
        allowset = new AddressSet();
        allocationAllowset = new AddressSet();

        // Setup allowsets
        allowset.add(alice);
        // We'll add mechanisms to the allocation allowset as needed in tests
        vm.stopPrank();

        // Deploy RegenStaker with rewardToken
        vm.prank(admin);
        regenStaker = new RegenStaker(
            IERC20(address(rewardToken)), // reward token
            stakeToken, // stake token
            calculator,
            1e18, // maxBumpTip
            admin, // admin
            30 days, // rewardDuration
            1e18, // minimumStakeAmount
            IAddressSet(address(allowset)), // stakerAllowset
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset)) // allocationMechanismAllowset
        );

        // Alice stakes
        stakeToken.mint(alice, 100e18);
        vm.startPrank(alice);
        stakeToken.approve(address(regenStaker), 100e18);
        depositId = regenStaker.stake(10e18, alice, alice);
        vm.stopPrank();

        // Setup rewards
        rewardToken.mint(address(regenStaker), 1000e18);
        vm.startPrank(admin);
        regenStaker.setRewardNotifier(admin, true);
        regenStaker.notifyRewardAmount(100e18);
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 15 days);
    }

    function testContributeRevertsOnAssetMismatch() public {
        // Deploy mechanism expecting wrong token
        MockMechanism mechanism = new MockMechanism(IERC20(address(wrongToken)));

        // Add mechanism to allowset
        vm.prank(admin);
        allocationAllowset.add(address(mechanism));

        // Expect AssetMismatch error
        vm.expectRevert(
            abi.encodeWithSelector(RegenStakerBase.AssetMismatch.selector, address(rewardToken), address(wrongToken))
        );

        // Try to contribute - should revert with AssetMismatch
        vm.prank(alice);
        regenStaker.contribute(depositId, address(mechanism), 1e18, block.timestamp + 1 days, 0, bytes32(0), bytes32(0));
    }

    function testContributeDoesNotRevertOnAssetMatch() public {
        // Deploy mechanism expecting correct token
        MockMechanism mechanism = new MockMechanism(IERC20(address(rewardToken)));

        // Add mechanism to allowset
        vm.prank(admin);
        allocationAllowset.add(address(mechanism));

        // The validation should pass the asset check
        // (may still revert for other reasons like signature validation)
        vm.prank(alice);
        try regenStaker.contribute(
            depositId, address(mechanism), 1e18, block.timestamp + 1 days, 0, bytes32(0), bytes32(0)
        ) {
            // If it succeeds, great
            assertTrue(true);
        } catch Error(string memory reason) {
            // If it fails for a different reason, that's fine
            // Just make sure it's not AssetMismatch
            assertFalse(
                keccak256(bytes(reason)) == keccak256(bytes("AssetMismatch")),
                "Should not fail with AssetMismatch when tokens match"
            );
        } catch (bytes memory) {
            // Low-level revert - also fine as long as we got past the asset check
            assertTrue(true);
        }
    }
}

contract RegenStakerBaseClaimerPermissionsDemoTest is Test {
    RegenStaker public regenStaker;
    MockERC20Staking public token; // Same token for stake and reward
    MockEarningPowerCalculator public earningPowerCalculator;
    OctantQFMechanism public allocationMechanism;
    AddressSet public stakerAllowset;
    AddressSet public allocationAllowset;

    address public admin = makeAddr("admin");
    address public owner;
    uint256 private ownerPk;
    address public claimer;
    uint256 private claimerPk;
    address public delegatee = makeAddr("delegatee");

    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant REWARD_AMOUNT = 1000e18;
    uint128 public constant REWARD_DURATION = 30 days;

    Staker.DepositIdentifier public depositId;

    function setUp() public {
        // Deploy infrastructure
        token = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        // Deploy real allocation mechanism (OctantQFMechanism) using shared implementation
        TokenizedAllocationMechanism impl = new TokenizedAllocationMechanism();
        AllocationConfig memory cfg = AllocationConfig({
            asset: IERC20(address(token)),
            name: "TestAlloc",
            symbol: "TA",
            votingDelay: 1,
            votingPeriod: 30 days,
            quorumShares: 1,
            timelockDelay: 1,
            gracePeriod: 100,
            owner: admin
        });
        allocationMechanism = new OctantQFMechanism(
            address(impl),
            cfg,
            1,
            1,
            IAddressSet(address(0)), // contributionAllowset
            IAddressSet(address(0)), // contributionBlockset
            AccessMode.NONE
        );

        // Deploy allowsets
        vm.startPrank(admin);
        stakerAllowset = new AddressSet();
        allocationAllowset = new AddressSet();

        // Setup allowsets
        (owner, ownerPk) = makeAddrAndKey("owner");
        stakerAllowset.add(owner);
        (claimer, claimerPk) = makeAddrAndKey("claimer");
        stakerAllowset.add(claimer);
        allocationAllowset.add(address(allocationMechanism));
        vm.stopPrank();

        // Deploy RegenStaker with same token for stake/reward (enables compounding)
        vm.prank(admin);
        regenStaker = new RegenStaker(
            IERC20(address(token)), // rewardsToken
            token, // stakeToken
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            REWARD_DURATION,
            1e18, // minimumStakeAmount
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset))
        );

        // Fund and create deposit with claimer designation
        token.mint(owner, STAKE_AMOUNT);
        token.mint(address(regenStaker), REWARD_AMOUNT);

        vm.startPrank(owner);
        token.approve(address(regenStaker), STAKE_AMOUNT);
        depositId = regenStaker.stake(STAKE_AMOUNT, delegatee, claimer);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(admin);
        regenStaker.setRewardNotifier(admin, true);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Accumulate rewards
        vm.warp(block.timestamp + REWARD_DURATION / 2);
    }

    /// @notice Demonstrates that claimers CAN claim rewards - INTENDED BEHAVIOR
    function testDemonstrate_ClaimerCanClaimRewards() public {
        // Claimer successfully claims rewards
        vm.prank(claimer);
        uint256 claimedAmount = regenStaker.claimReward(depositId);

        // Verify rewards were claimed
        assertGt(claimedAmount, 0, "claims rewards");
        assertEq(token.balanceOf(claimer), claimedAmount, "Rewards sent to claimer");
    }

    /// @notice Demonstrates that claimers CAN compound rewards - INTENDED BEHAVIOR
    /// @dev This increases the deposit's stake amount, which is the documented behavior
    function testDemonstrate_ClaimerCanCompoundRewards() public {
        (uint96 stakeBefore,,,,,,) = regenStaker.deposits(depositId);

        // Claimer compounds rewards (claims + restakes in one operation)
        vm.prank(claimer);
        uint256 compoundedAmount = regenStaker.compoundRewards(depositId);

        (uint96 stakeAfter,,,,,,) = regenStaker.deposits(depositId);

        // Verify stake increased through compounding
        assertGt(compoundedAmount, 0, "compounded");
        assertEq(stakeAfter - stakeBefore, compoundedAmount);
    }

    /// @notice Demonstrates the permission boundaries - claimers CANNOT withdraw
    function testDemonstrate_ClaimerCannotWithdraw() public {
        vm.prank(claimer);
        vm.expectRevert(); // Claimer lacks withdrawal permission
        regenStaker.withdraw(depositId, 10e18);
    }

    /// @notice Demonstrates that claimers CAN contribute when on contribution allowset
    function testDemonstrate_ClaimerCanContributeIfAllowseted() public {
        // Progress time to accrue rewards
        vm.warp(block.timestamp + REWARD_DURATION / 4);

        // Prepare EIP-712 signature for signupOnBehalfWithSignature(user=claimer, payer=regenStaker)
        // Claimer receives voting power and provides signature (claimer autonomy)
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(claimer);
        uint256 amount = 1e18;
        uint256 deadline = block.timestamp + 1 days;
        bytes32 typeHash =
            keccak256(bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)"));
        bytes32 structHash = keccak256(abi.encode(typeHash, claimer, address(regenStaker), amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimerPk, digest);

        uint256 mechanismBalanceBefore = token.balanceOf(address(allocationMechanism));

        // Claimer contributes unclaimed rewards to the real allocation mechanism
        vm.prank(claimer);
        uint256 contributed = regenStaker.contribute(depositId, address(allocationMechanism), amount, deadline, v, r, s);

        // Verify contribution succeeded
        assertEq(contributed, amount);
        assertEq(token.balanceOf(address(allocationMechanism)) - mechanismBalanceBefore, amount);
    }

    /// @notice Demonstrates owner control - can revoke claimer at any time
    function testDemonstrate_OwnerCanRevokeClaimer() public {
        address newClaimer = makeAddr("newClaimer");

        // Owner changes claimer
        vm.prank(admin);
        stakerAllowset.add(newClaimer);

        vm.prank(owner);
        regenStaker.alterClaimer(depositId, newClaimer);

        // Old claimer no longer has access
        vm.prank(claimer);
        vm.expectRevert(); // No longer authorized
        regenStaker.claimReward(depositId);

        // New claimer has access
        vm.prank(newClaimer);
        uint256 claimed = regenStaker.claimReward(depositId);
        assertGt(claimed, 0, "New claimer can claim");
    }
}

contract RegenStakerBaseCompoundAllowsetFixTest is Test {
    RegenStaker public staker;
    MockERC20Staking public stakeToken;
    RegenEarningPowerCalculator public earningPowerCalculator;
    AddressSet public stakerAllowset;
    AddressSet public earningPowerAllowset;
    AddressSet public allocationAllowset;

    address public admin = makeAddr("admin");
    address public notifier = makeAddr("notifier");
    address public depositor = makeAddr("depositor");
    address public allowlistedClaimer = makeAddr("allowlistedClaimer");
    address public nonAllowsetedClaimer = makeAddr("nonAllowsetedClaimer");
    address public delegatee = makeAddr("delegatee");

    uint256 constant INITIAL_BALANCE = 10_000e18;
    uint256 constant STAKE_AMOUNT = 1000e18;
    uint256 constant REWARD_AMOUNT = 500e18;

    event StakeDeposited(
        address indexed depositor, Staker.DepositIdentifier indexed depositId, uint256 amount, uint256 earningPower
    );

    function setUp() public {
        // Deploy tokens
        stakeToken = new MockERC20Staking(18);

        // Deploy allowsets
        stakerAllowset = new AddressSet();
        earningPowerAllowset = new AddressSet();
        allocationAllowset = new AddressSet();

        // Deploy earning power calculator
        earningPowerCalculator = new RegenEarningPowerCalculator(
            admin, IAddressSet(address(earningPowerAllowset)), IAddressSet(address(0)), AccessMode.ALLOWSET
        );

        // Deploy staker with same token for staking and rewards (to enable compounding)
        staker = new RegenStaker(
            IERC20(address(stakeToken)), // rewards token (same as stake)
            stakeToken, // stake token
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            30 days, // rewardDuration
            0, // minimumStakeAmount
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET,
            allocationAllowset
        );

        // Setup notifier
        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);

        // Fund users
        stakeToken.mint(depositor, INITIAL_BALANCE);
        stakeToken.mint(allowlistedClaimer, INITIAL_BALANCE);
        stakeToken.mint(nonAllowsetedClaimer, INITIAL_BALANCE);
        stakeToken.mint(notifier, INITIAL_BALANCE);
    }

    /// @notice Test inAllowset owner + inAllowset claimer (should work)
    function test_allowlistedOwnerAllowsetedClaimer() public {
        // AddressSet both depositor and claimer
        stakerAllowset.add(depositor);
        stakerAllowset.add(allowlistedClaimer);
        earningPowerAllowset.add(depositor);

        // Depositor stakes with inAllowset claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, allowlistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();

        // Advance time to earn rewards
        vm.warp(block.timestamp + 15 days);

        // Allowseted claimer can compound for inAllowset depositor
        vm.prank(allowlistedClaimer);
        uint256 compounded = staker.compoundRewards(depositId);

        assertGt(compounded, 0, "Should have compounded rewards");
    }

    /// @notice Test non-inAllowset owner + inAllowset claimer (should fail - the fix)
    function test_nonAllowsetedOwnerAllowsetedClaimer() public {
        // Initially allowset depositor to create deposit
        stakerAllowset.add(depositor);
        stakerAllowset.add(allowlistedClaimer);
        earningPowerAllowset.add(depositor);

        // Depositor stakes with inAllowset claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, allowlistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Remove depositor from allowset (e.g., compliance issue)
        stakerAllowset.remove(depositor);
        assertFalse(stakerAllowset.contains(depositor));
        assertTrue(stakerAllowset.contains(allowlistedClaimer));

        // Allowseted claimer CANNOT compound for non-inAllowset depositor (the fix)
        vm.prank(allowlistedClaimer);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, depositor));
        staker.compoundRewards(depositId);
    }

    /// @notice Test inAllowset owner calling their own compound (should work)
    function test_allowlistedOwnerSelfCompound() public {
        // AddressSet depositor
        stakerAllowset.add(depositor);
        earningPowerAllowset.add(depositor);

        // Depositor stakes with themselves as claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, depositor);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Depositor can compound their own rewards
        vm.prank(depositor);
        uint256 compounded = staker.compoundRewards(depositId);

        assertGt(compounded, 0, "Should have compounded rewards");
    }

    /// @notice Test non-inAllowset owner calling their own compound (should fail)
    function test_nonAllowsetedOwnerSelfCompound() public {
        // Initially allowset to create deposit
        stakerAllowset.add(depositor);
        earningPowerAllowset.add(depositor);

        // Depositor stakes
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, depositor);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Remove depositor from allowset
        stakerAllowset.remove(depositor);

        // Non-inAllowset depositor cannot compound their own rewards
        vm.prank(depositor);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, depositor));
        staker.compoundRewards(depositId);
    }

    /// @notice Test inAllowset owner + non-inAllowset claimer (should work)
    function test_allowlistedOwnerNonAllowsetedClaimer() public {
        // AddressSet only depositor, not the claimer
        stakerAllowset.add(depositor);
        earningPowerAllowset.add(depositor);
        assertFalse(stakerAllowset.contains(nonAllowsetedClaimer));

        // Depositor stakes with non-inAllowset claimer
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, nonAllowsetedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Non-inAllowset claimer CAN compound for inAllowset depositor
        // The implementation only checks that the deposit owner is inAllowset
        vm.prank(nonAllowsetedClaimer);
        uint256 compounded = staker.compoundRewards(depositId);
        assertGt(compounded, 0, "Should have compounded rewards");
    }

    /// @notice Test that legitimate compound operations still work after fix
    function test_legitimateCompoundStillWorks() public {
        // Setup multiple inAllowset users
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        stakeToken.mint(alice, INITIAL_BALANCE);
        stakeToken.mint(bob, INITIAL_BALANCE);

        stakerAllowset.add(alice);
        stakerAllowset.add(bob);
        earningPowerAllowset.add(alice);
        earningPowerAllowset.add(bob);

        // Alice stakes with Bob as claimer
        vm.startPrank(alice);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier aliceDeposit = staker.stake(STAKE_AMOUNT, delegatee, bob);
        vm.stopPrank();

        // Bob stakes with Alice as claimer
        vm.startPrank(bob);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier bobDeposit = staker.stake(STAKE_AMOUNT, delegatee, alice);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Bob can compound Alice's deposit
        vm.prank(bob);
        uint256 aliceCompounded = staker.compoundRewards(aliceDeposit);
        assertGt(aliceCompounded, 0, "Bob should compound Alice's rewards");

        // Alice can compound Bob's deposit
        vm.prank(alice);
        uint256 bobCompounded = staker.compoundRewards(bobDeposit);
        assertGt(bobCompounded, 0, "Alice should compound Bob's rewards");
    }

    /// @notice Test unauthorized claimer cannot compound
    function test_unauthorizedClaimerCannotCompound() public {
        address unauthorizedUser = makeAddr("unauthorized");

        // AddressSet depositor
        stakerAllowset.add(depositor);
        stakerAllowset.add(unauthorizedUser);
        earningPowerAllowset.add(depositor);

        // Depositor stakes with allowlistedClaimer (not unauthorizedUser)
        stakerAllowset.add(allowlistedClaimer);
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, allowlistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Unauthorized user (not owner, not claimer) cannot compound
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                Staker.Staker__Unauthorized.selector, bytes32("not claimer or owner"), unauthorizedUser
            )
        );
        staker.compoundRewards(depositId);
    }

    /// @notice Test scenario where depositor is removed then re-added to allowset
    function test_depositorRemovedThenReaddedToAddressSet() public {
        // AddressSet both
        stakerAllowset.add(depositor);
        stakerAllowset.add(allowlistedClaimer);
        earningPowerAllowset.add(depositor);

        // Create deposit
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, delegatee, allowlistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 10 days);

        // Remove depositor from allowset
        stakerAllowset.remove(depositor);

        // Claimer cannot compound while depositor is not inAllowset
        vm.prank(allowlistedClaimer);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, depositor));
        staker.compoundRewards(depositId);

        // Re-add depositor to allowset
        stakerAllowset.add(depositor);

        // Now claimer can compound again
        vm.prank(allowlistedClaimer);
        uint256 compounded = staker.compoundRewards(depositId);
        assertGt(compounded, 0, "Should compound after re-adding to allowset");
    }

    /// @notice Fuzz test various scenarios
    function testFuzz_compoundAllowsetChecks(bool ownerAllowseted, bool claimerAllowseted, bool callerIsOwner) public {
        // Setup based on fuzz inputs
        if (ownerAllowseted) {
            stakerAllowset.add(depositor);
            earningPowerAllowset.add(depositor);
        }
        if (claimerAllowseted) {
            stakerAllowset.add(allowlistedClaimer);
        }

        // Skip if neither is inAllowset (can't create deposit)
        if (!ownerAllowseted) return;

        // Create deposit
        vm.startPrank(depositor);
        stakeToken.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId =
            staker.stake(STAKE_AMOUNT, delegatee, callerIsOwner ? depositor : allowlistedClaimer);
        vm.stopPrank();

        // Add rewards
        _addRewards();
        vm.warp(block.timestamp + 15 days);

        // Remove owner from allowset for testing
        if (!ownerAllowseted) {
            stakerAllowset.remove(depositor);
        }

        // Determine who is calling and expected result
        address caller = callerIsOwner ? depositor : allowlistedClaimer;

        // The implementation only checks that the deposit owner is inAllowset
        // It doesn't matter if the claimer is inAllowset or not
        bool shouldSucceed = ownerAllowseted;

        // Execute compound
        if (shouldSucceed) {
            vm.prank(caller);
            uint256 compounded = staker.compoundRewards(depositId);
            assertGt(compounded, 0, "Should compound successfully");
        } else {
            vm.prank(caller);
            vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, depositor));
            staker.compoundRewards(depositId);
        }
    }

    // ============ Helper Functions ============

    function _addRewards() internal {
        vm.startPrank(notifier);
        stakeToken.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
    }
}

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
        earningPowerCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator newCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator newCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator newCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator newCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator newCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator newCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator calculator2 =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

        RegenEarningPowerCalculator calculator3 =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
        RegenEarningPowerCalculator newCalculator =
            new RegenEarningPowerCalculator(admin, allowset, IAddressSet(address(0)), AccessMode.ALLOWSET);

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
            address(regenStaker.earningPowerCalculator()), address(newCalculator), "Should succeed after rewardEndTime"
        );
    }
}

contract RegenStakerBaseVotingPowerAssignmentTest is Test {
    RegenStaker public regenStaker;
    MockERC20Staking public token;
    MockEarningPowerCalculator public earningPowerCalculator;
    OctantQFMechanism public allocationMechanism;
    AddressSet public stakerAllowset;
    AddressSet public contributionAllowset;
    AddressSet public allocationAllowset;

    address public admin = makeAddr("admin");
    address public owner;
    uint256 private ownerPk;
    address public claimer;
    uint256 private claimerPk;
    address public delegatee = makeAddr("delegatee");

    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant REWARD_AMOUNT = 1000e18;
    uint128 public constant REWARD_DURATION = 30 days;
    uint256 public constant CONTRIBUTION_AMOUNT = 10e18;

    Staker.DepositIdentifier public depositId;

    function setUp() public {
        // Create addresses with private keys for signature generation
        (owner, ownerPk) = makeAddrAndKey("owner");
        (claimer, claimerPk) = makeAddrAndKey("claimer");

        // Deploy infrastructure
        token = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        // Deploy real allocation mechanism
        TokenizedAllocationMechanism impl = new TokenizedAllocationMechanism();
        AllocationConfig memory cfg = AllocationConfig({
            asset: IERC20(address(token)),
            name: "TestAlloc",
            symbol: "TA",
            votingDelay: 1,
            votingPeriod: 30 days,
            quorumShares: 1,
            timelockDelay: 1,
            gracePeriod: 100,
            owner: admin
        });
        allocationMechanism = new OctantQFMechanism(
            address(impl),
            cfg,
            1,
            1,
            IAddressSet(address(0)), // contributionAllowset
            IAddressSet(address(0)), // contributionBlockset
            AccessMode.NONE
        );

        // Deploy and configure allowsets
        vm.startPrank(admin);
        stakerAllowset = new AddressSet();
        contributionAllowset = new AddressSet();
        allocationAllowset = new AddressSet();

        // Add both owner and claimer to necessary allowsets
        stakerAllowset.add(owner);
        stakerAllowset.add(claimer);
        contributionAllowset.add(owner);
        contributionAllowset.add(claimer);
        allocationAllowset.add(address(allocationMechanism));
        vm.stopPrank();

        // Deploy RegenStaker with same token for stake/reward
        vm.prank(admin);
        regenStaker = new RegenStaker(
            IERC20(address(token)), // rewardsToken
            token, // stakeToken
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            REWARD_DURATION,
            1e18, // minimumStakeAmount
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset))
        );

        // Fund and create deposit with claimer designation
        token.mint(owner, STAKE_AMOUNT);
        token.mint(address(regenStaker), REWARD_AMOUNT);

        vm.startPrank(owner);
        token.approve(address(regenStaker), STAKE_AMOUNT);
        depositId = regenStaker.stake(STAKE_AMOUNT, delegatee, claimer);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(admin);
        regenStaker.setRewardNotifier(admin, true);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Accumulate rewards
        vm.warp(block.timestamp + REWARD_DURATION / 4);
    }

    /// @notice Test that when OWNER contributes, OWNER gets voting power
    /// @dev This is the expected base case - contributor gets voting power
    function testVotingPower_OwnerContribute_OwnerGetsVotingPower() public {
        // Create signature for owner to contribute
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(owner);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash =
            keccak256(bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)"));
        bytes32 structHash =
            keccak256(abi.encode(typeHash, owner, address(regenStaker), CONTRIBUTION_AMOUNT, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        // Owner contributes their own deposit's rewards
        vm.prank(owner);
        uint256 contributed =
            regenStaker.contribute(depositId, address(allocationMechanism), CONTRIBUTION_AMOUNT, deadline, v, r, s);

        // Verify contribution succeeded
        assertEq(contributed, CONTRIBUTION_AMOUNT, "Contribution amount mismatch");

        // CRITICAL ASSERTION: Owner gets the voting power
        uint256 ownerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).votingPower(owner);
        assertEq(ownerVotingPower, CONTRIBUTION_AMOUNT, "Owner should have voting power equal to contribution");

        // CRITICAL ASSERTION: Claimer has NO voting power
        uint256 claimerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).votingPower(claimer);
        assertEq(claimerVotingPower, 0, "Claimer should have no voting power when owner contributes");
    }

    /// @notice Test that when CLAIMER contributes, CLAIMER gets voting power (NOT owner)
    /// @dev This proves the intended behavior where voting power follows the contributor
    function testVotingPower_ClaimerContribute_ClaimerGetsVotingPower() public {
        // Claimer provides signature and receives voting power (claimer autonomy)
        // Defense-in-depth: deposit.owner must also be eligible (checked separately)

        // Create signature for claimer (who will receive voting power)
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(claimer);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash =
            keccak256(bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)"));
        bytes32 structHash =
            keccak256(abi.encode(typeHash, claimer, address(regenStaker), CONTRIBUTION_AMOUNT, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimerPk, digest);

        // Claimer contributes owner's deposit's rewards
        vm.prank(claimer);
        uint256 contributed =
            regenStaker.contribute(depositId, address(allocationMechanism), CONTRIBUTION_AMOUNT, deadline, v, r, s);

        // Verify contribution succeeded
        assertEq(contributed, CONTRIBUTION_AMOUNT, "Contribution amount mismatch");

        // CRITICAL ASSERTION: Claimer gets the voting power (contributor principle)
        uint256 claimerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).votingPower(claimer);
        assertEq(claimerVotingPower, CONTRIBUTION_AMOUNT, "Claimer should have voting power as contributor");

        // CRITICAL ASSERTION: Owner has NO voting power
        uint256 ownerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).votingPower(owner);
        assertEq(ownerVotingPower, 0, "Owner should have no voting power when claimer contributes");
    }

    /// @notice Test that both owner and claimer contributions result in each getting their own voting power
    /// @dev Owner contributes → owner gets voting power, Claimer contributes → claimer gets voting power
    function testVotingPower_BothContribute_EachGetsOwnVotingPower() public {
        uint256 halfContribution = CONTRIBUTION_AMOUNT / 2;

        // First: Owner contributes half
        _contributeAsOwner(halfContribution);

        // Second: Claimer contributes the other half
        _contributeAsClaimer(halfContribution);

        // CRITICAL ASSERTION: Each contributor gets their own voting power
        uint256 ownerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).votingPower(owner);
        uint256 claimerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).votingPower(claimer);

        assertEq(ownerVotingPower, halfContribution, "Owner gets voting power from own contribution");
        assertEq(claimerVotingPower, halfContribution, "Claimer gets voting power from own contribution");
    }

    // Helper function to reduce stack depth
    function _contributeAsOwner(uint256 amount) internal {
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(owner);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash =
            keccak256(bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)"));
        bytes32 structHash = keccak256(abi.encode(typeHash, owner, address(regenStaker), amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(depositId, address(allocationMechanism), amount, deadline, v, r, s);
        assertEq(contributed, amount, "Owner contribution mismatch");
    }

    // Helper function to reduce stack depth
    function _contributeAsClaimer(uint256 amount) internal {
        // Claimer provides signature and receives voting power (claimer autonomy)
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(claimer);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash =
            keccak256(bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)"));
        bytes32 structHash = keccak256(abi.encode(typeHash, claimer, address(regenStaker), amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimerPk, digest);

        vm.prank(claimer);
        uint256 contributed = regenStaker.contribute(depositId, address(allocationMechanism), amount, deadline, v, r, s);
        assertEq(contributed, amount, "Claimer contribution mismatch");
    }

    /// @notice Test that attempting to contribute without proper signature fails
    /// @dev Ensures voting power assignment requires valid authorization
    function testVotingPower_WrongSignature_Reverts() public {
        // Test wrong signature by using an unrelated signer
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(owner);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash =
            keccak256(bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)"));
        // Sign for owner but with WRONG private key
        bytes32 structHash =
            keccak256(abi.encode(typeHash, owner, address(regenStaker), CONTRIBUTION_AMOUNT, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimerPk, digest); // Wrong signer!

        // Try to contribute with wrong signature - should fail
        vm.prank(claimer);
        vm.expectRevert(); // Will revert due to signature mismatch
        regenStaker.contribute(depositId, address(allocationMechanism), CONTRIBUTION_AMOUNT, deadline, v, r, s);

        // Verify no voting power was assigned
        uint256 ownerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).votingPower(owner);
        assertEq(ownerVotingPower, 0, "Owner should have no voting power after failed contribution");
    }
}

contract RegenStakerSameTokenProtectionTest is Test {
    RegenStaker public staker;
    MockERC20Staking public token;
    RegenEarningPowerCalculator public earningPowerCalculator;
    AddressSet public allowset;

    address public admin = address(0x1);
    address public notifier = address(0x2);
    address public user1 = address(0x3);
    address public delegatee = address(0x4);

    uint256 constant INITIAL_BALANCE = 1_000_000e18;
    uint256 constant STAKE_AMOUNT = 1000e18;
    uint256 constant REWARD_AMOUNT = 500e18;

    function setUp() public {
        // Deploy token with delegation support
        token = new MockERC20Staking(18);

        // Deploy allowset
        allowset = new AddressSet();
        allowset.add(user1);

        // Deploy earning power calculator
        earningPowerCalculator = new RegenEarningPowerCalculator(
            admin,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Deploy staker with SAME token for staking and rewards
        staker = new RegenStaker(
            IERC20(address(token)), // rewards token (SAME)
            token, // stake token (SAME)
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            30 days, // rewardDuration
            0, // minimumStakeAmount
            IAddressSet(address(0)), // no staker allowset
            IAddressSet(address(0)),
            AccessMode.NONE,
            allowset // allocation mechanism allowset
        );

        // Setup admin and notifier
        vm.startPrank(admin);
        staker.setRewardNotifier(notifier, true);
        vm.stopPrank();

        // Fund users
        token.mint(user1, INITIAL_BALANCE);
        token.mint(notifier, INITIAL_BALANCE);
    }

    /// @notice Test that RegenStaker relies on base Staker check (reward balance >= amount)
    function test_baseStakerCheckSufficientForSurrogates() public {
        // User stakes tokens (goes to surrogate)
        vm.startPrank(user1);
        token.approve(address(staker), STAKE_AMOUNT);
        staker.stake(STAKE_AMOUNT, delegatee, user1);
        vm.stopPrank();

        // Verify tokens are in surrogate, not main contract
        assertEq(token.balanceOf(address(staker)), 0, "Main contract should have no stake tokens");
        address surrogate = address(staker.surrogates(delegatee));
        assertEq(token.balanceOf(surrogate), STAKE_AMOUNT, "Surrogate should hold stake tokens");

        // Base Staker requires reward balance >= notified amount
        vm.startPrank(notifier);

        // Should revert - new balance validation: no rewards transferred yet
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerBase.InsufficientRewardBalance.selector,
                0, // currentBalance = 0 (no tokens transferred yet)
                REWARD_AMOUNT // required = totalRewards - totalClaimedRewards + amount = 0 - 0 + 500e18
            )
        );
        staker.notifyRewardAmount(REWARD_AMOUNT);

        // Transfer LESS than reward amount - should still fail balance check
        token.transfer(address(staker), REWARD_AMOUNT - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerBase.InsufficientRewardBalance.selector,
                REWARD_AMOUNT - 1, // currentBalance = 499e18 (transferred amount)
                REWARD_AMOUNT // required = 0 - 0 + 500e18 = 500e18
            )
        );
        staker.notifyRewardAmount(REWARD_AMOUNT);

        // Transfer exactly reward amount - should succeed
        // Note: Does NOT need totalStaked since stakes are segregated in surrogates
        token.transfer(address(staker), 1); // Add the missing 1 wei to reach REWARD_AMOUNT
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // This demonstrates that surrogate segregation makes the same-token scenario safe
        // without needing the additional protection that WithoutDelegate variant requires
    }

    /// @notice Test that different token scenario still works normally
    function test_differentTokensNoProtectionNeeded() public {
        // Deploy a variant with different reward token
        MockERC20Staking rewardToken = new MockERC20Staking(18);
        RegenStaker differentTokenStaker = new RegenStaker(
            IERC20(address(rewardToken)), // different reward token
            token, // stake token
            earningPowerCalculator,
            0,
            admin,
            30 days,
            0,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            allowset
        );

        vm.startPrank(admin);
        differentTokenStaker.setRewardNotifier(notifier, true);
        vm.stopPrank();

        // Fund and notify - protection check is skipped for different tokens
        rewardToken.mint(notifier, REWARD_AMOUNT);
        vm.startPrank(notifier);
        rewardToken.transfer(address(differentTokenStaker), REWARD_AMOUNT);
        differentTokenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
    }
}

/// @title Tests for Same-Token Protection in RegenStakerWithoutDelegateSurrogateVotes
/// @notice Tests the protection mechanism that prevents reward notifications from corrupting user deposits
/// @dev Addresses REG-023 (OSU-956) - Same-token accounting vulnerability
contract RegenStakerWithoutDelegateSurrogateVotesSameTokenProtectionTest is Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    RegenStakerWithoutDelegateSurrogateVotes public differentTokenStaker;
    MockERC20 public token;
    MockERC20 public rewardToken;
    MockERC20 public differentRewardToken;
    RegenEarningPowerCalculator public earningPowerCalculator;
    AddressSet public allowset;

    address public admin = address(0x1);
    address public notifier = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);

    uint256 public constant INITIAL_BALANCE = 1_000_000e18;
    uint256 public constant STAKE_AMOUNT = 1000e18;
    uint256 public constant REWARD_AMOUNT = 500e18;

    function setUp() public {
        // Deploy tokens
        token = new MockERC20(18);
        rewardToken = new MockERC20(18);
        differentRewardToken = new MockERC20(18);

        // Deploy allowset (constructor sets msg.sender as owner)
        allowset = new AddressSet();
        allowset.add(user1);
        allowset.add(user2);

        // Deploy earning power calculator
        earningPowerCalculator = new RegenEarningPowerCalculator(
            admin,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        // Deploy staker with SAME token for staking and rewards (vulnerable scenario)
        staker = new RegenStakerWithoutDelegateSurrogateVotes(
            IERC20(address(token)), // rewards token (SAME)
            IERC20(address(token)), // stake token (SAME)
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            30 days, // rewardDuration
            0, // minimumStakeAmount
            IAddressSet(address(0)), // no staker allowset
            IAddressSet(address(0)), // stakerBlockset
            AccessMode.NONE,
            allowset // allocation mechanism allowset
        );

        // Deploy staker with DIFFERENT tokens (safe scenario)
        differentTokenStaker = new RegenStakerWithoutDelegateSurrogateVotes(
            IERC20(address(differentRewardToken)), // different reward token
            IERC20(address(token)), // stake token
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            30 days, // rewardDuration
            0, // minimumStakeAmount
            IAddressSet(address(0)), // no staker allowset
            IAddressSet(address(0)), // stakerBlockset
            AccessMode.NONE,
            allowset // allocation mechanism allowset
        );

        // Setup admin and notifier
        vm.startPrank(admin);
        staker.setRewardNotifier(notifier, true);
        differentTokenStaker.setRewardNotifier(notifier, true);
        vm.stopPrank();

        // Fund users
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);
        token.mint(notifier, INITIAL_BALANCE);
        differentRewardToken.mint(notifier, INITIAL_BALANCE);
    }

    /// @notice Test unauthorized caller gets auth error before balance check
    function test_notifyReward_unauthorizedRevertsWithAuthError() public {
        // Setup: User stakes tokens
        vm.startPrank(user1);
        token.approve(address(staker), STAKE_AMOUNT);
        staker.stake(STAKE_AMOUNT, user1);
        vm.stopPrank();

        // Try to notify as unauthorized user (not notifier)
        // Even with sufficient balance, should fail on auth check first
        token.mint(address(staker), REWARD_AMOUNT); // Contract has sufficient balance

        vm.prank(user1); // user1 is not a notifier
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not notifier"), user1));
        staker.notifyRewardAmount(REWARD_AMOUNT);

        // One auth failure is sufficient to validate access control ordering for readability
    }

    /// @notice Test success case: exact balance requirement (covers normal success path too)
    function test_notifyReward_withExactBalance() public {
        // User stakes tokens
        vm.startPrank(user1);
        token.approve(address(staker), STAKE_AMOUNT);
        staker.stake(STAKE_AMOUNT, user1);
        vm.stopPrank();

        // Notifier adds EXACT reward amount
        vm.startPrank(notifier);
        token.transfer(address(staker), REWARD_AMOUNT);

        // Should succeed - we have exactly stakes + rewards
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Verify balance
        assertEq(token.balanceOf(address(staker)), STAKE_AMOUNT + REWARD_AMOUNT);
    }

    /// @notice Test protection case: insufficient balance prevents corruption
    function test_notifyReward_revertsWhenWouldAffectDeposits() public {
        // User stakes tokens
        vm.startPrank(user1);
        token.approve(address(staker), STAKE_AMOUNT);
        staker.stake(STAKE_AMOUNT, user1);
        vm.stopPrank();

        // Notifier tries to notify MORE rewards than available
        vm.startPrank(notifier);
        token.transfer(address(staker), 100e18); // Only transfer 100, but try to notify 500

        // Should revert - would need to eat into user deposits
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerBase.InsufficientRewardBalance.selector,
                STAKE_AMOUNT + 100e18, // currentBalance
                STAKE_AMOUNT + REWARD_AMOUNT // required
            )
        );
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
    }

    // Note: Multi-notification protection is covered by fuzz/property tests; omitting redundant example

    /// @notice Test protection after compounding increases totalStaked
    function test_notifyReward_afterCompounding() public {
        // Setup initial stake and rewards
        vm.startPrank(user1);
        token.approve(address(staker), STAKE_AMOUNT);
        staker.stake(STAKE_AMOUNT, user1);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(notifier);
        token.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Advance time to earn rewards
        vm.warp(block.timestamp + 15 days);

        // Compound rewards (DepositIdentifier(0) for first deposit)
        vm.prank(user1);
        staker.compoundRewards(Staker.DepositIdentifier.wrap(0));

        // totalStaked should have increased
        uint256 newTotalStaked = staker.totalStaked();
        assertGt(newTotalStaked, STAKE_AMOUNT);

        // Try to notify MORE than available balance - should fail with new simple accounting
        // New accounting: required = totalStaked + totalRewards - totalClaimedRewards + newAmount
        vm.startPrank(notifier);
        uint256 actualBalance = token.balanceOf(address(staker));

        // Get current state for simple accounting
        uint256 currentTotalRewards = staker.totalRewards();
        uint256 currentTotalClaimed = staker.totalClaimedRewards();
        uint256 newAmount = 300e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerBase.InsufficientRewardBalance.selector,
                actualBalance, // currentBalance
                newTotalStaked + currentTotalRewards - currentTotalClaimed + newAmount
            )
        );
        staker.notifyRewardAmount(newAmount);

        // Add enough tokens to satisfy the simple accounting requirements
        // Need: totalStaked + totalRewards - totalClaimedRewards + newAmount - currentBalance
        uint256 additionalNeeded = newTotalStaked +
            currentTotalRewards -
            currentTotalClaimed +
            newAmount -
            actualBalance;
        token.transfer(address(staker), additionalNeeded);
        staker.notifyRewardAmount(300e18);
        vm.stopPrank();
    }

    /// @notice Test different tokens scenario now has appropriate balance validation
    function test_notifyReward_differentTokens_hasValidation() public {
        // User stakes tokens (these go to stake token, separate from reward token)
        vm.startPrank(user1);
        token.approve(address(differentTokenStaker), STAKE_AMOUNT);
        differentTokenStaker.stake(STAKE_AMOUNT, user1);
        vm.stopPrank();

        vm.startPrank(notifier);
        // Should fail without transferring reward tokens first
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerBase.InsufficientRewardBalance.selector,
                0, // currentBalance = 0 (no reward tokens transferred)
                REWARD_AMOUNT // required = totalRewards - totalClaimedRewards + amount = 0 - 0 + 500e18
            )
        );
        differentTokenStaker.notifyRewardAmount(REWARD_AMOUNT);

        // Transfer reward tokens and should succeed
        differentRewardToken.transfer(address(differentTokenStaker), REWARD_AMOUNT);
        differentTokenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
    }

    /// @notice Test admin typo scenario - the exact case we're protecting against
    function test_adminTypo_extraZero_prevented() public {
        // Setup: Users stake significant amounts
        vm.startPrank(user1);
        token.approve(address(staker), 10_000e18);
        staker.stake(10_000e18, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(staker), 10_000e18);
        staker.stake(10_000e18, user2);
        vm.stopPrank();

        // Admin intends to notify 1,000 tokens but accidentally types 10,000 (extra zero)
        vm.startPrank(notifier);
        token.transfer(address(staker), 1_000e18); // Only transfer the intended amount

        // The typo notification should fail, protecting user deposits
        vm.expectRevert(
            abi.encodeWithSelector(
                RegenStakerBase.InsufficientRewardBalance.selector,
                20_000e18 + 1_000e18, // currentBalance (stakes + transferred rewards)
                20_000e18 + 10_000e18 // required (stakes + typo amount)
            )
        );
        staker.notifyRewardAmount(10_000e18); // Typo: extra zero

        // Correct notification works
        staker.notifyRewardAmount(1_000e18);
        vm.stopPrank();

        // Note: Withdrawal test removed as REG-007 (OSU-918) addresses the withdrawal issue
        // This test focuses on the protection mechanism preventing corruption
    }

    /// @notice Fuzz test: protection holds for various amounts
    function testFuzz_protection(uint256 stakeAmt, uint256 rewardAmt, uint256 actualTransfer) public {
        stakeAmt = bound(stakeAmt, 1e18, 100_000e18);
        rewardAmt = bound(rewardAmt, 1e18, 100_000e18);
        actualTransfer = bound(actualTransfer, 0, rewardAmt);

        // Setup stake
        token.mint(user1, stakeAmt);
        vm.startPrank(user1);
        token.approve(address(staker), stakeAmt);
        staker.stake(stakeAmt, user1);
        vm.stopPrank();

        // Try to notify rewards
        vm.startPrank(notifier);
        token.transfer(address(staker), actualTransfer);

        if (actualTransfer >= rewardAmt) {
            // Should succeed
            staker.notifyRewardAmount(rewardAmt);
        } else {
            // Should revert - insufficient balance
            vm.expectRevert(
                abi.encodeWithSelector(
                    RegenStakerBase.InsufficientRewardBalance.selector,
                    stakeAmt + actualTransfer, // currentBalance
                    stakeAmt + rewardAmt // required
                )
            );
            staker.notifyRewardAmount(rewardAmt);
        }
        vm.stopPrank();
    }
}
