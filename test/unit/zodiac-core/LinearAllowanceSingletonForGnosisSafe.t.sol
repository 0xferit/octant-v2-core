// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { LinearAllowanceSingletonForGnosisSafe } from "src/zodiac-core/modules/LinearAllowanceSingletonForGnosisSafe.sol";
import { ILinearAllowanceSingleton } from "src/zodiac-core/interfaces/ILinearAllowanceSingleton.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockSafe } from "test/mocks/zodiac-core/MockSafe.sol";
import { NATIVE_TOKEN } from "src/constants.sol";

contract LinearAllowanceSingletonForGnosisSafeTest is Test {
    LinearAllowanceSingletonForGnosisSafe public module;
    MockSafe public safe;
    MockERC20 public token;

    address public delegate;
    address public delegate2;

    uint192 constant DRIP_RATE = 1 ether;

    function setUp() public {
        module = new LinearAllowanceSingletonForGnosisSafe();
        safe = new MockSafe();
        token = new MockERC20(18);
        delegate = makeAddr("delegate");
        delegate2 = makeAddr("delegate2");

        // Enable module on safe
        safe.enableModule(address(module));

        // Fund safe
        vm.deal(address(safe), 100 ether);
        token.mint(address(safe), 100 ether);
    }

    // --- setAllowance ---

    function test_SetAllowance_Success() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        // Advance and check
        vm.warp(block.timestamp + 1 days);
        uint256 unspent = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspent, DRIP_RATE, "Should accrue 1 day of drip rate");
    }

    function test_SetAllowance_RevertIf_DelegateZero() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(ILinearAllowanceSingleton.AddressZeroForArgument.selector, "delegate"));
        module.setAllowance(address(0), NATIVE_TOKEN, DRIP_RATE);
    }

    function test_SetAllowance_UpdateExisting() public {
        vm.startPrank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        // Advance time to accrue some allowance
        vm.warp(block.timestamp + 1 days);

        // Update drip rate - should preserve accrued
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE * 2);
        vm.stopPrank();

        // Advance another day
        vm.warp(block.timestamp + 1 days);

        // Should have 1 day at old rate + 1 day at new rate
        uint256 unspent = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspent, DRIP_RATE + DRIP_RATE * 2, "Should accrue correctly after update");
    }

    // --- setAllowances (batch) ---

    function test_SetAllowances_Success() public {
        address[] memory delegates = new address[](2);
        delegates[0] = delegate;
        delegates[1] = delegate2;

        address[] memory tokens = new address[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = address(token);

        uint192[] memory rates = new uint192[](2);
        rates[0] = DRIP_RATE;
        rates[1] = DRIP_RATE * 2;

        vm.prank(address(safe));
        module.setAllowances(delegates, tokens, rates);

        vm.warp(block.timestamp + 1 days);

        assertEq(module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN), DRIP_RATE);
        assertEq(module.getTotalUnspent(address(safe), delegate2, address(token)), DRIP_RATE * 2);
    }

    function test_SetAllowances_RevertIf_LengthMismatch() public {
        address[] memory delegates = new address[](2);
        delegates[0] = delegate;
        delegates[1] = delegate2;

        address[] memory tokens = new address[](1); // Mismatched
        tokens[0] = NATIVE_TOKEN;

        uint192[] memory rates = new uint192[](2);
        rates[0] = DRIP_RATE;
        rates[1] = DRIP_RATE;

        vm.prank(address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(ILinearAllowanceSingleton.ArrayLengthsMismatch.selector, 2, 1, 2)
        );
        module.setAllowances(delegates, tokens, rates);
    }

    // --- revokeAllowance ---

    function test_RevokeAllowance_ClearsAllAccrued() public {
        vm.startPrank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        vm.warp(block.timestamp + 1 days);

        // Verify there is accrued
        uint256 unspentBefore = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspentBefore, DRIP_RATE);

        // Revoke
        module.revokeAllowance(delegate, NATIVE_TOKEN);
        vm.stopPrank();

        // After revoke, should be zero
        uint256 unspentAfter = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspentAfter, 0, "Should be zero after revoke");

        // Even after more time, should stay zero
        vm.warp(block.timestamp + 1 days);
        uint256 unspentLater = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspentLater, 0, "Should remain zero after revoke");
    }

    function test_RevokeAllowance_RevertIf_DelegateZero() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(ILinearAllowanceSingleton.AddressZeroForArgument.selector, "delegate"));
        module.revokeAllowance(address(0), NATIVE_TOKEN);
    }

    // --- revokeAllowances (batch) ---

    function test_RevokeAllowances_Success() public {
        vm.startPrank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);
        module.setAllowance(delegate2, address(token), DRIP_RATE);

        vm.warp(block.timestamp + 1 days);

        address[] memory delegates = new address[](2);
        delegates[0] = delegate;
        delegates[1] = delegate2;

        address[] memory tokens = new address[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = address(token);

        module.revokeAllowances(delegates, tokens);
        vm.stopPrank();

        assertEq(module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN), 0);
        assertEq(module.getTotalUnspent(address(safe), delegate2, address(token)), 0);
    }

    function test_RevokeAllowances_RevertIf_LengthMismatch() public {
        address[] memory delegates = new address[](2);
        delegates[0] = delegate;
        delegates[1] = delegate2;

        address[] memory tokens = new address[](1);
        tokens[0] = NATIVE_TOKEN;

        vm.prank(address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(ILinearAllowanceSingleton.ArrayLengthsMismatch.selector, 2, 1, 0)
        );
        module.revokeAllowances(delegates, tokens);
    }

    // --- executeAllowanceTransfer ---

    function test_ExecuteAllowanceTransfer_NativeToken() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        vm.warp(block.timestamp + 1 days);

        address payable recipient = payable(makeAddr("recipient"));
        uint256 recipientBefore = recipient.balance;

        vm.prank(delegate);
        uint256 amount = module.executeAllowanceTransfer(address(safe), NATIVE_TOKEN, recipient);

        assertEq(amount, DRIP_RATE);
        assertEq(recipient.balance - recipientBefore, DRIP_RATE);
    }

    function test_ExecuteAllowanceTransfer_ERC20() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, address(token), DRIP_RATE);

        vm.warp(block.timestamp + 1 days);

        address payable recipient = payable(makeAddr("recipient"));
        uint256 recipientBefore = token.balanceOf(recipient);

        vm.prank(delegate);
        uint256 amount = module.executeAllowanceTransfer(address(safe), address(token), recipient);

        assertEq(amount, DRIP_RATE);
        assertEq(token.balanceOf(recipient) - recipientBefore, DRIP_RATE);
    }

    function test_ExecuteAllowanceTransfer_RevertIf_SafeZero() public {
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(ILinearAllowanceSingleton.AddressZeroForArgument.selector, "safe"));
        module.executeAllowanceTransfer(address(0), NATIVE_TOKEN, payable(makeAddr("recipient")));
    }

    function test_ExecuteAllowanceTransfer_RevertIf_ToZero() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);
        vm.warp(block.timestamp + 1 days);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(ILinearAllowanceSingleton.AddressZeroForArgument.selector, "to"));
        module.executeAllowanceTransfer(address(safe), NATIVE_TOKEN, payable(address(0)));
    }

    function test_ExecuteAllowanceTransfer_RevertIf_NoAllowance() public {
        // No allowance set, no time passed
        vm.prank(delegate);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILinearAllowanceSingleton.NoAllowanceToTransfer.selector,
                address(safe),
                delegate,
                NATIVE_TOKEN
            )
        );
        module.executeAllowanceTransfer(address(safe), NATIVE_TOKEN, payable(makeAddr("recipient")));
    }

    function test_ExecuteAllowanceTransfer_RevertIf_ZeroTransfer() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        vm.warp(block.timestamp + 1 days);

        // Drain safe balance
        vm.deal(address(safe), 0);

        vm.prank(delegate);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILinearAllowanceSingleton.ZeroTransfer.selector,
                address(safe),
                delegate,
                NATIVE_TOKEN
            )
        );
        module.executeAllowanceTransfer(address(safe), NATIVE_TOKEN, payable(makeAddr("recipient")));
    }

    // --- executeAllowanceTransfers (batch) ---

    function test_ExecuteAllowanceTransfers_Success() public {
        MockSafe safe2 = new MockSafe();
        vm.deal(address(safe2), 100 ether);
        safe2.enableModule(address(module));

        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);
        vm.prank(address(safe2));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE * 2);

        vm.warp(block.timestamp + 1 days);

        address[] memory safes = new address[](2);
        safes[0] = address(safe);
        safes[1] = address(safe2);

        address[] memory tokens = new address[](2);
        tokens[0] = NATIVE_TOKEN;
        tokens[1] = NATIVE_TOKEN;

        address[] memory tos = new address[](2);
        address payable recipient = payable(makeAddr("recipient"));
        tos[0] = recipient;
        tos[1] = recipient;

        uint256 recipientBefore = recipient.balance;

        vm.prank(delegate);
        uint256[] memory amounts = module.executeAllowanceTransfers(safes, tokens, tos);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], DRIP_RATE);
        assertEq(amounts[1], DRIP_RATE * 2);
        assertEq(recipient.balance - recipientBefore, DRIP_RATE * 3);
    }

    function test_ExecuteAllowanceTransfers_RevertIf_LengthMismatch() public {
        address[] memory safes = new address[](2);
        safes[0] = address(safe);
        safes[1] = address(safe);

        address[] memory tokens = new address[](1); // Mismatched
        tokens[0] = NATIVE_TOKEN;

        address[] memory tos = new address[](2);
        tos[0] = makeAddr("recipient");
        tos[1] = makeAddr("recipient");

        vm.prank(delegate);
        vm.expectRevert(
            abi.encodeWithSelector(ILinearAllowanceSingleton.ArrayLengthsMismatch.selector, 2, 1, 2)
        );
        module.executeAllowanceTransfers(safes, tokens, tos);
    }

    // --- getBalance ---

    function test_GetBalance_NativeToken() public view {
        uint256 balance = module.getBalance(address(safe), NATIVE_TOKEN);
        assertEq(balance, 100 ether, "Should return safe ETH balance");
    }

    function test_GetBalance_ERC20() public view {
        uint256 balance = module.getBalance(address(safe), address(token));
        assertEq(balance, 100 ether, "Should return safe token balance");
    }

    // --- getMaxWithdrawableAmount ---

    function test_GetMaxWithdrawableAmount_NoAllowance() public view {
        uint256 maxAmount = module.getMaxWithdrawableAmount(address(safe), delegate, NATIVE_TOKEN);
        assertEq(maxAmount, 0, "Should return 0 when no allowance");
    }

    function test_GetMaxWithdrawableAmount_LimitedByAllowance() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        vm.warp(block.timestamp + 1 days);

        uint256 maxAmount = module.getMaxWithdrawableAmount(address(safe), delegate, NATIVE_TOKEN);
        assertEq(maxAmount, DRIP_RATE, "Should be limited by allowance when safe has more");
    }

    function test_GetMaxWithdrawableAmount_LimitedBySafeBalance() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        vm.warp(block.timestamp + 100 days);

        // Drain safe to less than accrued allowance
        vm.deal(address(safe), 0.5 ether);

        uint256 maxAmount = module.getMaxWithdrawableAmount(address(safe), delegate, NATIVE_TOKEN);
        assertEq(maxAmount, 0.5 ether, "Should be limited by safe balance");
    }

    // --- getTotalUnspent ---

    function test_GetTotalUnspent_BeforeAnyAllowance() public view {
        uint256 unspent = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspent, 0, "Should be 0 before any allowance is set");
    }

    function test_GetTotalUnspent_AccruesOverTime() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        vm.warp(block.timestamp + 2 days);

        uint256 unspent = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspent, DRIP_RATE * 2, "Should accrue for 2 days");
    }

    function test_GetTotalUnspent_NoAccrualAtSameBlock() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        // Don't advance time
        uint256 unspent = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspent, 0, "Should be 0 at same block");
    }

    // --- allowances mapping accessor ---

    function test_AllowancesAccessor() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        (
            uint192 dripRatePerDay,
            uint64 lastBookedAtInSeconds,
            uint256 totalUnspent,
            uint256 totalSpent
        ) = module.allowances(address(safe), delegate, NATIVE_TOKEN);

        assertEq(dripRatePerDay, DRIP_RATE);
        assertTrue(lastBookedAtInSeconds > 0);
        assertEq(totalUnspent, 0); // No time has passed
        assertEq(totalSpent, 0);
    }

    // --- Event emission ---

    function test_SetAllowance_EmitsEvent() public {
        vm.prank(address(safe));
        vm.expectEmit(true, true, true, true);
        emit ILinearAllowanceSingleton.AllowanceSet(address(safe), delegate, NATIVE_TOKEN, DRIP_RATE);
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);
    }

    function test_RevokeAllowance_EmitsEvent() public {
        vm.startPrank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, true, true);
        emit ILinearAllowanceSingleton.AllowanceRevoked(address(safe), delegate, NATIVE_TOKEN, DRIP_RATE);
        module.revokeAllowance(delegate, NATIVE_TOKEN);
        vm.stopPrank();
    }

    function test_ExecuteAllowanceTransfer_EmitsEvent() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);
        vm.warp(block.timestamp + 1 days);

        address payable recipient = payable(makeAddr("recipient"));

        vm.prank(delegate);
        vm.expectEmit(true, true, true, true);
        emit ILinearAllowanceSingleton.AllowanceTransferred(
            address(safe),
            delegate,
            NATIVE_TOKEN,
            recipient,
            DRIP_RATE
        );
        module.executeAllowanceTransfer(address(safe), NATIVE_TOKEN, recipient);
    }

    // --- _calculateNewAccrued: unset allowance (lastBookedAtInSeconds == 0) returns 0 ---

    function test_getTotalUnspent_unsetAllowance_returnsZero() public view {
        // Querying an unset allowance should return 0
        // This exercises _calculateNewAccrued when lastBookedAtInSeconds == 0
        uint256 unspent = module.getTotalUnspent(address(safe), address(0xDEAD), NATIVE_TOKEN);
        assertEq(unspent, 0, "Unset allowance should return 0");
    }

    // --- _calculateCurrentAllowance: zero accrued (no time passed) ---

    function test_getTotalUnspent_noTimePassed_returnsZero() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);

        // No time has passed since setAllowance, so newAccrued should be 0
        uint256 unspent = module.getTotalUnspent(address(safe), delegate, NATIVE_TOKEN);
        assertEq(unspent, 0, "No time passed means 0 unspent");
    }

    // --- _executeAllowanceTransfer: safe == address(0) reverts ---

    function test_executeAllowanceTransfer_zeroSafe_reverts() public {
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(ILinearAllowanceSingleton.AddressZeroForArgument.selector, "safe"));
        module.executeAllowanceTransfer(address(0), NATIVE_TOKEN, payable(makeAddr("recipient")));
    }

    // --- _executeAllowanceTransfer: to == address(0) reverts ---

    function test_executeAllowanceTransfer_zeroTo_reverts() public {
        vm.prank(address(safe));
        module.setAllowance(delegate, NATIVE_TOKEN, DRIP_RATE);
        vm.warp(block.timestamp + 1 days);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(ILinearAllowanceSingleton.AddressZeroForArgument.selector, "to"));
        module.executeAllowanceTransfer(address(safe), NATIVE_TOKEN, payable(address(0)));
    }
}
