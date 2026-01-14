// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";

/**
 * @title VerifyAddressSetFactory
 * @author Golem Foundation
 * @notice Script to verify deployed AddressSetFactory contract on Ethereum mainnet
 * @dev Prompts user for contract address and verifies using forge verify-contract
 *
 * Usage:
 * forge script script/verify/VerifyAddressSetFactory.s.sol:VerifyAddressSetFactory \
 *   --rpc-url $ETH_RPC_URL \
 *   --etherscan-api-key $ETHERSCAN_API_KEY \
 *   --ffi
 *
 * Optional:
 * export CHAIN_ID=1
 * export ADDRESS_SET_FACTORY=0x...
 */
contract VerifyAddressSetFactory is Script {
    // Contract address (to be prompted from user)
    address public addressSetFactory;

    // Contract name for verification
    string constant CONTRACT_NAME = "src/factories/AddressSetFactory.sol:AddressSetFactory";

    // Chain ID used for verification (defaults to RPC chain id)
    uint256 public chainId;

    function run() public {
        chainId = vm.envOr("CHAIN_ID", block.chainid);

        // Prompt user for contract address
        _promptForAddress();

        // Verify the contract
        _verifyContract();

        // Log summary
        _logSummary();
    }

    function _promptForAddress() internal {
        console.log("=== ADDRESS SET FACTORY VERIFICATION ===");
        console.log("Please provide the deployed contract address:\n");

        addressSetFactory = vm.envOr("ADDRESS_SET_FACTORY", address(0));
        if (addressSetFactory != address(0)) {
            console.log("[OK] AddressSetFactory:", addressSetFactory);
        } else {
            try vm.prompt("Enter AddressSetFactory address") returns (string memory addr) {
                addressSetFactory = vm.parseAddress(addr);
                console.log("[OK] AddressSetFactory:", addressSetFactory);
            } catch {
                revert("Invalid AddressSetFactory address");
            }
        }

        console.log("\n=== ADDRESS COLLECTED ===\n");
    }

    function _verifyContract() internal {
        console.log("=== STARTING CONTRACT VERIFICATION ===\n");
        console.log("Verifying AddressSetFactory at", addressSetFactory);
        console.log("Using chain ID:", chainId);

        string[] memory inputs = new string[](7);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(addressSetFactory);
        inputs[3] = CONTRACT_NAME;
        inputs[4] = "--chain-id";
        inputs[5] = vm.toString(chainId);
        inputs[6] = "--watch";

        try vm.ffi(inputs) returns (bytes memory result) {
            console.log("[SUCCESS] AddressSetFactory verification initiated");
            console.log("   Result:", string(result));
        } catch (bytes memory error) {
            console.log("[FAILED] AddressSetFactory verification failed");
            console.log("   Error:", string(error));
        }

        console.log("");
    }

    function _logSummary() internal view {
        console.log("\n=== VERIFICATION SUMMARY ===");
        console.log("Attempted to verify:");
        console.log("- AddressSetFactory:", addressSetFactory);
        console.log("Chain ID:", chainId);
        console.log("\nNote: Verification is asynchronous. Check Etherscan for final status.");
        console.log("Contract path:", CONTRACT_NAME);
        console.log("==============================\n");
    }
}
