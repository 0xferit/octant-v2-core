// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol"; // For OwnableUnauthorizedAccount error

contract AllowsetTest is Test {
    AddressSet allowset;
    address owner;
    address user1;
    address user2;
    address user3;
    address nonOwner;

    function setUp() public {
        address intendedOwner = makeAddr("intendedOwner"); // Create a dedicated address for ownership
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        nonOwner = makeAddr("nonOwner");

        vm.prank(intendedOwner); // Prank as the intended owner for the deployment
        allowset = new AddressSet();

        owner = intendedOwner; // Assign the 'owner' variable to the actual owner of the allowset
    }

    // --- Constructor & Ownership Tests ---
    function test_Constructor_SetsOwnerCorrectly() public view {
        assertEq(allowset.owner(), owner, "Owner should be the intendedOwner");
    }

    // --- isAllowseted Tests ---
    function test_IsAllowseted_InitiallyFalse() public view {
        assertFalse(allowset.contains(user1), "User1 should not be inAllowset initially");
        assertFalse(allowset.contains(address(0)), "Address(0) should not be inAllowset initially");
    }

    // --- addToAllowset Tests ---
    function test_AddToAllowset_SingleAccount() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(owner);
        allowset.add(accounts);

        assertTrue(allowset.contains(user1), "User1 should be inAllowset after adding");
        assertFalse(allowset.contains(user2), "User2 should still not be inAllowset");
    }

    function test_AddToAllowset_MultipleAccounts() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        vm.prank(owner);
        allowset.add(accounts);

        assertTrue(allowset.contains(user1), "User1 should be inAllowset");
        assertTrue(allowset.contains(user2), "User2 should be inAllowset");
        assertFalse(allowset.contains(user3), "User3 should not be inAllowset");
    }

    function test_AddToAllowset_EmptyList() public {
        address[] memory accounts = new address[](0);

        vm.prank(owner);
        vm.expectRevert();
        allowset.add(accounts);
    }

    function test_AddToAllowset_AddAddressZero() public {
        address[] memory accounts = new address[](1);
        accounts[0] = address(0);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressSet.IllegalAddressSetOperation.selector,
                address(0),
                "Address zero not allowed."
            )
        );
        allowset.add(accounts);
    }

    function test_AddToAllowset_AlreadyAllowseted() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.startPrank(owner);
        allowset.add(accounts); // Add once
        assertTrue(allowset.contains(user1));

        vm.expectRevert(
            abi.encodeWithSelector(AddressSet.IllegalAddressSetOperation.selector, user1, "Address already in set.")
        );
        allowset.add(accounts); // Add again
        vm.stopPrank();
    }

    function test_RevertIf_AddToAllowset_NotOwner() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.startPrank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        allowset.add(accounts);
        vm.stopPrank();
    }

    // --- removeFromAllowset Tests ---
    function test_RemoveFromAllowset_SingleAccount() public {
        address[] memory addAccounts = new address[](1);
        addAccounts[0] = user1;
        vm.startPrank(owner);
        allowset.add(addAccounts);
        assertTrue(allowset.contains(user1));

        address[] memory removeAccounts = new address[](1);
        removeAccounts[0] = user1;
        allowset.remove(removeAccounts);

        assertFalse(allowset.contains(user1), "User1 should not be inAllowset after removal");
        vm.stopPrank();
    }

    function test_RemoveFromAllowset_MultipleAccounts() public {
        address[] memory addAccounts = new address[](3);
        addAccounts[0] = user1;
        addAccounts[1] = user2;
        addAccounts[2] = user3;
        vm.startPrank(owner);
        allowset.add(addAccounts);
        assertTrue(allowset.contains(user1));
        assertTrue(allowset.contains(user2));
        assertTrue(allowset.contains(user3));

        address[] memory removeAccounts = new address[](2);
        removeAccounts[0] = user1;
        removeAccounts[1] = user3;
        allowset.remove(removeAccounts);

        assertFalse(allowset.contains(user1), "User1 should be removed");
        assertTrue(allowset.contains(user2), "User2 should remain inAllowset");
        assertFalse(allowset.contains(user3), "User3 should be removed");
        vm.stopPrank();
    }

    function test_RemoveFromAllowset_EmptyList() public {
        address[] memory addAccounts = new address[](1);
        addAccounts[0] = user1;
        vm.startPrank(owner);
        allowset.add(addAccounts);
        assertTrue(allowset.contains(user1));

        address[] memory removeAccounts = new address[](0);
        vm.expectRevert();
        allowset.remove(removeAccounts);
        vm.stopPrank();
    }

    function test_RemoveFromAllowset_AddressZero() public {
        vm.startPrank(owner);
        address[] memory removeAccounts = new address[](1);
        removeAccounts[0] = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressSet.IllegalAddressSetOperation.selector,
                address(0),
                "Address zero not allowed."
            )
        );
        allowset.remove(removeAccounts);
        vm.stopPrank();
    }

    function test_RemoveFromAllowset_AccountNotAllowseted() public {
        address[] memory accounts = new address[](1);
        accounts[0] = user1; // user1 is not inAllowset yet

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(AddressSet.IllegalAddressSetOperation.selector, user1, "Address not in set.")
        );
        allowset.remove(accounts);

        assertFalse(allowset.contains(user1), "User1 should remain not inAllowset");
    }

    function test_RevertIf_RemoveFromAllowset_NotOwner() public {
        address[] memory addAccounts = new address[](1);
        addAccounts[0] = user1;
        vm.startPrank(owner); // owner adds user1
        allowset.add(addAccounts);
        vm.stopPrank(); // Stop owner prank before starting nonOwner prank

        address[] memory removeAccounts = new address[](1);
        removeAccounts[0] = user1;

        vm.startPrank(nonOwner); // nonOwner tries to remove
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        allowset.remove(removeAccounts);
        vm.stopPrank();

        vm.prank(owner); // Verify user1 still inAllowset as owner didn't remove
        assertTrue(allowset.contains(user1), "User1 should still be inAllowset as non-owner failed to remove");
    }

    // --- Single-address add(address) overload tests ---

    function test_AddSingle_Success() public {
        vm.prank(owner);
        allowset.add(user1);

        assertTrue(allowset.contains(user1), "User1 should be in set after single add");
    }

    function test_AddSingle_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AddressSet.AddressSetAltered(user1, AddressSet.AddressSetOperation.Add);
        allowset.add(user1);
    }

    function test_AddSingle_RevertIf_AddressZero() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressSet.IllegalAddressSetOperation.selector,
                address(0),
                "Address zero not allowed."
            )
        );
        allowset.add(address(0));
    }

    function test_AddSingle_RevertIf_AlreadyInSet() public {
        vm.startPrank(owner);
        allowset.add(user1);

        vm.expectRevert(
            abi.encodeWithSelector(AddressSet.IllegalAddressSetOperation.selector, user1, "Address already in set.")
        );
        allowset.add(user1);
        vm.stopPrank();
    }

    function test_AddSingle_RevertIf_NotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        allowset.add(user1);
    }

    // --- Single-address remove(address) overload tests ---

    function test_RemoveSingle_Success() public {
        vm.startPrank(owner);
        allowset.add(user1);
        assertTrue(allowset.contains(user1));

        allowset.remove(user1);
        assertFalse(allowset.contains(user1), "User1 should be removed from set");
        vm.stopPrank();
    }

    function test_RemoveSingle_EmitsEvent() public {
        vm.startPrank(owner);
        allowset.add(user1);

        vm.expectEmit(true, true, false, false);
        emit AddressSet.AddressSetAltered(user1, AddressSet.AddressSetOperation.Remove);
        allowset.remove(user1);
        vm.stopPrank();
    }

    function test_RemoveSingle_RevertIf_AddressZero() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressSet.IllegalAddressSetOperation.selector,
                address(0),
                "Address zero not allowed."
            )
        );
        allowset.remove(address(0));
    }

    function test_RemoveSingle_RevertIf_NotInSet() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(AddressSet.IllegalAddressSetOperation.selector, user1, "Address not in set.")
        );
        allowset.remove(user1);
    }

    function test_RemoveSingle_RevertIf_NotOwner() public {
        vm.startPrank(owner);
        allowset.add(user1);
        vm.stopPrank();

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        allowset.remove(user1);
    }

    // --- values() and length() tests ---

    function test_Values_EmptyInitially() public view {
        address[] memory vals = allowset.values();
        assertEq(vals.length, 0, "Should be empty initially");
    }

    function test_Values_ReturnsAllAddresses() public {
        vm.startPrank(owner);
        allowset.add(user1);
        allowset.add(user2);
        allowset.add(user3);
        vm.stopPrank();

        address[] memory vals = allowset.values();
        assertEq(vals.length, 3, "Should have 3 addresses");
    }

    function test_Length_EmptyInitially() public view {
        assertEq(allowset.length(), 0, "Length should be 0 initially");
    }

    function test_Length_IncreasesOnAdd() public {
        vm.startPrank(owner);
        allowset.add(user1);
        assertEq(allowset.length(), 1, "Length should be 1 after adding one");

        allowset.add(user2);
        assertEq(allowset.length(), 2, "Length should be 2 after adding two");
        vm.stopPrank();
    }

    function test_Length_DecreasesOnRemove() public {
        vm.startPrank(owner);
        allowset.add(user1);
        allowset.add(user2);
        assertEq(allowset.length(), 2);

        allowset.remove(user1);
        assertEq(allowset.length(), 1, "Length should decrease after removal");
        vm.stopPrank();
    }

    // --- Batch add event tests ---

    function test_AddBatch_EmitsEventForEachAddress() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit AddressSet.AddressSetAltered(user1, AddressSet.AddressSetOperation.Add);
        vm.expectEmit(true, true, false, false);
        emit AddressSet.AddressSetAltered(user2, AddressSet.AddressSetOperation.Add);
        allowset.add(accounts);
    }

    // --- Batch remove event tests ---

    function test_RemoveBatch_EmitsEventForEachAddress() public {
        address[] memory addAccounts = new address[](2);
        addAccounts[0] = user1;
        addAccounts[1] = user2;

        vm.startPrank(owner);
        allowset.add(addAccounts);

        address[] memory removeAccounts = new address[](2);
        removeAccounts[0] = user1;
        removeAccounts[1] = user2;

        vm.expectEmit(true, true, false, false);
        emit AddressSet.AddressSetAltered(user1, AddressSet.AddressSetOperation.Remove);
        vm.expectEmit(true, true, false, false);
        emit AddressSet.AddressSetAltered(user2, AddressSet.AddressSetOperation.Remove);
        allowset.remove(removeAccounts);
        vm.stopPrank();
    }

    // --- Batch add with address(0) in the middle ---

    function test_AddBatch_RevertIf_AddressZeroInMiddle() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = address(0);
        accounts[2] = user2;

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressSet.IllegalAddressSetOperation.selector,
                address(0),
                "Address zero not allowed."
            )
        );
        allowset.add(accounts);
    }

    // --- Batch remove with address(0) in the middle ---

    function test_RemoveBatch_RevertIf_AddressZeroInMiddle() public {
        // First add user1 so the batch remove doesn't fail on user1 being absent
        vm.prank(owner);
        allowset.add(user1);

        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = address(0);
        accounts[2] = user2;

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                AddressSet.IllegalAddressSetOperation.selector,
                address(0),
                "Address zero not allowed."
            )
        );
        allowset.remove(accounts);
    }
}
