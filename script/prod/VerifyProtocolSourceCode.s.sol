// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// ─── Import file-level constants from DeployProtocol ──────────────────────────
import { SAFE, WETH, GLM, MAX_BUMP_TIP, MINIMUM_STAKE, REWARD_DURATION, ALLOCATION_MECHANISM_ALLOWSET_SALT, EXPECTED_YIELD_SKIMMING, EXPECTED_YIELD_DONATING, EXPECTED_PAYMENT_SPLITTER_FACTORY, EXPECTED_LIDO_FACTORY, EXPECTED_MORPHO_FACTORY, EXPECTED_SKY_FACTORY, EXPECTED_YEARN_FACTORY, EXPECTED_ADDRESS_SET_FACTORY, EXPECTED_CALC_FACTORY, EXPECTED_STAKER_FACTORY, EXPECTED_ALLOWSET, EXPECTED_CALCULATOR, EXPECTED_STAKER, EXPECTED_STAKER_ALLOWSET, EXPECTED_STAKER_BLOCKSET } from "./DeployProtocol.s.sol";

// ─── Pinned bytecodes (for RegenStakerFactory constructor args) ──────────────
import { REGEN_STAKER_V1_CREATION_CODE, REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE } from "./RegenStakerBytecodes.sol";

// ─── Type imports for constructor args encoding ──────────────────────────────
import { IERC20 } from "staker/Staker.sol";
import { IAddressSet } from "src/utils/IAddressSet.sol";
import { IEarningPowerCalculator } from "staker/interfaces/IEarningPowerCalculator.sol";
import { AccessMode } from "src/constants.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { RegenStakerFactory } from "src/factories/RegenStakerFactory.sol";

