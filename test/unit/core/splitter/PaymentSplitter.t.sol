// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { PaymentSplitter } from "src/core/PaymentSplitter.sol";
import { PaymentSplitterFactory } from "src/factories/PaymentSplitterFactory.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract PaymentSplitterTest is Test {
    PaymentSplitter public splitter;
    MockERC20 public token;

    address[] public payees;
    uint256[] public shares;

    // Test accounts
    address payable public alice = payable(address(0x1));
    address payable public bob = payable(address(0x2));
    address payable public charlie = payable(address(0x3));
    address payable public nonPayee = payable(address(0x4));

    uint256 public constant INITIAL_ETH_AMOUNT = 100 ether;
    uint256 public constant INITIAL_TOKEN_AMOUNT = 1000e18;

    function setUp() public {
        // Setup test accounts with ETH
        vm.deal(alice, INITIAL_ETH_AMOUNT);
        vm.deal(bob, INITIAL_ETH_AMOUNT);
        vm.deal(charlie, INITIAL_ETH_AMOUNT);

        // Create payee names
        string[] memory payeeNames = new string[](3);
        payeeNames[0] = "GrantRoundOperator";
        payeeNames[1] = "ESF";
        payeeNames[2] = "OpEx";

        // Create payees and shares arrays
        payees = new address payable[](3);
        payees[0] = alice;
        payees[1] = bob;
        payees[2] = charlie;

        shares = new uint256[](3);
        shares[0] = 50;
        shares[1] = 30;
        shares[2] = 20;

        // Create mock ERC20 token for testing
        token = new MockERC20(18);
        token.mint(address(this), INITIAL_TOKEN_AMOUNT);

        // payment splitter factory
        PaymentSplitterFactory splitterFactory = new PaymentSplitterFactory();

        // Deploy PaymentSplitter
        splitter = PaymentSplitter(payable(splitterFactory.createPaymentSplitter(payees, payeeNames, shares)));
    }

    function _convertToAddressArray(address payable[] memory _payees) internal pure returns (address[] memory) {
        address[] memory result = new address[](_payees.length);
        for (uint256 i = 0; i < _payees.length; i++) {
            result[i] = _payees[i];
        }
        return result;
    }

    // Test constructor and initial state
    function testInitialState() public view {
        assertEq(splitter.totalShares(), 100);
        assertEq(splitter.payee(0), alice);
        assertEq(splitter.payee(1), bob);
        assertEq(splitter.payee(2), charlie);
        assertEq(splitter.shares(alice), 50);
        assertEq(splitter.shares(bob), 30);
        assertEq(splitter.shares(charlie), 20);
    }

    // Test initialization validation
    function testInitializeValidation() public {
        // Create a new factory for testing
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        // Test unequal arrays (payees and shares)
        address[] memory _payees = new address[](2);
        _payees[0] = alice;
        _payees[1] = bob;

        string[] memory _payeeNames = new string[](2);
        _payeeNames[0] = "Alice";
        _payeeNames[1] = "Bob";

        uint256[] memory _shares = new uint256[](3);
        _shares[0] = 50;
        _shares[1] = 30;
        _shares[2] = 20;

        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitter(_payees, _payeeNames, _shares);

        // Test empty arrays
        address[] memory emptyPayees = new address[](0);
        string[] memory emptyNames = new string[](0);
        uint256[] memory emptyShares = new uint256[](0);

        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitter(emptyPayees, emptyNames, emptyShares);

        // Test zero address payee
        address[] memory zeroAddressPayees = new address[](3);
        zeroAddressPayees[0] = alice;
        zeroAddressPayees[1] = address(0);
        zeroAddressPayees[2] = charlie;

        string[] memory zeroAddressNames = new string[](3);
        zeroAddressNames[0] = "Alice";
        zeroAddressNames[1] = "Zero";
        zeroAddressNames[2] = "Charlie";

        uint256[] memory validShares = new uint256[](3);
        validShares[0] = 50;
        validShares[1] = 30;
        validShares[2] = 20;

        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitter(zeroAddressPayees, zeroAddressNames, validShares);

        // Test zero shares
        address[] memory validPayees = new address[](3);
        validPayees[0] = alice;
        validPayees[1] = bob;
        validPayees[2] = charlie;

        string[] memory validNames = new string[](3);
        validNames[0] = "Alice";
        validNames[1] = "Bob";
        validNames[2] = "Charlie";

        uint256[] memory zeroShares = new uint256[](3);
        zeroShares[0] = 50;
        zeroShares[1] = 0;
        zeroShares[2] = 20;

        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitter(validPayees, validNames, zeroShares);

        // Test duplicate payees
        address[] memory duplicatePayees = new address[](3);
        duplicatePayees[0] = alice;
        duplicatePayees[1] = alice; // Duplicate
        duplicatePayees[2] = charlie;

        vm.expectRevert("PaymentSplitterFactory: initialization failed");
        factory.createPaymentSplitter(duplicatePayees, validNames, validShares);
    }

    // Test receiving ETH
    function testReceiveEth() public {
        uint256 amount = 1 ether;

        // Send ETH to the contract
        (bool success, ) = address(splitter).call{ value: amount }("");
        assertTrue(success);

        assertEq(address(splitter).balance, amount);
    }

    // Test ETH release
    function testReleaseEth() public {
        uint256 amount = 100 ether;

        // Send ETH to the contract
        (bool success, ) = address(splitter).call{ value: amount }("");
        assertTrue(success);

        // Check initial state
        assertEq(address(splitter).balance, amount);

        // Calculate expected amounts
        uint256 aliceExpected = (amount * 50) / 100;
        uint256 bobExpected = (amount * 30) / 100;
        uint256 charlieExpected = (amount * 20) / 100;

        // Check releasable amounts
        assertEq(splitter.releasable(alice), aliceExpected);
        assertEq(splitter.releasable(bob), bobExpected);
        assertEq(splitter.releasable(charlie), charlieExpected);

        // Release to Alice
        uint256 aliceBalanceBefore = alice.balance;
        splitter.release(alice);
        assertEq(alice.balance, aliceBalanceBefore + aliceExpected);
        assertEq(splitter.releasable(alice), 0);
        assertEq(splitter.released(alice), aliceExpected);

        // Release to Bob
        uint256 bobBalanceBefore = bob.balance;
        splitter.release(bob);
        assertEq(bob.balance, bobBalanceBefore + bobExpected);
        assertEq(splitter.releasable(bob), 0);
        assertEq(splitter.released(bob), bobExpected);

        // Release to Charlie
        uint256 charlieBalanceBefore = charlie.balance;
        splitter.release(charlie);
        assertEq(charlie.balance, charlieBalanceBefore + charlieExpected);
        assertEq(splitter.releasable(charlie), 0);
        assertEq(splitter.released(charlie), charlieExpected);

        // Verify total released
        assertEq(splitter.totalReleased(), amount);
    }

    // Test releasing to non-payee
    function testReleaseToNonPayee() public {
        uint256 amount = 1 ether;
        (bool success, ) = address(splitter).call{ value: amount }("");
        assertTrue(success);

        vm.expectRevert("PaymentSplitter: account has no shares");
        splitter.release(nonPayee);
    }

    // Test releasing when no payment is due
    function testReleaseWhenNoDue() public {
        vm.expectRevert("PaymentSplitter: account is not due payment");
        splitter.release(alice);
    }

    // Test ERC20 token release
    function testReleaseToken() public {
        uint256 amount = 100e18;

        // Send tokens to the contract
        token.transfer(address(splitter), amount);

        // Check initial state
        assertEq(token.balanceOf(address(splitter)), amount);

        // Calculate expected amounts
        uint256 aliceExpected = (amount * 50) / 100;
        uint256 bobExpected = (amount * 30) / 100;
        uint256 charlieExpected = (amount * 20) / 100;

        // Check releasable amounts
        assertEq(splitter.releasable(IERC20(address(token)), alice), aliceExpected);
        assertEq(splitter.releasable(IERC20(address(token)), bob), bobExpected);
        assertEq(splitter.releasable(IERC20(address(token)), charlie), charlieExpected);

        // Release tokens to Alice
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        splitter.release(IERC20(address(token)), alice);
        assertEq(token.balanceOf(alice), aliceBalanceBefore + aliceExpected);
        assertEq(splitter.releasable(IERC20(address(token)), alice), 0);
        assertEq(splitter.released(IERC20(address(token)), alice), aliceExpected);

        // Release tokens to Bob
        uint256 bobBalanceBefore = token.balanceOf(bob);
        splitter.release(IERC20(address(token)), bob);
        assertEq(token.balanceOf(bob), bobBalanceBefore + bobExpected);
        assertEq(splitter.releasable(IERC20(address(token)), bob), 0);
        assertEq(splitter.released(IERC20(address(token)), bob), bobExpected);

        // Release tokens to Charlie
        uint256 charlieBalanceBefore = token.balanceOf(charlie);
        splitter.release(IERC20(address(token)), charlie);
        assertEq(token.balanceOf(charlie), charlieBalanceBefore + charlieExpected);
        assertEq(splitter.releasable(IERC20(address(token)), charlie), 0);
        assertEq(splitter.released(IERC20(address(token)), charlie), charlieExpected);

        // Verify total released
        assertEq(splitter.totalReleased(IERC20(address(token))), amount);
    }

    // Test multiple payment rounds
    function testMultiplePayments() public {
        uint256 firstAmount = 100 ether;
        uint256 secondAmount = 50 ether;

        // First payment
        (bool success1, ) = address(splitter).call{ value: firstAmount }("");
        assertTrue(success1);

        // Release to Alice
        uint256 aliceExpected1 = (firstAmount * 50) / 100;
        uint256 aliceBalanceBefore1 = alice.balance;
        splitter.release(alice);
        assertEq(alice.balance, aliceBalanceBefore1 + aliceExpected1);

        // Second payment
        (bool success2, ) = address(splitter).call{ value: secondAmount }("");
        assertTrue(success2);

        // Release to Alice again
        uint256 aliceExpected2 = (secondAmount * 50) / 100;
        uint256 aliceBalanceBefore2 = alice.balance;
        splitter.release(alice);
        assertEq(alice.balance, aliceBalanceBefore2 + aliceExpected2);

        // Check total released for Alice
        assertEq(splitter.released(alice), aliceExpected1 + aliceExpected2);
    }

    // Test ERC20 token release to non-payee reverts
    function testReleaseTokenToNonPayee() public {
        uint256 amount = 100e18;
        token.transfer(address(splitter), amount);

        vm.expectRevert("PaymentSplitter: account has no shares");
        splitter.release(IERC20(address(token)), nonPayee);
    }

    // Test ERC20 token release when no payment is due
    function testReleaseTokenWhenNoDue() public {
        // No tokens sent to splitter, so releasable is 0 for all payees
        vm.expectRevert("PaymentSplitter: account is not due payment");
        splitter.release(IERC20(address(token)), alice);
    }

    // Test for events
    function testEvents() public {
        uint256 amount = 1 ether;

        // Test PaymentReceived event
        vm.expectEmit(true, true, true, true);
        emit PaymentSplitter.PaymentReceived(address(this), amount);
        (bool success, ) = address(splitter).call{ value: amount }("");
        assertTrue(success);

        // Test PaymentReleased event
        uint256 aliceExpected = (amount * 50) / 100;
        vm.expectEmit(true, true, true, true);
        emit PaymentSplitter.PaymentReleased(alice, aliceExpected);
        splitter.release(alice);

        // Test ERC20PaymentReleased event
        uint256 tokenAmount = 100e18;
        token.transfer(address(splitter), tokenAmount);
        uint256 bobExpected = (tokenAmount * 30) / 100;
        vm.expectEmit(true, true, true, true);
        emit PaymentSplitter.ERC20PaymentReleased(IERC20(address(token)), bob, bobExpected);
        splitter.release(IERC20(address(token)), bob);
    }

    // Test PaymentSplitterFactory: createPaymentSplitterWithETH
    function testCreatePaymentSplitterWithETH() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address[] memory _payees = new address[](2);
        _payees[0] = alice;
        _payees[1] = bob;

        string[] memory _payeeNames = new string[](2);
        _payeeNames[0] = "Alice";
        _payeeNames[1] = "Bob";

        uint256[] memory _shares = new uint256[](2);
        _shares[0] = 60;
        _shares[1] = 40;

        address newSplitter = factory.createPaymentSplitterWithETH{ value: 1 ether }(_payees, _payeeNames, _shares);
        assertTrue(newSplitter != address(0));
        assertEq(address(newSplitter).balance, 1 ether);
    }

    // Test PaymentSplitterFactory: createPaymentSplitterWithSalt
    function testCreatePaymentSplitterWithSalt() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address[] memory _payees = new address[](2);
        _payees[0] = alice;
        _payees[1] = bob;

        string[] memory _payeeNames = new string[](2);
        _payeeNames[0] = "Alice";
        _payeeNames[1] = "Bob";

        uint256[] memory _shares = new uint256[](2);
        _shares[0] = 60;
        _shares[1] = 40;

        bytes32 salt = keccak256("my-salt");
        address newSplitter = factory.createPaymentSplitterWithSalt(_payees, _payeeNames, _shares, salt);
        assertTrue(newSplitter != address(0));

        // Predict and verify
        address predicted = factory.predictDeterministicAddressWithSalt(address(this), _payees, _shares, salt);
        assertEq(newSplitter, predicted);
    }

    // Test PaymentSplitterFactory: createPaymentSplitterWithETHAndSalt
    function testCreatePaymentSplitterWithETHAndSalt() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address[] memory _payees = new address[](2);
        _payees[0] = alice;
        _payees[1] = bob;

        string[] memory _payeeNames = new string[](2);
        _payeeNames[0] = "Alice";
        _payeeNames[1] = "Bob";

        uint256[] memory _shares = new uint256[](2);
        _shares[0] = 60;
        _shares[1] = 40;

        bytes32 salt = keccak256("eth-salt");
        address newSplitter = factory.createPaymentSplitterWithETHAndSalt{ value: 1 ether }(
            _payees,
            _payeeNames,
            _shares,
            salt
        );
        assertTrue(newSplitter != address(0));
        assertEq(address(newSplitter).balance, 1 ether);
    }

    // Test PaymentSplitterFactory: predictDeterministicAddress
    function testPredictDeterministicAddress() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address predicted = factory.predictDeterministicAddress(address(this));
        assertTrue(predicted != address(0));

        // Deploy and compare
        address[] memory _payees = new address[](1);
        _payees[0] = alice;
        string[] memory _payeeNames = new string[](1);
        _payeeNames[0] = "Alice";
        uint256[] memory _shares = new uint256[](1);
        _shares[0] = 100;

        address actual = factory.createPaymentSplitter(_payees, _payeeNames, _shares);
        assertEq(actual, predicted);
    }

    // Test PaymentSplitterFactory: getSplittersByDeployer
    function testGetSplittersByDeployer() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address[] memory _payees = new address[](1);
        _payees[0] = alice;
        string[] memory _payeeNames = new string[](1);
        _payeeNames[0] = "Alice";
        uint256[] memory _shares = new uint256[](1);
        _shares[0] = 100;

        factory.createPaymentSplitter(_payees, _payeeNames, _shares);

        PaymentSplitterFactory.SplitterInfo[] memory splitters = factory.getSplittersByDeployer(address(this));
        assertEq(splitters.length, 1);
        assertEq(splitters[0].payees[0], alice);
    }

    // Test PaymentSplitterFactory: sweep
    function testSweep() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        // Force some ETH to the factory
        vm.deal(address(factory), 1 ether);

        uint256 balBefore = address(alice).balance;
        factory.sweep(alice);
        assertEq(address(alice).balance, balBefore + 1 ether);
    }

    // Test PaymentSplitterFactory: sweep with no ETH reverts
    function testSweepNoEthReverts() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        vm.expectRevert("PaymentSplitterFactory: no ETH to sweep");
        factory.sweep(alice);
    }

    // Test PaymentSplitterFactory: sweep not owner reverts
    function testSweepNotOwnerReverts() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();
        vm.deal(address(factory), 1 ether);

        vm.prank(alice);
        vm.expectRevert("PaymentSplitterFactory: not owner");
        factory.sweep(alice);
    }

    // Test PaymentSplitterFactory: length mismatch on createPaymentSplitterWithSalt
    function testCreateWithSaltLengthMismatchReverts() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address[] memory _payees = new address[](2);
        _payees[0] = alice;
        _payees[1] = bob;

        string[] memory _payeeNames = new string[](2);
        _payeeNames[0] = "Alice";
        _payeeNames[1] = "Bob";

        uint256[] memory _shares = new uint256[](1);
        _shares[0] = 100;

        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitterWithSalt(_payees, _payeeNames, _shares, bytes32(0));
    }

    // Test PaymentSplitterFactory: length mismatch on createPaymentSplitterWithETH
    function testCreateWithETHLengthMismatchReverts() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address[] memory _payees = new address[](2);
        _payees[0] = alice;
        _payees[1] = bob;

        string[] memory _payeeNames = new string[](2);
        _payeeNames[0] = "Alice";
        _payeeNames[1] = "Bob";

        uint256[] memory _shares = new uint256[](1);
        _shares[0] = 100;

        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitterWithETH{ value: 0 }(_payees, _payeeNames, _shares);
    }

    // Test PaymentSplitterFactory: length mismatch on createPaymentSplitterWithETHAndSalt
    function testCreateWithETHAndSaltLengthMismatchReverts() public {
        PaymentSplitterFactory factory = new PaymentSplitterFactory();

        address[] memory _payees = new address[](2);
        _payees[0] = alice;
        _payees[1] = bob;

        string[] memory _payeeNames = new string[](2);
        _payeeNames[0] = "Alice";
        _payeeNames[1] = "Bob";

        uint256[] memory _shares = new uint256[](1);
        _shares[0] = 100;

        vm.expectRevert("PaymentSplitterFactory: length mismatch");
        factory.createPaymentSplitterWithETHAndSalt{ value: 0 }(_payees, _payeeNames, _shares, bytes32(0));
    }
}

