// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { UniswapV3SwapperHarness } from "test/mocks/UniswapV3SwapperHarness.sol";
import { MockUniswapV3Router } from "test/mocks/MockUniswapV3Router.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract UniswapV3SwapperTest is Test {
    UniswapV3SwapperHarness public swapper;
    MockUniswapV3Router public mockRouter;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public baseToken; // WETH-equivalent

    uint24 constant FEE_LOW = 500;
    uint24 constant FEE_MEDIUM = 3000;

    function setUp() public {
        tokenA = new MockERC20(18);
        tokenB = new MockERC20(18);
        baseToken = new MockERC20(18);
        mockRouter = new MockUniswapV3Router();

        swapper = new UniswapV3SwapperHarness(address(mockRouter), address(baseToken));

        // Set up fees
        swapper.setUniFees(address(tokenA), address(baseToken), FEE_LOW);
        swapper.setUniFees(address(baseToken), address(tokenB), FEE_MEDIUM);
        swapper.setUniFees(address(tokenA), address(tokenB), FEE_MEDIUM);

        // Fund the swapper
        tokenA.mint(address(swapper), 100 ether);
        tokenB.mint(address(swapper), 100 ether);
        baseToken.mint(address(swapper), 100 ether);

        vm.label(address(tokenA), "TokenA");
        vm.label(address(tokenB), "TokenB");
        vm.label(address(baseToken), "BaseToken");
        vm.label(address(mockRouter), "MockRouter");
    }

    // --- _setUniFees tests ---

    function test_SetUniFees_SetsBidirectional() public {
        MockERC20 tok0 = new MockERC20(18);
        MockERC20 tok1 = new MockERC20(18);

        swapper.setUniFees(address(tok0), address(tok1), 10000);

        assertEq(swapper.uniFees(address(tok0), address(tok1)), 10000);
        assertEq(swapper.uniFees(address(tok1), address(tok0)), 10000);
    }

    // --- _checkAllowance tests ---

    function test_CheckAllowance_ApprovesWhenInsufficient() public {
        // Initially no allowance
        uint256 allowanceBefore = tokenA.allowance(address(swapper), address(mockRouter));
        assertEq(allowanceBefore, 0);

        swapper.checkAllowance(address(mockRouter), address(tokenA), 10 ether);

        uint256 allowanceAfter = tokenA.allowance(address(swapper), address(mockRouter));
        assertEq(allowanceAfter, 10 ether);
    }

    function test_CheckAllowance_NoOpWhenSufficient() public {
        // Set allowance first
        swapper.checkAllowance(address(mockRouter), address(tokenA), 10 ether);
        uint256 allowance1 = tokenA.allowance(address(swapper), address(mockRouter));

        // Check again with less amount - should not change
        swapper.checkAllowance(address(mockRouter), address(tokenA), 5 ether);
        uint256 allowance2 = tokenA.allowance(address(swapper), address(mockRouter));

        assertEq(allowance1, allowance2, "Allowance should not change when sufficient");
    }

    // --- _swapFrom tests ---

    function test_SwapFrom_ZeroAmount_ReturnsZero() public {
        uint256 result = swapper.swapFrom(address(tokenA), address(baseToken), 0, 0);
        assertEq(result, 0, "Zero amount should return zero");
    }

    function test_SwapFrom_BelowMinAmount_ReturnsZero() public {
        swapper.setMinAmountToSell(10 ether);
        uint256 result = swapper.swapFrom(address(tokenA), address(baseToken), 5 ether, 0);
        assertEq(result, 0, "Amount below min should return zero");
    }

    function test_SwapFrom_DirectSwap_FromIsBase() public {
        // Swap base -> tokenA (direct path since _from == base)
        uint256 result = swapper.swapFrom(address(baseToken), address(tokenA), 1 ether, 0);
        assertEq(result, 1 ether, "Direct swap from base should succeed");
    }

    function test_SwapFrom_DirectSwap_ToIsBase() public {
        // Swap tokenA -> base (direct path since _to == base)
        uint256 result = swapper.swapFrom(address(tokenA), address(baseToken), 1 ether, 0);
        assertEq(result, 1 ether, "Direct swap to base should succeed");
    }

    function test_SwapFrom_MultihopSwap() public {
        // Swap tokenA -> tokenB (multi-hop through base since neither is base)
        uint256 result = swapper.swapFrom(address(tokenA), address(tokenB), 1 ether, 0);
        assertEq(result, 1 ether, "Multi-hop swap should succeed");
    }

    // --- _swapTo tests ---

    function test_SwapTo_ZeroMaxAmount_ReturnsZero() public {
        uint256 result = swapper.swapTo(address(tokenA), address(baseToken), 1 ether, 0);
        assertEq(result, 0, "Zero max amount should return zero");
    }

    function test_SwapTo_BelowMinAmount_ReturnsZero() public {
        swapper.setMinAmountToSell(10 ether);
        uint256 result = swapper.swapTo(address(tokenA), address(baseToken), 1 ether, 5 ether);
        assertEq(result, 0, "Max amount below min should return zero");
    }

    function test_SwapTo_DirectSwap_FromIsBase() public {
        // Swap base -> tokenA (direct path since _from == base)
        uint256 result = swapper.swapTo(address(baseToken), address(tokenA), 1 ether, 2 ether);
        assertEq(result, 1 ether, "Direct exactOutput from base should succeed");
    }

    function test_SwapTo_DirectSwap_ToIsBase() public {
        // Swap tokenA -> base (direct path since _to == base)
        uint256 result = swapper.swapTo(address(tokenA), address(baseToken), 1 ether, 2 ether);
        assertEq(result, 1 ether, "Direct exactOutput to base should succeed");
    }

    function test_SwapTo_MultihopSwap() public {
        // Swap tokenA -> tokenB (multi-hop through base since neither is base)
        uint256 result = swapper.swapTo(address(tokenA), address(tokenB), 1 ether, 2 ether);
        assertEq(result, 1 ether, "Multi-hop exactOutput should succeed");
    }

    function test_SwapTo_ResetsApprovalAfterSwap() public {
        // After a swapTo, allowance should be reset to 0
        swapper.swapTo(address(tokenA), address(baseToken), 1 ether, 2 ether);

        uint256 allowanceAfter = tokenA.allowance(address(swapper), address(mockRouter));
        assertEq(allowanceAfter, 0, "Allowance should be reset to 0 after swapTo");
    }

    // --- state variable tests ---

    function test_DefaultBase() public view {
        assertEq(swapper.base(), address(baseToken), "Base should be set to baseToken");
    }

    function test_DefaultRouter() public view {
        assertEq(swapper.router(), address(mockRouter), "Router should be set to mockRouter");
    }

    function test_MinAmountToSell_Default() public view {
        assertEq(swapper.minAmountToSell(), 0, "Default minAmountToSell should be 0");
    }
}
