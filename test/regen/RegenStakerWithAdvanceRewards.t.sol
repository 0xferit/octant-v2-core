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
/// @notice Tests for setAdvanceRewards() and contributeFromAdvanceRewards()
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
    // contributeFromAdvanceRewards
    // =========================================================

    function test_contributeFromAdvance_tokensFlowToCaller() public {
        uint256 earmarkPct = 5;
        uint256 earmarkedAmount = (STAKE_AMOUNT * earmarkPct) / 100;
        uint96 balanceBefore = _depositBalance(depositId);
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, earmarkPct);

        vm.prank(owner);
        regenStaker.contributeFromAdvanceRewards(
            depositId,
            address(0),
            earmarkedAmount,
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );

        assertEq(_depositBalance(depositId), balanceBefore - earmarkedAmount, "deposit.balance should decrease");
        assertEq(token.balanceOf(owner), ownerBalanceBefore + earmarkedAmount, "owner should receive stake tokens");
    }

    function test_contributeFromAdvance_earningPowerUpdated() public {
        uint256 earmarkPct = 5;
        uint256 earmarkedAmount = (STAKE_AMOUNT * earmarkPct) / 100;
        uint96 epBefore = _depositEarningPower(depositId);

        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, earmarkPct);

        vm.prank(owner);
        regenStaker.contributeFromAdvanceRewards(
            depositId,
            address(0),
            earmarkedAmount,
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );

        uint96 epAfter = _depositEarningPower(depositId);
        // MockEarningPowerCalculator returns balance as earning power
        assertEq(epAfter, STAKE_AMOUNT - earmarkedAmount, "earning power should decrease proportionally");
        assertTrue(epAfter < epBefore, "earning power should have dropped");
    }

    function test_contributeFromAdvance_partialReducesEarmark() public {
        uint256 earmarkPct = 5;
        uint256 earmarkedAmount = (STAKE_AMOUNT * earmarkPct) / 100;
        uint256 partialAmount = earmarkedAmount / 2;

        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, earmarkPct);

        vm.prank(owner);
        regenStaker.contributeFromAdvanceRewards(
            depositId,
            address(0),
            partialAmount,
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );

        (uint96 remaining, uint64 lockEnd) = regenStaker.advanceRewards(depositId);
        assertEq(remaining, earmarkedAmount - partialAmount, "earmark should be reduced by partial amount");
        assertGt(lockEnd, block.timestamp, "lock should still be active after partial contribution");
    }

    function test_contributeFromAdvance_fullConsumesAmountButKeepsLockUntilExpiry() public {
        uint256 earmarkPct = 5;
        uint256 earmarkedAmount = (STAKE_AMOUNT * earmarkPct) / 100;

        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, earmarkPct);

        // Read lockEnd before consumption to use in the withdraw revert assertion
        (, uint64 lockEnd) = regenStaker.advanceRewards(depositId);

        vm.prank(owner);
        regenStaker.contributeFromAdvanceRewards(
            depositId,
            address(0),
            earmarkedAmount,
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );

        (uint96 amount, uint64 lockEndAfter) = regenStaker.advanceRewards(depositId);
        assertEq(amount, 0, "earmark amount should be consumed after full contribution");
        assertGt(lockEndAfter, block.timestamp, "lockEnd should remain active until expiry");

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.CommitmentLockActive.selector, depositId, lockEnd));
        regenStaker.withdraw(depositId, 1e18);
    }

    function test_contributeFromAdvance_revertsOverEarmark() public {
        uint256 earmarkPct = 5;
        uint256 earmarkedAmount = (STAKE_AMOUNT * earmarkPct) / 100;
        uint256 overAmount = earmarkedAmount + 1;

        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, earmarkPct);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(RegenStakerBase.InsufficientAdvanceRewards.selector, overAmount, earmarkedAmount)
        );
        regenStaker.contributeFromAdvanceRewards(
            depositId,
            address(0),
            overAmount,
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_contributeFromAdvance_rewardAccrualUnaffected() public {
        // Accrue some rewards before contribution
        vm.warp(block.timestamp + REWARD_DURATION / 4);

        uint256 earmarkPct = 5;
        uint256 earmarkedAmount = (STAKE_AMOUNT * earmarkPct) / 100;

        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, earmarkPct);

        vm.prank(owner);
        regenStaker.contributeFromAdvanceRewards(
            depositId,
            address(0),
            earmarkedAmount,
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );

        uint96 remainingBalance = _depositBalance(depositId);
        assertEq(remainingBalance, STAKE_AMOUNT - earmarkedAmount, "balance should reflect contribution");

        // Accrue more rewards on the remaining balance
        vm.warp(block.timestamp + REWARD_DURATION / 4);

        uint256 balanceBefore = token.balanceOf(owner);
        vm.prank(owner);
        regenStaker.claimReward(depositId);
        uint256 claimed = token.balanceOf(owner) - balanceBefore;
        assertGt(claimed, 0, "should have accrued rewards on remaining balance");
    }

    function test_contributeFromAdvance_allowedByClaimerToo() public {
        uint256 earmarkPct = 5;
        uint256 earmarkedAmount = (STAKE_AMOUNT * earmarkPct) / 100;

        // Only owner can earmark
        vm.prank(owner);
        regenStaker.setAdvanceRewards(depositId, earmarkPct);

        uint256 claimerBalanceBefore = token.balanceOf(claimer);

        // Claimer can call contributeFromAdvanceRewards; tokens go to claimer (msg.sender)
        vm.prank(claimer);
        regenStaker.contributeFromAdvanceRewards(
            depositId,
            address(0),
            earmarkedAmount,
            block.timestamp + 1 days,
            0,
            bytes32(0),
            bytes32(0)
        );

        assertEq(
            token.balanceOf(claimer),
            claimerBalanceBefore + earmarkedAmount,
            "claimer should receive stake tokens"
        );
    }
}
