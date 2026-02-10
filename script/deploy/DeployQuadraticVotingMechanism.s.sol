// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script, console } from "forge-std/Script.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployQuadraticVotingMechanism is Script {
    AllocationMechanismFactory public factory;
    MockERC20 public mockToken;
    address public qvm;

    function deploy() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy factory
        factory = new AllocationMechanismFactory();

        // 2. Deploy mock ERC20 token (18 decimals)
        mockToken = new MockERC20(18);

        // 3. Deploy QuadraticVotingMechanism via factory
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(mockToken)),
            name: "Quadratic Voting Mechanism",
            symbol: "QVM",
            votingDelay: 1 hours,
            votingPeriod: 7 days,
            quorumShares: 1 ether,
            timelockDelay: 1 days,
            gracePeriod: 7 days,
            owner: address(0) // factory overrides with msg.sender
        });

        qvm = factory.deployQuadraticVotingMechanism(config, 50, 100);

        vm.stopBroadcast();

        console.log("Factory:", address(factory));
        console.log("MockToken:", address(mockToken));
        console.log("QVM:", qvm);
    }
}
