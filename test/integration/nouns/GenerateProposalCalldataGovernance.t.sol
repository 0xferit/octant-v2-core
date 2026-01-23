// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// Import the actual script we're testing
import { GenerateProposalCalldata } from "partners/nouns_dao/script/GenerateProposalCalldata.s.sol";

/// @notice Nouns DAO Governor interface (minimal)
interface INounsDAOProxy {
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    function queue(uint256 proposalId) external;
    function execute(uint256 proposalId) external;
    function state(uint256 proposalId) external view returns (uint8);
    function proposalThreshold() external view returns (uint256);
}

/// @notice Nouns NFT interface for voting power
interface INounsToken {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function delegate(address delegatee) external;
    function getCurrentVotes(address account) external view returns (uint96);
    function balanceOf(address owner) external view returns (uint256);
}

/**
 * @title GenerateProposalCalldata Governance Flow Test
 * @notice End-to-end test that DIRECTLY CALLS GenerateProposalCalldata.s.sol to get proposal data
 * @dev Run with:
 *      FOUNDRY_PROFILE=local forge test \
 *        --match-contract GenerateProposalCalldataGovernanceTest \
 *        -vvv
 *
 *      This test:
 *      1. Instantiates GenerateProposalCalldata.s.sol
 *      2. Calls getProposalTransactions() to get the EXACT calldata
 *      3. Creates a Nouns DAO proposal with that calldata
 *      4. Executes full governance flow: propose → vote → queue → execute
 *      5. Verifies: PaymentSplitter deployed, Strategy deployed, Treasury has shares
 *
 *      If the script changes, this test automatically uses the new values.
 */
