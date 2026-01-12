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
 * @notice Deployment script for AddressSetFactory
 * @dev Deploys AddressSetFactory deterministically by calling the CREATE2 factory.
 *
 * Usage:
 * ```bash
 * export SAFE_ADDRESS=0x...
 * export CHAIN=ethereum
 * export WALLET_TYPE=local # or ledger
 * export PRIVATE_KEY=0x... # required for WALLET_TYPE=local
 * export SENDER=0x... # must be a Safe owner or delegate
 * export ADDRESS_SET_FACTORY_SALT=OCTANT_ADDRESS_SET_FACTORY_V1_TEST
 *
 * forge script script/deploy/DeployAddressSetFactory.s.sol:DeployAddressSetFactory \
 *   --rpc-url $ETH_RPC_URL \
 *   --ffi \
 *   --sender $SENDER
 * ```
 *
 * Note: The --sender flag must be set to the address corresponding to PRIVATE_KEY.
 *       This address must be an owner or delegate of the Safe.
 */
contract DeployAddressSetFactory is Script, BatchScript {
    error AddressMismatch(address expected, address actual);
    error DeploymentFailed();

    /// @notice Default salt label for deterministic factory deployment
    string public constant DEFAULT_SALT_LABEL = "OCTANT_ADDRESS_SET_FACTORY_V1";
    bytes32 public constant DEPLOYMENT_SALT = keccak256("OCTANT_ADDRESS_SET_FACTORY_V1");

    /// @notice Deployed factory contract
    AddressSetFactory public factory;

    /// @notice Safe address used to submit the batch
    address public safe;

    function setUp() public {
        safe = _loadSafeAddress();

        console.log("Using Safe:", safe);
    }

    function run() external isBatch(safe) returns (address) {
        return _deploy();
    }

    function _deploy() internal returns (address) {
        console.log("=== ADDRESS SET FACTORY DEPLOYMENT ===");

        string memory saltLabel = vm.envOr("ADDRESS_SET_FACTORY_SALT", DEFAULT_SALT_LABEL);
        if (bytes(saltLabel).length == 0) {
            saltLabel = DEFAULT_SALT_LABEL;
        }
        bytes32 salt = keccak256(bytes(saltLabel));

        bytes memory creationCode = type(AddressSetFactory).creationCode;
        address expectedAddress = _computeCreate2AddressViaFactory(salt, creationCode);
        console.log("Expected factory address:", expectedAddress);
        console.log("Salt string:", saltLabel);
        console.logBytes32(salt);

        bytes memory deployData = abi.encodePacked(salt, creationCode);
        bytes memory result = executeTransaction(CREATE2_FACTORY, 0, deployData, Operation.CALL, true);
        address deployedAddress = _decodeCreate2DeployerResult(result);
        if (deployedAddress != expectedAddress) {
            revert AddressMismatch(expectedAddress, deployedAddress);
        }

        factory = AddressSetFactory(deployedAddress);

        console.log("AddressSetFactory deployed at:", deployedAddress);
        return deployedAddress;
    }
}
