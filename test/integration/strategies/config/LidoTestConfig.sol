// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title LidoTestConfig
/// @notice Configuration constants for Lido strategy integration tests
library LidoTestConfig {
    /// @notice wstETH token address on mainnet
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @notice Tokenized strategy implementation address
    address internal constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    /// @notice Function signature for exchange rate query
    string internal constant EXCHANGE_RATE_SELECTOR = "stEthPerToken()";

    /// @notice Fork block number (latest - 90 days)
    uint256 internal constant FORK_BLOCK = 22508883 - 6500 * 90;

    /// @notice Minimum deposit amount for fuzz tests
    uint256 internal constant MIN_DEPOSIT = 0.01e18;

    /// @notice Maximum deposit amount for fuzz tests
    uint256 internal constant MAX_DEPOSIT = 10000e18;

    /// @notice Initial deposit for setup
    uint256 internal constant INITIAL_DEPOSIT = 100000e18;

    /// @notice Asset decimals
    uint8 internal constant DECIMALS = 18;

    /// @notice Strategy name
    string internal constant STRATEGY_NAME = "Lido Vault Shares";

    /// @notice Strategy symbol
    string internal constant STRATEGY_SYMBOL = "osLIDO";
}
