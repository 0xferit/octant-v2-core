// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { YearnV3Strategy } from "src/strategies/yieldDonating/YearnV3Strategy.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldDonating/MorphoCompounderStrategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Constructor validation unit tests for yield donating strategies
/// @notice Covers asset mismatch revert branches (YearnV3 line 79, MorphoCompounder line 80)
contract StrategyConstructorValidationTest is Test {
    ERC20Mock public asset;
    ERC20Mock public wrongAsset;
    address public fakeVault;
    YieldDonatingTokenizedStrategy public tokenizedStrategy;

    address management = address(0x1);
    address keeper = address(0x2);
    address emergencyAdmin = address(0x3);
    address donationAddress = address(0x4);

    function setUp() public {
        asset = new ERC20Mock();
        wrongAsset = new ERC20Mock();

        // Deploy the tokenized strategy implementation
        YieldDonatingTokenizedStrategy impl = new YieldDonatingTokenizedStrategy();
        tokenizedStrategy = YieldDonatingTokenizedStrategy(address(new ERC1967Proxy(address(impl), "")));

        // Create a fake vault that returns `asset` as its asset
        fakeVault = address(new MockVaultAsset(address(asset)));
    }

    /// @notice YearnV3Strategy constructor reverts on asset mismatch (line 79)
    function test_yearnV3_constructorAssetMismatch_reverts() public {
        vm.expectRevert("Asset mismatch with compounder vault");
        new YearnV3Strategy(
            fakeVault,
            address(wrongAsset), // Wrong asset - doesn't match fakeVault's asset
            "Test Yearn",
            "tsYearn",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(tokenizedStrategy)
        );
    }

    /// @notice MorphoCompounderStrategy constructor reverts on asset mismatch (line 80)
    function test_morphoCompounder_constructorAssetMismatch_reverts() public {
        vm.expectRevert("Asset mismatch with compounder vault");
        new MorphoCompounderStrategy(
            fakeVault,
            address(wrongAsset), // Wrong asset - doesn't match fakeVault's asset
            "Test Morpho",
            "tsMorpho",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(tokenizedStrategy)
        );
    }
}

/// @title Minimal mock that implements asset() to return a specified address
contract MockVaultAsset {
    address public asset;

    constructor(address _asset) {
        asset = _asset;
    }
}
