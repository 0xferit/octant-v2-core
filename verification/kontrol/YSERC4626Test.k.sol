// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";

import { ERC4626BaseTest } from "test/kontrol/ERC4626BaseTest.k.sol";
import { YSSetup } from "test/kontrol/YSSetup.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title YSERC4626Test
 * @notice ERC4626 property tests instantiated for YieldSkimmingTokenizedStrategy
 * @dev Extends ERC4626BaseTest and YSSetup. Overrides virtual accessors to bind
 *      to the YS setup. Includes YS-specific conversion tests for solvent/insolvent paths.
 */
contract YSERC4626Test is ERC4626BaseTest, YSSetup {
    using Math for uint256;
    using WadRayMath for uint256;

    function setUp() public override(YSSetup) {
        YSSetup.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                    VIRTUAL ACCESSORS
    //////////////////////////////////////////////////////////////*/

    function getStrategy() internal view override returns (ITokenizedStrategy) {
        return iYSStrategy;
    }

    function getStrategyAddr() internal view override returns (address) {
        return address(ysStrategy);
    }

    function getKeeper() internal view override returns (address) {
        return _keeper;
    }

    function getDragonRouter() internal view override returns (address) {
        return _dragonRouter;
    }

    function getAssetAddr() internal view override returns (address) {
        return _asset;
    }

    /*//////////////////////////////////////////////////////////////
                    TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Shutdown blocks deposits and mints
    function testShutdownBlocksYS(address user) public {
        _assumeNonReentrant();

        vm.assume(user != address(0));
        vm.assume(user != address(ysStrategy));

        // Set shutdown = true
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 1);

        _assertShutdownBlocks(user);
    }

    /// @notice User balance is bounded by totalSupply
    /// @dev Storage-accessor sanity check: with fully symbolic storage, balance and
    ///      totalSupply are independent -- the assumption is necessary. The invariant
    ///      is proven inductively through state transitions in testDepositValueDebtYS.
    function testBalanceBoundedYS(address user) public {
        _assumeNonReentrant();

        vm.assume(user != address(0));

        uint256 totalSupply = _loadUInt256(address(ysStrategy), TS_TOTAL_SUPPLY_SLOT);
        uint256 balance = _loadMappingUInt256(address(ysStrategy), TS_BALANCES_SLOT, uint256(uint160(user)), 0);
        vm.assume(balance <= totalSupply);

        _assertBalanceBounded(user);
    }

    /// @notice When solvent, conversion uses rate: shares = assets * rate / RAY
    function testConversionSolventYS(uint256 amount) public {
        _assumeNonReentrant();

        vm.assume(amount > 0);
        vm.assume(amount < ETH_UPPER_BOUND);

        uint256 totalAssets = _loadUInt256(address(ysStrategy), TS_TOTAL_ASSETS_SLOT);
        uint256 totalSupply = _loadUInt256(address(ysStrategy), TS_TOTAL_SUPPLY_SLOT);
        vm.assume(totalAssets > 0);
        vm.assume(totalSupply > 0);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        // Ensure solvent
        _assumeNoOverflow(totalAssets, mockRate);
        uint256 currentValue = totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        uint256 userDebt = _loadUInt256(address(ysStrategy), YS_TOTAL_DEBT_OWED_TO_USER_SLOT);
        uint256 dragonDebt = _loadUInt256(address(ysStrategy), YS_DRAGON_ROUTER_DEBT_SLOT);
        _assumeNoOverflow(userDebt, dragonDebt);
        vm.assume(currentValue >= userDebt + dragonDebt);

        // Avoid overflow
        _assumeNoOverflow(amount, mockRate);

        uint256 expectedShares = amount.mulDiv(mockRate, WadRayMath.RAY);
        uint256 actualShares = iYSStrategy.convertToShares(amount);
        assertEq(actualShares, expectedShares);
    }

    /// @notice When insolvent, conversion falls back to proportional (base TokenizedStrategy logic)
    function testConversionFallbackInsolventYS(uint256 amount) public {
        _assumeNonReentrant();

        vm.assume(amount > 0);
        vm.assume(amount < ETH_UPPER_BOUND);

        uint256 totalAssets = _loadUInt256(address(ysStrategy), TS_TOTAL_ASSETS_SLOT);
        uint256 totalSupply = _loadUInt256(address(ysStrategy), TS_TOTAL_SUPPLY_SLOT);
        vm.assume(totalAssets > 0);
        vm.assume(totalSupply > 0);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        // Ensure insolvent
        _assumeNoOverflow(totalAssets, mockRate);
        uint256 currentValue = totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        uint256 userDebt = _loadUInt256(address(ysStrategy), YS_TOTAL_DEBT_OWED_TO_USER_SLOT);
        uint256 dragonDebt = _loadUInt256(address(ysStrategy), YS_DRAGON_ROUTER_DEBT_SLOT);
        _assumeNoOverflow(userDebt, dragonDebt);
        vm.assume(userDebt + dragonDebt > 0);
        vm.assume(currentValue < userDebt + dragonDebt);

        // Avoid overflow in proportional calc
        _assumeNoOverflow(amount, totalSupply);

        // Proportional: shares = amount * totalSupply / totalAssets (base logic)
        uint256 expectedShares = amount.mulDiv(totalSupply, totalAssets);
        uint256 actualShares = iYSStrategy.convertToShares(amount);
        assertEq(actualShares, expectedShares);
    }
}
