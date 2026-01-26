// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { SparkDonatingStrategyTest } from "../SparkStrategy.t.sol";

/// @title Spark USDC Vault Strategy Test
/// @author Octant
/// @notice Integration tests for SparkStrategy with SparkDAO USDC vault
/// @dev Extends SparkDonatingStrategyTest with USDC-specific configuration
contract SparkUSDCVaultStrategyTest is SparkDonatingStrategyTest {
    // USDC configuration is the default in SparkDonatingStrategyTest
    // No overrides needed - this test validates USDC works with the base configuration
}
