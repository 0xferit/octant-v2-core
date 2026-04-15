// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { BaseYieldSkimmingStrategy } from "src/strategies/yieldSkimming/BaseYieldSkimmingStrategy.sol";
import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { IYieldSkimmingStrategy } from "src/strategies/yieldSkimming/IYieldSkimmingStrategy.sol";

/// @dev Concrete strategy mirroring the pattern in YieldSkimmingStaleDragonBurn tests.
contract TestYieldSkimmingStrategyForDebtSub is BaseYieldSkimmingStrategy {
    uint256 private _rate;

    constructor(
        address _asset,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseYieldSkimmingStrategy(
            _asset,
            "Test YieldSkim",
            "tsYS",
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        _rate = 1e18;
    }

    function setExchangeRate(uint256 newRate) external {
        _rate = newRate;
    }

    function _getCurrentExchangeRate() internal view override returns (uint256) {
        return _rate;
    }

    function decimalsOfExchangeRate() public pure override returns (uint256) {
        return 18;
    }
}

/// @notice Bailsec #39 — `_handleDragonLossProtection` previously used a raw
///         subtraction `YS.dragonRouterDebtInAssetValue -= dragonBurn`. If
///         `dragonBalance` ever exceeded `dragonRouterDebtInAssetValue` (drift
///         from rebasing tokens, future code paths, or storage manipulation),
///         the burn would underflow and brick loss protection. The fix mirrors
///         the saturating pattern already used in redeem/withdraw.
contract YieldSkimmingDragonDebtSubtractionTest is Test {
    TestYieldSkimmingStrategyForDebtSub internal strategy;
    ERC20Mock internal asset;

    address internal management = address(0x1);
    address internal keeper = address(0x2);
    address internal emergencyAdmin = address(0x3);
    address internal dragonRouter = address(0x4);
    address internal alice = address(0xA);

    ITokenizedStrategy internal tokenized;
    YieldSkimmingTokenizedStrategy internal ys;

    /// @dev ERC-7201 namespaced slot for YieldSkimmingStorage; field offsets:
    ///        slot+0 totalDebtOwedToUserInAssetValue
    ///        slot+1 lastReportedRate
    ///        slot+2 dragonRouterDebtInAssetValue
    bytes32 internal constant YS_SLOT =
        keccak256(abi.encode(uint256(keccak256("octant.yieldSkimming.exchangeRate")) - 1)) & ~bytes32(uint256(0xff));

    function setUp() public {
        asset = new ERC20Mock();
        YieldSkimmingTokenizedStrategy implementation = new YieldSkimmingTokenizedStrategy();
        strategy = new TestYieldSkimmingStrategyForDebtSub(
            address(asset),
            management,
            keeper,
            emergencyAdmin,
            dragonRouter,
            true, // enableBurning
            address(implementation)
        );
        tokenized = ITokenizedStrategy(address(strategy));
        ys = YieldSkimmingTokenizedStrategy(address(strategy));

        vm.prank(management);
        strategy.setLossLimitRatio(9999);
    }

    function _depositUser(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.prank(user);
        asset.approve(address(strategy), amount);
        vm.prank(user);
        tokenized.deposit(amount, user);
    }

    /// @notice Simulate accounting drift where dragon balance > dragon debt, then
    ///         trigger a loss whose burn amount exceeds the (corrupted) debt. The
    ///         saturating subtraction should keep the burn going; without it the
    ///         transaction reverts with an arithmetic underflow.
    function test_lossProtectionSurvivesDebtBelowBurn() public {
        _depositUser(alice, 100 ether);

        // Generate profit so dragon is minted shares with synced balance/debt.
        strategy.setExchangeRate(2e18); // double the rate => +100 value
        vm.prank(keeper);
        tokenized.report();

        uint256 dragonBalance = tokenized.balanceOf(dragonRouter);
        uint256 dragonDebt = ys.getDragonRouterDebtInAssetValue();
        assertEq(dragonBalance, dragonDebt, "balance and debt should start synced");
        assertGt(dragonBalance, 0, "dragon should hold shares after profit");

        // Drift: shrink dragonRouterDebtInAssetValue to 1 wei but leave the
        // dragon's share balance untouched. Now dragonBalance >> debt, so the
        // next burn will subtract more than the tracked debt.
        bytes32 dragonDebtSlot = bytes32(uint256(YS_SLOT) + 2);
        vm.store(address(strategy), dragonDebtSlot, bytes32(uint256(1)));
        assertEq(ys.getDragonRouterDebtInAssetValue(), 1, "drift not applied");

        // Drop the rate so the vault is insolvent and a burn is required.
        strategy.setExchangeRate(5e17); // halve from initial; assets * 0.5 < userDebt + dragonDebt
        assertTrue(ys.isVaultInsolvent(), "vault should be insolvent");

        // With the fix: report() processes the burn cleanly and saturates debt to 0.
        // Without the fix: this call reverts with `panic: arithmetic underflow`.
        vm.prank(keeper);
        tokenized.report();

        assertEq(ys.getDragonRouterDebtInAssetValue(), 0, "debt must saturate to zero");
        assertLt(tokenized.balanceOf(dragonRouter), dragonBalance, "dragon shares should have been burned");
    }
}
