// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { Setup, IMockStrategy } from "./utils/Setup.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";

/// @notice Verifies that YIELD_SKIMMING_STORAGE_SLOT conforms to the ERC-7201 namespaced
///         storage formula. Bailsec #38 flagged that the constant previously omitted the
///         outer keccak256(abi.encode(...)) wrap and the alignment mask, deviating from the
///         standard. This test pins the canonical derivation and proves that namespaced
///         state actually lands at that slot.
contract YieldSkimmingStorageSlotTest is Setup {
    /// @dev Canonical ERC-7201 derivation for the namespace used by the strategy.
    bytes32 internal constant EXPECTED_SLOT =
        keccak256(abi.encode(uint256(keccak256("octant.yieldSkimming.exchangeRate")) - 1)) & ~bytes32(uint256(0xff));

    function setUp() public override {
        super.setUp();
    }

    function test_storageSlot_matchesERC7201Derivation() public pure {
        // Mask must be applied: low byte is zero.
        assertEq(uint256(EXPECTED_SLOT) & 0xff, 0, "ERC-7201 alignment mask not applied");

        // Slot must derive from the outer keccak256(abi.encode(inner)) wrap (not bytes32(inner)).
        uint256 inner = uint256(keccak256("octant.yieldSkimming.exchangeRate")) - 1;
        bytes32 nonCompliant = bytes32(inner);
        assertTrue(EXPECTED_SLOT != nonCompliant, "slot must not equal pre-fix non-compliant derivation");
    }

    function test_storageSlot_namespacedStateLandsAtCanonicalSlot() public {
        // Drive the namespaced storage by depositing — this writes
        // YS.totalDebtOwedToUserInAssetValue to the namespaced slot.
        uint256 depositAmount = 1e18;
        mintAndDepositIntoStrategy(strategy, user, depositAmount);

        // Namespaced struct layout:
        //   slot+0  totalDebtOwedToUserInAssetValue
        //   slot+1  lastReportedRate
        //   slot+2  dragonRouterDebtInAssetValue
        bytes32 word0 = vm.load(address(strategy), EXPECTED_SLOT);
        bytes32 word1 = vm.load(address(strategy), bytes32(uint256(EXPECTED_SLOT) + 1));

        uint256 userDebt = uint256(word0);
        uint256 lastRate = uint256(word1);

        // Cross-check via the public accessor: storage at the canonical ERC-7201 slot
        // must match what the contract reports.
        uint256 reportedDebt = IYieldSkimmingStrategy(address(strategy)).gettotalDebtOwedToUserInAssetValue();
        assertEq(userDebt, reportedDebt, "user debt not at canonical ERC-7201 slot");
        assertGt(userDebt, 0, "deposit should have set user debt");

        uint256 reportedRate = IYieldSkimmingStrategy(address(strategy)).getLastRateRay();
        assertEq(lastRate, reportedRate, "lastReportedRate not at canonical ERC-7201 slot");
        assertGt(lastRate, 0, "deposit should have set lastReportedRate");
    }
}
