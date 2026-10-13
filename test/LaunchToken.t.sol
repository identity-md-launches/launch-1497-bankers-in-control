// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    LaunchToken private token;
    address private alice;
    address private bob;

    function setUp() public {
        token = new LaunchToken();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    function test_metadataAndSupplyBelongToDeployer() public view {
        assertEq(token.name(), "Bankers In Control");
        assertEq(token.symbol(), "BIC");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferHasNoFeesOrSupplyChange(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalAndTransferFrom() public {
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        assertTrue(token.approve(bob, 7 ether));
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 6 ether));
        assertEq(token.balanceOf(alice), 4 ether);
        assertEq(token.balanceOf(bob), 6 ether);
        assertEq(token.allowance(alice, bob), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 1 ether, 2 ether));
        vm.prank(bob);
        token.transferFrom(alice, bob, 2 ether);
    }

    function test_insufficientBalanceAndZeroRecipientRevert() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintOwnerPauseUpgradeOrBurnEntryPoints() public {
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", alice, 1 ether);
        calls[1] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[2] = abi.encodeWithSignature("pause()");
        calls[3] = abi.encodeWithSignature("upgradeTo(address)", alice);
        calls[4] = abi.encodeWithSignature("initialize(address)", alice);
        calls[5] = abi.encodeWithSignature("setMinter(address)", alice);
        calls[6] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[7] = abi.encodeWithSignature("owner()");
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerOK,) = address(token).call(calls[i]);
            assertFalse(deployerOK);
            vm.prank(alice);
            (bool otherOK,) = address(token).call(calls[i]);
            assertFalse(otherOK);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }
}
