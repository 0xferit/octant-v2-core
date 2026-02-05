// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { Setup } from "./utils/Setup.sol";
import { TokenizedStrategy } from "src/core/TokenizedStrategy.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PermitTest is Setup {
    uint256 constant AMOUNT = 10 ** 18;
    uint256 constant PRIVATE_KEY = 0xabcd; // Known private key for tests
    bytes32 constant EIP712DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address public spender;

    function setUp() public override {
        super.setUp();
        spender = address(0x1234);
        vm.label(spender, "spender");
    }

    function testPermit() public {
        address owner = vm.addr(PRIVATE_KEY);
        uint256 deadline = block.timestamp + 3600;

        assertEq(strategy.allowance(owner, spender), 0);

        bytes32 digest = _getPermitDigest(address(strategy), owner, spender, AMOUNT, strategy.nonces(owner), deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);

        vm.prank(spender);
        strategy.permit(owner, spender, AMOUNT, deadline, v, r, s);

        assertEq(strategy.allowance(owner, spender), AMOUNT);
    }

    function testDomainSeparatorUsesStrategyName() public view {
        bytes32 nameHash = keccak256(bytes(strategy.name()));
        bytes32 versionHash = keccak256(bytes(strategy.apiVersion()));
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(EIP712DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(strategy))
        );

        assertEq(strategy.DOMAIN_SEPARATOR(), expectedDomainSeparator);
    }

    function testDomainSeparatorUpdatesOnNameChange() public {
        bytes32 originalDomainSeparator = strategy.DOMAIN_SEPARATOR();

        // Change name
        string memory newName = "New Strategy Name";
        vm.prank(management);
        strategy.setName(newName);

        // Verify domain separator changed
        bytes32 newDomainSeparator = strategy.DOMAIN_SEPARATOR();
        assertTrue(newDomainSeparator != originalDomainSeparator, "Domain separator should change with name");

        // Verify new domain separator matches expected value
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(bytes(newName)),
                keccak256(bytes(strategy.apiVersion())),
                block.chainid,
                address(strategy)
            )
        );
        assertEq(newDomainSeparator, expectedDomainSeparator, "Domain separator should use new name");
    }

    function testPermitInvalidatedAfterNameChange() public {
        address owner = vm.addr(PRIVATE_KEY);
        uint256 deadline = block.timestamp + 3600;

        // Sign permit with original name
        bytes32 digest = _getPermitDigest(address(strategy), owner, spender, AMOUNT, strategy.nonces(owner), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);

        // Change name before using permit
        vm.prank(management);
        strategy.setName("New Name");

        // Old permit should fail (wrong domain separator)
        vm.expectRevert();
        vm.prank(spender);
        strategy.permit(owner, spender, AMOUNT, deadline, v, r, s);
    }

    function testPermitWorksAfterNameChange() public {
        // Change name first
        vm.prank(management);
        strategy.setName("New Name");

        address owner = vm.addr(PRIVATE_KEY);
        uint256 deadline = block.timestamp + 3600;

        // Sign permit with new domain separator
        bytes32 digest = _getPermitDigest(address(strategy), owner, spender, AMOUNT, strategy.nonces(owner), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);

        // Permit should work
        vm.prank(spender);
        strategy.permit(owner, spender, AMOUNT, deadline, v, r, s);

        assertEq(strategy.allowance(owner, spender), AMOUNT);
    }

    function testPermitWithUsedPermit() public {
        address owner = vm.addr(PRIVATE_KEY);
        uint256 deadline = block.timestamp + 3600;

        bytes32 digest = _getPermitDigest(address(strategy), owner, spender, AMOUNT, strategy.nonces(owner), deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);

        vm.prank(spender);
        strategy.permit(owner, spender, AMOUNT, deadline, v, r, s);

        vm.expectRevert();
        vm.prank(spender);
        strategy.permit(owner, spender, AMOUNT, deadline, v, r, s);
    }

    function testPermitWithExpiredDeadline() public {
        // Set block timestamp to 1000
        vm.warp(1000);

        address owner = vm.addr(PRIVATE_KEY);
        uint256 deadline = block.timestamp - 600; // Expired deadline

        bytes32 digest = _getPermitDigest(address(strategy), owner, spender, AMOUNT, strategy.nonces(owner), deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);

        vm.expectRevert("ERC20: PERMIT_DEADLINE_EXPIRED");
        vm.prank(spender);
        strategy.permit(owner, spender, AMOUNT, deadline, v, r, s);
    }

    // Helper function to generate permit digest according to EIP-712
    function _getPermitDigest(
        address token,
        address owner,
        address _spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, _spender, value, nonce, deadline));

        return keccak256(abi.encodePacked("\x19\x01", TokenizedStrategy(token).DOMAIN_SEPARATOR(), structHash));
    }
}
