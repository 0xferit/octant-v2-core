// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import { BatchScript } from "../helpers/BatchScript.sol";

// Strategy implementations
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

// Factory contracts
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";
import { LidoStrategyFactory } from "src/factories/LidoStrategyFactory.sol";
import { MorphoCompounderStrategyFactory } from "src/factories/MorphoCompounderStrategyFactory.sol";
import { SkyCompounderStrategyFactory } from "src/factories/SkyCompounderStrategyFactory.sol";
import { YearnV3StrategyFactory } from "src/factories/yieldDonating/YearnV3StrategyFactory.sol";
import { AaveV3StrategyFactory } from "src/factories/AaveV3StrategyFactory.sol";
import { SparkStrategyFactory } from "src/factories/SparkStrategyFactory.sol";

/**
 * @title DeployNewStrategiesAndFactories
 * @author Golem Foundation
 * @notice Deploys new tokenized strategies, PaymentSplitterFactory, and all strategy factories via Safe multisig
 * @dev Due to the EIP-7825 per-transaction gas limit of 16,777,216 gas (2^24), all 9 contracts
 *      cannot be deployed in a single transaction (~21.8M gas total). The deployment is split
 *      into two Safe MultiSend batches:
 *
 *      Batch 1 (~12.4M gas): Implementations + PaymentSplitter + YieldSkimming factories
 *        - YieldSkimmingTokenizedStrategy
 *        - YieldDonatingTokenizedStrategy
 *        - PaymentSplitterFactory
 *        - LidoStrategyFactory
 *        - MorphoCompounderStrategyFactory
 *
 *      Batch 2 (~9.4M gas): Remaining YieldDonating factories
 *        - SkyCompounderStrategyFactory
 *        - YearnV3StrategyFactory
 *        - AaveV3StrategyFactory
 *        - SparkStrategyFactory
 *
 * Usage:
 * ```bash
 * export SAFE_ADDRESS=0x...
 * export CHAIN=mainnet
 * export WALLET_TYPE=local  # or ledger
 * export PRIVATE_KEY=0x...  # required for WALLET_TYPE=local
 * export SENDER=0x...       # must be a Safe owner or delegate
 * export ETH_RPC_URL=https://...
 *
 * # Deploy ALL (both batches, two Safe proposals in sequence)
 * forge script script/deploy/DeployNewStrategiesAndFactories.s.sol \
 *   --rpc-url $ETH_RPC_URL --ffi --sender $SENDER
 *
 * # Or deploy each batch individually:
 * forge script script/deploy/DeployNewStrategiesAndFactories.s.sol \
 *   --sig "runBatch1()" --rpc-url $ETH_RPC_URL --ffi --sender $SENDER
 *
 * forge script script/deploy/DeployNewStrategiesAndFactories.s.sol \
 *   --sig "runBatch2()" --rpc-url $ETH_RPC_URL --ffi --sender $SENDER
 * ```
 */
