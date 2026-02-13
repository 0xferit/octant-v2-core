// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import { ITokenizedStrategy } from "src/core/interfaces/ITokenizedStrategy.sol";
import { IBaseStrategy } from "src/core/interfaces/IBaseStrategy.sol";

// Interface to use during testing that implements the 4626 standard
// the implementation functions, the Strategies immutable functions
// as well as the added functions for the Mock Strategy.
interface IMockStrategy is ITokenizedStrategy, IBaseStrategy {
    function setTrigger(bool _trigger) external;

    function onlyLetManagers() external;

    function onlyLetKeepersIn() external;

    function onlyLetEmergencyAdminsIn() external;

    function safeDeposit(uint256 assets, address receiver, uint256 minSharesOut) external;

    function yieldSource() external view returns (address);

    function managed() external view returns (bool);

    function kept() external view returns (bool);

    function emergentizated() external view returns (bool);

    function dontTend() external view returns (bool);

    function setDontTend(bool _dontTend) external;

    function unlockedShares() external view returns (uint256);

    function lossAmount() external view returns (uint256);

    function enableBurning() external view returns (bool);

    function setEnableBurning(bool _enableBurning) external;
}
