// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.25;

import { YieldDonatingTokenizedStrategy } from "./YieldDonatingTokenizedStrategy.sol";

/**
 * @title Whitelisted Yield Donating Tokenized Strategy
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice YieldDonatingTokenizedStrategy with whitelist-gated deposits and mints.
 */
contract WhitelistedYieldDonatingTokenizedStrategy is YieldDonatingTokenizedStrategy {
    event WhitelistUpdated(address indexed account, bool status);

    bytes32 internal constant WHITELIST_STORAGE =
        keccak256(abi.encode(uint256(keccak256("octant.whitelisted.strategy.storage")) - 1)) & ~bytes32(uint256(0xff));

    struct WhitelistData {
        mapping(address => bool) whitelisted;
    }

    function _whitelistStorage() internal pure returns (WhitelistData storage W) {
        bytes32 slot = WHITELIST_STORAGE;
        assembly {
            W.slot := slot
        }
    }

    function setWhitelist(address _account, bool _status) external onlyManagement {
        _whitelistStorage().whitelisted[_account] = _status;
        emit WhitelistUpdated(_account, _status);
    }

    function setWhitelistBatch(address[] calldata _accounts, bool _status) external onlyManagement {
        WhitelistData storage W = _whitelistStorage();
        for (uint256 i = 0; i < _accounts.length; i++) {
            W.whitelisted[_accounts[i]] = _status;
            emit WhitelistUpdated(_accounts[i], _status);
        }
    }

    function isWhitelisted(address _account) public view returns (bool) {
        return _whitelistStorage().whitelisted[_account];
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
