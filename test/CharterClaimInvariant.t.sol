// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CharterClaim} from "../src/CharterClaim.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {MockCharter} from "./helpers/MockCharter.sol";
import {CharterFixture} from "./helpers/CharterFixture.sol";

/// @dev Independent model of ownership, permanent beneficiaries, and payouts across random actions.
contract CharterInvariantHandler is Test {
    uint256 private constant INSTANT = uint256(800_000_000 ether) / 1032 / 10;
    uint256 private constant REST = uint256(800_000_000 ether) / 1032 - INSTANT;
    uint256 public constant ID_COUNT = 12;
    uint256 public constant ELIGIBLE_COUNT = 9;
    CharterClaim private immutable claims;
    LaunchToken private immutable token;
    MockCharter private immutable charter;
    address[3] private actors;

    mapping(uint256 => address) public modelOwner;
    mapping(address => uint256) public modelNftBalance;
    mapping(uint256 => address) public modelClaimant;
    mapping(uint256 => bool) public modelRestPaid;
    mapping(address => uint256) public modelPayout;
    // These counters are updated by actions, independently of CharterClaim's view scan.
    mapping(address => uint256) public ownedUnclaimedCount;
    mapping(address => uint256) public pendingRestCount;
    uint256 public totalPaid;
    uint256 public donations;
    uint256 public instantSuccesses;
    uint256 public restSuccesses;

    constructor(CharterClaim claims_, LaunchToken token_, MockCharter charter_, address[3] memory actors_) {
        claims = claims_;
        token = token_;
        charter = charter_;
        actors = actors_;
    }

    function idAt(uint256 index) public pure returns (uint256) {
        // Include valid IDs across the range and ineligible NFTs that still block rest.
        if (index < 7) return index + 1;
        if (index == 7) return 1032;
        if (index == 8) return 1033;
        if (index == 9) return 0;
        if (index == 10) return 517;
        return type(uint256).max;
    }

    function moveOrMint(uint256 rawId, uint256 rawActor) external {
        uint256 id = idAt(rawId % ID_COUNT);
        address to = actors[rawActor % 3];
        _moveOrMint(id, to);
    }

    function _moveOrMint(uint256 id, address to) private {
        address from = modelOwner[id];
        if (from == address(0)) {
            charter.mint(to, id);
        } else {
            vm.prank(from);
            charter.transferFrom(from, to, id);
            modelNftBalance[from]--;
        }
        if (_eligible(id) && modelClaimant[id] == address(0)) {
            if (from != address(0)) ownedUnclaimedCount[from]--;
            ownedUnclaimedCount[to]++;
        }
        modelOwner[id] = to;
        modelNftBalance[to]++;
    }

    function burn(uint256 rawId) external {
        uint256 id = idAt(rawId % ID_COUNT);
        _burn(id);
    }

    function _burn(uint256 id) private {
        address holder = modelOwner[id];
        if (holder == address(0)) return;
        charter.burn(id);
        if (_eligible(id) && modelClaimant[id] == address(0)) ownedUnclaimedCount[holder]--;
        modelNftBalance[holder]--;
        delete modelOwner[id];
    }

    function claimInstant(uint256 rawActor, uint256 rawFirst, uint256 rawSecond, bool batch) external {
        address account = actors[rawActor % 3];
        uint256[] memory ids = _ids(rawFirst, rawSecond, batch);
        bool expected = _canClaimInstant(account, ids[0]);
        if (batch) expected = expected && ids[0] != ids[1] && _canClaimInstant(account, ids[1]);

        vm.prank(account);
        (bool ok,) = address(claims).call(abi.encodeCall(claims.claim, (ids)));
        assertEq(ok, expected, "instant success differs from independent model");
        if (ok) _recordInstant(account, ids);
    }

    /// @dev Bias some calls toward successful, variable-size batches so failures cannot dominate
    /// exploration. Selection uses the model, never the implementation's claimant or preview.
    function claimAvailable(uint256 rawActor, uint256 rawLimit, bool reverse) external {
        address account = actors[rawActor % 3];
        uint256 count = ownedUnclaimedCount[account];
        if (count == 0) return;
        uint256 limit = bound(rawLimit, 1, count);
        uint256[] memory ids = new uint256[](limit);
        uint256 cursor;
        for (uint256 i; i < ID_COUNT && cursor < limit; ++i) {
            uint256 id = idAt(reverse ? ID_COUNT - 1 - i : i);
            if (_canClaimInstant(account, id)) ids[cursor++] = id;
        }
        assertEq(cursor, limit, "ownership counter drift");
        vm.prank(account);
        claims.claim(ids);
        _recordInstant(account, ids);
    }

    /// @dev Creates a zero-NFT wallet without burning the NFTs. This exercises new owners,
    /// delayed rest, and reacquisition as separate random steps.
    function transferAll(uint256 rawActor, uint256 rawRecipient) external {
        uint256 actorIndex = rawActor % 3;
        address from = actors[actorIndex];
        address to = actors[(actorIndex + 1 + rawRecipient % 2) % 3];
        for (uint256 i; i < ID_COUNT; ++i) {
            uint256 id = idAt(i);
            if (modelOwner[id] == from) _moveOrMint(id, to);
        }
    }

    function claimRest(uint256 rawActor, uint256 rawFirst, uint256 rawSecond, bool batch) external {
        address account = actors[rawActor % 3];
        uint256[] memory ids = _ids(rawFirst, rawSecond, batch);
        bool expected = modelNftBalance[account] == 0 && _canClaimRest(account, ids[0]);
        if (batch) expected = expected && ids[0] != ids[1] && _canClaimRest(account, ids[1]);

        vm.prank(account);
        (bool ok,) = address(claims).call(abi.encodeCall(claims.claimRest, (ids)));
        assertEq(ok, expected, "rest success differs from independent model");
        if (ok) _recordRest(account, ids);
    }

    function exitAndClaimRest(uint256 rawActor) external {
        address account = actors[rawActor % 3];
        uint256 count;
        for (uint256 i; i < ID_COUNT; ++i) {
            uint256 id = idAt(i);
            if (modelOwner[id] == account) _burn(id);
            if (_canClaimRest(account, id)) count++;
        }
        if (count == 0) return;
        uint256[] memory ids = new uint256[](count);
        uint256 cursor;
        for (uint256 i; i < ID_COUNT; ++i) {
            uint256 id = idAt(i);
            if (_canClaimRest(account, id)) ids[cursor++] = id;
        }
        vm.prank(account);
        claims.claimRest(ids);
        _recordRest(account, ids);
    }

    function donate(uint256 rawAmount) external {
        uint256 amount = rawAmount % (token.balanceOf(address(this)) + 1);
        token.transfer(address(claims), amount);
        donations += amount;
    }

    function _canClaimInstant(address account, uint256 id) private view returns (bool) {
        return _eligible(id) && modelOwner[id] == account && modelClaimant[id] == address(0);
    }

    function _canClaimRest(address account, uint256 id) private view returns (bool) {
        return _eligible(id) && modelClaimant[id] == account && !modelRestPaid[id];
    }

    function _eligible(uint256 id) private pure returns (bool) {
        return id >= 1 && id <= 1032;
    }

    function _recordInstant(address account, uint256[] memory ids) private {
        for (uint256 i; i < ids.length; ++i) {
            modelClaimant[ids[i]] = account;
        }
        ownedUnclaimedCount[account] -= ids.length;
        pendingRestCount[account] += ids.length;
        instantSuccesses++;
        _paid(account, ids.length * INSTANT);
    }

    function _recordRest(address account, uint256[] memory ids) private {
        for (uint256 i; i < ids.length; ++i) {
            modelRestPaid[ids[i]] = true;
        }
        pendingRestCount[account] -= ids.length;
        restSuccesses++;
        _paid(account, ids.length * REST);
    }

    function _paid(address account, uint256 amount) private {
        modelPayout[account] += amount;
        totalPaid += amount;
    }

    function _ids(uint256 rawFirst, uint256 rawSecond, bool batch) private pure returns (uint256[] memory ids) {
        ids = new uint256[](batch ? 2 : 1);
        ids[0] = idAt(rawFirst % ID_COUNT);
        if (batch) ids[1] = idAt(rawSecond % ID_COUNT);
    }
}

