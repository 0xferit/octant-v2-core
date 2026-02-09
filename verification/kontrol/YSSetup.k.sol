// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { YieldSkimmingTokenizedStrategy } from "src/strategies/yieldSkimming/YieldSkimmingTokenizedStrategy.sol";
import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

import { KontrolTest } from "test/kontrol/KontrolTest.k.sol";
import { TestERC20 } from "test/kontrol/TestERC20.k.sol";
import { MockSimpleYieldSkimmingStrategy } from "test/kontrol/MockSimpleYieldSkimmingStrategy.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title YSSetup
 * @notice Symbolic setup for formal verification of YieldSkimmingTokenizedStrategy
 * @dev Deploys a MockSimpleYieldSkimmingStrategy using YieldSkimmingTokenizedStrategy as the
 *      delegatecall implementation. Makes storage symbolic, then restores concrete
 *      addresses and YS-specific values to avoid excessive branching in the symbolic executor.
 */
contract YSSetup is KontrolTest {
    YieldSkimmingTokenizedStrategy public ysImplementation;
    MockSimpleYieldSkimmingStrategy public ysStrategy;
    ITokenizedStrategy public iYSStrategy;

    address public _asset;
    address internal _management;
    address internal _keeper;
    address internal _emergencyAdmin;
    address internal _dragonRouter;

    uint256 deploymentTimestamp;
    uint256 currentTimestamp;

    function setUp() public virtual {
        // Concrete role addresses (avoid symbolic branching on prank)
        _management = makeAddr("MANAGEMENT");
        _keeper = makeAddr("KEEPER");
        _emergencyAdmin = makeAddr("EMERGENCY_ADMIN");
        _dragonRouter = makeAddr("DRAGON_ROUTER");

        // Deploy mock ERC20 asset
        TestERC20 erc20 = new TestERC20();
        _asset = address(erc20);

        // Deploy the YieldSkimmingTokenizedStrategy implementation
        ysImplementation = new YieldSkimmingTokenizedStrategy();

        // Deploy mock strategy (BaseStrategy constructor calls initialize via delegatecall)
        deploymentTimestamp = freshUInt256Bounded();
        vm.warp(deploymentTimestamp);

        ysStrategy = new MockSimpleYieldSkimmingStrategy(
            _asset,
            "Test YS Strategy",
            "tYSS",
            _management,
            _keeper,
            _emergencyAdmin,
            _dragonRouter,
            true, // enableBurning
            address(ysImplementation)
        );

        iYSStrategy = ITokenizedStrategy(address(ysStrategy));

        // ============================================
        // MAKE STORAGE SYMBOLIC
        // ============================================
        kevm.symbolicStorage(address(ysStrategy));

        // ============================================
        // RESTORE CONCRETE VALUES
        // ============================================
        // Addresses must be concrete to avoid excessive branching on
        // prank cheatcode and access control checks.
        _storeAddress(address(ysStrategy), TS_ASSET_SLOT, _asset);
        _storeAddress(address(ysStrategy), TS_MANAGEMENT_SLOT, _management);
        _storeAddress(address(ysStrategy), TS_KEEPER_SLOT, _keeper);
        _storeAddress(address(ysStrategy), TS_EMERGENCY_ADMIN_SLOT, _emergencyAdmin);
        _storeAddress(address(ysStrategy), TS_DRAGON_ROUTER_SLOT, _dragonRouter);

        // Symbolic totalSupply and totalAssets
        uint256 totalSupply = freshUInt256Bounded();
        _storeUInt256(address(ysStrategy), TS_TOTAL_SUPPLY_SLOT, totalSupply);
        uint256 totalAssets = freshUInt256Bounded();
        _storeUInt256(address(ysStrategy), TS_TOTAL_ASSETS_SLOT, totalAssets);

        // Flags: decimals=18, entered=NOT_ENTERED(1), shutdown=false(0), enableBurning=true(1)
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_DECIMALS_OFFSET, TS_DECIMALS_WIDTH, 18);
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_ENTERED_OFFSET, TS_ENTERED_WIDTH, 1);
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 0);
        _storeData(address(ysStrategy), TS_FLAGS_SLOT, TS_ENABLE_BURNING_OFFSET, TS_ENABLE_BURNING_WIDTH, 1);

        // Disable health check for core invariant proofs
        _storeData(address(ysStrategy), HC_SLOT, HC_DO_HEALTH_CHECK_OFFSET, HC_DO_HEALTH_CHECK_WIDTH, 0);

        // Symbolic dragon router balance
        uint256 dragonBalance = freshUInt256Bounded();
        _storeMappingUInt256(address(ysStrategy), TS_BALANCES_SLOT, uint256(uint160(_dragonRouter)), 0, dragonBalance);

        // ============================================
        // YIELD SKIMMING SPECIFIC VALUES
        // ============================================
        // Symbolic value debts
        uint256 userDebt = freshUInt256Bounded();
        _storeUInt256(address(ysStrategy), YS_TOTAL_DEBT_OWED_TO_USER_SLOT, userDebt);

        uint256 dragonDebt = freshUInt256Bounded();
        _storeUInt256(address(ysStrategy), YS_DRAGON_ROUTER_DEBT_SLOT, dragonDebt);

        uint256 lastReportedRate = freshUInt256Bounded();
        _storeUInt256(address(ysStrategy), YS_LAST_REPORTED_RATE_SLOT, lastReportedRate);

        // Mock exchange rate: concrete decimals=27 (RAY), symbolic rate > 0
        // Using 27 decimals avoids branching in _currentRateRay() scaling logic
        _storeUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_DECIMALS_SLOT, 27);
        uint256 mockRate = freshUInt256Bounded();
        vm.assume(mockRate > 0);
        _storeUInt256(address(ysStrategy), MOCK_YS_EXCHANGE_RATE_SLOT, mockRate);

        // Warp to a later timestamp
        currentTimestamp = freshUInt256Bounded();
        vm.assume(deploymentTimestamp < currentTimestamp);
        vm.warp(currentTimestamp);
    }
}
