// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";

import { KontrolTest } from "test/kontrol/KontrolTest.k.sol";
import "test/kontrol/SharedStateSlots.k.sol";

/**
 * @title ERC4626BaseTest
 * @notice Abstract polymorphic ERC4626 property test base for Kontrol proofs
 * @dev Provides reusable per-function invariants that apply to both YieldDonating
 *      and YieldSkimming strategies. Concrete test contracts override virtual
 *      accessors to bind to specific setup contracts.
 *
 *      Invariants:
 *      1. After deposit, shares are redeemable (if balance > 0 and totalAssets > 0)
 *      2. Shutdown blocks maxDeposit and maxMint
 *      3. User balance bounded by totalSupply
 *      4. Conversion consistency (no rounding trap): round-trip loses at most 1 unit
 */
abstract contract ERC4626BaseTest is KontrolTest {
    /*//////////////////////////////////////////////////////////////
                    VIRTUAL ACCESSORS
    //////////////////////////////////////////////////////////////*/

    function getStrategy() internal view virtual returns (ITokenizedStrategy);

    function getStrategyAddr() internal view virtual returns (address);

    function getKeeper() internal view virtual returns (address);

    function getDragonRouter() internal view virtual returns (address);

    function getAssetAddr() internal view virtual returns (address);

    /*//////////////////////////////////////////////////////////////
                    HELPERS
    //////////////////////////////////////////////////////////////*/

    function _assumeNonReentrant() internal {
        _storeData(getStrategyAddr(), TS_FLAGS_SLOT, TS_ENTERED_OFFSET, TS_ENTERED_WIDTH, 1);
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT: SHARES REDEEMABLE AFTER DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @notice After deposit, if receiver has balance and totalAssets > 0, maxRedeem > 0
    function _assertSharesRedeemable(address receiver) internal view {
        ITokenizedStrategy s = getStrategy();
        if (s.balanceOf(receiver) > 0 && s.totalAssets() > 0) {
            _establish(Mode.Assert, s.maxRedeem(receiver) > 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT: SHUTDOWN BLOCKS DEPOSITS
    //////////////////////////////////////////////////////////////*/

    /// @notice When shutdown, maxDeposit and maxMint return 0
    function _assertShutdownBlocks(address user) internal view {
        ITokenizedStrategy s = getStrategy();
        _establish(Mode.Assert, s.maxDeposit(user) == 0);
        _establish(Mode.Assert, s.maxMint(user) == 0);
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT: BALANCE BOUNDED BY SUPPLY
    //////////////////////////////////////////////////////////////*/

    /// @notice balanceOf(user) <= totalSupply()
    function _assertBalanceBounded(address user) internal view {
        ITokenizedStrategy s = getStrategy();
        _establish(Mode.Assert, s.balanceOf(user) <= s.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                    INVARIANT: CONVERSION CONSISTENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice Round-trip conversion must not create value:
    ///         convertToAssets(convertToShares(x)) <= x
    ///         convertToShares(convertToAssets(x)) <= x
    function _assertConversionConsistency(uint256 amount) internal view {
        ITokenizedStrategy s = getStrategy();
        // shares -> assets -> shares should not create value
        uint256 shares = s.convertToShares(amount);
        uint256 backToAssets = s.convertToAssets(shares);
        _establish(Mode.Assert, backToAssets <= amount);

        // assets -> shares -> assets should not create value
        uint256 assets = s.convertToAssets(amount);
        uint256 backToShares = s.convertToShares(assets);
        _establish(Mode.Assert, backToShares <= amount);
    }
}
