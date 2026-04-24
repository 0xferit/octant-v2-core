// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { SwappingYieldForwarder } from "src/core/SwappingYieldForwarder.sol";
import { MockSwapper } from "test/mocks/MockSwapper.sol";

/// @notice Strategy mock whose convertToAssets uses floor((shares * totalAssets) / totalSupply)
///         and whose redeem reverts with ZERO_ASSETS if the preview rounds to zero. Mirrors
///         the real TokenizedStrategy.redeem guard so we can reproduce the pre-fix DoS
///         (1 wei share dust on a loss-impaired strategy bricks reportSwapAndForward).
contract LossImpairedStrategy is ERC20Mock {
    ERC20Mock public immutable underlying;
    uint256 public totalAssetsStored;
    bool public reported;
    bool public redeemCalled;

    constructor(address _underlying) {
        underlying = ERC20Mock(_underlying);
    }

    function asset() external view returns (address) {
        return address(underlying);
    }

    function setTotalAssets(uint256 v) external {
        totalAssetsStored = v;
    }

    function maxRedeem(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        uint256 ts = totalSupply();
        if (ts == 0) return shares;
        return (shares * totalAssetsStored) / ts;
    }

    function report() external returns (uint256, uint256) {
        reported = true;
        return (0, 0);
    }

    function redeem(uint256 shares, address receiver, address owner, uint256) external returns (uint256 assets) {
        redeemCalled = true;
        uint256 ts = totalSupply();
        assets = ts == 0 ? shares : (shares * totalAssetsStored) / ts;
        require(assets > 0, "ZERO_ASSETS");
        _burn(owner, shares);
        totalAssetsStored -= assets;
        underlying.mint(receiver, assets);
    }
}

/// @notice Programmable strategy mock for the maxRedeem cap path. 1:1 rate
///         means non-zero shares always yield non-zero assets, so the zero-asset guard never
///         fires here and we isolate the cap behaviour.
contract MockStrategy is ERC20Mock {
    ERC20Mock public immutable underlying;
    uint256 internal _maxRedeemValue;
    bool public reported;
    uint256 public constant REDEEM_RATE = 1;

    constructor(address _underlying) {
        underlying = ERC20Mock(_underlying);
    }

    function asset() external view returns (address) {
        return address(underlying);
    }

    function setMaxRedeem(uint256 value) external {
        _maxRedeemValue = value;
    }

    function maxRedeem(address) external view returns (uint256) {
        return _maxRedeemValue;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares * REDEEM_RATE;
    }

    function report() external returns (uint256, uint256) {
        reported = true;
        return (0, 0);
    }

    function redeem(uint256 shares, address receiver, address owner, uint256) external returns (uint256 assets) {
        require(shares <= _maxRedeemValue, "MAX_REDEEM");
        _burn(owner, shares);
        assets = shares * REDEEM_RATE;
        underlying.mint(receiver, assets);
    }
}

/// @notice Mock vault that exposes management() so the SwappingYieldForwarder constructor
///         and onlyVaultManagement modifier are satisfied. Not exercised by these tests.
contract MockVault {
    address public management;

    constructor(address _management) {
        management = _management;
    }
}

/// @notice Mirror guards on SwappingYieldForwarder.reportSwapAndForward.
///         Both guards were added to YieldForwarder.reportAndForward in the sibling forwarder PR
///         and must be mirrored on the swapping variant so external vault liquidity shortfalls
///         (maxRedeem < balance) and loss-impaired dust (convertToAssets rounds to zero) do
///         not revert the outer call and roll back report() side effects.
contract SwappingYieldForwarderMirrorTest is Test {
    SwappingYieldForwarder internal swappingForwarder;
    ERC20Mock internal underlying;
    ERC20Mock internal targetAsset;
    MockVault internal vault;

    address internal receiver = address(0xBEEF);
    address internal keeperEOA = address(0xCAFE);

    function setUp() public {
        underlying = new ERC20Mock();
        targetAsset = new ERC20Mock();
        vault = new MockVault(address(this));

        MockSwapper swapper = new MockSwapper(address(targetAsset), 1e18);
        swappingForwarder = new SwappingYieldForwarder(
            receiver,
            keeperEOA,
            address(targetAsset),
            address(swapper),
            address(vault),
            0
        );
    }

    function _impair(
        LossImpairedStrategy s,
        address shareholder,
        uint256 shareholderShares,
        address forwarderAddr,
        uint256 dust
    ) internal {
        s.mint(shareholder, shareholderShares);
        s.mint(forwarderAddr, dust);
        s.setTotalAssets(shareholderShares - 1);
    }

    // --- Zero-asset skip on loss-impaired strategy ---

    /// @notice Dust share on a loss-impaired strategy must not revert reportSwapAndForward.
    ///         report() commits, no swap is attempted, dust stays at forwarder.
    function test_reportSwapAndForward_dustOnLossImpaired_skipsRedeem() public {
        LossImpairedStrategy s = new LossImpairedStrategy(address(underlying));
        _impair(s, address(0xA11CE), 1_000 ether, address(swappingForwarder), 1);

        assertEq(s.convertToAssets(1), 0, "precondition: dust rounds to zero");

        vm.prank(keeperEOA);
        uint256 assetsOut = swappingForwarder.reportSwapAndForward(address(s), 0, 0, block.timestamp + 1 hours);

        assertEq(assetsOut, 0, "no swap output");
        assertEq(s.balanceOf(address(swappingForwarder)), 1, "dust share retained");
        assertEq(targetAsset.balanceOf(receiver), 0, "receiver gets nothing");
        assertTrue(s.reported(), "report() commits on swapping variant");
        assertFalse(s.redeemCalled(), "redeem must be skipped, not called-and-failed");
    }

    // --- maxRedeem cap ---

    /// @notice maxRedeem < balance. Pre-fix this would revert inside redeem and roll back
    ///         report(). Post-fix: shares capped at maxRedeem, report() commits, residual
    ///         shares stay for a later call, swap runs on the capped amount.
    function test_reportSwapAndForward_maxRedeemBelowBalance_capsAtMaxRedeem() public {
        MockStrategy s = new MockStrategy(address(underlying));
        s.mint(address(swappingForwarder), 100 ether);
        s.setMaxRedeem(40 ether);

        vm.prank(keeperEOA);
        uint256 assetsOut = swappingForwarder.reportSwapAndForward(address(s), 0, 0, block.timestamp + 1 hours);

        assertEq(assetsOut, 40 ether, "output matches capped redeem");
        assertEq(s.balanceOf(address(swappingForwarder)), 60 ether, "residual shares retained");
        assertEq(targetAsset.balanceOf(receiver), 40 ether, "receiver gets swapped output");
        assertTrue(s.reported(), "report() commits on swapping variant");
    }

    /// @notice maxRedeem == 0: skip redeem AND skip swap, report() still commits.
    function test_reportSwapAndForward_maxRedeemZero_skipsRedeemAndSwap() public {
        MockStrategy s = new MockStrategy(address(underlying));
        s.mint(address(swappingForwarder), 100 ether);
        s.setMaxRedeem(0);

        vm.prank(keeperEOA);
        uint256 assetsOut = swappingForwarder.reportSwapAndForward(address(s), 0, 0, block.timestamp + 1 hours);

        assertEq(assetsOut, 0, "no swap when redeem is skipped");
        assertEq(s.balanceOf(address(swappingForwarder)), 100 ether, "all shares retained");
        assertEq(targetAsset.balanceOf(receiver), 0, "receiver gets nothing");
        assertTrue(s.reported(), "report() still commits");
    }
}
