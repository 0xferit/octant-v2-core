// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { BatchScript } from "../helpers/BatchScript.sol";

/**
 * @title DeployAddressSet
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Deployment script for AddressSet contracts via AddressSetFactory using Safe multisig
 * @dev Deploys AddressSet instances through the factory for correct ownership and deterministic addresses.
 *
 *      PREREQUISITES:
 *      - AddressSetFactory must be deployed first (use DeployAddressSetFactory.s.sol)
 *      - Set ADDRESS_SET_FACTORY env var to the factory address
 *
 * Usage:
 * ```bash
 * # Deploy a staker allowset through Safe
 * export SAFE_ADDRESS=0x...
 * export CHAIN=ethereum
 * export WALLET_TYPE=local # or ledger
 * export PRIVATE_KEY=0x... # required for WALLET_TYPE=local
 * export ADDRESS_SET_FACTORY=0x...
 * export ADDRESS_SET_SALT=STAKER_ALLOWSET_V1
 *
 * forge script script/deploy/DeployAddressSet.s.sol:DeployAddressSet \
 *   --rpc-url $ETH_RPC_URL \
 *   --ffi
 * ```
 *
 * Environment Variables:
 * - ADDRESS_SET_FACTORY: Address of deployed AddressSetFactory
 * - ADDRESS_SET_SALT: Salt string for deterministic address (e.g., "STAKER_ALLOWSET_V1")
 * - ADDRESS_SET_OWNER: Address that will own the AddressSet (defaults to SAFE_ADDRESS)
 */
contract DeployAddressSet is Script, BatchScript {
    error AddressMismatch(address expected, address actual);
    error OwnerMismatch(address expected, address actual);
    error InvalidOwner();

    /// @notice Default salts for common AddressSet deployments
    bytes32 public constant STAKER_ALLOWSET_SALT = keccak256("OCTANT_STAKER_ALLOWSET_V1");
    bytes32 public constant STAKER_BLOCKSET_SALT = keccak256("OCTANT_STAKER_BLOCKSET_V1");
    bytes32 public constant ALLOCATION_MECHANISM_ALLOWSET_SALT = keccak256("OCTANT_ALLOCATION_MECHANISM_ALLOWSET_V1");

    /// @notice Deployed AddressSet contract
    AddressSet public addressSet;

    /// @notice AddressSetFactory used for deployments
    AddressSetFactory public factory;

    /// @notice Safe address used to submit the batch
    address public safe;

    /// @notice AddressSet owner (defaults to Safe)
    address public owner;

    function setUp() public {
        safe = vm.envOr("SAFE_ADDRESS", address(0));
        if (safe == address(0)) {
            try vm.prompt("Enter Safe Address") returns (string memory res) {
                safe = vm.parseAddress(res);
            } catch {
                revert("Invalid Safe Address");
            }
        }

        factory = AddressSetFactory(vm.envAddress("ADDRESS_SET_FACTORY"));
        owner = vm.envOr("ADDRESS_SET_OWNER", safe);
        if (owner == address(0)) revert InvalidOwner();

        console.log("Using Safe:", safe);
        console.log("Factory:", address(factory));
        console.log("Owner:", owner);
    }

    function run() public isBatch(safe) {
        _deploySingle();
        executeBatch(true);
    }

    function _deploySingle() internal returns (address) {
        string memory saltString = vm.envOr("ADDRESS_SET_SALT", string("OCTANT_ADDRESS_SET_V1"));
        bytes32 salt = keccak256(bytes(saltString));

        console.log("=== ADDRESSSET DEPLOYMENT VIA FACTORY ===");
        console.log("Owner:", owner);
        console.log("Salt string:", saltString);
        console.logBytes32(salt);

        address expectedAddress = factory.predictAddress(salt, owner);
        console.log("Expected AddressSet address:", expectedAddress);

        bytes memory result = addToBatch(
            address(factory),
            0,
            abi.encodeWithSignature("deploy(bytes32,address)", salt, owner)
        );
        address deployedAddress = abi.decode(result, (address));
        addressSet = AddressSet(deployedAddress);

        console.log("Deployed AddressSet address:", deployedAddress);

        if (expectedAddress != deployedAddress) {
            revert AddressMismatch(expectedAddress, deployedAddress);
        }
        console.log("[OK] Deployment is deterministic");

        address actualOwner = addressSet.owner();
        console.log("Owner:", actualOwner);

        if (actualOwner != owner) {
            revert OwnerMismatch(owner, actualOwner);
        }
        console.log("[OK] Ownership correctly set to owner");

        console.log("=== DEPLOYMENT COMPLETE ===");

        return deployedAddress;
    }

    /// @notice Deploy all three AddressSets needed for RegenStaker
    /// @return stakerAllowset Address of staker allowset
    /// @return stakerBlockset Address of staker blockset
    /// @return allocationMechanismAllowset Address of allocation mechanism allowset
    function deployAll()
        external
        isBatch(safe)
        returns (address stakerAllowset, address stakerBlockset, address allocationMechanismAllowset)
    {
        console.log("=== DEPLOYING ALL ADDRESSSETS FOR REGENSTAKER ===");
        console.log("Owner:", owner);
        console.log("Factory:", address(factory));

        bytes memory stakerAllowsetResult = addToBatch(
            address(factory),
            0,
            abi.encodeWithSignature("deploy(bytes32,address)", STAKER_ALLOWSET_SALT, owner)
        );
        stakerAllowset = abi.decode(stakerAllowsetResult, (address));
        console.log("Staker Allowset:", stakerAllowset);

        bytes memory stakerBlocksetResult = addToBatch(
            address(factory),
            0,
            abi.encodeWithSignature("deploy(bytes32,address)", STAKER_BLOCKSET_SALT, owner)
        );
        stakerBlockset = abi.decode(stakerBlocksetResult, (address));
        console.log("Staker Blockset:", stakerBlockset);

        bytes memory allocationMechanismAllowsetResult = addToBatch(
            address(factory),
            0,
            abi.encodeWithSignature("deploy(bytes32,address)", ALLOCATION_MECHANISM_ALLOWSET_SALT, owner)
        );
        allocationMechanismAllowset = abi.decode(allocationMechanismAllowsetResult, (address));
        console.log("Allocation Mechanism Allowset:", allocationMechanismAllowset);

        executeBatch(true);

        console.log("=== ALL ADDRESSSETS DEPLOYED ===");
    }
}
