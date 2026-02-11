// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BaseYieldSkimmingHealthCheck } from "src/strategies/periphery/BaseYieldSkimmingHealthCheck.sol";

/**
 * @title MockSimpleYieldSkimmingStrategy
 * @notice Minimal YieldSkimming strategy for Kontrol formal verification proofs
 * @dev Extends BaseYieldSkimmingHealthCheck with controllable exchange rate and
 *      _harvestAndReport() return value. Does not interact with any external yield
 *      source -- pure accounting mock.
 *
 *      Regular storage layout:
 *        Slot 0: BaseYieldSkimmingHealthCheck packed (doHealthCheck, profitLimitRatio, lossLimitRatio)
 *        Slot 1: nextTotalAssets (uint256)
 *        Slot 2: mockExchangeRate (uint256)
 *        Slot 3: mockExchangeRateDecimals (uint256)
 */
contract MockSimpleYieldSkimmingStrategy is BaseYieldSkimmingHealthCheck {
    /// @notice Value returned by _harvestAndReport(). Set via setNextTotalAssets() or symbolic storage.
    uint256 public nextTotalAssets;

    /// @notice Mock exchange rate returned by getCurrentExchangeRate()
    uint256 public mockExchangeRate;

    /// @notice Mock decimals for exchange rate returned by decimalsOfExchangeRate()
    uint256 public mockExchangeRateDecimals;

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseYieldSkimmingHealthCheck(
            _asset,
            _name,
            _symbol,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {}

    function setNextTotalAssets(uint256 _amount) external {
        nextTotalAssets = _amount;
    }

    function setMockExchangeRate(uint256 _rate) external {
        mockExchangeRate = _rate;
    }

    function setMockExchangeRateDecimals(uint256 _decimals) external {
        mockExchangeRateDecimals = _decimals;
    }

    /// @notice Returns the mock exchange rate (read from storage, set via symbolic or setter)
    function getCurrentExchangeRate() external view returns (uint256) {
        return mockExchangeRate;
    }

    /// @notice Returns the mock decimals for exchange rate
    function decimalsOfExchangeRate() external view returns (uint256) {
        return mockExchangeRateDecimals;
    }

    function _harvestAndReport() internal view override returns (uint256) {
        return nextTotalAssets;
    }

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _emergencyWithdraw(uint256) internal override {}
}
