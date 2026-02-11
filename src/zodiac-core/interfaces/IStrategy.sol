// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { ITokenizedStrategy } from "./ITokenizedStrategy.sol";
import { IBaseStrategy } from "./IBaseStrategy.sol";

/**
 * @title Octant Strategy Interface (Zodiac Core)
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Composite interface combining base strategy callbacks with tokenized strategy extensions
 *         used by Octant strategies. Implementations are expected to support ERC-4626-like flows
 *         (via TokenizedStrategy) and donation routing mechanics to the dragon router.
 */
interface IStrategy is IBaseStrategy, ITokenizedStrategy {}