contract CharterClaimInvariantTest is CharterFixture {
    CharterInvariantHandler private handler;

    function setUp() public override {
        super.setUp();
        address[3] memory actors = [alice, bob, carol];
        handler = new CharterInvariantHandler(claims, token, charter, actors);
        token.transfer(address(handler), 1_000 ether);

        // Each actor starts with a real pending entitlement. Random sequences can never pass
        // merely because no one managed to claim; more unclaimed IDs remain for exploration.
        for (uint256 i; i < handler.ID_COUNT(); ++i) {
            handler.moveOrMint(i, i % 3);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.claimAvailable(i, 1, false);
        }

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.moveOrMint.selector;
        selectors[1] = handler.burn.selector;
        selectors[2] = handler.claimInstant.selector;
        selectors[3] = handler.claimRest.selector;
        selectors[4] = handler.exitAndClaimRest.selector;
        selectors[5] = handler.donate.selector;
        selectors[6] = handler.claimAvailable.selector;
        selectors[7] = handler.transferAll.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_claimantsAndPaymentsMatchModelAndFundsAreConserved() public view {
        uint256 paidFromFlags;
        for (uint256 i; i < handler.ID_COUNT(); ++i) {
            uint256 id = handler.idAt(i);
            address recorded = handler.modelClaimant(id);
            bool restPaid = handler.modelRestPaid(id);
            assertEq(claims.claimant(id), recorded, "permanent claimant mismatch");
            assertEq(claims.instantClaimed(id), recorded != address(0), "instant mismatch");
            assertEq(claims.restClaimed(id), restPaid, "rest mismatch");
            if (recorded != address(0)) paidFromFlags += INSTANT;
            if (restPaid) {
                assertTrue(recorded != address(0), "rest without instant");
                paidFromFlags += REST;
            }
        }

        address[3] memory actors = [alice, bob, carol];
        uint256 paidToAccounts;
        for (uint256 i; i < actors.length; ++i) {
            address account = actors[i];
            assertEq(charter.balanceOf(account), handler.modelNftBalance(account), "NFT model drift");
            assertEq(token.balanceOf(account), handler.modelPayout(account), "wrong beneficiary or amount");
            (uint256 instant, uint256 rest) = claims.claimable(account);
            assertEq(instant, handler.ownedUnclaimedCount(account) * INSTANT, "instant preview disagrees with actions");
            uint256 expectedRest = handler.modelNftBalance(account) == 0 ? handler.pendingRestCount(account) * REST : 0;
            assertEq(rest, expectedRest, "rest preview disagrees with actions");
            paidToAccounts += token.balanceOf(account);
        }
        assertEq(paidFromFlags, handler.totalPaid());
        assertEq(paidToAccounts, handler.totalPaid());
        assertLe(paidFromFlags, handler.ELIGIBLE_COUNT() * SHARE);
        assertEq(token.balanceOf(address(claims)) + handler.totalPaid(), ALLOCATION + handler.donations());
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertGe(handler.instantSuccesses(), 3, "campaign never entered the funded claim state");
    }

    /// @dev Liveness: after EVERY random sequence, burn/revoke all tracked NFTs and settle every
    /// original claimant's remaining rest. No token minting, balance edits, or state resets.
    function afterInvariant() public {
        for (uint256 i; i < 3; ++i) {
            handler.exitAndClaimRest(i);
        }
        uint256 claimedCount;
        for (uint256 i; i < handler.ID_COUNT(); ++i) {
            uint256 id = handler.idAt(i);
            if (handler.modelClaimant(id) != address(0)) {
                claimedCount++;
                assertTrue(claims.restClaimed(id), "valid rest entitlement could not be settled");
            }
        }
        assertEq(handler.totalPaid(), claimedCount * SHARE, "each claimant must finish with one share per ID");
        assertEq(token.balanceOf(address(claims)), ALLOCATION + handler.donations() - claimedCount * SHARE);
        assertGt(handler.restSuccesses(), 0, "rest liveness was not exercised");
        invariant_claimantsAndPaymentsMatchModelAndFundsAreConserved();
    }

    function test_handlerSequenceIncludesPartialClaimsTransfersRejectionsAndSettlement() public {
        handler.claimAvailable(0, 1, true);
        handler.claimRest(0, 0, 0, false); // Blocked while owning a Charter.
        handler.transferAll(0, 0);
        handler.claimRest(0, 0, 0, false); // Original claimant can now take rest for ID 1.
        handler.claimRest(0, 0, 0, false); // Replaying that payment must fail.
        handler.moveOrMint(9, 0); // Even ID zero counts as a Charter for the balance gate.
        handler.claimInstant(0, 9, 9, false); // It never receives an allocation.
        handler.burn(9);
        handler.donate(1);
        invariant_claimantsAndPaymentsMatchModelAndFundsAreConserved();
        afterInvariant();
    }
}
