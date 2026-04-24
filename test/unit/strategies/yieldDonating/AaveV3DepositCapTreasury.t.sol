// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { AaveV3Strategy } from "src/strategies/yieldDonating/AaveV3Strategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

/// @dev MockPool with a configurable `getReserveNormalizedIncome`. The strategy's
///      treasury-scaling path reads the projected `nextLiquidityIndex` off IPool
///      (not IPoolDataProvider), so these tests exercise the scaling by flipping
///      this value instead of the stored `liquidityIndex` on the data provider.
contract MockPool {
    uint256 public normalizedIncome = 1e27; // default: RAY (no growth)

    function supply(address, uint256, address, uint16) external {}
    function withdraw(address, uint256, address) external pure returns (uint256) {
        return 0;
    }
    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return normalizedIncome;
    }
    function setNormalizedIncome(uint256 v) external {
        normalizedIncome = v;
    }
}

/// @notice Mock that lets tests configure totalAToken and accruedToTreasuryScaled
///         independently. Pre-fix code only sees `getATokenTotalSupply` (totalAToken),
///         post-fix code reads both and sums them via `getReserveData`.
contract TreasuryAwareDataProvider {
    uint256 internal constant RAY = 1e27;

    address public aToken;
    uint256 public supplyCapWholeTokens;
    uint256 public totalAToken;
    uint256 public accruedToTreasuryScaled;
    uint256 public liquidityIndex = RAY; // default: no growth (scale = 1:1)

    constructor(address _aToken, uint256 _supplyCapWholeTokens) {
        aToken = _aToken;
        supplyCapWholeTokens = _supplyCapWholeTokens;
    }

    function setTotals(uint256 _totalAToken, uint256 _accruedToTreasuryScaled) external {
        totalAToken = _totalAToken;
        accruedToTreasuryScaled = _accruedToTreasuryScaled;
    }

    /// @dev Configure the reserve liquidity index to simulate growth. `_liquidityIndex`
    ///      is in Aave's RAY convention (1e27 = 1.0x = no growth).
    function setLiquidityIndex(uint256 _liquidityIndex) external {
        liquidityIndex = _liquidityIndex;
    }

    function getReserveTokensAddresses(
        address
    ) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress) {
        return (aToken, address(0), address(0));
    }

    function getReserveCaps(address) external view returns (uint256, uint256) {
        return (0, supplyCapWholeTokens);
    }

    // Legacy view — pre-fix code path. Returns only totalAToken (omits treasury accrual).
    function getATokenTotalSupply(address) external view returns (uint256) {
        return totalAToken;
    }

    function getReserveConfigurationData(
        address
    ) external pure returns (uint256, uint256, uint256, uint256, uint256, bool, bool, bool, bool, bool) {
        return (0, 0, 0, 0, 0, false, false, false, true, false); // active, not frozen
    }

    function getPaused(address) external pure returns (bool) {
        return false;
    }

    // Post-fix view — exposes accruedToTreasuryScaled separately so the strategy can
    // include it in cap-headroom math.
    function getReserveData(
        address
    )
        external
        view
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
        return (0, accruedToTreasuryScaled, totalAToken, 0, 0, 0, 0, 0, 0, liquidityIndex, 0, 0);
    }
}

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

