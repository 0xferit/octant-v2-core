// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { AddressSet } from "src/utils/AddressSet.sol";

/**
 * @title VerifyAddressSets
 * @author Golem Foundation
 * @notice Script to verify deployed AddressSet contracts on Ethereum mainnet
 * @dev Prompts user for contract addresses and verifies each using forge verify-contract
 *
 * Usage:
 * forge script script/verify/VerifyAddressSets.s.sol:VerifyAddressSets \
 *   --rpc-url $ETH_RPC_URL \
 *   --etherscan-api-key $ETHERSCAN_API_KEY \
 *   --ffi
 *
 * Optional:
 * export CHAIN_ID=1
 * export STAKER_ALLOWSET=0x...
 * export STAKER_BLOCKSET=0x...
 * export ALLOCATION_MECHANISM_ALLOWSET=0x...
 */
contract VerifyAddressSets is Script {
    // Contract addresses (to be prompted from user)
    address public stakerAllowset;
    address public stakerBlockset;
    address public allocationMechanismAllowset;

    // Contract name for verification
    string constant CONTRACT_NAME = "src/utils/AddressSet.sol:AddressSet";

    // Chain ID used for verification (defaults to RPC chain id)
    uint256 public chainId;

    function run() public {
        chainId = vm.envOr("CHAIN_ID", block.chainid);

        _promptForAddresses();
        _verifyContracts();
        _logSummary();
    }

    function _promptForAddresses() internal {
        console.log("=== ADDRESS SETS VERIFICATION ===");
        console.log("Please provide the deployed contract addresses:\n");

        stakerAllowset = vm.envOr("STAKER_ALLOWSET", address(0));
        if (stakerAllowset != address(0)) {
            console.log("[OK] Staker allowset:", stakerAllowset);
        } else {
            try vm.prompt("Enter staker allowset address") returns (string memory addr) {
                stakerAllowset = vm.parseAddress(addr);
                console.log("[OK] Staker allowset:", stakerAllowset);
            } catch {
                revert("Invalid staker allowset address");
            }
        }

        stakerBlockset = vm.envOr("STAKER_BLOCKSET", address(0));
        if (stakerBlockset != address(0)) {
            console.log("[OK] Staker blockset:", stakerBlockset);
        } else {
            try vm.prompt("Enter staker blockset address") returns (string memory addr) {
                stakerBlockset = vm.parseAddress(addr);
                console.log("[OK] Staker blockset:", stakerBlockset);
            } catch {
                revert("Invalid staker blockset address");
            }
        }

        allocationMechanismAllowset = vm.envOr("ALLOCATION_MECHANISM_ALLOWSET", address(0));
        if (allocationMechanismAllowset != address(0)) {
            console.log("[OK] Allocation mechanism allowset:", allocationMechanismAllowset);
        } else {
            try vm.prompt("Enter allocation mechanism allowset address") returns (string memory addr) {
                allocationMechanismAllowset = vm.parseAddress(addr);
                console.log("[OK] Allocation mechanism allowset:", allocationMechanismAllowset);
            } catch {
                revert("Invalid allocation mechanism allowset address");
            }
        }

        console.log("\n=== ALL ADDRESSES COLLECTED ===\n");
    }

    function _verifyContracts() internal {
        console.log("=== STARTING CONTRACT VERIFICATION ===\n");

        _verifyContract(stakerAllowset, "Staker allowset");
        _verifyContract(stakerBlockset, "Staker blockset");
        _verifyContract(allocationMechanismAllowset, "Allocation mechanism allowset");
    }

    function _verifyContract(address contractAddress, string memory displayName) internal {
        console.log("Verifying", displayName, "at", contractAddress);

        string[] memory inputs = new string[](7);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(contractAddress);
        inputs[3] = CONTRACT_NAME;
        inputs[4] = "--chain-id";
        inputs[5] = vm.toString(chainId);
        inputs[6] = "--watch";

        try vm.ffi(inputs) returns (bytes memory result) {
            console.log("[SUCCESS]", displayName, "verification initiated");
            console.log("   Result:", string(result));
        } catch (bytes memory error) {
            console.log("[FAILED]", displayName, "verification failed");
            console.log("   Error:", string(error));
        }

        console.log("");
    }

    function _logSummary() internal view {
        console.log("\n=== VERIFICATION SUMMARY ===");
        console.log("Attempted to verify the following contracts:");
        console.log("- Staker allowset:", stakerAllowset);
        console.log("- Staker blockset:", stakerBlockset);
        console.log("- Allocation mechanism allowset:", allocationMechanismAllowset);
        console.log("Chain ID:", chainId);
        console.log("\nNote: Verification is asynchronous. Check Etherscan for final status.");
        console.log("Contract path:", CONTRACT_NAME);
        console.log("==============================\n");
    }
}
