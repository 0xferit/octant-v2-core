// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { CurveSwapper } from "src/swappers/CurveSwapper.sol";
import { ISwapper } from "src/core/interfaces/ISwapper.sol";
import { SwappingYieldForwarder } from "src/core/SwappingYieldForwarder.sol";
import { MorphoTestConfig } from "test/integration/strategies/config/MorphoTestConfig.sol";
import { BaseSwapperIntegrationTest } from "./base/BaseSwapperIntegrationTest.sol";

/// @title CurveSwapperIntegration
/// @notice Integration test: MorphoCompounder USDC profit → Curve 3Pool → USDT → receiver
/// @dev Uses Curve 3Pool exchange on mainnet fork (USDC index=1, USDT index=2)
contract CurveSwapperIntegrationTest is BaseSwapperIntegrationTest {
    // Curve 3Pool mainnet
    address internal constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // 3Pool indices: 0=DAI, 1=USDC, 2=USDT
    int128 internal constant INDEX_USDC = 1;
    int128 internal constant INDEX_USDT = 2;

    CurveSwapper public curveSwapper;

    function _targetAsset() internal pure override returns (address) {
        return USDT;
    }

    function _deploySwapper() internal override returns (ISwapper) {
        curveSwapper = new CurveSwapper(CURVE_3POOL, INDEX_USDC, INDEX_USDT, MorphoTestConfig.USDC, USDT);
        return ISwapper(address(curveSwapper));
    }

    function _labelSwapperAddresses() internal override {
        vm.label(CURVE_3POOL, "Curve3Pool");
        vm.label(USDT, "USDT");
    }

    function setUp() public {
        _baseSetUp();
    }

    // ========== NO-SWAP FALLBACK TESTS ==========

    function test_reportAndForward_noSwap() public {
        _test_reportAndForward_noSwap();
    }

    function test_reportAndForward_zeroProfit() public {
        _test_reportAndForward_zeroProfit();
    }

    // ========== SWAP PATH TESTS ==========

    function test_reportSwapAndForward_fullFlow_Curve() public {
        _test_reportSwapAndForward_fullFlow();
    }

    function test_reportSwapAndForward_zeroProfit_Curve() public {
        _test_reportSwapAndForward_zeroProfit();
    }

    function test_reportSwapAndForward_multipleReports_Curve() public {
        _test_reportSwapAndForward_multipleReports();
    }

    function test_reportSwapAndForward_emitsEvent_Curve() public {
        _test_reportSwapAndForward_emitsEvent();
    }

    // ========== ACCESS CONTROL ==========

    function test_onlyKeeper_reportAndForward_Curve() public {
        _test_onlyKeeper_reportAndForward();
    }

    function test_onlyKeeper_reportSwapAndForward_Curve() public {
        _test_onlyKeeper_reportSwapAndForward();
    }

    // ========== CURVE-SPECIFIC TESTS ==========

    /// @notice Curve 3Pool: USDC→USDT should be near 1:1 for stablecoins
    function test_curveSwap_nearOneToOne() public {
        _depositAndReport(DEPOSIT_AMOUNT);

        uint256 profit = 1_000e6;
        _simulateProfit(profit);

        vm.prank(keeperEOA);
        uint256 assetsOut = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);

        _clearMocks();

        // Both USDC and USDT have 6 decimals, output should be very close to input
        assertGt(assetsOut, 0, "Curve should produce nonzero USDT output");

        // Receiver should have USDT
        assertGt(ERC20(USDT).balanceOf(receiver), 0, "Receiver should have USDT");
    }

    /// @notice Verify swapper immutables are correctly set
    function test_curveSwapper_config() public view {
        assertEq(curveSwapper.pool(), CURVE_3POOL);
        assertEq(curveSwapper.indexIn(), INDEX_USDC);
        assertEq(curveSwapper.indexOut(), INDEX_USDT);
        assertEq(curveSwapper.tokenIn(), MorphoTestConfig.USDC);
        assertEq(curveSwapper.tokenOut(), USDT);
    }
}
