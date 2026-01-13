// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Hats } from "hats-protocol/Hats.sol";
import { DragonHatter } from "src/utils/hats/DragonHatter.sol";
import { SimpleEligibilityAndToggle } from "src/utils/hats/SimpleEligibilityAndToggle.sol";

/**
 * @title DeployHatsProtocol
 * @notice Script to deploy Hats protocol and setup Dragon Protocol hat hierarchy
 * @dev Follows the structure:
 * 1 (Top Hat)
 * └── 1.1 (Autonomous Admin Hat - Protocol)
 *     └── 1.1.1 (Admin Hat - Dragon)
 *         └── 1.1.1.1 (Branch Hat - Vault Management)
 */
contract DeployHatsProtocol is Test {
    // Constants for Hats protocol setup
    string public constant BASE_IMAGE_URI = "https://www.images.hats.work/";
    string public constant PROTOCOL_NAME = "Dragon Protocol Hats";
    uint32 public constant DEFAULT_MAX_SUPPLY = 5;

    // Hat IDs
    uint256 public topHatId;
    uint256 public autonomousAdminHatId;
    uint256 public dragonAdminHatId;
    uint256 public branchHatId;

    // Deployed contracts
    Hats public hats;
    DragonHatter public dragonHatter;
    SimpleEligibilityAndToggle public simpleEligibilityAndToggle;

    function deploy() public virtual {
        // Start broadcasting transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        // 1. Deploy Hats protocol
        hats = new Hats(PROTOCOL_NAME, BASE_IMAGE_URI);
        // Deploy DragonHatter with branch hat ID

        console2.log("HATS deployed");
        console2.log("HATS address:", address(hats));
        console2.log("Deployer address:", deployer);
        // 2. Create TopHat (1) and mint to deployer
        topHatId = hats.mintTopHat(deployer, "Dragon Protocol Top Hat", string.concat(BASE_IMAGE_URI, "tophat"));

        // Deploy simple eligibility and toggle module
        simpleEligibilityAndToggle = new SimpleEligibilityAndToggle();

        // 3. Create Autonomous Admin Hat (1.1)
        autonomousAdminHatId = hats.createHat(
            topHatId,
            "Dragon Protocol Autonomous Admin",
            DEFAULT_MAX_SUPPLY,
            address(simpleEligibilityAndToggle),
            address(simpleEligibilityAndToggle),
            true,
            string.concat(BASE_IMAGE_URI, "autonomous")
        );
        // Note: Initially unworn - can be used later for automation

        // 4. Create Dragon Admin Hat (1.1.1)
        dragonAdminHatId = hats.createHat(
            autonomousAdminHatId,
            "Dragon Protocol Admin",
            DEFAULT_MAX_SUPPLY,
            address(simpleEligibilityAndToggle), // No eligibility check yet
            address(simpleEligibilityAndToggle), // No toggle yet
            true, // Mutable
            string.concat(BASE_IMAGE_URI, "dragon-admin")
        );

        // Mint Dragon Admin hat to deployer so they can deploy DragonHatter
        hats.mintHat(dragonAdminHatId, deployer);

        // Create branch hat with proper admin rights
        branchHatId = hats.createHat(
            dragonAdminHatId,
            "Dragon Protocol Vault Management",
            DEFAULT_MAX_SUPPLY, // Only one admin for branch
            address(simpleEligibilityAndToggle), // Will be set to DragonHatter after deployment
            address(simpleEligibilityAndToggle), // Will be set to DragonHatter after deployment
            true,
            ""
        );

        // Deploy DragonHatter with branch hat ID
        dragonHatter = new DragonHatter(address(hats), dragonAdminHatId, branchHatId);

        // Set eligibility and toggle to DragonHatter
        // HATS.setHatEligibility(branchHatId, address(dragonHatter));
        // HATS.setHatToggle(branchHatId, address(dragonHatter));

        // Mint branch hat to DragonHatter
        hats.mintHat(branchHatId, address(dragonHatter));

        // Initialize roles
        dragonHatter.initialize();

        // Grant roles to deployer using DragonHatter's grantRole function
        dragonHatter.grantRole(dragonHatter.KEEPER_ROLE(), deployer);
        dragonHatter.grantRole(dragonHatter.MANAGEMENT_ROLE(), deployer);
        dragonHatter.grantRole(dragonHatter.EMERGENCY_ROLE(), deployer);
        dragonHatter.grantRole(dragonHatter.REGEN_GOVERNANCE_ROLE(), deployer);

        vm.label(address(dragonHatter), "DragonHatter");
        vm.label(address(simpleEligibilityAndToggle), "SimpleEligibilityAndToggle");
        vm.label(address(msg.sender), "Deployer");

        vm.stopBroadcast();

        // Log deployed addresses and hat IDs
        // console.log("Hats Protocol deployed at:", address(HATS));
        // console.log("DragonHatter deployed at:", address(dragonHatter));
        // console.log("Top Hat ID:", topHatId);
        // console.log("Autonomous Admin Hat ID:", autonomousAdminHatId);
        // console.log("Dragon Admin Hat ID:", dragonAdminHatId);
        // console.log("Branch Hat ID:", branchHatId);

        // Log role hat IDs
        // console.log("Keeper Role Hat ID:", dragonHatter.getRoleHat(dragonHatter.KEEPER_ROLE()));
        // console.log("Management Role Hat ID:", dragonHatter.getRoleHat(dragonHatter.MANAGEMENT_ROLE()));
        // console.log("Emergency Role Hat ID:", dragonHatter.getRoleHat(dragonHatter.EMERGENCY_ROLE()));
        // console.log("Regen Governance Role Hat ID:", dragonHatter.getRoleHat(dragonHatter.REGEN_GOVERNANCE_ROLE()));
    }
}
