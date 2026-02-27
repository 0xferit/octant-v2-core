// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { OctantTestBase } from "test/proof-of-concepts/OctantTestBase.t.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { Staker } from "staker/Staker.sol";

/// @title Cantina Competition September 2025 – Finding 359 Fix
/// @notice Proves reward schedule metadata is emitted for call-free indexing.
contract Cantina359Fix is OctantTestBase {
    uint256 internal constant FIRST_REWARD = 100 ether;
    uint256 internal constant SECOND_REWARD = 40 ether;

    function testFix_EmitsRewardScheduleMetadata() public {
        // Fund the notifier for both reward notifications.
        rewardToken.mint(rewardNotifier, FIRST_REWARD + SECOND_REWARD);

        // --- First reward notification: no carry-over ---
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), FIRST_REWARD);
        uint256 expectedEndTimeFirst = block.timestamp + REWARD_DURATION;

        vm.expectEmit(false, false, false, true);
        emit Staker.RewardNotified(FIRST_REWARD, rewardNotifier);
        vm.expectEmit(false, false, false, true);
        emit RegenStakerBase.RewardScheduleUpdated(
            FIRST_REWARD,
            0,
            FIRST_REWARD,
            FIRST_REWARD,
            REWARD_DURATION,
            expectedEndTimeFirst
        );
        regenStaker.notifyRewardAmount(FIRST_REWARD);
        vm.stopPrank();

        // --- Second reward notification: full carry-over from first cycle ---
        vm.startPrank(rewardNotifier);
        rewardToken.transfer(address(regenStaker), SECOND_REWARD);
        uint256 expectedEndTimeSecond = block.timestamp + REWARD_DURATION;

        vm.expectEmit(false, false, false, true);
        emit Staker.RewardNotified(SECOND_REWARD, rewardNotifier);
        vm.expectEmit(false, false, false, true);
        emit RegenStakerBase.RewardScheduleUpdated(
            SECOND_REWARD,
            FIRST_REWARD,
            FIRST_REWARD + SECOND_REWARD,
            FIRST_REWARD + SECOND_REWARD,
            REWARD_DURATION,
            expectedEndTimeSecond
        );
        regenStaker.notifyRewardAmount(SECOND_REWARD);
        vm.stopPrank();
    }
}
