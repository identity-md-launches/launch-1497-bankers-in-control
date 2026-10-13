// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CharterClaim} from "../src/CharterClaim.sol";
import {CharterFixture} from "./helpers/CharterFixture.sol";
import {MockCharter} from "./helpers/MockCharter.sol";

contract CharterClaimTest is CharterFixture {
    event Claimed(uint256 indexed id, address indexed account, uint256 amount, bool rest);

    function test_constantsAndInitialState() public view {
        assertEq(claims.CHARTER(), CHARTER_ADDRESS);
        assertEq(claims.MAX_ID(), MAX_ID);
        assertEq(claims.ALLOCATION(), ALLOCATION);
        assertEq(claims.SHARE(), SHARE);
        assertEq(claims.INSTANT(), INSTANT);
        assertEq(claims.REST(), REST);
        assertEq(INSTANT + REST, SHARE);
        assertEq(address(claims.token()), address(token));
        assertEq(claims.claimant(1), address(0));
        assertFalse(claims.instantClaimed(1));
        assertFalse(claims.restClaimed(1));
    }

    function test_constructorRejectsZeroToken() public {
        vm.expectRevert(CharterClaim.InvalidToken.selector);
        new CharterClaim(address(0));
    }

    function test_claimSinglePaysOwnerAndEmitsEvent() public {
        charter.mint(alice, 1);
        vm.expectEmit(true, true, false, true, address(claims));
        emit Claimed(1, alice, INSTANT, false);
        vm.prank(alice);
        claims.claim(_one(1));

        assertEq(token.balanceOf(alice), INSTANT);
        assertEq(token.balanceOf(address(claims)), ALLOCATION - INSTANT);
        assertEq(claims.claimant(1), alice);
        assertTrue(claims.instantClaimed(1));
        assertFalse(claims.restClaimed(1));
        assertEq(charter.ownerOf(1), alice);
    }

    function test_unsortedBatchIncludesBothBoundariesAndUsesOneTransfer() public {
        charter.mint(alice, MAX_ID);
        charter.mint(alice, 1);
        vm.recordLogs();
        vm.prank(alice);
        claims.claim(_two(MAX_ID, 1));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 3);
        _assertPaymentLogs(logs, false, 2 * INSTANT);
        assertEq(token.balanceOf(alice), 2 * INSTANT);
        assertEq(claims.claimant(1), alice);
        assertEq(claims.claimant(MAX_ID), alice);
    }

    function test_emptyBatchesRevert() public {
        vm.expectRevert(CharterClaim.EmptyBatch.selector);
        claims.claim(new uint256[](0));
        vm.expectRevert(CharterClaim.EmptyBatch.selector);
        claims.claimRest(new uint256[](0));
    }

    function test_zeroIdRejectedEvenIfNftExists() public {
        charter.mint(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.InvalidId.selector, 0));
        vm.prank(alice);
        claims.claim(_one(0));
    }

    function testFuzz_idsAboveCutoffRejected(uint256 rawId) public {
        uint256 id = bound(rawId, MAX_ID + 1, type(uint256).max);
        charter.mint(alice, id);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.InvalidId.selector, id));
        vm.prank(alice);
        claims.claim(_one(id));
        assertEq(token.balanceOf(alice), 0);
    }

    function test_nonexistentCharterCannotClaim() public {
        vm.expectRevert(abi.encodeWithSelector(MockCharter.NonexistentToken.selector, 500));
        vm.prank(alice);
        claims.claim(_one(500));
        assertFalse(claims.instantClaimed(500));
    }

    function test_approvedOperatorCannotClaim() public {
        charter.mint(alice, 1);
        vm.prank(alice);
        charter.approve(bob, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotCharterOwner.selector, 1));
        vm.prank(bob);
        claims.claim(_one(1));
        assertEq(claims.claimant(1), address(0));
    }

    function test_onlyCurrentOwnerCanClaimBeforeInitialPayment() public {
        charter.mint(alice, 1);
        _transfer(alice, bob, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotCharterOwner.selector, 1));
        vm.prank(alice);
        claims.claim(_one(1));
        vm.prank(bob);
        claims.claim(_one(1));
        assertEq(claims.claimant(1), bob);
    }

    function test_duplicateInitialIdRollsBackWholeBatch() public {
        charter.mint(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.AlreadyClaimed.selector, 1));
        vm.prank(alice);
        claims.claim(_two(1, 1));
        assertEq(claims.claimant(1), address(0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(claims)), ALLOCATION);
        vm.prank(alice);
        claims.claim(_one(1));
    }

    function test_mixedOwnershipBatchRollsBackEarlierIds() public {
        charter.mint(alice, 1);
        charter.mint(bob, 2);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotCharterOwner.selector, 2));
        vm.prank(alice);
        claims.claim(_two(1, 2));
        assertEq(claims.claimant(1), address(0));
        assertEq(claims.claimant(2), address(0));
        assertEq(token.balanceOf(alice), 0);
    }

    function test_invalidLaterIdRollsBackEarlierIds() public {
        charter.mint(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.InvalidId.selector, MAX_ID + 1));
        vm.prank(alice);
        claims.claim(_two(1, MAX_ID + 1));
        assertFalse(claims.instantClaimed(1));
        assertEq(token.balanceOf(address(claims)), ALLOCATION);
    }

    function test_repeatedInitialClaimAndNewOwnerBothFail() public {
        _initial(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.AlreadyClaimed.selector, 1));
        vm.prank(alice);
        claims.claim(_one(1));
        _transfer(alice, bob, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.AlreadyClaimed.selector, 1));
        vm.prank(bob);
        claims.claim(_one(1));
        assertEq(claims.claimant(1), alice);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_restBlockedWhileHoldingClaimedCharter() public {
        _initial(alice, 1);
        vm.expectRevert(CharterClaim.StillHoldsCharter.selector);
        vm.prank(alice);
        claims.claimRest(_one(1));
        assertFalse(claims.restClaimed(1));
    }

    function test_restBlockedByUnclaimedCharter() public {
        _initial(alice, 1);
        charter.mint(alice, 2);
        _transfer(alice, bob, 1);
        vm.expectRevert(CharterClaim.StillHoldsCharter.selector);
        vm.prank(alice);
        claims.claimRest(_one(1));
        _assertClaimable(alice, INSTANT, 0);
    }

    function test_restBlockedByLaterMintAboveCutoffUntilItLeaves() public {
        _initial(alice, 1);
        _transfer(alice, bob, 1);
        charter.mint(alice, MAX_ID + 100);
        vm.expectRevert(CharterClaim.StillHoldsCharter.selector);
        vm.prank(alice);
        claims.claimRest(_one(1));
        _assertClaimable(alice, 0, 0);
        charter.burn(MAX_ID + 100);
        vm.prank(alice);
        claims.claimRest(_one(1));
        assertEq(token.balanceOf(alice), SHARE);
    }

    function test_restPaidToOriginalClaimantAfterTransfer() public {
        _initial(alice, 1);
        _transfer(alice, bob, 1);
        vm.expectEmit(true, true, false, true, address(claims));
        emit Claimed(1, alice, REST, true);
        vm.prank(alice);
        claims.claimRest(_one(1));
        assertEq(claims.claimant(1), alice);
        assertTrue(claims.instantClaimed(1));
        assertTrue(claims.restClaimed(1));
        assertEq(token.balanceOf(alice), SHARE);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(claims)), ALLOCATION - SHARE);
    }

    function test_restNeverQueriesBurnedOrRevokedIds() public {
        _initial(alice, 1);
        charter.burn(1);
        charter.failOwnerReads(true);
        _assertClaimable(alice, 0, REST);
        vm.prank(alice);
        claims.claimRest(_one(1));
        assertEq(token.balanceOf(alice), SHARE);
        _assertClaimable(alice, 0, 0);
    }

    function test_restUsesSingleTransferForBatch() public {
        _initial(alice, MAX_ID);
        _initial(alice, 1);
        charter.burn(MAX_ID);
        charter.burn(1);
        vm.recordLogs();
        vm.prank(alice);
        claims.claimRest(_two(MAX_ID, 1));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 3);
        _assertPaymentLogs(logs, true, 2 * REST);
        assertEq(token.balanceOf(alice), 2 * SHARE);
    }

    function test_restCannotBeClaimedBeforeInstantOrByAnotherAccount() public {
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotClaimant.selector, 1));
        vm.prank(alice);
        claims.claimRest(_one(1));
        _initial(alice, 1);
        _transfer(alice, bob, 1);
        charter.burn(1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotClaimant.selector, 1));
        vm.prank(bob);
        claims.claimRest(_one(1));
        assertFalse(claims.restClaimed(1));
    }

    function test_restRejectsOutOfRangeIds() public {
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.InvalidId.selector, 0));
        vm.prank(alice);
        claims.claimRest(_one(0));
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.InvalidId.selector, MAX_ID + 1));
        vm.prank(alice);
        claims.claimRest(_one(MAX_ID + 1));
    }

    function test_duplicateRestIdRollsBackWholeBatch() public {
        _initial(alice, 1);
        charter.burn(1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.RestAlreadyClaimed.selector, 1));
        vm.prank(alice);
        claims.claimRest(_two(1, 1));
        assertFalse(claims.restClaimed(1));
        assertEq(token.balanceOf(alice), INSTANT);
        vm.prank(alice);
        claims.claimRest(_one(1));
    }

    function test_mixedClaimantRestBatchRollsBackEarlierIds() public {
        _initial(alice, 1);
        _initial(bob, 2);
        charter.burn(1);
        charter.burn(2);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotClaimant.selector, 2));
        vm.prank(alice);
        claims.claimRest(_two(1, 2));
        assertFalse(claims.restClaimed(1));
        assertFalse(claims.restClaimed(2));
        assertEq(token.balanceOf(alice), INSTANT);
    }

    function test_restCannotBePaidTwiceOrResetByRemint() public {
        _initial(alice, 1);
        charter.burn(1);
        vm.prank(alice);
        claims.claimRest(_one(1));
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.RestAlreadyClaimed.selector, 1));
        vm.prank(alice);
        claims.claimRest(_one(1));
        charter.mint(bob, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.AlreadyClaimed.selector, 1));
        vm.prank(bob);
        claims.claim(_one(1));
        assertEq(claims.claimant(1), alice);
        assertEq(token.balanceOf(alice), SHARE);
    }

    function test_reacquiringCharterBlocksOnlyUnpaidRest() public {
        _initial(alice, 1);
        _initial(alice, 2);
        _transfer(alice, bob, 1);
        _transfer(alice, bob, 2);
        vm.prank(alice);
        claims.claimRest(_one(1));
        _transfer(bob, alice, 1);
        vm.expectRevert(CharterClaim.StillHoldsCharter.selector);
        vm.prank(alice);
        claims.claimRest(_one(2));
        _assertClaimable(alice, 0, 0);
        _transfer(alice, bob, 1);
        _assertClaimable(alice, 0, REST);
        vm.prank(alice);
        claims.claimRest(_one(2));
        assertEq(token.balanceOf(alice), 2 * SHARE);
    }

    function test_underfundedInstantRevertsAndCanBeRetriedAfterFunding() public {
        CharterClaim unfunded = new CharterClaim(address(token));
        charter.mint(alice, 1);
        charter.mint(alice, 2);
        token.transfer(address(unfunded), 2 * INSTANT - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(unfunded), 2 * INSTANT - 1, 2 * INSTANT
            )
        );
        vm.prank(alice);
        unfunded.claim(_two(1, 2));
        assertFalse(unfunded.instantClaimed(1));
        assertFalse(unfunded.instantClaimed(2));
        assertEq(token.balanceOf(alice), 0);
        token.transfer(address(unfunded), 1);
        vm.prank(alice);
        unfunded.claim(_two(1, 2));
        assertEq(token.balanceOf(alice), 2 * INSTANT);
    }

    function test_underfundedRestRevertsAndPreservesClaimant() public {
        CharterClaim unfunded = new CharterClaim(address(token));
        token.transfer(address(unfunded), INSTANT);
        charter.mint(alice, 1);
        vm.prank(alice);
        unfunded.claim(_one(1));
        charter.burn(1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(unfunded), 0, REST)
        );
        vm.prank(alice);
        unfunded.claimRest(_one(1));
        assertEq(unfunded.claimant(1), alice);
        assertFalse(unfunded.restClaimed(1));
        token.transfer(address(unfunded), REST);
        vm.prank(alice);
        unfunded.claimRest(_one(1));
        assertEq(token.balanceOf(alice), SHARE);
    }

    function test_failedCharterBalanceReadFailsClosed() public {
        _initial(alice, 1);
        charter.burn(1);
        charter.failBalanceReads(true);
        vm.expectRevert(MockCharter.ReadUnavailable.selector);
        vm.prank(alice);
        claims.claimRest(_one(1));
        assertFalse(claims.restClaimed(1));
        vm.expectRevert(MockCharter.ReadUnavailable.selector);
        claims.claimable(alice);
    }

    function test_claimableSkipsMissingBurnedAndOutOfRangeIds() public {
        charter.mint(alice, 2);
        charter.mint(alice, MAX_ID);
        charter.mint(alice, 101);
        charter.burn(101);
        charter.mint(alice, MAX_ID + 1);
        charter.mint(bob, 17);
        _assertClaimable(alice, 2 * INSTANT, 0);
        _assertClaimable(bob, INSTANT, 0);
        _assertClaimable(carol, 0, 0);
        _assertClaimable(address(0), 0, 0);
        assertFalse(claims.instantClaimed(0));
        assertFalse(claims.restClaimed(MAX_ID + 1));
    }

    function test_claimableTracksPartialBatchesAndTransfers() public {
        charter.mint(alice, 1);
        charter.mint(alice, 2);
        charter.mint(alice, MAX_ID);
        vm.prank(alice);
        claims.claim(_two(1, MAX_ID));
        _assertClaimable(alice, INSTANT, 0);
        _transfer(alice, bob, 1);
        _transfer(alice, bob, MAX_ID);
        _transfer(alice, bob, 2);
        _assertClaimable(alice, 0, 2 * REST);
        _assertClaimable(bob, INSTANT, 0);
        vm.prank(alice);
        claims.claimRest(_one(MAX_ID));
        _assertClaimable(alice, 0, REST);
    }

    function test_laterMintWithinCutoffCanClaimButNoOtherSharesRedistribute() public {
        _initial(alice, 1);
        charter.burn(1);
        vm.prank(alice);
        claims.claimRest(_one(1));
        vm.warp(100 * 365 days);
        assertEq(token.balanceOf(address(claims)), ALLOCATION - SHARE);
        charter.mint(bob, MAX_ID);
        _assertClaimable(bob, INSTANT, 0);
        vm.prank(bob);
        claims.claim(_one(MAX_ID));
        assertEq(token.balanceOf(bob), INSTANT);
        assertEq(token.balanceOf(address(claims)), ALLOCATION - SHARE - INSTANT);
    }

    function test_allIdsPayExactlyOneShareAndLeaveOnlyRoundingDust() public {
        uint256[] memory ids = new uint256[](MAX_ID);
        for (uint256 id = 1; id <= MAX_ID; ++id) {
            charter.mint(alice, id);
            ids[id - 1] = id;
        }
        _assertClaimable(alice, MAX_ID * INSTANT, 0);
        vm.prank(alice);
        claims.claim(ids);
        for (uint256 id = 1; id <= MAX_ID; ++id) {
            charter.burn(id);
        }
        _assertClaimable(alice, 0, MAX_ID * REST);
        vm.prank(alice);
        claims.claimRest(ids);
        assertEq(token.balanceOf(alice), MAX_ID * SHARE);
        assertEq(token.balanceOf(address(claims)), 200);
        assertEq(token.balanceOf(alice) + token.balanceOf(address(claims)), ALLOCATION);
        _assertClaimable(alice, 0, 0);
    }

    function testFuzz_fullLifecyclePaysOneShare(uint256 rawId, bool burn) public {
        uint256 id = bound(rawId, 1, MAX_ID);
        _initial(alice, id);
        if (burn) charter.burn(id);
        else _transfer(alice, bob, id);
        vm.prank(alice);
        claims.claimRest(_one(id));
        assertEq(token.balanceOf(alice), SHARE);
        assertEq(token.balanceOf(address(claims)), ALLOCATION - SHARE);
        assertEq(claims.claimant(id), alice);
        assertTrue(claims.restClaimed(id));
    }

    function _assertPaymentLogs(Vm.Log[] memory logs, bool rest, uint256 total) private view {
        for (uint256 i; i < 2; ++i) {
            assertEq(logs[i].emitter, address(claims));
            assertEq(logs[i].topics[0], keccak256("Claimed(uint256,address,uint256,bool)"));
            assertEq(logs[i].topics[1], bytes32(i == 0 ? MAX_ID : 1));
            assertEq(logs[i].topics[2], bytes32(uint256(uint160(alice))));
            assertEq(logs[i].data, abi.encode(rest ? REST : INSTANT, rest));
        }
        assertEq(logs[2].emitter, address(token));
        assertEq(logs[2].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[2].topics[1], bytes32(uint256(uint160(address(claims)))));
        assertEq(logs[2].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(logs[2].data, abi.encode(total));
    }
}
