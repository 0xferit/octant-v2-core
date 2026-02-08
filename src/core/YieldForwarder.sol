// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal interface for strategy share redemption
interface IRedeemable {
    /// @notice Redeem shares for underlying assets
    /// @param shares Amount of shares to redeem
    /// @param receiver Address to receive the redeemed assets
    /// @param owner Address whose shares are being redeemed
    /// @param maxLoss Maximum acceptable loss in basis points
    /// @return assets Amount of assets returned
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256 assets);
}

/**
 * @title YieldForwarder
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Immutable, single-purpose contract that redeems strategy shares and forwards
 *         the underlying assets to a hardcoded receiver
 * @dev Designed for trust-minimized yield flows where profit shares from a strategy
 *      are automatically redeemed for the underlying asset and sent to a receiver.
 *
 *      DESIGN:
 *      - Fully immutable: no admin, no upgrades, no sweep
 *      - Zero-admin: receiver is set once at construction
 *      - Permissionless: anyone can call redeemAndForward()
 *      - Single-purpose: assets can only flow to the hardcoded receiver
 *      - Strategy is passed as a call-time parameter to avoid circular dependencies
 */
contract YieldForwarder {
    // ============================================
    // ERRORS
    // ============================================

    /// @notice Thrown when the receiver address is zero
    error InvalidReceiver();

    /// @notice Thrown when there are no shares to redeem
    error NoSharesToRedeem();

    // ============================================
    // EVENTS
    // ============================================

    /// @notice Emitted when shares are redeemed and assets forwarded to the receiver
    /// @param strategy Address of the strategy whose shares were redeemed
    /// @param receiver Address that received the underlying assets
    /// @param shares Amount of shares redeemed
    /// @param assets Amount of underlying assets forwarded
    event YieldForwarded(address indexed strategy, address indexed receiver, uint256 shares, uint256 assets);

    // ============================================
    // STATE
    // ============================================

    /// @notice The address that receives all redeemed assets
    /// @dev Set once at construction, cannot be changed
    address public immutable receiver;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /// @notice Creates a new YieldForwarder with a fixed receiver
    /// @param _receiver Address that will receive all forwarded assets
    constructor(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiver();
        receiver = _receiver;
    }

    // ============================================
    // EXTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Redeems all strategy shares held by this contract and forwards assets to receiver
     * @dev Permissionless - anyone can call this to trigger redemption and forwarding.
     *      The strategy address is passed as a parameter to avoid circular deployment dependencies.
     * @param strategy Address of the strategy contract (must implement IRedeemable and IERC20)
     * @param maxLoss Maximum acceptable loss in basis points for the redemption
     * @return assets Amount of underlying assets forwarded to receiver
     */
    function redeemAndForward(address strategy, uint256 maxLoss) external returns (uint256 assets) {
        uint256 shares = IERC20(strategy).balanceOf(address(this));
        if (shares == 0) revert NoSharesToRedeem();

        assets = IRedeemable(strategy).redeem(shares, receiver, address(this), maxLoss);

        emit YieldForwarded(strategy, receiver, shares, assets);
    }
}
