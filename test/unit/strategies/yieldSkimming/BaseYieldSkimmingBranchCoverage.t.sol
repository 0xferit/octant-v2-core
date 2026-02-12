// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { BaseYieldSkimmingStrategy } from "src/strategies/yieldSkimming/BaseYieldSkimmingStrategy.sol";
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

/// @title Concrete implementation of BaseYieldSkimmingStrategy for testing
contract ConcreteYieldSkimmingStrategy is BaseYieldSkimmingStrategy {
    uint256 private _rate;

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
        BaseYieldSkimmingStrategy(
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
    {
        _rate = 1e18;
    }

    function _getCurrentExchangeRate() internal view override returns (uint256) {
        return _rate;
    }

    function decimalsOfExchangeRate() public pure override returns (uint256) {
        return 18;
    }
}

/// @title BaseYieldSkimmingStrategy branch coverage tests
/// @notice Covers balanceOfAsset(), getCurrentExchangeRate(), _freeFunds() no-op, and _harvestAndReport()
contract BaseYieldSkimmingBranchCoverageTest is Test {
    ERC20Mock public asset;
    YieldSkimmingTokenizedStrategy public implementation;
    ConcreteYieldSkimmingStrategy public strategy;

    address management = address(0x1);
    address keeper = address(0x2);
    address emergencyAdmin = address(0x3);
    address donationAddress = address(0x4);

    function setUp() public {
        asset = new ERC20Mock();

        // Use YieldSkimmingTokenizedStrategy (not YieldDonating) because
        // BaseYieldSkimmingHealthCheck._executeHealthCheck calls getLastRateRay()
        // which only exists on YieldSkimmingTokenizedStrategy
        implementation = new YieldSkimmingTokenizedStrategy();

        strategy = new ConcreteYieldSkimmingStrategy(
            address(asset),
            "Test YieldSkim",
            "tsYS",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(implementation)
        );
    }

    /// @notice balanceOfAsset() returns correct balance (lines 76-77)
    function test_balanceOfAsset_returnsBalance() public {
        assertEq(strategy.balanceOfAsset(), 0, "Should be 0 initially");

        // Mint assets directly to strategy
        asset.mint(address(strategy), 50e18);
        assertEq(strategy.balanceOfAsset(), 50e18, "Should return 50e18");
    }

    /// @notice getCurrentExchangeRate() public wrapper works (line 85-87)
    function test_getCurrentExchangeRate_returnsRate() public view {
        assertEq(strategy.getCurrentExchangeRate(), 1e18, "Should return 1e18");
    }

    /// @notice _freeFunds is a no-op (line 114) - exercised via direct call as self
    function test_freeFunds_noOp() public {
        // Call freeFunds directly as the strategy itself (simulating delegatecall context)
        // Since _deployFunds is also a no-op, withdrawal via TokenizedStrategy never needs
        // to call freeFunds (assets stay idle). So we call it directly to get coverage.
        vm.prank(address(strategy));
        strategy.freeFunds(0);
    }

    /// @notice _harvestAndReport returns totalAssets (line 124-127) - exercised via report
    function test_harvestAndReport_reportsTotalAssets() public {
        asset.mint(address(this), 100e18);
        asset.approve(address(strategy), 100e18);
        ITokenizedStrategy(address(strategy)).deposit(100e18, address(this));

        // Report should succeed and call _harvestAndReport internally
        vm.prank(keeper);
        ITokenizedStrategy(address(strategy)).report();

        assertEq(ITokenizedStrategy(address(strategy)).totalAssets(), 100e18, "totalAssets should be 100e18");
    }
}
