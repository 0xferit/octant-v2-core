// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { AaveV3Strategy } from "src/strategies/yieldDonating/AaveV3Strategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract MockPool {
    function supply(address, uint256, address, uint16) external {}
    function withdraw(address, uint256, address) external pure returns (uint256) {
        return 0;
    }
    function getReserveNormalizedIncome(address) external pure returns (uint256) {
        return 1e27;
    }
}

/// @notice Static data provider with caller-controlled paused flag and supply cap.
contract StaticDataProvider {
    address public aToken;
    bool public paused;
    uint256 public supplyCap;

    constructor(address _aToken, bool _paused, uint256 _supplyCap) {
        aToken = _aToken;
        paused = _paused;
        supplyCap = _supplyCap;
    }

    function getReserveTokensAddresses(
        address
    ) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress) {
        return (aToken, address(0), address(0));
    }

    function getReserveCaps(address) external view returns (uint256, uint256) {
        return (0, supplyCap);
    }

    function getATokenTotalSupply(address) external pure returns (uint256) {
        return 0;
    }

    function getReserveConfigurationData(
        address
    ) external pure returns (uint256, uint256, uint256, uint256, uint256, bool, bool, bool, bool, bool) {
        return (0, 0, 0, 0, 0, false, false, false, true, false);
    }

    function getPaused(address) external view returns (bool) {
        return paused;
    }

    function getReserveData(
        address
    )
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint40
        )
    {
        return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }
}

/// @notice AddressesProvider with a settable data provider pointer — emulates Aave
///         governance rotating the PoolDataProvider via AIP.
contract RotatingAddressesProvider {
    address public pool;
    address public dataProvider;

    constructor(address _pool, address _dataProvider) {
        pool = _pool;
        dataProvider = _dataProvider;
    }

    function setDataProvider(address newDataProvider) external {
        dataProvider = newDataProvider;
    }

    function getPool() external view returns (address) {
        return pool;
    }

    function getPoolDataProvider() external view returns (address) {
        return dataProvider;
    }
}

/// @notice Issue 51 -- the pre-fix code cached `dataProvider` as `immutable` from
///         `addressesProvider.getPoolDataProvider()` at construction time. Aave rotates
///         its PoolDataProvider periodically (the Pool itself is a transparent proxy and
///         is stable, but the data provider is a fresh deployment per AIP). A cached
///         pointer keeps reading stale supply caps and pause flags forever. The fix
///         resolves the data provider from `addressesProvider` on every limit query.
contract AaveV3DataProviderRotationTest is Test {
    AaveV3Strategy internal strategy;
    ERC20Mock internal asset;
    ERC20Mock internal aToken;
    RotatingAddressesProvider internal addressesProvider;
    StaticDataProvider internal initialDataProvider;

    address internal management = address(0x1);
    address internal keeper = address(0x2);
    address internal emergencyAdmin = address(0x3);
    address internal donationAddress = address(0x4);

    function setUp() public {
        asset = new ERC20Mock();
        aToken = new ERC20Mock();
        MockPool pool = new MockPool();

        // Initial: not paused, large cap → headroom positive.
        initialDataProvider = new StaticDataProvider(address(aToken), false, 1000);
        addressesProvider = new RotatingAddressesProvider(address(pool), address(initialDataProvider));

        YieldDonatingTokenizedStrategy impl = new YieldDonatingTokenizedStrategy();

        strategy = new AaveV3Strategy(
            address(addressesProvider),
            address(0), // rewardsController not exercised in rotation tests
            address(asset),
            "Test Aave",
            "tsAAVE",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(impl)
        );
    }

    /// @notice After Aave rotates the PoolDataProvider, the strategy must observe
    ///         the new provider's state. Pre-fix: `dataProvider` was cached as
    ///         `immutable`, so `availableDepositLimit` would still consult the old
    ///         provider that reports `paused=false` and return positive headroom.
    function test_rotationFlippingPause_reflectsImmediately() public {
        // Baseline: reserve open → headroom positive.
        assertGt(strategy.availableDepositLimit(address(0)), 0, "baseline must have headroom");

        // Aave governance rotates to a new PoolDataProvider that reports the reserve as paused.
        StaticDataProvider rotated = new StaticDataProvider(address(aToken), true, 1000);
        addressesProvider.setDataProvider(address(rotated));

        // Post-fix: limit reads the current data provider → 0.
        // Pre-fix: limit reads the cached immutable → still > 0.
        assertEq(strategy.availableDepositLimit(address(0)), 0, "rotation to paused provider must zero deposit limit");
        assertEq(
            strategy.availableWithdrawLimit(address(0)),
            0,
            "rotation to paused provider must zero withdraw limit"
        );
    }

    /// @notice The public `dataProvider()` view must report the CURRENT value from
    ///         `addressesProvider`, not a snapshot. Pre-fix this assertion fails with
    ///         the original (cached) address.
    function test_dataProviderAccessor_returnsCurrentAddress() public {
        assertEq(
            address(strategy.dataProvider()),
            address(initialDataProvider),
            "initial state - accessor returns initial provider"
        );

        StaticDataProvider rotated = new StaticDataProvider(address(aToken), false, 2000);
        addressesProvider.setDataProvider(address(rotated));

        assertEq(
            address(strategy.dataProvider()),
            address(rotated),
            "after rotation - accessor must return the NEW provider, not the cached one"
        );
    }
}
