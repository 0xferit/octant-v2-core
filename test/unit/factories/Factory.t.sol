// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";
import { MultistrategyVault } from "src/core/MultistrategyVault.sol";
import { IMultistrategyVaultFactory } from "src/factories/interfaces/IMultistrategyVaultFactory.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

// Mocks needed for testing
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract VaultFactoryTest is Test {
    // Constants
    uint256 constant WEEK = 7 * 24 * 60 * 60; // 1 week in seconds

    // Test addresses
    address gov;
    address bunny;
    address fish;

    // Contracts
    MockERC20 asset;
    MultistrategyVaultFactory vaultFactory;
    address vaultImplementation;

    function setUp() public {
        // Setup roles
        gov = address(0x1);
        bunny = address(0x2);
        fish = address(0x3);

        // Setup contracts
        asset = new MockERC20(18);

        // Deploy a vault implementation
        // Note: In a real test, you'd deploy the actual vault implementation
        vaultImplementation = address(new MultistrategyVault());

        // Deploy the vault factory
        vaultFactory = new MultistrategyVaultFactory("Vault V3 Factory test", vaultImplementation, gov);

        // Label addresses for better trace output
        vm.label(gov, "Governor");
        vm.label(bunny, "Bunny");
        vm.label(fish, "Fish");
        vm.label(address(asset), "Asset");
        vm.label(address(vaultFactory), "VaultFactory");
        vm.label(vaultImplementation, "VaultImplementation");
    }

    function testNewVaultWithDifferentSalt() public {
        assertEq(vaultFactory.name(), "Vault V3 Factory test");

        // Deploy first vault
        vm.prank(gov);
        address newVaultAddr = vaultFactory.deployNewVault(address(asset), "first_vault", "fv", bunny, WEEK);

        // Check the events and vault properties
        MultistrategyVault newVault = MultistrategyVault(newVaultAddr);
        assertEq(newVault.name(), "first_vault");
        assertEq(newVault.roleManager(), bunny);

        // Deploy second vault
        vm.prank(gov);
        address secondVaultAddr = vaultFactory.deployNewVault(address(asset), "second_vault", "sv", fish, WEEK);

        // Check the events and vault properties
        IMultistrategyVault secondVault = IMultistrategyVault(secondVaultAddr);
        assertEq(secondVault.name(), "second_vault");
        assertEq(secondVault.roleManager(), fish);
    }

    function testNewVaultSameNameAssetAndSymbolDifferentSender() public {
        // Deploy first vault from gov
        vm.prank(gov);
        address newVaultAddr = vaultFactory.deployNewVault(address(asset), "first_vault", "fv", bunny, WEEK);

        // Check properties
        IMultistrategyVault newVault = IMultistrategyVault(newVaultAddr);
        assertEq(newVault.name(), "first_vault");
        assertEq(newVault.roleManager(), bunny);

        // Deploy same vault from bunny
        vm.prank(bunny);
        address anotherVaultAddr = vaultFactory.deployNewVault(address(asset), "first_vault", "fv", bunny, WEEK);

        // Check properties
        IMultistrategyVault anotherVault = IMultistrategyVault(anotherVaultAddr);
        assertEq(anotherVault.name(), "first_vault");
        assertEq(anotherVault.roleManager(), bunny);
    }

    function testNewVaultSameSenderNameAssetAndSymbolReverts() public {
        // Deploy vault
        vm.prank(gov);
        address newVaultAddr = vaultFactory.deployNewVault(address(asset), "first_vault", "fv", bunny, WEEK);

        // Check properties
        IMultistrategyVault newVault = IMultistrategyVault(newVaultAddr);
        assertEq(newVault.name(), "first_vault");
        assertEq(newVault.roleManager(), bunny);

        // Try to deploy the same vault again with the same sender
        vm.prank(gov);
        vm.expectRevert(); // The revert doesn't have a specific reason in create2
        vaultFactory.deployNewVault(address(asset), "first_vault", "fv", bunny, WEEK);
    }

    function testShutdownFactory() public {
        assertEq(vaultFactory.shutdown(), false);

        // Shutdown the factory
        vm.prank(gov);
        vaultFactory.shutdownFactory();

        // Check state
        assertEq(vaultFactory.shutdown(), true);

        // Try to deploy a vault after shutdown
        vm.prank(gov);
        vm.expectRevert("shutdown");
        vaultFactory.deployNewVault(address(asset), "first_vault", "fv", bunny, WEEK);
    }

    function testShutdownFactoryReverts() public {
        assertEq(vaultFactory.shutdown(), false);

        // Try to shutdown from non-governance
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.shutdownFactory();
    }

    // --- Protocol fee configuration ---

    function testProtocolFeeConfig_defaultFee() public {
        // Set protocol fee recipient first
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(fish);

        // Set default protocol fee
        vm.prank(gov);
        vaultFactory.setProtocolFeeBps(1000); // 10%

        // Query protocol fee for any vault
        (uint16 feeBps, address recipient) = vaultFactory.protocolFeeConfig(bunny);
        assertEq(feeBps, 1000);
        assertEq(recipient, fish);
    }

    function testProtocolFeeConfig_customFee() public {
        // Set protocol fee recipient first
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(fish);

        // Set default fee
        vm.prank(gov);
        vaultFactory.setProtocolFeeBps(1000);

        // Set custom fee for bunny vault
        vm.prank(gov);
        vaultFactory.setCustomProtocolFeeBps(bunny, 500);

        // Query protocol fee - should return custom fee
        (uint16 feeBps, address recipient) = vaultFactory.protocolFeeConfig(bunny);
        assertEq(feeBps, 500);
        assertEq(recipient, fish); // recipient always from default

        assertTrue(vaultFactory.useCustomProtocolFee(bunny));
    }

    function testProtocolFeeConfig_zeroVaultUseMsgSender() public {
        // Set protocol fee recipient
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(fish);

        // Set default fee
        vm.prank(gov);
        vaultFactory.setProtocolFeeBps(1000);

        // Query with address(0) should use msg.sender
        vm.prank(bunny);
        (uint16 feeBps, ) = vaultFactory.protocolFeeConfig(address(0));
        assertEq(feeBps, 1000);
    }

    function testRemoveCustomProtocolFee() public {
        // Set protocol fee recipient
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(fish);

        // Set custom fee
        vm.prank(gov);
        vaultFactory.setCustomProtocolFeeBps(bunny, 500);
        assertTrue(vaultFactory.useCustomProtocolFee(bunny));

        // Remove custom fee
        vm.prank(gov);
        vaultFactory.removeCustomProtocolFee(bunny);
        assertFalse(vaultFactory.useCustomProtocolFee(bunny));
    }

    // --- Fee validation ---

    function testSetProtocolFeeBps_tooHigh_reverts() public {
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(fish);

        vm.prank(gov);
        vm.expectRevert("fee too high");
        vaultFactory.setProtocolFeeBps(5001);
    }

    function testSetProtocolFeeBps_noRecipient_reverts() public {
        vm.prank(gov);
        vm.expectRevert("no recipient");
        vaultFactory.setProtocolFeeBps(1000);
    }

    function testSetProtocolFeeBps_notGovernance_reverts() public {
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.setProtocolFeeBps(1000);
    }

    function testSetProtocolFeeRecipient_zeroAddress_reverts() public {
        vm.prank(gov);
        vm.expectRevert("zero address");
        vaultFactory.setProtocolFeeRecipient(address(0));
    }

    function testSetProtocolFeeRecipient_notGovernance_reverts() public {
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.setProtocolFeeRecipient(fish);
    }

    function testSetCustomProtocolFeeBps_tooHigh_reverts() public {
        vm.prank(gov);
        vaultFactory.setProtocolFeeRecipient(fish);

        vm.prank(gov);
        vm.expectRevert("fee too high");
        vaultFactory.setCustomProtocolFeeBps(bunny, 5001);
    }

    function testSetCustomProtocolFeeBps_noRecipient_reverts() public {
        vm.prank(gov);
        vm.expectRevert("no recipient");
        vaultFactory.setCustomProtocolFeeBps(bunny, 1000);
    }

    function testSetCustomProtocolFeeBps_notGovernance_reverts() public {
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.setCustomProtocolFeeBps(bunny, 1000);
    }

    function testRemoveCustomProtocolFee_notGovernance_reverts() public {
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.removeCustomProtocolFee(bunny);
    }

    // --- Governance transfer ---

    function testTransferGovernance_succeeds() public {
        vm.prank(gov);
        vaultFactory.transferGovernance(bunny);
        assertEq(vaultFactory.pendingGovernance(), bunny);

        vm.prank(bunny);
        vaultFactory.acceptGovernance();
        assertEq(vaultFactory.governance(), bunny);
        assertEq(vaultFactory.pendingGovernance(), address(0));
    }

    function testTransferGovernance_notGovernance_reverts() public {
        vm.prank(bunny);
        vm.expectRevert("not governance");
        vaultFactory.transferGovernance(bunny);
    }

    function testAcceptGovernance_notPending_reverts() public {
        vm.prank(bunny);
        vm.expectRevert("not pending governance");
        vaultFactory.acceptGovernance();
    }

    // --- Shutdown already shutdown ---

    function testShutdownFactory_alreadyShutdown_reverts() public {
        vm.prank(gov);
        vaultFactory.shutdownFactory();

        vm.prank(gov);
        vm.expectRevert("shutdown");
        vaultFactory.shutdownFactory();
    }

    // --- View functions ---

    function testApiVersion() public view {
        assertEq(vaultFactory.apiVersion(), "3.0.4");
    }

    function testVaultOriginal() public view {
        assertEq(vaultFactory.vaultOriginal(), vaultImplementation);
    }

    function testReinitializeVaultReverts() public {
        // Get the vault original
        address original = vaultFactory.vaultOriginal();

        // Try to initialize the original vault
        vm.prank(gov);
        vm.expectRevert(IMultistrategyVault.AlreadyInitialized.selector);
        IMultistrategyVault(original).initialize(address(asset), "first_vault", "fv", bunny, WEEK);

        // Deploy a new vault
        vm.prank(gov);
        address newVaultAddr = vaultFactory.deployNewVault(address(asset), "first_vault", "fv", bunny, WEEK);

        // Check properties
        IMultistrategyVault newVault = IMultistrategyVault(newVaultAddr);
        assertEq(newVault.name(), "first_vault");
        assertEq(newVault.roleManager(), bunny);

        // Try to reinitialize the new vault
        vm.prank(gov);
        vm.expectRevert(IMultistrategyVault.AlreadyInitialized.selector);
        newVault.initialize(address(asset), "first_vault", "fv", bunny, WEEK);
    }
}