contract GenerateProposalCalldataGovernanceTest is Test {
    // ══════════════════════════════════════════════════════════════════════════════
    // NOUNS DAO MAINNET ADDRESSES
    // ══════════════════════════════════════════════════════════════════════════════

    /// @notice Nouns DAO Governor proxy contract
    address public constant NOUNS_DAO_PROXY = 0x6f3E6272A167e8AcCb32072d08E0957F9c79223d;

    /// @notice Nouns NFT token contract
    address public constant NOUNS_TOKEN = 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03;

    /// @notice wstETH token address
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    /// @notice Vote type: For
    uint8 public constant VOTE_FOR = 1;

    /// @dev Selector for proposals(uint256)
    bytes4 private constant PROPOSALS_SELECTOR = bytes4(keccak256("proposals(uint256)"));

    // ══════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ══════════════════════════════════════════════════════════════════════════════

    uint256 public mainnetFork;
    uint256 public proposalId;
    address public testProposer;
    address public testVoter;

    /// @notice The script instance - this is what we're testing
    GenerateProposalCalldata public script;

    /// @notice Nouns Treasury address (from script)
    address public nounsTreasury;

    /// @notice Predicted addresses (from script)
    address public predictedPaymentSplitter;
    address public predictedStrategy;

    /// @notice Deposit amount (from script)
    uint256 public depositAmount;

    // ══════════════════════════════════════════════════════════════════════════════
    // SETUP
    // ══════════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Fork mainnet
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        // Create test addresses
        testProposer = makeAddr("testProposer");
        testVoter = makeAddr("testVoter");

        // ════════════════════════════════════════════════════════════════════════
        // INSTANTIATE THE SCRIPT - This is the key part!
        // ════════════════════════════════════════════════════════════════════════
        script = new GenerateProposalCalldata();

        // Get values directly from the script
        nounsTreasury = script.getNounsTreasury();
        depositAmount = script.getDepositAmount();
        (predictedPaymentSplitter, predictedStrategy) = script.getPrecomputedAddresses();

        // Label addresses for better traces
        vm.label(NOUNS_DAO_PROXY, "NounsDAOProxy");
        vm.label(nounsTreasury, "NounsExecutor");
        vm.label(NOUNS_TOKEN, "NounsToken");
        vm.label(WSTETH, "wstETH");
        vm.label(predictedPaymentSplitter, "PredictedPaymentSplitter");
        vm.label(predictedStrategy, "PredictedStrategy");
        vm.label(testProposer, "TestProposer");
        vm.label(testVoter, "TestVoter");
        vm.label(address(script), "GenerateProposalCalldata");
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // MAIN TEST
    // ══════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Full governance flow test using calldata directly from GenerateProposalCalldata.s.sol
     * @dev The test calls script.getProposalTransactions() to get the exact calldata
     */
    function test_fullGovernanceFlowWithScriptCalldata() public {
        INounsDAOProxy dao = INounsDAOProxy(NOUNS_DAO_PROXY);
        INounsToken nounsToken = INounsToken(NOUNS_TOKEN);

        // Precondition: Treasury must have sufficient wstETH
        uint256 treasuryWstETH = IERC20(WSTETH).balanceOf(nounsTreasury);
        require(treasuryWstETH >= depositAmount, "Treasury has insufficient wstETH");

        // Step 0: Setup voting power
        _setupVotingPower(dao, nounsToken);

        // Step 1: Create proposal using EXACT calldata from the script
        _createProposalFromScript(dao);

        // Step 2: Wait for voting delay, then vote
        _waitAndVote(dao);

        // Step 3: Queue the proposal
        _queueProposal(dao);

        // Step 4: Wait for timelock, then execute
        _waitAndExecute(dao);

        // Step 5: Verify everything worked
        _verifyExecution();
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // STEP IMPLEMENTATIONS
    // ══════════════════════════════════════════════════════════════════════════════

    function _setupVotingPower(INounsDAOProxy dao, INounsToken nounsToken) internal {
        uint256 proposalThreshold = dao.proposalThreshold();

        // Transfer Nouns from treasury to proposer (need threshold + 1)
        uint256 proposerNounsNeeded = proposalThreshold + 1;
        uint256 found = 0;

        for (uint256 tokenId = 20; tokenId < 1000 && found < proposerNounsNeeded; tokenId++) {
            try nounsToken.ownerOf(tokenId) returns (address owner) {
                if (owner == nounsTreasury) {
                    vm.prank(nounsTreasury);
                    nounsToken.transferFrom(nounsTreasury, testProposer, tokenId);
                    found++;
                }
            } catch {
                continue;
            }
        }
        require(found >= proposerNounsNeeded, "Could not find enough Nouns for proposer");

        // Delegate proposer's Nouns to self
        vm.prank(testProposer);
        nounsToken.delegate(testProposer);

        // Transfer Nouns to voter (need ~150 for quorum)
        uint256 voterNounsNeeded = 150;
        found = 0;

        for (uint256 tokenId = 100; tokenId < 2000 && found < voterNounsNeeded; tokenId++) {
            try nounsToken.ownerOf(tokenId) returns (address owner) {
                if (owner == nounsTreasury) {
                    vm.prank(nounsTreasury);
                    nounsToken.transferFrom(nounsTreasury, testVoter, tokenId);
                    found++;
                }
            } catch {
                continue;
            }
        }
        require(found >= 100, "Could not find enough Nouns for voter");

        // Delegate voter's Nouns to self
        vm.prank(testVoter);
        nounsToken.delegate(testVoter);

        // Roll forward to ensure delegation takes effect
        vm.roll(block.number + 1);

        // Verify voting power
        uint96 proposerVotes = nounsToken.getCurrentVotes(testProposer);
        uint96 voterVotes = nounsToken.getCurrentVotes(testVoter);
        require(proposerVotes > proposalThreshold, "Proposer needs more votes");
        require(voterVotes >= 100, "Voter needs more votes");
    }

    /**
     * @notice Create proposal by calling getProposalTransactions() on the actual script
     * @dev This is the key test - we use the EXACT output from GenerateProposalCalldata.s.sol
     */
    function _createProposalFromScript(INounsDAOProxy dao) internal {
        // ════════════════════════════════════════════════════════════════════════
        // GET PROPOSAL DATA DIRECTLY FROM THE SCRIPT
        // ════════════════════════════════════════════════════════════════════════
        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        ) = script.getProposalTransactions();

        // Verify we got 4 transactions
        assertEq(targets.length, 4, "Script should return 4 transactions");
        assertEq(values.length, 4, "Script should return 4 values");
        assertEq(signatures.length, 4, "Script should return 4 signatures");
        assertEq(calldatas.length, 4, "Script should return 4 calldatas");

        // Create the proposal using the script's exact output
        vm.prank(testProposer);
        proposalId = dao.propose(
            targets,
            values,
            signatures,
            calldatas,
            "Deploy Lido Yield Strategy - Testing GenerateProposalCalldata.s.sol output"
        );

        // Verify proposal created (state 0 = Pending or 10 = Updatable in V3)
        uint8 state = dao.state(proposalId);
        assertTrue(state == 0 || state == 10, "Proposal should be Pending or Updatable");
    }

    function _waitAndVote(INounsDAOProxy dao) internal {
        // Roll to voting start
        vm.roll(_getProposalStartBlock(proposalId) + 1);

        // Verify Active state
        uint8 state = dao.state(proposalId);
        assertEq(state, 1, "Proposal should be Active");

        // Vote from proposer
        vm.prank(testProposer);
        (bool success1, ) = address(dao).call(abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, VOTE_FOR));
        require(success1, "Proposer vote failed");

        // Vote from voter
        vm.prank(testVoter);
        (bool success2, ) = address(dao).call(abi.encodeWithSignature("castVote(uint256,uint8)", proposalId, VOTE_FOR));
        require(success2, "Voter vote failed");

        // Roll to end of voting
        vm.roll(_getProposalEndBlock(proposalId) + 1);

        // Verify Succeeded (4) or ObjectionPeriod (9)
        state = dao.state(proposalId);
        assertTrue(state == 4 || state == 9, "Proposal should have Succeeded or be in ObjectionPeriod");
    }

    function _queueProposal(INounsDAOProxy dao) internal {
        dao.queue(proposalId);

        uint8 state = dao.state(proposalId);
        assertEq(state, 5, "Proposal should be Queued");
    }

    function _waitAndExecute(INounsDAOProxy dao) internal {
        // Warp to after ETA
        vm.warp(_getProposalEta(proposalId) + 1);

        // Execute
        dao.execute(proposalId);

        // Verify Executed
        uint8 state = dao.state(proposalId);
        assertEq(state, 7, "Proposal should be Executed");
    }

    function _verifyExecution() internal view {
        // ════════════════════════════════════════════════════════════════════════
        // VERIFY: PaymentSplitter deployed to predicted address (from script)
        // ════════════════════════════════════════════════════════════════════════
        assertTrue(predictedPaymentSplitter.code.length > 0, "PaymentSplitter should be deployed at predicted address");

        // ════════════════════════════════════════════════════════════════════════
        // VERIFY: LidoStrategy deployed to predicted address (from script)
        // ════════════════════════════════════════════════════════════════════════
        assertTrue(predictedStrategy.code.length > 0, "LidoStrategy should be deployed at predicted address");

        // ════════════════════════════════════════════════════════════════════════
        // VERIFY: Treasury has strategy shares
        // ════════════════════════════════════════════════════════════════════════
        uint256 treasuryShares = IERC4626(predictedStrategy).balanceOf(nounsTreasury);
        assertGt(treasuryShares, 0, "Treasury should have strategy shares");

        // ════════════════════════════════════════════════════════════════════════
        // VERIFY: Strategy has the deposited assets (amount from script)
        // ════════════════════════════════════════════════════════════════════════
        uint256 strategyAssets = IERC4626(predictedStrategy).totalAssets();
        assertEq(strategyAssets, depositAmount, "Strategy should have deposited assets");

        // ════════════════════════════════════════════════════════════════════════
        // VERIFY: Shares are redeemable for approximately the deposit amount
        // ════════════════════════════════════════════════════════════════════════
        uint256 redeemableAssets = IERC4626(predictedStrategy).convertToAssets(treasuryShares);
        assertApproxEqRel(
            redeemableAssets,
            depositAmount,
            0.01e18, // 1% tolerance
            "Shares should be redeemable for ~deposit amount"
        );
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // PROPOSAL FIELD EXTRACTORS
    // ══════════════════════════════════════════════════════════════════════════════

    function _getProposalStartBlock(uint256 _proposalId) internal view returns (uint256 startBlock) {
        (bool success, bytes memory data) = NOUNS_DAO_PROXY.staticcall(
            abi.encodeWithSelector(PROPOSALS_SELECTOR, _proposalId)
        );
        require(success, "proposals call failed");
        assembly {
            startBlock := mload(add(data, 192))
        }
    }

    function _getProposalEndBlock(uint256 _proposalId) internal view returns (uint256 endBlock) {
        (bool success, bytes memory data) = NOUNS_DAO_PROXY.staticcall(
            abi.encodeWithSelector(PROPOSALS_SELECTOR, _proposalId)
        );
        require(success, "proposals call failed");
        assembly {
            endBlock := mload(add(data, 224))
        }
    }

    function _getProposalEta(uint256 _proposalId) internal view returns (uint256 eta) {
        (bool success, bytes memory data) = NOUNS_DAO_PROXY.staticcall(
            abi.encodeWithSelector(PROPOSALS_SELECTOR, _proposalId)
        );
        require(success, "proposals call failed");
        assembly {
            eta := mload(add(data, 160))
        }
    }
}
