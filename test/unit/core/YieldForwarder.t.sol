// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, Vm } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { YieldForwarder, IRedeemable, IReportable } from "src/core/YieldForwarder.sol";

/// @notice Mock strategy that acts as both an ERC20 (shares) and implements report + redeem
/// @dev On report(), mints profit shares to the configured donation address.
///      On redeem(), burns shares from owner and transfers assets 1:1 to receiver.
contract MockRedeemableStrategy is ERC20 {
    ERC20 public asset;
    address public donationAddress;
    uint256 public profitPerReport;

    constructor(ERC20 _asset) ERC20("Mock Strategy", "mSTRAT") {
        asset = _asset;
    }

    function setDonationAddress(address _addr) external {
        donationAddress = _addr;
    }

    function setProfitPerReport(uint256 _amount) external {
        profitPerReport = _amount;
    }

    /// @notice Simulates strategy report: mints profit shares to donation address
    function report() external returns (uint256 profit, uint256 loss) {
        if (profitPerReport > 0) {
            _mint(donationAddress, profitPerReport);
        }
        return (profitPerReport, 0);
    }

    /// @notice Simulates strategy redemption: burns shares from owner, transfers assets to receiver
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) external returns (uint256 assets) {
        maxLoss; // silence unused param
        _burn(owner, shares);
        assets = shares; // 1:1 for testing
        asset.transfer(receiver, assets);
    }
}

/// @notice Simple mock asset token
contract MockAsset is ERC20 {
    constructor() ERC20("Mock Asset", "mASSET") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract YieldForwarderTest is Test {
    YieldForwarder public forwarder;
    MockAsset public asset;
    MockRedeemableStrategy public strategy;

    address public receiver = address(0xBEEF);
    address public keeperEOA = address(0xCAFE);

    function setUp() public {
        asset = new MockAsset();
        strategy = new MockRedeemableStrategy(asset);
        forwarder = new YieldForwarder(receiver, keeperEOA);

        // Configure mock: profit shares go to the forwarder
        strategy.setDonationAddress(address(forwarder));

        vm.label(receiver, "Receiver");
        vm.label(keeperEOA, "KeeperEOA");
        vm.label(address(forwarder), "YieldForwarder");
        vm.label(address(strategy), "MockStrategy");
        vm.label(address(asset), "MockAsset");
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

    function test_constructor_revertsOnZeroReceiver() public {
        vm.expectRevert(YieldForwarder.InvalidReceiver.selector);
        new YieldForwarder(address(0), keeperEOA);
    }

    function test_constructor_revertsOnZeroKeeper() public {
        vm.expectRevert(YieldForwarder.InvalidKeeper.selector);
        new YieldForwarder(receiver, address(0));
    }

    // ═══════════════════════════════════════════════════════════
    // reportAndForward TESTS
    // ═══════════════════════════════════════════════════════════

    function test_reportAndForward_success() public {
        uint256 profitAmount = 100e18;
        strategy.setProfitPerReport(profitAmount);
        // Fund strategy with assets so it can pay out on redeem
        asset.mint(address(strategy), profitAmount);

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 0);

        // Assets should arrive at receiver
        assertEq(assets, profitAmount);
        assertEq(asset.balanceOf(receiver), profitAmount);
        // Forwarder should have no shares left
        assertEq(strategy.balanceOf(address(forwarder)), 0);
    }

    function test_reportAndForward_revertsWhenNotKeeper() public {
        address nonKeeper = address(0x1111);
        vm.prank(nonKeeper);
        vm.expectRevert(YieldForwarder.OnlyKeeper.selector);
        forwarder.reportAndForward(address(strategy), 0);
    }

    function test_reportAndForward_zeroProfit_returnsZero() public {
        // No profit configured (default 0)
        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 0);

        assertEq(assets, 0);
        assertEq(asset.balanceOf(receiver), 0);
    }

    function test_reportAndForward_emitsEvent() public {
        uint256 profitAmount = 50e18;
        strategy.setProfitPerReport(profitAmount);
        asset.mint(address(strategy), profitAmount);

        vm.expectEmit(true, true, false, true);
        emit YieldForwarder.YieldForwarded(address(strategy), receiver, profitAmount, profitAmount);

        vm.prank(keeperEOA);
        forwarder.reportAndForward(address(strategy), 0);
    }

    function test_reportAndForward_noEventOnZeroProfit() public {
        // With zero profit, no YieldForwarded event should be emitted
        vm.recordLogs();
        vm.prank(keeperEOA);
        forwarder.reportAndForward(address(strategy), 0);

        // Check no YieldForwarded event was emitted
        bytes32 yieldForwardedSelector = keccak256("YieldForwarded(address,address,uint256,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics[0] != yieldForwardedSelector,
                "YieldForwarded should not be emitted on zero profit"
            );
        }
    }

    function test_reportAndForward_multipleReports() public {
        uint256 profit1 = 30e18;
        uint256 profit2 = 70e18;

        // First report
        strategy.setProfitPerReport(profit1);
        asset.mint(address(strategy), profit1);
        vm.prank(keeperEOA);
        forwarder.reportAndForward(address(strategy), 0);
        assertEq(asset.balanceOf(receiver), profit1);

        // Second report
        strategy.setProfitPerReport(profit2);
        asset.mint(address(strategy), profit2);
        vm.prank(keeperEOA);
        forwarder.reportAndForward(address(strategy), 0);
        assertEq(asset.balanceOf(receiver), profit1 + profit2);
    }

    function test_reportAndForward_multipleStrategies() public {
        // Create a second strategy with a separate asset
        MockAsset asset2 = new MockAsset();
        MockRedeemableStrategy strategy2 = new MockRedeemableStrategy(asset2);
        strategy2.setDonationAddress(address(forwarder));

        uint256 profit1 = 40e18;
        uint256 profit2 = 60e18;

        // Fund both strategies
        strategy.setProfitPerReport(profit1);
        asset.mint(address(strategy), profit1);
        strategy2.setProfitPerReport(profit2);
        asset2.mint(address(strategy2), profit2);

        // Report from strategy 1
        vm.prank(keeperEOA);
        forwarder.reportAndForward(address(strategy), 0);
        assertEq(asset.balanceOf(receiver), profit1);

        // Report from strategy 2
        vm.prank(keeperEOA);
        forwarder.reportAndForward(address(strategy2), 0);
        assertEq(asset2.balanceOf(receiver), profit2);
    }

    function test_reportAndForward_passesMaxLoss() public {
        uint256 profitAmount = 10e18;
        strategy.setProfitPerReport(profitAmount);
        asset.mint(address(strategy), profitAmount);

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 100); // 100 basis points
        assertEq(assets, profitAmount);
    }
}
