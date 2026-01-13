// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2023 Haberdasher Labs
// Modified for testing purposes - removed batchCreateHats to avoid stack-too-deep in coverage
pragma solidity >=0.8.13;

/// @notice Errors for Hats Protocol
error NotAdmin(address user, uint256 hatId);
error AllHatsWorn(uint256 hatId);
error AlreadyWearingHat(address wearer, uint256 hatId);
error HatDoesNotExist(uint256 hatId);
error NotEligible();
error NotHatWearer();
error NotHatsToggle();
error NotHatsEligibility();
error HatNotActive();
error NotAdminOrWearer();
error ZeroAddress();
error MaxLevelsReached();
error InvalidHatId();
error Immutable();
error NewMaxSupplyTooLow();
error BatchArrayLengthMismatch();
error StringTooLong();

/// @notice Events for Hats Protocol
interface HatsEvents {
    event HatCreated(
        uint256 id,
        string details,
        uint32 maxSupply,
        address eligibility,
        address toggle,
        bool mutable_,
        string imageURI
    );
    event HatStatusChanged(uint256 hatId, bool newStatus);
    event HatDetailsChanged(uint256 hatId, string newDetails);
    event HatEligibilityChanged(uint256 hatId, address newEligibility);
    event HatToggleChanged(uint256 hatId, address newToggle);
    event HatMutabilityChanged(uint256 hatId);
    event HatMaxSupplyChanged(uint256 hatId, uint32 newMaxSupply);
    event HatImageURIChanged(uint256 hatId, string newImageURI);
    event TopHatLinkRequested(uint32 domain, uint256 newAdmin);
    event TopHatLinked(uint32 domain, uint256 newAdmin);
    event WearerStandingChanged(uint256 hatId, address wearer, bool wearerStanding);
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );
}

