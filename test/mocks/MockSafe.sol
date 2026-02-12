// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Enum } from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

contract MockSafe {
    mapping(address => bool) public modules;

    function enableModule(address module) external {
        modules[module] = true;
    }

    function execTransactionViaDelegateCall(address target, bytes memory data) external returns (bool success) {
        // We wrap the call in assembly to have more control
        assembly {
            success := delegatecall(gas(), target, add(data, 0x20), mload(data), 0, 0)
        }

        // If the delegatecall failed, we need to forward the revert message
        if (!success) {
            assembly {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
        }

        return success;
    }

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation
    ) external returns (bool) {
        require(modules[msg.sender], "Not authorized");

        (bool success, ) = to.call{ value: value }(data);
        return success;
    }
}
