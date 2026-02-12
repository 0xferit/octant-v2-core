// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { AccessMode } from "src/constants.sol";
import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { Staker } from "staker/Staker.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

/// @title RegenStakerGLMWETHIntegrationTest
/// @notice Integration tests for RegenStakerWithoutDelegateSurrogateVotes against mainnet GLM/WETH
contract RegenStakerGLMWETHIntegrationTest is Test {
    IERC20 public constant GLM = IERC20(0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429);
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    RegenStakerWithoutDelegateSurrogateVotes public staker;
    RegenEarningPowerCalculator public earningPowerCalculator;
    AddressSet public allocationAllowset;

    uint256 internal constant ALICE_PK = 0xA11CE;
    address public admin = makeAddr("admin");
    address public alice = vm.addr(ALICE_PK);
    address public bob = makeAddr("bob");
    address public notifier = makeAddr("notifier");

    uint256 internal constant STAKE_AMOUNT = 1000 ether;
    uint256 internal constant REWARD_AMOUNT = 500 ether;
    uint128 internal constant REWARD_DURATION = 30 days;
    uint256 internal constant HALF_REWARD_DURATION = REWARD_DURATION / 2;
    uint256 internal constant PAST_REWARD_END = REWARD_DURATION + 1 days;
    uint256 internal constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        vm.createSelectFork(vm.envString("TEST_RPC_URL"));

        earningPowerCalculator = new RegenEarningPowerCalculator(
            admin,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        allocationAllowset = new AddressSet();

        staker = new RegenStakerWithoutDelegateSurrogateVotes(
            WETH,
            GLM,
            earningPowerCalculator,
            0,
            admin,
            REWARD_DURATION,
            0,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE,
            allocationAllowset
        );

        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);

        deal(address(GLM), alice, INITIAL_BALANCE);
        deal(address(GLM), bob, INITIAL_BALANCE);
        deal(address(WETH), notifier, INITIAL_BALANCE);
    }

    function _deployStaker(
        IEarningPowerCalculator calc,
        IAddressSet _allowset,
        IAddressSet _blockset,
        AccessMode mode
    ) internal returns (RegenStakerWithoutDelegateSurrogateVotes) {
        return
            new RegenStakerWithoutDelegateSurrogateVotes(
                WETH,
                GLM,
                calc,
                0,
                admin,
                REWARD_DURATION,
                0,
                _allowset,
                _blockset,
                mode,
                allocationAllowset
            );
    }

    // --- Balance validation (different-token) ---

    /// @notice Notifying without sufficient reward token balance should revert
    function test_validateBalance_differentToken_productionConfig() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        // Notifying without transferring WETH first should revert
        vm.startPrank(notifier);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.InsufficientRewardBalance.selector, 0, REWARD_AMOUNT));
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.startPrank(notifier);
        WETH.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // required does NOT include totalStaked when tokens differ
        assertEq(staker.totalRewards(), REWARD_AMOUNT);
        assertEq(staker.totalClaimedRewards(), 0);
        assertEq(staker.totalStaked(), STAKE_AMOUNT);
        assertEq(WETH.balanceOf(address(staker)), REWARD_AMOUNT);
        assertEq(GLM.balanceOf(address(staker)), STAKE_AMOUNT);

        vm.warp(block.timestamp + HALF_REWARD_DURATION);

        vm.prank(alice);
        uint256 claimed = staker.claimReward(depositId);
        assertGt(claimed, 0);

        // Re-notify after partial claim: carryOver reflects claimed amount
        uint256 newRewardAmount = 200 ether;
        vm.startPrank(notifier);
        WETH.transfer(address(staker), newRewardAmount);
        staker.notifyRewardAmount(newRewardAmount);
        vm.stopPrank();

        assertEq(staker.totalRewards(), REWARD_AMOUNT + newRewardAmount);
        assertEq(staker.totalClaimedRewards(), claimed);
    }

    // --- totalClaimedRewards consistency ---

    /// @notice claimReward should increment totalClaimedRewards exactly once
    function test_totalClaimedRewards_claimPath() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.startPrank(notifier);
        WETH.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + HALF_REWARD_DURATION);
        assertEq(staker.totalClaimedRewards(), 0);

        vm.prank(alice);
        uint256 claimed = staker.claimReward(depositId);
        assertGt(claimed, 0);

        assertEq(staker.totalClaimedRewards(), claimed);
        assertEq(WETH.balanceOf(address(staker)), REWARD_AMOUNT - claimed);

        uint256 carryOver = staker.totalRewards() - staker.totalClaimedRewards();
        assertEq(carryOver, REWARD_AMOUNT - claimed);
        assertGe(WETH.balanceOf(address(staker)), carryOver);
    }

    // --- Paused withdrawal ---

    /// @notice Users can withdraw when paused; staking and claiming revert
    function test_withdrawWorksWhenPaused() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.prank(admin);
        staker.pause();

        vm.startPrank(bob);
        GLM.approve(address(staker), STAKE_AMOUNT);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        staker.stake(STAKE_AMOUNT, bob, bob);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        staker.claimReward(depositId);

        uint256 aliceBalanceBefore = GLM.balanceOf(alice);
        vm.prank(alice);
        staker.withdraw(depositId, STAKE_AMOUNT);
        assertEq(GLM.balanceOf(alice), aliceBalanceBefore + STAKE_AMOUNT);
        assertEq(staker.totalStaked(), 0);
    }

    /// @notice _stakeTokenSafeTransferFrom override allows withdrawal while paused
    function test_withdrawPaused_stakeTokenSafeTransferFrom() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.startPrank(notifier);
        WETH.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + HALF_REWARD_DURATION);

        vm.prank(admin);
        staker.pause();

        vm.prank(alice);
        staker.withdraw(depositId, STAKE_AMOUNT);

        assertEq(GLM.balanceOf(address(staker)), 0);
        assertGt(WETH.balanceOf(address(staker)), 0);
    }

    // --- Delegation always reverts ---

    /// @notice alterDelegatee reverts with DelegationNotSupported
    function test_alterDelegatee_reverts() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(RegenStakerWithoutDelegateSurrogateVotes.DelegationNotSupported.selector);
        staker.alterDelegatee(depositId, bob);
    }

    /// @notice alterDelegateeOnBehalf reverts even with a valid EIP-712 signature
    function test_alterDelegateeOnBehalf_reverts() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = staker.nonces(alice);
        bytes32 structHash = keccak256(
            abi.encode(staker.ALTER_DELEGATEE_TYPEHASH(), depositId, bob, alice, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", staker.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        vm.expectRevert(RegenStakerWithoutDelegateSurrogateVotes.DelegationNotSupported.selector);
        staker.alterDelegateeOnBehalf(depositId, bob, alice, deadline, abi.encodePacked(r, s, v));
    }

    // --- surrogates() ---

    /// @notice surrogates() returns address(this) for any input
    function test_surrogates_returnsThis() public view {
        assertEq(address(staker.surrogates(alice)), address(staker));
        assertEq(address(staker.surrogates(address(0))), address(staker));
        assertEq(address(staker.surrogates(address(1))), address(staker));
    }

    // --- Full lifecycle ---

    /// @notice Stake → earn → partial claim → re-notify → full claim → withdraw
    function test_fullLifecycle_productionConfig() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.startPrank(notifier);
        WETH.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        assertEq(staker.totalRewards(), REWARD_AMOUNT);
        assertEq(staker.totalClaimedRewards(), 0);

        vm.warp(block.timestamp + HALF_REWARD_DURATION);

        vm.prank(alice);
        uint256 claimed1 = staker.claimReward(depositId);
        assertGt(claimed1, 0);
        assertEq(staker.totalClaimedRewards(), claimed1);
        assertGt(staker.totalRewards() - staker.totalClaimedRewards(), 0);

        uint256 additionalRewards = 300 ether;
        vm.startPrank(notifier);
        WETH.transfer(address(staker), additionalRewards);
        staker.notifyRewardAmount(additionalRewards);
        vm.stopPrank();

        assertEq(staker.totalRewards(), REWARD_AMOUNT + additionalRewards);
        assertEq(staker.totalClaimedRewards(), claimed1);

        vm.warp(block.timestamp + PAST_REWARD_END);

        vm.prank(alice);
        uint256 claimed2 = staker.claimReward(depositId);

        uint256 totalClaimed = staker.totalClaimedRewards();
        assertEq(totalClaimed, claimed1 + claimed2);
        assertApproxEqAbs(totalClaimed, REWARD_AMOUNT + additionalRewards, 2);

        vm.prank(alice);
        staker.withdraw(depositId, STAKE_AMOUNT);
        assertEq(staker.totalStaked(), 0);
        assertEq(GLM.balanceOf(alice), INITIAL_BALANCE);
    }

    // --- No double-counting ---

    /// @notice _claimReward does NOT go through _consumeRewards (no double-count)
    function test_noDoubleCounting_claimReward() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.startPrank(notifier);
        WETH.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + PAST_REWARD_END);

        assertGt(staker.unclaimedReward(depositId), 0);

        vm.prank(alice);
        uint256 claimed = staker.claimReward(depositId);

        assertEq(staker.totalClaimedRewards(), claimed);

        uint256 carryOver = staker.totalRewards() - staker.totalClaimedRewards();
        assertGe(WETH.balanceOf(address(staker)), carryOver);
    }

    // --- Multiple stakers ---

    /// @notice Equal stakers receive equal rewards over full period
    function test_multipleStakers_fullDistribution() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier aliceDepositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier bobDepositId = staker.stake(STAKE_AMOUNT, bob, bob);
        vm.stopPrank();

        vm.startPrank(notifier);
        WETH.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + PAST_REWARD_END);

        vm.prank(alice);
        uint256 aliceClaimed = staker.claimReward(aliceDepositId);

        vm.prank(bob);
        uint256 bobClaimed = staker.claimReward(bobDepositId);

        assertApproxEqAbs(aliceClaimed, bobClaimed, 2);
        assertEq(staker.totalClaimedRewards(), aliceClaimed + bobClaimed);
        assertApproxEqAbs(aliceClaimed + bobClaimed, REWARD_AMOUNT, 2);
    }

    // --- compoundRewards reverts on different-token staker ---

    /// @notice compoundRewards reverts with CompoundingNotSupported on GLM/WETH staker
    function test_compoundRewards_revertsOnDifferentToken() public {
        vm.startPrank(alice);
        GLM.approve(address(staker), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = staker.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.startPrank(notifier);
        WETH.transfer(address(staker), REWARD_AMOUNT);
        staker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + HALF_REWARD_DURATION);

        vm.prank(alice);
        vm.expectRevert(RegenStakerBase.CompoundingNotSupported.selector);
        staker.compoundRewards(depositId);
    }

    // --- Access control (ALLOWSET / BLOCKSET) ---

    /// @notice ALLOWSET mode: authorized can stake, unauthorized reverts
    function test_allowsetMode_blocksUnauthorizedStake() public {
        AddressSet stakerAllowset = new AddressSet();
        stakerAllowset.add(alice);

        RegenStakerWithoutDelegateSurrogateVotes s = _deployStaker(
            earningPowerCalculator,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        vm.prank(admin);
        s.setRewardNotifier(notifier, true);

        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();
        assertEq(s.totalStaked(), STAKE_AMOUNT);

        vm.startPrank(bob);
        GLM.approve(address(s), STAKE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, bob));
        s.stake(STAKE_AMOUNT, bob, bob);
        vm.stopPrank();
    }

    /// @notice BLOCKSET mode: blocklisted stakers revert
    function test_blocksetMode_blocksBlockedStake() public {
        AddressSet stakerBlockset = new AddressSet();
        stakerBlockset.add(bob);

        RegenStakerWithoutDelegateSurrogateVotes s = _deployStaker(
            earningPowerCalculator,
            IAddressSet(address(0)),
            IAddressSet(address(stakerBlockset)),
            AccessMode.BLOCKSET
        );

        vm.prank(admin);
        s.setRewardNotifier(notifier, true);

        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();
        assertEq(s.totalStaked(), STAKE_AMOUNT);

        vm.startPrank(bob);
        GLM.approve(address(s), STAKE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerBlocked.selector, bob));
        s.stake(STAKE_AMOUNT, bob, bob);
        vm.stopPrank();
    }

    /// @notice Grandfathered withdrawal after allowset removal; re-staking blocked
    function test_allowsetMode_withdrawGrandfathered() public {
        AddressSet stakerAllowset = new AddressSet();
        stakerAllowset.add(alice);

        RegenStakerWithoutDelegateSurrogateVotes s = _deployStaker(
            earningPowerCalculator,
            IAddressSet(address(stakerAllowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        vm.prank(admin);
        s.setRewardNotifier(notifier, true);

        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        stakerAllowset.remove(alice);

        // Withdraw still works (no access check on _withdraw)
        uint256 balBefore = GLM.balanceOf(alice);
        vm.prank(alice);
        s.withdraw(depositId, STAKE_AMOUNT);
        assertEq(GLM.balanceOf(alice), balBefore + STAKE_AMOUNT);

        // Re-staking blocked
        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(RegenStakerBase.StakerNotAllowed.selector, alice));
        s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();
    }

    // --- bumpEarningPower (real RegenEarningPowerCalculator) ---

    function _deployCalcWithAllowset(
        address who
    ) internal returns (RegenEarningPowerCalculator calc, AddressSet calcAllowset) {
        calcAllowset = new AddressSet();
        calcAllowset.add(who);
        calc = new RegenEarningPowerCalculator(
            address(this),
            IAddressSet(address(calcAllowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );
    }

    function _deployStakerWithCalc(
        RegenEarningPowerCalculator calc
    ) internal returns (RegenStakerWithoutDelegateSurrogateVotes s) {
        s = _deployStaker(
            IEarningPowerCalculator(address(calc)),
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        vm.prank(admin);
        s.setRewardNotifier(notifier, true);
    }

    /// @notice Down-bump when user removed from calculator allowset
    function test_bumpEarningPower_qualifiedDownBump() public {
        (RegenEarningPowerCalculator calc, AddressSet calcAllowset) = _deployCalcWithAllowset(alice);
        RegenStakerWithoutDelegateSurrogateVotes s = _deployStakerWithCalc(calc);

        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        (, , uint96 epBefore, , , , ) = s.deposits(depositId);
        assertEq(uint256(epBefore), STAKE_AMOUNT);

        calcAllowset.remove(alice);

        vm.prank(bob);
        s.bumpEarningPower(depositId, bob, 0);

        (, , uint96 epAfter, , , , ) = s.deposits(depositId);
        assertEq(uint256(epAfter), 0);
    }

    /// @notice Up-bump when user re-added to calculator allowset
    function test_bumpEarningPower_qualifiedUpBump() public {
        (RegenEarningPowerCalculator calc, AddressSet calcAllowset) = _deployCalcWithAllowset(alice);
        RegenStakerWithoutDelegateSurrogateVotes s = _deployStakerWithCalc(calc);

        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        calcAllowset.remove(alice);
        vm.prank(bob);
        s.bumpEarningPower(depositId, bob, 0);

        (, , uint96 epDown, , , , ) = s.deposits(depositId);
        assertEq(uint256(epDown), 0);

        calcAllowset.add(alice);
        vm.prank(bob);
        s.bumpEarningPower(depositId, bob, 0);

        (, , uint96 epUp, , , , ) = s.deposits(depositId);
        assertEq(uint256(epUp), STAKE_AMOUNT);
    }

    /// @notice Bump reverts when earning power hasn't changed
    function test_bumpEarningPower_unqualifiedReverts() public {
        (RegenEarningPowerCalculator calc, ) = _deployCalcWithAllowset(alice);
        RegenStakerWithoutDelegateSurrogateVotes s = _deployStakerWithCalc(calc);

        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Staker.Staker__Unqualified.selector, STAKE_AMOUNT));
        s.bumpEarningPower(depositId, bob, 0);
    }

    /// @notice bumpEarningPower reverts when paused
    function test_bumpEarningPower_revertsWhenPaused() public {
        (RegenEarningPowerCalculator calc, AddressSet calcAllowset) = _deployCalcWithAllowset(alice);
        RegenStakerWithoutDelegateSurrogateVotes s = _deployStakerWithCalc(calc);

        vm.startPrank(alice);
        GLM.approve(address(s), STAKE_AMOUNT);
        Staker.DepositIdentifier depositId = s.stake(STAKE_AMOUNT, alice, alice);
        vm.stopPrank();

        calcAllowset.remove(alice);

        vm.prank(admin);
        s.pause();

        vm.prank(bob);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        s.bumpEarningPower(depositId, bob, 0);
    }
}
