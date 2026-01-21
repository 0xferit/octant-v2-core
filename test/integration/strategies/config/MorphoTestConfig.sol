// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title MorphoTestConfig
/// @notice Configuration constants for MorphoCompounder strategy integration tests
library MorphoTestConfig {
    /// @notice USDC token address on mainnet
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Steakhouse USDC Morpho vault address on mainnet
    address internal constant MORPHO_VAULT = 0x074134A2784F4F66b6ceD6f68849382990Ff3215;

    /// @notice Tokenized strategy implementation address
    address internal constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    /// @notice Morpho Blue vault address
    address internal constant MORPHO_BLUE_VAULT = 0xBEEF01735c132Ada46AA9aA4c54623cAA92A64CB;

    /// @notice Fork block number (latest - 90 days)
    uint256 internal constant FORK_BLOCK = 22508883 - 6500 * 90;

    /// @notice Minimum deposit amount for fuzz tests (USDC has 6 decimals)
    uint256 internal constant MIN_DEPOSIT = 1e6;

    /// @notice Maximum deposit amount for fuzz tests
    uint256 internal constant MAX_DEPOSIT = 100000e6;

    /// @notice Initial deposit for setup
    uint256 internal constant INITIAL_DEPOSIT = 100000e6;

    /// @notice Asset decimals
    uint8 internal constant DECIMALS = 6;

    /// @notice Strategy name
    string internal constant STRATEGY_NAME = "MorphoCompounder Donating Strategy";

    /// @notice Strategy symbol
    string internal constant STRATEGY_SYMBOL = "osMORPHO";
}
