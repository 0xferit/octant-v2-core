// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { AllocationMechanismFactory } from "src/mechanisms/AllocationMechanismFactory.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BatchScript } from "../helpers/BatchScript.sol";

/**
 * @title DeployQuadraticVotingMechanism
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Deploy a QuadraticVotingMechanism via AllocationMechanismFactory
 * @dev Supports two modes:
 *
 *      SAFE MODE (production): Set SAFE_ADDRESS to deploy via Safe multisig.
 *      BROADCAST MODE (testing): Omit SAFE_ADDRESS for direct broadcast.
 *
 *      Required env vars:
 *        ALLOCATION_MECHANISM_FACTORY - Address of the deployed AllocationMechanismFactory
 *        ASSET_TOKEN                  - Address of the underlying ERC20 token
 *        QVM_NAME                     - Name for the mechanism's shares (ERC20 metadata)
 *        QVM_SYMBOL                   - Symbol for the mechanism's shares (ERC20 metadata)
 *
 *      Optional env vars (with defaults):
 *        VOTING_DELAY       - Delay before voting begins (default: 1 hour)
 *        VOTING_PERIOD      - Duration of voting (default: 7 days)
 *        QUORUM_SHARES      - Minimum voting power for quorum (default: 1 ether)
 *        TIMELOCK_DELAY     - Delay before redemptions begin (default: 1 day)
 *        GRACE_PERIOD       - Duration of redemption window (default: 7 days)
 *        ALPHA_NUMERATOR    - Quadratic alpha numerator (default: 50)
 *        ALPHA_DENOMINATOR  - Quadratic alpha denominator (default: 100)
 *
 *      Safe mode additional env vars:
 *        SAFE_ADDRESS  - Safe multisig address
 *        CHAIN         - Target chain (ethereum, sepolia, etc.)
 *        WALLET_TYPE   - Wallet type (local or ledger)
 *        PRIVATE_KEY   - Private key (for WALLET_TYPE=local)
 *        SENDER        - Address of the Safe owner/delegate
 *
 * Usage (broadcast mode):
 * ```bash
 * export ALLOCATION_MECHANISM_FACTORY=0x...
 * export ASSET_TOKEN=0x...
 * export QVM_NAME="Quadratic Voting Mechanism"
 * export QVM_SYMBOL="QVM"
 *
 * forge script script/deploy/DeployQuadraticVotingMechanism.s.sol \
 *   --rpc-url $ETH_RPC_URL \
 *   --broadcast \
 *   --private-key $PRIVATE_KEY
 * ```
 *
 * Usage (Safe mode):
 * ```bash
 * export SAFE_ADDRESS=0x...
 * export CHAIN=ethereum
 * export WALLET_TYPE=local
 * export PRIVATE_KEY=0x...
 * export SENDER=0x...
 * export ALLOCATION_MECHANISM_FACTORY=0x...
 * export ASSET_TOKEN=0x...
 * export QVM_NAME="Quadratic Voting Mechanism"
 * export QVM_SYMBOL="QVM"
 *
 * forge script script/deploy/DeployQuadraticVotingMechanism.s.sol \
 *   --rpc-url $ETH_RPC_URL \
 *   --ffi \
 *   --sender $SENDER
 * ```
 */
