// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import { AccessMode } from "src/constants.sol";
import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { Staker } from "staker/Staker.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

/// @title Invariant test for monotonic reward property
/// @notice Verifies that totalRewards is monotonically non-decreasing
/// @dev Tests the property: totalRewards can only increase or stay the same, never decrease
contract RegenMonotonicRewardInvariant is StdInvariant, Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    MockERC20 public token;
    AddressSet public allowset;
    RegenEarningPowerCalculator public earningPowerCalculator;
    address public admin = address(0xA);
    address public notifier = address(0xB);
    address public user = address(0xC);
    RegenMonotonicRewardHandler public handler;

    function setUp() public {
        token = new MockERC20(18);
        allowset = new AddressSet();
        allowset.add(user);
        earningPowerCalculator = new RegenEarningPowerCalculator(
            admin,
            IAddressSet(address(allowset)),
            IAddressSet(address(0)),
            AccessMode.ALLOWSET
        );

        staker = new RegenStakerWithoutDelegateSurrogateVotes(
            IERC20(address(token)),
            IERC20(address(token)),
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

        vm.prank(admin);
        staker.setRewardNotifier(notifier, true);

        handler = new RegenMonotonicRewardHandler(staker, token, admin, notifier, user);
        targetContract(address(handler));
    }

    /// @notice Invariant: totalRewards is monotonically non-decreasing
    /// @dev After any action, totalRewards must be >= previous totalRewards
    /// @dev This ensures rewards cannot be clawed back once notified
    function invariant_TotalRewardsMonotonicallyIncreasing() public view {
        uint256 currentTotalRewards = staker.totalRewards();
        uint256 previousTotalRewards = handler.previousTotalRewards();

        assertGe(currentTotalRewards, previousTotalRewards, "totalRewards decreased: rewards cannot be clawed back");
    }
}

contract RegenMonotonicRewardHandler is Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    MockERC20 public token;
    address public admin;
    address public notifier;
    address public user;

    uint256 public previousTotalRewards;

    constructor(
        RegenStakerWithoutDelegateSurrogateVotes _staker,
        MockERC20 _token,
        address _admin,
        address _notifier,
        address _user
    ) {
        staker = _staker;
        token = _token;
        admin = _admin;
        notifier = _notifier;
        user = _user;
        previousTotalRewards = staker.totalRewards();
    }

    function stake(uint256 amount) external {
        amount = bound(amount, 1e9, 1_000_000e18);
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(staker), amount);
        staker.stake(amount, user);
        vm.stopPrank();
        _updatePreviousTotalRewards();
    }

    function withdraw(uint256 depositId, uint256 amount) external {
        amount = bound(amount, 1, type(uint256).max);
        vm.warp(block.timestamp + ((depositId % 7) + 1) * 1 days);
        vm.prank(user);
        try staker.withdraw(Staker.DepositIdentifier.wrap(depositId % 4), amount) {} catch {}
        _updatePreviousTotalRewards();
    }

    function claimReward(uint256 depositId) external {
        vm.warp(block.timestamp + ((depositId % 7) + 1) * 1 days);
        vm.prank(user);
        try staker.claimReward(Staker.DepositIdentifier.wrap(depositId % 4)) {} catch {}
        _updatePreviousTotalRewards();
    }

    function compound(uint256 depositId) external {
        vm.warp(block.timestamp + ((depositId % 7) + 1) * 1 days);
        vm.prank(user);
        try staker.compoundRewards(Staker.DepositIdentifier.wrap(depositId % 4)) {} catch {}
        _updatePreviousTotalRewards();
    }

    function notify(uint256 rewardAmt, uint256 transferAmt) external {
        rewardAmt = bound(rewardAmt, 1, 1_000_000e18);
        transferAmt = bound(transferAmt, 0, rewardAmt);
        token.mint(notifier, transferAmt);
        vm.startPrank(notifier);
        if (transferAmt > 0) token.transfer(address(staker), transferAmt);
        if (transferAmt >= rewardAmt) {
            staker.notifyRewardAmount(rewardAmt);
        } else {
            vm.expectRevert(RegenStakerBase.InsufficientRewardBalance.selector);
            staker.notifyRewardAmount(rewardAmt);
        }
        vm.stopPrank();
        _updatePreviousTotalRewards();
    }

    function _updatePreviousTotalRewards() internal {
        previousTotalRewards = staker.totalRewards();
    }
}
