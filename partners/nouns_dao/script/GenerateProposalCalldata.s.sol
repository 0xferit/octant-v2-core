// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import { Script, console } from "forge-std/Script.sol";

import { YieldForwarderFactory } from "src/factories/YieldForwarderFactory.sol";
import { LidoStrategyFactory } from "src/factories/LidoStrategyFactory.sol";

/// @notice Minimal interface for wstETH conversion functions
interface IWstETH {
    /// @notice Get amount of wstETH for a given amount of stETH
    /// @param _stETHAmount Amount of stETH (≈ ETH value)
    /// @return Amount of wstETH
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    /// @notice Get amount of stETH for a given amount of wstETH
    /// @param _wstETHAmount Amount of wstETH
    /// @return Amount of stETH (≈ ETH value)
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
}

/**
 * @title GenerateProposalCalldata
 * @notice Generates calldata for Nouns DAO proposal to deploy Lido yield strategy
 * @dev Run with: forge script partners/nouns_dao/script/GenerateProposalCalldata.s.sol --fork-url $ETH_RPC_URL -vvvv
 *
 *      This script outputs ready-to-use data for the Nouns DAO UI (nouns.wtf/vote):
 *      - Transaction 1: Deploy YieldForwarder via Factory
 *      - Transaction 2: Deploy LidoStrategy via Factory
 *      - Transaction 3: Approve wstETH to Strategy
 *      - Transaction 4: Deposit wstETH into Strategy
 *
 *      OUTPUT FORMAT:
 *      The script outputs each transaction with:
 *      - Target: Contract address to call
 *      - Value: ETH to send (always 0)
 *      - Function: Human-readable signature for Nouns UI
 *      - Calldata: ABI-encoded parameters (WITHOUT selector) for Nouns UI
 *
 *      PREREQUISITES:
 *      - LidoStrategyFactory must be deployed to mainnet (update LIDO_STRATEGY_FACTORY)
 *      - YieldForwarderFactory must be deployed to mainnet (update YIELD_FORWARDER_FACTORY)
 *      - Update all placeholder addresses before production use
 */
