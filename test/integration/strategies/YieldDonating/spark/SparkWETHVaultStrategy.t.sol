// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SparkDonatingStrategyTest } from "../SparkStrategy.t.sol";
import { SparkTestConfig } from "../../config/SparkTestConfig.sol";

/// @title Spark WETH Vault Strategy Test
/// @author Octant
/// @notice Integration tests for SparkStrategy with SparkDAO WETH vault
/// @dev Extends SparkDonatingStrategyTest with WETH-specific configuration
contract SparkWETHVaultStrategyTest is SparkDonatingStrategyTest {
    // ========== WETH CONFIGURATION OVERRIDES ==========

    function _asset() internal pure override returns (address) {
        return SparkTestConfig.WETH;
    }

    function _strategyName() internal pure override returns (string memory) {
        return SparkTestConfig.WETH_STRATEGY_NAME;
    }

    function _strategySymbol() internal pure override returns (string memory) {
        return SparkTestConfig.WETH_STRATEGY_SYMBOL;
    }

    function _initialDeposit() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_INITIAL_DEPOSIT;
    }

    function _compounderVault() internal pure override returns (address) {
        return SparkTestConfig.WETH_SPARK_VAULT;
    }

    function _minDeposit() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_MIN_DEPOSIT;
    }

    function _maxDeposit() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_MAX_DEPOSIT;
    }

    function _decimals() internal pure override returns (uint8) {
        return SparkTestConfig.WETH_DECIMALS;
    }

    // ========== WETH TEST-SPECIFIC CONFIGURATION OVERRIDES ==========

    function _vsrTestDeposit() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_VSR_TEST_DEPOSIT;
    }

    function _depositCapMaxCheck() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_DEPOSIT_CAP_MAX_CHECK;
    }

    function _depositCapExcess() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_DEPOSIT_CAP_EXCESS;
    }

    function _multiUserDeposit1() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_MULTI_USER_DEPOSIT_1;
    }

    function _multiUserDeposit2() internal pure override returns (uint256) {
        return SparkTestConfig.WETH_MULTI_USER_DEPOSIT_2;
    }
}
