// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ─── Forge ──────────────────────────────────────────────────────────────────
import { Script, console } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";

// ─── Safe batching ──────────────────────────────────────────────────────────
import { BatchScript } from "../helpers/BatchScript.sol";

// ─── Phase A: Strategy implementations ──────────────────────────────────────
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

// ─── Phase A: Factory contracts ─────────────────────────────────────────────
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";
import { LidoStrategyFactory } from "src/factories/LidoStrategyFactory.sol";
import { MorphoCompounderStrategyFactory } from "src/factories/MorphoCompounderStrategyFactory.sol";
import { SkyCompounderStrategyFactory } from "src/factories/SkyCompounderStrategyFactory.sol";
import { YearnV3StrategyFactory } from "src/factories/yieldDonating/YearnV3StrategyFactory.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";
import { RegenEarningPowerCalculatorFactory } from "src/factories/RegenEarningPowerCalculatorFactory.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";

// ─── Phase B: Instance contracts ────────────────────────────────────────────
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { AccessMode } from "src/constants.sol";

// ─── OZ imports (verification test) ─────────────────────────────────────────
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ─── Type imports (staker-compatible for CreateStakerParams) ────────────────
import { Staker, IERC20 } from "staker/Staker.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";

// ─── Pinned bytecodes (reproducible deployment) ─────────────────────────────
import { REGEN_STAKER_V1_CREATION_CODE, REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE } from "./RegenStakerBytecodes.sol";

// ═════════════════════════════════════════════════════════════════════════════
//
//  FILE-LEVEL CONSTANTS -- shared by DeployProtocol and VerifyProtocolDeployment
//
// ═════════════════════════════════════════════════════════════════════════════

// --- Gnosis Safe & Tokens ---
address constant SAFE = 0x4B55fA101Dfa399af2FCDa83bB9e77bCa0009418;
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant GLM = 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429;

// --- Phase A: CREATE2 Deployment Salts (date-based: DDMMYYYY) ---
bytes32 constant YIELD_SKIMMING_SALT = keccak256("OCTANT_YIELD_SKIMMING_STRATEGY_16022026");
bytes32 constant YIELD_DONATING_SALT = keccak256("OCTANT_YIELD_DONATING_STRATEGY_16022026");
bytes32 constant PAYMENT_SPLITTER_FACTORY_SALT = keccak256("PAYMENT_SPLITTER_FACTORY_16022026");
bytes32 constant LIDO_FACTORY_SALT = keccak256("LIDO_STRATEGY_FACTORY_16022026");
bytes32 constant MORPHO_FACTORY_SALT = keccak256("MORPHO_COMPOUNDER_FACTORY_16022026");
bytes32 constant SKY_FACTORY_SALT = keccak256("SKY_COMPOUNDER_FACTORY_16022026");
bytes32 constant YEARN_V3_FACTORY_SALT = keccak256("YEARN_V3_STRATEGY_FACTORY_16022026");
bytes32 constant ADDRESS_SET_FACTORY_SALT = keccak256("ADDRESS_SET_FACTORY_16022026");
bytes32 constant CALC_FACTORY_SALT = keccak256("REGEN_EARNING_POWER_CALCULATOR_FACTORY_16022026");
bytes32 constant STAKER_FACTORY_SALT = keccak256("REGEN_STAKER_FACTORY_16022026");

// --- Phase B: Instance Deployment Salts ---
bytes32 constant ALLOCATION_MECHANISM_ALLOWSET_SALT = keccak256("OCTANT_ALLOCATION_MECHANISM_ALLOWSET_V1");
bytes32 constant CALCULATOR_SALT = keccak256("OCTANT_REGEN_EARNING_POWER_CALCULATOR_V1");
bytes32 constant STAKER_SALT = keccak256("OCTANT_REGEN_STAKER_WITHOUT_DELEGATION_V1");

// --- Staker Access Control Salts ---
bytes32 constant STAKER_ALLOWSET_SALT = keccak256("OCTANT_STAKER_ALLOWSET_V1");
bytes32 constant STAKER_BLOCKSET_SALT = keccak256("OCTANT_STAKER_BLOCKSET_V1");

// --- Staker Configuration ---
uint256 constant MAX_BUMP_TIP = 0.002 ether;
uint256 constant MINIMUM_STAKE = 0;
uint256 constant REWARD_DURATION = 30 days;

// --- Expected Addresses (deterministic, computed via DeployProtocol.computeAllAddresses()) ---

