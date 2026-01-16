// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title Whitelistable
 * @author [Golem Foundation](https://golem.foundation)
 * @custom:security-contact security@golem.foundation
 * @notice Mixin providing whitelist storage and management functions.
 * @dev Uses ERC-7201 namespaced storage to avoid collisions.
 *      Inheriting contracts must implement access control for setWhitelist/setWhitelistBatch.
 */
abstract contract Whitelistable {
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

    function _setWhitelist(address _account, bool _status) internal {
        _whitelistStorage().whitelisted[_account] = _status;
        emit WhitelistUpdated(_account, _status);
    }

    function _setWhitelistBatch(address[] calldata _accounts, bool _status) internal {
        WhitelistData storage W = _whitelistStorage();
        for (uint256 i = 0; i < _accounts.length; i++) {
            W.whitelisted[_accounts[i]] = _status;
            emit WhitelistUpdated(_accounts[i], _status);
        }
    }

    function isWhitelisted(address _account) public view returns (bool) {
        return _whitelistStorage().whitelisted[_account];
    }
}
