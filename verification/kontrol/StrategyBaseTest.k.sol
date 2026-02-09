// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

import { ERC4626BaseTest } from "test/kontrol/ERC4626BaseTest.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title StrategyBaseTest
 * @notice Abstract polymorphic base for common TokenizedStrategy invariant proofs
 * @dev Provides 7 strategy-agnostic test functions that apply to any TokenizedStrategy
 *      implementation (YieldDonating or YieldSkimming). Concrete subclasses override
 *      virtual hooks to provide strategy-specific setup and extra assertions.
 *
 *      Inherited tests:
 *      1. testTend              -- tend preserves totalAssets/totalSupply
 *      2. testReportOnlyKeeper  -- non-keeper reverts with "!keeper"
 *      3. testReportByManagement-- management can call report
 *      4. testShutdownBlocks    -- shutdown sets maxDeposit/maxMint to 0
 *      5. testBalanceBounded    -- balanceOf(user) <= totalSupply
 *      6. testReportNoChange    -- report with same totalAssets preserves state
 *      7. testReportLossNoBurning -- burning disabled means no shares burned
 */
abstract contract StrategyBaseTest is ERC4626BaseTest {
    /*//////////////////////////////////////////////////////////////
                    VIRTUAL HOOKS (override in subclasses)
    //////////////////////////////////////////////////////////////*/

    /// @dev Set up strategy-specific state for report-no-change scenario.
    ///      YD: no-op (just sets MOCK_NEXT_TOTAL_ASSETS_SLOT).
    ///      YS: set exchange rate, asset balance, solvency constraint.
    function _setupReportNoChange(uint256 totalAssets) internal virtual;

    /// @dev Set up strategy-specific state for loss scenario with burning disabled.
    ///      YD: set newTotalAssets < totalAssets.
    ///      YS: set rate to produce value loss.
    function _setupLossScenario(uint256 totalAssets) internal virtual;

    /// @dev Assert strategy-specific invariants after report-no-change.
    ///      YD: no-op.
    ///      YS: assert userDebt and dragonDebt unchanged.
    function _assertReportNoChangeExtras() internal view virtual;

    /// @dev Assert strategy-specific invariants after tend.
    ///      YD: no-op.
    ///      YS: assert userDebt and dragonDebt unchanged.
    function _assertTendExtras() internal view virtual;

    /*//////////////////////////////////////////////////////////////
                    COMMON TEST FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tend should not change totalAssets or totalSupply
    function testTend() public virtual {
        _assumeNonReentrant();

        ITokenizedStrategy s = getStrategy();

        uint256 preTotalAssets = s.totalAssets();
        uint256 preTotalSupply = s.totalSupply();

        vm.startPrank(getKeeper());
        s.tend();
        vm.stopPrank();

        assertEq(s.totalAssets(), preTotalAssets);
        assertEq(s.totalSupply(), preTotalSupply);

        _assertTendExtras();
    }

    /// @notice Non-keeper/non-management address cannot call report
    function testReportOnlyKeeper() public {
        _assumeNonReentrant();

        address stratAddr = getStrategyAddr();
        _storeData(stratAddr, HC_SLOT, HC_DO_HEALTH_CHECK_OFFSET, HC_DO_HEALTH_CHECK_WIDTH, 0);
        _storeUInt256(stratAddr, MOCK_NEXT_TOTAL_ASSETS_SLOT, freshUInt256Bounded());

        address nonKeeper = makeAddr("NON_KEEPER");

        vm.startPrank(nonKeeper);
        vm.expectRevert("!keeper");
        getStrategy().report();
        vm.stopPrank();
    }

    /// @notice Management can also call report (management has keeper privileges)
    function testReportByManagement() public virtual {
        _assumeNonReentrant();

        address stratAddr = getStrategyAddr();
        _storeData(stratAddr, HC_SLOT, HC_DO_HEALTH_CHECK_OFFSET, HC_DO_HEALTH_CHECK_WIDTH, 0);

        ITokenizedStrategy s = getStrategy();
        uint256 totalAssets = s.totalAssets();
        uint256 totalSupply = s.totalSupply();
        vm.assume(totalAssets > 0);
        vm.assume(totalSupply > 0);

        _setupReportNoChange(totalAssets);

        vm.startPrank(getManagement());
        s.report();
        vm.stopPrank();
        // Should succeed without revert
    }

    /// @notice When shutdown, maxDeposit and maxMint return 0
    function testShutdownBlocks(address user) public {
        _assumeNonReentrant();

        vm.assume(user != address(0));
        vm.assume(user != getStrategyAddr());

        // Set shutdown = true
        _storeData(getStrategyAddr(), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 1);

        _assertShutdownBlocks(user);
    }

    /// @notice balanceOf(user) <= totalSupply()
    function testBalanceBounded(address user) public {
        _assumeNonReentrant();

        vm.assume(user != address(0));

        address stratAddr = getStrategyAddr();
        uint256 totalSupply = _loadUInt256(stratAddr, TS_TOTAL_SUPPLY_SLOT);
        uint256 balance = _loadMappingUInt256(stratAddr, TS_BALANCES_SLOT, uint256(uint160(user)), 0);
        vm.assume(balance <= totalSupply);

        _assertBalanceBounded(user);
    }

    /// @notice When harvest returns same totalAssets, no shares minted or burned
    function testReportNoChange() public virtual {
        _assumeNonReentrant();

        address stratAddr = getStrategyAddr();
        _storeData(stratAddr, HC_SLOT, HC_DO_HEALTH_CHECK_OFFSET, HC_DO_HEALTH_CHECK_WIDTH, 0);

        ITokenizedStrategy s = getStrategy();
        uint256 preTotalAssets = s.totalAssets();
        uint256 preTotalSupply = s.totalSupply();
        uint256 preDragonBalance = _loadMappingUInt256(
            stratAddr,
            TS_BALANCES_SLOT,
            uint256(uint160(getDragonRouter())),
            0
        );
        vm.assume(preTotalAssets > 0);
        vm.assume(preTotalSupply > 0);

        _setupReportNoChange(preTotalAssets);

        vm.startPrank(getKeeper());
        s.report();
        vm.stopPrank();

        assertEq(s.totalAssets(), preTotalAssets);
        assertEq(s.totalSupply(), preTotalSupply);
        uint256 postDragonBalance = _loadMappingUInt256(
            stratAddr,
            TS_BALANCES_SLOT,
            uint256(uint160(getDragonRouter())),
            0
        );
        assertEq(postDragonBalance, preDragonBalance);

        _assertReportNoChangeExtras();
    }

    /// @notice When burning is disabled, loss reduces totalAssets but totalSupply
    ///         and dragon balance stay unchanged
    function testReportLossNoBurning() public virtual {
        _assumeNonReentrant();

        address stratAddr = getStrategyAddr();
        _storeData(stratAddr, HC_SLOT, HC_DO_HEALTH_CHECK_OFFSET, HC_DO_HEALTH_CHECK_WIDTH, 0);

        // Disable burning
        _storeData(stratAddr, TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 0);

        ITokenizedStrategy s = getStrategy();
        uint256 preTotalSupply = s.totalSupply();
        uint256 preTotalAssets = s.totalAssets();
        uint256 preDragonBalance = _loadMappingUInt256(
            stratAddr,
            TS_BALANCES_SLOT,
            uint256(uint160(getDragonRouter())),
            0
        );
        vm.assume(preTotalAssets > 0);
        vm.assume(preTotalSupply > 0);
        vm.assume(preDragonBalance <= preTotalSupply);

        _setupLossScenario(preTotalAssets);

        vm.startPrank(getKeeper());
        s.report();
        vm.stopPrank();

        // No shares burned -- totalSupply and dragon balance unchanged
        assertEq(s.totalSupply(), preTotalSupply);
        uint256 postDragonBalance = _loadMappingUInt256(
            stratAddr,
            TS_BALANCES_SLOT,
            uint256(uint160(getDragonRouter())),
            0
        );
        assertEq(postDragonBalance, preDragonBalance);
    }
}
