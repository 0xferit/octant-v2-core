// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { AaveV3Strategy } from "src/strategies/yieldDonating/AaveV3Strategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Inline mock for IPoolAddressesProvider
contract MockAddressesProvider {
    address public pool;
    address public dataProvider;

    constructor(address _pool, address _dataProvider) {
        pool = _pool;
        dataProvider = _dataProvider;
    }

    function getPool() external view returns (address) {
        return pool;
    }

    function getPoolDataProvider() external view returns (address) {
        return dataProvider;
    }
}

/// @title Inline mock for IPool (no-op)
contract MockPool {
    function supply(address, uint256, address, uint16) external {}
    function withdraw(address, uint256, address) external pure returns (uint256) {
        return 0;
    }
}

/// @title Inline mock for IPoolDataProvider
contract MockDataProvider {
    address public aToken;
    uint256 public borrowCap;
    uint256 public supplyCap;
    uint256 public totalSupply;

    constructor(address _aToken, uint256 _supplyCap, uint256 _totalSupply) {
        aToken = _aToken;
        supplyCap = _supplyCap;
        totalSupply = _totalSupply;
    }

    function getReserveTokensAddresses(address)
        external
        view
        returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress)
    {
        return (aToken, address(0), address(0));
    }

    function getReserveCaps(address) external view returns (uint256, uint256) {
        return (borrowCap, supplyCap);
    }

    function getATokenTotalSupply(address) external view returns (uint256) {
        return totalSupply;
    }
}

/// @title AaveV3Strategy branch coverage tests
/// @notice Covers 3 uncovered constructor & availableDepositLimit branches
contract AaveV3BranchCoverageTest is Test {
    ERC20Mock public asset;
    YieldDonatingTokenizedStrategy public tokenizedStrategy;

    address management = address(0x1);
    address keeper = address(0x2);
    address emergencyAdmin = address(0x3);
    address donationAddress = address(0x4);

    function setUp() public {
        asset = new ERC20Mock();
        YieldDonatingTokenizedStrategy impl = new YieldDonatingTokenizedStrategy();
        tokenizedStrategy = YieldDonatingTokenizedStrategy(address(new ERC1967Proxy(address(impl), "")));
    }

    /// @notice Constructor reverts when _addressesProvider == address(0) (line 111)
    function test_constructor_zeroAddressesProvider_reverts() public {
        vm.expectRevert("Zero addressesProvider");
        new AaveV3Strategy(
            address(0), // zero addressesProvider
            address(asset),
            "Test Aave",
            "tsAAVE",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(tokenizedStrategy)
        );
    }

    /// @notice Constructor reverts when aToken == address(0) (line 119)
    function test_constructor_zeroAToken_reverts() public {
        MockPool pool = new MockPool();
        // DataProvider returns address(0) for aToken
        MockDataProvider dataProvider = new MockDataProvider(address(0), 0, 0);
        MockAddressesProvider provider = new MockAddressesProvider(address(pool), address(dataProvider));

        vm.expectRevert("Asset not supported by pool");
        new AaveV3Strategy(
            address(provider),
            address(asset),
            "Test Aave",
            "tsAAVE",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(tokenizedStrategy)
        );
    }

    /// @notice availableDepositLimit returns type(uint256).max when supplyCap == 0 (line 135)
    function test_availableDepositLimit_zeroSupplyCap_returnsMax() public {
        // Create valid mocks with supplyCap = 0 (unlimited)
        ERC20Mock mockAToken = new ERC20Mock();
        MockPool pool = new MockPool();
        MockDataProvider dataProvider = new MockDataProvider(address(mockAToken), 0, 0);
        MockAddressesProvider provider = new MockAddressesProvider(address(pool), address(dataProvider));

        AaveV3Strategy strategy = new AaveV3Strategy(
            address(provider),
            address(asset),
            "Test Aave",
            "tsAAVE",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(tokenizedStrategy)
        );

        uint256 limit = strategy.availableDepositLimit(address(this));
        assertEq(limit, type(uint256).max, "Should return max uint when supply cap is 0");
    }
}
