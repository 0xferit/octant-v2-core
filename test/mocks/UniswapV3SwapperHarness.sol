// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { UniswapV3Swapper } from "src/strategies/periphery/UniswapV3Swapper.sol";

/// @notice Test harness exposing internal functions of UniswapV3Swapper
contract UniswapV3SwapperHarness is UniswapV3Swapper {
    constructor(address _router, address _base) {
        router = _router;
        base = _base;
    }

    function setUniFees(address _token0, address _token1, uint24 _fee) external {
        _setUniFees(_token0, _token1, _fee);
    }

    function swapFrom(address _from, address _to, uint256 _amountIn, uint256 _minAmountOut) external returns (uint256) {
        return _swapFrom(_from, _to, _amountIn, _minAmountOut);
    }

    function swapTo(address _from, address _to, uint256 _amountTo, uint256 _maxAmountFrom) external returns (uint256) {
        return _swapTo(_from, _to, _amountTo, _maxAmountFrom);
    }

    function checkAllowance(address _contract, address _token, uint256 _amount) external {
        _checkAllowance(_contract, _token, _amount);
    }

    function setMinAmountToSell(uint256 _minAmount) external {
        minAmountToSell = _minAmount;
    }
}
