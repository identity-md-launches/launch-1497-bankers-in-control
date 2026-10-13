// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {CharterClaim} from "../src/CharterClaim.sol";
import {CharterFixture} from "./helpers/CharterFixture.sol";
import {AdversarialToken} from "./helpers/AdversarialToken.sol";

contract CharterClaimAdversarialTest is CharterFixture {
    AdversarialToken private otherToken;
    CharterClaim private otherClaims;

    function setUp() public override {
        super.setUp();
        otherToken = new AdversarialToken();
        otherClaims = new CharterClaim(address(otherToken));
        otherToken.transfer(address(otherClaims), ALLOCATION);
    }

    function test_falseReturnRollsBackBothPhasesAndAllowsRetry() public {
        _assertFailureAndRetry(AdversarialToken.Mode.FalseReturn);
    }

    function test_revertingTransferRollsBackBothPhasesAndAllowsRetry() public {
        _assertFailureAndRetry(AdversarialToken.Mode.RevertTransfer);
    }

    function test_malformedReturnRollsBackEvenIfTokenMovedBalances() public {
        _assertFailureAndRetry(AdversarialToken.Mode.MalformedReturn);
    }

    function test_tokenWithoutReturnValueIsSupported() public {
        otherToken.setMode(AdversarialToken.Mode.NoReturn);
        charter.mint(alice, 1);
        vm.prank(alice);
        otherClaims.claim(_one(1));
        charter.burn(1);
        vm.prank(alice);
        otherClaims.claimRest(_one(1));
        assertEq(otherToken.balanceOf(alice), SHARE);
        assertTrue(otherClaims.restClaimed(1));
    }

    function test_initialCallbackSeesWholeBatchRecordedAndCannotReenterEitherPhase() public {
        charter.mint(address(otherToken), 1);
        charter.mint(address(otherToken), 2);
        otherToken.configureCallback(otherClaims, _two(1, 2), false);
        otherToken.start(otherClaims, _two(1, 2), false);
        _assertReentrancyBlocked();
        assertEq(otherToken.balanceOf(address(otherToken)), 2 * INSTANT);
        assertEq(otherToken.balanceOf(address(otherClaims)), ALLOCATION - 2 * INSTANT);
        assertFalse(otherClaims.restClaimed(1));
        assertFalse(otherClaims.restClaimed(2));
        // The callback burned both NFTs. A later, separate rest call remains valid.
        otherToken.setMode(AdversarialToken.Mode.Normal);
        otherToken.start(otherClaims, _two(1, 2), true);
        assertEq(otherToken.balanceOf(address(otherToken)), 2 * SHARE);
    }

    function test_restCallbackSeesWholeBatchPaidAndCannotReenterEitherPhase() public {
        charter.mint(address(otherToken), 1);
        charter.mint(address(otherToken), 2);
        otherToken.start(otherClaims, _two(1, 2), false);
        charter.burn(1);
        charter.burn(2);
        otherToken.configureCallback(otherClaims, _two(1, 2), true);
        otherToken.start(otherClaims, _two(1, 2), true);
        _assertReentrancyBlocked();
        assertTrue(otherClaims.restClaimed(1));
        assertTrue(otherClaims.restClaimed(2));
        assertEq(otherToken.balanceOf(address(otherToken)), 2 * SHARE);
        assertEq(otherToken.balanceOf(address(otherClaims)), ALLOCATION - 2 * SHARE);
    }

    function test_tokenWithoutCodeFailsOnFirstPayoutAndLeavesIdUnclaimed() public {
        address noCode = makeAddr("non-contract token");
        CharterClaim misconfigured = new CharterClaim(noCode);
        charter.mint(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, noCode));
        vm.prank(alice);
        misconfigured.claim(_one(1));
        assertEq(misconfigured.claimant(1), address(0));
    }

    function test_missingCharterCodeFailsWithoutPaying() public {
        vm.etch(CHARTER_ADDRESS, bytes(""));
        vm.expectRevert();
        vm.prank(alice);
        claims.claim(_one(1));
        vm.expectRevert();
        vm.prank(alice);
        claims.claimRest(_one(1));
        assertEq(token.balanceOf(address(claims)), ALLOCATION);
        assertEq(claims.claimant(1), address(0));
    }

    function _assertFailureAndRetry(AdversarialToken.Mode badMode) private {
        charter.mint(alice, 1);
        charter.mint(alice, 2);
        otherToken.setMode(badMode);
        _expectTransferFailure(badMode);
        vm.prank(alice);
        otherClaims.claim(_two(1, 2));
        assertFalse(otherClaims.instantClaimed(1));
        assertFalse(otherClaims.instantClaimed(2));
        assertEq(otherToken.balanceOf(alice), 0);
        assertEq(otherToken.balanceOf(address(otherClaims)), ALLOCATION);

        otherToken.setMode(AdversarialToken.Mode.Normal);
        vm.prank(alice);
        otherClaims.claim(_two(1, 2));
        charter.burn(1);
        charter.burn(2);

        otherToken.setMode(badMode);
        _expectTransferFailure(badMode);
        vm.prank(alice);
        otherClaims.claimRest(_two(1, 2));
        assertFalse(otherClaims.restClaimed(1));
        assertFalse(otherClaims.restClaimed(2));
        assertEq(otherClaims.claimant(1), alice);
        assertEq(otherClaims.claimant(2), alice);
        assertEq(otherToken.balanceOf(alice), 2 * INSTANT);
        assertEq(otherToken.balanceOf(address(otherClaims)), ALLOCATION - 2 * INSTANT);

        otherToken.setMode(AdversarialToken.Mode.Normal);
        vm.prank(alice);
        otherClaims.claimRest(_two(1, 2));
        assertEq(otherToken.balanceOf(alice), 2 * SHARE);
    }

    function _expectTransferFailure(AdversarialToken.Mode badMode) private {
        if (badMode == AdversarialToken.Mode.FalseReturn) {
            vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(otherToken)));
        } else if (badMode == AdversarialToken.Mode.RevertTransfer) {
            vm.expectRevert(AdversarialToken.TransferRejected.selector);
        } else {
            vm.expectRevert();
        }
    }

    function _assertReentrancyBlocked() private view {
        assertTrue(otherToken.sawEffects());
        assertFalse(otherToken.nestedInstantSucceeded());
        assertFalse(otherToken.nestedRestSucceeded());
        bytes memory expected = abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(otherToken.nestedInstantResult(), expected);
        assertEq(otherToken.nestedRestResult(), expected);
    }
}