/// @notice Issue 45 -- `validateSupply` enforces
///         `(scaledTotalSupply + accruedToTreasury).rayMul(idx) + amount <= cap`.
///         The pre-fix code compared cap against `getATokenTotalSupply` only, which
///         omits the `accruedToTreasury` contribution. That over-reports headroom by
///         exactly `accruedToTreasuryScaled`, sending users into `SUPPLY_CAP_EXCEEDED`
///         reverts. The fix incorporates `accruedToTreasuryScaled` conservatively into
///         the cap denominator.
contract AaveV3DepositCapTreasuryTest is Test {
    AaveV3Strategy internal strategy;
    ERC20Mock internal asset;
    ERC20Mock internal aToken;
    TreasuryAwareDataProvider internal dp;
    MockPool internal pool;

    address internal management = address(0x1);
    address internal keeper = address(0x2);
    address internal emergencyAdmin = address(0x3);
    address internal donationAddress = address(0x4);

    uint256 internal constant SUPPLY_CAP_WHOLE = 1000;
    uint256 internal constant CAP_SCALED = 1000 ether; // 1000 * 1e18

    function setUp() public {
        asset = new ERC20Mock();
        aToken = new ERC20Mock();
        pool = new MockPool();
        dp = new TreasuryAwareDataProvider(address(aToken), SUPPLY_CAP_WHOLE);
        MockAddressesProvider provider = new MockAddressesProvider(address(pool), address(dp));

        YieldDonatingTokenizedStrategy impl = new YieldDonatingTokenizedStrategy();

        strategy = new AaveV3Strategy(
            address(provider),
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

    /// @notice Treasury accrual must reduce reported headroom. Pre-fix code returns
    ///         `cap - totalAToken` (overstated); post-fix returns `cap - (totalAToken + treasury)`.
    function test_treasuryAccrualReducesHeadroom() public {
        // Configure so that:
        //   totalAToken             = 800 ether
        //   accruedToTreasuryScaled = 100 ether
        //   cap                     = 1000 ether
        // Pre-fix headroom: 1000 - 800       = 200 ether (WRONG -- cap is at 900 effectively).
        // Post-fix headroom: 1000 - (800+100) = 100 ether.
        dp.setTotals(800 ether, 100 ether);

        uint256 limit = strategy.availableDepositLimit(address(0));
        assertEq(
            limit,
            100 ether,
            "Headroom must subtract accruedToTreasury -- pre-fix returned 200 ether (overstated by 100 ether)"
        );
    }

    /// @notice When treasury accrual fully consumes remaining cap headroom, the limit
    ///         must be zero. Pre-fix code still reports positive headroom equal to the
    ///         treasury balance, sending depositors into SUPPLY_CAP_EXCEEDED.
    function test_treasuryAccrualSaturatesCap_returnsZero() public {
        // totalAToken + accruedToTreasury equals the scaled cap exactly.
        dp.setTotals(900 ether, 100 ether);

        uint256 limit = strategy.availableDepositLimit(address(0));
        assertEq(limit, 0, "Limit must be zero when treasury accrual fills the cap");
    }

    /// @notice Sanity check: with zero treasury accrual, the limit matches the legacy
    ///         calculation. Locks in that the fix doesn't regress the common case.
    function test_zeroTreasury_matchesLegacyHeadroom() public {
        dp.setTotals(700 ether, 0);
        uint256 limit = strategy.availableDepositLimit(address(0));
        assertEq(limit, 300 ether, "Zero-treasury case must equal cap - totalAToken");
    }

    /// @notice Codex P2 regression -- `accruedToTreasuryScaled` is in scaled (pre-rayMul)
    ///         units while `totalAToken` is in underlying units. When `liquidityIndex > 1e27`
    ///         the old code summed them directly, under-counting treasury contribution and
    ///         overstating headroom. Post-fix the strategy rayMuls treasury into underlying
    ///         units (ceiling-rounded) before adding.
    ///
    ///         Scenario:
    ///           totalAToken             = 800 ether (underlying)
    ///           accruedToTreasuryScaled = 100 ether (scaled; actual underlying = 105 ether)
    ///           liquidityIndex          = 1.05e27
    ///         Pre-fix headroom (raw sum): 1000 - (800 + 100)       = 100 ether (overstated by 5 ether).
    ///         Post-fix headroom:          1000 - (800 + 105)       =  95 ether.
    function test_treasuryAccrual_scalesByLiquidityIndex() public {
        dp.setTotals(800 ether, 100 ether);
        pool.setNormalizedIncome(1.05e27); // 5% reserve growth

        uint256 limit = strategy.availableDepositLimit(address(0));
        assertEq(
            limit,
            95 ether,
            "Headroom must scale treasury by liquidityIndex -- pre-fix returned 100 ether (overstated by 5 ether)"
        );
    }

    /// @notice Ceiling-rounding sanity check: sub-wei fractional residue after rayMul
    ///         must round up so headroom stays conservative. With 1 wei scaled accrual
    ///         and liquidityIndex = 1e27 + 1, `mulDiv(1, 1e27+1, 1e27, Ceil) == 2`;
    ///         floor would give 1. The difference must be visible in the returned limit.
    function test_treasuryAccrual_ceilingDivisionRoundsUp() public {
        dp.setTotals(100 ether, 1);
        pool.setNormalizedIncome(1e27 + 1);

        uint256 limit = strategy.availableDepositLimit(address(0));
        assertEq(limit, 1000 ether - 100 ether - 2, "Sub-wei treasury residue must round up, not down");
    }
}
