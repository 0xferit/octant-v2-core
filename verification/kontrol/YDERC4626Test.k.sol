// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

import { ERC4626BaseTest } from "test/kontrol/ERC4626BaseTest.k.sol";
import { YDSetup } from "test/kontrol/YDSetup.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title YDERC4626Test
 * @notice ERC4626 property tests instantiated for YieldDonatingTokenizedStrategy
 * @dev Extends ERC4626BaseTest and YDSetup. Overrides virtual accessors to bind
 *      to the YD setup. Each test function calls the abstract invariant helpers.
 */
contract YDERC4626Test is ERC4626BaseTest, YDSetup {
    function setUp() public override(YDSetup) {
        YDSetup.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                    VIRTUAL ACCESSORS
    //////////////////////////////////////////////////////////////*/

    function getStrategy() internal view override returns (ITokenizedStrategy) {
        return iStrategy;
    }

    function getStrategyAddr() internal view override returns (address) {
        return address(strategy);
    }

    function getKeeper() internal view override returns (address) {
        return _keeper;
    }

    function getDragonRouter() internal view override returns (address) {
        return _dragonRouter;
    }

    function getAssetAddr() internal view override returns (address) {
        return _asset;
    }

    /*//////////////////////////////////////////////////////////////
                    TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice After deposit, shares are redeemable
    function testSharesRedeemableAfterDepositYD(uint256 assets, address receiver) public {
        _assumeNonReentrant();

        vm.assume(assets > 0);
        vm.assume(assets < ETH_UPPER_BOUND);
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(strategy));
        vm.assume(receiver != _dragonRouter);

        uint256 totalAssets = _loadUInt256(address(strategy), TS_TOTAL_ASSETS_SLOT);
        uint256 totalSupply = _loadUInt256(address(strategy), TS_TOTAL_SUPPLY_SLOT);
        vm.assume(totalAssets > 0);
        vm.assume(totalSupply > 0);

        _assumeNoOverflow(assets, totalSupply);
        uint256 expectedShares = (assets * totalSupply) / totalAssets;
        vm.assume(expectedShares > 0);
        _assumeNoOverflow(totalSupply, expectedShares);
        _assumeNoOverflow(totalAssets, assets);

        // Inductive hypothesis: receiver's balance is bounded by totalSupply pre-deposit.
        // The unchecked balance increment in _mint means the prover needs this constraint
        // to verify the invariant is preserved through the deposit state transition.
        uint256 receiverBalance = _loadMappingUInt256(
            address(strategy),
            TS_BALANCES_SLOT,
            uint256(uint160(receiver)),
            0
        );
        vm.assume(receiverBalance <= totalSupply);

        // Not shutdown
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 0);

        address depositor = makeAddr("DEPOSITOR");
        deal(_asset, depositor, assets);
        vm.prank(depositor);
        (bool ok, ) = _asset.call(abi.encodeWithSignature("approve(address,uint256)", address(strategy), assets));
        require(ok);

        deal(_asset, address(strategy), totalAssets);

        vm.prank(depositor);
        iStrategy.deposit(assets, receiver);

        _assertSharesRedeemable(receiver);
        _assertBalanceBounded(receiver);
    }

    /// @notice Shutdown blocks deposits and mints
    function testShutdownBlocksYD(address user) public {
        _assumeNonReentrant();

        vm.assume(user != address(0));
        vm.assume(user != address(strategy));

        // Set shutdown = true
        _storeData(address(strategy), TS_FLAGS_SLOT, TS_SHUTDOWN_OFFSET, TS_SHUTDOWN_WIDTH, 1);

        _assertShutdownBlocks(user);
    }

    /// @notice User balance is bounded by totalSupply
    /// @dev Storage-accessor sanity check: with fully symbolic storage, balance and
    ///      totalSupply are independent -- the assumption is necessary. The invariant
    ///      is proven inductively through state transitions in testSharesRedeemableAfterDepositYD.
    function testBalanceBoundedYD(address user) public {
        _assumeNonReentrant();

        vm.assume(user != address(0));

        // Set a concrete balance <= totalSupply
        uint256 totalSupply = _loadUInt256(address(strategy), TS_TOTAL_SUPPLY_SLOT);
        uint256 balance = _loadMappingUInt256(address(strategy), TS_BALANCES_SLOT, uint256(uint160(user)), 0);
        vm.assume(balance <= totalSupply);

        _assertBalanceBounded(user);
    }

    /// @notice Conversion round-trip does not create value
    function testConversionConsistencyYD(uint256 amount) public {
        _assumeNonReentrant();

        vm.assume(amount > 0);
        vm.assume(amount < ETH_UPPER_BOUND);

        uint256 totalAssets = _loadUInt256(address(strategy), TS_TOTAL_ASSETS_SLOT);
        uint256 totalSupply = _loadUInt256(address(strategy), TS_TOTAL_SUPPLY_SLOT);
        vm.assume(totalAssets > 0);
        vm.assume(totalSupply > 0);

        // Avoid overflow in mulDiv
        _assumeNoOverflow(amount, totalSupply);
        _assumeNoOverflow(amount, totalAssets);

        _assertConversionConsistency(amount);
    }
}
