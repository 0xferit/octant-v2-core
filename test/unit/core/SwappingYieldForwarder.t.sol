// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import { SwappingYieldForwarder } from "src/core/SwappingYieldForwarder.sol";
import { YieldForwarder } from "src/core/YieldForwarder.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

import { MockFactory } from "test/mocks/MockFactory.sol";
import { MockStrategy } from "test/mocks/core/tokenized-strategies/MockStrategy.sol";
import { MockYieldSource } from "test/mocks/core/tokenized-strategies/MockYieldSource.sol";
import { MockSwapper } from "test/mocks/MockSwapper.sol";
import { IMockStrategy } from "test/mocks/core/IMockStrategy.sol";

contract SwappingYieldForwarderTest is Test {
    SwappingYieldForwarder public forwarder;
    ERC20Mock public asset;
    ERC20Mock public targetAsset;
    IMockStrategy public strategy;
    MockYieldSource public yieldSource;
    MockFactory public mockFactory;
    MockSwapper public swapper;
    YieldDonatingTokenizedStrategy public implementation;

    address public receiver = address(0xBEEF);
    address public keeperEOA = address(0xCAFE);
    address public management = address(0xA1);
    address public emergencyAdmin = address(0xA2);
    address public user = address(0xA3);
    address public protocolFeeRecipient = address(0xA4);

    uint256 public constant DEPOSIT_AMOUNT = 100e18;

    function setUp() public {
        mockFactory = new MockFactory(0, protocolFeeRecipient);
        implementation = new YieldDonatingTokenizedStrategy();

        asset = new ERC20Mock();
        targetAsset = new ERC20Mock();
        yieldSource = new MockYieldSource(address(asset));

        // Deploy swapper (1:1 rate)
        swapper = new MockSwapper(address(targetAsset), 1e18);

        // Deploy SwappingYieldForwarder
        forwarder = new SwappingYieldForwarder(receiver, keeperEOA, address(targetAsset), address(swapper));

        // Deploy strategy with forwarder as both keeper and donation address
        strategy = IMockStrategy(
            address(
                new MockStrategy(
                    address(asset),
                    address(yieldSource),
                    management,
                    address(forwarder),
                    emergencyAdmin,
                    address(forwarder),
                    address(implementation)
                )
            )
        );

        vm.startPrank(management);
        strategy.setKeeper(address(forwarder));
        strategy.setEmergencyAdmin(emergencyAdmin);
        strategy.setPendingManagement(management);
        strategy.acceptManagement();
        vm.stopPrank();

        vm.label(receiver, "Receiver");
        vm.label(keeperEOA, "KeeperEOA");
        vm.label(address(forwarder), "SwappingYieldForwarder");
        vm.label(address(strategy), "Strategy");
        vm.label(address(asset), "Asset");
        vm.label(address(targetAsset), "TargetAsset");
        vm.label(address(yieldSource), "YieldSource");
        vm.label(address(swapper), "MockSwapper");
    }

    function _depositIntoStrategy(address _user, uint256 _amount) internal {
        asset.mint(_user, _amount);
        vm.startPrank(_user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, _user);
        vm.stopPrank();
    }

    function _simulateProfit(uint256 _profit) internal {
        asset.mint(address(yieldSource), _profit);
    }

    // ═══════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════

    function test_constructor_setsReceiver() public view {
        assertEq(forwarder.receiver(), receiver);
    }

    function test_constructor_setsKeeper() public view {
        assertEq(forwarder.keeper(), keeperEOA);
    }

    function test_constructor_setsTargetAsset() public view {
        assertEq(forwarder.targetAsset(), address(targetAsset));
    }

    function test_constructor_setsSwapper() public view {
        assertEq(address(forwarder.swapper()), address(swapper));
    }

    function test_constructor_revertsOnZeroReceiver() public {
        vm.expectRevert(YieldForwarder.InvalidReceiver.selector);
        new SwappingYieldForwarder(address(0), keeperEOA, address(targetAsset), address(swapper));
    }

    function test_constructor_revertsOnZeroKeeper() public {
        vm.expectRevert(YieldForwarder.InvalidKeeper.selector);
        new SwappingYieldForwarder(receiver, address(0), address(targetAsset), address(swapper));
    }

    function test_constructor_revertsOnZeroTargetAsset() public {
        vm.expectRevert(SwappingYieldForwarder.InvalidTargetAsset.selector);
        new SwappingYieldForwarder(receiver, keeperEOA, address(0), address(swapper));
    }

    function test_constructor_revertsOnZeroSwapper() public {
        vm.expectRevert(SwappingYieldForwarder.InvalidSwapper.selector);
        new SwappingYieldForwarder(receiver, keeperEOA, address(targetAsset), address(0));
    }

    // ═══════════════════════════════════════════════════════════
    // reportAndForward — NO-SWAP FALLBACK PATH
    // ═══════════════════════════════════════════════════════════

    function test_reportAndForward_fullFlow() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        uint256 profit = 10e18;
        _simulateProfit(profit);

        uint256 receiverBalanceBefore = asset.balanceOf(receiver);
        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 10_000);

        assertGt(assets, 0, "Should forward nonzero assets");
        assertEq(asset.balanceOf(receiver), receiverBalanceBefore + assets, "Receiver should get underlying asset");
        assertEq(strategy.balanceOf(address(forwarder)), 0, "Forwarder should have 0 shares");
        // Receiver gets underlying asset, NOT target asset
        assertEq(targetAsset.balanceOf(receiver), 0, "Receiver should NOT get target asset on no-swap path");
    }

    function test_reportAndForward_revertsWhenNotKeeper() public {
        vm.prank(address(0x1111));
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        forwarder.reportAndForward(address(strategy), 0);
    }

    function test_reportAndForward_zeroProfit_returnsZero() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 10_000);

        assertEq(assets, 0, "Should return 0 when no profit");
    }

    function test_reportAndForward_emitsEvent() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        _simulateProfit(20e18);

        vm.expectEmit(true, true, false, false);
        emit YieldForwarder.YieldForwarded(address(strategy), receiver, 0, 0);

        vm.prank(keeperEOA);
        forwarder.reportAndForward(address(strategy), 10_000);
    }

    // ═══════════════════════════════════════════════════════════
    // reportSwapAndForward — SWAP PATH
    // ═══════════════════════════════════════════════════════════

    function test_reportSwapAndForward_fullFlow() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        uint256 profit = 10e18;
        _simulateProfit(profit);

        vm.prank(keeperEOA);
        uint256 assetsOut = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);

        assertGt(assetsOut, 0, "Should swap and forward nonzero target assets");
        assertEq(targetAsset.balanceOf(receiver), assetsOut, "Receiver should get target asset");
        assertEq(strategy.balanceOf(address(forwarder)), 0, "Forwarder should have 0 shares");
        // Underlying asset should NOT be at receiver (it was swapped)
        assertEq(asset.balanceOf(receiver), 0, "Receiver should NOT get underlying on swap path");
    }

    function test_reportSwapAndForward_revertsWhenNotKeeper() public {
        vm.prank(address(0x1111));
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        forwarder.reportSwapAndForward(address(strategy), 0, 0);
    }

    function test_reportSwapAndForward_zeroProfit_returnsZero() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        vm.prank(keeperEOA);
        uint256 assetsOut = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);

        assertEq(assetsOut, 0, "Should return 0 when no profit");
        assertEq(targetAsset.balanceOf(receiver), 0, "Receiver should get nothing");
    }

    function test_reportSwapAndForward_emitsEvent() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        _simulateProfit(20e18);

        vm.expectEmit(true, true, false, false);
        emit SwappingYieldForwarder.YieldSwappedAndForwarded(address(strategy), receiver, 0, 0, 0);

        vm.prank(keeperEOA);
        forwarder.reportSwapAndForward(address(strategy), 10_000, 0);
    }

    function test_reportSwapAndForward_multipleReports() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        // First profit cycle
        _simulateProfit(5e18);
        vm.prank(keeperEOA);
        uint256 assets1 = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);
        assertGt(assets1, 0, "First report should yield target assets");

        // Second profit cycle
        _simulateProfit(15e18);
        vm.prank(keeperEOA);
        uint256 assets2 = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);
        assertGt(assets2, 0, "Second report should yield target assets");

        assertEq(targetAsset.balanceOf(receiver), assets1 + assets2, "Receiver should accumulate all payouts");
    }

    function test_reportSwapAndForward_respectsMinAmountOut() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        _simulateProfit(10e18);

        // minAmountOut too high should revert (swapper enforces it)
        vm.prank(keeperEOA);
        vm.expectRevert();
        forwarder.reportSwapAndForward(address(strategy), 10_000, type(uint256).max);
    }

    function test_reportSwapAndForward_lossScenario_noSharesMinted() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        // Simulate loss
        vm.prank(address(strategy));
        yieldSource.simulateLoss(5e18);

        vm.prank(keeperEOA);
        uint256 assetsOut = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);

        assertEq(assetsOut, 0, "Loss report should return 0");
        assertEq(targetAsset.balanceOf(receiver), 0, "Receiver gets nothing on loss");
    }

    /// @notice Covers the `if (assetsIn == 0) return 0` branch in reportSwapAndForward.
    ///         shares > 0 but redeem returns 0 assets (e.g., extreme rounding in strategy).
    function test_reportSwapAndForward_sharesExistButRedeemReturnsZero() public {
        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        _simulateProfit(10e18);

        // Mock strategy.report() to do nothing special (shares already get minted)
        // Mock strategy.redeem() to return 0 assets (extreme edge case)
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(bytes4(keccak256("redeem(uint256,address,address,uint256)"))),
            abi.encode(uint256(0))
        );

        vm.prank(keeperEOA);
        uint256 assetsOut = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);

        assertEq(assetsOut, 0, "Should return 0 when redeem returns 0 assets");
        assertEq(targetAsset.balanceOf(receiver), 0, "Receiver gets nothing");

        vm.clearMockedCalls();
    }

    // ═══════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════

    function test_reportSwapAndForward_fuzz_profitAmount(uint256 profit) public {
        profit = bound(profit, 1e15, 1e27);

        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        _simulateProfit(profit);

        vm.prank(keeperEOA);
        uint256 assetsOut = forwarder.reportSwapAndForward(address(strategy), 10_000, 0);

        assertGt(assetsOut, 0, "Should always forward positive target assets for positive profit");
        assertEq(strategy.balanceOf(address(forwarder)), 0, "Forwarder should redeem all shares");
        assertEq(targetAsset.balanceOf(receiver), assetsOut, "Receiver balance should match returned assets");
    }

    function test_reportAndForward_fuzz_profitAmount(uint256 profit) public {
        profit = bound(profit, 1e15, 1e27);

        _depositIntoStrategy(user, DEPOSIT_AMOUNT);
        vm.prank(address(forwarder));
        strategy.report();

        _simulateProfit(profit);

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 10_000);

        assertGt(assets, 0, "Should always forward positive assets for positive profit");
        assertEq(strategy.balanceOf(address(forwarder)), 0, "Forwarder should redeem all shares");
        assertEq(asset.balanceOf(receiver), assets, "Receiver balance should match returned assets");
    }

    // ═══════════════════════════════════════════════════════════
    // ROLE VERIFICATION
    // ═══════════════════════════════════════════════════════════

    function test_strategyDonationAddressIsForwarder() public view {
        assertEq(strategy.dragonRouter(), address(forwarder), "Strategy donation address should be forwarder");
    }

    function test_strategyKeeperIsForwarder() public view {
        assertEq(strategy.keeper(), address(forwarder), "Strategy keeper should be forwarder");
    }
}
