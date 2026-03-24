// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { KpkERC4626StrategyTest } from "../KpkERC4626Strategy.t.sol";
import { KpkTestConfig } from "../../config/KpkTestConfig.sol";

/// @title KPK Gearbox WETH Strategy Test
/// @author Octant
/// @notice Integration tests for ERC4626Strategy with KPK WETH earn pool on Gearbox V3
/// @dev Gearbox V3 PoolV3 is ERC-4626 compliant, so the generic ERC4626Strategy works.
///      Extends KpkERC4626StrategyTest with Gearbox WETH-specific configuration.
contract KpkGearboxWETHStrategyTest is KpkERC4626StrategyTest {
    // ========== GEARBOX WETH CONFIGURATION OVERRIDES ==========

    function _asset() internal pure override returns (address) {
        return KpkTestConfig.WETH;
    }

    function _strategyName() internal pure override returns (string memory) {
        return KpkTestConfig.GEARBOX_WETH_STRATEGY_NAME;
    }

    function _strategySymbol() internal pure override returns (string memory) {
        return KpkTestConfig.GEARBOX_WETH_STRATEGY_SYMBOL;
    }

    function _initialDeposit() internal pure override returns (uint256) {
        return KpkTestConfig.WETH_INITIAL_DEPOSIT;
    }

    function _compounderVault() internal pure override returns (address) {
        return KpkTestConfig.GEARBOX_WETH_KPK_POOL;
    }

    function _minDeposit() internal pure override returns (uint256) {
        return KpkTestConfig.WETH_MIN_DEPOSIT;
    }

    function _maxDeposit() internal pure override returns (uint256) {
        return KpkTestConfig.WETH_MAX_DEPOSIT;
    }

    function _decimals() internal pure override returns (uint8) {
        return KpkTestConfig.WETH_DECIMALS;
    }

    // ========== WETH TEST-SPECIFIC CONFIGURATION OVERRIDES ==========

    function _depositCapMaxCheck() internal pure override returns (uint256) {
        return KpkTestConfig.WETH_DEPOSIT_CAP_MAX_CHECK;
    }

    function _depositCapExcess() internal pure override returns (uint256) {
        return KpkTestConfig.WETH_DEPOSIT_CAP_EXCESS;
    }

    function _multiUserDeposit1() internal pure override returns (uint256) {
        return KpkTestConfig.WETH_MULTI_USER_DEPOSIT_1;
    }

    function _multiUserDeposit2() internal pure override returns (uint256) {
        return KpkTestConfig.WETH_MULTI_USER_DEPOSIT_2;
    }
}
