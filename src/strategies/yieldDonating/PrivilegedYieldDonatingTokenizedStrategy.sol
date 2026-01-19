// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

import { YieldDonatingTokenizedStrategy } from "./YieldDonatingTokenizedStrategy.sol";
import { Privileged } from "src/core/Privileged.sol";

/**
 * @title Privileged Yield Donating Tokenized Strategy
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice YieldDonatingTokenizedStrategy with privileged-gated deposits and mints.
 */
contract PrivilegedYieldDonatingTokenizedStrategy is YieldDonatingTokenizedStrategy, Privileged {
    function setPrivileged(address _account, bool _status) external onlyManagement {
        _setPrivileged(_account, _status);
    }

    function setPrivilegedBatch(address[] calldata _accounts, bool _status) external onlyManagement {
        _setPrivilegedBatch(_accounts, _status);
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(isPrivileged(msg.sender) && isPrivileged(receiver), "!privileged");
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        require(isPrivileged(msg.sender) && isPrivileged(receiver), "!privileged");
        return super.mint(shares, receiver);
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        if (!isPrivileged(receiver)) return 0;
        return super.maxDeposit(receiver);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        if (!isPrivileged(receiver)) return 0;
        return super.maxMint(receiver);
    }
}