contract GenerateProposalCalldata is Script {
    // ══════════════════════════════════════════════════════════════════════════════
    // CONFIGURATION - UPDATE THESE VALUES BEFORE GENERATING PROPOSAL
    // ══════════════════════════════════════════════════════════════════════════════

    /// @notice Nouns DAO Treasury (Executor/Timelock) - DO NOT CHANGE
    address constant NOUNS_TREASURY = 0xb1a32FC9F9D8b2cf86C068Cae13108809547ef71;

    /// @notice YieldForwarder Factory address
    /// @dev Placeholder - update when deployed to mainnet
    address constant YIELD_FORWARDER_FACTORY = 0x5711765E0756B45224fc1FdA1B41ab344682bBcb;

    /// @notice wstETH token address on Ethereum mainnet - DO NOT CHANGE
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    // ═══════════════════════════════════════════════════════════════════════════════
    // PRODUCTION ADDRESSES - DEPLOYED TO MAINNET
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Tokenized Strategy implementation (YieldSkimmingTokenizedStrategy) - PRODUCTION
    address constant TOKENIZED_STRATEGY = 0xae2d523179CF2eA3a0750B2015c38c57aB94f77E;

    /// @notice LidoStrategyFactory address - PRODUCTION
    address constant LIDO_STRATEGY_FACTORY = 0xB248Df1fc187Fdb6C89bDc30071e68D235DeC3c2;

    /// @notice Nouns Payer contract address (receives forwarded wstETH yield)
    /// @dev Placeholder - update with actual Nouns Payer contract address
    address constant NOUNS_PAYER = 0x0eCC079C20DaA9fDE0e26b6d745c0b38479ff200;

    /// @notice Keeper bot address for calling report()
    /// @dev For testing: using deployer address. Update for production.
    /// @dev CRITICAL: Do NOT use Treasury - would require governance vote for each harvest
    address constant KEEPER_BOT = 0x0eCC079C20DaA9fDE0e26b6d745c0b38479ff200;

    /// @notice Emergency admin address
    /// @dev For testing: using deployer address. Update for production.
    address constant EMERGENCY_ADMIN = 0x0eCC079C20DaA9fDE0e26b6d745c0b38479ff200;

    /// @notice Strategy name (appears in token metadata)
    string constant STRATEGY_NAME = "NounsLidoStrategy";

    /// @notice Strategy symbol (share token symbol)
    string constant STRATEGY_SYMBOL = "ysNounsLido";

    /// @notice Target ETH value to deposit (will be converted to wstETH at current rate)
    /// @dev 1000 ETH = 1000e18 = 1000000000000000000000
    /// @dev The actual wstETH amount deposited depends on the stETH/wstETH exchange rate at execution time
    uint256 constant TARGET_ETH_VALUE = 1000 ether;

    /// @notice Salt for deterministic YieldForwarder deployment
    /// @dev Using an explicit salt avoids race conditions where the deployment count
    ///      could change between proposal creation and execution
    bytes32 constant YIELD_FORWARDER_SALT = keccak256("NounsDAO-LidoStrategy-YieldForwarder-v1");

    // ══════════════════════════════════════════════════════════════════════════════
    // MAIN SCRIPT
    // ══════════════════════════════════════════════════════════════════════════════

    function run() public {
        // No-op storage write to prevent "can be view" warning (forge scripts don't support view entry points)
        assembly {
            sstore(0, 0)
        }

        _printHeader();

        // Precompute deterministic addresses
        (address predictedYF, address predictedStrategy) = getPrecomputedAddresses();

        _printConfiguration();
        _printPrecomputedAddresses(predictedYF, predictedStrategy);

        // Generate and print all 4 transactions
        _printTransaction1_DeployYieldForwarder();
        _printTransaction2_DeployStrategy(predictedYF);
        _printTransaction3_ApproveWstETH(predictedStrategy);
        _printTransaction4_DepositWstETH(predictedStrategy);

        // Print summary for Nouns DAO UI
        _printNounsUISummary(predictedStrategy);

        _printFooter();
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // PUBLIC GETTERS - Used by tests to extract proposal data
    // ══════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get precomputed CREATE2 addresses for YieldForwarder and Strategy
     * @return predictedYieldForwarder The deterministic address where YieldForwarder will deploy
     * @return predictedStrategy The deterministic address where LidoStrategy will deploy
     */
    function getPrecomputedAddresses()
        public
        view
        returns (address predictedYieldForwarder, address predictedStrategy)
    {
        return _computeAddresses();
    }

    /**
     * @notice Get the complete proposal data for Nouns DAO governance
     * @dev Returns all 4 transactions in the format expected by NounsDAOProxy.propose()
     * @return targets Array of contract addresses to call
     * @return values Array of ETH values to send (all 0)
     * @return signatures Array of function signatures
     * @return calldatas Array of ABI-encoded parameters (without selector)
     */
    function getProposalTransactions()
        public
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        (address predictedYF, address predictedStrategy) = _computeAddresses();

        targets = new address[](4);
        values = new uint256[](4);
        signatures = new string[](4);
        calldatas = new bytes[](4);

        // TX 1: Deploy YieldForwarder
        (targets[0], values[0], signatures[0], calldatas[0]) = _getTransaction1_DeployYieldForwarder();

        // TX 2: Deploy LidoStrategy
        (targets[1], values[1], signatures[1], calldatas[1]) = _getTransaction2_DeployStrategy(predictedYF);

        // TX 3: Approve wstETH to Strategy
        (targets[2], values[2], signatures[2], calldatas[2]) = _getTransaction3_ApproveWstETH(predictedStrategy);

        // TX 4: Deposit wstETH into Strategy
        (targets[3], values[3], signatures[3], calldatas[3]) = _getTransaction4_DepositWstETH(predictedStrategy);
    }

    /**
     * @notice Get the target ETH value to deposit
     * @return The target ETH value (before conversion to wstETH)
     */
    function getTargetEthValue() public pure returns (uint256) {
        return TARGET_ETH_VALUE;
    }

    /**
     * @notice Get the wstETH deposit amount by converting TARGET_ETH_VALUE at current exchange rate
     * @dev Calls wstETH contract to convert stETH amount (≈ ETH) to wstETH
     *      Since stETH ≈ ETH (1:1 peg), TARGET_ETH_VALUE in stETH ≈ TARGET_ETH_VALUE in ETH
     * @return The wstETH deposit amount at current exchange rate
     */
    function getDepositAmount() public view returns (uint256) {
        return IWstETH(WSTETH).getWstETHByStETH(TARGET_ETH_VALUE);
    }

    /**
     * @notice Get the Nouns Treasury address
     * @return The Nouns DAO Executor/Timelock address
     */
    function getNounsTreasury() public pure returns (address) {
        return NOUNS_TREASURY;
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ══════════════════════════════════════════════════════════════════════════════

    function _computeAddresses() internal view returns (address predictedYF, address predictedStrategy) {
        // Predict YieldForwarder address with explicit salt (avoids race conditions in governance)
        predictedYF = YieldForwarderFactory(YIELD_FORWARDER_FACTORY).computeYieldForwarderAddress(
            NOUNS_PAYER,
            YIELD_FORWARDER_SALT,
            NOUNS_TREASURY
        );

        // Predict Strategy address using LidoStrategyFactory.computeStrategyAddress()
        predictedStrategy = LidoStrategyFactory(LIDO_STRATEGY_FACTORY).computeStrategyAddress(
            WSTETH, // _vault
            WSTETH, // _asset
            STRATEGY_NAME,
            STRATEGY_SYMBOL,
            NOUNS_TREASURY, // _management
            KEEPER_BOT, // _keeper
            EMERGENCY_ADMIN, // _emergencyAdmin
            predictedYF, // _donationAddress
            false, // _enableBurning
            TOKENIZED_STRATEGY, // _tokenizedStrategyAddress
            NOUNS_TREASURY // _deployer (Treasury will deploy via governance)
        );
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // TRANSACTION DATA GENERATORS - Single source of truth for all transaction data
    // ══════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get TX 1 data: Deploy YieldForwarder
     * @return target Contract address to call
     * @return value ETH value (0)
     * @return signature Function signature
     * @return calldataParams ABI-encoded parameters
     */
    function _getTransaction1_DeployYieldForwarder()
        internal
        pure
        returns (address target, uint256 value, string memory signature, bytes memory calldataParams)
    {
        target = YIELD_FORWARDER_FACTORY;
        value = 0;
        signature = "createYieldForwarder(address,bytes32)";
        calldataParams = abi.encode(NOUNS_PAYER, YIELD_FORWARDER_SALT);
    }

    /**
     * @notice Get TX 2 data: Deploy LidoStrategy
     * @param yieldForwarder The predicted YieldForwarder address
     * @return target Contract address to call
     * @return value ETH value (0)
     * @return signature Function signature
     * @return calldataParams ABI-encoded parameters
     */
    function _getTransaction2_DeployStrategy(
        address yieldForwarder
    ) internal pure returns (address target, uint256 value, string memory signature, bytes memory calldataParams) {
        target = LIDO_STRATEGY_FACTORY;
        value = 0;
        signature = "createStrategy(string,string,address,address,address,address,bool,address)";
        calldataParams = abi.encode(
            STRATEGY_NAME,
            STRATEGY_SYMBOL,
            NOUNS_TREASURY,
            KEEPER_BOT,
            EMERGENCY_ADMIN,
            yieldForwarder,
            false,
            TOKENIZED_STRATEGY
        );
    }

    /**
     * @notice Get TX 3 data: Approve wstETH to Strategy
     * @param strategy The predicted Strategy address
     * @return target Contract address to call
     * @return value ETH value (0)
     * @return signature Function signature
     * @return calldataParams ABI-encoded parameters
     */
    function _getTransaction3_ApproveWstETH(
        address strategy
    ) internal view returns (address target, uint256 value, string memory signature, bytes memory calldataParams) {
        target = WSTETH;
        value = 0;
        signature = "approve(address,uint256)";
        calldataParams = abi.encode(strategy, getDepositAmount());
    }

    /**
     * @notice Get TX 4 data: Deposit wstETH into Strategy
     * @param strategy The predicted Strategy address
     * @return target Contract address to call
     * @return value ETH value (0)
     * @return signature Function signature
     * @return calldataParams ABI-encoded parameters
     */
    function _getTransaction4_DepositWstETH(
        address strategy
    ) internal view returns (address target, uint256 value, string memory signature, bytes memory calldataParams) {
        target = strategy;
        value = 0;
        signature = "deposit(uint256,address)";
        calldataParams = abi.encode(getDepositAmount(), NOUNS_TREASURY);
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // TRANSACTION PRINTERS - Use _getTransaction* for data, then print
    // ══════════════════════════════════════════════════════════════════════════════

    function _printTransaction1_DeployYieldForwarder() internal pure {
        (
            address target,
            ,
            string memory signature,
            bytes memory calldataParams
        ) = _getTransaction1_DeployYieldForwarder();

        console.log("");
        console.log("================================================================================");
        console.log("TRANSACTION 1: Deploy YieldForwarder");
        console.log("================================================================================");
        console.log("");
        console.log("TARGET (copy this):");
        console.log("  ", target);
        console.log("");
        console.log("VALUE:");
        console.log("  0");
        console.log("");
        console.log("FUNCTION (copy this):");
        console.log("  ", signature);
        console.log("");
        console.log("PARAMETERS:");
        console.log("  receiver: ", NOUNS_PAYER);
        console.log("  salt:     ");
        console.logBytes32(YIELD_FORWARDER_SALT);
        console.log("");
        console.log("CALLDATA (copy this - parameters only, no selector):");
        console.logBytes(calldataParams);
    }

    function _printTransaction2_DeployStrategy(address yieldForwarder) internal pure {
        (address target, , string memory signature, bytes memory calldataParams) = _getTransaction2_DeployStrategy(
            yieldForwarder
        );

        console.log("");
        console.log("================================================================================");
        console.log("TRANSACTION 2: Deploy LidoStrategy");
        console.log("================================================================================");
        console.log("");
        console.log("TARGET (copy this):");
        console.log("  ", target);
        console.log("");
        console.log("VALUE:");
        console.log("  0");
        console.log("");
        console.log("FUNCTION (copy this):");
        console.log("  ", signature);
        console.log("");
        console.log("PARAMETERS:");
        console.log("  _name:                     %s", STRATEGY_NAME);
        console.log("  _symbol:                   %s", STRATEGY_SYMBOL);
        console.log("  _management:               ", NOUNS_TREASURY);
        console.log("  _keeper:                   ", KEEPER_BOT);
        console.log("  _emergencyAdmin:           ", EMERGENCY_ADMIN);
        console.log("  _donationAddress:          ", yieldForwarder);
        console.log("  _enableBurning:            false");
        console.log("  _tokenizedStrategyAddress: ", TOKENIZED_STRATEGY);
        console.log("");
        console.log("CALLDATA (copy this - parameters only, no selector):");
        console.logBytes(calldataParams);
    }

    function _printTransaction3_ApproveWstETH(address strategy) internal view {
        (address target, , string memory signature, bytes memory calldataParams) = _getTransaction3_ApproveWstETH(
            strategy
        );
        uint256 depositAmount = getDepositAmount();

        console.log("");
        console.log("================================================================================");
        console.log("TRANSACTION 3: Approve wstETH to Strategy");
        console.log("================================================================================");
        console.log("");
        console.log("TARGET (copy this):");
        console.log("  ", target);
        console.log("");
        console.log("VALUE:");
        console.log("  0");
        console.log("");
        console.log("FUNCTION (copy this):");
        console.log("  ", signature);
        console.log("");
        console.log("PARAMETERS:");
        console.log("  spender: ", strategy);
        console.log("  amount:  %s wstETH (= %s ETH value)", depositAmount / 1e18, TARGET_ETH_VALUE / 1e18);
        console.log("");
        console.log("CALLDATA (copy this - parameters only, no selector):");
        console.logBytes(calldataParams);
    }

    function _printTransaction4_DepositWstETH(address strategy) internal view {
        (address target, , string memory signature, bytes memory calldataParams) = _getTransaction4_DepositWstETH(
            strategy
        );
        uint256 depositAmount = getDepositAmount();

        console.log("");
        console.log("================================================================================");
        console.log("TRANSACTION 4: Deposit wstETH into Strategy");
        console.log("================================================================================");
        console.log("");
        console.log("TARGET (copy this):");
        console.log("  ", target);
        console.log("");
        console.log("VALUE:");
        console.log("  0");
        console.log("");
        console.log("FUNCTION (copy this):");
        console.log("  ", signature);
        console.log("");
        console.log("PARAMETERS:");
        console.log("  assets:   %s wstETH (= %s ETH value)", depositAmount / 1e18, TARGET_ETH_VALUE / 1e18);
        console.log("  receiver: ", NOUNS_TREASURY);
        console.log("");
        console.log("CALLDATA (copy this - parameters only, no selector):");
        console.logBytes(calldataParams);
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // SUMMARY OUTPUT
    // ══════════════════════════════════════════════════════════════════════════════

    function _printNounsUISummary(address predictedStrategy) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("NOUNS DAO UI SUMMARY - COPY/PASTE READY");
        console.log("================================================================================");
        console.log("");
        console.log("Add these 4 transactions in order on nouns.wtf/vote:");
        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("TX 1 - Deploy YieldForwarder");
        console.log("--------------------------------------------------------------------------------");
        console.log("Target:   ", YIELD_FORWARDER_FACTORY);
        console.log("Function: createYieldForwarder(address,bytes32)");
        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("TX 2 - Deploy LidoStrategy");
        console.log("--------------------------------------------------------------------------------");
        console.log("Target:   ", LIDO_STRATEGY_FACTORY);
        console.log("Function: createStrategy(string,string,address,address,address,address,bool,address)");
        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("TX 3 - Approve wstETH");
        console.log("--------------------------------------------------------------------------------");
        console.log("Target:   ", WSTETH);
        console.log("Function: approve(address,uint256)");
        console.log("");
        console.log("--------------------------------------------------------------------------------");
        console.log("TX 4 - Deposit wstETH");
        console.log("--------------------------------------------------------------------------------");
        console.log("Target:   ", predictedStrategy);
        console.log("Function: deposit(uint256,address)");
        console.log("");
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // PRINT HELPERS
    // ══════════════════════════════════════════════════════════════════════════════

    function _printHeader() internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("    NOUNS DAO PROPOSAL CALLDATA GENERATOR");
        console.log("    Octant v2 - Lido Yield Skimming Strategy");
        console.log("================================================================================");
        console.log("");
    }

    function _printConfiguration() internal view {
        uint256 depositAmount = getDepositAmount();
        console.log("CONFIGURATION:");
        console.log("--------------------------------------------------------------------------------");
        console.log("  Treasury (Management):      ", NOUNS_TREASURY);
        console.log("  YieldForwarder Factory:     ", YIELD_FORWARDER_FACTORY);
        console.log("  LidoStrategy Factory:       ", LIDO_STRATEGY_FACTORY);
        console.log("  Nouns Payer:                ", NOUNS_PAYER);
        console.log("  Keeper Bot:                 ", KEEPER_BOT);
        console.log("  Emergency Admin:            ", EMERGENCY_ADMIN);
        console.log("  wstETH Token:               ", WSTETH);
        console.log("  Tokenized Strategy Impl:    ", TOKENIZED_STRATEGY);
        console.log("  Strategy Name:               %s", STRATEGY_NAME);
        console.log("  Strategy Symbol:             %s", STRATEGY_SYMBOL);
        console.log("  Target ETH Value:            %s ETH", TARGET_ETH_VALUE / 1e18);
        console.log("  Deposit Amount:              %s wstETH (at current rate)", depositAmount / 1e18);
        console.log("");
    }

    function _printPrecomputedAddresses(address predictedYF, address predictedStrategy) internal pure {
        console.log("PRECOMPUTED ADDRESSES (via CREATE2):");
        console.log("--------------------------------------------------------------------------------");
        console.log("  YieldForwarder: ", predictedYF);
        console.log("  Strategy:       ", predictedStrategy);
        console.log("");
        console.log("NOTE: These addresses are deterministic. The contracts will deploy to these");
        console.log("exact addresses when the proposal executes.");
    }

    function _printFooter() internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("NEXT STEPS:");
        console.log("================================================================================");
        console.log("");
        console.log("1. Update placeholder addresses in this script:");
        console.log("   - YIELD_FORWARDER_FACTORY: Deploy YieldForwarderFactory to mainnet");
        console.log("   - NOUNS_PAYER:             Get actual Nouns Payer contract address");
        console.log("   - KEEPER_BOT:              Set up dedicated keeper EOA/bot");
        console.log("   - EMERGENCY_ADMIN:         Decide on emergency admin (Treasury or multisig)");
        console.log("");
        console.log("2. Re-run this script to generate production calldata");
        console.log("");
        console.log("3. Go to nouns.wtf/vote and create a new proposal");
        console.log("   - Add all 4 transactions in order");
        console.log("   - Copy the TARGET, FUNCTION, and CALLDATA for each transaction");
        console.log("");
        console.log("4. Use the proposal template from partners/nouns_dao/README.md");
        console.log("");
        console.log("================================================================================");
        console.log("");
    }
}
