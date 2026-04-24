// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { AaveV3Strategy } from "src/strategies/yieldDonating/AaveV3Strategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract MockPool {
    function supply(address, uint256, address, uint16) external {}
    function withdraw(address, uint256, address) external pure returns (uint256) {
        return 0;
    }
}

contract MockDataProvider {
    address public aToken;

    constructor(address _aToken) {
        aToken = _aToken;
    }

    function getReserveTokensAddresses(
        address
    ) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress) {
        return (aToken, address(0), address(0));
    }

    function getReserveCaps(address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function getATokenTotalSupply(address) external pure returns (uint256) {
        return 0;
    }

    function getReserveConfigurationData(
        address
    ) external pure returns (uint256, uint256, uint256, uint256, uint256, bool, bool, bool, bool, bool) {
        return (0, 0, 0, 0, 0, false, false, false, true, false);
    }

    function getPaused(address) external pure returns (bool) {
        return false;
    }

    function getReserveData(
        address
    )
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint40
        )
    {
        return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }
}

contract MockAddressesProvider {
    address public pool;
    address public dataProvider;

    constructor(address _pool, address _dataProvider) {
        pool = _pool;
        dataProvider = _dataProvider;
    }

    function getPool() external view returns (address) {
        return pool;
    }

    function getPoolDataProvider() external view returns (address) {
        return dataProvider;
    }
}

/// @notice Mock RewardsController that hands back caller-controlled lists and
///         transfers a recorded reward token to `to` so the dragon-router payout path
///         is mechanically verified end-to-end.
contract MockRewardsController {
    ERC20Mock public rewardToken;
    uint256 public payout;

    constructor(ERC20Mock _rewardToken, uint256 _payout) {
        rewardToken = _rewardToken;
        payout = _payout;
    }

    function claimAllRewards(
        address[] calldata /*assets*/,
        address to
    ) external returns (address[] memory rewardsList, uint256[] memory amounts) {
        rewardsList = new address[](1);
        rewardsList[0] = address(rewardToken);
        amounts = new uint256[](1);
        amounts[0] = payout;
        if (payout > 0) {
            rewardToken.mint(to, payout);
        }
    }
}

/// @notice Issue 44 -- the strategy used to ignore Aave's RewardsController and any
///         airdropped ERC-20 that landed on its address, so liquidity-mining emissions and
///         off-chain reward distributions were unrecoverable. The fix wires the
///         RewardsController and adds keeper-only `claimAaveRewards` and `sweepAirdrop`.
contract AaveV3RewardsAndSweepTest is Test {
    AaveV3Strategy internal strategy;
    AaveV3Strategy internal strategyWithoutRewards;
    ERC20Mock internal asset;
    ERC20Mock internal aToken;
    ERC20Mock internal rewardToken;
    MockRewardsController internal rewards;

    address internal management = address(0x1);
    address internal keeper = address(0x2);
    address internal emergencyAdmin = address(0x3);
    address internal donationAddress = address(0x4);
    address internal randomCaller = address(0xBEEF);

    function setUp() public {
        asset = new ERC20Mock();
        aToken = new ERC20Mock();
        rewardToken = new ERC20Mock();

        MockPool pool = new MockPool();
        MockDataProvider dp = new MockDataProvider(address(aToken));
        MockAddressesProvider provider = new MockAddressesProvider(address(pool), address(dp));

        rewards = new MockRewardsController(rewardToken, 100 ether);

        YieldDonatingTokenizedStrategy impl = new YieldDonatingTokenizedStrategy();

        strategy = new AaveV3Strategy(
            address(provider),
            address(rewards),
            address(asset),
            "Test Aave",
            "tsAAVE",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(impl)
        );

        strategyWithoutRewards = new AaveV3Strategy(
            address(provider),
            address(0), // explicit zero — claim path must revert with a clear message
            address(asset),
            "Test Aave No Rewards",
            "tsAAVE_NR",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            address(impl)
        );
    }

    // --- claimAaveRewards ---

    /// @notice Keeper claim transfers reward tokens from controller to dragon router.
    function test_claimAaveRewards_keeperPaysOutToDragon() public {
        assertEq(rewardToken.balanceOf(donationAddress), 0, "dragon must start with no reward tokens");

        vm.prank(keeper);
        strategy.claimAaveRewards();

        assertEq(rewardToken.balanceOf(donationAddress), 100 ether, "claim must forward emissions to dragon router");
    }

    /// @notice Random caller cannot claim. Pre-fix this whole entry point did not exist;
    ///         post-fix it must enforce keeper authorization.
    function test_claimAaveRewards_revertsForUnauthorizedCaller() public {
        vm.prank(randomCaller);
        vm.expectRevert(); // BaseStrategy onlyKeepers reverts on unauthorized caller
        strategy.claimAaveRewards();
    }

    /// @notice Misconfigured deployment (no rewardsController) must revert loudly
    ///         instead of silently no-op'ing on a zero target.
    function test_claimAaveRewards_revertsWhenControllerUnset() public {
        vm.prank(keeper);
        vm.expectRevert("AaveV3Strategy: RewardsController not configured");
        strategyWithoutRewards.claimAaveRewards();
    }

    // --- sweepAirdrop ---

    /// @notice Keeper can sweep an arbitrary ERC-20 to the dragon router.
    function test_sweepAirdrop_keeperForwardsToDragon() public {
        ERC20Mock airdrop = new ERC20Mock();
        airdrop.mint(address(strategy), 75 ether);

        vm.prank(keeper);
        strategy.sweepAirdrop(address(airdrop));

        assertEq(airdrop.balanceOf(donationAddress), 75 ether, "dragon must receive swept balance");
        assertEq(airdrop.balanceOf(address(strategy)), 0, "strategy must hold zero post-sweep");
    }

    /// @notice Sweeping the strategy asset is rejected — would let a keeper drain the
    ///         strategy's idle (pre-deploy) balance to the dragon router.
    function test_sweepAirdrop_revertsOnMainAsset() public {
        asset.mint(address(strategy), 1 ether);

        vm.prank(keeper);
        vm.expectRevert("AaveV3Strategy: Cannot sweep main asset");
        strategy.sweepAirdrop(address(asset));
    }

    /// @notice Sweeping the aToken is rejected — would let a keeper liquidate the
    ///         deployed Aave position to the dragon router.
    function test_sweepAirdrop_revertsOnAToken() public {
        aToken.mint(address(strategy), 1 ether);

        vm.prank(keeper);
        vm.expectRevert("AaveV3Strategy: Cannot sweep aToken");
        strategy.sweepAirdrop(address(aToken));
    }

    /// @notice Random caller cannot sweep.
    function test_sweepAirdrop_revertsForUnauthorizedCaller() public {
        ERC20Mock airdrop = new ERC20Mock();
        airdrop.mint(address(strategy), 1 ether);

        vm.prank(randomCaller);
        vm.expectRevert();
        strategy.sweepAirdrop(address(airdrop));
    }

    /// @notice Sweeping a zero-balance token is rejected — keeps the keeper from
    ///         emitting noise events and, more importantly, surfaces a misconfigured
    ///         token address loudly.
    function test_sweepAirdrop_revertsOnZeroBalance() public {
        ERC20Mock airdrop = new ERC20Mock();

        vm.prank(keeper);
        vm.expectRevert("AaveV3Strategy: No balance to sweep");
        strategy.sweepAirdrop(address(airdrop));
    }
}
