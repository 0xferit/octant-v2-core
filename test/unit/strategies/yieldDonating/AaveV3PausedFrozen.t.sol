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
}

/// @notice Configurable data provider so tests can flip paused/active/frozen flags.
contract ConfigurableDataProvider {
    address public aToken;

    bool public paused;
    bool public isActive = true;
    bool public isFrozen;

    uint256 public supplyCap; // whole-token cap, default unbounded enough that headroom > 0
    uint256 public totalSupply;

    constructor(address _aToken, uint256 _supplyCapWholeTokens, uint256 _totalSupply) {
        aToken = _aToken;
        supplyCap = _supplyCapWholeTokens;
        totalSupply = _totalSupply;
    }

    function setPaused(bool v) external {
        paused = v;
    }

    function setActive(bool v) external {
        isActive = v;
    }

    function setFrozen(bool v) external {
        isFrozen = v;
    }

    function getReserveTokensAddresses(
        address
    ) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress) {
        return (aToken, address(0), address(0));
    }

    function getReserveCaps(address) external view returns (uint256, uint256) {
        return (0, supplyCap);
    }

    function getATokenTotalSupply(address) external view returns (uint256) {
        return totalSupply;
    }

    function getReserveConfigurationData(
        address
    ) external view returns (uint256, uint256, uint256, uint256, uint256, bool, bool, bool, bool, bool) {
        return (0, 0, 0, 0, 0, false, false, false, isActive, isFrozen);
    }

    function getPaused(address) external view returns (bool) {
        return paused;
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

/// @notice Issue 47 -- when Aave governance/risk admin pauses or freezes a reserve,
///         `pool.supply` / `pool.withdraw` revert. The cap views must short-circuit to
///         zero in those states so ERC-4626 `maxDeposit`/`maxRedeem` consumers don't
///         route users straight into failing transactions.
///         Withdraw is gated on `paused` and `!isActive` (NOT `isFrozen`) -- a frozen
///         reserve still allows exits in Aave's validation logic.
contract AaveV3PausedFrozenTest is Test {
    AaveV3Strategy internal strategy;
    ERC20Mock internal asset;
    ERC20Mock internal aToken;
    ConfigurableDataProvider internal dp;

    address internal management = address(0x1);
    address internal keeper = address(0x2);
    address internal emergencyAdmin = address(0x3);
    address internal donationAddress = address(0x4);

    function setUp() public {
        asset = new ERC20Mock();
        aToken = new ERC20Mock();
        MockPool pool = new MockPool();
        // supplyCap = 1000 whole tokens with 18 decimals; totalSupply = 0 -> headroom > 0
        dp = new ConfigurableDataProvider(address(aToken), 1000, 0);
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

        // Park aTokens on the strategy AND back them with underlying liquidity at the
        // aToken address — `availableWithdrawLimit` returns `min(aTokenBalance, poolLiquidity)`,
        // where poolLiquidity = `asset.balanceOf(aToken)`.
        aToken.mint(address(strategy), 500 ether);
        asset.mint(address(aToken), 500 ether);
    }

    /// @notice Baseline (active, not paused, not frozen): both views return positive.
    function test_baseline_bothLimitsPositive() public view {
        assertGt(strategy.availableDepositLimit(address(0)), 0, "deposit limit should be positive in baseline");
        assertGt(strategy.availableWithdrawLimit(address(0)), 0, "withdraw limit should be positive in baseline");
    }

    /// @notice Paused (zero idle on strategy) -> both limits return 0.
    function test_paused_zeroIdle_bothLimitsZero() public {
        dp.setPaused(true);
        assertEq(strategy.availableDepositLimit(address(0)), 0, "paused reserve must block deposits");
        assertEq(strategy.availableWithdrawLimit(address(0)), 0, "paused + no idle -> no withdrawable");
    }

    /// @notice Inactive (zero idle on strategy) -> both limits return 0.
    function test_inactive_zeroIdle_bothLimitsZero() public {
        dp.setActive(false);
        assertEq(strategy.availableDepositLimit(address(0)), 0, "inactive reserve must block deposits");
        assertEq(strategy.availableWithdrawLimit(address(0)), 0, "inactive + no idle -> no withdrawable");
    }

    /// @notice Codex P1 regression -- when the reserve is paused, any idle balance
    ///         already sitting on the strategy (direct transfers, post-shutdown
    ///         emergency withdraw, rebates, partially-freed funds) doesn't need an
    ///         Aave pool interaction to exit. `availableWithdrawLimit` must surface
    ///         that idle balance so ERC-4626 `maxWithdraw` / `maxRedeem` aren't zero.
    function test_paused_withIdle_returnsIdleBalance() public {
        // Seed idle balance on the strategy (direct transfer / emergency-withdraw scenario).
        uint256 idle = 42 ether;
        asset.mint(address(strategy), idle);

        dp.setPaused(true);
        assertEq(
            strategy.availableDepositLimit(address(0)),
            0,
            "paused reserve must block deposits regardless of idle"
        );
        assertEq(
            strategy.availableWithdrawLimit(address(0)),
            idle,
            "paused + idle -> idle is withdrawable (no Aave pool interaction needed)"
        );
    }

    /// @notice Same invariant for the inactive flag -- an inactive reserve still lets
    ///         users exit the idle leg via ERC-4626.
    function test_inactive_withIdle_returnsIdleBalance() public {
        uint256 idle = 17 ether;
        asset.mint(address(strategy), idle);

        dp.setActive(false);
        assertEq(
            strategy.availableDepositLimit(address(0)),
            0,
            "inactive reserve must block deposits regardless of idle"
        );
        assertEq(
            strategy.availableWithdrawLimit(address(0)),
            idle,
            "inactive + idle -> idle is withdrawable (no Aave pool interaction needed)"
        );
    }

    /// @notice Frozen blocks deposits but NOT withdraws (Aave semantics).
    function test_frozen_blocksDepositButNotWithdraw() public {
        dp.setFrozen(true);
        assertEq(strategy.availableDepositLimit(address(0)), 0, "frozen reserve must block deposits");
        assertGt(
            strategy.availableWithdrawLimit(address(0)),
            0,
            "frozen reserve must still allow withdraws (Aave validation logic)"
        );
    }
}
