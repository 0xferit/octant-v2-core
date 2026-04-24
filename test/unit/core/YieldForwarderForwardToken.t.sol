// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { YieldForwarder } from "src/core/YieldForwarder.sol";

/// @notice Pre-fix, a `YieldForwarder` deployed as a strategy's `dragonRouter`
///         had no path for arbitrary ERC-20 balances. If Spark (or any
///         airdrop-emitting strategy) called `sweepAirdrop` while the forwarder was
///         the router, the swept tokens were stuck at the forwarder forever. Fix:
///         keeper-gated `forwardToken(address)` that flushes any ERC-20 balance
///         to the immutable `receiver`.
contract YieldForwarderForwardTokenTest is Test {
    YieldForwarder internal forwarder;
    ERC20Mock internal token;

    address internal receiver = address(0xBEEF);
    address internal keeperEOA = address(0xCAFE);
    address internal randomCaller = address(0xD00D);

    function setUp() public {
        forwarder = new YieldForwarder(receiver, keeperEOA);
        token = new ERC20Mock();
    }

    // --- YieldForwarder.forwardToken ---

    /// @notice Keeper flushes the full token balance to `receiver`.
    function test_forwardToken_keeperCanForwardToReceiver() public {
        token.mint(address(forwarder), 123 ether);

        vm.prank(keeperEOA);
        forwarder.forwardToken(address(token));

        assertEq(token.balanceOf(receiver), 123 ether, "receiver must get full balance");
        assertEq(token.balanceOf(address(forwarder)), 0, "forwarder must be drained");
    }

    /// @notice Non-keeper callers cannot flush balances, even though the destination is fixed.
    function test_forwardToken_revertsWhenNotKeeper() public {
        token.mint(address(forwarder), 7 ether);

        vm.prank(randomCaller);
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        forwarder.forwardToken(address(token));

        assertEq(token.balanceOf(address(forwarder)), 7 ether, "forwarder keeps balance on unauthorized call");
        assertEq(token.balanceOf(receiver), 0, "receiver gets nothing");
    }

    /// @notice Zero balance is a no-op for the keeper.
    function test_forwardToken_zeroBalanceIsNoop() public {
        assertEq(token.balanceOf(address(forwarder)), 0, "precondition: zero");

        vm.prank(keeperEOA);
        forwarder.forwardToken(address(token));

        assertEq(token.balanceOf(receiver), 0, "no transfer on zero balance");
    }

    /// @notice Emits TokenForwarded with the right (token, receiver, amount) tuple.
    function test_forwardToken_emitsTokenForwardedEvent() public {
        token.mint(address(forwarder), 50 ether);

        vm.expectEmit(true, true, false, true);
        emit YieldForwarder.TokenForwarded(address(token), receiver, 50 ether);

        vm.prank(keeperEOA);
        forwarder.forwardToken(address(token));
    }

    /// @notice Destination is locked to the immutable `receiver`.
    function test_forwardToken_destinationIsImmutableReceiver() public {
        token.mint(address(forwarder), 42 ether);

        vm.prank(keeperEOA);
        forwarder.forwardToken(address(token));

        assertEq(token.balanceOf(keeperEOA), 0, "caller must not get tokens");
        assertEq(token.balanceOf(receiver), 42 ether, "only receiver gets tokens");
    }
}