/// @title PaymentSplitter _addPayee Branch Coverage
/// @notice Tests duplicate account check directly on PaymentSplitter.initialize
///         Uses Clones.clone() to create uninitialized proxies (new PaymentSplitter() auto-locks initializer)
contract PaymentSplitterAddPayeeBranchTest is Test {
    PaymentSplitter implementation;

    function setUp() public {
        implementation = new PaymentSplitter();
    }

    function _createProxy() internal returns (PaymentSplitter) {
        address proxy = Clones.clone(address(implementation));
        return PaymentSplitter(payable(proxy));
    }

    // ===== _addPayee: duplicate account reverts =====
    function test_initialize_duplicatePayee_reverts() public {
        PaymentSplitter ps = _createProxy();

        address[] memory dupePayees = new address[](3);
        dupePayees[0] = address(0x1);
        dupePayees[1] = address(0x1); // Duplicate
        dupePayees[2] = address(0x3);

        uint256[] memory dupeShares = new uint256[](3);
        dupeShares[0] = 50;
        dupeShares[1] = 30;
        dupeShares[2] = 20;

        vm.expectRevert("PaymentSplitter: account already has shares");
        ps.initialize(dupePayees, dupeShares);
    }

    // ===== _addPayee: zero address reverts =====
    function test_initialize_zeroAddress_reverts() public {
        PaymentSplitter ps = _createProxy();

        address[] memory zeroPayees = new address[](2);
        zeroPayees[0] = address(0);
        zeroPayees[1] = address(0x2);

        uint256[] memory validShares = new uint256[](2);
        validShares[0] = 50;
        validShares[1] = 50;

        vm.expectRevert("PaymentSplitter: account is the zero address");
        ps.initialize(zeroPayees, validShares);
    }

    // ===== _addPayee: zero shares reverts =====
    function test_initialize_zeroShares_reverts() public {
        PaymentSplitter ps = _createProxy();

        address[] memory validPayees = new address[](2);
        validPayees[0] = address(0x1);
        validPayees[1] = address(0x2);

        uint256[] memory zeroShares = new uint256[](2);
        zeroShares[0] = 50;
        zeroShares[1] = 0;

        vm.expectRevert("PaymentSplitter: shares are 0");
        ps.initialize(validPayees, zeroShares);
    }

    // ===== initialize: empty arrays reverts =====
    function test_initialize_emptyArrays_reverts() public {
        PaymentSplitter ps = _createProxy();

        address[] memory emptyPayees = new address[](0);
        uint256[] memory emptyShares = new uint256[](0);

        vm.expectRevert("PaymentSplitter: no payees");
        ps.initialize(emptyPayees, emptyShares);
    }

    // ===== initialize: length mismatch reverts =====
    function test_initialize_lengthMismatch_reverts() public {
        PaymentSplitter ps = _createProxy();

        address[] memory twoPayees = new address[](2);
        twoPayees[0] = address(0x1);
        twoPayees[1] = address(0x2);

        uint256[] memory oneShare = new uint256[](1);
        oneShare[0] = 100;

        vm.expectRevert("PaymentSplitter: payees and shares length mismatch");
        ps.initialize(twoPayees, oneShare);
    }
}
