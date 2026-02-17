// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { PSMSwapper } from "src/swappers/PSMSwapper.sol";
import { ISwapper } from "src/core/interfaces/ISwapper.sol";
import { SwappingYieldForwarder } from "src/core/SwappingYieldForwarder.sol";
import { MorphoTestConfig } from "test/integration/strategies/config/MorphoTestConfig.sol";
import { BaseSwapperIntegrationTest } from "./base/BaseSwapperIntegrationTest.sol";

/// @title PSMSwapperIntegration
/// @notice Integration test: MorphoCompounder USDC profit → PSM → USDS → receiver
/// @dev Uses LitePSMWrapper (USDC → USDS) via SELL_GEM route on mainnet fork
contract PSMSwapperIntegrationTest is BaseSwapperIntegrationTest {
    // Sky Protocol mainnet addresses
    address internal constant LITE_PSM_WRAPPER = 0xA188EEC8F81263234dA3622A406892F3D630f98c;
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    PSMSwapper public psmSwapper;

    function _targetAsset() internal pure override returns (address) {
        return USDS;
    }

    function _deploySwapper() internal override returns (ISwapper) {
        psmSwapper = new PSMSwapper(
            LITE_PSM_WRAPPER,
            PSMSwapper.Route.SELL_GEM,
            MorphoTestConfig.USDC,
            USDS,
            0 // conversionFactor not needed for SELL_GEM
        );
        return ISwapper(address(psmSwapper));
    }

    function _labelSwapperAddresses() internal override {
        vm.label(LITE_PSM_WRAPPER, "LitePSMWrapper");
        vm.label(USDS, "USDS");
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

    function test_reportSwapAndForward_fullFlow_PSM() public {
        _test_reportSwapAndForward_fullFlow();
    }

    function test_reportSwapAndForward_zeroProfit_PSM() public {
        _test_reportSwapAndForward_zeroProfit();
    }

    function test_reportSwapAndForward_multipleReports_PSM() public {
        _test_reportSwapAndForward_multipleReports();
    }

    function test_reportSwapAndForward_emitsEvent_PSM() public {
        _test_reportSwapAndForward_emitsEvent();
    }

    // ========== ACCESS CONTROL ==========

    function test_onlyKeeper_reportAndForward_PSM() public {
        _test_onlyKeeper_reportAndForward();
    }

    function test_onlyKeeper_reportSwapAndForward_PSM() public {
        _test_onlyKeeper_reportSwapAndForward();
    }

    // ========== PSM-SPECIFIC TESTS ==========

    /// @notice PSM SELL_GEM is 1:1 (currently 0% fee), verify output matches input closely
    function test_psmSwap_nearOneToOne() public {
        _depositAndReport(DEPOSIT_AMOUNT);

        uint256 profit = 1_000e6; // 1k USDC
        _simulateProfit(profit);

        vm.prank(keeperEOA);
        uint256 assetsOut = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);

        _clearMocks();

        // PSM has 0% fee currently, so USDS output should be very close to USDC input
        // USDC has 6 decimals, USDS has 18 decimals, so we need to scale
        // 1 USDC (1e6) → 1 USDS (1e18) through PSM
        // assetsOut is in USDS (18 decimals)
        assertGt(assetsOut, 0, "PSM should produce nonzero USDS output");

        // Receiver should have USDS, not USDC
        assertGt(ERC20(USDS).balanceOf(receiver), 0, "Receiver should have USDS");
    }

    /// @notice Verify swapper immutables are correctly set
    function test_psmSwapper_config() public view {
        assertEq(psmSwapper.protocol(), LITE_PSM_WRAPPER);
        assertEq(uint256(psmSwapper.route()), uint256(PSMSwapper.Route.SELL_GEM));
        assertEq(psmSwapper.tokenIn(), MorphoTestConfig.USDC);
        assertEq(psmSwapper.tokenOut(), USDS);
    }
}
