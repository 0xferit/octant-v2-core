// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title KpkTestConfig
/// @notice Configuration constants for KPK (karpatkey) ERC4626 strategy integration tests
/// @dev KPK vaults are ERC-4626 vaults curated by karpatkey on Morpho and Gearbox V3
library KpkTestConfig {
    /// @notice USDC token address on mainnet
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice WETH token address on mainnet
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @notice wstETH token address on mainnet
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    // ========== MORPHO VAULT ADDRESSES ==========

    /// @notice KPK USDC Prime vault address on mainnet (MetaMorpho ERC-4626)
    address internal constant USDC_KPK_VAULT = 0xe108fbc04852B5df72f9E44d7C29F47e7A993aDd;

    /// @notice KPK ETH Prime vault address on mainnet (MetaMorpho ERC-4626)
    address internal constant WETH_KPK_VAULT = 0xd564F765F9aD3E7d2d6cA782100795a885e8e7C8;

    // ========== GEARBOX V3 POOL ADDRESSES ==========

    /// @notice KPK WETH earn pool on Gearbox V3 (ERC-4626 PoolV3)
    address internal constant GEARBOX_WETH_KPK_POOL = 0x9396DCbf78fc526bb003665337C5E73b699571EF;

    /// @notice KPK wstETH earn pool on Gearbox V3 (ERC-4626 PoolV3)
    address internal constant GEARBOX_WSTETH_KPK_POOL = 0xA9d17f6D3285208280a1Fd9B94479c62e0AABa64;

    /// @notice Tokenized strategy implementation address
    address internal constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    /// @notice Mainnet block used for the Kpk integration fork.
    /// @dev Karpatkey curates the KPK MetaMorpho vaults on Morpho and periodically caps their
    ///      `maxDeposit` to 0 while rebalancing or waiting for liquidity. When the fork runs on
    ///      mainnet `latest`, the deposit-side tests fail with `ERC4626: deposit more than max`
    ///      during those windows even though the strategy code is correct. Pinning to a block
    ///      where all four KPK vaults (ETH Prime, USDC Prime, Gearbox WETH, Gearbox wstETH) are
    ///      uncapped keeps the suite deterministic against curator policy changes. Update only if
    ///      the pinned block itself drifts out of the healthy window.
    uint256 internal constant FORK_BLOCK = 24_800_000;

    // ========== USDC CONFIGURATION ==========

    /// @notice Minimum deposit amount for USDC fuzz tests (6 decimals)
    uint256 internal constant USDC_MIN_DEPOSIT = 1e6;

    /// @notice Maximum deposit amount for USDC fuzz tests
    uint256 internal constant USDC_MAX_DEPOSIT = 100000e6;

    /// @notice Initial deposit for USDC setup
    uint256 internal constant USDC_INITIAL_DEPOSIT = 100000e6;

    /// @notice USDC decimals
    uint8 internal constant USDC_DECIMALS = 6;

    /// @notice Strategy name for USDC
    string internal constant USDC_STRATEGY_NAME = "KPK USDC Prime Donating Strategy";

    /// @notice Strategy symbol for USDC
    string internal constant USDC_STRATEGY_SYMBOL = "osKpkUSDC";

    // ========== WETH CONFIGURATION ==========

    /// @notice Minimum deposit amount for WETH fuzz tests (18 decimals)
    uint256 internal constant WETH_MIN_DEPOSIT = 1e18;

    /// @notice Maximum deposit amount for WETH fuzz tests
    uint256 internal constant WETH_MAX_DEPOSIT = 100e18;

    /// @notice Initial deposit for WETH setup
    uint256 internal constant WETH_INITIAL_DEPOSIT = 100e18;

    /// @notice WETH decimals
    uint8 internal constant WETH_DECIMALS = 18;

    /// @notice Strategy name for WETH
    string internal constant WETH_STRATEGY_NAME = "KPK ETH Prime Donating Strategy";

    /// @notice Strategy symbol for WETH
    string internal constant WETH_STRATEGY_SYMBOL = "osKpkETH";

    // ========== WSTETH CONFIGURATION ==========

    /// @notice Minimum deposit amount for wstETH fuzz tests (18 decimals)
    uint256 internal constant WSTETH_MIN_DEPOSIT = 1e18;

    /// @notice Maximum deposit amount for wstETH fuzz tests
    uint256 internal constant WSTETH_MAX_DEPOSIT = 100e18;

    /// @notice Initial deposit for wstETH setup
    uint256 internal constant WSTETH_INITIAL_DEPOSIT = 100e18;

    /// @notice wstETH decimals
    uint8 internal constant WSTETH_DECIMALS = 18;

    /// @notice Strategy name for Gearbox WETH
    string internal constant GEARBOX_WETH_STRATEGY_NAME = "KPK Gearbox WETH Donating Strategy";

    /// @notice Strategy symbol for Gearbox WETH
    string internal constant GEARBOX_WETH_STRATEGY_SYMBOL = "osKpkGbWETH";

    /// @notice Strategy name for Gearbox wstETH
    string internal constant GEARBOX_WSTETH_STRATEGY_NAME = "KPK Gearbox wstETH Donating Strategy";

    /// @notice Strategy symbol for Gearbox wstETH
    string internal constant GEARBOX_WSTETH_STRATEGY_SYMBOL = "osKpkGbWstETH";

    // ========== TEST-SPECIFIC AMOUNTS ==========

    /// @notice Deposit cap max check amount for USDC (1 billion)
    uint256 internal constant USDC_DEPOSIT_CAP_MAX_CHECK = 1000000000e6;

    /// @notice Deposit cap max check amount for WETH (1 million)
    uint256 internal constant WETH_DEPOSIT_CAP_MAX_CHECK = 1000000e18;

    /// @notice Deposit cap max check amount for wstETH (1 million)
    uint256 internal constant WSTETH_DEPOSIT_CAP_MAX_CHECK = 1000000e18;

    /// @notice Deposit cap excess amount for USDC
    uint256 internal constant USDC_DEPOSIT_CAP_EXCESS = 1000e6;

    /// @notice Deposit cap excess amount for WETH
    uint256 internal constant WETH_DEPOSIT_CAP_EXCESS = 1e18;

    /// @notice Deposit cap excess amount for wstETH
    uint256 internal constant WSTETH_DEPOSIT_CAP_EXCESS = 1e18;

    /// @notice Multi-user test first deposit for USDC (5,000)
    uint256 internal constant USDC_MULTI_USER_DEPOSIT_1 = 5000e6;

    /// @notice Multi-user test second deposit for USDC (3,000)
    uint256 internal constant USDC_MULTI_USER_DEPOSIT_2 = 3000e6;

    /// @notice Multi-user test first deposit for WETH (5)
    uint256 internal constant WETH_MULTI_USER_DEPOSIT_1 = 5e18;

    /// @notice Multi-user test second deposit for WETH (3)
    uint256 internal constant WETH_MULTI_USER_DEPOSIT_2 = 3e18;

    /// @notice Multi-user test first deposit for wstETH (5)
    uint256 internal constant WSTETH_MULTI_USER_DEPOSIT_1 = 5e18;

    /// @notice Multi-user test second deposit for wstETH (3)
    uint256 internal constant WSTETH_MULTI_USER_DEPOSIT_2 = 3e18;
}
