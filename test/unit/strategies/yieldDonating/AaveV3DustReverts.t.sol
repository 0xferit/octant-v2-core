// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { AaveV3Strategy } from "src/strategies/yieldDonating/AaveV3Strategy.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract DustAavePoolMock {
    uint256 internal constant RAY = 1e27;

    string internal constant INVALID_MINT_AMOUNT = "24";
    string internal constant INVALID_BURN_AMOUNT = "25";

    uint256 public liquidityIndex = 3e27;

    function supply(address asset, uint256 amount, address, uint16) external {
        require(_rayDiv(amount, liquidityIndex) != 0, INVALID_MINT_AMOUNT);
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address, uint256 amount, address) external view returns (uint256) {
        require(_rayDiv(amount, liquidityIndex) != 0, INVALID_BURN_AMOUNT);
        return amount;
    }

    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return liquidityIndex;
    }

    function _rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * RAY + b / 2) / b;
    }
}

contract DustDataProviderMock {
    address public immutable aToken;

    constructor(address _aToken) {
        aToken = _aToken;
    }

    function getReserveTokensAddresses(
        address
    ) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress) {
        return (aToken, address(0), address(0));
    }
}

contract DustAddressesProviderMock {
    address public immutable pool;
    address public immutable dataProvider;

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

contract AaveV3DustHarness is AaveV3Strategy {
    constructor(
        address addressesProvider,
        address asset,
        address management,
        address keeper,
        address emergencyAdmin,
        address donationAddress,
        address implementation
    )
        AaveV3Strategy(
            addressesProvider,
            address(0),
            asset,
            "Test Aave Dust",
            "tsAAVEDUST",
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false,
            implementation
        )
    {}

    function exposedDeployFunds(uint256 amount) external {
        _deployFunds(amount);
    }

    function exposedFreeFunds(uint256 amount) external {
        _freeFunds(amount);
    }
}

contract AaveV3DustRevertsTest is Test {
    ERC20Mock internal asset;
    ERC20Mock internal aToken;
    DustAavePoolMock internal pool;
    AaveV3DustHarness internal strategy;

    address internal management = address(0x1);
    address internal keeper = address(0x2);
    address internal emergencyAdmin = address(0x3);
    address internal donationAddress = address(0x4);

    function setUp() public {
        asset = new ERC20Mock();
        aToken = new ERC20Mock();
        pool = new DustAavePoolMock();
        DustDataProviderMock dataProvider = new DustDataProviderMock(address(aToken));
        DustAddressesProviderMock addressesProvider = new DustAddressesProviderMock(
            address(pool),
            address(dataProvider)
        );
        YieldDonatingTokenizedStrategy implementation = new YieldDonatingTokenizedStrategy();

        strategy = new AaveV3DustHarness(
            address(addressesProvider),
            address(asset),
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            address(implementation)
        );
    }

    function test_supplyDustRevertsWithInvalidMintAmount() public {
        asset.mint(address(strategy), 1);

        vm.expectRevert(bytes("24"));
        strategy.exposedDeployFunds(1);
    }

    function test_withdrawDustRevertsWithInvalidBurnAmount() public {
        vm.expectRevert(bytes("25"));
        strategy.exposedFreeFunds(1);
    }
}
