// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { KpkERC4626StrategyTest } from "../KpkERC4626Strategy.t.sol";

/// @title KPK USDC Prime Strategy Test
/// @author Octant
/// @notice Integration tests for ERC4626Strategy with KPK USDC Prime vault on Morpho
/// @dev Extends KpkERC4626StrategyTest with USDC-specific configuration
contract KpkUSDCPrimeStrategyTest is KpkERC4626StrategyTest {
    // USDC configuration is the default in KpkERC4626StrategyTest
    // No overrides needed - this test validates USDC works with the base configuration
}
