// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockForwarderStrategy
 * @notice Minimal mock for Kontrol formal verification of YieldForwarder contracts
 * @dev Implements IReportable, IRedeemable, IERC20.balanceOf, and IERC4626Asset.asset()
 *      with controllable return values. Does not interact with any external contracts.
 *
 *      Storage layout (all plain slots, no ERC-7201):
 *        slot 0: mockShareBalance   -- returned by balanceOf()
 *        slot 1: mockRedeemReturn   -- returned by redeem()
 *        slot 2: mockAsset          -- returned by asset()
 *        slot 3: lastRedeemReceiver -- captures receiver arg from redeem()
 *        slot 4: lastRedeemShares   -- captures shares arg from redeem()
 */
contract MockForwarderStrategy {
    uint256 public mockShareBalance;
    uint256 public mockRedeemReturn;
    address public mockAsset;
    address public lastRedeemReceiver;
    uint256 public lastRedeemShares;

    /// @notice No-op report; strategy report logic is verified by existing YD/YS Kontrol proofs
    /// @dev Self-assignment prevents pure/view optimization to match real IReportable mutability
    function report() external returns (uint256, uint256) {
        mockShareBalance = mockShareBalance;
        return (0, 0);
    }

    /// @notice Returns the controllable mock share balance for any address
    function balanceOf(address) external view returns (uint256) {
        return mockShareBalance;
    }

    /// @notice Mock redeem that captures arguments and zeroes share balance
    function redeem(uint256 shares, address receiver, address, uint256) external returns (uint256) {
        lastRedeemShares = shares;
        lastRedeemReceiver = receiver;
        mockShareBalance = 0;
        return mockRedeemReturn;
    }

    /// @notice Returns the mock underlying asset address
    function asset() external view returns (address) {
        return mockAsset;
    }
}
