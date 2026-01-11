// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { BatchScript } from "../helpers/BatchScript.sol";

/**
 * @title DeployRegenStakerFactory
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Deployment script for RegenStakerFactory via Safe multisig
 * @dev Deploys RegenStakerFactory deterministically using CREATE2 with a salt for consistent addresses.
 *
 * Usage:
 * ```bash
 * export SAFE_ADDRESS=0x...
 * export CHAIN=ethereum
 * export WALLET_TYPE=local # or ledger
 * export PRIVATE_KEY=0x... # required for WALLET_TYPE=local
 *
 * forge script script/deploy/DeployRegenStakerFactory.s.sol:DeployRegenStakerFactory \
 *   --rpc-url $ETH_RPC_URL \
 *   --ffi
 * ```
 */
contract DeployRegenStakerFactory is Script, BatchScript {
    /// @notice Salt for deterministic deployment
    bytes32 public constant DEPLOYMENT_SALT = keccak256("OCTANT_REGEN_STAKER_FACTORY_V1");

    /// @notice Deployed factory contract (expected address)
    RegenStakerFactory public regenStakerFactory;

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

    function run() public virtual isBatch(safe) {
        console.log("=== REGEN STAKER FACTORY DEPLOYMENT (SAFE) ===");

        bytes32 regenStakerBytecodeHash = keccak256(type(RegenStaker).creationCode);
        bytes32 noDelegationBytecodeHash = keccak256(type(RegenStakerWithoutDelegateSurrogateVotes).creationCode);

        console.log("RegenStaker bytecode hash:");
        console.logBytes32(regenStakerBytecodeHash);
        console.log("RegenStakerWithoutDelegation bytecode hash:");
        console.logBytes32(noDelegationBytecodeHash);

        bytes memory creationCode = abi.encodePacked(
            type(RegenStakerFactory).creationCode,
            abi.encode(regenStakerBytecodeHash, noDelegationBytecodeHash)
        );
        address expectedAddress = _computeCreate2Address(CREATE2_FACTORY, DEPLOYMENT_SALT, keccak256(creationCode));
        console.log("Expected address:", expectedAddress);

        // Explicitly call CREATE2_FACTORY with salt + bytecode via Safe batch
        bytes memory deployData = abi.encodePacked(DEPLOYMENT_SALT, creationCode);
        addToBatch(CREATE2_FACTORY, 0, deployData);

        regenStakerFactory = RegenStakerFactory(expectedAddress);

        executeBatch(true);
        _logDeploymentSummary();
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Safe Address:", safe);
        console.log("RegenStakerFactory:", address(regenStakerFactory));
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
     * @param factory CREATE2 factory address
     * @param salt Deployment salt
     * @param initCodeHash Hash of the contract's creation code (including constructor args)
     * @return Expected deployment address
     */
    function _computeCreate2Address(
        address factory,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factory, salt, initCodeHash)))));
    }
}
