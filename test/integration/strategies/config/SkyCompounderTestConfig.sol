// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title SkyCompounderTestConfig
/// @notice Configuration constants for SkyCompounder strategy integration tests
library SkyCompounderTestConfig {
    /// @notice USDS token address on mainnet
    address internal constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;

    /// @notice Sky Protocol Staking Contract on mainnet
    address internal constant STAKING = 0x0650CAF159C5A49f711e8169D4336ECB9b950275;

    /// @notice WETH address on mainnet
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice Minimum deposit amount for fuzz tests
    uint256 internal constant MIN_DEPOSIT = 1e18;

    /// @notice Maximum deposit amount for fuzz tests
    uint256 internal constant MAX_DEPOSIT = 100000e18;

    /// @notice Initial deposit for setup
    uint256 internal constant INITIAL_DEPOSIT = 100000e18;

    /// @notice Asset decimals
    uint8 internal constant DECIMALS = 18;

    /// @notice Strategy name
    string internal constant STRATEGY_NAME = "SkyCompounder Vault Shares";

    /// @notice Strategy symbol
    string internal constant STRATEGY_SYMBOL = "osSKY";
}
