// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

import { WadRayMath } from "src/utils/libs/Maths/WadRay.sol";

import { YSSetup } from "test/kontrol/YSSetup.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

struct YSProofState {
    uint256 totalAssets;
    uint256 totalSupply;
    uint256 dragonBalance;
    uint256 userDebt;
    uint256 dragonDebt;
}

/**
 * @title YSStrategyTest
 * @notice Kontrol formal verification proofs for YieldSkimmingTokenizedStrategy
 * @dev Proves key invariants of the yield-skimming report mechanism:
 *      - Profit: dragon balance and debt increase by profitValue
 *      - Loss with burning: dragon balance and debt decrease
 *      - Solvency gates: deposit/dragon-redeem blocked during insolvency
 *      - Value debt tracking: deposit increases userDebt, redeem decreases it
 *      - Transfer debt rebalancing: dragon transfers rebalance user/dragon debt
 *      - Access control and tend no-op
 */
contract YSStrategyTest is YSSetup {
    using Math for uint256;
    using WadRayMath for uint256;

    YSProofState private preState;
    YSProofState private postState;

    function _snapshot() internal view returns (YSProofState memory state) {
        state.totalAssets = _loadUInt256(address(ysStrategy), TS_TOTAL_ASSETS_SLOT);
        state.totalSupply = _loadUInt256(address(ysStrategy), TS_TOTAL_SUPPLY_SLOT);
        state.dragonBalance = _loadMappingUInt256(
            address(ysStrategy),
            TS_BALANCES_SLOT,
            uint256(uint160(_dragonRouter)),
            0
        );
        state.userDebt = _loadUInt256(address(ysStrategy), YS_TOTAL_DEBT_OWED_TO_USER_SLOT);
        state.dragonDebt = _loadUInt256(address(ysStrategy), YS_DRAGON_ROUTER_DEBT_SLOT);
    }

    function assumeNonReentrant() internal {
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_ENTERED_OFFSET, TS_ENTERED_WIDTH, 1);
    }

    function disableHealthCheck() internal {
        _storeData(address(ysStrategy), HC_SLOT, HC_DO_HEALTH_CHECK_OFFSET, HC_DO_HEALTH_CHECK_WIDTH, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH PROFIT
    //////////////////////////////////////////////////////////////*/

    /// @notice When report detects profit (currentValue > userDebt + dragonDebt),
    ///         shares are minted to dragon, dragon debt increases, user debt unchanged
    function testReportProfitYS() public {
        assumeNonReentrant();
        disableHealthCheck();

        preState = _snapshot();

        // Valid pre-state
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        // Mock harvest returns totalAssets (no change in asset balance, profit comes from rate)
        _storeUInt256(address(ysStrategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);

        // Give strategy enough asset balance
        deal(_asset, address(ysStrategy), preState.totalAssets);

        // Load mock exchange rate
        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        // currentValue = totalAssets * rate / RAY
        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);

        // Profit scenario: currentValue > userDebt + dragonDebt
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        uint256 totalDebt = preState.userDebt + preState.dragonDebt;
        vm.assume(currentValue > totalDebt);

        uint256 profitValue = currentValue - totalDebt;

        // Avoid overflow in dragonBalance + profitValue (shares minted = profitValue)
        _assumeNoOverflow(preState.dragonBalance, profitValue);
        _assumeNoOverflow(preState.totalSupply, profitValue);
        _assumeNoOverflow(preState.dragonDebt, profitValue);

        vm.startPrank(_keeper);
        iYSStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // Dragon received shares equal to profitValue
        assertEq(postState.dragonBalance, preState.dragonBalance + profitValue);
        // Dragon debt increased by profitValue
        assertEq(postState.dragonDebt, preState.dragonDebt + profitValue);
        // User debt unchanged
        assertEq(postState.userDebt, preState.userDebt);
        // totalSupply increased by profitValue
        assertEq(postState.totalSupply, preState.totalSupply + profitValue);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH LOSS (BURNING ENABLED, SUFFICIENT DRAGON)
    //////////////////////////////////////////////////////////////*/

    /// @notice When report detects loss and dragon has sufficient shares,
    ///         dragon balance and debt decrease
    function testReportLossWithBurningYS() public {
        assumeNonReentrant();
        disableHealthCheck();

        // Enable burning
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 1);

        preState = _snapshot();

        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        _storeUInt256(address(ysStrategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);
        deal(_asset, address(ysStrategy), preState.totalAssets);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);

        // Loss scenario: currentValue < userDebt + dragonDebt
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        uint256 totalDebt = preState.userDebt + preState.dragonDebt;
        vm.assume(currentValue < totalDebt);
        vm.assume(currentValue > 0);

        uint256 lossValue = totalDebt - currentValue;

        // Dragon can cover loss: dragonBalance >= lossValue
        vm.assume(preState.dragonBalance >= lossValue);
        vm.assume(preState.dragonDebt >= lossValue);

        vm.startPrank(_keeper);
        iYSStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // Dragon shares burned by lossValue (dragonBurn = min(lossValue, dragonBalance) = lossValue)
        assertEq(postState.dragonBalance, preState.dragonBalance - lossValue);
        // Dragon debt decreased by lossValue
        assertEq(postState.dragonDebt, preState.dragonDebt - lossValue);
        // User debt unchanged
        assertEq(postState.userDebt, preState.userDebt);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH LOSS (INSUFFICIENT DRAGON)
    //////////////////////////////////////////////////////////////*/

    /// @notice When dragon can't cover the full loss, all dragon shares are burned
    function testReportLossInsufficientDragonYS() public {
        assumeNonReentrant();
        disableHealthCheck();

        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 1);

        preState = _snapshot();

        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        _storeUInt256(address(ysStrategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);
        deal(_asset, address(ysStrategy), preState.totalAssets);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);

        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        uint256 totalDebt = preState.userDebt + preState.dragonDebt;
        vm.assume(currentValue < totalDebt);

        uint256 lossValue = totalDebt - currentValue;

        // Dragon can't cover: dragonBalance < lossValue
        vm.assume(lossValue > preState.dragonBalance);
        vm.assume(preState.dragonDebt >= preState.dragonBalance);

        vm.startPrank(_keeper);
        iYSStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // All dragon shares burned (dragonBurn = min(lossValue, dragonBalance) = dragonBalance)
        assertEq(postState.dragonBalance, 0);
        // Dragon debt decreased by dragonBalance (the amount burned)
        assertEq(postState.dragonDebt, preState.dragonDebt - preState.dragonBalance);
        // totalSupply decreased by dragonBalance
        assertEq(postState.totalSupply, preState.totalSupply - preState.dragonBalance);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH NO CHANGE
    //////////////////////////////////////////////////////////////*/

    /// @notice When currentValue == totalDebt, no shares minted or burned
    function testReportNoChangeYS() public {
        assumeNonReentrant();
        disableHealthCheck();

        preState = _snapshot();

        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        _storeUInt256(address(ysStrategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);
        deal(_asset, address(ysStrategy), preState.totalAssets);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);

        // No change: currentValue == userDebt + dragonDebt
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue == preState.userDebt + preState.dragonDebt);

        vm.startPrank(_keeper);
        iYSStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        assertEq(postState.totalSupply, preState.totalSupply);
        assertEq(postState.dragonBalance, preState.dragonBalance);
        assertEq(postState.userDebt, preState.userDebt);
        assertEq(postState.dragonDebt, preState.dragonDebt);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH LOSS (BURNING DISABLED)
    //////////////////////////////////////////////////////////////*/

    /// @notice When burning is disabled, no shares are burned even on loss
    function testReportLossNoBurningYS() public {
        assumeNonReentrant();
        disableHealthCheck();

        // Disable burning
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 0);

        preState = _snapshot();

        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        _storeUInt256(address(ysStrategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);
        deal(_asset, address(ysStrategy), preState.totalAssets);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);

        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue < preState.userDebt + preState.dragonDebt);

        vm.startPrank(_keeper);
        iYSStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // No shares burned
        assertEq(postState.totalSupply, preState.totalSupply);
        assertEq(postState.dragonBalance, preState.dragonBalance);
    }

    /*//////////////////////////////////////////////////////////////
                    SOLVENCY TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit reverts when vault is insolvent
    function testDepositBlockedDuringInsolvency() public {
        assumeNonReentrant();

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);

        // Set up insolvency: totalDebt > currentValue with positive debts
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(preState.userDebt + preState.dragonDebt > 0);
        vm.assume(currentValue < preState.userDebt + preState.dragonDebt);

        // Not shutdown
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 0);

        address depositor = makeAddr("DEPOSITOR");
        uint256 depositAmount = 1 ether;
        deal(_asset, depositor, depositAmount);
        vm.prank(depositor);
        (bool ok, ) = _asset.call(
            abi.encodeWithSignature("approve(address,uint256)", address(ysStrategy), depositAmount)
        );
        require(ok);

        vm.prank(depositor);
        vm.expectRevert("Cannot operate when vault is insolvent");
        iYSStrategy.deposit(depositAmount, depositor);
    }

    /// @notice Dragon redeem reverts during insolvency
    function testDragonBlockedDuringInsolvency() public {
        assumeNonReentrant();

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance > 0);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);

        // Insolvency
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(preState.userDebt + preState.dragonDebt > 0);
        vm.assume(currentValue < preState.userDebt + preState.dragonDebt);

        // Set lastReport to now (no lockup)
        _storeData(address(ysStrategy), TS_KEEPER_SLOT, TS_LAST_REPORT_OFFSET, TS_LAST_REPORT_WIDTH, block.timestamp);

        vm.prank(_dragonRouter);
        vm.expectRevert("Dragon cannot operate during insolvency");
        iYSStrategy.redeem(1, _dragonRouter, _dragonRouter);
    }

    /// @notice Deposit to dragon router always reverts
    function testDepositBlockedForDragon() public {
        assumeNonReentrant();

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        // Ensure solvent (so the only revert reason is "Dragon cannot deposit")
        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue >= preState.userDebt + preState.dragonDebt);

        // Not shutdown
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 0);

        address depositor = makeAddr("DEPOSITOR");
        uint256 depositAmount = 1 ether;
        deal(_asset, depositor, depositAmount);
        vm.prank(depositor);
        (bool ok, ) = _asset.call(
            abi.encodeWithSignature("approve(address,uint256)", address(ysStrategy), depositAmount)
        );
        require(ok);

        vm.prank(depositor);
        vm.expectRevert("Dragon cannot deposit");
        iYSStrategy.deposit(depositAmount, _dragonRouter);
    }

    /*//////////////////////////////////////////////////////////////
                    TEND (NO STATE CHANGE)
    //////////////////////////////////////////////////////////////*/

    /// @notice Tend should not change any state
    function testTendYS() public {
        assumeNonReentrant();

        preState = _snapshot();

        vm.startPrank(_keeper);
        iYSStrategy.tend();
        vm.stopPrank();

        postState = _snapshot();

        assertEq(postState.totalAssets, preState.totalAssets);
        assertEq(postState.totalSupply, preState.totalSupply);
        assertEq(postState.userDebt, preState.userDebt);
        assertEq(postState.dragonDebt, preState.dragonDebt);
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Non-keeper/non-management address cannot call report
    function testReportOnlyKeeperYS() public {
        assumeNonReentrant();
        disableHealthCheck();

        _storeUInt256(address(ysStrategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, freshUInt256Bounded());

        address nonKeeper = makeAddr("NON_KEEPER");

        vm.startPrank(nonKeeper);
        vm.expectRevert("!keeper");
        iYSStrategy.report();
        vm.stopPrank();
    }

    /// @notice Management can also call report
    function testReportByManagementYS() public {
        assumeNonReentrant();
        disableHealthCheck();

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        _storeUInt256(address(ysStrategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);
        deal(_asset, address(ysStrategy), preState.totalAssets);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        // Set up no-change scenario so report succeeds without overflow
        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue == preState.userDebt + preState.dragonDebt);

        vm.startPrank(_management);
        iYSStrategy.report();
        vm.stopPrank();
        // Should succeed without revert
    }

    /*//////////////////////////////////////////////////////////////
                    VALUE DEBT TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @notice After deposit, userDebt increases by shares (= assets * rate / RAY)
    function testDepositValueDebtYS(uint256 assets, address receiver) public {
        assumeNonReentrant();

        vm.assume(assets > 0);
        vm.assume(assets < ETH_UPPER_BOUND);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(ysStrategy));
        vm.assume(receiver != _dragonRouter);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        // Ensure solvent
        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue >= preState.userDebt + preState.dragonDebt);

        // shares = assets * rate / RAY
        _assumeNoOverflow(assets, mockRate);
        uint256 expectedShares = assets.mulDiv(mockRate, WadRayMath.RAY);
        vm.assume(expectedShares > 0);
        _assumeNoOverflow(preState.totalSupply, expectedShares);
        _assumeNoOverflow(preState.totalAssets, assets);
        _assumeNoOverflow(preState.userDebt, expectedShares);

        // Inductive hypothesis: receiver's balance is bounded by totalSupply pre-deposit.
        // The unchecked balance increment in _mint means the prover needs this constraint
        // to verify the invariant is preserved through the deposit state transition.
        uint256 receiverBalance = _loadMappingUInt256(
            address(ysStrategy),
            TS_BALANCES_SLOT,
            uint256(uint160(receiver)),
            0
        );
        vm.assume(receiverBalance <= preState.totalSupply);

        // Not shutdown
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 0);

        // Depositor setup
        address depositor = makeAddr("DEPOSITOR");
        deal(_asset, depositor, assets);
        vm.prank(depositor);
        (bool ok, ) = _asset.call(abi.encodeWithSignature("approve(address,uint256)", address(ysStrategy), assets));
        require(ok);

        deal(_asset, address(ysStrategy), preState.totalAssets);

        vm.prank(depositor);
        iYSStrategy.deposit(assets, receiver);

        postState = _snapshot();

        // User debt increased by shares
        assertEq(postState.userDebt, preState.userDebt + expectedShares);

        // Balance bounded by totalSupply after deposit (inductive step)
        _establish(Mode.Assert, iYSStrategy.balanceOf(receiver) <= iYSStrategy.totalSupply());
    }

    /// @notice After redeem, userDebt decreases by shares
    function testRedeemValueDebtYS(uint256 shares, address receiver, address owner) public {
        assumeNonReentrant();

        vm.assume(shares > 0);
        vm.assume(shares < ETH_UPPER_BOUND);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(ysStrategy));
        vm.assume(owner != address(0));
        vm.assume(owner != address(ysStrategy));
        vm.assume(owner != _dragonRouter);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(shares <= preState.totalSupply);

        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);

        // Ensure solvent (not insolvent -- needed for conversion path)
        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue >= preState.userDebt + preState.dragonDebt);

        // assets = shares * RAY / rate (floor)
        uint256 expectedAssets = shares.mulDiv(WadRayMath.RAY, mockRate);
        vm.assume(expectedAssets > 0);
        vm.assume(expectedAssets <= preState.totalAssets);

        // User debt must be >= shares for clean subtraction
        vm.assume(preState.userDebt >= shares);

        // Owner must have sufficient shares
        _storeMappingUInt256(address(ysStrategy), TS_BALANCES_SLOT, uint256(uint160(owner)), 0, shares);

        // Give strategy enough asset balance
        deal(_asset, address(ysStrategy), preState.totalAssets);

        // Set lastReport to now (no lockup)
        _storeData(address(ysStrategy), TS_KEEPER_SLOT, TS_LAST_REPORT_OFFSET, TS_LAST_REPORT_WIDTH, block.timestamp);

        vm.prank(owner);
        iYSStrategy.redeem(shares, receiver, owner);

        postState = _snapshot();

        // User debt decreased by shares
        assertEq(postState.userDebt, preState.userDebt - shares);
    }

    /*//////////////////////////////////////////////////////////////
                    TRANSFER DEBT REBALANCING
    //////////////////////////////////////////////////////////////*/

    /// @notice Dragon transfers to user: dragonDebt decreases, userDebt increases
    function testTransferDragonToUser(address to, uint256 amount) public {
        assumeNonReentrant();

        vm.assume(to != address(0));
        vm.assume(to != address(ysStrategy));
        vm.assume(to != _dragonRouter);
        vm.assume(amount > 0);
        vm.assume(amount < ETH_UPPER_BOUND);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance >= amount);
        vm.assume(preState.dragonDebt >= amount);

        // Ensure solvent
        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);
        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue >= preState.userDebt + preState.dragonDebt);

        _assumeNoOverflow(preState.userDebt, amount);

        vm.prank(_dragonRouter);
        (bool ok, ) = address(ysStrategy).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok, "transfer failed");

        postState = _snapshot();

        // Dragon debt decreased
        assertEq(postState.dragonDebt, preState.dragonDebt - amount);
        // User debt increased
        assertEq(postState.userDebt, preState.userDebt + amount);
    }

    /// @notice User transfers to dragon: userDebt decreases, dragonDebt increases
    function testTransferUserToDragon(address from, uint256 amount) public {
        assumeNonReentrant();

        vm.assume(from != address(0));
        vm.assume(from != address(ysStrategy));
        vm.assume(from != _dragonRouter);
        vm.assume(amount > 0);
        vm.assume(amount < ETH_UPPER_BOUND);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.userDebt >= amount);

        // Ensure solvent
        uint256 mockRate = _loadUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT);
        vm.assume(mockRate > 0);
        _assumeNoOverflow(preState.totalAssets, mockRate);
        uint256 currentValue = preState.totalAssets.mulDiv(mockRate, WadRayMath.RAY);
        _assumeNoOverflow(preState.userDebt, preState.dragonDebt);
        vm.assume(currentValue >= preState.userDebt + preState.dragonDebt);

        _assumeNoOverflow(preState.dragonDebt, amount);

        // Give `from` enough shares
        _storeMappingUInt256(address(ysStrategy), TS_BALANCES_SLOT, uint256(uint160(from)), 0, amount);

        vm.prank(from);
        (bool ok, ) = address(ysStrategy).call(
            abi.encodeWithSignature("transfer(address,uint256)", _dragonRouter, amount)
        );
        require(ok, "transfer failed");

        postState = _snapshot();

        // User debt decreased
        assertEq(postState.userDebt, preState.userDebt - amount);
        // Dragon debt increased
        assertEq(postState.dragonDebt, preState.dragonDebt + amount);
    }
}
