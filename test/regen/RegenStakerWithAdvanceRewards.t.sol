// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessMode } from "src/constants.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { Staker } from "staker/Staker.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockEarningPowerCalculator } from "test/mocks/MockEarningPowerCalculator.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";

/// @title RegenStaker Advance Rewards Tests
/// @notice Tests for setAdvanceRewards() and contribution split flow through contribute()
contract RegenStakerWithAdvanceRewardsTest is Test {
    RegenStaker public regenStaker;
    MockERC20Staking public token;
    MockEarningPowerCalculator public earningPowerCalculator;
    OctantQFMechanism public allocationMechanism;
    AddressSet public allocationAllowset;

    address public admin = makeAddr("admin");
    address public owner;
    uint256 private ownerPk;
    address public claimer;
    uint256 private claimerPk;
    address public delegatee = makeAddr("delegatee");
    address public stranger = makeAddr("stranger");

    uint256 public constant STAKE_AMOUNT = 1000e18;
    uint256 public constant REWARD_AMOUNT = 10_000e18;
    uint128 public constant REWARD_DURATION = 30 days;

    Staker.DepositIdentifier public depositId;

    function setUp() public {
        (owner, ownerPk) = makeAddrAndKey("owner");
        (claimer, claimerPk) = makeAddrAndKey("claimer");

        token = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        // Deploy a real OctantQFMechanism (same token for stake/reward)
        TokenizedAllocationMechanism impl = new TokenizedAllocationMechanism();
        AllocationConfig memory cfg = AllocationConfig({
            asset: IERC20(address(token)),
            name: "AdvanceTest",
            symbol: "ST",
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
            IAddressSet(address(0)), // contributionAllowset (open)
            IAddressSet(address(0)), // contributionBlockset (none)
            AccessMode.NONE
        );

        vm.startPrank(admin);
        allocationAllowset = new AddressSet();
        allocationAllowset.add(address(allocationMechanism));
        vm.stopPrank();

        vm.prank(admin);
        regenStaker = new RegenStaker(
            IERC20(address(token)), // rewardsToken (same as stake token)
            token,
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            REWARD_DURATION,
            1e18, // minimumStakeAmount
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            IAddressSet(address(allocationAllowset))
        );

        // Fund owner and stake
        token.mint(owner, STAKE_AMOUNT);
        token.mint(address(regenStaker), REWARD_AMOUNT);

        vm.startPrank(owner);
        token.approve(address(regenStaker), STAKE_AMOUNT);
        depositId = regenStaker.stake(STAKE_AMOUNT, delegatee, claimer);
        vm.stopPrank();

        // Schedule rewards
        vm.startPrank(admin);
        regenStaker.setRewardNotifier(admin, true);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();
    }

    // =========================================================
    // Helpers
    // =========================================================

    /// @dev Returns deposit balance from the public tuple getter
    function _depositBalance(Staker.DepositIdentifier _depositId) internal view returns (uint96 bal) {
        (bal, , , , , , ) = regenStaker.deposits(_depositId);
    }

    /// @dev Returns deposit earning power from the public tuple getter
    function _depositEarningPower(Staker.DepositIdentifier _depositId) internal view returns (uint96 ep) {
        (, , ep, , , , ) = regenStaker.deposits(_depositId);
    }

    function _contributeSignatureFor(
        address _contributor,
        uint256 _contributorPk,
        uint256 _amount
    ) internal returns (uint256 deadline, uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(_contributor);
        deadline = block.timestamp + 1 days;

        bytes32 typeHash = keccak256(
            bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)")
        );
        bytes32 structHash = keccak256(
            abi.encode(typeHash, _contributor, address(regenStaker), _amount, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(_contributorPk, digest);
    }

    // =========================================================
    // setAdvanceRewards
    // =========================================================

    function test_setAdvanceRewards_stateCorrect() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        (uint96 amount, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(amount, (STAKE_AMOUNT * 5) / 100, "amount mismatch");
        assertEq(lockEnd, block.timestamp + 5 * 30 days, "lockEnd mismatch");
    }

    function test_setAdvanceRewards_lockLinear() public {
        // 1% -> 30 days
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 1);
        (, uint64 lockEnd1) = regenStaker.advanceRewards(depositId);
        assertEq(lockEnd1, block.timestamp + 30 days, "1% lock mismatch");

        // Expire lock, then set 5% -> 150 days
        vm.warp(uint256(lockEnd1) + 1);
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);
        (, uint64 lockEnd5) = regenStaker.advanceRewards(depositId);
        assertEq(lockEnd5, block.timestamp + 5 * 30 days, "5% lock mismatch");
    }

    function test_setAdvanceRewards_blocksWithdraw() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.CommitmentLockActive.selector, depositId, lockEnd));
        regenStaker.withdraw(depositId, 1e18);
    }

    function test_setAdvanceRewards_allowsWithdrawAfterLock() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);

        // Warp past lock expiry
        vm.warp(uint256(lockEnd) + 1);

        // Withdrawal must succeed; stale earmark must be cleared
        vm.prank(owner);
        regenStaker.withdraw(depositId, 1e18);

        (uint96 amount, uint64 newLockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(amount, 0, "stale earmark should be cleared");
        assertEq(newLockEnd, 0, "stale lockEnd should be cleared");
    }

    function test_setAdvanceRewards_revertsIfAlreadyLocked() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.ActiveCommitmentExists.selector, depositId));
        regenStaker.setAdvanceRewards(depositId, 5);
    }

    function test_setAdvanceRewards_allowsResetAfterExpiry() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        vm.warp(uint256(lockEnd) + 1);

        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        (uint96 amount, uint64 newLockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(amount, (STAKE_AMOUNT * 5) / 100, "new amount mismatch");
        assertEq(newLockEnd, block.timestamp + 5 * 30 days, "new lockEnd mismatch");
    }

    function test_setAdvanceRewards_revertsInvalidPct() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.InvalidAdvanceRewardsPct.selector, 0));
        regenStaker.setAdvanceRewards(depositId, 0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.InvalidAdvanceRewardsPct.selector, 6));
        regenStaker.setAdvanceRewards(depositId, 6);
    }

    function test_setAdvanceRewards_revertsIfNotOwner() public {
        vm.prank(claimer);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not owner"), claimer));
        regenStaker.setAdvanceRewards(depositId, 5);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not owner"), stranger));
        regenStaker.setAdvanceRewards(depositId, 5);
    }

    // =========================================================
    // contribute split flow
    // =========================================================

    function test_contribute_usesRewardsOnly_whenAvailable() public {
        vm.warp(block.timestamp + REWARD_DURATION / 4);

        uint256 rewardAvailable = regenStaker.unclaimedReward(depositId);
        uint256 rewardToContribute = rewardAvailable / 2;
        require(rewardToContribute > 0, "reward-to-contribute should be > 0");

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _contributeSignatureFor(
            owner,
            ownerPk,
            rewardToContribute
        );

        uint256 mechanismBalanceBefore = token.balanceOf(address(allocationMechanism));
        uint96 balanceBefore = _depositBalance(depositId);
        uint256 totalStakedBefore = regenStaker.totalStaked();

        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            rewardToContribute,
            deadline,
            v,
            r,
            s
        );

        assertEq(contributed, rewardToContribute, "contributed amount mismatch");
        assertEq(
            token.balanceOf(address(allocationMechanism)) - mechanismBalanceBefore,
            rewardToContribute,
            "all contribution should hit mechanism"
        );
        assertEq(_depositBalance(depositId), balanceBefore, "deposit balance should not reduce");
        assertEq(regenStaker.totalStaked(), totalStakedBefore, "total staked should not change");
    }

    function test_contribute_usesAdvanceRewardsOnly_whenNoRewardsAvailable() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);
        uint256 earmarkAmount = (STAKE_AMOUNT * 5) / 100;
        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        vm.warp(uint256(lockEnd) + 1);

        vm.prank(owner);
        regenStaker.claimReward(depositId);

        assertEq(regenStaker.unclaimedReward(depositId), 0, "should have zero unclaimed reward");

        uint96 balanceBefore = _depositBalance(depositId);
        uint256 totalStakedBefore = regenStaker.totalStaked();
        uint256 ownerTotalStakedBefore = regenStaker.depositorTotalStaked(owner);
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint96 epBefore = _depositEarningPower(depositId);
        uint256 mechanismBalanceBefore = token.balanceOf(address(allocationMechanism));

        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(0),
            earmarkAmount,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );

        assertEq(contributed, 0, "contributed-to-mechanism amount should be zero");
        assertEq(token.balanceOf(address(allocationMechanism)), mechanismBalanceBefore, "mechanism should not receive tokens");
        assertEq(token.balanceOf(owner), ownerBalanceBefore + earmarkAmount, "owner should receive stake payout");
        assertEq(_depositBalance(depositId), balanceBefore - earmarkAmount, "deposit balance should reduce by advance amount");
        assertEq(regenStaker.totalStaked(), totalStakedBefore - earmarkAmount, "global total staked should reduce");
        assertEq(
            regenStaker.depositorTotalStaked(owner),
            ownerTotalStakedBefore - earmarkAmount,
            "depositor total staked should reduce"
        );
        assertEq(_depositEarningPower(depositId), epBefore - uint96(earmarkAmount), "earning power should reduce");
        (uint96 remaining, uint64 currentLockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(remaining, 0, "advance rewards should be consumed");
        assertEq(currentLockEnd, 0, "stale lock should be cleared on advance consumption");
    }

    function test_contribute_mixedRewardAndAdvanceFlow() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 1);
        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        vm.warp(uint256(lockEnd) + 1);

        uint256 rewardToContribute = regenStaker.unclaimedReward(depositId);
        require(rewardToContribute > 0, "reward should have accrued");
        uint256 advanceAmount = ((STAKE_AMOUNT * 1) / 100) / 2;

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _contributeSignatureFor(
            owner,
            ownerPk,
            rewardToContribute
        );

        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            rewardToContribute + advanceAmount,
            deadline,
            v,
            r,
            s
        );

        assertEq(contributed, rewardToContribute, "reward portion should be returned");
        assertEq(token.balanceOf(address(allocationMechanism)), rewardToContribute, "mechanism should only receive reward portion");
        assertEq(token.balanceOf(owner), advanceAmount, "owner should receive advance payout");
        assertEq(_depositBalance(depositId), STAKE_AMOUNT - advanceAmount, "deposit should reduce by advance portion only");
        assertEq(regenStaker.totalStaked(), STAKE_AMOUNT - advanceAmount, "global total staked should reduce only by advance");
        assertEq(regenStaker.depositorTotalStaked(owner), STAKE_AMOUNT - advanceAmount, "depositor total staked should reduce only by advance");
        (uint96 remaining, uint64 currentLockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(remaining, ((STAKE_AMOUNT * 1) / 100) - advanceAmount, "advance reward marking should reduce by payout");
        assertEq(currentLockEnd, 0, "stale lock should be cleared on mixed advance consumption");
    }

    function test_contribute_rewardOnlyLegStillWorksDuringActiveLock() public {
        vm.warp(block.timestamp + REWARD_DURATION / 4);
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);

        uint256 rewardAvailable = regenStaker.unclaimedReward(depositId);
        uint256 rewardToContribute = rewardAvailable / 2;
        require(rewardToContribute > 0, "reward-to-contribute should be > 0");

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _contributeSignatureFor(
            owner,
            ownerPk,
            rewardToContribute
        );

        uint256 mechanismBalanceBefore = token.balanceOf(address(allocationMechanism));
        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            rewardToContribute,
            deadline,
            v,
            r,
            s
        );

        assertEq(contributed, rewardToContribute);
        assertEq(token.balanceOf(address(allocationMechanism)) - mechanismBalanceBefore, rewardToContribute);
        (uint96 remainingAdvance, uint64 currentLockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(remainingAdvance, (STAKE_AMOUNT * 5) / 100);
        assertEq(currentLockEnd, lockEnd);
    }

    function test_contribute_mixedLegBlockedWhenActiveCommitmentLock() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);
        (uint96 earmark, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        assertGt(earmark, 0, "earmark should exist");

        vm.warp(block.timestamp + REWARD_DURATION / 4);
        uint256 rewardAvailable = regenStaker.unclaimedReward(depositId);

        uint256 totalToContribute = rewardAvailable + 1;
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _contributeSignatureFor(
            owner,
            ownerPk,
            rewardAvailable
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.CommitmentLockActive.selector, depositId, lockEnd));
        regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            totalToContribute,
            deadline,
            v,
            r,
            s
        );
    }

    function test_contribute_staleAdvanceLockIsClearedAndCanBeReset() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);
        (uint96 earmarkAmount, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        require(earmarkAmount > 0, "earmark should exist");
        vm.warp(uint256(lockEnd) + 1);

        vm.prank(owner);
        regenStaker.claimReward(depositId);
        assertEq(regenStaker.unclaimedReward(depositId), 0, "rewards should be zeroed before advance leg");

        uint96 balanceBefore = _depositBalance(depositId);
        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(0),
            1,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        assertEq(contributed, 0, "advance-only call should return mechanism contribution of 0");
        assertEq(_depositBalance(depositId), balanceBefore - 1, "advance should reduce principal");
        (uint96 remainingAfterConsume, uint64 lockAfterConsume) = regenStaker.advanceRewards(depositId);
        assertEq(remainingAfterConsume, earmarkAmount - 1, "advance amount should remain after stale-lock cleanup");
        assertEq(lockAfterConsume, 0, "lock should be cleared after expiry");

        uint96 balanceBeforeReset = _depositBalance(depositId);
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);
        (uint96 refreshedAmount, uint64 refreshedLockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(refreshedAmount, (uint256(balanceBeforeReset) * 5) / 100, "stale lock should allow full reset");
        assertEq(refreshedLockEnd, block.timestamp + 5 * 30 days, "new lock should be active");
    }

    function test_contribute_overconsumedAdvanceAmount_reverts() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);
        uint256 earmarkAmount = (STAKE_AMOUNT * 5) / 100;
        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        vm.warp(uint256(lockEnd) + 1);

        vm.prank(owner);
        regenStaker.claimReward(depositId);
        assertEq(regenStaker.unclaimedReward(depositId), 0, "rewards should be zeroed before advance leg");

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(RegenStakerBase.InsufficientAdvanceRewards.selector, earmarkAmount + 1, earmarkAmount)
        );
        regenStaker.contribute(
            depositId,
            address(0),
            earmarkAmount + 1,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_contribute_zeroAmountStillAllowedForContributionSignup() public {
        vm.warp(block.timestamp + REWARD_DURATION / 4);
        uint256 rewardAvailable = regenStaker.unclaimedReward(depositId);
        require(rewardAvailable > 0, "reward should be available");

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) = _contributeSignatureFor(owner, ownerPk, 0);

        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            0,
            deadline,
            v,
            r,
            s
        );
        assertEq(contributed, 0, "zero amount should still be a valid signup path");
    }

    function test_contribute_fromAdvanceRewards_allowedForClaimerToo() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);
        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        vm.warp(uint256(lockEnd) + 1);

        vm.prank(owner);
        regenStaker.claimReward(depositId);
        assertEq(regenStaker.unclaimedReward(depositId), 0, "rewards should be zeroed before advance leg");

        uint256 earmarkAmount = (STAKE_AMOUNT * 5) / 100;
        uint256 claimerBalanceBefore = token.balanceOf(claimer);

        vm.prank(claimer);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(0),
            earmarkAmount,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
        assertEq(contributed, 0, "advance-only call should return contribution portion");
        assertEq(token.balanceOf(claimer), claimerBalanceBefore + earmarkAmount, "claimer should receive payout");
    }

    function test_contribute_fromAdvanceRewards_revertsUnauthorizedCaller() public {
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, 5);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unauthorized.selector, bytes32("not claimer or owner"), stranger));
        regenStaker.contribute(
            depositId,
            address(0),
            (STAKE_AMOUNT * 5) / 100,
            0,
            0,
            bytes32(0),
            bytes32(0)
        );
    }
}
