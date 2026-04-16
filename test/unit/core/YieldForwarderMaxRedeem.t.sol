// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { YieldForwarder } from "src/core/YieldForwarder.sol";

/// @notice Programmable share-token + strategy mock. Exposes setters for `maxRedeem`
///         and for the forwarder's share balance so the test can place the forwarder
///         in the pre-fix revert state (`balance > maxRedeem`).
contract MockStrategy is ERC20Mock {
    ERC20Mock public immutable underlying;
    uint256 internal _maxRedeemValue;
    bool public reported;
    uint256 public lastRedeemedShares;
    uint256 public constant REDEEM_RATE = 1; // 1 share => 1 unit of underlying (test-local)

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
        // Mirrors the 1:1 REDEEM_RATE used by `redeem`. Non-zero shares => non-zero
        // assets, so the rounding-skip guard never fires in these tests
        // (this suite targets the maxRedeem cap path, not the rounding path).
        return shares * REDEEM_RATE;
    }

    function report() external returns (uint256, uint256) {
        reported = true;
        return (0, 0);
    }

    function redeem(uint256 shares, address receiver, address owner, uint256) external returns (uint256 assets) {
        // Pre-fix guard would trip here if shares > _maxRedeemValue.
        require(shares <= _maxRedeemValue, "MAX_REDEEM");
        _burn(owner, shares);
        assets = shares * REDEEM_RATE;
        underlying.mint(receiver, assets);
        lastRedeemedShares = shares;
    }
}

/// @notice Pre-fix, `reportAndForward` passed `IERC20(strategy).balanceOf(forwarder)`
///         directly into `redeem`. If external vault liquidity shrank,
///         `strategy.maxRedeem(forwarder) < balance` and the inner revert rolled back
///         the entire call, including `report()`. Fix caps shares at `maxRedeem` so
///         the report always commits and residual shares stay at the forwarder for a
///         later call.
contract YieldForwarderMaxRedeemTest is Test {
    YieldForwarder internal forwarder;
    ERC20Mock internal underlying;
    MockStrategy internal strategy;

    address internal receiver = address(0xBEEF);
    address internal keeperEOA = address(0xCAFE);

    function setUp() public {
        underlying = new ERC20Mock();
        forwarder = new YieldForwarder(receiver, keeperEOA);
        strategy = new MockStrategy(address(underlying));
    }

    // --- YieldForwarder.reportAndForward ---

    /// @notice Happy path: maxRedeem >= balance, full balance is redeemed.
    function test_reportAndForward_maxRedeemAboveBalance_redeemsAll() public {
        strategy.mint(address(forwarder), 100 ether);
        strategy.setMaxRedeem(1_000 ether);

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 0);

        assertEq(assets, 100 ether, "all shares redeemed");
        assertEq(strategy.balanceOf(address(forwarder)), 0, "no residual shares");
        assertEq(underlying.balanceOf(receiver), 100 ether, "receiver got assets");
        assertTrue(strategy.reported(), "report() executed");
    }

    /// @notice Fix path: maxRedeem < balance. Pre-fix this would revert inside redeem and
    ///         roll back the report() above. Post-fix: redeem is capped at maxRedeem,
    ///         report() commits, residual shares remain for a later call.
    function test_reportAndForward_maxRedeemBelowBalance_capsAtMaxRedeem() public {
        strategy.mint(address(forwarder), 100 ether);
        strategy.setMaxRedeem(30 ether);

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 0);

        assertEq(assets, 30 ether, "redeem is capped at maxRedeem");
        assertEq(strategy.balanceOf(address(forwarder)), 70 ether, "residual shares stay at forwarder");
        assertEq(underlying.balanceOf(receiver), 30 ether, "receiver gets the cap amount");
        assertTrue(strategy.reported(), "report() still commits");
    }

    /// @notice When maxRedeem is zero (locked vault), skip the redeem entirely but still commit report().
    function test_reportAndForward_maxRedeemZero_skipsRedeem() public {
        strategy.mint(address(forwarder), 100 ether);
        strategy.setMaxRedeem(0);

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 0);

        assertEq(assets, 0, "no redeem when maxRedeem is zero");
        assertEq(strategy.balanceOf(address(forwarder)), 100 ether, "all shares retained");
        assertEq(underlying.balanceOf(receiver), 0, "receiver gets nothing");
        assertTrue(strategy.reported(), "report() commits regardless");
    }

    /// @notice Forwarder holds zero shares: early return, no maxRedeem probe needed.
    function test_reportAndForward_zeroBalance_earlyReturn() public {
        strategy.setMaxRedeem(100 ether);

        vm.prank(keeperEOA);
        uint256 assets = forwarder.reportAndForward(address(strategy), 0);

        assertEq(assets, 0, "early return on zero balance");
        assertTrue(strategy.reported(), "report() still runs");
    }
}