// Phase A: Factories & Implementations
address constant EXPECTED_YIELD_SKIMMING = 0x573A99d6717273fcC48072F1A9761b337b4877fF;
address constant EXPECTED_YIELD_DONATING = 0xb7Ac4a08b9e0FAD5DC154e4F4b35b4365B2Fb3cA;
address constant EXPECTED_PAYMENT_SPLITTER_FACTORY = 0x11551f2b877055b2731E5A25B1C01966C0D5aaA1;
address constant EXPECTED_LIDO_FACTORY = 0x4732CF067dEcB38B84F64f4Ae61FD83a6D2eBb03;
address constant EXPECTED_MORPHO_FACTORY = 0xeC9710B9e3404C788AddD567dF52D669942fA5d2;
address constant EXPECTED_SKY_FACTORY = 0x67E5dc580c5c8702B7E46BA1812C56d304B136D3;
address constant EXPECTED_YEARN_FACTORY = 0xd5338eb7DFFE2e16cd217e8b0FA3d762024f614C;
address constant EXPECTED_ADDRESS_SET_FACTORY = 0x94e05a2bEd3a6bD2809cF8Dcb7dc85b57019F714;
address constant EXPECTED_CALC_FACTORY = 0x5Afd92333b6e5AF40A55455abD435cb2EE876Dba;
address constant EXPECTED_STAKER_FACTORY = 0x8f15465724bF7a7fF4171257E4f03Df1A586201D;

// Phase B: Instances
address constant EXPECTED_ALLOWSET = 0x19cD4e88f7F76948e54285b4E47B7d202225ee50;
address constant EXPECTED_CALCULATOR = 0x66F7b714360866725EF9d5C13EB4761113F3580c;
address constant EXPECTED_STAKER = 0xD883B716F03EDcC3a007b6B1e5131eE81f04490a;
address constant EXPECTED_STAKER_ALLOWSET = 0xb0661B32f9B5D0eBAde3fec11DF21FBd12a1e941;
address constant EXPECTED_STAKER_BLOCKSET = 0xa64E2d8dd4C283F89dCF1Db5414A0c78ae4e85b5;

// ═════════════════════════════════════════════════════════════════════════════
//
//  DEPLOYMENT SCRIPT
//
// ═════════════════════════════════════════════════════════════════════════════