contract DeployNewStrategiesAndFactories is Script, BatchScript {
    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYMENT SALTS (date-based: DDMMYYYY format)
    // ═══════════════════════════════════════════════════════════════════════

    // Strategy implementation salts
    bytes32 public constant YIELD_SKIMMING_SALT = keccak256("OCTANT_YIELD_SKIMMING_STRATEGY_10022026");
    bytes32 public constant YIELD_DONATING_SALT = keccak256("OCTANT_YIELD_DONATING_STRATEGY_10022026");

    // Factory deployment salts
    bytes32 public constant PAYMENT_SPLITTER_FACTORY_SALT = keccak256("PAYMENT_SPLITTER_FACTORY_10022026");
    bytes32 public constant LIDO_FACTORY_SALT = keccak256("LIDO_STRATEGY_FACTORY_10022026");
    bytes32 public constant MORPHO_FACTORY_SALT = keccak256("MORPHO_COMPOUNDER_FACTORY_10022026");
    bytes32 public constant SKY_FACTORY_SALT = keccak256("SKY_COMPOUNDER_FACTORY_10022026");
    bytes32 public constant YEARN_V3_FACTORY_SALT = keccak256("YEARN_V3_STRATEGY_FACTORY_10022026");
    bytes32 public constant AAVE_V3_FACTORY_SALT = keccak256("AAVE_V3_STRATEGY_FACTORY_10022026");
    bytes32 public constant SPARK_FACTORY_SALT = keccak256("SPARK_STRATEGY_FACTORY_10022026");

    // ═══════════════════════════════════════════════════════════════════════
    // DEPLOYED ADDRESSES (computed, logged after deployment)
    // ═══════════════════════════════════════════════════════════════════════

    // Batch 1
    address public yieldSkimmingStrategy;
    address public yieldDonatingStrategy;
    address public paymentSplitterFactory;
    address public lidoFactory;
    address public morphoFactory;

    // Batch 2
    address public skyFactory;
    address public yearnV3Factory;
    address public aaveV3Factory;
    address public sparkFactory;
    address public safe;

    function setUp() public {
        safe = _loadSafeAddress();
        console.log("Using Safe:", safe);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RUN ALL: Proposes both batches as two Safe transactions (nonce N, N+1)
    // ═══════════════════════════════════════════════════════════════════════

    function run() public isBatch(safe) {
        // --- Batch 1 ---
        _calculateBatch1Addresses();
        _addBatch1Deployments();
        executeBatch(true);
        _logBatch1Summary();

        // Clear the transaction queue for batch 2
        delete encodedTxns;

        // --- Batch 2 ---
        _calculateBatch2Addresses();
        _addBatch2Deployments();
        executeBatch(true);
        _logBatch2Summary();

        _logFullSummary();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BATCH 1: Implementations + PaymentSplitter + YieldSkimming factories
    // Estimated gas: ~12.4M (under 16.78M EIP-7825 limit)
    // ═══════════════════════════════════════════════════════════════════════

    function runBatch1() external isBatch(safe) {
        _calculateBatch1Addresses();
        _addBatch1Deployments();
        executeBatch(true);
        _logBatch1Summary();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BATCH 2: Remaining YieldDonating factories
    // Estimated gas: ~11.3M (under 16.78M EIP-7825 limit)
    // ═══════════════════════════════════════════════════════════════════════

    function runBatch2() external isBatch(safe) {
        _calculateBatch2Addresses();
        _addBatch2Deployments();
        executeBatch(true);
        _logBatch2Summary();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADDRESS PRECOMPUTATION
    // ═══════════════════════════════════════════════════════════════════════

    function _calculateBatch1Addresses() internal {
        yieldSkimmingStrategy = _computeCreate2AddressViaFactory(
            YIELD_SKIMMING_SALT,
            keccak256(type(YieldSkimmingTokenizedStrategy).creationCode)
        );
        yieldDonatingStrategy = _computeCreate2AddressViaFactory(
            YIELD_DONATING_SALT,
            keccak256(type(YieldDonatingTokenizedStrategy).creationCode)
        );
        paymentSplitterFactory = _computeCreate2AddressViaFactory(
            PAYMENT_SPLITTER_FACTORY_SALT,
            keccak256(type(PaymentSplitterFactory).creationCode)
        );
        lidoFactory = _computeCreate2AddressViaFactory(
            LIDO_FACTORY_SALT,
            keccak256(type(LidoStrategyFactory).creationCode)
        );
        morphoFactory = _computeCreate2AddressViaFactory(
            MORPHO_FACTORY_SALT,
            keccak256(type(MorphoCompounderStrategyFactory).creationCode)
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BATCH DEPLOYMENT LOGIC
    // ═══════════════════════════════════════════════════════════════════════

    function _addBatch1Deployments() internal {
        console.log("\n=== BATCH 1: Implementations + YieldSkimming Factories ===\n");

        _addCreate2Deployment(YIELD_SKIMMING_SALT, type(YieldSkimmingTokenizedStrategy).creationCode);
        console.log("- YieldSkimmingTokenizedStrategy:", yieldSkimmingStrategy);

        _addCreate2Deployment(YIELD_DONATING_SALT, type(YieldDonatingTokenizedStrategy).creationCode);
        console.log("- YieldDonatingTokenizedStrategy:", yieldDonatingStrategy);

        _addCreate2Deployment(PAYMENT_SPLITTER_FACTORY_SALT, type(PaymentSplitterFactory).creationCode);
        console.log("- PaymentSplitterFactory:", paymentSplitterFactory);

        _addCreate2Deployment(LIDO_FACTORY_SALT, type(LidoStrategyFactory).creationCode);
        console.log("- LidoStrategyFactory:", lidoFactory);

        _addCreate2Deployment(MORPHO_FACTORY_SALT, type(MorphoCompounderStrategyFactory).creationCode);
        console.log("- MorphoCompounderStrategyFactory:", morphoFactory);
    }

    function _addBatch2Deployments() internal {
        console.log("\n=== BATCH 2: YieldDonating Factories ===\n");

        _addCreate2Deployment(SKY_FACTORY_SALT, type(SkyCompounderStrategyFactory).creationCode);
        console.log("- SkyCompounderStrategyFactory:", skyFactory);

        _addCreate2Deployment(YEARN_V3_FACTORY_SALT, type(YearnV3StrategyFactory).creationCode);
        console.log("- YearnV3StrategyFactory:", yearnV3Factory);

        _addCreate2Deployment(AAVE_V3_FACTORY_SALT, type(AaveV3StrategyFactory).creationCode);
        console.log("- AaveV3StrategyFactory:", aaveV3Factory);

        _addCreate2Deployment(SPARK_FACTORY_SALT, type(SparkStrategyFactory).creationCode);
        console.log("- SparkStrategyFactory:", sparkFactory);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // LOGGING
    // ═══════════════════════════════════════════════════════════════════════

    function _logBatch1Summary() internal view {
        console.log("\n=== BATCH 1 SUMMARY ===");
        console.log("Safe Address:", safe);
        console.log("Contracts: 5 (nonce N)");
        console.log("  YieldSkimmingTokenizedStrategy:", yieldSkimmingStrategy);
        console.log("  YieldDonatingTokenizedStrategy:", yieldDonatingStrategy);
        console.log("  PaymentSplitterFactory:", paymentSplitterFactory);
        console.log("  LidoStrategyFactory:", lidoFactory);
        console.log("  MorphoCompounderStrategyFactory:", morphoFactory);
        console.log("Transaction sent to Safe for signing.\n");
    }

    function _logBatch2Summary() internal view {
        console.log("\n=== BATCH 2 SUMMARY ===");
        console.log("Safe Address:", safe);
        console.log("Contracts: 4 (nonce N+1)");
        console.log("  SkyCompounderStrategyFactory:", skyFactory);
        console.log("  YearnV3StrategyFactory:", yearnV3Factory);
        console.log("  AaveV3StrategyFactory:", aaveV3Factory);
        console.log("  SparkStrategyFactory:", sparkFactory);
        console.log("Transaction sent to Safe for signing.\n");
    }

    function _logFullSummary() internal pure {
        console.log("=== FULL DEPLOYMENT SUMMARY ===");
        console.log("Total contracts: 9 across 2 Safe transactions");
        console.log("Both transactions proposed to Safe for signing.");
        console.log("Execute batch 1 first, then batch 2.");
        console.log("================================\n");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADDRESS PRECOMPUTATION
    // ═══════════════════════════════════════════════════════════════════════

    function _calculateBatch2Addresses() internal {
        skyFactory = _computeCreate2AddressViaFactory(
            SKY_FACTORY_SALT,
            keccak256(type(SkyCompounderStrategyFactory).creationCode)
        );
        yearnV3Factory = _computeCreate2AddressViaFactory(
            YEARN_V3_FACTORY_SALT,
            keccak256(type(YearnV3StrategyFactory).creationCode)
        );
        aaveV3Factory = _computeCreate2AddressViaFactory(
            AAVE_V3_FACTORY_SALT,
            keccak256(type(AaveV3StrategyFactory).creationCode)
        );
        sparkFactory = _computeCreate2AddressViaFactory(
            SPARK_FACTORY_SALT,
            keccak256(type(SparkStrategyFactory).creationCode)
        );
    }
}
