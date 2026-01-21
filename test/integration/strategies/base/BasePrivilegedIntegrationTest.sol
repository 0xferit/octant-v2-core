// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { Privileged } from "src/core/Privileged.sol";

/// @notice Interface for privileged strategy functions
interface IPrivilegedStrategy {
    function setPrivileged(address _account, bool _status) external;
    function setPrivilegedBatch(address[] calldata _accounts, bool _status) external;
    function isPrivileged(address _account) external view returns (bool);
}

/// @title BasePrivilegedIntegrationTest
/// @notice Abstract contract providing shared test implementations for privileged strategy tests
/// @dev Provides test functions for privileged access control that work with both YieldDonating and YieldSkimming
abstract contract BasePrivilegedIntegrationTest is Test {
    // ========== EVENTS ==========

    event PrivilegedUpdated(address indexed account, bool status);

    // ========== ABSTRACT METHODS ==========

    /// @notice Returns the vault interface
    function _vault() internal view virtual returns (ITokenizedStrategy);

    /// @notice Returns the asset address
    function _asset() internal view virtual returns (address);

    /// @notice Returns the management address
    function _management() internal view virtual returns (address);

    /// @notice Returns the privileged strategy address (cast to Privileged)
    function _privilegedStrategy() internal view virtual returns (address);

    /// @notice Returns a privileged user address
    function _privilegedUser() internal view virtual returns (address);

    /// @notice Returns a non-privileged user address
    function _nonPrivilegedUser() internal view virtual returns (address);

    /// @notice Airdrops tokens to a user
    function _airdrop(address token, address to, uint256 amount) internal virtual;

    /// @notice Returns the minimum deposit amount
    function _minDeposit() internal view virtual returns (uint256);

    /// @notice Returns the maximum deposit amount
    function _maxDeposit() internal view virtual returns (uint256);

    // ========== SHARED PRIVILEGED TEST IMPLEMENTATIONS ==========

    /// @notice Test that setPrivileged can only be called by management
    function _testSetPrivilegedOnlyManagement() internal {
        address nonManagement = makeAddr("nonManagement");

        vm.startPrank(nonManagement);
        vm.expectRevert("!management");
        IPrivilegedStrategy(_privilegedStrategy()).setPrivileged(address(1), true);
        vm.stopPrank();
    }

    /// @notice Test that setPrivileged works when called by management
    function _testSetPrivilegedByManagement() internal {
        address newPrivilegedUser = makeAddr("newPrivilegedUser");

        assertFalse(
            IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(newPrivilegedUser),
            "Should not be privileged initially"
        );

        vm.startPrank(_management());
        vm.expectEmit(true, true, true, true);
        emit PrivilegedUpdated(newPrivilegedUser, true);
        IPrivilegedStrategy(_privilegedStrategy()).setPrivileged(newPrivilegedUser, true);
        vm.stopPrank();

        assertTrue(
            IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(newPrivilegedUser),
            "Should be privileged after setting"
        );

        // Test removing privilege
        vm.startPrank(_management());
        vm.expectEmit(true, true, true, true);
        emit PrivilegedUpdated(newPrivilegedUser, false);
        IPrivilegedStrategy(_privilegedStrategy()).setPrivileged(newPrivilegedUser, false);
        vm.stopPrank();

        assertFalse(
            IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(newPrivilegedUser),
            "Should not be privileged after removal"
        );
    }

    /// @notice Test that setPrivilegedBatch can only be called by management
    function _testSetPrivilegedBatchOnlyManagement() internal {
        address[] memory accounts = new address[](2);
        accounts[0] = makeAddr("account1");
        accounts[1] = makeAddr("account2");

        address nonManagement = makeAddr("nonManagement");

        vm.startPrank(nonManagement);
        vm.expectRevert("!management");
        IPrivilegedStrategy(_privilegedStrategy()).setPrivilegedBatch(accounts, true);
        vm.stopPrank();
    }

    /// @notice Test that setPrivilegedBatch works when called by management
    function _testSetPrivilegedBatchByManagement() internal {
        address[] memory accounts = new address[](3);
        accounts[0] = makeAddr("batchAccount1");
        accounts[1] = makeAddr("batchAccount2");
        accounts[2] = makeAddr("batchAccount3");

        // Verify none are privileged initially
        for (uint256 i = 0; i < accounts.length; i++) {
            assertFalse(
                IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(accounts[i]),
                "Should not be privileged initially"
            );
        }

        // Add all as privileged
        vm.startPrank(_management());
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.expectEmit(true, true, true, true);
            emit PrivilegedUpdated(accounts[i], true);
        }
        IPrivilegedStrategy(_privilegedStrategy()).setPrivilegedBatch(accounts, true);
        vm.stopPrank();

        // Verify all are now privileged
        for (uint256 i = 0; i < accounts.length; i++) {
            assertTrue(
                IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(accounts[i]),
                "Should be privileged after batch set"
            );
        }

        // Remove all privileges
        vm.startPrank(_management());
        IPrivilegedStrategy(_privilegedStrategy()).setPrivilegedBatch(accounts, false);
        vm.stopPrank();

        // Verify none are privileged
        for (uint256 i = 0; i < accounts.length; i++) {
            assertFalse(
                IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(accounts[i]),
                "Should not be privileged after removal"
            );
        }
    }

    /// @notice Test that deposit reverts when msg.sender is not privileged
    function _testDepositRevertsWhenSenderNotPrivileged() internal {
        uint256 depositAmount = _minDeposit();
        address nonPrivileged = _nonPrivilegedUser();
        address privileged = _privilegedUser();

        _airdrop(_asset(), nonPrivileged, depositAmount);

        vm.startPrank(nonPrivileged);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        vm.expectRevert("!privileged");
        _vault().deposit(depositAmount, privileged); // Receiver is privileged, but sender is not
        vm.stopPrank();
    }

    /// @notice Test that deposit reverts when receiver is not privileged
    function _testDepositRevertsWhenReceiverNotPrivileged() internal {
        uint256 depositAmount = _minDeposit();
        address privileged = _privilegedUser();
        address nonPrivileged = _nonPrivilegedUser();

        _airdrop(_asset(), privileged, depositAmount);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        vm.expectRevert("!privileged");
        _vault().deposit(depositAmount, nonPrivileged); // Sender is privileged, but receiver is not
        vm.stopPrank();
    }

    /// @notice Test that deposit works when both sender and receiver are privileged
    function _testDepositSucceedsWhenBothPrivileged() internal {
        uint256 depositAmount = _minDeposit();
        address privileged = _privilegedUser();

        _airdrop(_asset(), privileged, depositAmount);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        uint256 shares = _vault().deposit(depositAmount, privileged);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertEq(_vault().balanceOf(privileged), shares, "Should have correct share balance");
    }

    /// @notice Test that mint reverts when msg.sender is not privileged
    function _testMintRevertsWhenSenderNotPrivileged() internal {
        uint256 shareAmount = _minDeposit();
        address nonPrivileged = _nonPrivilegedUser();
        address privileged = _privilegedUser();

        // Need to have enough assets to cover the mint
        uint256 requiredAssets = IERC4626(address(_vault())).previewMint(shareAmount);
        _airdrop(_asset(), nonPrivileged, requiredAssets * 2);

        vm.startPrank(nonPrivileged);
        ERC20(_asset()).approve(address(_vault()), type(uint256).max);
        vm.expectRevert("!privileged");
        _vault().mint(shareAmount, privileged);
        vm.stopPrank();
    }

    /// @notice Test that mint reverts when receiver is not privileged
    function _testMintRevertsWhenReceiverNotPrivileged() internal {
        uint256 shareAmount = _minDeposit();
        address privileged = _privilegedUser();
        address nonPrivileged = _nonPrivilegedUser();

        uint256 requiredAssets = IERC4626(address(_vault())).previewMint(shareAmount);
        _airdrop(_asset(), privileged, requiredAssets * 2);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), type(uint256).max);
        vm.expectRevert("!privileged");
        _vault().mint(shareAmount, nonPrivileged);
        vm.stopPrank();
    }

    /// @notice Test that mint works when both sender and receiver are privileged
    function _testMintSucceedsWhenBothPrivileged() internal {
        uint256 shareAmount = _minDeposit();
        address privileged = _privilegedUser();

        uint256 requiredAssets = IERC4626(address(_vault())).previewMint(shareAmount);
        _airdrop(_asset(), privileged, requiredAssets * 2);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), type(uint256).max);
        uint256 assets = _vault().mint(shareAmount, privileged);
        vm.stopPrank();

        assertGt(assets, 0, "Should consume assets");
        assertEq(_vault().balanceOf(privileged), shareAmount, "Should have correct share balance");
    }

    /// @notice Test that maxDeposit returns 0 for non-privileged users
    function _testMaxDepositReturnsZeroForNonPrivileged() internal view {
        address nonPrivileged = _nonPrivilegedUser();

        uint256 maxDeposit = IERC4626(address(_vault())).maxDeposit(nonPrivileged);
        assertEq(maxDeposit, 0, "maxDeposit should return 0 for non-privileged");
    }

    /// @notice Test that maxDeposit returns non-zero for privileged users
    function _testMaxDepositReturnsNonZeroForPrivileged() internal view {
        address privileged = _privilegedUser();

        uint256 maxDeposit = IERC4626(address(_vault())).maxDeposit(privileged);
        assertGt(maxDeposit, 0, "maxDeposit should return non-zero for privileged");
    }

    /// @notice Test that maxMint returns 0 for non-privileged users
    function _testMaxMintReturnsZeroForNonPrivileged() internal view {
        address nonPrivileged = _nonPrivilegedUser();

        uint256 maxMint = IERC4626(address(_vault())).maxMint(nonPrivileged);
        assertEq(maxMint, 0, "maxMint should return 0 for non-privileged");
    }

    /// @notice Test that maxMint returns non-zero for privileged users
    function _testMaxMintReturnsNonZeroForPrivileged() internal view {
        address privileged = _privilegedUser();

        uint256 maxMint = IERC4626(address(_vault())).maxMint(privileged);
        assertGt(maxMint, 0, "maxMint should return non-zero for privileged");
    }

    /// @notice Test that non-privileged users can still withdraw (withdrawals are not restricted)
    function _testWithdrawWorksForNonPrivileged() internal {
        uint256 depositAmount = _minDeposit();
        address privileged = _privilegedUser();
        address nonPrivileged = _nonPrivilegedUser();

        // First, privileged user deposits
        _airdrop(_asset(), privileged, depositAmount);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        uint256 shares = _vault().deposit(depositAmount, privileged);
        vm.stopPrank();

        // Transfer shares to non-privileged user
        vm.startPrank(privileged);
        ERC20(address(_vault())).transfer(nonPrivileged, shares);
        vm.stopPrank();

        // Non-privileged user should be able to withdraw
        vm.startPrank(nonPrivileged);
        uint256 withdrawAmount = IERC4626(address(_vault())).maxWithdraw(nonPrivileged);
        uint256 withdrawn = IERC4626(address(_vault())).withdraw(withdrawAmount, nonPrivileged, nonPrivileged);
        vm.stopPrank();

        assertGt(withdrawn, 0, "Non-privileged should be able to withdraw");
    }

    /// @notice Test that non-privileged users can still redeem (redemptions are not restricted)
    function _testRedeemWorksForNonPrivileged() internal {
        uint256 depositAmount = _minDeposit();
        address privileged = _privilegedUser();
        address nonPrivileged = _nonPrivilegedUser();

        // First, privileged user deposits
        _airdrop(_asset(), privileged, depositAmount);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        uint256 shares = _vault().deposit(depositAmount, privileged);
        vm.stopPrank();

        // Transfer shares to non-privileged user
        vm.startPrank(privileged);
        ERC20(address(_vault())).transfer(nonPrivileged, shares);
        vm.stopPrank();

        // Non-privileged user should be able to redeem
        vm.startPrank(nonPrivileged);
        // Use maxRedeem to avoid "redeem more than max" errors from underlying vault constraints
        uint256 maxRedeemable = IERC4626(address(_vault())).maxRedeem(nonPrivileged);
        uint256 sharesToRedeem = shares > maxRedeemable ? maxRedeemable : shares;
        uint256 assets = IERC4626(address(_vault())).redeem(sharesToRedeem, nonPrivileged, nonPrivileged);
        vm.stopPrank();

        assertGt(assets, 0, "Non-privileged should be able to redeem");
    }

    /// @notice Test that transfers work regardless of privilege status
    function _testTransferWorksForNonPrivileged() internal {
        uint256 depositAmount = _minDeposit();
        address privileged = _privilegedUser();
        address nonPrivileged = _nonPrivilegedUser();
        address recipient = makeAddr("recipient");

        // First, privileged user deposits
        _airdrop(_asset(), privileged, depositAmount);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        uint256 shares = _vault().deposit(depositAmount, privileged);
        vm.stopPrank();

        // Transfer shares to non-privileged user
        vm.startPrank(privileged);
        ERC20(address(_vault())).transfer(nonPrivileged, shares);
        vm.stopPrank();

        // Non-privileged user should be able to transfer
        vm.startPrank(nonPrivileged);
        ERC20(address(_vault())).transfer(recipient, shares / 2);
        vm.stopPrank();

        assertEq(_vault().balanceOf(recipient), shares / 2, "Transfer should work for non-privileged");
    }

    /// @notice Fuzz test deposit with privilege check
    function _testFuzzPrivilegedDeposit(uint256 depositAmount) internal {
        depositAmount = bound(depositAmount, _minDeposit(), _maxDeposit());
        address privileged = _privilegedUser();

        _airdrop(_asset(), privileged, depositAmount);

        vm.startPrank(privileged);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        uint256 shares = _vault().deposit(depositAmount, privileged);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertEq(_vault().balanceOf(privileged), shares, "Should have correct share balance");
    }

    /// @notice Test privileged user can deposit to another privileged user
    function _testPrivilegedCanDepositToAnotherPrivileged() internal {
        uint256 depositAmount = _minDeposit();
        address privileged1 = _privilegedUser();
        address privileged2 = makeAddr("privileged2");

        // Make privileged2 privileged
        vm.prank(_management());
        IPrivilegedStrategy(_privilegedStrategy()).setPrivileged(privileged2, true);

        _airdrop(_asset(), privileged1, depositAmount);

        vm.startPrank(privileged1);
        ERC20(_asset()).approve(address(_vault()), depositAmount);
        uint256 shares = _vault().deposit(depositAmount, privileged2);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertEq(_vault().balanceOf(privileged2), shares, "Receiver should have shares");
        assertEq(_vault().balanceOf(privileged1), 0, "Sender should have no shares");
    }

    /// @notice Test isPrivileged view function
    function _testIsPrivilegedViewFunction() internal view {
        address privileged = _privilegedUser();
        address nonPrivileged = _nonPrivilegedUser();

        assertTrue(
            IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(privileged),
            "Privileged user should return true"
        );
        assertFalse(
            IPrivilegedStrategy(_privilegedStrategy()).isPrivileged(nonPrivileged),
            "Non-privileged user should return false"
        );
    }
}
