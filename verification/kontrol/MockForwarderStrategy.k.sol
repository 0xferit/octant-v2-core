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
 *        slot 5: lastReportCaller   -- captures msg.sender from report()
 *        slot 6: expectedBalanceOfAccount -- only this account has shares
 *        slot 7: lastRedeemOwner    -- captures owner arg from redeem()
 *        slot 8: lastRedeemMaxLoss  -- captures maxLoss arg from redeem()
 *        slot 9: mockMaxRedeem      -- returned by maxRedeem()
 *        slot 10: mockConvertToAssets -- returned by convertToAssets()
 */
contract MockForwarderStrategy {
    uint256 public mockShareBalance;
    uint256 public mockRedeemReturn;
    address public mockAsset;
    address public lastRedeemReceiver;
    uint256 public lastRedeemShares;
    address public lastReportCaller;
    address public expectedBalanceOfAccount;
    address public lastRedeemOwner;
    uint256 public lastRedeemMaxLoss;
    uint256 public mockMaxRedeem;
    uint256 public mockConvertToAssets;

    /// @notice No-op report that still records the caller
    function report() external returns (uint256, uint256) {
        lastReportCaller = msg.sender;
        return (0, 0);
    }

    /// @notice Returns shares only for the configured forwarder account
    function balanceOf(address account) external view returns (uint256) {
        if (account != expectedBalanceOfAccount) {
            return 0;
        }

        return mockShareBalance;
    }

    /// @notice Mock ERC-4626 maxRedeem guard used by SwappingYieldForwarder
    function maxRedeem(address) external view returns (uint256) {
        return mockMaxRedeem;
    }

    /// @notice Mock ERC-4626 convertToAssets guard used by SwappingYieldForwarder
    function convertToAssets(uint256) external view returns (uint256) {
        return mockConvertToAssets;
    }

    /// @notice Mock redeem that captures arguments and zeroes share balance
    function redeem(uint256 shares, address receiver, address owner, uint256 maxLoss) external returns (uint256) {
        lastRedeemShares = shares;
        lastRedeemReceiver = receiver;
        lastRedeemOwner = owner;
        lastRedeemMaxLoss = maxLoss;
        mockShareBalance = 0;
        return mockRedeemReturn;
    }

    /// @notice Returns the mock underlying asset address
    function asset() external view returns (address) {
        return mockAsset;
    }
}
