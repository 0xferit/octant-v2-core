// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { BaseYieldDonatingIntegrationTest } from "../../YieldDonating/base/BaseYieldDonatingIntegrationTest.sol";
import { BaseIntegrationTest } from "../../base/BaseIntegrationTest.sol";
import { BasePrivilegedIntegrationTest, IPrivilegedStrategy } from "../../base/BasePrivilegedIntegrationTest.sol";

/// @title BasePrivilegedYieldDonatingIntegrationTest
/// @notice Base contract for privileged yield donating strategy integration tests
/// @dev Combines YieldDonating base tests with privileged access control tests
abstract contract BasePrivilegedYieldDonatingIntegrationTest is
    BaseYieldDonatingIntegrationTest,
    BasePrivilegedIntegrationTest
{
    // ========== STATE VARIABLES ==========

    /// @notice Address of a privileged test user
    address public privilegedUser;

    /// @notice Address of a non-privileged test user
    address public nonPrivilegedUser;

    // ========== IMPLEMENTATION OF ABSTRACT METHODS ==========

    function _vault() internal view override returns (ITokenizedStrategy) {
        return vault;
    }

    /// @dev Override for BaseIntegrationTest and BasePrivilegedIntegrationTest - delegates to the concrete implementation
    function _asset() internal view virtual override(BaseIntegrationTest, BasePrivilegedIntegrationTest) returns (address);

    function _management() internal view override returns (address) {
        return management;
    }

    function _privilegedStrategy() internal view virtual override returns (address) {
        return address(vault);
    }

    function _privilegedUser() internal view override returns (address) {
        return privilegedUser;
    }

    function _nonPrivilegedUser() internal view override returns (address) {
        return nonPrivilegedUser;
    }

    function _airdrop(address token, address to, uint256 amount) internal override {
        airdrop(ERC20(token), to, amount);
    }

    /// @dev Override for BasePrivilegedIntegrationTest - delegates to the concrete implementation
    function _minDeposit() internal view virtual override(BaseYieldDonatingIntegrationTest, BasePrivilegedIntegrationTest) returns (uint256);

    /// @dev Override for BasePrivilegedIntegrationTest - delegates to the concrete implementation
    function _maxDeposit() internal view virtual override(BaseYieldDonatingIntegrationTest, BasePrivilegedIntegrationTest) returns (uint256);

    // ========== SETUP HELPERS ==========

    /// @notice Sets up the privileged and non-privileged users
    function _setupPrivilegedUsers() internal virtual {
        privilegedUser = makeAddr("privilegedUser");
        nonPrivilegedUser = makeAddr("nonPrivilegedUser");

        // Make the privilegedUser privileged
        vm.startPrank(management);
        IPrivilegedStrategy(address(vault)).setPrivileged(privilegedUser, true);
        vm.stopPrank();

        // Ensure user is also privileged for base tests
        vm.startPrank(management);
        IPrivilegedStrategy(address(vault)).setPrivileged(user, true);
        vm.stopPrank();
    }

    /// @notice Grants privilege status to an array of test users
    /// @param users Array of addresses to grant privilege to
    function _grantPrivilegeToTestUsers(address[] memory users) internal {
        vm.startPrank(management);
        for (uint256 i = 0; i < users.length; i++) {
            IPrivilegedStrategy(address(vault)).setPrivileged(users[i], true);
        }
        vm.stopPrank();
    }

    /// @notice Extended base setup that includes privileged user setup
    function _privilegedBaseSetUp() internal virtual {
        _baseSetUp();
        _setupPrivilegedUsers();
    }
}
