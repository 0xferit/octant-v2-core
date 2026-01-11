// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";
import { BatchScript } from "../helpers/BatchScript.sol";

/**
 * @title DeployAddressSetFactory
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Deployment script for AddressSetFactory via Safe multisig
 * @dev Deploys AddressSetFactory deterministically by calling the CREATE2 factory through Safe.
 *      This ensures the deployed address matches the predicted address.
 *
 * Usage:
 * ```bash
 * export SAFE_ADDRESS=0x...
 * export CHAIN=ethereum
 * export WALLET_TYPE=local # or ledger
 * export PRIVATE_KEY=0x... # required for WALLET_TYPE=local
 *
 * forge script script/deploy/DeployAddressSetFactory.s.sol:DeployAddressSetFactory \
 *   --rpc-url $ETH_RPC_URL \
 *   --ffi
 * ```
 */
contract DeployAddressSetFactory is Script, BatchScript {
    /// @notice Salt for deterministic factory deployment
    bytes32 public constant DEPLOYMENT_SALT = keccak256("OCTANT_ADDRESS_SET_FACTORY_V1");

    /// @notice Deployed factory contract (expected address)
    AddressSetFactory public factory;

    /// @notice Safe address used to submit the batch
    address public safe;

    function setUp() public {
        safe = vm.envOr("SAFE_ADDRESS", address(0));
        if (safe == address(0)) {
            try vm.prompt("Enter Safe Address") returns (string memory res) {
                safe = vm.parseAddress(res);
            } catch {
                revert("Invalid Safe Address");
            }
        }

        console.log("Using Safe:", safe);
    }

    function run() public isBatch(safe) {
        console.log("=== ADDRESS SET FACTORY DEPLOYMENT (SAFE) ===");

        bytes memory creationCode = type(AddressSetFactory).creationCode;
        address expectedAddress = _computeCreate2Address(CREATE2_FACTORY, DEPLOYMENT_SALT, keccak256(creationCode));
        console.log("Expected factory address:", expectedAddress);

        // Explicitly call CREATE2_FACTORY with salt + bytecode via Safe batch
        bytes memory deployData = abi.encodePacked(DEPLOYMENT_SALT, creationCode);
        addToBatch(CREATE2_FACTORY, 0, deployData);

        factory = AddressSetFactory(expectedAddress);

        executeBatch(true);
        _logDeploymentSummary();
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Safe Address:", safe);
        console.log("AddressSetFactory:", address(factory));
        console.log("\nBatch transaction created:");
        console.log("- Safe will call execTransaction once");
        console.log("- execTransaction calls MultiSendCallOnly");
        console.log("- MultiSendCallOnly calls CREATE2 factory");
        console.log("- CREATE2 factory deploys contract deterministically");
        console.log("\nTransaction sent to Safe for signing.");
        console.log("========================\n");
    }

    /**
     * @notice Compute expected CREATE2 address
     * @param factoryAddr CREATE2 factory address
     * @param salt Deployment salt
     * @param initCodeHash Hash of the contract's creation code
     * @return Expected deployment address
     */
    function _computeCreate2Address(
        address factoryAddr,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factoryAddr, salt, initCodeHash)))));
    }
}