/// @title MockHats - A test mock for Hats Protocol
/// @notice This is a simplified version of Hats.sol for testing purposes
/// @dev Removed batchCreateHats to avoid stack-too-deep errors during coverage
contract MockHats is HatsEvents {
    /*//////////////////////////////////////////////////////////////
                              HATS DATA MODELS
    //////////////////////////////////////////////////////////////*/

    struct Hat {
        address eligibility;
        uint32 maxSupply;
        uint32 supply;
        uint16 lastHatId;
        address toggle;
        uint96 config;
        string details;
        string imageURI;
    }

    /*//////////////////////////////////////////////////////////////
                              HATS STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;
    uint32 public lastTopHatId;
    string public baseImageURI;
    mapping(uint256 => Hat) internal _hats;
    mapping(uint256 => mapping(address => bool)) public badStandings;
    mapping(address => mapping(uint256 => uint256)) internal _balanceOf;

    // HatsIdUtilities storage
    mapping(uint32 => uint256) public linkedTreeRequests;
    mapping(uint32 => uint256) public linkedTreeAdmins;

    uint256 internal constant TOPHAT_ADDRESS_SPACE = 32;
    uint256 internal constant LOWER_LEVEL_ADDRESS_SPACE = 16;
    uint256 internal constant MAX_LEVELS = 14;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _baseImageURI) {
        name = _name;
        baseImageURI = _baseImageURI;
    }

    /*//////////////////////////////////////////////////////////////
                              HATS LOGIC
    //////////////////////////////////////////////////////////////*/

    function mintTopHat(
        address _target,
        string calldata _details,
        string calldata _imageURI
    ) public returns (uint256 topHatId) {
        topHatId = uint256(++lastTopHatId) << 224;

        _createHat(topHatId, _details, 1, address(0), address(0), false, _imageURI);

        _mintHat(_target, topHatId);
    }

    function createHat(
        uint256 _admin,
        string calldata _details,
        uint32 _maxSupply,
        address _eligibility,
        address _toggle,
        bool _mutable,
        string calldata _imageURI
    ) public returns (uint256 newHatId) {
        if (uint16(_admin) > 0) {
            revert MaxLevelsReached();
        }

        if (_eligibility == address(0)) revert ZeroAddress();
        if (_toggle == address(0)) revert ZeroAddress();
        if (!isValidHatId(_admin)) revert InvalidHatId();

        newHatId = getNextId(_admin);
        _checkAdmin(newHatId);
        _createHat(newHatId, _details, _maxSupply, _eligibility, _toggle, _mutable, _imageURI);
        ++_hats[_admin].lastHatId;
    }

    function getNextId(uint256 _admin) public view returns (uint256 nextId) {
        uint16 nextHatId = _hats[_admin].lastHatId + 1;
        nextId = buildHatId(_admin, nextHatId);
    }

    function mintHat(uint256 _hatId, address _wearer) public returns (bool success) {
        Hat storage hat = _hats[_hatId];
        if (hat.maxSupply == 0) revert HatDoesNotExist(_hatId);
        if (!isEligible(_wearer, _hatId)) revert NotEligible();
        if (!_isActive(hat, _hatId)) revert HatNotActive();
        _checkAdmin(_hatId);
        if (hat.supply >= hat.maxSupply) revert AllHatsWorn(_hatId);
        if (_balanceOf[_wearer][_hatId] > 0) revert AlreadyWearingHat(_wearer, _hatId);
        _mintHat(_wearer, _hatId);
        success = true;
    }

    function setHatStatus(uint256 _hatId, bool _newStatus) external returns (bool toggled) {
        Hat storage hat = _hats[_hatId];
        if (msg.sender != hat.toggle) {
            revert NotHatsToggle();
        }
        toggled = _processHatStatus(_hatId, _newStatus);
    }

    function setHatWearerStatus(
        uint256 _hatId,
        address _wearer,
        bool _eligible,
        bool _standing
    ) external returns (bool updated) {
        Hat storage hat = _hats[_hatId];
        if (msg.sender != hat.eligibility) {
            revert NotHatsEligibility();
        }
        updated = _processHatWearerStatus(_hatId, _wearer, _eligible, _standing);
    }

    function renounceHat(uint256 _hatId) external {
        if (_balanceOf[msg.sender][_hatId] < 1) {
            revert NotHatWearer();
        }
        _burnHat(msg.sender, _hatId);
    }

    /*//////////////////////////////////////////////////////////////
                              HATS INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _createHat(
        uint256 _id,
        string calldata _details,
        uint32 _maxSupply,
        address _eligibility,
        address _toggle,
        bool _mutable,
        string calldata _imageURI
    ) internal {
        Hat storage hat = _hats[_id];
        hat.details = _details;
        hat.maxSupply = _maxSupply;
        hat.eligibility = _eligibility;
        hat.toggle = _toggle;
        hat.imageURI = _imageURI;
        hat.config = _mutable ? uint96(3 << 94) : uint96(1 << 95);

        emit HatCreated(_id, _details, _maxSupply, _eligibility, _toggle, _mutable, _imageURI);
    }

    function _mintHat(address _wearer, uint256 _hatId) internal {
        unchecked {
            _balanceOf[_wearer][_hatId] = 1;
            ++_hats[_hatId].supply;
        }
        emit TransferSingle(msg.sender, address(0), _wearer, _hatId, 1);
    }

    function _burnHat(address _wearer, uint256 _hatId) internal {
        _balanceOf[_wearer][_hatId] = 0;
        unchecked {
            --_hats[_hatId].supply;
        }
        emit TransferSingle(msg.sender, _wearer, address(0), _hatId, 1);
    }

    function _processHatStatus(uint256 _hatId, bool _newStatus) internal returns (bool updated) {
        Hat storage hat = _hats[_hatId];
        if (_newStatus != _getHatStatus(hat)) {
            _setHatStatus(hat, _newStatus);
            emit HatStatusChanged(_hatId, _newStatus);
            updated = true;
        }
    }

    function _processHatWearerStatus(
        uint256 _hatId,
        address _wearer,
        bool _eligible,
        bool _standing
    ) internal returns (bool updated) {
        if (_balanceOf[_wearer][_hatId] > 0) {
            if (!_eligible || !_standing) {
                _burnHat(_wearer, _hatId);
            }
        }

        if (_standing == badStandings[_hatId][_wearer]) {
            badStandings[_hatId][_wearer] = !_standing;
            updated = true;
            emit WearerStandingChanged(_hatId, _wearer, _standing);
        }
    }

    function _setHatStatus(Hat storage _hat, bool _status) internal {
        if (_status) {
            _hat.config |= uint96(1 << 95);
        } else {
            _hat.config &= ~uint96(1 << 95);
        }
    }

    function _getHatStatus(Hat storage _hat) internal view returns (bool) {
        return (_hat.config >> 95) & 1 == 1;
    }

    function _isMutable(Hat storage _hat) internal view returns (bool) {
        return (_hat.config >> 94) & 1 == 1;
    }

    function _checkAdmin(uint256 _hatId) internal view {
        if (!isAdminOfHat(msg.sender, _hatId)) {
            revert NotAdmin(msg.sender, _hatId);
        }
    }

    function _isActive(Hat storage _hat, uint256 _hatId) internal view returns (bool active) {
        if (_hat.toggle == address(0)) {
            active = _getHatStatus(_hat);
        } else {
            (bool success, bytes memory returndata) = _hat.toggle.staticcall(
                abi.encodeWithSignature("getHatStatus(uint256)", _hatId)
            );
            if (success && returndata.length == 32) {
                uint256 status = abi.decode(returndata, (uint256));
                if (status == 1) {
                    active = true;
                } else if (status == 0) {
                    active = false;
                } else {
                    active = _getHatStatus(_hat);
                }
            } else {
                active = _getHatStatus(_hat);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function viewHat(
        uint256 _hatId
    )
        external
        view
        returns (
            string memory details,
            uint32 maxSupply,
            uint32 supply,
            address eligibility,
            address toggle,
            string memory imageURI,
            uint16 lastHatId,
            bool mutable_,
            bool active
        )
    {
        Hat storage hat = _hats[_hatId];
        details = hat.details;
        maxSupply = hat.maxSupply;
        supply = hat.supply;
        eligibility = hat.eligibility;
        toggle = hat.toggle;
        imageURI = hat.imageURI;
        lastHatId = hat.lastHatId;
        mutable_ = _isMutable(hat);
        active = _isActive(hat, _hatId);
    }

    function isWearerOfHat(address _user, uint256 _hatId) public view returns (bool isWearer) {
        isWearer = balanceOf(_user, _hatId) > 0;
    }

    function isAdminOfHat(address _user, uint256 _hatId) public view returns (bool isAdmin) {
        uint256 linkedTreeAdmin;
        uint32 adminLocalHatLevel;

        if (isLocalTopHat(_hatId)) {
            linkedTreeAdmin = linkedTreeAdmins[getTopHatDomain(_hatId)];
            if (linkedTreeAdmin == 0) {
                isAdmin = isWearerOfHat(_user, _hatId);
            } else {
                isAdmin = isAdminOfHat(_user, linkedTreeAdmin);
            }
        } else {
            adminLocalHatLevel = getLocalHatLevel(_hatId) - 1;
            while (true) {
                if (isWearerOfHat(_user, getAdminAtLocalLevel(_hatId, adminLocalHatLevel))) {
                    isAdmin = true;
                    break;
                }
                if (adminLocalHatLevel == 0) {
                    linkedTreeAdmin = linkedTreeAdmins[getTopHatDomain(_hatId)];
                    if (linkedTreeAdmin == 0) break;
                    isAdmin = isAdminOfHat(_user, linkedTreeAdmin);
                    break;
                }
                unchecked {
                    --adminLocalHatLevel;
                }
            }
        }
    }

    function isInGoodStanding(address _wearer, uint256 _hatId) public view returns (bool standing) {
        standing = !badStandings[_hatId][_wearer];
        if (standing) {
            Hat storage hat = _hats[_hatId];
            if (hat.eligibility != address(0)) {
                (bool success, bytes memory returndata) = hat.eligibility.staticcall(
                    abi.encodeWithSignature("getWearerStatus(address,uint256)", _wearer, _hatId)
                );
                if (success && returndata.length == 64) {
                    (, uint256 standingWord) = abi.decode(returndata, (uint256, uint256));
                    if (standingWord < 2) {
                        standing = standingWord == 1;
                    }
                }
            }
        }
    }

    function isEligible(address _wearer, uint256 _hatId) public view returns (bool eligible) {
        Hat storage hat = _hats[_hatId];
        if (hat.eligibility == address(0)) {
            eligible = true;
        } else {
            (bool success, bytes memory returndata) = hat.eligibility.staticcall(
                abi.encodeWithSignature("getWearerStatus(address,uint256)", _wearer, _hatId)
            );
            if (success && returndata.length == 64) {
                (uint256 eligibleWord, uint256 standingWord) = abi.decode(returndata, (uint256, uint256));
                if (eligibleWord < 2 && standingWord < 2) {
                    eligible = eligibleWord == 1 && standingWord == 1;
                }
            }
        }
    }

    function balanceOf(address _wearer, uint256 _hatId) public view returns (uint256 balance) {
        Hat storage hat = _hats[_hatId];
        if (_balanceOf[_wearer][_hatId] > 0 && _isActive(hat, _hatId) && isEligible(_wearer, _hatId)) {
            balance = 1;
        }
    }

    function getHatEligibilityModule(uint256 _hatId) external view returns (address eligibility) {
        eligibility = _hats[_hatId].eligibility;
    }

    function getHatToggleModule(uint256 _hatId) external view returns (address toggle) {
        toggle = _hats[_hatId].toggle;
    }

    function getHatMaxSupply(uint256 _hatId) external view returns (uint32 maxSupply) {
        maxSupply = _hats[_hatId].maxSupply;
    }

    function hatSupply(uint256 _hatId) external view returns (uint32 supply) {
        supply = _hats[_hatId].supply;
    }

    /*//////////////////////////////////////////////////////////////
                          HATS ID UTILITIES
    //////////////////////////////////////////////////////////////*/

    function buildHatId(uint256 _admin, uint16 _newHat) public pure returns (uint256 id) {
        uint256 mask;
        for (uint256 i = 0; i < MAX_LEVELS; ) {
            unchecked {
                mask = uint256(type(uint256).max >> (TOPHAT_ADDRESS_SPACE + (LOWER_LEVEL_ADDRESS_SPACE * i)));
            }
            if (_admin & mask == 0) {
                unchecked {
                    id = _admin | (uint256(_newHat) << (LOWER_LEVEL_ADDRESS_SPACE * (MAX_LEVELS - 1 - i)));
                }
                return id;
            }
            unchecked {
                ++i;
            }
        }
        revert MaxLevelsReached();
    }

    function getHatLevel(uint256 _hatId) public view returns (uint32 level) {
        level = getLocalHatLevel(_hatId);
        uint256 treeAdmin = linkedTreeAdmins[getTopHatDomain(_hatId)];
        if (treeAdmin != 0) {
            level = 1 + level + getHatLevel(treeAdmin);
        }
    }

    function getLocalHatLevel(uint256 _hatId) public pure returns (uint32 level) {
        if (_hatId & uint256(type(uint224).max) == 0) return 0;
        if (_hatId & uint256(type(uint208).max) == 0) return 1;
        if (_hatId & uint256(type(uint192).max) == 0) return 2;
        if (_hatId & uint256(type(uint176).max) == 0) return 3;
        if (_hatId & uint256(type(uint160).max) == 0) return 4;
        if (_hatId & uint256(type(uint144).max) == 0) return 5;
        if (_hatId & uint256(type(uint128).max) == 0) return 6;
        if (_hatId & uint256(type(uint112).max) == 0) return 7;
        if (_hatId & uint256(type(uint96).max) == 0) return 8;
        if (_hatId & uint256(type(uint80).max) == 0) return 9;
        if (_hatId & uint256(type(uint64).max) == 0) return 10;
        if (_hatId & uint256(type(uint48).max) == 0) return 11;
        if (_hatId & uint256(type(uint32).max) == 0) return 12;
        if (_hatId & uint256(type(uint16).max) == 0) return 13;
        return 14;
    }

    function isTopHat(uint256 _hatId) public view returns (bool _isTopHat) {
        _isTopHat = isLocalTopHat(_hatId) && linkedTreeAdmins[getTopHatDomain(_hatId)] == 0;
    }

    function isLocalTopHat(uint256 _hatId) public pure returns (bool _isLocalTopHat) {
        _isLocalTopHat = _hatId > 0 && uint224(_hatId) == 0;
    }

    function isValidHatId(uint256 _hatId) public pure returns (bool validHatId) {
        if (isLocalTopHat(_hatId)) return true;
        uint32 level = getLocalHatLevel(_hatId);
        uint256 admin;
        for (uint256 i = level - 1; i > 0; ) {
            admin = _hatId >> (LOWER_LEVEL_ADDRESS_SPACE * (MAX_LEVELS - i));
            if (uint16(admin) == 0) return false;
            unchecked {
                --i;
            }
        }
        return true;
    }

    function getAdminAtLocalLevel(uint256 _hatId, uint32 _level) public pure returns (uint256 admin) {
        uint256 mask = type(uint256).max << (LOWER_LEVEL_ADDRESS_SPACE * (MAX_LEVELS - _level));
        admin = _hatId & mask;
    }

    function getTopHatDomain(uint256 _hatId) public pure returns (uint32 domain) {
        domain = uint32(_hatId >> (LOWER_LEVEL_ADDRESS_SPACE * MAX_LEVELS));
    }
}
