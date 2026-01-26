// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title SparkTestConfig
/// @notice Configuration constants for Spark strategy integration tests
library SparkTestConfig {
    /// @notice USDC token address on mainnet
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice WETH token address on mainnet
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice USDT token address on mainnet (for wrong asset tests)
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @notice Spark USDC vault address on mainnet
    address internal constant USDC_SPARK_VAULT = 0x28B3a8fb53B741A8Fd78c0fb9A6B2393d896a43d;

    /// @notice Spark WETH vault address on mainnet
    address internal constant WETH_SPARK_VAULT = 0xfE6eb3b609a7C8352A241f7F3A21CEA4e9209B8f;

    /// @notice Tokenized strategy implementation address
    address internal constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    /// @notice Minimum deposit amount for USDC fuzz tests (6 decimals)
    uint256 internal constant USDC_MIN_DEPOSIT = 1e6;

    /// @notice Maximum deposit amount for USDC fuzz tests
    uint256 internal constant USDC_MAX_DEPOSIT = 100000e6;

    /// @notice Initial deposit for USDC setup
    uint256 internal constant USDC_INITIAL_DEPOSIT = 100000e6;

    /// @notice Minimum deposit amount for WETH fuzz tests (18 decimals)
    uint256 internal constant WETH_MIN_DEPOSIT = 1e18;

    /// @notice Maximum deposit amount for WETH fuzz tests
    uint256 internal constant WETH_MAX_DEPOSIT = 100e18;

    /// @notice Initial deposit for WETH setup
    uint256 internal constant WETH_INITIAL_DEPOSIT = 100e18;

    /// @notice USDC decimals
    uint8 internal constant USDC_DECIMALS = 6;

    /// @notice WETH decimals
    uint8 internal constant WETH_DECIMALS = 18;

    /// @notice Strategy name for USDC
    string internal constant USDC_STRATEGY_NAME = "Spark USDC Donating Strategy";

    /// @notice Strategy symbol for USDC
    string internal constant USDC_STRATEGY_SYMBOL = "osSparkUSDC";

    /// @notice Strategy name for WETH
    string internal constant WETH_STRATEGY_NAME = "Spark WETH Donating Strategy";

    /// @notice Strategy symbol for WETH
    string internal constant WETH_STRATEGY_SYMBOL = "osSparkWETH";

    // ========== TEST-SPECIFIC AMOUNTS ==========

    /// @notice VSR accrual test deposit amount for USDC (10,000 USDC)
    uint256 internal constant USDC_VSR_TEST_DEPOSIT = 10000e6;

    /// @notice VSR accrual test deposit amount for WETH (10 WETH)
    uint256 internal constant WETH_VSR_TEST_DEPOSIT = 10e18;

    /// @notice Deposit cap max check amount for USDC (1 billion)
    uint256 internal constant USDC_DEPOSIT_CAP_MAX_CHECK = 1000000000e6;

    /// @notice Deposit cap max check amount for WETH (1 million)
    uint256 internal constant WETH_DEPOSIT_CAP_MAX_CHECK = 1000000e18;

    /// @notice Deposit cap excess amount for USDC
    uint256 internal constant USDC_DEPOSIT_CAP_EXCESS = 1000e6;

    /// @notice Deposit cap excess amount for WETH
    uint256 internal constant WETH_DEPOSIT_CAP_EXCESS = 1e18;

    /// @notice Multi-user test first deposit for USDC (5,000)
    uint256 internal constant USDC_MULTI_USER_DEPOSIT_1 = 5000e6;

    /// @notice Multi-user test second deposit for USDC (3,000)
    uint256 internal constant USDC_MULTI_USER_DEPOSIT_2 = 3000e6;

    /// @notice Multi-user test first deposit for WETH (5)
    uint256 internal constant WETH_MULTI_USER_DEPOSIT_1 = 5e18;

    /// @notice Multi-user test second deposit for WETH (3)
    uint256 internal constant WETH_MULTI_USER_DEPOSIT_2 = 3e18;
}