contract DeployQuadraticVotingMechanism is Script, BatchScript {
    error AlphaDenominatorZero();
    error AlphaNumeratorExceedsDenominator(uint256 numerator, uint256 denominator);
    error VotingPeriodTooShort(uint256 period);
    error VotingPeriodTooLong(uint256 period);
    error TimelockDelayTooLong(uint256 delay);
    error GracePeriodTooShort(uint256 period);

    AllocationMechanismFactory public factory;

    function run() public {
        factory = AllocationMechanismFactory(vm.envAddress("ALLOCATION_MECHANISM_FACTORY"));
        console.log("AllocationMechanismFactory:", address(factory));

        address safeAddress = vm.envOr("SAFE_ADDRESS", address(0));
        if (safeAddress != address(0)) {
            console.log("Using Safe:", safeAddress);
            _runSafe(safeAddress);
        } else {
            _runBroadcast();
        }
    }

    function _runSafe(address safe_) private isBatch(safe_) {
        (AllocationConfig memory config, uint256 alphaNumerator, uint256 alphaDenominator) = _loadConfig();
        _logConfig(config, alphaNumerator, alphaDenominator);

        bytes memory data = abi.encodeCall(
            AllocationMechanismFactory.deployQuadraticVotingMechanism,
            (config, alphaNumerator, alphaDenominator)
        );

        bytes memory result = executeTransaction(address(factory), 0, data, Operation.CALL, true);
        address deployedAddress = abi.decode(result, (address));
        console.log("QVM deployed at:", deployedAddress);
    }

    function _runBroadcast() private {
        (AllocationConfig memory config, uint256 alphaNumerator, uint256 alphaDenominator) = _loadConfig();
        _logConfig(config, alphaNumerator, alphaDenominator);

        vm.startBroadcast();
        address deployedAddress = factory.deployQuadraticVotingMechanism(config, alphaNumerator, alphaDenominator);
        vm.stopBroadcast();

        console.log("QVM deployed at:", deployedAddress);
    }

    function _loadConfig()
        internal
        view
        returns (AllocationConfig memory config, uint256 alphaNumerator, uint256 alphaDenominator)
    {
        // Required
        address assetToken = vm.envAddress("ASSET_TOKEN");
        string memory name = vm.envString("QVM_NAME");
        string memory symbol = vm.envString("QVM_SYMBOL");

        // Optional with defaults
        uint256 votingDelay = vm.envOr("VOTING_DELAY", uint256(1 hours));
        uint256 votingPeriod = vm.envOr("VOTING_PERIOD", uint256(7 days));
        uint256 quorumShares = vm.envOr("QUORUM_SHARES", uint256(1 ether));
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(1 days));
        uint256 gracePeriod = vm.envOr("GRACE_PERIOD", uint256(7 days));
        alphaNumerator = vm.envOr("ALPHA_NUMERATOR", uint256(50));
        alphaDenominator = vm.envOr("ALPHA_DENOMINATOR", uint256(100));

        // Validation
        if (alphaDenominator == 0) revert AlphaDenominatorZero();
        if (alphaNumerator > alphaDenominator) {
            revert AlphaNumeratorExceedsDenominator(alphaNumerator, alphaDenominator);
        }
        if (votingPeriod < 1 hours) revert VotingPeriodTooShort(votingPeriod);
        if (votingPeriod > 365 days) revert VotingPeriodTooLong(votingPeriod);
        if (timelockDelay > 30 days) revert TimelockDelayTooLong(timelockDelay);
        if (gracePeriod < 1 hours) revert GracePeriodTooShort(gracePeriod);

        config = AllocationConfig({
            asset: IERC20(assetToken),
            name: name,
            symbol: symbol,
            votingDelay: votingDelay,
            votingPeriod: votingPeriod,
            quorumShares: quorumShares,
            timelockDelay: timelockDelay,
            gracePeriod: gracePeriod,
            owner: address(0) // factory overrides with msg.sender
        });
    }

    function _logConfig(AllocationConfig memory config, uint256 alphaNumerator, uint256 alphaDenominator) private pure {
        console.log("=== QVM DEPLOYMENT ===");
        console.log("Asset token:", address(config.asset));
        console.log("Name:", config.name);
        console.log("Symbol:", config.symbol);
        console.log("Voting delay:", config.votingDelay);
        console.log("Voting period:", config.votingPeriod);
        console.log("Quorum shares:", config.quorumShares);
        console.log("Timelock delay:", config.timelockDelay);
        console.log("Grace period:", config.gracePeriod);
        console.log("Alpha numerator:", alphaNumerator);
        console.log("Alpha denominator:", alphaDenominator);
    }
}
