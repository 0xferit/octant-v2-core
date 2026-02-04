// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MultistrategyVault } from "src/core/MultistrategyVault.sol";
import { MultistrategyVaultFactory } from "src/factories/MultistrategyVaultFactory.sol";

contract VAULT005_VaultPermitDomainMismatch is Test {
    MockERC20 asset;
    MultistrategyVault vault;
    MultistrategyVaultFactory vaultFactory;
    MultistrategyVault vaultImplementation;

    uint256 ownerPk;
    address owner;
    address spender;
    address roleManager;

    bytes32 constant EIP712DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        ownerPk = 0xA11CE;
        owner = vm.addr(ownerPk);
        spender = address(0xBEEF);
        roleManager = address(0xCAFE);

        asset = new MockERC20(18);
        vaultImplementation = new MultistrategyVault();
        vaultFactory = new MultistrategyVaultFactory("Test Factory", address(vaultImplementation), roleManager);
        vault = MultistrategyVault(
            vaultFactory.deployNewVault(address(asset), "Octant Test Vault", "oTV", roleManager, 7 days)
        );
    }

    function _signWithDomain(
        bytes32 domainSeparator,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8, bytes32, bytes32) {
        uint256 nonce = vault.nonces(owner);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        return vm.sign(ownerPk, digest);
    }

    function test_permit_AllowsSignatureUsingTokenNameDomain() external {
        // Arrange
        uint256 value = 1e18;
        uint256 deadline = block.timestamp + 1 days;

        bytes32 nameHash = keccak256(bytes(vault.name()));
        bytes32 versionHash = keccak256(bytes(vault.API_VERSION()));
        bytes32 domainSeparator = keccak256(
            abi.encode(EIP712DOMAIN_TYPEHASH, nameHash, versionHash, block.chainid, address(vault))
        );
        assertEq(vault.DOMAIN_SEPARATOR(), domainSeparator);

        // Act
        (uint8 v, bytes32 r, bytes32 s) = _signWithDomain(domainSeparator, value, deadline);
        vault.permit(owner, spender, value, deadline, v, r, s);

        // Assert
        assertEq(vault.allowance(owner, spender), value);
    }
}
