// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";

/**
 * @title VerifyRegenStakerFactory
 * @author Golem Foundation
 * @notice Script to verify deployed RegenStakerFactory contract on Ethereum mainnet
 * @dev Prompts user for contract address and verifies using forge verify-contract
 *
 * Usage:
 * forge script script/verify/VerifyRegenStakerFactory.s.sol:VerifyRegenStakerFactory \
 *   --rpc-url $ETH_RPC_URL \
 *   --etherscan-api-key $ETHERSCAN_API_KEY \
 *   --ffi
 *
 * Optional:
 * export CHAIN_ID=1
 * export REGEN_STAKER_FACTORY=0x...
 */
contract VerifyRegenStakerFactory is Script {
    // Contract address (to be prompted from user)
    address public regenStakerFactory;

    // Contract name for verification
    string constant CONTRACT_NAME = "src/factories/RegenStakerFactory.sol:RegenStakerFactory";

    bytes32 public regenStakerBytecodeHash;
    bytes32 public noDelegationBytecodeHash;
    uint256 public chainId;

    function run() public {
        chainId = vm.envOr("CHAIN_ID", block.chainid);

        _promptForAddress();
        _computeConstructorArgs();
        _verifyContract();
        _logSummary();
    }

    function _promptForAddress() internal {
        console.log("=== REGEN STAKER FACTORY VERIFICATION ===");
        console.log("Please provide the deployed contract address:\n");

        regenStakerFactory = vm.envOr("REGEN_STAKER_FACTORY", address(0));
        if (regenStakerFactory != address(0)) {
            console.log("[OK] RegenStakerFactory:", regenStakerFactory);
        } else {
            try vm.prompt("Enter RegenStakerFactory address") returns (string memory addr) {
                regenStakerFactory = vm.parseAddress(addr);
                console.log("[OK] RegenStakerFactory:", regenStakerFactory);
            } catch {
                revert("Invalid RegenStakerFactory address");
            }
        }

        console.log("\n=== ADDRESS COLLECTED ===\n");
    }

    function _computeConstructorArgs() internal {
        regenStakerBytecodeHash = keccak256(type(RegenStaker).creationCode);
        noDelegationBytecodeHash = keccak256(type(RegenStakerWithoutDelegateSurrogateVotes).creationCode);

        console.log("RegenStaker bytecode hash:");
        console.logBytes32(regenStakerBytecodeHash);
        console.log("RegenStakerWithoutDelegation bytecode hash:");
        console.logBytes32(noDelegationBytecodeHash);
    }

    function _verifyContract() internal {
        console.log("=== STARTING CONTRACT VERIFICATION ===\n");
        console.log("Verifying RegenStakerFactory at", regenStakerFactory);
        console.log("Using chain ID:", chainId);

        bytes memory constructorArgs = abi.encode(regenStakerBytecodeHash, noDelegationBytecodeHash);

        string[] memory inputs = new string[](9);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(regenStakerFactory);
        inputs[3] = CONTRACT_NAME;
        inputs[4] = "--chain-id";
        inputs[5] = vm.toString(chainId);
        inputs[6] = "--constructor-args";
        inputs[7] = vm.toString(constructorArgs);
        inputs[8] = "--watch";

        try vm.ffi(inputs) returns (bytes memory result) {
            console.log("[SUCCESS] RegenStakerFactory verification initiated");
            console.log("   Result:", string(result));
        } catch (bytes memory error) {
            console.log("[FAILED] RegenStakerFactory verification failed");
            console.log("   Error:", string(error));
        }

        console.log("");
    }

    function _logSummary() internal view {
        console.log("\n=== VERIFICATION SUMMARY ===");
        console.log("Attempted to verify:");
        console.log("- RegenStakerFactory:", regenStakerFactory);
        console.log("Chain ID:", chainId);
        console.log("\nNote: Verification is asynchronous. Check Etherscan for final status.");
        console.log("Contract path:", CONTRACT_NAME);
        console.log("==============================\n");
    }
}
