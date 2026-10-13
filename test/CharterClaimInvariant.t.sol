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
    uint256 public constant ID_COUNT = 9;
    CharterClaim private immutable claims;
    LaunchToken private immutable token;
    MockCharter private immutable charter;
    address[3] private actors;

    mapping(uint256 => address) public modelOwner;
    mapping(address => uint256) public modelNftBalance;
    mapping(uint256 => address) public modelClaimant;
    mapping(uint256 => bool) public modelRestPaid;
    mapping(address => uint256) public modelPayout;
    uint256 public totalPaid;
    uint256 public donations;

    constructor(CharterClaim claims_, LaunchToken token_, MockCharter charter_, address[3] memory actors_) {
        claims = claims_;
        token = token_;
        charter = charter_;
        actors = actors_;
    }

    function idAt(uint256 index) public pure returns (uint256) {
        // Exercise small IDs, the inclusive cutoff, and a later NFT that can block rest.
        if (index < 7) return index + 1;
        if (index == 7) return 1032;
        return 1033;
    }

    function moveOrMint(uint256 rawId, uint256 rawActor) external {
        uint256 id = idAt(rawId % ID_COUNT);
        address to = actors[rawActor % 3];
        address from = modelOwner[id];
        if (from == address(0)) {
            charter.mint(to, id);
        } else {
            vm.prank(from);
            charter.transferFrom(from, to, id);
            modelNftBalance[from]--;
        }
        modelOwner[id] = to;
        modelNftBalance[to]++;
    }

    function burn(uint256 rawId) external {
        uint256 id = idAt(rawId % ID_COUNT);
        address holder = modelOwner[id];
        if (holder == address(0)) return;
        charter.burn(id);
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
        if (ok) {
            for (uint256 i; i < ids.length; ++i) {
                modelClaimant[ids[i]] = account;
            }
            _paid(account, ids.length * INSTANT);
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
            if (modelOwner[id] == account) {
                charter.burn(id);
                modelNftBalance[account]--;
                delete modelOwner[id];
            }
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
        return id <= 1032 && modelOwner[id] == account && modelClaimant[id] == address(0);
    }

    function _canClaimRest(address account, uint256 id) private view returns (bool) {
        return id <= 1032 && modelClaimant[id] == account && !modelRestPaid[id];
    }

    function _recordRest(address account, uint256[] memory ids) private {
        for (uint256 i; i < ids.length; ++i) {
            modelRestPaid[ids[i]] = true;
        }
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

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.moveOrMint.selector;
        selectors[1] = handler.burn.selector;
        selectors[2] = handler.claimInstant.selector;
        selectors[3] = handler.claimRest.selector;
        selectors[4] = handler.exitAndClaimRest.selector;
        selectors[5] = handler.donate.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

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
            paidToAccounts += token.balanceOf(account);
        }
        assertEq(paidFromFlags, handler.totalPaid());
        assertEq(paidToAccounts, handler.totalPaid());
        assertLe(paidFromFlags, 8 * SHARE);
        assertEq(token.balanceOf(address(claims)) + handler.totalPaid(), ALLOCATION + handler.donations());
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }
}
