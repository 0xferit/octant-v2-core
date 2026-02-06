// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

import { YDSetup } from "test/kontrol/YDSetup.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

struct YDProofState {
    uint256 totalAssets;
    uint256 totalSupply;
    uint256 dragonBalance;
}

/**
 * @title YDStrategyTest
 * @notice Kontrol formal verification proofs for YieldDonatingTokenizedStrategy
 * @dev Proves key invariants of the yield-donating report mechanism:
 *      - PPS (price-per-share) is non-decreasing for regular holders after report with profit
 *      - PPS is non-decreasing after report with loss when dragon has sufficient balance
 *      - totalAssets is always updated to newTotalAssets after report
 *      - Dragon shares are minted on profit and burned on loss (when burning enabled)
 *      - Access control: only keepers/management can call report
 *      - Tend does not change PPS or totalAssets
 *      - Deposit/withdraw/mint/redeem preserve PPS non-decreasing
 */
contract YDStrategyTest is YDSetup {
    YDProofState private preState;
    YDProofState private postState;

    function _snapshot() internal view returns (YDProofState memory state) {
        state.totalAssets = _loadUInt256(address(strategy), TS_TOTAL_ASSETS_SLOT);
        state.totalSupply = _loadUInt256(address(strategy), TS_TOTAL_SUPPLY_SLOT);
        state.dragonBalance = _loadMappingUInt256(
            address(strategy),
            TS_BALANCES_SLOT,
            uint256(uint160(_dragonRouter)),
            0
        );
    }

    function assumeNonReentrant() internal {
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_ENTERED_OFFSET, TS_ENTERED_WIDTH, 1);
    }

    function disableHealthCheck() internal {
        _storeData(address(strategy), HC_SLOT, HC_DO_HEALTH_CHECK_OFFSET, HC_DO_HEALTH_CHECK_WIDTH, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice PPS does not decrease: totalAssets_new * totalSupply_old >= totalAssets_old * totalSupply_new
    function ppsNonDecreasingInvariant(Mode mode) internal view {
        _establish(mode, postState.totalAssets * preState.totalSupply >= preState.totalAssets * postState.totalSupply);
    }

    /// @notice totalAssets updated to the expected value
    function totalAssetsUpdatedCorrectly(Mode mode, uint256 expectedTotalAssets) internal view {
        _establish(mode, postState.totalAssets == expectedTotalAssets);
    }

    /// @notice Dragon balance does not exceed totalSupply
    function dragonBalanceBoundedBySupply(Mode mode) internal view {
        _establish(mode, postState.dragonBalance <= postState.totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH PROFIT
    //////////////////////////////////////////////////////////////*/

    /// @notice When report harvests a profit, shares are minted to dragon router
    ///         and PPS is preserved (non-decreasing) for regular holders
    function testReportProfit() public {
        assumeNonReentrant();
        disableHealthCheck();

        preState = _snapshot();

        // Valid pre-state
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        // Profit scenario: newTotalAssets > oldTotalAssets
        uint256 newTotalAssets = freshUInt256Bounded();
        vm.assume(newTotalAssets > preState.totalAssets);
        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, newTotalAssets);

        // Avoid overflow in sharesToMint = profit * totalSupply / totalAssets
        uint256 profit = newTotalAssets - preState.totalAssets;
        _assumeNoOverflow(profit, preState.totalSupply);

        // Avoid overflow in totalSupply + sharesToMint
        uint256 sharesToMint = (profit * preState.totalSupply) / preState.totalAssets;
        _assumeNoOverflow(preState.totalSupply, sharesToMint);

        // Avoid overflow in dragonBalance + sharesToMint
        _assumeNoOverflow(preState.dragonBalance, sharesToMint);

        vm.startPrank(_keeper);
        iStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // Assertions
        ppsNonDecreasingInvariant(Mode.Assert);
        totalAssetsUpdatedCorrectly(Mode.Assert, newTotalAssets);
        dragonBalanceBoundedBySupply(Mode.Assert);

        // Dragon received shares
        _establish(Mode.Assert, postState.dragonBalance >= preState.dragonBalance);
        // totalSupply increased
        _establish(Mode.Assert, postState.totalSupply >= preState.totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH LOSS (BURNING ENABLED, SUFFICIENT DRAGON)
    //////////////////////////////////////////////////////////////*/

    /// @notice When report harvests a loss with burning enabled and the dragon
    ///         has enough shares, shares are burned and PPS is preserved
    function testReportLossWithBurning() public {
        assumeNonReentrant();
        disableHealthCheck();

        // Enable burning
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 1);

        preState = _snapshot();

        // Valid pre-state
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        // Loss scenario: newTotalAssets < oldTotalAssets
        uint256 newTotalAssets = freshUInt256Bounded();
        vm.assume(newTotalAssets < preState.totalAssets);
        vm.assume(newTotalAssets > 0);
        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, newTotalAssets);

        // Dragon has enough shares to cover the loss burn
        uint256 loss = preState.totalAssets - newTotalAssets;
        _assumeNoOverflow(loss, preState.totalSupply);
        uint256 sharesToBurn = Math.ceilDiv(loss * preState.totalSupply, preState.totalAssets);
        vm.assume(preState.dragonBalance >= sharesToBurn);

        vm.startPrank(_keeper);
        iStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // Assertions
        ppsNonDecreasingInvariant(Mode.Assert);
        totalAssetsUpdatedCorrectly(Mode.Assert, newTotalAssets);

        // Dragon shares were burned
        _establish(Mode.Assert, postState.dragonBalance <= preState.dragonBalance);
        // totalSupply decreased
        _establish(Mode.Assert, postState.totalSupply <= preState.totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH LOSS (INSUFFICIENT DRAGON)
    //////////////////////////////////////////////////////////////*/

    /// @notice When dragon can't cover the full loss, all its shares are burned
    ///         and the remaining loss reduces PPS
    function testReportLossInsufficientDragon() public {
        assumeNonReentrant();
        disableHealthCheck();

        // Enable burning
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 1);

        preState = _snapshot();

        // Valid pre-state
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        // Loss scenario where dragon can't cover
        uint256 newTotalAssets = freshUInt256Bounded();
        vm.assume(newTotalAssets < preState.totalAssets);
        vm.assume(newTotalAssets > 0);
        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, newTotalAssets);

        uint256 loss = preState.totalAssets - newTotalAssets;
        _assumeNoOverflow(loss, preState.totalSupply);
        uint256 sharesToBurn = Math.ceilDiv(loss * preState.totalSupply, preState.totalAssets);
        vm.assume(sharesToBurn > preState.dragonBalance);

        vm.startPrank(_keeper);
        iStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // totalAssets still updated correctly
        totalAssetsUpdatedCorrectly(Mode.Assert, newTotalAssets);
        // All dragon shares burned
        assertEq(postState.dragonBalance, 0);
        // totalSupply decreased by exactly the dragon balance
        assertEq(postState.totalSupply, preState.totalSupply - preState.dragonBalance);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH NO CHANGE
    //////////////////////////////////////////////////////////////*/

    /// @notice When harvest returns same totalAssets, no shares minted or burned
    function testReportNoChange() public {
        assumeNonReentrant();
        disableHealthCheck();

        preState = _snapshot();

        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        // Set mock to return current totalAssets (no profit, no loss)
        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);

        vm.startPrank(_keeper);
        iStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // No change
        assertEq(postState.totalAssets, preState.totalAssets);
        assertEq(postState.totalSupply, preState.totalSupply);
        assertEq(postState.dragonBalance, preState.dragonBalance);
    }

    /*//////////////////////////////////////////////////////////////
                    REPORT WITH LOSS (BURNING DISABLED)
    //////////////////////////////////////////////////////////////*/

    /// @notice When burning is disabled, loss reduces totalAssets but totalSupply
    ///         and dragon balance stay unchanged
    function testReportLossNoBurning() public {
        assumeNonReentrant();
        disableHealthCheck();

        // Disable burning
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 0);

        preState = _snapshot();

        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(preState.dragonBalance <= preState.totalSupply);

        // Loss scenario
        uint256 newTotalAssets = freshUInt256Bounded();
        vm.assume(newTotalAssets < preState.totalAssets);
        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, newTotalAssets);

        vm.startPrank(_keeper);
        iStrategy.report();
        vm.stopPrank();

        postState = _snapshot();

        // totalAssets decreased
        totalAssetsUpdatedCorrectly(Mode.Assert, newTotalAssets);
        // No shares burned -- totalSupply and dragon balance unchanged
        assertEq(postState.totalSupply, preState.totalSupply);
        assertEq(postState.dragonBalance, preState.dragonBalance);
    }

    /*//////////////////////////////////////////////////////////////
                    TEND (NO STATE CHANGE)
    //////////////////////////////////////////////////////////////*/

    /// @notice Tend should not change totalAssets or totalSupply
    function testTend() public {
        assumeNonReentrant();

        preState = _snapshot();

        vm.startPrank(_keeper);
        iStrategy.tend();
        vm.stopPrank();

        postState = _snapshot();

        assertEq(postState.totalAssets, preState.totalAssets);
        assertEq(postState.totalSupply, preState.totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Non-keeper/non-management address cannot call report
    function testReportOnlyKeeper() public {
        assumeNonReentrant();
        disableHealthCheck();

        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, freshUInt256Bounded());

        address nonKeeper = makeAddr("NON_KEEPER");

        vm.startPrank(nonKeeper);
        vm.expectRevert("!keeper");
        iStrategy.report();
        vm.stopPrank();
    }

    /// @notice Management can also call report (management has keeper privileges)
    function testReportByManagement() public {
        assumeNonReentrant();
        disableHealthCheck();

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, preState.totalAssets);

        vm.startPrank(_management);
        iStrategy.report();
        vm.stopPrank();
        // Should succeed without revert
    }

    /// @notice Emergency admin can shutdown but not call report
    function testReportNotEmergencyAdmin() public {
        assumeNonReentrant();
        disableHealthCheck();

        _storeUInt256(address(strategy), MOCK_NEXT_TOTAL_ASSETS_SLOT, freshUInt256Bounded());

        vm.startPrank(_emergencyAdmin);
        vm.expectRevert("!keeper");
        iStrategy.report();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT / MINT
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit assets: totalAssets increases by assets, totalSupply increases by shares,
    ///         receiver balance increases, PPS non-decreasing
    function testDepositYD(uint256 assets, address receiver) public {
        assumeNonReentrant();

        // Bound inputs
        vm.assume(assets > 0);
        vm.assume(assets < ETH_UPPER_BOUND);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(strategy));
        vm.assume(receiver != _dragonRouter);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        // PPS = totalAssets / totalSupply -- shares = assets * totalSupply / totalAssets
        _assumeNoOverflow(assets, preState.totalSupply);
        uint256 expectedShares = (assets * preState.totalSupply) / preState.totalAssets;
        vm.assume(expectedShares > 0);
        _assumeNoOverflow(preState.totalSupply, expectedShares);
        _assumeNoOverflow(preState.totalAssets, assets);

        // Not shutdown
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 0);

        // Ensure depositor has asset balance and has approved strategy
        address depositor = makeAddr("DEPOSITOR");
        vm.prank(depositor);
        // Use deal to give depositor enough assets
        deal(_asset, depositor, assets);
        // Approve strategy to spend
        vm.prank(depositor);
        (bool ok, ) = _asset.call(abi.encodeWithSignature("approve(address,uint256)", address(strategy), assets));
        require(ok);

        // Also give strategy existing asset balance to match totalAssets
        deal(_asset, address(strategy), preState.totalAssets);

        uint256 preReceiverBalance = _loadMappingUInt256(
            address(strategy),
            TS_BALANCES_SLOT,
            uint256(uint160(receiver)),
            0
        );

        vm.prank(depositor);
        iStrategy.deposit(assets, receiver);

        postState = _snapshot();

        // totalAssets increased by assets
        assertEq(postState.totalAssets, preState.totalAssets + assets);
        // totalSupply increased
        _establish(Mode.Assert, postState.totalSupply > preState.totalSupply);
        // PPS non-decreasing
        ppsNonDecreasingInvariant(Mode.Assert);
        // Receiver balance increased
        uint256 postReceiverBalance = _loadMappingUInt256(
            address(strategy),
            TS_BALANCES_SLOT,
            uint256(uint160(receiver)),
            0
        );
        _establish(Mode.Assert, postReceiverBalance > preReceiverBalance);
    }

    /// @notice Mint shares: totalAssets increases, totalSupply increases by shares,
    ///         receiver balance increases, PPS non-decreasing
    function testMintYD(uint256 shares, address receiver) public {
        assumeNonReentrant();

        // Bound inputs
        vm.assume(shares > 0);
        vm.assume(shares < ETH_UPPER_BOUND);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(strategy));
        vm.assume(receiver != _dragonRouter);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);

        // assets = shares * totalAssets / totalSupply (rounded up)
        _assumeNoOverflow(shares, preState.totalAssets);
        uint256 expectedAssets = Math.ceilDiv(shares * preState.totalAssets, preState.totalSupply);
        vm.assume(expectedAssets > 0);
        _assumeNoOverflow(preState.totalSupply, shares);
        _assumeNoOverflow(preState.totalAssets, expectedAssets);

        // Not shutdown
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 0);

        // Ensure depositor has asset balance and has approved strategy
        address depositor = makeAddr("DEPOSITOR");
        deal(_asset, depositor, expectedAssets);
        vm.prank(depositor);
        (bool ok, ) = _asset.call(
            abi.encodeWithSignature("approve(address,uint256)", address(strategy), expectedAssets)
        );
        require(ok);

        // Give strategy existing asset balance to match totalAssets
        deal(_asset, address(strategy), preState.totalAssets);

        vm.prank(depositor);
        iStrategy.mint(shares, receiver);

        postState = _snapshot();

        // totalSupply increased by shares
        assertEq(postState.totalSupply, preState.totalSupply + shares);
        // totalAssets increased
        _establish(Mode.Assert, postState.totalAssets > preState.totalAssets);
        // PPS non-decreasing
        ppsNonDecreasingInvariant(Mode.Assert);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAW / REDEEM
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraw assets: totalAssets decreases by assets, owner balance decreases,
    ///         PPS non-decreasing
    function testWithdrawYD(uint256 assets, address receiver, address owner) public {
        assumeNonReentrant();

        // Bound inputs
        vm.assume(assets > 0);
        vm.assume(assets < ETH_UPPER_BOUND);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(strategy));
        vm.assume(owner != address(0));
        vm.assume(owner != address(strategy));
        vm.assume(owner != _dragonRouter);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(assets <= preState.totalAssets);

        // shares = assets * totalSupply / totalAssets (rounded up)
        _assumeNoOverflow(assets, preState.totalSupply);
        uint256 expectedShares = Math.ceilDiv(assets * preState.totalSupply, preState.totalAssets);
        vm.assume(expectedShares > 0);
        vm.assume(expectedShares <= preState.totalSupply);

        // Owner must have sufficient shares
        _storeMappingUInt256(address(strategy), TS_BALANCES_SLOT, uint256(uint160(owner)), 0, expectedShares);

        // Give strategy enough asset balance for withdrawal
        deal(_asset, address(strategy), preState.totalAssets);

        // Set lastReport to current timestamp so no lockup
        _storeData(address(strategy), TS_KEEPER_SLOT, TS_LAST_REPORT_OFFSET, TS_LAST_REPORT_WIDTH, block.timestamp);

        vm.prank(owner);
        iStrategy.withdraw(assets, receiver, owner);

        postState = _snapshot();

        // totalAssets decreased by assets
        assertEq(postState.totalAssets, preState.totalAssets - assets);
        // totalSupply decreased
        _establish(Mode.Assert, postState.totalSupply < preState.totalSupply);
        // PPS non-decreasing
        ppsNonDecreasingInvariant(Mode.Assert);
    }

    /// @notice Redeem shares: totalSupply decreases by shares, owner balance decreases,
    ///         PPS non-decreasing
    function testRedeemYD(uint256 shares, address receiver, address owner) public {
        assumeNonReentrant();

        // Bound inputs
        vm.assume(shares > 0);
        vm.assume(shares < ETH_UPPER_BOUND);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(strategy));
        vm.assume(owner != address(0));
        vm.assume(owner != address(strategy));
        vm.assume(owner != _dragonRouter);

        preState = _snapshot();
        vm.assume(preState.totalAssets > 0);
        vm.assume(preState.totalSupply > 0);
        vm.assume(shares <= preState.totalSupply);

        // assets = shares * totalAssets / totalSupply (rounded down)
        _assumeNoOverflow(shares, preState.totalAssets);
        uint256 expectedAssets = (shares * preState.totalAssets) / preState.totalSupply;
        vm.assume(expectedAssets > 0);
        vm.assume(expectedAssets <= preState.totalAssets);

        // Owner must have sufficient shares
        _storeMappingUInt256(address(strategy), TS_BALANCES_SLOT, uint256(uint160(owner)), 0, shares);

        // Give strategy enough asset balance for withdrawal
        deal(_asset, address(strategy), preState.totalAssets);

        // Set lastReport to current timestamp so no lockup
        _storeData(address(strategy), TS_KEEPER_SLOT, TS_LAST_REPORT_OFFSET, TS_LAST_REPORT_WIDTH, block.timestamp);

        vm.prank(owner);
        iStrategy.redeem(shares, receiver, owner);

        postState = _snapshot();

        // totalSupply decreased by shares
        assertEq(postState.totalSupply, preState.totalSupply - shares);
        // totalAssets decreased
        _establish(Mode.Assert, postState.totalAssets < preState.totalAssets);
        // PPS non-decreasing
        ppsNonDecreasingInvariant(Mode.Assert);
    }
}