/// @title VerifyProtocolSourceCode
/// @notice Verifies all 15 Octant v2 protocol contracts on Etherscan and Sourcify.
///         Uses deterministic addresses from DeployProtocol file-level constants.
///
///         Etherscan (requires API key):
///           ETHERSCAN_API_KEY=... forge script script/prod/VerifyProtocolSourceCode.s.sol:VerifyProtocolSourceCode \
///             --sig "verifyEtherscan()" --ffi
///
///         Sourcify (no API key needed):
///           forge script script/prod/VerifyProtocolSourceCode.s.sol:VerifyProtocolSourceCode \
///             --sig "verifySourcify()" --ffi
contract VerifyProtocolSourceCode is Script {
    // ═════════════════════════════════════════════════════════════════════════
    //  CONTRACT SOURCE PATHS
    // ═════════════════════════════════════════════════════════════════════════

    string constant YIELD_SKIMMING_PATH =
        "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol:YieldSkimmingTokenizedStrategy";
    string constant YIELD_DONATING_PATH =
        "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol:YieldDonatingTokenizedStrategy";
    string constant PAYMENT_SPLITTER_FACTORY_PATH = "src/factories/PaymentSplitterFactory.sol:PaymentSplitterFactory";
    string constant LIDO_FACTORY_PATH = "src/factories/LidoStrategyFactory.sol:LidoStrategyFactory";
    string constant MORPHO_FACTORY_PATH =
        "src/factories/MorphoCompounderStrategyFactory.sol:MorphoCompounderStrategyFactory";
    string constant SKY_FACTORY_PATH = "src/factories/SkyCompounderStrategyFactory.sol:SkyCompounderStrategyFactory";
    string constant YEARN_FACTORY_PATH =
        "src/factories/yieldDonating/YearnV3StrategyFactory.sol:YearnV3StrategyFactory";
    string constant ADDRESS_SET_FACTORY_PATH = "src/factories/AddressSetFactory.sol:AddressSetFactory";
    string constant CALC_FACTORY_PATH =
        "src/factories/RegenEarningPowerCalculatorFactory.sol:RegenEarningPowerCalculatorFactory";
    string constant STAKER_FACTORY_PATH = "src/factories/RegenStakerFactory.sol:RegenStakerFactory";
    string constant ADDRESS_SET_PATH = "src/utils/AddressSet.sol:AddressSet";
    string constant CALCULATOR_PATH = "src/regen/RegenEarningPowerCalculator.sol:RegenEarningPowerCalculator";
    string constant STAKER_PATH =
        "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol:RegenStakerWithoutDelegateSurrogateVotes";

    // ═════════════════════════════════════════════════════════════════════════
    //  ENTRY POINTS
    // ═════════════════════════════════════════════════════════════════════════

    /// @notice Verify all 15 contracts on Etherscan. Requires ETHERSCAN_API_KEY env var.
    function verifyEtherscan() external {
        _verifyAll("etherscan");
    }

    /// @notice Verify all 15 contracts on Sourcify. No API key needed.
    function verifySourcify() external {
        _verifyAll("sourcify");
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  INTERNAL: ORCHESTRATION
    // ═════════════════════════════════════════════════════════════════════════

    function _verifyAll(string memory verifier) internal {
        console.log("=== VERIFYING ALL 15 PROTOCOL CONTRACTS ===");
        console.log("Verifier:", verifier);
        console.log("");

        // ── Phase A: No constructor args (10 contracts) ──────────────────

        _verify(EXPECTED_YIELD_SKIMMING, YIELD_SKIMMING_PATH, "YieldSkimmingTokenizedStrategy", verifier);
        _verify(EXPECTED_YIELD_DONATING, YIELD_DONATING_PATH, "YieldDonatingTokenizedStrategy", verifier);
        _verify(EXPECTED_PAYMENT_SPLITTER_FACTORY, PAYMENT_SPLITTER_FACTORY_PATH, "PaymentSplitterFactory", verifier);
        _verify(EXPECTED_LIDO_FACTORY, LIDO_FACTORY_PATH, "LidoStrategyFactory", verifier);
        _verify(EXPECTED_MORPHO_FACTORY, MORPHO_FACTORY_PATH, "MorphoCompounderStrategyFactory", verifier);
        _verify(EXPECTED_SKY_FACTORY, SKY_FACTORY_PATH, "SkyCompounderStrategyFactory", verifier);
        _verify(EXPECTED_YEARN_FACTORY, YEARN_FACTORY_PATH, "YearnV3StrategyFactory", verifier);
        _verify(EXPECTED_ADDRESS_SET_FACTORY, ADDRESS_SET_FACTORY_PATH, "AddressSetFactory", verifier);
        _verify(EXPECTED_CALC_FACTORY, CALC_FACTORY_PATH, "RegenEarningPowerCalculatorFactory", verifier);

        // ── Phase A: With constructor args (1 contract) ──────────────────

        bytes memory stakerFactoryArgs = abi.encode(
            keccak256(REGEN_STAKER_V1_CREATION_CODE),
            keccak256(REGEN_STAKER_WITHOUT_DELEGATION_V1_CREATION_CODE)
        );
        _verifyWithArgs(
            EXPECTED_STAKER_FACTORY,
            STAKER_FACTORY_PATH,
            "RegenStakerFactory",
            stakerFactoryArgs,
            verifier
        );

        // ── Phase B: No constructor args (3 AddressSets) ─────────────────

        _verify(EXPECTED_ALLOWSET, ADDRESS_SET_PATH, "AddressSet (allocationMechanism)", verifier);
        _verify(EXPECTED_STAKER_ALLOWSET, ADDRESS_SET_PATH, "AddressSet (stakerAllowset)", verifier);
        _verify(EXPECTED_STAKER_BLOCKSET, ADDRESS_SET_PATH, "AddressSet (stakerBlockset)", verifier);

        // ── Phase B: With constructor args (2 contracts) ─────────────────

        bytes memory calculatorArgs = abi.encode(
            SAFE,
            IAddressSet(address(0)),
            IAddressSet(address(0)),
            AccessMode.NONE
        );
        _verifyWithArgs(EXPECTED_CALCULATOR, CALCULATOR_PATH, "RegenEarningPowerCalculator", calculatorArgs, verifier);

        bytes memory stakerArgs = _buildStakerConstructorArgs();
        _verifyWithArgs(EXPECTED_STAKER, STAKER_PATH, "RegenStakerWithoutDelegateSurrogateVotes", stakerArgs, verifier);

        console.log("=== VERIFICATION COMPLETE ===");
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  INTERNAL: CONSTRUCTOR ARGS
    // ═════════════════════════════════════════════════════════════════════════

    /// @dev Builds the staker constructor args matching _stakerAddress() in DeployProtocol.
    function _buildStakerConstructorArgs() internal pure returns (bytes memory) {
        address calculatorAddr = _computeCalculatorAddress();
        address allowsetAddr = _computeAllowsetAddress();

        return
            abi.encode(
                IERC20(WETH),
                IERC20(GLM),
                IEarningPowerCalculator(calculatorAddr),
                MAX_BUMP_TIP,
                SAFE,
                REWARD_DURATION,
                MINIMUM_STAKE,
                IAddressSet(address(0)),
                IAddressSet(address(0)),
                AccessMode.NONE,
                IAddressSet(allowsetAddr)
            );
    }

    /// @dev Replicates DeployProtocol._calculatorAddress() pure computation.
    function _computeCalculatorAddress() internal pure returns (address) {
        bytes32 salt = keccak256("OCTANT_REGEN_EARNING_POWER_CALCULATOR_V1");
        bytes memory creationCode = abi.encodePacked(
            type(RegenEarningPowerCalculator).creationCode,
            abi.encode(SAFE, IAddressSet(address(0)), IAddressSet(address(0)), AccessMode.NONE)
        );

        // Nick's CREATE2 factory at 0x4e59b44847b379578588920cA78FbF26c0B4956C
        address factory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), factory, salt, keccak256(creationCode)));
        return address(uint160(uint256(hash)));
    }

    /// @dev Replicates DeployProtocol._predictAddressSet() for the allocation mechanism allowset.
    function _computeAllowsetAddress() internal pure returns (address) {
        // First compute AddressSetFactory address via Nick's CREATE2
        bytes32 asFactorySalt = keccak256("ADDRESS_SET_FACTORY_16022026");
        address nickFactory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        bytes32 asFactoryHash = keccak256(
            abi.encodePacked(bytes1(0xff), nickFactory, asFactorySalt, keccak256(type(AddressSetFactory).creationCode))
        );
        address asFactory = address(uint160(uint256(asFactoryHash)));

        // Then predict AddressSet address as deployed by AddressSetFactory
        bytes32 finalSalt = keccak256(abi.encode(ALLOCATION_MECHANISM_ALLOWSET_SALT, SAFE));
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), asFactory, finalSalt, keccak256(type(AddressSet).creationCode))
        );
        return address(uint160(uint256(hash)));
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  INTERNAL: FFI VERIFICATION
    // ═════════════════════════════════════════════════════════════════════════

    /// @dev Verify a contract with no constructor args via forge verify-contract.
    function _verify(
        address contractAddress,
        string memory contractPath,
        string memory displayName,
        string memory verifier
    ) internal {
        console.log("Verifying", displayName, "at", contractAddress);

        string[] memory inputs = new string[](9);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(contractAddress);
        inputs[3] = contractPath;
        inputs[4] = "--verifier";
        inputs[5] = verifier;
        inputs[6] = "--chain";
        inputs[7] = "1";
        inputs[8] = "--watch";

        try vm.ffi(inputs) returns (bytes memory result) {
            console.log("  [SUCCESS]", displayName);
            console.log("   ", string(result));
        } catch (bytes memory error) {
            console.log("  [FAILED]", displayName);
            console.log("   ", string(error));
        }

        console.log("");
    }

    /// @dev Verify a contract with constructor args via forge verify-contract.
    ///      For Sourcify, constructor args are extracted from the creation tx automatically,
    ///      so we skip the --constructor-args flag.
    function _verifyWithArgs(
        address contractAddress,
        string memory contractPath,
        string memory displayName,
        bytes memory constructorArgs,
        string memory verifier
    ) internal {
        console.log("Verifying", displayName, "at", contractAddress);

        bool isEtherscan = _strEq(verifier, "etherscan");

        uint256 inputCount = isEtherscan ? 11 : 9;
        string[] memory inputs = new string[](inputCount);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = vm.toString(contractAddress);
        inputs[3] = contractPath;
        inputs[4] = "--verifier";
        inputs[5] = verifier;
        inputs[6] = "--chain";
        inputs[7] = "1";
        inputs[8] = "--watch";

        if (isEtherscan) {
            inputs[9] = "--constructor-args";
            inputs[10] = vm.toString(constructorArgs);
        }

        try vm.ffi(inputs) returns (bytes memory result) {
            console.log("  [SUCCESS]", displayName);
            console.log("   ", string(result));
        } catch (bytes memory error) {
            console.log("  [FAILED]", displayName);
            console.log("   ", string(error));
        }

        console.log("");
    }

    /// @dev Simple string equality check.
    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
