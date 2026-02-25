// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { DeployAddressSet } from "script/deploy/DeployAddressSet.s.sol";
import { DeployRegenStaker } from "script/deploy/DeployRegenStaker.s.sol";
import { DeployRegenEarningPowerCalculator } from "script/deploy/DeployRegenEarningPowerCalculator.s.sol";
import { DeployedAddresses } from "script/helpers/DeployedAddresses.sol";

contract DeployRegenStakerWithSafe is Script {
    // Deployers
    DeployAddressSet public deployAddressSet;
    DeployRegenStaker public deployRegenStaker;
    DeployRegenEarningPowerCalculator public deployRegenEarningPowerCalculator;

    // Some factories
    address public addressSetFactory;
    address public regenStakerFactory;

    // Deployed contract addresses
    address public stakerAllowset;
    address public stakerBlockset;
    address public allocationMechanismAllowset;
    address public regenEarningPowerCalculator;
    address public regenStaker;

    // Address registry for network-specific deployments
    DeployedAddresses public immutable deployedAddresses;

    error DeploymentFailed();

    /**
     * @notice Constructor to initialize the deployed addresses registry
     * @dev Initializes the immutable deployedAddresses variable once
     */
    constructor() {
        deployedAddresses = new DeployedAddresses();
    }

    function setUp() public {
        setUpDeployedContracts();

        if (stakerAllowset == address(0)) {
            deployAddressSet = new DeployAddressSet();
            deployAddressSet.setUp();
        }

        if (regenEarningPowerCalculator == address(0)) {
            deployRegenEarningPowerCalculator = new DeployRegenEarningPowerCalculator();
            deployRegenEarningPowerCalculator.setUp();
        }

        deployRegenStaker = new DeployRegenStaker();
        deployRegenStaker.setUp();
    }

    /**
     * @notice Load previously deployed contract addresses for the current network
     * @dev Uses DeployedAddresses helper to get network-specific addresses via DEPLOYMENT_NETWORK env var
     *      Any address set to address(0) will trigger fresh deployment in the run() function
     *      Set DEPLOYMENT_NETWORK to: "mainnet", "sepolia", "staging", or "anvil"
     */
    function setUpDeployedContracts() public {
        DeployedAddresses.ContractAddresses memory addresses = deployedAddresses.getAddressesByEnv();

        addressSetFactory = vm.envOr("ADDRESS_SET_FACTORY", address(0));
        if (addressSetFactory == address(0)) {
            addressSetFactory = addresses.addressSetFactory;
            vm.setEnv("ADDRESS_SET_FACTORY", vm.toString(addressSetFactory));
        }

        regenStakerFactory = vm.envOr("REGEN_STAKER_FACTORY", address(0));
        if (regenStakerFactory == address(0)) {
            regenStakerFactory = addresses.regenStakerFactory;
            vm.setEnv("REGEN_STAKER_FACTORY", vm.toString(regenStakerFactory));
        }

        stakerAllowset = addresses.stakerAllowset;
        stakerBlockset = addresses.stakerBlockset;
        allocationMechanismAllowset = addresses.allocationMechanismAllowset;

        regenEarningPowerCalculator = addresses.regenEarningPowerCalculator;
        if(regenEarningPowerCalculator != address(0)) {
            vm.setEnv("EARNING_POWER_CALCULATOR", vm.toString(regenEarningPowerCalculator));
        }
    }

    function run() public {
        string memory startingBlock = vm.toString(block.number);

        // Deploy AddressSets
        if (stakerAllowset == address(0)) {
            (stakerAllowset, stakerBlockset, allocationMechanismAllowset) = deployAddressSet.deployAll();
            if (stakerAllowset == address(0)) revert DeploymentFailed();
            vm.setEnv("STAKER_ALLOWSET", vm.toString(stakerAllowset));
            vm.setEnv("STAKER_BLOCKSET", vm.toString(stakerBlockset));
            vm.setEnv("ALLOCATION_ALLOWSET", vm.toString(allocationMechanismAllowset));
        }

        if (regenEarningPowerCalculator == address(0)) {
            regenEarningPowerCalculator = deployRegenEarningPowerCalculator.run();
            if (regenEarningPowerCalculator == address(0)) revert DeploymentFailed();
            vm.setEnv("EARNING_POWER_CALCULATOR", vm.toString(regenEarningPowerCalculator));
        }

        if (regenStaker == address(0)) {
            regenStaker = deployRegenStaker.deployWithoutDelegation();
            if (regenStaker == address(0)) revert DeploymentFailed();
        }

        console2.log("\nDeployment Summary:");
        console2.log("------------------");
        console2.log("Starting block:                   ", startingBlock);
        console2.log("Staker Allowset:                  ", stakerAllowset);
        console2.log("Staker Blockset:                  ", stakerBlockset);
        console2.log("Allocation Mechanism Allowset:    ", allocationMechanismAllowset);
        console2.log("Earning Power Calculator:         ", regenEarningPowerCalculator);
        console2.log("RegenStakerFactory:               ", regenStakerFactory);
        console2.log("RegenStaker (without delegation): ", regenStaker);
        console2.log("------------------");
        console2.log("Now go to Safe app and approve all transactions in the batch with the above details. After confirming, you can verify the deployments on-chain and update your registry if needed.");
    }
}
