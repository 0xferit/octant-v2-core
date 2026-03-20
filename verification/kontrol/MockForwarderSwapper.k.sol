// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockForwarderSwapper
 * @notice Minimal ISwapper mock for Kontrol formal verification of SwappingYieldForwarder
 * @dev Controllable swap return value with argument capture for property assertions.
 *
 *      Storage layout (all plain slots, no ERC-7201):
 *        slot 0: mockSwapReturn    -- returned by swap()
 *        slot 1: lastSwapReceiver  -- captures receiver arg
 *        slot 2: lastTokenIn       -- captures tokenIn arg
 *        slot 3: lastTokenOut      -- captures tokenOut arg
 *        slot 4: lastAmountIn      -- captures amountIn arg
 *        slot 5: lastMinAmountOut  -- captures minAmountOut arg
 */
contract MockForwarderSwapper {
    uint256 public mockSwapReturn;
    address public lastSwapReceiver;
    address public lastTokenIn;
    address public lastTokenOut;
    uint256 public lastAmountIn;
    uint256 public lastMinAmountOut;

    /// @notice Mock swap that captures arguments and returns controllable output
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver
    ) external returns (uint256) {
        lastTokenIn = tokenIn;
        lastTokenOut = tokenOut;
        lastAmountIn = amountIn;
        lastMinAmountOut = minAmountOut;
        lastSwapReceiver = receiver;
        return mockSwapReturn;
    }
}
