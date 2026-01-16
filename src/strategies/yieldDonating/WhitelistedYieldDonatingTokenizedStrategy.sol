// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

import { YieldDonatingTokenizedStrategy } from "./YieldDonatingTokenizedStrategy.sol";
import { Whitelistable } from "src/core/Whitelistable.sol";

/**
 * @title Whitelisted Yield Donating Tokenized Strategy
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice YieldDonatingTokenizedStrategy with whitelist-gated deposits and mints.
 */
contract WhitelistedYieldDonatingTokenizedStrategy is YieldDonatingTokenizedStrategy, Whitelistable {
    function setWhitelist(address _account, bool _status) external onlyManagement {
        _setWhitelist(_account, _status);
    }

    function setWhitelistBatch(address[] calldata _accounts, bool _status) external onlyManagement {
        _setWhitelistBatch(_accounts, _status);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(isWhitelisted(receiver), "!whitelisted");
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        require(isWhitelisted(receiver), "!whitelisted");
        return super.mint(shares, receiver);
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        if (!isWhitelisted(receiver)) return 0;
        return super.maxDeposit(receiver);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        if (!isWhitelisted(receiver)) return 0;
        return super.maxMint(receiver);
    }
}
