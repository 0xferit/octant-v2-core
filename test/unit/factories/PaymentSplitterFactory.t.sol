// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";
import { PaymentSplitter } from "src/core/PaymentSplitter.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract PaymentSplitterFactoryTest is Test {
    PaymentSplitterFactory public factory;
    MockERC20 public token;

    // Test accounts
    address payable public alice = payable(address(0x1));
    address payable public bob = payable(address(0x2));
    address payable public charlie = payable(address(0x3));

    uint256 public constant INITIAL_ETH_AMOUNT = 100 ether;
    uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;

    function setUp() public {
        // Setup test accounts with ETH
        vm.deal(alice, INITIAL_ETH_AMOUNT);
        vm.deal(bob, INITIAL_ETH_AMOUNT);
        vm.deal(charlie, INITIAL_ETH_AMOUNT);
        vm.deal(address(this), INITIAL_ETH_AMOUNT);

        // Create mock ERC20 token for testing
        token = new MockERC20(18);
        token.mint(address(this), INITIAL_TOKEN_AMOUNT);

        // Deploy factory
        factory = new PaymentSplitterFactory();
    }

    // Test creating a PaymentSplitter without ETH
    function testCreatePaymentSplitter() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create PaymentSplitter and capture events
        vm.recordLogs();
        address splitterAddress = factory.createPaymentSplitter(payees, payeeNames, shares);

        // Verify splitter was created
        assertTrue(splitterAddress != address(0));

        // Check the PaymentSplitter state
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.payee(0), alice);
        assertEq(splitter.payee(1), bob);
        assertEq(splitter.payee(2), charlie);
        assertEq(splitter.shares(alice), 50);
        assertEq(splitter.shares(bob), 30);
        assertEq(splitter.shares(charlie), 20);

        // Verify splitter has no ETH
        assertEq(address(splitter).balance, 0);
    }

    // Test creating a PaymentSplitter with ETH
    function testCreatePaymentSplitterWithETH() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        uint256 ethAmount = 10 ether;

        // Create PaymentSplitter and capture events
        vm.recordLogs();
        address splitterAddress = factory.createPaymentSplitterWithETH{ value: ethAmount }(payees, payeeNames, shares);

        // Verify splitter was created
        assertTrue(splitterAddress != address(0));

        // Check the PaymentSplitter state
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.payee(0), alice);
        assertEq(splitter.payee(1), bob);
        assertEq(splitter.payee(2), charlie);
        assertEq(splitter.shares(alice), 50);
        assertEq(splitter.shares(bob), 30);
        assertEq(splitter.shares(charlie), 20);

        // Verify splitter received ETH
        assertEq(address(splitter).balance, ethAmount);

        // Calculate expected amounts
        uint256 aliceExpected = (ethAmount * 50) / 100;
        uint256 bobExpected = (ethAmount * 30) / 100;
        uint256 charlieExpected = (ethAmount * 20) / 100;

        // Check releasable amounts
        assertEq(splitter.releasable(alice), aliceExpected);
        assertEq(splitter.releasable(bob), bobExpected);
        assertEq(splitter.releasable(charlie), charlieExpected);
    }

    // Test releasing ETH from a created PaymentSplitter
    function testReleaseFromCreatedSplitter() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        uint256 ethAmount = 10 ether;

        // Create PaymentSplitter with ETH
        address splitterAddress = factory.createPaymentSplitterWithETH{ value: ethAmount }(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Release to Alice
        uint256 aliceExpected = (ethAmount * 50) / 100;
        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice); // Alice calls release
        splitter.release(alice);

        assertEq(alice.balance, aliceBalanceBefore + aliceExpected);
        assertEq(splitter.releasable(alice), 0);
        assertEq(splitter.released(alice), aliceExpected);
    }

    // Test PaymentSplitterFactory with ERC20 tokens
    function testWithERC20Tokens() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create PaymentSplitter
        address splitterAddress = factory.createPaymentSplitter(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Send tokens to the splitter
        uint256 tokenAmount = 100e18;
        token.transfer(address(splitter), tokenAmount);

        // Check token balances in the splitter
        assertEq(token.balanceOf(address(splitter)), tokenAmount);

        // Calculate expected amounts
        uint256 aliceExpected = (tokenAmount * 50) / 100;
        uint256 bobExpected = (tokenAmount * 30) / 100;
        uint256 charlieExpected = (tokenAmount * 20) / 100;

        // Check releasable amounts
        assertEq(splitter.releasable(IERC20(address(token)), alice), aliceExpected);
        assertEq(splitter.releasable(IERC20(address(token)), bob), bobExpected);
        assertEq(splitter.releasable(IERC20(address(token)), charlie), charlieExpected);

        // Release tokens to Alice
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        splitter.release(IERC20(address(token)), alice);
        assertEq(token.balanceOf(alice), aliceBalanceBefore + aliceExpected);
    }

    // Test invalid input to PaymentSplitter through factory
    function testInvalidInputToFactory() public {
        // Prepare invalid payees (empty array)
        address[] memory emptyPayees = new address[](0);
        string[] memory emptyNames = new string[](0);
        uint256[] memory emptyShares = new uint256[](0);

        // Expect revert
        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitter(emptyPayees, emptyNames, emptyShares);

        // Prepare invalid payees (mismatched arrays)
        address[] memory payees = new address[](2);
        payees[0] = alice;
        payees[1] = bob;

        string[] memory payeeNames = new string[](2);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Expect revert
        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitter(payees, payeeNames, shares);
    }

    // Test edge cases
    function testEdgeCases() public {
        // Single payee case
        address[] memory singlePayee = new address[](1);
        singlePayee[0] = alice;

        string[] memory singleName = new string[](1);
        singleName[0] = "GrantRoundOperator";

        uint256[] memory singleShare = new uint256[](1);
        singleShare[0] = 100;

        // Create PaymentSplitter with a single payee
        address splitterAddress = factory.createPaymentSplitter(singlePayee, singleName, singleShare);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Verify splitter state
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.payee(0), alice);
        assertEq(splitter.shares(alice), 100);

        // Many payees case (testing with 10)
        address[] memory manyPayees = new address[](10);
        string[] memory manyNames = new string[](10);
        uint256[] memory manyShares = new uint256[](10);

        for (uint256 i = 0; i < 10; i++) {
            // Create unique addresses
            manyPayees[i] = address(uint160(0x100 + i));
            manyNames[i] = string(abi.encodePacked("Payee", i));
            manyShares[i] = 10; // Equal shares
        }

        // Create PaymentSplitter with many payees
        address manySplitterAddress = factory.createPaymentSplitter(manyPayees, manyNames, manyShares);
        PaymentSplitter manySplitter = PaymentSplitter(payable(manySplitterAddress));

        // Verify splitter state
        assertEq(manySplitter.totalShares(), 100);

        for (uint256 i = 0; i < 10; i++) {
            assertEq(manySplitter.payee(i), manyPayees[i]);
            assertEq(manySplitter.shares(manyPayees[i]), 10);
        }
    }

    // Test creating PaymentSplitter with explicit salt
    function testCreatePaymentSplitterWithSalt() public {
        // Prepare payees and shares
        address[] memory payees = new address[](2);
        payees[0] = alice;
        payees[1] = bob;

        string[] memory payeeNames = new string[](2);
        payeeNames[0] = "Recipient1";
        payeeNames[1] = "Recipient2";

        uint256[] memory shares = new uint256[](2);
        shares[0] = 60;
        shares[1] = 40;

        bytes32 salt = keccak256("test-salt-v1");

        // Predict address before deployment (now includes payees and shares)
        address predictedAddress = factory.predictDeterministicAddressWithSalt(address(this), payees, shares, salt);

        // Create PaymentSplitter with salt
        address splitterAddress = factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt);

        // Verify predicted address matches actual
        assertEq(splitterAddress, predictedAddress, "Address should match prediction");

        // Verify splitter state
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.shares(alice), 60);
        assertEq(splitter.shares(bob), 40);
    }

    // Test that salt-based deployment is independent of deployment count
    function testSaltIndependentOfDeploymentCount() public {
        // Prepare payees and shares
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 fixedSalt = keccak256("governance-proposal-v1");

        // Predict address with salt BEFORE any deployments (includes payees and shares)
        address predictedWithSalt = factory.predictDeterministicAddressWithSalt(
            address(this),
            payees,
            shares,
            fixedSalt
        );

        // Deploy some splitters using the count-based method
        factory.createPaymentSplitter(payees, payeeNames, shares);
        factory.createPaymentSplitter(payees, payeeNames, shares);
        factory.createPaymentSplitter(payees, payeeNames, shares);

        // Verify count has changed
        assertEq(factory.getSplittersByDeployer(address(this)).length, 3);

        // Predict address with same salt AFTER deployments - should be unchanged
        address predictedWithSaltAfter = factory.predictDeterministicAddressWithSalt(
            address(this),
            payees,
            shares,
            fixedSalt
        );
        assertEq(predictedWithSaltAfter, predictedWithSalt, "Salt-based prediction should be independent of count");

        // Actually deploy with salt - should match original prediction
        address actualAddress = factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, fixedSalt);
        assertEq(actualAddress, predictedWithSalt, "Deployed address should match original prediction");
    }

    // Test that same salt cannot be used twice by same deployer
    function testCannotReuseSalt() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 salt = keccak256("unique-salt");

        // First deployment succeeds
        factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt);

        // Second deployment with same salt should fail (CREATE2 collision)
        vm.expectRevert();
        factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt);
    }

    // Test creating PaymentSplitter with ETH and explicit salt
    function testCreatePaymentSplitterWithETHAndSalt() public {
        address[] memory payees = new address[](2);
        payees[0] = alice;
        payees[1] = bob;

        string[] memory payeeNames = new string[](2);
        payeeNames[0] = "Recipient1";
        payeeNames[1] = "Recipient2";

        uint256[] memory shares = new uint256[](2);
        shares[0] = 70;
        shares[1] = 30;

        bytes32 salt = keccak256("eth-salt-test-v1");
        uint256 ethAmount = 5 ether;

        // Predict address before deployment
        address predictedAddress = factory.predictDeterministicAddressWithSalt(address(this), payees, shares, salt);

        // Create PaymentSplitter with ETH and salt
        address splitterAddress = factory.createPaymentSplitterWithETHAndSalt{ value: ethAmount }(
            payees,
            payeeNames,
            shares,
            salt
        );

        // Verify predicted address matches actual
        assertEq(splitterAddress, predictedAddress, "Address should match prediction");

        // Verify splitter state
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.shares(alice), 70);
        assertEq(splitter.shares(bob), 30);

        // Verify splitter received ETH
        assertEq(address(splitter).balance, ethAmount);

        // Verify releasable amounts
        assertEq(splitter.releasable(alice), (ethAmount * 70) / 100);
        assertEq(splitter.releasable(bob), (ethAmount * 30) / 100);
    }

    // Test that different deployers can use same salt
    function testDifferentDeployersCanUseSameSalt() public {
        address[] memory payees = new address[](1);
        payees[0] = charlie;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 salt = keccak256("shared-salt");

        // Deploy from this contract
        address addr1 = factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt);

        // Deploy from alice with same salt
        vm.prank(alice);
        address addr2 = factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt);

        // Addresses should be different (because deployer is part of final salt)
        assertTrue(addr1 != addr2, "Different deployers should get different addresses");
    }

    // Test PaymentSplitterCreatedWithSalt event emission
    function testEmitsPaymentSplitterCreatedWithSaltEvent() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 salt = keccak256("event-test-salt");

        // Predict address for event check
        address predictedAddress = factory.predictDeterministicAddressWithSalt(address(this), payees, shares, salt);

        // Expect the event with indexed salt
        vm.expectEmit(true, true, true, true);
        emit PaymentSplitterFactory.PaymentSplitterCreatedWithSalt(
            address(this),
            predictedAddress,
            salt,
            payees,
            payeeNames,
            shares
        );

        factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt);
    }

    // Test ETH+salt event emission
    function testEmitsPaymentSplitterCreatedWithSaltEventForETH() public {
        address[] memory payees = new address[](1);
        payees[0] = bob;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 salt = keccak256("eth-event-test-salt");
        uint256 ethAmount = 1 ether;

        address predictedAddress = factory.predictDeterministicAddressWithSalt(address(this), payees, shares, salt);

        vm.expectEmit(true, true, true, true);
        emit PaymentSplitterFactory.PaymentSplitterCreatedWithSalt(
            address(this),
            predictedAddress,
            salt,
            payees,
            payeeNames,
            shares
        );

        factory.createPaymentSplitterWithETHAndSalt{ value: ethAmount }(payees, payeeNames, shares, salt);
    }

    // Test ETH+salt cannot reuse same salt (CREATE2 collision)
    function testCannotReuseSaltWithETH() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 salt = keccak256("eth-unique-salt");

        // First deployment succeeds
        factory.createPaymentSplitterWithETHAndSalt{ value: 1 ether }(payees, payeeNames, shares, salt);

        // Second deployment with same salt should fail
        vm.expectRevert();
        factory.createPaymentSplitterWithETHAndSalt{ value: 1 ether }(payees, payeeNames, shares, salt);
    }

    // Test ETH+salt is independent of deployment count
    function testETHSaltIndependentOfDeploymentCount() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 fixedSalt = keccak256("eth-governance-v1");
        uint256 ethAmount = 2 ether;

        // Predict address BEFORE any deployments
        address predictedWithSalt = factory.predictDeterministicAddressWithSalt(
            address(this),
            payees,
            shares,
            fixedSalt
        );

        // Deploy some splitters using count-based methods
        factory.createPaymentSplitter(payees, payeeNames, shares);
        factory.createPaymentSplitterWithETH{ value: 0.1 ether }(payees, payeeNames, shares);

        // Prediction should be unchanged
        address predictedAfter = factory.predictDeterministicAddressWithSalt(address(this), payees, shares, fixedSalt);
        assertEq(predictedAfter, predictedWithSalt, "Prediction should not change");

        // Deploy with ETH+salt - should match original prediction
        address actual = factory.createPaymentSplitterWithETHAndSalt{ value: ethAmount }(
            payees,
            payeeNames,
            shares,
            fixedSalt
        );
        assertEq(actual, predictedWithSalt, "Should match original prediction");
        assertEq(address(actual).balance, ethAmount, "Should have ETH balance");
    }

    // Test ETH+salt length mismatch validation
    function testETHSaltLengthMismatchReverts() public {
        address[] memory payees = new address[](2);
        payees[0] = alice;
        payees[1] = bob;

        string[] memory payeeNames = new string[](1); // Mismatched length
        payeeNames[0] = "Recipient";

        uint256[] memory shares = new uint256[](2);
        shares[0] = 50;
        shares[1] = 50;

        bytes32 salt = keccak256("mismatch-test");

        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitterWithETHAndSalt{ value: 1 ether }(payees, payeeNames, shares, salt);
    }

    // Test ETH+salt with zero ETH (should work like regular salt version)
    function testETHSaltWithZeroETH() public {
        address[] memory payees = new address[](1);
        payees[0] = charlie;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 salt = keccak256("zero-eth-salt");

        address predictedAddress = factory.predictDeterministicAddressWithSalt(address(this), payees, shares, salt);

        // Deploy with 0 ETH
        address splitterAddress = factory.createPaymentSplitterWithETHAndSalt{ value: 0 }(
            payees,
            payeeNames,
            shares,
            salt
        );

        assertEq(splitterAddress, predictedAddress, "Address should match prediction");
        assertEq(address(splitterAddress).balance, 0, "Should have zero balance");
    }

    // Test that salt+ETH and salt-only use same address calculation
    function testSaltAndETHSaltUseSameAddressCalculation() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        bytes32 salt1 = keccak256("test-salt-1");
        bytes32 salt2 = keccak256("test-salt-2");

        // Deploy with salt (no ETH)
        address addr1 = factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt1);

        // Deploy with ETH+salt
        address addr2 = factory.createPaymentSplitterWithETHAndSalt{ value: 1 ether }(
            payees,
            payeeNames,
            shares,
            salt2
        );

        // Both should be tracked in deployer's splitters
        PaymentSplitterFactory.SplitterInfo[] memory splitters = factory.getSplittersByDeployer(address(this));
        assertEq(splitters.length, 2, "Should have 2 splitters");
        assertEq(splitters[0].splitterAddress, addr1);
        assertEq(splitters[1].splitterAddress, addr2);
    }

    // --- sweep tests ---

    function testSweep_Success() public {
        // Force-send ETH to the factory (simulating accidental send)
        vm.deal(address(factory), 1 ether);

        uint256 balanceBefore = alice.balance;
        factory.sweep(alice);
        assertEq(alice.balance, balanceBefore + 1 ether, "Alice should receive swept ETH");
        assertEq(address(factory).balance, 0, "Factory should have zero balance after sweep");
    }

    function testSweep_RevertIf_NotOwner() public {
        vm.deal(address(factory), 1 ether);

        vm.prank(alice);
        vm.expectRevert("PaymentSplitterFactory: not owner");
        factory.sweep(alice);
    }

    function testSweep_RevertIf_NoBalance() public {
        vm.expectRevert("PaymentSplitterFactory: no ETH to sweep");
        factory.sweep(alice);
    }

    // --- predictDeterministicAddress tests ---

    function testPredictDeterministicAddress_MatchesCreate() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        // Predict before deploying
        address predicted = factory.predictDeterministicAddress(address(this));

        // Deploy
        address actual = factory.createPaymentSplitter(payees, payeeNames, shares);

        assertEq(predicted, actual, "Predicted address should match actual deployment");
    }

    function testPredictDeterministicAddress_DifferentAfterDeploy() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        address predicted1 = factory.predictDeterministicAddress(address(this));
        factory.createPaymentSplitter(payees, payeeNames, shares);

        // After a deployment, the prediction for the same deployer should change
        // (because deployment count is part of the salt)
        address predicted2 = factory.predictDeterministicAddress(address(this));
        assertTrue(predicted1 != predicted2, "Prediction should change after deployment");
    }

    // --- length mismatch on createPaymentSplitterWithSalt ---

    function testCreatePaymentSplitterWithSalt_RevertIf_LengthMismatch() public {
        address[] memory payees = new address[](2);
        payees[0] = alice;
        payees[1] = bob;

        string[] memory payeeNames = new string[](1); // Mismatched
        payeeNames[0] = "Recipient";

        uint256[] memory shares = new uint256[](2);
        shares[0] = 50;
        shares[1] = 50;

        bytes32 salt = keccak256("mismatch-salt-test");

        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitterWithSalt(payees, payeeNames, shares, salt);
    }

    // --- length mismatch on createPaymentSplitterWithETH ---

    function testCreatePaymentSplitterWithETH_RevertIf_LengthMismatch() public {
        address[] memory payees = new address[](2);
        payees[0] = alice;
        payees[1] = bob;

        string[] memory payeeNames = new string[](1); // Mismatched
        payeeNames[0] = "Recipient";

        uint256[] memory shares = new uint256[](2);
        shares[0] = 50;
        shares[1] = 50;

        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitterWithETH{ value: 1 ether }(payees, payeeNames, shares);
    }

    // --- getSplittersByDeployer ---

    function testGetSplittersByDeployer_EmptyInitially() public view {
        PaymentSplitterFactory.SplitterInfo[] memory splitters = factory.getSplittersByDeployer(alice);
        assertEq(splitters.length, 0, "Should be empty initially");
    }

    // --- implementation is non-zero ---

    function testImplementation_IsSet() public view {
        assertTrue(factory.implementation() != address(0), "Implementation should be set");
    }

    // --- owner is set ---

    function testOwner_IsDeployer() public view {
        assertEq(factory.owner(), address(this), "Owner should be the deployer");
    }

    // --- PaymentSplitterCreated event emission ---

    function testEmitsPaymentSplitterCreatedEvent() public {
        address[] memory payees = new address[](1);
        payees[0] = alice;
        string[] memory payeeNames = new string[](1);
        payeeNames[0] = "Recipient";
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        address predicted = factory.predictDeterministicAddress(address(this));

        vm.expectEmit(true, true, false, true);
        emit PaymentSplitterFactory.PaymentSplitterCreated(address(this), predicted, payees, payeeNames, shares);

        factory.createPaymentSplitter(payees, payeeNames, shares);
    }

    // ========================================================
    //  Branch coverage: initialization failure paths
    // ========================================================

    /// @notice createPaymentSplitterWithETH reverts when initialization fails (empty payees)
    function testCreatePaymentSplitterWithETH_RevertIf_InitializationFails() public {
        address[] memory emptyPayees = new address[](0);
        string[] memory emptyNames = new string[](0);
        uint256[] memory emptyShares = new uint256[](0);

        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitterWithETH{ value: 1 ether }(emptyPayees, emptyNames, emptyShares);
    }

    /// @notice createPaymentSplitterWithSalt reverts when initialization fails (empty payees)
    function testCreatePaymentSplitterWithSalt_RevertIf_InitializationFails() public {
        address[] memory emptyPayees = new address[](0);
        string[] memory emptyNames = new string[](0);
        uint256[] memory emptyShares = new uint256[](0);
        bytes32 salt = keccak256("init-fail-salt");

        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitterWithSalt(emptyPayees, emptyNames, emptyShares, salt);
    }

    /// @notice createPaymentSplitterWithETHAndSalt reverts when initialization fails (empty payees)
    function testCreatePaymentSplitterWithETHAndSalt_RevertIf_InitializationFails() public {
        address[] memory emptyPayees = new address[](0);
        string[] memory emptyNames = new string[](0);
        uint256[] memory emptyShares = new uint256[](0);
        bytes32 salt = keccak256("init-fail-eth-salt");

        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitterWithETHAndSalt{ value: 1 ether }(emptyPayees, emptyNames, emptyShares, salt);
    }

    /// @notice sweep reverts when recipient cannot receive ETH
    function testSweep_RevertIf_RecipientRejectsETH() public {
        // Deploy a contract that rejects ETH
        EthRejecter rejecter = new EthRejecter();

        // Force-send ETH to the factory
        vm.deal(address(factory), 1 ether);

        vm.expectRevert("PaymentSplitterFactory: sweep failed");
        factory.sweep(payable(address(rejecter)));
    }

    // Helper function for receiving ETH
    receive() external payable {}
}

/// @notice Helper contract that rejects all ETH transfers
contract EthRejecter {
    // No receive or fallback - will revert on ETH transfer
}
