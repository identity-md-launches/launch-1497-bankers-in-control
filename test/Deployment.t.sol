// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CharterClaim} from "../src/CharterClaim.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @dev Local deployment/allocation model, not the network's actual factory or pool.
contract LaunchModel {
    function deploy() external returns (LaunchToken token, CharterClaim claims) {
        token = new LaunchToken();
        claims = new CharterClaim(address(token));
    }

    function launch(address pool, address swarm) external returns (LaunchToken token, CharterClaim claims) {
        token = new LaunchToken();
        claims = new CharterClaim(address(token));
        token.transfer(pool, 100_000_000 ether);
        token.transfer(swarm, 100_000_000 ether);
        token.transfer(address(claims), 800_000_000 ether);
    }
}

contract DeploymentTest is Test {
    function test_constructorsLeaveAllSupplyWithFactory() public {
        LaunchModel factory = new LaunchModel();
        (LaunchToken token, CharterClaim claims) = factory.deploy();
        assertEq(token.balanceOf(address(factory)), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(claims)), 0);
        assertEq(address(claims.token()), address(token));
    }

    function test_allocationHandoffCanFundClaimsInSameTransaction() public {
        LaunchModel factory = new LaunchModel();
        address pool = makeAddr("test pool allocation sink");
        address swarm = makeAddr("test swarm allocation sink");
        (LaunchToken token, CharterClaim claims) = factory.launch(pool, swarm);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(pool), 100_000_000 ether);
        assertEq(token.balanceOf(swarm), 100_000_000 ether);
        assertEq(token.balanceOf(address(claims)), 800_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function test_claimConstructorSucceedsWithoutTokenOrNftCode() public {
        address tokenAddress = makeAddr("constructor-only token parameter");
        assertEq(tokenAddress.code.length, 0);
        CharterClaim claims = new CharterClaim(tokenAddress);
        assertEq(claims.CHARTER().code.length, 0);
        assertEq(address(claims.token()), tokenAddress);
    }

    function test_runtimeWithinSizeLimitAndNoForbiddenOpcodes() public {
        LaunchToken token = new LaunchToken();
        CharterClaim claims = new CharterClaim(address(token));
        _checkRuntime(address(token).code);
        _checkRuntime(address(claims).code);
    }

    function test_charterClaimHasNoAdminRecoveryOrApprovalEntryPoints() public {
        LaunchToken token = new LaunchToken();
        CharterClaim claims = new CharterClaim(address(token));
        token.transfer(address(claims), 800_000_000 ether);
        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeWithSignature("owner()");
        calls[1] = abi.encodeWithSignature("withdraw(address,uint256)", address(token), 1);
        calls[2] = abi.encodeWithSignature("withdraw()");
        calls[3] = abi.encodeWithSignature("recoverERC20(address,uint256)", address(token), 1);
        calls[4] = abi.encodeWithSignature("transferOwnership(address)", address(this));
        calls[5] = abi.encodeWithSignature("upgradeTo(address)", address(this));
        calls[6] = abi.encodeWithSignature("pause()");
        calls[7] = abi.encodeWithSignature("setToken(address)", address(token));
        calls[8] = abi.encodeWithSignature("approve(address,uint256)", address(this), 1);
        calls[9] = abi.encodeWithSignature("initialize(address)", address(this));
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(claims).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(token.balanceOf(address(claims)), 800_000_000 ether);
        assertEq(token.allowance(address(claims), address(this)), 0);
    }

    function _checkRuntime(bytes memory code) private pure {
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            }
        }
    }
}
