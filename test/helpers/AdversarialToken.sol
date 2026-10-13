// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CharterClaim} from "../../src/CharterClaim.sol";
import {MockCharter} from "./MockCharter.sol";

/// @dev Test-only transfer failures and callbacks; never a launch token.
contract AdversarialToken is ERC20 {
    enum Mode {
        Normal,
        FalseReturn,
        RevertTransfer,
        NoReturn,
        MalformedReturn,
        Callback
    }

    Mode public mode;
    bool public observingRest;
    bool public sawEffects;
    bool public nestedInstantSucceeded;
    bool public nestedRestSucceeded;
    bytes public nestedInstantResult;
    bytes public nestedRestResult;
    uint256[] private observedIds;
    CharterClaim public claims;

    error TransferRejected();

    constructor() ERC20("Test token", "TEST") {
        _mint(msg.sender, 1_000_000_000 ether);
    }

    function setMode(Mode nextMode) external {
        mode = nextMode;
    }

    function configureCallback(CharterClaim target, uint256[] calldata ids, bool rest) external {
        claims = target;
        observedIds = ids;
        observingRest = rest;
        mode = Mode.Callback;
    }

    function start(CharterClaim target, uint256[] calldata ids, bool rest) external {
        if (rest) target.claimRest(ids);
        else target.claim(ids);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (mode == Mode.FalseReturn) return false;
        if (mode == Mode.RevertTransfer) revert TransferRejected();
        if (mode == Mode.Callback && msg.sender == address(claims)) {
            for (uint256 i; i < observedIds.length; ++i) {
                uint256 id = observedIds[i];
                require(claims.claimant(id) == to, "claimant not recorded before transfer");
                require(claims.instantClaimed(id), "instant not recorded before transfer");
                require(claims.restClaimed(id) == observingRest, "rest effect not recorded before transfer");
                if (!observingRest) MockCharter(claims.CHARTER()).burn(id);
            }
            sawEffects = true;
            (nestedInstantSucceeded, nestedInstantResult) =
                address(claims).call(abi.encodeCall(claims.claim, (observedIds)));
            (nestedRestSucceeded, nestedRestResult) =
                address(claims).call(abi.encodeCall(claims.claimRest, (observedIds)));
        }
        bool result = super.transfer(to, amount);
        if (mode == Mode.NoReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        if (mode == Mode.MalformedReturn) {
            assembly ("memory-safe") {
                mstore(0, 1)
                return(31, 1)
            }
        }
        return result;
    }
}
