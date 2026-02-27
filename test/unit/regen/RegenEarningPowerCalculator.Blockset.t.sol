// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { AccessMode } from "src/constants.sol";
import "forge-std/Test.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { IAccessControlledEarningPowerCalculator } from "src/regen/interfaces/IAccessControlledEarningPowerCalculator.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title RegenEarningPowerCalculator BLOCKSET Branch Coverage
/// @notice Tests BLOCKSET mode and edge cases for RegenEarningPowerCalculator
contract RegenEarningPowerCalculatorBlocksetTest is Test {
    RegenEarningPowerCalculator calculator;
    AddressSet allowset;
    AddressSet blockset;
    address owner;
    address staker1;
    address staker2;
    address blockedStaker;

    function setUp() public {
        owner = makeAddr("owner");
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");
        blockedStaker = makeAddr("blockedStaker");

        vm.startPrank(owner);
        allowset = new AddressSet();
        blockset = new AddressSet();

        calculator = new RegenEarningPowerCalculator(
            owner,
            IAddressSet(address(allowset)),
            IAddressSet(address(blockset)),
            AccessMode.BLOCKSET
        );

        vm.stopPrank();
    }

    // ===== BLOCKSET Mode: getEarningPower =====

    function test_blocksetMode_unblockedUserHasEarningPower() public view {
        // staker1 is not in blockset, should have earning power
        uint256 ep = calculator.getEarningPower(1000, staker1, address(0));
        assertEq(ep, 1000, "Unblocked user should have full earning power");
    }

    function test_blocksetMode_blockedUserHasZeroEarningPower() public {
        vm.prank(owner);
        blockset.add(blockedStaker);

        uint256 ep = calculator.getEarningPower(1000, blockedStaker, address(0));
        assertEq(ep, 0, "Blocked user should have zero earning power");
    }

    function test_blocksetMode_unblockedAfterRemoval() public {
        vm.startPrank(owner);
        blockset.add(blockedStaker);
        assertEq(calculator.getEarningPower(1000, blockedStaker, address(0)), 0);

        blockset.remove(blockedStaker);
        vm.stopPrank();

        assertEq(calculator.getEarningPower(1000, blockedStaker, address(0)), 1000);
    }

    // ===== BLOCKSET Mode: getNewEarningPower =====

    function test_blocksetMode_getNewEarningPower_blockedUser() public {
        vm.prank(owner);
        blockset.add(blockedStaker);

        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(
            1000,
            blockedStaker,
            address(0),
            1000 // old earning power was 1000
        );

        assertEq(newEP, 0, "Blocked user should have 0 new earning power");
        assertTrue(qualifies, "Should qualify for bump since EP changed from 1000 to 0");
    }

    function test_blocksetMode_getNewEarningPower_unblockedUser() public view {
        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(
            500,
            staker1,
            address(0),
            0 // old earning power was 0
        );

        assertEq(newEP, 500, "Unblocked user should have full earning power");
        assertTrue(qualifies, "Should qualify for bump since EP changed from 0 to 500");
    }

    function test_blocksetMode_getNewEarningPower_noBump() public view {
        // No change in earning power
        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(
            500,
            staker1,
            address(0),
            500 // old EP matches new EP
        );

        assertEq(newEP, 500);
        assertFalse(qualifies, "Should not qualify when EP unchanged");
    }

    // ===== BLOCKSET Mode: setBlockset =====

    function test_setBlockset_asOwner() public {
        AddressSet newBlockset = new AddressSet();

        vm.prank(owner);
        calculator.setBlockset(newBlockset);

        assertEq(address(calculator.blockset()), address(newBlockset));
    }

    function test_setBlockset_emitsEvent() public {
        AddressSet newBlockset = new AddressSet();

        vm.expectEmit();
        emit RegenEarningPowerCalculator.BlocksetAssigned(IAddressSet(address(newBlockset)));

        vm.prank(owner);
        calculator.setBlockset(newBlockset);
    }

    function test_setBlockset_notOwner_reverts() public {
        AddressSet newBlockset = new AddressSet();

        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", staker1));
        calculator.setBlockset(newBlockset);
    }

    // ===== setAccessMode =====

    function test_setAccessMode_asOwner() public {
        vm.prank(owner);
        calculator.setAccessMode(AccessMode.NONE);
        assertEq(uint8(calculator.accessMode()), uint8(AccessMode.NONE));
    }

    function test_setAccessMode_emitsEvent() public {
        vm.expectEmit();
        emit RegenEarningPowerCalculator.AccessModeSet(AccessMode.ALLOWSET);

        vm.prank(owner);
        calculator.setAccessMode(AccessMode.ALLOWSET);
    }

    function test_setAccessMode_notOwner_reverts() public {
        vm.prank(staker1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", staker1));
        calculator.setAccessMode(AccessMode.NONE);
    }

    // ===== Mode transitions =====

    function test_modeTransition_blocksetToNone() public {
        vm.startPrank(owner);
        blockset.add(blockedStaker);
        assertEq(calculator.getEarningPower(1000, blockedStaker, address(0)), 0);

        calculator.setAccessMode(AccessMode.NONE);
        vm.stopPrank();

        // Now blocked user has earning power again
        assertEq(calculator.getEarningPower(1000, blockedStaker, address(0)), 1000);
    }

    function test_modeTransition_noneToAllowset() public {
        vm.startPrank(owner);
        calculator.setAccessMode(AccessMode.NONE);
        assertEq(calculator.getEarningPower(1000, staker1, address(0)), 1000);

        calculator.setAccessMode(AccessMode.ALLOWSET);
        vm.stopPrank();

        // Now only allowset members have earning power
        assertEq(calculator.getEarningPower(1000, staker1, address(0)), 0);

        vm.prank(owner);
        allowset.add(staker1);
        assertEq(calculator.getEarningPower(1000, staker1, address(0)), 1000);
    }

    function test_modeTransition_allowsetToBlockset() public {
        vm.startPrank(owner);
        calculator.setAccessMode(AccessMode.ALLOWSET);
        allowset.add(staker1);
        assertEq(calculator.getEarningPower(1000, staker1, address(0)), 1000);
        assertEq(calculator.getEarningPower(1000, staker2, address(0)), 0);

        calculator.setAccessMode(AccessMode.BLOCKSET);
        vm.stopPrank();

        // Now both have EP (no one in blockset)
        assertEq(calculator.getEarningPower(1000, staker1, address(0)), 1000);
        assertEq(calculator.getEarningPower(1000, staker2, address(0)), 1000);
    }

    // ===== Constructor with BLOCKSET mode =====

    function test_constructor_blocksetMode() public {
        AddressSet bs = new AddressSet();
        AddressSet as_ = new AddressSet();

        vm.prank(owner);
        RegenEarningPowerCalculator calc = new RegenEarningPowerCalculator(
            owner,
            IAddressSet(address(as_)),
            IAddressSet(address(bs)),
            AccessMode.BLOCKSET
        );

        assertEq(uint8(calc.accessMode()), uint8(AccessMode.BLOCKSET));
        assertEq(address(calc.blockset()), address(bs));
    }

    function test_constructor_noneMode() public {
        vm.prank(owner);
        RegenEarningPowerCalculator calc = new RegenEarningPowerCalculator(
            owner,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );

        assertEq(uint8(calc.accessMode()), uint8(AccessMode.NONE));
        // Everyone has earning power in NONE mode
        assertEq(calc.getEarningPower(1000, staker1, address(0)), 1000);
    }

    // ===== Earning power capping at uint96.max =====

    function test_blocksetMode_earningPowerCapped() public view {
        uint256 veryLargeStake = uint256(type(uint96).max) + 1000;
        uint256 ep = calculator.getEarningPower(veryLargeStake, staker1, address(0));
        assertEq(ep, uint256(type(uint96).max), "Should be capped at uint96 max");
    }

    function test_blocksetMode_getNewEarningPower_capped() public view {
        uint256 veryLargeStake = uint256(type(uint96).max) + 1000;
        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(veryLargeStake, staker1, address(0), 0);

        assertEq(newEP, uint256(type(uint96).max), "Should be capped at uint96 max");
        assertTrue(qualifies);
    }

    // ===== Changing blockset affects earning power =====

    function test_changingBlockset_affectsEarningPower() public {
        vm.startPrank(owner);
        blockset.add(staker1);
        assertEq(calculator.getEarningPower(1000, staker1, address(0)), 0);

        // Create new blockset without staker1
        AddressSet newBlockset = new AddressSet();
        calculator.setBlockset(newBlockset);
        vm.stopPrank();

        // staker1 should now have earning power
        assertEq(calculator.getEarningPower(1000, staker1, address(0)), 1000);
    }

    // ===== getNewEarningPower bump qualification edge case =====

    function test_getNewEarningPower_blockedToUnblocked_qualifiesForBump() public {
        vm.startPrank(owner);
        blockset.add(staker1);

        // Currently blocked: EP = 0
        (uint256 ep1, bool q1) = calculator.getNewEarningPower(1000, staker1, address(0), 0);
        assertEq(ep1, 0);
        assertFalse(q1, "No bump when EP stays 0");

        // Unblock
        blockset.remove(staker1);
        vm.stopPrank();

        // Now unblocked: EP = 1000, old was 0 => qualifies
        (uint256 ep2, bool q2) = calculator.getNewEarningPower(1000, staker1, address(0), 0);
        assertEq(ep2, 1000);
        assertTrue(q2);
    }
}
