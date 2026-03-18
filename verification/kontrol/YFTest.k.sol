// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { YieldForwarder } from "src/core/YieldForwarder.sol";

import { YFSetup } from "test/kontrol/YFSetup.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title YFTest
 * @notice Kontrol formal verification proofs for YieldForwarder
 * @dev Proves 5 behavioral properties of the YieldForwarder contract:
 *      1. Access control: only keeper can call reportAndForward
 *      2. Receiver guarantee: redeem always targets the hardcoded receiver
 *      3. No residual shares: forwarder holds 0 shares after execution
 *      4. Zero-share passthrough: returns 0 without calling redeem when no shares
 *      5. Return value correctness: return matches mock redeem output
 */
contract YFTest is YFSetup {
    /// @notice Non-keeper address always reverts with OnlyKeeper
    function testReportAndForwardOnlyKeeper() public {
        address nonKeeper = makeAddr("NON_KEEPER");

        vm.prank(nonKeeper);
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        forwarder.reportAndForward(address(mockStrategy), 0);
    }

    /// @notice redeem() is always called with the hardcoded receiver as recipient
    function testReportAndForwardReceiverGuarantee() public {
        // Pre-condition: shares exist to trigger the redeem path
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        vm.prank(_keeper);
        forwarder.reportAndForward(address(mockStrategy), 0);

        // Assert: redeem was called with receiver == forwarder.receiver()
        address lastReceiver = _loadAddress(address(mockStrategy), MFS_LAST_RECEIVER_SLOT);
        assertEq(lastReceiver, _receiver);
    }

    /// @notice After reportAndForward, forwarder holds 0 shares on the strategy
    function testReportAndForwardNoResidualShares() public {
        // Pre-condition: shares exist
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        vm.prank(_keeper);
        forwarder.reportAndForward(address(mockStrategy), 0);

        // Assert: mock share balance is 0 (set to 0 by mock's redeem)
        uint256 postShares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        assertEq(postShares, 0);
    }

    /// @notice When shares == 0, returns 0 and redeem is never called
    function testReportAndForwardZeroSharesPassthrough() public {
        // Set shares to 0
        _storeUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT, 0);

        // Write sentinel to detect any redeem call, including redeem(0, ...).
        // Without this, a regression removing the early return guard would call
        // redeem(0, ...) which writes lastRedeemShares = 0, indistinguishable
        // from the "never called" default.
        uint256 sentinel = type(uint256).max;
        _storeUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT, sentinel);

        vm.prank(_keeper);
        uint256 assets = forwarder.reportAndForward(address(mockStrategy), 0);

        // Assert: returned 0
        assertEq(assets, 0);

        // Assert: redeem was never called (sentinel preserved)
        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, sentinel);
    }

    /// @notice Return value of reportAndForward equals the value returned by redeem
    function testReportAndForwardReturnsRedeemAssets() public {
        // Pre-condition: shares exist
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        uint256 expectedReturn = _loadUInt256(address(mockStrategy), MFS_REDEEM_RETURN_SLOT);

        vm.prank(_keeper);
        uint256 assets = forwarder.reportAndForward(address(mockStrategy), 0);

        assertEq(assets, expectedReturn);
    }
}
