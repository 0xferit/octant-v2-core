/* SPDX-License-Identifier: GPL-3.0 */
pragma solidity ^0.8.23;
pragma abicoder v2;

import { ABDKMath64x64 } from "abdk-libraries-solidity/ABDKMath64x64.sol";
import "./vendor/uniswap/libraries/TickMath.sol";
import "./vendor/uniswap/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./vendor/uniswap/libraries/TransferHelper.sol";

library ExtraTickMath {
    function divRound(int128 x, int128 y) internal pure returns (int128 result) {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;

        // Check if remainder is greater than 0.5
        if (quot % 2 ** 64 >= 0x8000000000000000) {
            result += 1;
        }
    }

    function nearestUsableTick(int24 tick_, uint24 tickSpacing) internal pure returns (int24 result) {
        result = int24(divRound(int128(tick_), int128(int24(tickSpacing)))) * int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }
}

contract UniswapLiquidityHelper is IERC721Receiver {
    error UniswapLiquidityHelper__MustBeOwner();

    address public immutable contractOwner;
    address public immutable token0Address;
    address public immutable token1Address;

    uint24 public immutable poolFee;

    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    mapping(uint256 => Deposit) public deposits;
    mapping(uint24 => int24) public feeAmountTickSpacing;

    // Storage variable for position data to reduce stack pressure during coverage builds
    struct PositionData {
        uint128 liquidity;
        address token0;
        address token1;
    }
    PositionData internal _positionData;

    constructor(address token0Address_, address token1Address_, address nonfungiblePositionManager_, uint24 poolFee_) {
        contractOwner = msg.sender;
        token0Address = token0Address_;
        token1Address = token1Address_;
        nonfungiblePositionManager = INonfungiblePositionManager(nonfungiblePositionManager_);
        poolFee = poolFee_;

        feeAmountTickSpacing[500] = 10;
        feeAmountTickSpacing[3000] = 60;
        feeAmountTickSpacing[10000] = 200;
    }

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        // get position information
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    /// @dev possible improvement to do is to make the msg.sender the owner of the NFT and approve the liquidity helper to perform operations
    function mintNewPosition(
        uint256 amountToMint0Wei_,
        uint256 amountToMint1Wei_
    ) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        uint256 amount0ToMint = amountToMint0Wei_;
        uint256 amount1ToMint = amountToMint1Wei_;

        // Approve the position manager
        TransferHelper.safeApprove(token0Address, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(token1Address, address(nonfungiblePositionManager), amount1ToMint);

        int24 tickSpacing = feeAmountTickSpacing[poolFee];
        int24 tickLowerRounded = ExtraTickMath.nearestUsableTick(TickMath.MIN_TICK, uint24(tickSpacing));
        int24 tickUpperRounded = ExtraTickMath.nearestUsableTick(TickMath.MAX_TICK, uint24(tickSpacing));

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0Address,
            token1: token1Address,
            fee: poolFee,
            tickLower: tickLowerRounded,
            tickUpper: tickUpperRounded,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Note that the pool defined by GLM/WETH and fee tier 1.0% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(token0Address, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(token0Address, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1Address, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(token1Address, msg.sender, refund1);
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position
        // Call to safeTransfer will trigger `onERC721Received` which must return the selector else transfer will fail
        // nonfungiblePositionManager.safeTransferFrom(msg.sender, address(this), tokenId);

        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: msg.sender,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
    }

    /// @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseLiquidityInHalf(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // caller must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, "Not the owner");
        // get liquidity data for tokenId - use storage to reduce stack pressure
        _positionData.liquidity = _getPositionLiquidity(tokenId);
        uint128 halfLiquidity = _positionData.liquidity / 2;
        deposits[tokenId].liquidity = halfLiquidity;

        return _decreaseLiquidity(tokenId, halfLiquidity);
    }

    function removeLiquidity(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        // assign returned variables to silence warnings
        amount0 = 0;
        amount1 = 0;
        // caller must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, "Not the owner");
        // get liquidity data for tokenId - use storage to reduce stack pressure
        _positionData.liquidity = _getPositionLiquidity(tokenId);
        deposits[tokenId].liquidity = 0;

        _decreaseLiquidity(tokenId, _positionData.liquidity);
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param tokenId The id of the erc721 token
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        // Approve the position manager
        TransferHelper.safeApprove(token0Address, address(nonfungiblePositionManager), amountAdd0);
        TransferHelper.safeApprove(token1Address, address(nonfungiblePositionManager), amountAdd1);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(params);

        // Update deposit
        deposits[tokenId].liquidity = liquidity;

        // Remove allowance and refund in both assets.
        if (amount0 < amountAdd0) {
            TransferHelper.safeApprove(token0Address, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amountAdd0 - amount0;
            TransferHelper.safeTransfer(token0Address, msg.sender, refund0);
        }

        if (amount1 < amountAdd1) {
            TransferHelper.safeApprove(token1Address, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amountAdd1 - amount1;
            TransferHelper.safeTransfer(token1Address, msg.sender, refund1);
        }
    }

    function returnFunds(uint256 token0Amount, uint256 token1Amount) public {
        if (msg.sender != contractOwner) {
            revert UniswapLiquidityHelper__MustBeOwner();
        }
        TransferHelper.safeTransfer(token0Address, contractOwner, token0Amount);
        TransferHelper.safeTransfer(token1Address, contractOwner, token1Amount);
    }

    /**
     * Internal & Private functions
     */
    function _decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }

    function _createDeposit(address owner, uint256 tokenId) internal {
        // Use helper to get position data - reduces stack pressure during coverage builds
        _loadPositionData(tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({
            owner: owner,
            liquidity: _positionData.liquidity,
            token0: _positionData.token0,
            token1: _positionData.token1
        });
    }

    /// @notice Helper function to get position liquidity - uses low-level call to reduce stack pressure
    function _getPositionLiquidity(uint256 tokenId) internal view returns (uint128) {
        // Use low-level call to avoid 12-return-value stack overflow
        bytes memory data = abi.encodeWithSelector(INonfungiblePositionManager.positions.selector, tokenId);
        (bool success, bytes memory result) = address(nonfungiblePositionManager).staticcall(data);
        require(success, "Position query failed");
        // Liquidity is the 8th return value (index 7), each value is 32 bytes
        // Skip first 7 values (7 * 32 = 224 bytes) to get liquidity
        uint128 liquidity;
        assembly {
            liquidity := mload(add(result, 256)) // 32 + 224 = 256 (skip length prefix + 7 values)
        }
        return liquidity;
    }

    /// @notice Helper function to load position data into storage - uses low-level call to reduce stack pressure
    function _loadPositionData(uint256 tokenId) internal {
        // Use low-level call to avoid 12-return-value stack overflow
        bytes memory data = abi.encodeWithSelector(INonfungiblePositionManager.positions.selector, tokenId);
        (bool success, bytes memory result) = address(nonfungiblePositionManager).staticcall(data);
        require(success, "Position query failed");

        // Decode only the values we need:
        // token0 is 3rd return value (index 2): offset = 32 + 64 = 96
        // token1 is 4th return value (index 3): offset = 32 + 96 = 128
        // liquidity is 8th return value (index 7): offset = 32 + 224 = 256
        assembly {
            let token0 := mload(add(result, 96))
            let token1 := mload(add(result, 128))
            let liquidity := mload(add(result, 256))

            // Store in storage struct
            sstore(_positionData.slot, liquidity)
            sstore(add(_positionData.slot, 1), token0)
            sstore(add(_positionData.slot, 2), token1)
        }
    }
}
