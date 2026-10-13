// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CharterClaim} from "../../src/CharterClaim.sol";
import {LaunchToken} from "../../src/LaunchToken.sol";
import {MockCharter} from "./MockCharter.sol";

abstract contract CharterFixture is Test {
    address internal constant CHARTER_ADDRESS = 0x69101f92427376FA80476A997d024cf9dC3EaE39;
    uint256 internal constant MAX_ID = 1032;
    uint256 internal constant ALLOCATION = 800_000_000 ether;
    uint256 internal constant SHARE = ALLOCATION / MAX_ID;
    uint256 internal constant INSTANT = SHARE / 10;
    uint256 internal constant REST = SHARE - INSTANT;

    LaunchToken internal token;
    CharterClaim internal claims;
    MockCharter internal charter;
    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        MockCharter implementation = new MockCharter();
        vm.etch(CHARTER_ADDRESS, address(implementation).code);
        charter = MockCharter(CHARTER_ADDRESS);
        token = new LaunchToken();
        claims = new CharterClaim(address(token));
        token.transfer(address(claims), ALLOCATION);
    }

    function _one(uint256 id) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = id;
    }

    function _two(uint256 first, uint256 second) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](2);
        ids[0] = first;
        ids[1] = second;
    }

    function _initial(address account, uint256 id) internal {
        charter.mint(account, id);
        vm.prank(account);
        claims.claim(_one(id));
    }

    function _transfer(address from, address to, uint256 id) internal {
        vm.prank(from);
        charter.transferFrom(from, to, id);
    }

    function _assertClaimable(address account, uint256 instant, uint256 rest) internal view {
        (uint256 actualInstant, uint256 actualRest) = claims.claimable(account);
        assertEq(actualInstant, instant, "instant eligibility");
        assertEq(actualRest, rest, "rest eligibility");
    }
}
