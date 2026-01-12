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
 * @notice Deployment script for RegenStakerFactory
 * @dev Deploys RegenStakerFactory deterministically using CREATE2.
 *
 * Usage:
 * ```bash
 * export SAFE_ADDRESS=0x...
 * export CHAIN=ethereum
 * export WALLET_TYPE=local # or ledger
 * export PRIVATE_KEY=0x... # required for WALLET_TYPE=local
 * export SENDER=0x... # must be a Safe owner or delegate
 *
 * forge script script/deploy/DeployRegenStakerFactory.s.sol:DeployRegenStakerFactory \
 *   --rpc-url $ETH_RPC_URL \
 *   --ffi \
 *   --sender $SENDER
 * ```
 *
 * Note: The --sender flag must be set to the address corresponding to PRIVATE_KEY.
 *       This address must be an owner or delegate of the Safe.
 */
contract DeployRegenStakerFactory is Script, BatchScript {
    error AddressMismatch(address expected, address actual);
    error DeploymentFailed();

    /// @notice Salt for deterministic deployment
    bytes32 public constant DEPLOYMENT_SALT = keccak256("OCTANT_REGEN_STAKER_FACTORY_V1");

    /// @notice Deployed factory contract
    RegenStakerFactory public regenStakerFactory;

    /// @notice Safe address used to submit the batch
    address public safe;

    function setUp() public {
        safe = _loadSafeAddress();

        console.log("Using Safe:", safe);
    }

    function run() public isBatch(safe) returns (address) {
        return _deploy();
    }

    function _deploy() internal returns (address) {
        console.log("=== REGEN STAKER FACTORY DEPLOYMENT ===");

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
        address expectedAddress = _computeCreate2AddressViaFactory(DEPLOYMENT_SALT, creationCode);
        console.log("Expected address:", expectedAddress);

        bytes memory deployData = abi.encodePacked(DEPLOYMENT_SALT, creationCode);
        bytes memory result = executeTransaction(CREATE2_FACTORY, 0, deployData, Operation.CALL, true);
        address deployedAddress = _decodeCreate2DeployerResult(result);
        if (deployedAddress != expectedAddress) {
            revert AddressMismatch(expectedAddress, deployedAddress);
        }

        regenStakerFactory = RegenStakerFactory(deployedAddress);

        console.log("RegenStakerFactory deployed at:", deployedAddress);
        return deployedAddress;
    }
}
