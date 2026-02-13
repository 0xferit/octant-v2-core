// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { ERC20SafeApproveLib } from "src/core/libs/ERC20SafeApproveLib.sol";
import { IMultistrategyVault } from "src/core/interfaces/IMultistrategyVault.sol";

/// @notice Standard ERC20 that returns true on approve
contract MockStandardToken {
    mapping(address => mapping(address => uint256)) public allowances;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice USDT-like token that returns no data on approve
contract MockNoReturnToken {
    mapping(address => mapping(address => uint256)) public allowances;

    function approve(address spender, uint256 amount) external {
        allowances[msg.sender][spender] = amount;
        // No return value - like USDT
    }
}

/// @notice Token that returns false on approve (instead of reverting)
contract MockFalseReturnToken {
    function approve(address, uint256) external pure returns (bool) {
        return false;
    }
}

/// @notice Token that reverts on approve
contract MockRevertingToken {
    function approve(address, uint256) external pure {
        revert("approve reverted");
    }
}

/// @notice Wrapper contract to use the library (libraries use delegatecall internally,
///         but external library functions use a regular call from the test contract)
contract SafeApproveWrapper {
    using ERC20SafeApproveLib for address;

    function safeApprove(address token, address spender, uint256 amount) external {
        token.safeApprove(spender, amount);
    }
}

contract ERC20SafeApproveLibTest is Test {
    SafeApproveWrapper wrapper;
    address spender = address(0xBEEF);

    function setUp() public {
        wrapper = new SafeApproveWrapper();
    }

    /// @notice Branch: success == true && data.length == 0 (USDT-like, no return data)
    function test_safeApprove_noReturnData_succeeds() public {
        MockNoReturnToken token = new MockNoReturnToken();
        // Should not revert
        wrapper.safeApprove(address(token), spender, 100);
    }

    /// @notice Branch: success == true && data returns true (standard ERC20)
    function test_safeApprove_returnTrue_succeeds() public {
        MockStandardToken token = new MockStandardToken();
        // Should not revert
        wrapper.safeApprove(address(token), spender, 100);
    }

    /// @notice Branch: success == true && data returns false
    function test_safeApprove_returnFalse_reverts() public {
        MockFalseReturnToken token = new MockFalseReturnToken();
        vm.expectRevert(IMultistrategyVault.ApprovalFailed.selector);
        wrapper.safeApprove(address(token), spender, 100);
    }

    /// @notice Branch: success == false (call reverts)
    function test_safeApprove_callReverts_reverts() public {
        MockRevertingToken token = new MockRevertingToken();
        vm.expectRevert(IMultistrategyVault.ApprovalFailed.selector);
        wrapper.safeApprove(address(token), spender, 100);
    }

    /// @notice Branch: success == false (call to EOA / non-contract address)
    function test_safeApprove_nonContract_succeeds() public {
        // Calling approve on an EOA (no code) returns success=true, data.length=0
        // This is how low-level call works on addresses with no code
        address eoa = address(0x1234);
        wrapper.safeApprove(eoa, spender, 100);
    }
}
