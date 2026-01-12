// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";

/**
 * @title DeployAddressSetFactory
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Deployment script for AddressSetFactory
 * @dev Deploys AddressSetFactory deterministically by calling the CREATE2 factory.
 *
 * Usage:
 * ```bash
 * forge script script/deploy/DeployAddressSetFactory.s.sol:DeployAddressSetFactory \
 *   --rpc-url $ETH_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify
 * ```
 */
contract DeployAddressSetFactory is Script {
    error DeploymentFailed();

    /// @notice Salt for deterministic factory deployment
    bytes32 public constant DEPLOYMENT_SALT = keccak256("OCTANT_ADDRESS_SET_FACTORY_V1");

    /// @notice Deployed factory contract
    AddressSetFactory public factory;

    function run() external returns (address) {
        return deploy();
    }

    function deploy() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== ADDRESS SET FACTORY DEPLOYMENT ===");
        console.log("Deployer:", deployer);

        bytes memory creationCode = type(AddressSetFactory).creationCode;
        address expectedAddress = _computeCreate2Address(CREATE2_FACTORY, DEPLOYMENT_SALT, keccak256(creationCode));
        console.log("Expected factory address:", expectedAddress);

        vm.startBroadcast(deployerPrivateKey);
        bytes memory deployData = abi.encodePacked(DEPLOYMENT_SALT, creationCode);
        (bool success, ) = CREATE2_FACTORY.call(deployData);
        if (!success) {
            revert DeploymentFailed();
        }
        vm.stopBroadcast();

        factory = AddressSetFactory(expectedAddress);

        if (expectedAddress.code.length == 0) {
            revert DeploymentFailed();
        }

        console.log("AddressSetFactory deployed at:", address(factory));
        return address(factory);
    }

    /// @notice Compute expected CREATE2 address
    function _computeCreate2Address(
        address factoryAddr,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", factoryAddr, salt, initCodeHash)))));
    }
}
