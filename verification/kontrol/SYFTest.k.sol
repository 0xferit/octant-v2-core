// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { YieldForwarder } from "src/core/YieldForwarder.sol";

import { SYFSetup } from "test/kontrol/SYFSetup.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title SYFTest
 * @notice Kontrol formal verification proofs for SwappingYieldForwarder
 * @dev Proves 9 behavioral properties of the SwappingYieldForwarder contract:
 *      1. Access control on reportSwapAndForward
 *      2. Swap output routed to hardcoded receiver
 *      3. No residual source asset after swap
 *      4. Zero-share passthrough (no swap/redeem)
 *      5. Zero-redeem passthrough (no swap when redeem returns 0)
 *      6. Zero-maxRedeem passthrough (no swap/redeem)
 *      7. Zero-convertToAssets passthrough (no swap/redeem)
 *      8. Correct token routing through swapper
 *      9. Inherited reportAndForward access control still works
 */
contract SYFTest is SYFSetup {
    function _assumeSwapPath() internal view returns (uint256 shares, uint256 redeemReturn) {
        shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        uint256 maxRedeem = _loadUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT);
        vm.assume(maxRedeem > 0);

        uint256 convertibleAssets = _loadUInt256(address(mockStrategy), MFS_CONVERT_TO_ASSETS_SLOT);
        vm.assume(convertibleAssets > 0);

        redeemReturn = _loadUInt256(address(mockStrategy), MFS_REDEEM_RETURN_SLOT);
        vm.assume(redeemReturn > 0);
    }

    /// @notice Non-keeper address always reverts with OnlyKeeper on reportSwapAndForward
    function testReportSwapAndForwardOnlyKeeper() public {
        address nonKeeper = makeAddr("NON_KEEPER");

        vm.prank(nonKeeper);
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        syfForwarder.reportSwapAndForward(address(mockStrategy), 0, 0, block.timestamp + 1 hours);
    }

    /// @notice swap() is always called with the hardcoded receiver as output recipient
    function testReportSwapAndForwardReceiverGuarantee() public {
        // Pre-conditions: shares are redeemable, convert to assets, and redeem returns non-zero
        _assumeSwapPath();

        vm.prank(_keeper);
        syfForwarder.reportSwapAndForward(address(mockStrategy), 0, 0, block.timestamp + 1 hours);

        // Assert: swap was called with receiver == forwarder.receiver()
        address lastReceiver = _loadAddress(address(mockSwapper), MSWP_LAST_RECEIVER_SLOT);
        assertEq(lastReceiver, _receiver);
    }

    /// @notice After reportSwapAndForward, forwarder holds 0 of source asset
    function testReportSwapAndForwardNoResidualSourceAsset() public {
        // Pre-conditions: shares are redeemable, convert to assets, and redeem returns non-zero
        _assumeSwapPath();

        vm.prank(_keeper);
        syfForwarder.reportSwapAndForward(address(mockStrategy), 0, 0, block.timestamp + 1 hours);

        // Assert: forwarder's source asset balance is 0 (all transferred to swapper)
        uint256 forwarderBalance = sourceAsset.balanceOf(address(syfForwarder));
        assertEq(forwarderBalance, 0);
    }

    /// @notice When shares == 0, report still runs and the function returns 0 without swap or redeem
    function testReportSwapAndForwardZeroSharesPassthrough() public {
        // Set shares to 0
        _storeUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT, 0);
        _storeAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT, address(0));

        // Write sentinels to detect any call to redeem or swap, including
        // redeem(0, ...) which would be indistinguishable from "never called"
        // if the default were 0.
        uint256 sentinel = type(uint256).max;
        _storeUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT, sentinel);
        _storeUInt256(address(mockSwapper), MSWP_LAST_AMOUNT_IN_SLOT, sentinel);

        vm.prank(_keeper);
        uint256 assetsOut = syfForwarder.reportSwapAndForward(address(mockStrategy), 0, 0, block.timestamp + 1 hours);

        // Assert: returned 0
        assertEq(assetsOut, 0);

        // Assert: report still ran before the zero-share early return
        address lastReportCaller = _loadAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT);
        assertEq(lastReportCaller, address(syfForwarder));

        // Assert: swap was never called (sentinel preserved)
        uint256 lastAmountIn = _loadUInt256(address(mockSwapper), MSWP_LAST_AMOUNT_IN_SLOT);
        assertEq(lastAmountIn, sentinel);

        // Assert: redeem was never called (sentinel preserved)
        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, sentinel);
    }

    /// @notice When redeem returns 0 assets (but shares > 0), returns 0 without swap
    function testReportSwapAndForwardZeroRedeemPassthrough() public {
        // Set shares > 0 but redeem return to 0
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);
        _storeUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT, shares);
        _storeUInt256(address(mockStrategy), MFS_CONVERT_TO_ASSETS_SLOT, 1);
        _storeUInt256(address(mockStrategy), MFS_REDEEM_RETURN_SLOT, 0);

        // Also zero out the forwarder's pre-loaded ERC20 balance (matches 0 redeem)
        _storeMappingUInt256(address(sourceAsset), ERC20_BALANCES_SLOT, uint256(uint160(address(syfForwarder))), 0, 0);

        vm.prank(_keeper);
        uint256 assetsOut = syfForwarder.reportSwapAndForward(address(mockStrategy), 0, 0, block.timestamp + 1 hours);

        // Assert: returned 0
        assertEq(assetsOut, 0);

        // Assert: swap was never called
        address lastSwapReceiver = _loadAddress(address(mockSwapper), MSWP_LAST_RECEIVER_SLOT);
        assertEq(lastSwapReceiver, address(0));
    }

    /// @notice When maxRedeem is 0, report still runs and neither redeem nor swap is called
    function testReportSwapAndForwardZeroMaxRedeemPassthrough() public {
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        _storeUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT, 0);
        _storeUInt256(address(mockStrategy), MFS_CONVERT_TO_ASSETS_SLOT, 1);
        _storeAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT, address(0));

        uint256 sentinel = type(uint256).max;
        _storeUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT, sentinel);
        _storeUInt256(address(mockSwapper), MSWP_LAST_AMOUNT_IN_SLOT, sentinel);

        vm.prank(_keeper);
        uint256 assetsOut = syfForwarder.reportSwapAndForward(address(mockStrategy), 0, 0, block.timestamp + 1 hours);

        assertEq(assetsOut, 0);

        address lastReportCaller = _loadAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT);
        assertEq(lastReportCaller, address(syfForwarder));

        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, sentinel);

        uint256 lastAmountIn = _loadUInt256(address(mockSwapper), MSWP_LAST_AMOUNT_IN_SLOT);
        assertEq(lastAmountIn, sentinel);

        uint256 postShares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        assertEq(postShares, shares);
    }

    /// @notice When redeemable shares floor to 0 assets, report still runs without redeeming or swapping
    function testReportSwapAndForwardZeroAssetsPassthrough() public {
        uint256 shares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        vm.assume(shares > 0);

        _storeUInt256(address(mockStrategy), MFS_MAX_REDEEM_SLOT, shares);
        _storeUInt256(address(mockStrategy), MFS_CONVERT_TO_ASSETS_SLOT, 0);
        _storeAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT, address(0));

        uint256 sentinel = type(uint256).max;
        _storeUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT, sentinel);
        _storeUInt256(address(mockSwapper), MSWP_LAST_AMOUNT_IN_SLOT, sentinel);

        vm.prank(_keeper);
        uint256 assetsOut = syfForwarder.reportSwapAndForward(address(mockStrategy), 0, 0, block.timestamp + 1 hours);

        assertEq(assetsOut, 0);

        address lastReportCaller = _loadAddress(address(mockStrategy), MFS_LAST_REPORT_CALLER_SLOT);
        assertEq(lastReportCaller, address(syfForwarder));

        uint256 lastShares = _loadUInt256(address(mockStrategy), MFS_LAST_SHARES_SLOT);
        assertEq(lastShares, sentinel);

        uint256 lastAmountIn = _loadUInt256(address(mockSwapper), MSWP_LAST_AMOUNT_IN_SLOT);
        assertEq(lastAmountIn, sentinel);

        uint256 postShares = _loadUInt256(address(mockStrategy), MFS_SHARE_BALANCE_SLOT);
        assertEq(postShares, shares);
    }

    /// @notice swap() is called with tokenIn = strategy.asset() and tokenOut = targetAsset
    function testReportSwapAndForwardCorrectTokenRouting() public {
        // Pre-conditions: shares are redeemable, convert to assets, and redeem returns non-zero
        (, uint256 redeemReturn) = _assumeSwapPath();
        uint256 maxLoss = freshUInt256Bounded();
        uint256 minAmountOut = freshUInt256Bounded();
        uint256 swapReturn = _loadUInt256(address(mockSwapper), MSWP_RETURN_SLOT);
        vm.assume(swapReturn >= minAmountOut);

        vm.prank(_keeper);
        syfForwarder.reportSwapAndForward(address(mockStrategy), maxLoss, minAmountOut, block.timestamp + 1 hours);

        // Assert: tokenIn == sourceAsset (strategy's underlying)
        address lastTokenIn = _loadAddress(address(mockSwapper), MSWP_LAST_TOKEN_IN_SLOT);
        assertEq(lastTokenIn, address(sourceAsset));

        // Assert: tokenOut == targetAsset (forwarder's configured target)
        address lastTokenOut = _loadAddress(address(mockSwapper), MSWP_LAST_TOKEN_OUT_SLOT);
        assertEq(lastTokenOut, address(targetAsset));

        // Assert: amountIn == redeemReturn
        uint256 lastAmountIn = _loadUInt256(address(mockSwapper), MSWP_LAST_AMOUNT_IN_SLOT);
        assertEq(lastAmountIn, redeemReturn);

        // Assert: minAmountOut is forwarded unchanged to the swapper
        uint256 lastMinAmountOut = _loadUInt256(address(mockSwapper), MSWP_LAST_MIN_AMOUNT_OUT_SLOT);
        assertEq(lastMinAmountOut, minAmountOut);

        // Assert: redeem is executed on behalf of and back into the forwarder
        address lastRedeemReceiver = _loadAddress(address(mockStrategy), MFS_LAST_RECEIVER_SLOT);
        assertEq(lastRedeemReceiver, address(syfForwarder));

        address lastRedeemOwner = _loadAddress(address(mockStrategy), MFS_LAST_OWNER_SLOT);
        assertEq(lastRedeemOwner, address(syfForwarder));

        uint256 lastRedeemMaxLoss = _loadUInt256(address(mockStrategy), MFS_LAST_MAX_LOSS_SLOT);
        assertEq(lastRedeemMaxLoss, maxLoss);
    }

    /// @notice Inherited reportAndForward() on SwappingYieldForwarder still enforces keeper check
    function testInheritedReportAndForwardAccessControl() public {
        address nonKeeper = makeAddr("NON_KEEPER");

        vm.prank(nonKeeper);
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        syfForwarder.reportAndForward(address(mockStrategy), 0);
    }
}
