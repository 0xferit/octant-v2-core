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
    address payable public treasury = payable(address(0x4));

    uint256 public constant INITIAL_ETH_AMOUNT = 100 ether;
    uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;

    function setUp() public {
        // Setup test accounts with ETH
        vm.deal(alice, INITIAL_ETH_AMOUNT);
        vm.deal(bob, INITIAL_ETH_AMOUNT);
        vm.deal(charlie, INITIAL_ETH_AMOUNT);
        vm.deal(treasury, INITIAL_ETH_AMOUNT);
        vm.deal(address(this), INITIAL_ETH_AMOUNT);

        // Create mock ERC20 token for testing
        token = new MockERC20(18);
        token.mint(address(this), INITIAL_TOKEN_AMOUNT);
        token.mint(alice, INITIAL_TOKEN_AMOUNT);

        // Deploy factory
        factory = new PaymentSplitterFactory();
    }

    // Test complete flow: create splitter, add ETH, and release payments
    function testCompleteFlow() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "Alice";
        payeeNames[1] = "Bob";
        payeeNames[2] = "Charlie";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create PaymentSplitter
        address splitterAddress = factory.createPaymentSplitter(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Send ETH to the splitter
        uint256 ethAmount = 10 ether;
        (bool success, ) = address(splitter).call{ value: ethAmount }("");
        assertTrue(success);

        // Record balances before release
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;
        uint256 charlieBalanceBefore = charlie.balance;

        // Release payments
        splitter.release(alice);
        splitter.release(bob);
        splitter.release(charlie);

        // Calculate expected amounts
        uint256 aliceExpected = (ethAmount * 50) / 100;
        uint256 bobExpected = (ethAmount * 30) / 100;
        uint256 charlieExpected = (ethAmount * 20) / 100;

        // Verify balances after release
        assertEq(alice.balance, aliceBalanceBefore + aliceExpected);
        assertEq(bob.balance, bobBalanceBefore + bobExpected);
        assertEq(charlie.balance, charlieBalanceBefore + charlieExpected);

        // Verify contract balance is zero after all payments are released
        assertEq(address(splitter).balance, 0);
    }

    // Test creating a splitter with ETH and releasing immediately
    function testCreateWithEthAndRelease() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "Alice";
        payeeNames[1] = "Bob";
        payeeNames[2] = "Charlie";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        uint256 ethAmount = 10 ether;

        // Record balances before
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;
        uint256 charlieBalanceBefore = charlie.balance;

        // Create PaymentSplitter with ETH
        address splitterAddress = factory.createPaymentSplitterWithETH{ value: ethAmount }(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Release payments immediately
        splitter.release(alice);
        splitter.release(bob);
        splitter.release(charlie);

        // Calculate expected amounts
        uint256 aliceExpected = (ethAmount * 50) / 100;
        uint256 bobExpected = (ethAmount * 30) / 100;
        uint256 charlieExpected = (ethAmount * 20) / 100;

        // Verify balances after release
        assertEq(alice.balance, aliceBalanceBefore + aliceExpected);
        assertEq(bob.balance, bobBalanceBefore + bobExpected);
        assertEq(charlie.balance, charlieBalanceBefore + charlieExpected);
    }

    // Test creating multiple splitters with different configurations
    function testMultipleSplitters() public {
        // First splitter - simple 50/50 split
        address[] memory twoPayees = new address[](2);
        twoPayees[0] = alice;
        twoPayees[1] = bob;

        string[] memory twoPayeeNames = new string[](2);
        twoPayeeNames[0] = "Alice";
        twoPayeeNames[1] = "Bob";

        uint256[] memory twoShares = new uint256[](2);
        twoShares[0] = 50;
        twoShares[1] = 50;

        address splitter1Address = factory.createPaymentSplitter(twoPayees, twoPayeeNames, twoShares);

        // Second splitter - complex split with treasury
        address[] memory fourPayees = new address[](4);
        fourPayees[0] = alice;
        fourPayees[1] = bob;
        fourPayees[2] = charlie;
        fourPayees[3] = treasury;

        string[] memory fourPayeeNames = new string[](4);
        fourPayeeNames[0] = "Alice";
        fourPayeeNames[1] = "Bob";
        fourPayeeNames[2] = "Charlie";
        fourPayeeNames[3] = "Treasury";

        uint256[] memory fourShares = new uint256[](4);
        fourShares[0] = 30;
        fourShares[1] = 25;
        fourShares[2] = 15;
        fourShares[3] = 30; // Treasury gets 30%

        address splitter2Address = factory.createPaymentSplitter(fourPayees, fourPayeeNames, fourShares);

        // Verify both splitters were created with correct configuration
        PaymentSplitter splitter1 = PaymentSplitter(payable(splitter1Address));
        PaymentSplitter splitter2 = PaymentSplitter(payable(splitter2Address));

        // Check first splitter configuration
        assertEq(splitter1.totalShares(), 100);
        assertEq(splitter1.payee(0), alice);
        assertEq(splitter1.payee(1), bob);
        assertEq(splitter1.shares(alice), 50);
        assertEq(splitter1.shares(bob), 50);

        // Check second splitter configuration
        assertEq(splitter2.totalShares(), 100);
        assertEq(splitter2.payee(0), alice);
        assertEq(splitter2.payee(1), bob);
        assertEq(splitter2.payee(2), charlie);
        assertEq(splitter2.payee(3), treasury);
        assertEq(splitter2.shares(alice), 30);
        assertEq(splitter2.shares(bob), 25);
        assertEq(splitter2.shares(charlie), 15);
        assertEq(splitter2.shares(treasury), 30);

        // Test funding both splitters
        uint256 amount1 = 10 ether;
        uint256 amount2 = 20 ether;

        (bool success1, ) = splitter1Address.call{ value: amount1 }("");
        (bool success2, ) = splitter2Address.call{ value: amount2 }("");

        assertTrue(success1);
        assertTrue(success2);

        // Verify ETH balances in both splitters
        assertEq(address(splitter1).balance, amount1);
        assertEq(address(splitter2).balance, amount2);
    }

    // Test integration with ERC20 tokens and paymentSplitterFactory
    function testERC20Integration() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "Alice";
        payeeNames[1] = "Bob";
        payeeNames[2] = "Charlie";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create PaymentSplitter
        address splitterAddress = factory.createPaymentSplitter(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Send both ETH and tokens to the splitter
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 100e18;

        (bool success, ) = address(splitter).call{ value: ethAmount }("");
        assertTrue(success);

        token.transfer(address(splitter), tokenAmount);

        // Release ETH
        uint256 aliceEthBefore = alice.balance;
        splitter.release(alice);
        uint256 aliceEthExpected = (ethAmount * 50) / 100;
        assertEq(alice.balance, aliceEthBefore + aliceEthExpected);

        // Release tokens
        uint256 aliceTokenBefore = token.balanceOf(alice);
        splitter.release(IERC20(address(token)), alice);
        uint256 aliceTokenExpected = (tokenAmount * 50) / 100;
        assertEq(token.balanceOf(alice), aliceTokenBefore + aliceTokenExpected);

        // Verify total released
        assertEq(splitter.released(alice), aliceEthExpected);
        assertEq(splitter.released(IERC20(address(token)), alice), aliceTokenExpected);
    }

    // Test multiple payment rounds with different sources
    function testMultiplePaymentRounds() public {
        // Prepare payees and shares
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "Alice";
        payeeNames[1] = "Bob";
        payeeNames[2] = "Charlie";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create PaymentSplitter
        address splitterAddress = factory.createPaymentSplitterWithETH{ value: 5 ether }(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // First round: Alice claims her share from the initial funding
        uint256 aliceBalanceBefore1 = alice.balance;
        splitter.release(alice);
        uint256 aliceExpected1 = (5 ether * 50) / 100; // 2.5 ETH
        assertEq(alice.balance, aliceBalanceBefore1 + aliceExpected1);

        // Second round: Bob sends ETH directly to the splitter
        vm.prank(bob);
        (bool success1, ) = address(splitter).call{ value: 10 ether }("");
        assertTrue(success1);

        // Alice claims her share again
        uint256 aliceBalanceBefore2 = alice.balance;
        splitter.release(alice);
        uint256 aliceExpected2 = (10 ether * 50) / 100; // 5 ETH
        assertEq(alice.balance, aliceBalanceBefore2 + aliceExpected2);

        // Third round: Charlie sends ETH directly to the splitter
        vm.prank(charlie);
        (bool success2, ) = address(splitter).call{ value: 15 ether }("");
        assertTrue(success2);

        // Bob claims all his accumulated shares
        uint256 bobBalanceBefore = bob.balance;
        splitter.release(bob);
        uint256 bobExpected = ((5 ether + 10 ether + 15 ether) * 30) / 100; // 9 ETH
        assertEq(bob.balance, bobBalanceBefore + bobExpected);

        // Verify state after multiple rounds
        assertEq(splitter.released(alice), aliceExpected1 + aliceExpected2);
        assertEq(splitter.released(bob), bobExpected);

        // Charlie hasn't claimed yet
        assertEq(splitter.released(charlie), 0);
        assertEq(splitter.releasable(charlie), ((5 ether + 10 ether + 15 ether) * 20) / 100); // 6 ETH
    }

    // Test user behavior scenarios
    function testUserBehaviorScenarios() public {
        // Scenario: Creating a splitter to distribute revenue from a business

        // Revenue shares for team members
        address[] memory revenueRecipients = new address[](4);
        revenueRecipients[0] = alice; // CEO
        revenueRecipients[1] = bob; // CTO
        revenueRecipients[2] = charlie; // CFO
        revenueRecipients[3] = treasury; // Company reserve

        string[] memory revenuePayeeNames = new string[](4);
        revenuePayeeNames[0] = "CEO";
        revenuePayeeNames[1] = "CTO";
        revenuePayeeNames[2] = "CFO";
        revenuePayeeNames[3] = "CompanyReserve";

        uint256[] memory revenueShares = new uint256[](4);
        revenueShares[0] = 25; // 25% to CEO
        revenueShares[1] = 15; // 15% to CTO
        revenueShares[2] = 10; // 10% to CFO
        revenueShares[3] = 50; // 50% to company reserve

        // 2. Deploy the splitter using the factory
        address revenueSplitter = factory.createPaymentSplitter(revenueRecipients, revenuePayeeNames, revenueShares);

        // 3. Business receives payment (simulated by sending ETH)
        uint256 businessRevenue = 100 ether;
        (bool success, ) = revenueSplitter.call{ value: businessRevenue }("");
        assertTrue(success);

        // 4. Team members can withdraw their shares
        // CEO withdraws
        uint256 ceoBalanceBefore = alice.balance;
        vm.prank(alice);
        PaymentSplitter(payable(revenueSplitter)).release(alice);
        assertEq(alice.balance, ceoBalanceBefore + ((businessRevenue * 25) / 100));

        // CFO withdraws
        uint256 cfoBalanceBefore = charlie.balance;
        vm.prank(charlie);
        PaymentSplitter(payable(revenueSplitter)).release(charlie);
        assertEq(charlie.balance, cfoBalanceBefore + ((businessRevenue * 10) / 100));

        // 5. Business receives a token payment
        uint256 tokenRevenue = 1000e18;
        token.transfer(revenueSplitter, tokenRevenue);

        // 6. CTO withdraws both ETH and tokens
        uint256 ctoEthBefore = bob.balance;
        uint256 ctoTokenBefore = token.balanceOf(bob);

        vm.startPrank(bob);
        PaymentSplitter(payable(revenueSplitter)).release(bob);
        PaymentSplitter(payable(revenueSplitter)).release(IERC20(address(token)), bob);
        vm.stopPrank();

        assertEq(bob.balance, ctoEthBefore + ((businessRevenue * 15) / 100));
        assertEq(token.balanceOf(bob), ctoTokenBefore + ((tokenRevenue * 15) / 100));
    }

    // Test error handling and recovery
    function testErrorHandlingAndRecovery() public {
        // Create a splitter with invalid inputs to test error handling
        address[] memory payees = new address[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "Alice";
        payeeNames[1] = "Bob";
        payeeNames[2] = "Charlie";

        uint256[] memory shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create a valid splitter
        address splitterAddress = factory.createPaymentSplitter(payees, payeeNames, shares);
        PaymentSplitter splitter = PaymentSplitter(payable(splitterAddress));

        // Scenario: Try to release funds when there are none
        vm.expectRevert("PaymentSplitter: account is not due payment");
        splitter.release(alice);

        // Recover by adding funds and trying again
        (bool success, ) = address(splitter).call{ value: 10 ether }("");
        assertTrue(success);

        // Now should work
        uint256 aliceBalanceBefore = alice.balance;
        splitter.release(alice);
        assertEq(alice.balance, aliceBalanceBefore + 5 ether); // 50% of 10 ETH

        // Scenario: Non-payee tries to claim funds
        address nonPayee = address(0x999);
        vm.expectRevert("PaymentSplitter: account has no shares");
        splitter.release(payable(nonPayee));
    }

    receive() external payable {}
}
