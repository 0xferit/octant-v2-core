// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TokenizedStrategy } from "src/zodiac-core/vaults/TokenizedStrategy.sol";
import { IBaseStrategy } from "src/zodiac-core/interfaces/IBaseStrategy.sol";
import { ITokenizedStrategy } from "src/zodiac-core/interfaces/ITokenizedStrategy.sol";
import { NATIVE_TOKEN } from "src/constants.sol";
import { ZeroShares, ZeroAssets } from "src/errors.sol";

/**
 * @title TestTokenizedStrategy
 * @notice Concrete test harness for TokenizedStrategy -- NOT production code.
 * @dev Implements all virtual functions with Dragon-style yield-donating semantics:
 *      profits are minted as shares to the dragonRouter, losses are absorbed by
 *      burning dragonRouter shares.  PPS stays constant for depositors.
 */
contract TestTokenizedStrategy is TokenizedStrategy {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                        ERC4626 WRITE OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) external payable override onlyOperator returns (uint256 shares) {
        StrategyData storage S = _strategyStorage();
        require(!S.shutdown, "strategy shutdown");

        // Handle type(uint256).max as "deposit sender's full balance"
        if (assets == type(uint256).max) {
            ERC20 _asset = S.asset;
            assets = address(_asset) == NATIVE_TOKEN ? msg.value : _asset.balanceOf(msg.sender);
        }

        shares = _convertToShares(S, assets, Math.Rounding.Floor);
        if (shares == 0) revert ZeroShares();

        _deposit(S, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external payable override onlyOperator returns (uint256 assets) {
        StrategyData storage S = _strategyStorage();
        assets = _convertToAssets(S, shares, Math.Rounding.Ceil);
        if (assets == 0) revert ZeroAssets();

        _deposit(S, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256 shares) {
        StrategyData storage S = _strategyStorage();
        shares = _convertToShares(S, assets, Math.Rounding.Ceil);
        if (shares == 0) revert ZeroShares();

        _withdraw(S, receiver, owner, assets, shares, maxLoss);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public override nonReentrant returns (uint256) {
        StrategyData storage S = _strategyStorage();
        uint256 assets = _convertToAssets(S, shares, Math.Rounding.Floor);
        if (assets == 0) revert ZeroAssets();

        return _withdraw(S, receiver, owner, assets, shares, maxLoss);
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT REPORTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Dragon-style report: profits minted to dragonRouter, losses absorbed by burning dragonRouter shares.
     */
    function report() external override nonReentrant onlyKeepers returns (uint256 profit, uint256 loss) {
        StrategyData storage S = _strategyStorage();

        uint256 newTotalAssets = IBaseStrategy(address(this)).harvestAndReport();
        uint256 oldTotalAssets = _totalAssets(S);
        address _dragonRouter = S.dragonRouter;

        if (newTotalAssets > oldTotalAssets) {
            unchecked {
                profit = newTotalAssets - oldTotalAssets;
            }
            _mint(S, _dragonRouter, _convertToShares(S, profit, Math.Rounding.Floor));
        } else {
            unchecked {
                loss = oldTotalAssets - newTotalAssets;
            }
            if (loss != 0) {
                // Absorb loss by burning dragonRouter shares (capped at its balance)
                uint256 sharesBurned = Math.min(
                    _convertToShares(S, loss, Math.Rounding.Floor),
                    S.balances[_dragonRouter]
                );
                if (sharesBurned > 0) {
                    _burn(S, _dragonRouter, sharesBurned);
                }
            }
        }

        S.totalAssets = newTotalAssets;
        S.lastReport = uint96(block.timestamp);

        emit Reported(profit, loss, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 TRANSFER OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function transfer(address, uint256) external pure override returns (bool) {
        revert("transfers not supported");
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        revert("transfers not supported");
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function maxWithdraw(address owner) external view override returns (uint256) {
        return _maxWithdraw(_strategyStorage(), owner);
    }

    function maxWithdraw(address owner, uint256 /*maxLoss*/) external view override returns (uint256) {
        return _maxWithdraw(_strategyStorage(), owner);
    }

    function _maxRedeem(StrategyData storage S, address _owner) internal view override returns (uint256 maxRedeem_) {
        maxRedeem_ = IBaseStrategy(address(this)).availableWithdrawLimit(_owner);
        if (maxRedeem_ == type(uint256).max) {
            maxRedeem_ = _balanceOf(S, _owner);
        } else {
            maxRedeem_ = Math.min(_convertToShares(S, maxRedeem_, Math.Rounding.Floor), _balanceOf(S, _owner));
        }
    }
}
