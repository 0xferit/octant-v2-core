// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { DragonTokenizedStrategy } from "src/zodiac-core/vaults/DragonTokenizedStrategy.sol";
import { MockStrategy } from "test/mocks/zodiac-core/MockStrategy.sol";
import { MockYieldSource } from "test/mocks/core/MockYieldSource.sol";
import { BaseTest } from "test/unit/zodiac-core/Base.t.sol";
import { NATIVE_TOKEN } from "src/constants.sol";

contract MockStrategyWithDepositLimit is MockStrategy {
    uint256 public depositLimit;

    function setDepositLimit(uint256 limit) external {
        depositLimit = limit;
    }

    function availableDepositLimit(address) public view override returns (uint256) {
        return depositLimit;
    }
}

contract VAULT002_DepositLimitOffByOne is BaseTest {
    MockStrategyWithDepositLimit internal moduleImplementation;
    DragonTokenizedStrategy internal tokenizedStrategyImplementation;
    MockYieldSource internal yieldSource;
    DragonTokenizedStrategy internal module;
    testTemps internal temps;

    address internal operator;
    address internal management = makeAddr("management");
    address internal keeper = makeAddr("keeper");
    address internal dragonRouter = makeAddr("dragonRouter");
    address internal regenGovernance = makeAddr("regenGovernance");

    string internal name = "Test Mock Strategy";
    uint256 internal maxReportDelay = 9;

    function setUp() public {
        _configure(false, "");

        moduleImplementation = new MockStrategyWithDepositLimit();
        tokenizedStrategyImplementation = new DragonTokenizedStrategy();
        yieldSource = new MockYieldSource(NATIVE_TOKEN);

        temps = _testTemps(
            address(moduleImplementation),
            abi.encode(
                address(tokenizedStrategyImplementation),
                NATIVE_TOKEN,
                address(yieldSource),
                management,
                keeper,
                dragonRouter,
                maxReportDelay,
                name,
                regenGovernance
            )
        );

        module = DragonTokenizedStrategy(payable(temps.module));
        operator = temps.safe;
    }

    function test_deposit_AllowsAtMaxLimit() public {
        // Arrange
        uint256 limit = 1 ether;
        MockStrategyWithDepositLimit(payable(address(module))).setDepositLimit(limit);
        vm.deal(operator, limit);

        // Act
        vm.prank(operator);
        uint256 shares = module.deposit(limit, operator);

        // Assert
        assertEq(module.maxDeposit(operator), limit);
        assertEq(shares, module.balanceOf(operator));
        assertGt(shares, 0, "shares should be minted");
    }

    function test_mint_AllowsAtMaxLimit() public {
        // Arrange
        uint256 limit = 1 ether;
        MockStrategyWithDepositLimit(payable(address(module))).setDepositLimit(limit);

        uint256 maxShares = module.maxMint(operator);
        uint256 assets = module.previewMint(maxShares);
        vm.deal(operator, assets);

        // Act
        vm.prank(operator);
        uint256 assetsSpent = module.mint(maxShares, operator);

        // Assert
        assertEq(module.maxMint(operator), maxShares);
        assertEq(assetsSpent, assets);
        assertEq(module.balanceOf(operator), maxShares);
    }
}
