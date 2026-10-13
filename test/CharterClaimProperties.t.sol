// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CharterClaim} from "src/CharterClaim.sol";
import {CharterFixture} from "./helpers/CharterFixture.sol";
import {MockCharter} from "./helpers/MockCharter.sol";

/// @dev A real intermediate caller, to distinguish msg.sender from the originating wallet.
contract CharterClaimCaller {
    function forward(CharterClaim target, uint256[] calldata ids, bool rest) external {
        if (rest) target.claimRest(ids);
        else target.claim(ids);
    }
}

contract CharterClaimPropertiesTest is CharterFixture {
    /// @dev Compare two executions from identical state. Neither batch size nor permutation may
    /// change the entitlement, rounding dust, permanent beneficiary, or terminal flags.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_partitionAndOrderDoNotChangePayout(
        uint256 rawCount,
        uint256 rawStart,
        uint256 rawSplit,
        uint256 shuffleSeed
    ) public {
        uint256 count = bound(rawCount, 2, 32);
        uint256 start = bound(rawStart, 1, MAX_ID);
        uint256[] memory ids = _mintIds(alice, count, start);
        uint256 snapshot = vm.snapshotState();

        vm.prank(alice);
        claims.claim(ids);
        _burnIds(ids);
        vm.prank(alice);
        claims.claimRest(ids);
        uint256 batchPayout = token.balanceOf(alice);
        uint256 batchRemainder = token.balanceOf(address(claims));
        assertEq(batchPayout, count * SHARE);
        _assertTerminal(ids, alice);

        assertTrue(vm.revertToStateAndDelete(snapshot));
        _shuffle(ids, shuffleSeed);
        uint256 split = bound(rawSplit, 1, count - 1);
        vm.prank(alice);
        claims.claim(_slice(ids, 0, split));
        vm.prank(alice);
        claims.claim(_slice(ids, split, count));
        assertEq(token.balanceOf(alice), count * INSTANT);
        _burnIds(ids);

        // Reverse the payout order as well as changing the instant batch order.
        vm.prank(alice);
        claims.claimRest(_slice(ids, split, count));
        assertEq(token.balanceOf(alice), count * INSTANT + (count - split) * REST);
        vm.prank(alice);
        claims.claimRest(_slice(ids, 0, split));
        assertEq(token.balanceOf(alice), batchPayout);
        assertEq(token.balanceOf(address(claims)), batchRemainder);
        _assertTerminal(ids, alice);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_duplicateAnywhereRollsBackAndOriginalBatchRemainsUsable(
        uint256 rawCount,
        uint256 rawFirst,
        uint256 rawSecond,
        bool rest
    ) public {
        uint256 count = bound(rawCount, 2, 32);
        uint256[] memory ids = _mintIds(alice, count, 1);
        if (rest) {
            vm.prank(alice);
            claims.claim(ids);
            _burnIds(ids);
        }
        uint256 first = bound(rawFirst, 0, count - 2);
        uint256 second = bound(rawSecond, first + 1, count - 1);
        uint256[] memory duplicate = _slice(ids, 0, count);
        duplicate[second] = duplicate[first];
        bytes4 selector = rest ? CharterClaim.RestAlreadyClaimed.selector : CharterClaim.AlreadyClaimed.selector;
        uint256 balanceBefore = token.balanceOf(address(claims));
        uint256 userBefore = token.balanceOf(alice);

        vm.expectRevert(abi.encodeWithSelector(selector, duplicate[first]));
        vm.prank(alice);
        if (rest) claims.claimRest(duplicate);
        else claims.claim(duplicate);

        _assertUnchanged(ids, rest, balanceBefore, userBefore);
        vm.prank(alice);
        if (rest) claims.claimRest(ids);
        else claims.claim(ids);
        assertEq(token.balanceOf(alice), userBefore + count * (rest ? REST : INSTANT));
    }

    /// @dev Each run contains a valid prefix/suffix and one of six distinct invalid members.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_badInstantMemberIsAtomic(uint256 rawCount, uint256 rawPosition, uint8 rawReason) public {
        uint256 count = bound(rawCount, 1, 32);
        uint256[] memory ids = _mintIds(alice, count, 1);
        uint256[] memory poisoned = _slice(ids, 0, count);
        uint256 reason = rawReason % 6;
        uint256 badId = MAX_ID;
        bytes4 selector;
        if (reason == 0 || reason == 1) {
            badId = reason == 0 ? 0 : type(uint256).max;
            // Existence must not bypass the fixed ID range.
            charter.mint(alice, badId);
            selector = CharterClaim.InvalidId.selector;
        } else if (reason == 2) {
            charter.mint(bob, badId);
            selector = CharterClaim.NotCharterOwner.selector;
        } else if (reason == 3) {
            selector = MockCharter.NonexistentToken.selector;
        } else if (reason == 4) {
            charter.mint(alice, badId);
            charter.burn(badId);
            selector = MockCharter.NonexistentToken.selector;
        } else {
            _initial(alice, badId);
            selector = CharterClaim.AlreadyClaimed.selector;
        }
        poisoned[bound(rawPosition, 0, count - 1)] = badId;
        uint256 balanceBefore = token.balanceOf(address(claims));
        uint256 userBefore = token.balanceOf(alice);

        vm.expectRevert(abi.encodeWithSelector(selector, badId));
        vm.prank(alice);
        claims.claim(poisoned);

        _assertUnchanged(ids, false, balanceBefore, userBefore);
        assertEq(claims.claimant(badId), reason == 5 ? alice : address(0));
        vm.prank(alice);
        claims.claim(ids);
        assertEq(token.balanceOf(alice), userBefore + count * INSTANT);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_badRestMemberIsAtomic(uint256 rawCount, uint256 rawPosition, uint8 rawReason) public {
        uint256 count = bound(rawCount, 1, 32);
        uint256[] memory ids = _mintIds(alice, count, 1);
        vm.prank(alice);
        claims.claim(ids);
        _burnIds(ids);
        uint256[] memory poisoned = _slice(ids, 0, count);
        uint256 reason = rawReason % 6;
        uint256 badId = MAX_ID;
        bytes4 selector;
        if (reason <= 2) {
            badId = reason == 0 ? 0 : (reason == 1 ? MAX_ID + 1 : type(uint256).max);
            selector = CharterClaim.InvalidId.selector;
        } else if (reason == 3) {
            selector = CharterClaim.NotClaimant.selector;
        } else if (reason == 4) {
            _initial(alice, badId);
            charter.burn(badId);
            vm.prank(alice);
            claims.claimRest(_one(badId));
            selector = CharterClaim.RestAlreadyClaimed.selector;
        } else {
            _initial(bob, badId);
            charter.burn(badId);
            selector = CharterClaim.NotClaimant.selector;
        }
        poisoned[bound(rawPosition, 0, count - 1)] = badId;
        uint256 balanceBefore = token.balanceOf(address(claims));
        uint256 userBefore = token.balanceOf(alice);
        uint256 otherBefore = token.balanceOf(bob);

        vm.expectRevert(abi.encodeWithSelector(selector, badId));
        vm.prank(alice);
        claims.claimRest(poisoned);

        _assertUnchanged(ids, true, balanceBefore, userBefore);
        assertEq(token.balanceOf(bob), otherBefore);
        assertEq(claims.restClaimed(badId), reason == 4);
        if (reason == 5) assertEq(claims.claimant(badId), bob);
        vm.prank(alice);
        claims.claimRest(ids);
        assertEq(token.balanceOf(alice), userBefore + count * REST);
        _assertTerminal(ids, alice);
    }

    /// @dev BIC ownership is independent of NFT eligibility. Giving BIC back is a donation,
    /// never a reset of either phase and never an increase in anyone's fixed entitlement.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_sendingPayoutAwayDoesNotTransferOrResetEntitlement(uint256 rawAmount, bool donate) public {
        _initial(alice, MAX_ID);
        uint256 amount = bound(rawAmount, 0, INSTANT);
        vm.prank(alice);
        token.transfer(donate ? address(claims) : bob, amount);
        charter.burn(MAX_ID);
        _assertClaimable(alice, 0, REST);
        _assertClaimable(bob, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotClaimant.selector, MAX_ID));
        vm.prank(bob);
        claims.claimRest(_one(MAX_ID));
        vm.prank(alice);
        claims.claimRest(_one(MAX_ID));
        assertEq(token.balanceOf(alice), SHARE - amount);
        assertEq(token.balanceOf(bob), donate ? 0 : amount);
        assertEq(token.balanceOf(address(claims)), ALLOCATION - SHARE + (donate ? amount : 0));
        assertEq(claims.claimant(MAX_ID), alice);
        assertTrue(claims.restClaimed(MAX_ID));
        _assertClaimable(alice, 0, 0);
    }

    function test_instantNeedsOnlyOwnerOfAndDoesNotDependOnBalanceRead() public {
        charter.mint(alice, MAX_ID);
        charter.failBalanceReads(true);
        vm.prank(alice);
        claims.claim(_one(MAX_ID));
        assertEq(token.balanceOf(alice), INSTANT);
        assertEq(claims.claimant(MAX_ID), alice);
    }

    function test_remintBeforeRestCannotReplaceTheOriginalClaimant() public {
        _initial(alice, MAX_ID);
        charter.burn(MAX_ID);
        charter.mint(bob, MAX_ID);
        _assertClaimable(bob, 0, 0);
        _assertClaimable(alice, 0, REST);
        charter.failOwnerReads(true);
        vm.prank(alice);
        claims.claimRest(_one(MAX_ID));
        assertEq(token.balanceOf(alice), SHARE);
        assertEq(token.balanceOf(bob), 0);
        assertEq(claims.claimant(MAX_ID), alice);
    }

    function test_contractWalletReceivesBothPhasesInsteadOfTxOrigin() public {
        CharterClaimCaller wallet = new CharterClaimCaller();
        charter.mint(address(wallet), 1);
        vm.prank(alice, alice);
        wallet.forward(claims, _one(1), false);
        assertEq(claims.claimant(1), address(wallet));
        assertEq(token.balanceOf(address(wallet)), INSTANT);
        assertEq(token.balanceOf(alice), 0);
        charter.burn(1);
        _assertClaimable(address(wallet), 0, REST);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotClaimant.selector, 1));
        vm.prank(alice, alice);
        claims.claimRest(_one(1));
        vm.prank(alice, alice);
        wallet.forward(claims, _one(1), true);
        assertEq(token.balanceOf(address(wallet)), SHARE);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_forwarderCannotClaimAnNftOwnedByTxOrigin() public {
        CharterClaimCaller forwarder = new CharterClaimCaller();
        charter.mint(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(CharterClaim.NotCharterOwner.selector, 1));
        vm.prank(alice, alice);
        forwarder.forward(claims, _one(1), false);
        assertFalse(claims.instantClaimed(1));
        assertEq(token.balanceOf(address(claims)), ALLOCATION);
    }

    function _mintIds(address account, uint256 count, uint256 start) private returns (uint256[] memory ids) {
        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = (start - 1 + i) % MAX_ID + 1;
            charter.mint(account, ids[i]);
        }
    }

    function _burnIds(uint256[] memory ids) private {
        for (uint256 i; i < ids.length; ++i) {
            charter.burn(ids[i]);
        }
    }

    function _slice(uint256[] memory ids, uint256 start, uint256 end) private pure returns (uint256[] memory result) {
        result = new uint256[](end - start);
        for (uint256 i = start; i < end; ++i) {
            result[i - start] = ids[i];
        }
    }

    function _shuffle(uint256[] memory ids, uint256 seed) private pure {
        for (uint256 i = ids.length - 1; i > 0; --i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 j = seed % (i + 1);
            (ids[i], ids[j]) = (ids[j], ids[i]);
        }
    }

    function _assertUnchanged(uint256[] memory ids, bool rest, uint256 contractBefore, uint256 userBefore)
        private
        view
    {
        for (uint256 i; i < ids.length; ++i) {
            assertEq(claims.claimant(ids[i]), rest ? alice : address(0), "failed batch changed claimant");
            assertEq(claims.instantClaimed(ids[i]), rest, "failed batch changed instant flag");
            assertFalse(claims.restClaimed(ids[i]), "failed batch consumed rest");
        }
        assertEq(token.balanceOf(address(claims)), contractBefore, "failed batch leaked funds");
        assertEq(token.balanceOf(alice), userBefore, "failed batch paid caller");
    }

    function _assertTerminal(uint256[] memory ids, address account) private view {
        for (uint256 i; i < ids.length; ++i) {
            assertEq(claims.claimant(ids[i]), account);
            assertTrue(claims.instantClaimed(ids[i]));
            assertTrue(claims.restClaimed(ids[i]));
        }
    }
}
