// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapRouter } from "@tokenized-strategy-periphery/interfaces/Uniswap/V3/ISwapRouter.sol";

interface MockMintable {
    function mint(address to, uint256 amount) external;
}

/// @notice Mock Uniswap V3 router for unit testing UniswapV3Swapper
/// @dev Simulates swaps by transferring tokens at 1:1 rate
contract MockUniswapV3Router {
    function exactInputSingle(
        ISwapRouter.ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut) {
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = params.amountIn; // 1:1 mock swap
        MockMintable(params.tokenOut).mint(params.recipient, amountOut);
        return amountOut;
    }

    function exactInput(
        ISwapRouter.ExactInputParams calldata params
    ) external payable returns (uint256 amountOut) {
        // Decode first token from path (first 20 bytes)
        address tokenIn;
        bytes calldata path = params.path;
        assembly {
            tokenIn := shr(96, calldataload(path.offset))
        }
        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = params.amountIn; // 1:1 mock swap

        // Decode last token from path (last 20 bytes)
        address tokenOut;
        uint256 pathLen = path.length;
        assembly {
            tokenOut := shr(96, calldataload(add(path.offset, sub(pathLen, 20))))
        }
        MockMintable(tokenOut).mint(params.recipient, amountOut);
        return amountOut;
    }

    function exactOutputSingle(
        ISwapRouter.ExactOutputSingleParams calldata params
    ) external payable returns (uint256 amountIn) {
        amountIn = params.amountOut; // 1:1 mock swap
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockMintable(params.tokenOut).mint(params.recipient, params.amountOut);
        return amountIn;
    }

    function exactOutput(
        ISwapRouter.ExactOutputParams calldata params
    ) external payable returns (uint256 amountIn) {
        amountIn = params.amountOut; // 1:1 mock swap

        // For exactOutput, the path is reversed: tokenOut is first, tokenIn is last
        address tokenOut;
        address tokenIn;
        bytes calldata path = params.path;
        uint256 pathLen = path.length;
        assembly {
            tokenOut := shr(96, calldataload(path.offset))
            tokenIn := shr(96, calldataload(add(path.offset, sub(pathLen, 20))))
        }
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockMintable(tokenOut).mint(params.recipient, params.amountOut);
        return amountIn;
    }
}
