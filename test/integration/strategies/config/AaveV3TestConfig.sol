// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title AaveV3TestConfig
/// @notice Configuration constants for AaveV3 strategy integration tests
library AaveV3TestConfig {
    /// @notice USDC token address on mainnet
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Aave V3 Pool address on mainnet
    address internal constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    /// @notice Aave V3 Addresses Provider on mainnet
    address internal constant AAVE_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    /// @notice Aave V3 Data Provider on mainnet
    address internal constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;

    /// @notice aUSDC V3 token address on mainnet
    address internal constant AUSDC_V3 = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    /// @notice Tokenized strategy implementation address
    address internal constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    /// @notice Minimum deposit amount for fuzz tests (USDC has 6 decimals)
    uint256 internal constant MIN_DEPOSIT = 1e6;

    /// @notice Maximum deposit amount for fuzz tests
    uint256 internal constant MAX_DEPOSIT = 100000e6;

    /// @notice Initial deposit for setup
    uint256 internal constant INITIAL_DEPOSIT = 100000e6;

    /// @notice Asset decimals
    uint8 internal constant DECIMALS = 6;

    /// @notice Strategy name
    string internal constant STRATEGY_NAME = "AaveV3 Donating Strategy";

    /// @notice Strategy symbol
    string internal constant STRATEGY_SYMBOL = "osAAVE";
}
