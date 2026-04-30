// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { YieldForwarder } from "src/core/YieldForwarder.sol";

import { YFSetup } from "test/kontrol/YFSetup.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title YFTest
 * @notice Kontrol formal verification proofs for YieldForwarder
 * @dev Proves 7 behavioral properties of the YieldForwarder contract:
 *      1. Access control: only keeper can call reportAndForward
 *      2. Receiver guarantee: redeem always targets the hardcoded receiver
 *      3. No residual shares when the full balance is redeemable
 *      4. Zero-share passthrough: returns 0 without calling redeem when no shares
 *      5. Zero-maxRedeem passthrough: returns 0 without calling redeem
 *      6. Zero-convertToAssets passthrough: returns 0 without calling redeem
 *      7. Return value correctness: return matches mock redeem output
 */
contract YFTest is YFSetup {
    function _assumeRedeemPath() internal view returns (uint256 balance, uint256 maxRedeem, uint256 redeemShares) {
        balance = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(balance > 0);

        maxRedeem = _loadUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT);
        vm.assume(maxRedeem > 0);

        redeemShares = balance < maxRedeem ? balance : maxRedeem;

        uint256 convertibleAssets = _loadUInt256(address(mockStrategy), MFS_CONVERT_TO_ASSETS_SLOT);
        vm.assume(convertibleAssets > 0);
    }

    function _assumeFullRedeemPath() internal view returns (uint256 balance) {
        (balance, , ) = _assumeRedeemPath();

        uint256 maxRedeem = _loadUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT);
        vm.assume(maxRedeem >= balance);
    }

    /// @notice Non-keeper address always reverts with OnlyKeeper
    function testReportAndForwardOnlyKeeper() public {
        address nonKeeper = makeAddr("NON_KEEPER");

        vm.prank(nonKeeper);
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        forwarder.reportAndForward(address(mockStrategy), 0);
    }

    /// @notice redeem() is always called with the hardcoded receiver as recipient
    function testReportAndForwardReceiverGuarantee() public {
        // Pre-condition: shares are redeemable and convert to non-zero assets
        (, , uint256 redeemShares) = _assumeRedeemPath();
        uint256 maxLoss = freshUInt256Bounded();

        vm.prank(_keeper);
        forwarder.reportAndForward(address(mockStrategy), maxLoss);

        // Assert: redeem was called with the expected receiver, owner, and maxLoss.
        address lastReceiver = _loadAddress(address(mockStrategy), MFS_LAST_RECEIVER_SLOT);
        assertEq(lastReceiver, _receiver);

        address lastOwner = _loadAddress(address(mockStrategy), MFS_LAST_OWNER_SLOT);
        assertEq(lastOwner, address(forwarder));

        uint256 lastMaxLoss = _loadUInt256(address(mockStrategy), MFS_LAST_MAX_LOSS_SLOT);
        assertEq(lastMaxLoss, maxLoss);

        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, redeemShares);
    }

    /// @notice After reportAndForward, forwarder holds 0 shares when the full balance is redeemable
    function testReportAndForwardNoResidualShares() public {
        // Pre-condition: shares exist and all are redeemable
        _assumeFullRedeemPath();

        vm.prank(_keeper);
        forwarder.reportAndForward(address(mockStrategy), 0);

        // Assert: mock share balance is 0 (set to 0 by mock's redeem)
        uint256 postShares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        assertEq(postShares, 0);
    }

    /// @notice When shares == 0, report still runs, returns 0, and redeem is never called
    function testReportAndForwardZeroSharesPassthrough() public {
        // Set shares to 0
        _storeUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT, 0);
        _storeAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT, address(0));

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

        // Assert: report still ran before the zero-share early return
        address lastReportCaller = _loadAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT);
        assertEq(lastReportCaller, address(forwarder));

        // Assert: redeem was never called (sentinel preserved)
        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, sentinel);
    }

    /// @notice When maxRedeem is 0, report still runs and redeem is never called
    function testReportAndForwardZeroMaxRedeemPassthrough() public {
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        _storeUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT, 0);
        _storeUInt256(address(mockStrategy), MFS_CONVERT_TO_ASSETS_SLOT, 1);
        _storeAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT, address(0));

        uint256 sentinel = type(uint256).max;
        _storeUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT, sentinel);

        vm.prank(_keeper);
        uint256 assets = forwarder.reportAndForward(address(mockStrategy), 0);

        assertEq(assets, 0);

        address lastReportCaller = _loadAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT);
        assertEq(lastReportCaller, address(forwarder));

        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, sentinel);

        uint256 postShares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        assertEq(postShares, shares);
    }

    /// @notice When redeemable shares floor to 0 assets, report still runs and redeem is never called
    function testReportAndForwardZeroAssetsPassthrough() public {
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        _storeUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT, shares);
        _storeUInt256(address(mockStrategy), MFS_CONVERT_TO_ASSETS_SLOT, 0);
        _storeUInt256(address(mockStrategy), MFS_EXPECTED_CONVERT_TO_ASSETS_SHARES_SLOT, shares);
        _storeAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT, address(0));

        uint256 sentinel = type(uint256).max;
        _storeUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT, sentinel);

        vm.prank(_keeper);
        uint256 assets = forwarder.reportAndForward(address(mockStrategy), 0);

        assertEq(assets, 0);

        address lastReportCaller = _loadAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT);
        assertEq(lastReportCaller, address(forwarder));

        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, sentinel);

        uint256 postShares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        assertEq(postShares, shares);
    }

    /// @notice Return value of reportAndForward equals the value returned by redeem
    function testReportAndForwardReturnsRedeemAssets() public {
        // Pre-condition: shares are redeemable and convert to non-zero assets
        _assumeRedeemPath();

        uint256 expectedReturn = _loadUInt256(address(mockStrategy), MFS_REDEEM_RETURN_SLOT);

        vm.prank(_keeper);
        uint256 assets = forwarder.reportAndForward(address(mockStrategy), 0);

        assertEq(assets, expectedReturn);
    }
}
