// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";
import { LidoStrategyFactory } from "src/factories/LidoStrategyFactory.sol";
import { MorphoCompounderStrategyFactory } from "src/factories/MorphoCompounderStrategyFactory.sol";
import { SkyCompounderStrategyFactory } from "src/factories/SkyCompounderStrategyFactory.sol";
import { YearnV3StrategyFactory } from "src/factories/yieldDonating/YearnV3StrategyFactory.sol";
import { AddressSetFactory } from "src/factories/AddressSetFactory.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { RegenEarningPowerCalculator } from "src/regen/RegenEarningPowerCalculator.sol";
import { AddressSet } from "src/utils/AddressSet.sol";
import { Staker } from "staker/Staker.sol";
import { AccessMode } from "src/constants.sol";

/// @title VerifyMainnetDeployment
/// @notice Fork test that validates all 13 deployed mainnet contracts are correctly deployed
///         and functionally operational. Run against Ethereum mainnet fork.
contract VerifyMainnetDeployment is Test {
    // --- Gnosis Safe & Tokens ---
    address constant SAFE = 0xeD0044FEB17407C989C5703767F3A8DE3f9DbD3f;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant GLM = 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429;

    // --- Phase A: Factories & Strategy Templates ---
    address constant YIELD_SKIMMING_TOKENIZED_STRATEGY = 0x152C9D9D6F6d5B7113DE3229fE37F6A8Ff3aC54F;
    address constant YIELD_DONATING_TOKENIZED_STRATEGY = 0x99C06566d1dFff1F2B5E172E60C4500fed8Ad5fE;

    PaymentSplitterFactory constant paymentSplitterFactory =
        PaymentSplitterFactory(0xFa7658C59ADeA43991D40CAfce632eE9a2065467);
    LidoStrategyFactory constant lidoStrategyFactory = LidoStrategyFactory(0x15c8D739865f5a62441513565425c6Da57DC1C85);
    MorphoCompounderStrategyFactory constant morphoFactory =
        MorphoCompounderStrategyFactory(0x22e9Fa60D8Fb1D98D2Ae5e693318539AB13651A3);
    SkyCompounderStrategyFactory constant skyFactory =
        SkyCompounderStrategyFactory(0x788d73C5785AB8ED4c59783C57709294F3D17c00);
    YearnV3StrategyFactory constant yearnFactory = YearnV3StrategyFactory(0x4814904ef57F0C2DaD50e7100F2a5e621F88aBD0);
    AddressSetFactory constant addressSetFactory = AddressSetFactory(0xd6e72Ef3E50254eDa47f89531ed38aEdfDF25647);

    // --- Phase B: Deployed Instances ---
    AddressSet constant allowSet = AddressSet(0xb6CBED8c9BE30576446ba4C4943e088c6B22cc24);
    RegenEarningPowerCalculator constant calculator =
        RegenEarningPowerCalculator(0xa4959B7439d4C7CCE7Bc63BA79586Ef065Ef485d);
    RegenStakerWithoutDelegateSurrogateVotes constant staker =
        RegenStakerWithoutDelegateSurrogateVotes(0xa8cadaa23790237582BF83B24d90e0Fe2920982d);

    // --- All deployed addresses for code-existence check ---
    address[] internal allContracts;

    address internal testUser = makeAddr("testUser");

    function setUp() public {
        allContracts.push(YIELD_SKIMMING_TOKENIZED_STRATEGY);
        allContracts.push(YIELD_DONATING_TOKENIZED_STRATEGY);
        allContracts.push(address(paymentSplitterFactory));
        allContracts.push(address(lidoStrategyFactory));
        allContracts.push(address(morphoFactory));
        allContracts.push(address(skyFactory));
        allContracts.push(address(yearnFactory));
        allContracts.push(address(addressSetFactory));
        allContracts.push(address(allowSet));
        allContracts.push(address(calculator));
        allContracts.push(address(staker));
    }

    // -----------------------------------------------------------------------
    // Test 1: All contracts have code
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
        // PaymentSplitterFactory: implementation and owner are non-zero
        assertTrue(paymentSplitterFactory.implementation() != address(0), "PSF: zero implementation");
        assertTrue(paymentSplitterFactory.owner() != address(0), "PSF: zero owner");

        // LidoStrategyFactory: WSTETH constant
        assertEq(lidoStrategyFactory.WSTETH(), 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, "LidoFactory: wrong WSTETH");

        // MorphoCompounderStrategyFactory: USDC and YS_USDC constants
        assertEq(morphoFactory.USDC(), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, "MorphoFactory: wrong USDC");
        assertEq(morphoFactory.YS_USDC(), 0x074134A2784F4F66b6ceD6f68849382990Ff3215, "MorphoFactory: wrong YS_USDC");

        // SkyCompounderStrategyFactory: USDS and USDS_REWARD_ADDRESS constants
        assertEq(skyFactory.USDS(), 0xdC035D45d973E3EC169d2276DDab16f1e407384F, "SkyFactory: wrong USDS");
        assertEq(
            skyFactory.USDS_REWARD_ADDRESS(),
            0x0650CAF159C5A49f711e8169D4336ECB9b950275,
            "SkyFactory: wrong USDS_REWARD_ADDRESS"
        );

        // YearnV3StrategyFactory: computeStrategyAddress doesn't revert with dummy params
        yearnFactory.computeStrategyAddress(
            address(1), // vault
            address(2), // asset
            "test",
            "TST",
            address(3), // management
            address(4), // keeper
            address(5), // emergencyAdmin
            address(6), // donationAddress
            false,
            YIELD_DONATING_TOKENIZED_STRATEGY,
            address(7) // deployer
        );

        // AddressSetFactory: predictAddress returns deterministic non-zero result
        address predicted = addressSetFactory.predictAddress(bytes32(uint256(1)), address(this));
        assertTrue(predicted != address(0), "AddressSetFactory: zero predicted address");
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

        // Owner (Safe) can add
        vm.prank(SAFE);
        allowSet.add(testAddr);
        assertTrue(allowSet.contains(testAddr), "AllowSet: address not found after add");
        assertEq(allowSet.length(), 1, "AllowSet: length should be 1 after add");

        // Owner (Safe) can remove
        vm.prank(SAFE);
        allowSet.remove(testAddr);
        assertFalse(allowSet.contains(testAddr), "AllowSet: address found after remove");
        assertEq(allowSet.length(), 0, "AllowSet: length should be 0 after remove");

        // Non-owner cannot add
        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, testUser));
        allowSet.add(testAddr);
    }

    // -----------------------------------------------------------------------
    // Test 5: Calculator parameters
    // -----------------------------------------------------------------------

    function test_calculatorParameters() public view {
        assertEq(calculator.owner(), SAFE, "Calculator: owner is not Safe");
        assertTrue(calculator.accessMode() == AccessMode.NONE, "Calculator: accessMode should be NONE");
        assertEq(address(calculator.allowset()), address(0), "Calculator: allowset should be zero");
        assertEq(address(calculator.blockset()), address(0), "Calculator: blockset should be zero");
    }

    // -----------------------------------------------------------------------
    // Test 6: Calculator earning power computation
    // -----------------------------------------------------------------------

    function test_calculatorEarningPower() public view {
        address user = address(0xBEEF);
        uint256 stakeAmount = 1000e18;

        // NONE mode: full earning power
        uint256 ep = calculator.getEarningPower(stakeAmount, user, user);
        assertEq(ep, stakeAmount, "Calculator: earning power should equal staked amount in NONE mode");

        // getNewEarningPower: old < new -> qualifies for bump
        (uint256 newEP, bool qualifies) = calculator.getNewEarningPower(stakeAmount, user, user, 500e18);
        assertEq(newEP, stakeAmount, "Calculator: newEarningPower mismatch");
        assertTrue(qualifies, "Calculator: should qualify for bump when EP changed");

        // getNewEarningPower: old == new -> no bump
        (uint256 sameEP, bool noBump) = calculator.getNewEarningPower(stakeAmount, user, user, stakeAmount);
        assertEq(sameEP, stakeAmount, "Calculator: sameEarningPower mismatch");
        assertFalse(noBump, "Calculator: should not qualify for bump when EP unchanged");
    }

    // -----------------------------------------------------------------------
    // Test 7: Staker parameters
    // -----------------------------------------------------------------------

    function test_stakerParameters() public view {
        assertEq(address(staker.REWARD_TOKEN()), WETH, "Staker: wrong REWARD_TOKEN");
        assertEq(address(staker.STAKE_TOKEN()), GLM, "Staker: wrong STAKE_TOKEN");
        assertEq(staker.admin(), SAFE, "Staker: admin is not Safe");
        assertEq(staker.maxBumpTip(), 2e15, "Staker: wrong maxBumpTip");
        assertEq(staker.rewardDuration(), 2_592_000, "Staker: wrong rewardDuration (expect 30 days)");
        assertEq(staker.minimumStakeAmount(), 0, "Staker: minimumStakeAmount should be 0");
        assertEq(address(staker.earningPowerCalculator()), address(calculator), "Staker: wrong earningPowerCalculator");
        assertEq(
            address(staker.allocationMechanismAllowset()),
            address(allowSet),
            "Staker: wrong allocationMechanismAllowset"
        );
        assertEq(address(staker.stakerAllowset()), address(0), "Staker: stakerAllowset should be zero");
        assertEq(address(staker.stakerBlockset()), address(0), "Staker: stakerBlockset should be zero");
        assertTrue(staker.stakerAccessMode() == AccessMode.NONE, "Staker: stakerAccessMode should be NONE");
        assertEq(staker.totalStaked(), 0, "Staker: totalStaked should be 0");
        assertEq(staker.totalEarningPower(), 0, "Staker: totalEarningPower should be 0");
    }

    // -----------------------------------------------------------------------
    // Test 8: Staker stake and withdraw cycle
    // -----------------------------------------------------------------------

    function test_stakerStakeAndWithdraw() public {
        uint256 amount = 100e18;

        // Deal GLM to test user
        deal(GLM, testUser, amount);

        // Approve and stake
        vm.startPrank(testUser);
        IERC20(GLM).approve(address(staker), amount);

        // WITHOUT_DELEGATION variant uses address(this) as surrogate,
        // so delegatee param is effectively ignored but must be non-zero.
        // Passing address(staker) as delegatee.
        Staker.DepositIdentifier depositId = staker.stake(amount, address(staker));
        vm.stopPrank();

        // Verify post-stake state
        assertEq(staker.totalStaked(), amount, "Staker: totalStaked mismatch after stake");
        assertEq(staker.depositorTotalStaked(testUser), amount, "Staker: depositorTotalStaked mismatch");

        // Withdraw full amount
        vm.prank(testUser);
        staker.withdraw(depositId, amount);

        // Verify post-withdraw state
        assertEq(staker.totalStaked(), 0, "Staker: totalStaked should be 0 after withdraw");
        assertEq(IERC20(GLM).balanceOf(testUser), amount, "Staker: GLM not returned to user");
    }

    // -----------------------------------------------------------------------
    // Test 9: Cross-contract integration (stake -> earning power via calculator)
    // -----------------------------------------------------------------------

    function test_crossContractIntegration() public {
        uint256 amount = 500e18;

        // Deal GLM and stake
        deal(GLM, testUser, amount);
        vm.startPrank(testUser);
        IERC20(GLM).approve(address(staker), amount);
        Staker.DepositIdentifier depositId = staker.stake(amount, address(staker));
        vm.stopPrank();

        // Read deposit and verify earning power matches staked amount (NONE mode)
        // deposits() returns: (balance, owner, earningPower, delegatee, claimer, rewardPerTokenCheckpoint, scaledUnclaimedRewardCheckpoint)
        (uint96 balance, , uint96 earningPower, , , , ) = staker.deposits(depositId);

        assertEq(uint256(balance), amount, "Deposit: balance mismatch");
        assertEq(uint256(earningPower), amount, "Deposit: earningPower should equal staked amount in NONE mode");
        assertEq(staker.totalEarningPower(), amount, "Staker: totalEarningPower should equal staked amount");

        // Clean up
        vm.prank(testUser);
        staker.withdraw(depositId, amount);
    }
}
