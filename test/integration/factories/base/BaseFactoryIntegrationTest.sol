// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { BaseStrategyFactory } from "src/factories/BaseStrategyFactory.sol";

/// @title BaseFactoryIntegrationTest
/// @notice Base contract for all factory integration tests providing common infrastructure
abstract contract BaseFactoryIntegrationTest is Test {
    using SafeERC20 for ERC20;

    // ========== STATE VARIABLES ==========

    /// @notice Management address
    address public management;

    /// @notice Keeper address
    address public keeper;

    /// @notice Emergency admin address
    address public emergencyAdmin;

    /// @notice Donation address
    address public donationAddress;

    /// @notice Mainnet fork ID
    uint256 public mainnetFork;

    // ========== ABSTRACT METHODS ==========

    /// @notice Returns the factory address
    function _factory() internal view virtual returns (address);

    /// @notice Returns the implementation address
    function _implementation() internal view virtual returns (address);

    /// @notice Returns the expected asset address for strategies
    function _asset() internal pure virtual returns (address);

    /// @notice Returns the strategy symbol prefix
    function _strategySymbolPrefix() internal pure virtual returns (string memory);

    /// @notice Creates a strategy with the given parameters
    /// @param name The strategy name
    /// @param symbol The strategy symbol
    /// @param mgmt The management address
    /// @return The deployed strategy address
    function _createStrategy(
        string memory name,
        string memory symbol,
        address mgmt
    ) internal virtual returns (address);

    /// @notice Deploys the factory
    function _deployFactory() internal virtual;

    /// @notice Deploys the implementation and returns its address
    function _deployImplementation() internal virtual returns (address);

    /// @notice Labels factory-specific addresses
    function _labelFactoryAddresses() internal virtual;

    // ========== SHARED SETUP ==========

    /// @notice Base setup that should be called by derived contracts
    function _baseSetUp() internal virtual {
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);
        _setupRoles();
        _deployImplementation();
        _deployFactory();
        _labelBaseAddresses();
        _labelFactoryAddresses();
    }

    /// @notice Sets up role addresses
    function _setupRoles() internal virtual {
        management = address(0x1);
        keeper = address(0x2);
        emergencyAdmin = address(0x3);
        donationAddress = address(0x4);
    }

    /// @notice Labels base addresses
    function _labelBaseAddresses() internal virtual {
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
    }

    // ========== SHARED TEST IMPLEMENTATIONS ==========

    /// @notice Shared test: strategy creation
    /// @param vaultName The vault name to use
    /// @param symbol The symbol to use
    function _testCreateStrategy(string memory vaultName, string memory symbol) internal virtual {
        vm.startPrank(management);
        address strategyAddress = _createStrategy(vaultName, symbol, management);
        vm.stopPrank();

        // Verify factory tracking
        (address deployerAddress, uint256 timestamp, string memory name, address stratDonationAddress) =
            BaseStrategyFactory(_factory()).strategies(management, 0);
        assertEq(deployerAddress, management, "Deployer address incorrect");
        assertEq(name, vaultName, "Vault name incorrect");
        assertEq(stratDonationAddress, donationAddress, "Donation address incorrect");
        assertTrue(timestamp > 0, "Timestamp should be set");

        // Verify strategy asset and symbol
        assertEq(IERC4626(strategyAddress).asset(), _asset(), "Asset incorrect");
        assertEq(ITokenizedStrategy(strategyAddress).symbol(), symbol, "Symbol incorrect");
    }

    /// @notice Shared test: multiple strategies per user
    /// @param first The first vault name
    /// @param second The second vault name
    function _testMultipleStrategiesPerUser(string memory first, string memory second) internal virtual {
        vm.startPrank(management);
        address firstAddr = _createStrategy(first, string.concat(_strategySymbolPrefix(), "1"), management);
        address secondAddr = _createStrategy(second, string.concat(_strategySymbolPrefix(), "2"), management);
        vm.stopPrank();

        (address deployer1,, string memory name1,) = BaseStrategyFactory(_factory()).strategies(management, 0);
        assertEq(deployer1, management, "First deployer address incorrect");
        assertEq(name1, first, "First vault name incorrect");

        (address deployer2,, string memory name2,) = BaseStrategyFactory(_factory()).strategies(management, 1);
        assertEq(deployer2, management, "Second deployer address incorrect");
        assertEq(name2, second, "Second vault name incorrect");

        assertTrue(firstAddr != secondAddr, "Strategies should have different addresses");
    }

    /// @notice Shared test: multiple users
    function _testMultipleUsers() internal virtual {
        address firstUser = address(0x5678);
        address secondUser = address(0x9876);

        vm.startPrank(firstUser);
        address firstAddr = _createStrategy("First User Vault", string.concat(_strategySymbolPrefix(), "1"), firstUser);
        vm.stopPrank();

        vm.startPrank(secondUser);
        address secondAddr =
            _createStrategy("Second User Vault", string.concat(_strategySymbolPrefix(), "2"), secondUser);
        vm.stopPrank();

        (address deployer1,, string memory name1,) = BaseStrategyFactory(_factory()).strategies(firstUser, 0);
        assertEq(deployer1, firstUser, "First user's deployer address incorrect");
        assertEq(name1, "First User Vault", "First user's vault name incorrect");

        (address deployer2,, string memory name2,) = BaseStrategyFactory(_factory()).strategies(secondUser, 0);
        assertEq(deployer2, secondUser, "Second user's deployer address incorrect");
        assertEq(name2, "Second User Vault", "Second user's vault name incorrect");

        assertTrue(firstAddr != secondAddr, "Strategies should have different addresses");
    }

    /// @notice Shared test: deterministic addressing
    function _testDeterministicAddressing() internal virtual {
        string memory vaultName = "Deterministic Vault";
        string memory symbol = string.concat(_strategySymbolPrefix(), "DET");

        vm.startPrank(management);
        address firstAddr = _createStrategy(vaultName, symbol, management);

        // Same params should revert
        vm.expectRevert(abi.encodeWithSelector(BaseStrategyFactory.StrategyAlreadyExists.selector, firstAddr));
        _createStrategy(vaultName, symbol, management);

        // Different params should succeed
        address secondAddr =
            _createStrategy("Different Vault", string.concat(_strategySymbolPrefix(), "DIF"), management);
        vm.stopPrank();

        assertTrue(firstAddr != secondAddr, "Different params should create different address");
    }
}