/// @title DeployProtocol
/// @notice Reproducible Foundry script encoding the complete Octant v2 protocol
///         deployment to Ethereum mainnet. All business-logic parameters are
///         hardcoded as file-level constants. Infrastructure env vars (CHAIN,
///         WALLET_TYPE, PRIVATE_KEY) remain as env vars since they are
///         deployment-time concerns.
///
///         The deployment is structured as 7 Gnosis Safe transactions:
///           Phase A (Tx 1-3): 10 factory/implementation contracts via Nick's CREATE2
///           Phase B (Tx 4-7): 3 address sets + calculator + staker + staker access set assignment
///                             Staker is constructed with address(0) for allowset/blockset,
///                             then assigned post-construction via admin setters in Tx 7
///                             (accessMode=NONE, so they are initially inactive).
///
///         Replay on a fork (simulation only, default):
///           CHAIN=mainnet WALLET_TYPE=local PRIVATE_KEY=0x... \
///           forge script script/prod/DeployProtocol.s.sol:DeployProtocol \
///             --sig "phaseA_batch1()" --rpc-url $FORK_RPC --ffi
///
///         Set SEND=true to submit Safe transactions to the API (production).
contract DeployProtocol is Script, BatchScript {
    // ═════════════════════════════════════════════════════════════════════════
    //  HELPERS
    // ═════════════════════════════════════════════════════════════════════════

    /// @dev Returns true when SEND=true env var is set. Defaults to false
    ///      (simulation only). Set SEND=true for production Safe API submission.
    function _shouldSend() internal view returns (bool) {
        return vm.envOr("SEND", false);
    }

    /// @dev Computes the deterministic AddressSetFactory address from Phase A.
    function _addressSetFactoryAddress() internal pure returns (address) {
        return _computeCreate2AddressViaFactory(ADDRESS_SET_FACTORY_SALT, type(AddressSetFactory).creationCode);
    }

    /// @dev Computes the deterministic RegenStakerFactory address from Phase A.
    function _stakerFactoryAddress() internal pure returns (address) {
        return
            _computeCreate2AddressViaFactory(
                STAKER_FACTORY_SALT,
                abi.encodePacked(
                    type(RegenStakerFactory).creationCode,
                    abi.encode(
                        keccak256(REGEN_STAKER_V1_CREATION_CODE),
                        keccak256(REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE)
                    )
                )
            );
    }

    /// @dev Computes the deterministic RegenEarningPowerCalculator address from Phase B.
    function _calculatorAddress() internal pure returns (address) {
        return
            _computeCreate2AddressViaFactory(
                CALCULATOR_SALT,
                abi.encodePacked(
                    type(RegenEarningPowerCalculator).creationCode,
                    abi.encode(SAFE, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE)
                )
            );
    }

    /// @dev Predicts an AddressSet address as deployed by AddressSetFactory.
    ///      Replicates AddressSetFactory.predictAddress logic using a pre-computed factory address.
    function _predictAddressSet(address asFactory, bytes32 salt, address owner) internal pure returns (address) {
        bytes32 finalSalt = keccak256(abi.encode(salt, owner));
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), asFactory, finalSalt, keccak256(type(AddressSet).creationCode))
        );
        return address(uint160(uint256(hash)));
    }

    /// @dev Computes the deterministic RegenStaker (WITHOUT delegation) address from Phase B.
    ///      Replicates RegenStakerFactory._deployStaker CREATE2 logic using a pre-computed factory address.
    function _stakerAddress() internal pure returns (address) {
        address asFactory = _addressSetFactoryAddress();
        address sfactory = _stakerFactoryAddress();

        // Replicate _encodeConstructorParams ordering from RegenStakerFactory
        bytes memory constructorParams = abi.encode(
            IERC20(WETH), // rewardsToken
            IERC20(GLM), // stakeToken
            IEarningPowerCalculator(_calculatorAddress()), // earningPowerCalculator
            MAX_BUMP_TIP, // maxBumpTip
            SAFE, // admin
            REWARD_DURATION, // rewardDuration
            MINIMUM_STAKE, // minimumStakeAmount
            IAddressSet(address(0)), // stakerAllowset (assigned post-construction via Tx 7)
            IAddressSet(address(0)), // stakerBlockset (assigned post-construction via Tx 7)
            AccessMode.NONE, // stakerAccessMode
            IAddressSet(_predictAddressSet(asFactory, ALLOCATION_MECHANISM_ALLOWSET_SALT, SAFE)) // allocationMechanismAllowset
        );

        bytes memory fullBytecode = bytes.concat(REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE, constructorParams);
        // finalSalt = keccak256(abi.encode(salt, msg.sender)) where msg.sender is the Safe
        bytes32 finalSalt = keccak256(abi.encode(STAKER_SALT, SAFE));

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), sfactory, finalSalt, keccak256(fullBytecode)));
        return address(uint160(uint256(hash)));
    }

    /// @notice Compute and log all 15 deterministic addresses from pure CREATE2 math.
    ///         No RPC or on-chain state needed. Used to populate EXPECTED_* constants.
    ///
    ///         Usage: forge script script/prod/DeployProtocol.s.sol:DeployProtocol \
    ///                  --sig "computeAllAddresses()"
    function computeAllAddresses() external pure {
        _logPhaseAAddresses();
        _logPhaseBAddresses();
    }

    function _logPhaseAAddresses() internal pure {
        console.log(
            "EXPECTED_YIELD_SKIMMING:",
            _computeCreate2AddressViaFactory(YIELD_SKIMMING_SALT, type(YieldSkimmingTokenizedStrategy).creationCode)
        );
        console.log(
            "EXPECTED_YIELD_DONATING:",
            _computeCreate2AddressViaFactory(YIELD_DONATING_SALT, type(YieldDonatingTokenizedStrategy).creationCode)
        );
        console.log(
            "EXPECTED_PAYMENT_SPLITTER_FACTORY:",
            _computeCreate2AddressViaFactory(PAYMENT_SPLITTER_FACTORY_SALT, type(PaymentSplitterFactory).creationCode)
        );
        console.log(
            "EXPECTED_LIDO_FACTORY:",
            _computeCreate2AddressViaFactory(LIDO_FACTORY_SALT, type(LidoStrategyFactory).creationCode)
        );
        console.log(
            "EXPECTED_MORPHO_FACTORY:",
            _computeCreate2AddressViaFactory(MORPHO_FACTORY_SALT, type(MorphoCompounderStrategyFactory).creationCode)
        );
        console.log(
            "EXPECTED_SKY_FACTORY:",
            _computeCreate2AddressViaFactory(SKY_FACTORY_SALT, type(SkyCompounderStrategyFactory).creationCode)
        );
        console.log(
            "EXPECTED_YEARN_FACTORY:",
            _computeCreate2AddressViaFactory(YEARN_V3_FACTORY_SALT, type(YearnV3StrategyFactory).creationCode)
        );
        console.log("EXPECTED_ADDRESS_SET_FACTORY:", _addressSetFactoryAddress());
        console.log(
            "EXPECTED_CALC_FACTORY:",
            _computeCreate2AddressViaFactory(CALC_FACTORY_SALT, type(RegenEarningPowerCalculatorFactory).creationCode)
        );
        console.log("EXPECTED_STAKER_FACTORY:", _stakerFactoryAddress());
    }

    function _logPhaseBAddresses() internal pure {
        address asFactory = _addressSetFactoryAddress();
        console.log("EXPECTED_ALLOWSET:", _predictAddressSet(asFactory, ALLOCATION_MECHANISM_ALLOWSET_SALT, SAFE));
        console.log("EXPECTED_STAKER_ALLOWSET:", _predictAddressSet(asFactory, STAKER_ALLOWSET_SALT, SAFE));
        console.log("EXPECTED_STAKER_BLOCKSET:", _predictAddressSet(asFactory, STAKER_BLOCKSET_SALT, SAFE));
        console.log("EXPECTED_CALCULATOR:", _calculatorAddress());
        console.log("EXPECTED_STAKER:", _stakerAddress());
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PHASE A: Factory Deployment (3 Safe Transactions)
    //
    //  All 10 contracts deployed via Nick's CREATE2 factory (0x4e59b44...56C).
    //  Split into 3 batches due to the EIP-7825 per-tx gas limit of ~16.78M.
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Tx 1 (~12.4M gas): 5 contracts
    ///         - YieldSkimmingTokenizedStrategy
    ///         - YieldDonatingTokenizedStrategy
    ///         - PaymentSplitterFactory
    ///         - LidoStrategyFactory
    ///         - MorphoCompounderStrategyFactory
    function phaseA_batch1() external isBatch(SAFE) {
        address deployed;

        deployed = _addCreate2Deployment(YIELD_SKIMMING_SALT, type(YieldSkimmingTokenizedStrategy).creationCode);
        require(deployed == EXPECTED_YIELD_SKIMMING, "YieldSkimming address mismatch");
        console.log("YieldSkimmingTokenizedStrategy:", deployed);

        deployed = _addCreate2Deployment(YIELD_DONATING_SALT, type(YieldDonatingTokenizedStrategy).creationCode);
        require(deployed == EXPECTED_YIELD_DONATING, "YieldDonating address mismatch");
        console.log("YieldDonatingTokenizedStrategy:", deployed);

        deployed = _addCreate2Deployment(PAYMENT_SPLITTER_FACTORY_SALT, type(PaymentSplitterFactory).creationCode);
        require(deployed == EXPECTED_PAYMENT_SPLITTER_FACTORY, "PaymentSplitterFactory address mismatch");
        console.log("PaymentSplitterFactory:", deployed);

        deployed = _addCreate2Deployment(LIDO_FACTORY_SALT, type(LidoStrategyFactory).creationCode);
        require(deployed == EXPECTED_LIDO_FACTORY, "LidoStrategyFactory address mismatch");
        console.log("LidoStrategyFactory:", deployed);

        deployed = _addCreate2Deployment(MORPHO_FACTORY_SALT, type(MorphoCompounderStrategyFactory).creationCode);
        require(deployed == EXPECTED_MORPHO_FACTORY, "MorphoCompounderStrategyFactory address mismatch");
        console.log("MorphoCompounderStrategyFactory:", deployed);

        executeBatch(_shouldSend());
    }

    /// @notice Tx 2: 2 contracts
    ///         - SkyCompounderStrategyFactory
    ///         - YearnV3StrategyFactory
    function phaseA_batch2() external isBatch(SAFE) {
        address deployed;

        deployed = _addCreate2Deployment(SKY_FACTORY_SALT, type(SkyCompounderStrategyFactory).creationCode);
        require(deployed == EXPECTED_SKY_FACTORY, "SkyFactory address mismatch");
        console.log("SkyCompounderStrategyFactory:", deployed);

        deployed = _addCreate2Deployment(YEARN_V3_FACTORY_SALT, type(YearnV3StrategyFactory).creationCode);
        require(deployed == EXPECTED_YEARN_FACTORY, "YearnFactory address mismatch");
        console.log("YearnV3StrategyFactory:", deployed);

        executeBatch(_shouldSend());
    }

    /// @notice Tx 3 (~3M gas): 3 contracts
    ///         - AddressSetFactory
    ///         - RegenEarningPowerCalculatorFactory
    ///         - RegenStakerFactory (constructor: canonical bytecode hashes)
    function phaseA_batch3() external isBatch(SAFE) {
        address deployed;

        deployed = _addCreate2Deployment(ADDRESS_SET_FACTORY_SALT, type(AddressSetFactory).creationCode);
        require(deployed == EXPECTED_ADDRESS_SET_FACTORY, "AddressSetFactory address mismatch");
        console.log("AddressSetFactory:", deployed);

        deployed = _addCreate2Deployment(CALC_FACTORY_SALT, type(RegenEarningPowerCalculatorFactory).creationCode);
        require(deployed == EXPECTED_CALC_FACTORY, "CalcFactory address mismatch");
        console.log("RegenEarningPowerCalculatorFactory:", deployed);

        deployed = _addCreate2Deployment(
            STAKER_FACTORY_SALT,
            abi.encodePacked(
                type(RegenStakerFactory).creationCode,
                abi.encode(
                    keccak256(REGEN_STAKER_V1_CREATION_CODE),
                    keccak256(REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE)
                )
            )
        );
        require(deployed == EXPECTED_STAKER_FACTORY, "StakerFactory address mismatch");
        console.log("RegenStakerFactory:", deployed);

        executeBatch(_shouldSend());
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  PHASE B: Instance Deployment (4 Safe Transactions)
    //
    //  Requires Phase A factories to be deployed and executed on-chain first.
    //  Deploys 3 address sets, the earning power calculator, and the staker.
    //  The staker is constructed with address(0) for allowset/blockset, then
    //  assigned post-construction via admin setters in Tx 7.
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Tx 4: Deploy all 3 address sets via AddressSetFactory
    ///         - allocationMechanismAllowset
    ///         - stakerAllowset
    ///         - stakerBlockset
    ///         Batched into a single Safe MultiSend transaction.
    function phaseB_addressSets() external isBatch(SAFE) {
        address asFactory = _addressSetFactoryAddress();
        address deployed;

        // 1. Deploy allocation mechanism allowset
        bytes memory result = addToBatch(
            asFactory,
            0,
            abi.encodeWithSignature("deploy(bytes32,address)", ALLOCATION_MECHANISM_ALLOWSET_SALT, SAFE)
        );
        deployed = abi.decode(result, (address));
        require(deployed == EXPECTED_ALLOWSET, "AllowSet address mismatch");
        console.log("AllocationMechanismAllowset:", deployed);

        // 2. Deploy staker allowset
        result = addToBatch(
            asFactory,
            0,
            abi.encodeWithSignature("deploy(bytes32,address)", STAKER_ALLOWSET_SALT, SAFE)
        );
        deployed = abi.decode(result, (address));
        require(deployed == EXPECTED_STAKER_ALLOWSET, "StakerAllowset address mismatch");
        console.log("StakerAllowset:", deployed);

        // 3. Deploy staker blockset
        result = addToBatch(
            asFactory,
            0,
            abi.encodeWithSignature("deploy(bytes32,address)", STAKER_BLOCKSET_SALT, SAFE)
        );
        deployed = abi.decode(result, (address));
        require(deployed == EXPECTED_STAKER_BLOCKSET, "StakerBlockset address mismatch");
        console.log("StakerBlockset:", deployed);

        executeBatch(_shouldSend());
    }

    /// @notice Tx 5: Deploy RegenEarningPowerCalculator via Nick's CREATE2 factory
    ///         Constructor args: owner=Safe, allowset=0, blockset=0, accessMode=NONE
    ///         Single Safe transaction (not MultiSend).
    function phaseB_calculator() external isBatch(SAFE) {
        bytes memory creationCode = abi.encodePacked(
            type(RegenEarningPowerCalculator).creationCode,
            abi.encode(SAFE, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE)
        );
        bytes memory deployData = abi.encodePacked(CALCULATOR_SALT, creationCode);

        bytes memory result = executeTransaction(CREATE2_FACTORY, 0, deployData, Operation.CALL, _shouldSend());
        address deployed = _decodeCreate2DeployerResult(result);
        require(deployed == EXPECTED_CALCULATOR, "Calculator address mismatch");
        console.log("RegenEarningPowerCalculator:", deployed);
    }

    /// @notice Tx 6: Deploy RegenStaker (WITHOUT delegation) via RegenStakerFactory
    ///         Staker is constructed with address(0) for stakerAllowset and
    ///         stakerBlockset. These are assigned post-construction in Tx 7.
    ///         accessMode is set to NONE so the sets are initially inactive.
    ///         Single Safe transaction (not MultiSend).
    function phaseB_staker() external isBatch(SAFE) {
        // Compute deterministic addresses for staker access control sets
        AddressSetFactory asFactory = AddressSetFactory(_addressSetFactoryAddress());

        RegenStakerFactory.CreateStakerParams memory params = RegenStakerFactory.CreateStakerParams({
            rewardsToken: IERC20(WETH),
            stakeToken: IERC20(GLM),
            admin: SAFE,
            stakerAllowset: IAddressSet(address(0)),
            stakerBlockset: IAddressSet(address(0)),
            stakerAccessMode: AccessMode.NONE,
            allocationMechanismAllowset: IAddressSet(
                asFactory.predictAddress(ALLOCATION_MECHANISM_ALLOWSET_SALT, SAFE)
            ),
            earningPowerCalculator: IEarningPowerCalculator(_calculatorAddress()),
            maxBumpTip: MAX_BUMP_TIP,
            minimumStakeAmount: MINIMUM_STAKE,
            rewardDuration: REWARD_DURATION
        });

        bytes memory data = abi.encodeWithSignature(
            "createStakerWithoutDelegation((address,address,address,address,address,uint8,address,address,uint256,uint256,uint256),bytes32,bytes)",
            params,
            STAKER_SALT,
            REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE
        );

        bytes memory result = executeTransaction(_stakerFactoryAddress(), 0, data, Operation.CALL, _shouldSend());
        address deployed = abi.decode(result, (address));
        require(deployed == EXPECTED_STAKER, "Staker address mismatch");
        console.log("RegenStaker:", deployed);
    }

    /// @notice Tx 7: Assign staker allowset and blockset via admin setters.
    ///         Batched into a single Safe MultiSend transaction.
    function phaseB_stakerAccessSets() external isBatch(SAFE) {
        address asFactory = _addressSetFactoryAddress();

        addToBatch(
            EXPECTED_STAKER,
            0,
            abi.encodeWithSignature(
                "setStakerAllowset(address)",
                _predictAddressSet(asFactory, STAKER_ALLOWSET_SALT, SAFE)
            )
        );

        addToBatch(
            EXPECTED_STAKER,
            0,
            abi.encodeWithSignature(
                "setStakerBlockset(address)",
                _predictAddressSet(asFactory, STAKER_BLOCKSET_SALT, SAFE)
            )
        );

        executeBatch(_shouldSend());
    }
}

// ═════════════════════════════════════════════════════════════════════════════
//
//  DEPLOYMENT VERIFICATION TEST
//
// ═════════════════════════════════════════════════════════════════════════════

/// @title VerifyProtocolDeployment
/// @notice Fork test that validates all deployed mainnet contracts are correctly
///         deployed and functionally operational. Covers all 10 Phase A
///         factory/implementation contracts, all 5 Phase B instance contracts.
///
///         Run against Ethereum mainnet fork:
///           forge test --match-contract VerifyProtocolDeployment --fork-url <mainnet-rpc>
contract VerifyProtocolDeployment is Test {
    // --- Typed bindings for deployed contracts ---

    // Phase A
    PaymentSplitterFactory constant paymentSplitterFactory = PaymentSplitterFactory(EXPECTED_PAYMENT_SPLITTER_FACTORY);
    LidoStrategyFactory constant lidoStrategyFactory = LidoStrategyFactory(EXPECTED_LIDO_FACTORY);
    MorphoCompounderStrategyFactory constant morphoFactory = MorphoCompounderStrategyFactory(EXPECTED_MORPHO_FACTORY);
    SkyCompounderStrategyFactory constant skyFactory = SkyCompounderStrategyFactory(EXPECTED_SKY_FACTORY);
    YearnV3StrategyFactory constant yearnFactory = YearnV3StrategyFactory(EXPECTED_YEARN_FACTORY);
    AddressSetFactory constant addressSetFactory = AddressSetFactory(EXPECTED_ADDRESS_SET_FACTORY);
    RegenEarningPowerCalculatorFactory constant calculatorFactory =
        RegenEarningPowerCalculatorFactory(EXPECTED_CALC_FACTORY);
    RegenStakerFactory constant regenStakerFactory = RegenStakerFactory(EXPECTED_STAKER_FACTORY);

    // Phase B
    AddressSet constant allowSet = AddressSet(EXPECTED_ALLOWSET);
    RegenEarningPowerCalculator constant calculator = RegenEarningPowerCalculator(EXPECTED_CALCULATOR);
    RegenStakerWithoutDelegateSurrogateVotes constant staker =
        RegenStakerWithoutDelegateSurrogateVotes(EXPECTED_STAKER);

    // Phase C
    AddressSet constant stakerAllowset = AddressSet(EXPECTED_STAKER_ALLOWSET);
    AddressSet constant stakerBlockset = AddressSet(EXPECTED_STAKER_BLOCKSET);

    // --- All deployed addresses for code-existence check ---
    address[] internal allContracts;

    address internal testUser = makeAddr("testUser");

    function setUp() public {
        allContracts.push(EXPECTED_YIELD_SKIMMING);
        allContracts.push(EXPECTED_YIELD_DONATING);
        allContracts.push(address(paymentSplitterFactory));
        allContracts.push(address(lidoStrategyFactory));
        allContracts.push(address(morphoFactory));
        allContracts.push(address(skyFactory));
        allContracts.push(address(yearnFactory));
        allContracts.push(address(addressSetFactory));
        allContracts.push(address(calculatorFactory));
        allContracts.push(address(regenStakerFactory));
        allContracts.push(address(allowSet));
        allContracts.push(address(calculator));
        allContracts.push(address(staker));
        allContracts.push(address(stakerAllowset));
        allContracts.push(address(stakerBlockset));
    }

    // -----------------------------------------------------------------------
    // Test 1: All 15 contracts have code on-chain
    // -----------------------------------------------------------------------

    function test_allContractsHaveCode() public view {
        for (uint256 i = 0; i < allContracts.length; i++) {
            assertTrue(
                allContracts[i].code.length > 0,
                string.concat("No code at address: ", vm.toString(allContracts[i]))
            );
        }
    }

    // -----------------------------------------------------------------------
    // Test 2: Factory interface smoke tests
    // -----------------------------------------------------------------------

    function test_factoryInterfaces() public view {
        // PaymentSplitterFactory
        assertTrue(paymentSplitterFactory.implementation() != address(0), "PSF: zero implementation");
        assertTrue(paymentSplitterFactory.owner() != address(0), "PSF: zero owner");

        // LidoStrategyFactory
        assertEq(lidoStrategyFactory.WSTETH(), 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, "LidoFactory: wrong WSTETH");

        // MorphoCompounderStrategyFactory
        assertEq(morphoFactory.USDC(), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "MorphoFactory: wrong USDC");
        assertEq(morphoFactory.YS_USDC(), 0x074134A2784F4F66b6ceD6f68849382990Ff3215, "MorphoFactory: wrong YS_USDC");

        // SkyCompounderStrategyFactory
        assertEq(skyFactory.USDS(), 0xdC035D45d973E3EC169d2276DDab16f1e407384F, "SkyFactory: wrong USDS");
        assertEq(
            skyFactory.USDS_REWARD_ADDRESS(),
            0x0650CAF159C5A49f711e8169D4336ECB9b950275,
            "SkyFactory: wrong USDS_REWARD_ADDRESS"
        );

        // YearnV3StrategyFactory: computeStrategyAddress doesn't revert
        yearnFactory.computeStrategyAddress(
            address(1),
            address(2),
            "test",
            "TST",
            address(3),
            address(4),
            address(5),
            address(6),
            false,
            EXPECTED_YIELD_DONATING,
            address(7)
        );

        // AddressSetFactory: predictAddress returns non-zero
        address predicted = addressSetFactory.predictAddress(bytes32(uint256(1)), address(this));
        assertTrue(predicted != address(0), "AddressSetFactory: zero predicted address");

        // RegenEarningPowerCalculatorFactory: predictAddress returns non-zero
        address calcPredicted = calculatorFactory.predictAddress(
            bytes32(uint256(1)),
            address(this),
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        assertTrue(calcPredicted != address(0), "CalcFactory: zero predicted address");

        // RegenStakerFactory: canonical bytecode hashes match pinned bytecodes
        assertEq(
            regenStakerFactory.canonicalBytecodeHash(RegenStakerFactory.RegenStakerVariant.WITH_DELEGATION),
            keccak256(REGEN_STAKER_V1_CREATION_CODE),
            "StakerFactory: WITH_DELEGATION hash does not match pinned bytecode"
        );
        assertEq(
            regenStakerFactory.canonicalBytecodeHash(RegenStakerFactory.RegenStakerVariant.WITHOUT_DELEGATION),
            keccak256(REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE),
            "StakerFactory: WITHOUT_DELEGATION hash does not match pinned bytecode"
        );
    }

    // -----------------------------------------------------------------------
    // Test 3: AllowSet ownership and initial state
    // -----------------------------------------------------------------------

    function test_allowSetOwnership() public view {
        assertEq(allowSet.owner(), SAFE, "AllowSet: owner is not Safe");
        assertEq(allowSet.length(), 0, "AllowSet: should be empty on fresh deploy");
    }

    // -----------------------------------------------------------------------
    // Test 4: AllowSet add/remove functionality
    // -----------------------------------------------------------------------

    function test_allowSetFunctionality() public {
        address testAddr = makeAddr("allowSetTest");

        vm.prank(SAFE);
        allowSet.add(testAddr);
        assertTrue(allowSet.contains(testAddr), "AllowSet: address not found after add");
        assertEq(allowSet.length(), 1, "AllowSet: length should be 1 after add");

        vm.prank(SAFE);
        allowSet.remove(testAddr);
        assertFalse(allowSet.contains(testAddr), "AllowSet: address found after remove");
        assertEq(allowSet.length(), 0, "AllowSet: length should be 0 after remove");

        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, testUser));
        allowSet.add(testAddr);
    }

    // -----------------------------------------------------------------------
    // Test 5: AddressSetFactory determinism (all 3 AddressSets match predictions)
    // -----------------------------------------------------------------------

    function test_addressSetFactoryDeterminism() public view {
        assertEq(
            addressSetFactory.predictAddress(ALLOCATION_MECHANISM_ALLOWSET_SALT, SAFE),
            address(allowSet),
            "AddressSetFactory: prediction mismatch for allocationMechanismAllowset"
        );

        assertEq(
            addressSetFactory.predictAddress(STAKER_ALLOWSET_SALT, SAFE),
            address(stakerAllowset),
            "AddressSetFactory: prediction mismatch for stakerAllowset"
        );

        assertEq(
            addressSetFactory.predictAddress(STAKER_BLOCKSET_SALT, SAFE),
            address(stakerBlockset),
            "AddressSetFactory: prediction mismatch for stakerBlockset"
        );

        assertTrue(address(allowSet) != address(stakerAllowset), "allowSet == stakerAllowset");
        assertTrue(address(allowSet) != address(stakerBlockset), "allowSet == stakerBlockset");
        assertTrue(address(stakerAllowset) != address(stakerBlockset), "stakerAllowset == stakerBlockset");
    }

    // -----------------------------------------------------------------------
    // Test 6: Staker AddressSet ownership and initial state
    // -----------------------------------------------------------------------

    function test_stakerAddressSetsOwnership() public view {
        assertEq(stakerAllowset.owner(), SAFE, "stakerAllowset: owner is not Safe");
        assertEq(stakerAllowset.length(), 0, "stakerAllowset: should be empty on fresh deploy");
        assertEq(stakerBlockset.owner(), SAFE, "stakerBlockset: owner is not Safe");
        assertEq(stakerBlockset.length(), 0, "stakerBlockset: should be empty on fresh deploy");
    }

    // -----------------------------------------------------------------------
    // Test 7: Calculator parameters
    // -----------------------------------------------------------------------

    function test_calculatorParameters() public view {
        assertEq(calculator.owner(), SAFE, "Calculator: owner is not Safe");
        assertTrue(calculator.accessMode() == AccessMode.NONE, "Calculator: accessMode should be NONE");
        assertEq(address(calculator.allowset()), address(0), "Calculator: allowset should be zero");
        assertEq(address(calculator.blockset()), address(0), "Calculator: blockset should be zero");
    }

    // -----------------------------------------------------------------------
    // Test 8: Calculator earning power computation
    // -----------------------------------------------------------------------

    function test_calculatorEarningPower() public view {
        address user = address(0xBEEF);
        uint256 stakeAmount = 1000e18;

        uint256 ep = calculator.getEarningPower(stakeAmount, user, user);
        assertEq(ep, stakeAmount, "Calculator: earning power should equal staked amount in NONE mode");

        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(stakeAmount, user, user, 500e18);
        assertEq(newEP, stakeAmount, "Calculator: newEarningPower mismatch");
        assertTrue(qualifies, "Calculator: should qualify for bump when EP changed");

        (uint256 sameEP, bool noBump) = calculator.getNewEarningPower(stakeAmount, user, user, stakeAmount);
        assertEq(sameEP, stakeAmount, "Calculator: sameEarningPower mismatch");
        assertFalse(noBump, "Calculator: should not qualify for bump when EP unchanged");
    }

    // -----------------------------------------------------------------------
    // Test 9: Staker parameters
    // -----------------------------------------------------------------------

    function test_stakerParameters() public view {
        assertEq(address(staker.REWARD_TOKEN()), WETH, "Staker: wrong REWARD_TOKEN");
        assertEq(address(staker.STAKE_TOKEN()), GLM, "Staker: wrong STAKE_TOKEN");
        assertEq(staker.admin(), SAFE, "Staker: admin is not Safe");
        assertEq(staker.maxBumpTip(), MAX_BUMP_TIP, "Staker: wrong maxBumpTip");
        assertEq(staker.rewardDuration(), REWARD_DURATION, "Staker: wrong rewardDuration");
        assertEq(staker.minimumStakeAmount(), MINIMUM_STAKE, "Staker: minimumStakeAmount should be 0");
        assertEq(address(staker.earningPowerCalculator()), address(calculator), "Staker: wrong earningPowerCalculator");
        assertEq(
            address(staker.allocationMechanismAllowset()),
            address(allowSet),
            "Staker: wrong allocationMechanismAllowset"
        );
        assertEq(
            address(staker.stakerAllowset()),
            address(stakerAllowset),
            "Staker: stakerAllowset not wired correctly"
        );
        assertEq(
            address(staker.stakerBlockset()),
            address(stakerBlockset),
            "Staker: stakerBlockset not wired correctly"
        );
        assertTrue(staker.stakerAccessMode() == AccessMode.NONE, "Staker: stakerAccessMode should be NONE");
        assertEq(staker.totalStaked(), 0, "Staker: totalStaked should be 0");
        assertEq(staker.totalEarningPower(), 0, "Staker: totalEarningPower should be 0");
    }

    // -----------------------------------------------------------------------
    // Test 10: Staker stake and withdraw cycle
    // -----------------------------------------------------------------------

    function test_stakerStakeAndWithdraw() public {
        uint256 amount = 100e18;

        deal(GLM, testUser, amount);

        vm.startPrank(testUser);
        IERC20(GLM).approve(address(staker), amount);
        Staker.DepositIdentifier depositId = staker.stake(amount, address(staker));
        vm.stopPrank();

        assertEq(staker.totalStaked(), amount, "Staker: totalStaked mismatch after stake");
        assertEq(staker.depositorTotalStaked(testUser), amount, "Staker: depositorTotalStaked mismatch");

        vm.prank(testUser);
        staker.withdraw(depositId, amount);

        assertEq(staker.totalStaked(), 0, "Staker: totalStaked should be 0 after withdraw");
        assertEq(IERC20(GLM).balanceOf(testUser), amount, "Staker: GLM not returned to user");
    }

    // -----------------------------------------------------------------------
    // Test 11: Cross-contract integration (stake -> earning power via calculator)
    // -----------------------------------------------------------------------

    function test_crossContractIntegration() public {
        uint256 amount = 500e18;

        deal(GLM, testUser, amount);
        vm.startPrank(testUser);
        IERC20(GLM).approve(address(staker), amount);
        Staker.DepositIdentifier depositId = staker.stake(amount, address(staker));
        vm.stopPrank();

        (uint96 balance, , uint96 earningPower, , , , ) = staker.deposits(depositId);

        assertEq(uint256(balance), amount, "Deposit: balance mismatch");
        assertEq(uint256(earningPower), amount, "Deposit: earningPower should equal staked amount in NONE mode");
        assertEq(staker.totalEarningPower(), amount, "Staker: totalEarningPower should equal staked amount");

        vm.prank(testUser);
        staker.withdraw(depositId, amount);
    }
}
