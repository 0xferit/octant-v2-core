// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { YieldForwarder, IRedeemable } from "src/core/YieldForwarder.sol";

/// @notice Mock strategy that acts as both an ERC20 (shares) and implements redeem
/// @dev Mints shares to simulate strategy share allocation, redeems by burning shares
///      and transferring a separate "asset" token to the receiver
contract MockRedeemableStrategy is ERC20 {
    ERC20 public asset;

    constructor(ERC20 _asset) ERC20("Mock Strategy", "mSTRAT") {
        asset = _asset;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Simulates strategy redemption: burns shares from owner, transfers assets to receiver
    /// @dev Returns assets 1:1 with shares for simplicity
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) external returns (uint256 assets) {
        // Silence unused param warning
        maxLoss;

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
    address public caller = address(0xCAFE);

    function setUp() public {
        asset = new MockAsset();
        strategy = new MockRedeemableStrategy(asset);
        forwarder = new YieldForwarder(receiver);

        vm.label(receiver, "Receiver");
        vm.label(caller, "Caller");
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

    function test_constructor_revertsOnZeroReceiver() public {
        vm.expectRevert(YieldForwarder.InvalidReceiver.selector);
        new YieldForwarder(address(0));
    }

    // ═══════════════════════════════════════════════════════════
    // redeemAndForward TESTS
    // ═══════════════════════════════════════════════════════════

    function test_redeemAndForward_success() public {
        uint256 shareAmount = 100e18;

        // Give forwarder some strategy shares
        strategy.mint(address(forwarder), shareAmount);
        // Fund strategy with assets so it can pay out
        asset.mint(address(strategy), shareAmount);

        // Anyone can call
        vm.prank(caller);
        uint256 assets = forwarder.redeemAndForward(address(strategy), 0);

        // Assets should arrive at receiver
        assertEq(assets, shareAmount);
        assertEq(asset.balanceOf(receiver), shareAmount);
        // Forwarder should have no shares left
        assertEq(strategy.balanceOf(address(forwarder)), 0);
    }

    function test_redeemAndForward_revertsOnZeroShares() public {
        // No shares allocated to forwarder
        vm.expectRevert(YieldForwarder.NoSharesToRedeem.selector);
        forwarder.redeemAndForward(address(strategy), 0);
    }

    function test_redeemAndForward_emitsEvent() public {
        uint256 shareAmount = 50e18;

        strategy.mint(address(forwarder), shareAmount);
        asset.mint(address(strategy), shareAmount);

        vm.expectEmit(true, true, false, true);
        emit YieldForwarder.YieldForwarded(address(strategy), receiver, shareAmount, shareAmount);

        forwarder.redeemAndForward(address(strategy), 0);
    }

    function test_redeemAndForward_permissionless_multipleCaller() public {
        // First caller
        uint256 amount1 = 30e18;
        strategy.mint(address(forwarder), amount1);
        asset.mint(address(strategy), amount1);

        vm.prank(address(0x1111));
        forwarder.redeemAndForward(address(strategy), 0);
        assertEq(asset.balanceOf(receiver), amount1);

        // Second caller
        uint256 amount2 = 70e18;
        strategy.mint(address(forwarder), amount2);
        asset.mint(address(strategy), amount2);

        vm.prank(address(0x2222));
        forwarder.redeemAndForward(address(strategy), 0);
        assertEq(asset.balanceOf(receiver), amount1 + amount2);
    }

    function test_redeemAndForward_multipleStrategies() public {
        // Create a second strategy with a separate asset
        MockAsset asset2 = new MockAsset();
        MockRedeemableStrategy strategy2 = new MockRedeemableStrategy(asset2);

        uint256 amount1 = 40e18;
        uint256 amount2 = 60e18;

        // Fund both strategies
        strategy.mint(address(forwarder), amount1);
        asset.mint(address(strategy), amount1);

        strategy2.mint(address(forwarder), amount2);
        asset2.mint(address(strategy2), amount2);

        // Redeem from strategy 1
        forwarder.redeemAndForward(address(strategy), 0);
        assertEq(asset.balanceOf(receiver), amount1);

        // Redeem from strategy 2
        forwarder.redeemAndForward(address(strategy2), 0);
        assertEq(asset2.balanceOf(receiver), amount2);

        // Forwarder should have no shares in either
        assertEq(strategy.balanceOf(address(forwarder)), 0);
        assertEq(strategy2.balanceOf(address(forwarder)), 0);
    }

    function test_redeemAndForward_passesMaxLoss() public {
        // This test verifies the maxLoss parameter is passed through
        // by checking that the call succeeds with a non-zero maxLoss
        uint256 shareAmount = 10e18;
        strategy.mint(address(forwarder), shareAmount);
        asset.mint(address(strategy), shareAmount);

        uint256 assets = forwarder.redeemAndForward(address(strategy), 100); // 100 basis points
        assertEq(assets, shareAmount);
    }
}
