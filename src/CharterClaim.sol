// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IFoundingCharter} from "./interfaces/IFoundingCharter.sol";

/// @notice Immutable two-stage BIC claims for Founding Charter IDs 1 through 1032.
/// @dev No owner, recovery, approvals, or funding callback. The launch transfers the allocation here.
contract CharterClaim is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant CHARTER = 0x69101f92427376FA80476A997d024cf9dC3EaE39;
    uint256 public constant MAX_ID = 1032;
    uint256 public constant ALLOCATION = 800_000_000 ether;
    uint256 public constant SHARE = ALLOCATION / MAX_ID;
    uint256 public constant INSTANT = SHARE / 10;
    uint256 public constant REST = SHARE - INSTANT;

    IERC20 public immutable token;

    mapping(uint256 id => address account) public claimant;
    mapping(uint256 id => bool paid) public restClaimed;

    error InvalidToken();
    error EmptyBatch();
    error InvalidId(uint256 id);
    error NotCharterOwner(uint256 id);
    error AlreadyClaimed(uint256 id);
    error StillHoldsCharter();
    error NotClaimant(uint256 id);
    error RestAlreadyClaimed(uint256 id);

    event Claimed(uint256 indexed id, address indexed account, uint256 amount, bool rest);

    /// @param token_ The launch's BIC token, supplied as $token by the launch system.
    /// @dev No external calls or code checks: deployment also works before external code is present.
    constructor(address token_) {
        if (token_ == address(0)) revert InvalidToken();
        token = IERC20(token_);
    }

    /// @notice Claim the initial 10% for eligible IDs currently owned by the caller.
    /// @dev All IDs are recorded before the single aggregate transfer. Duplicates revert the batch.
    function claim(uint256[] calldata ids) external nonReentrant {
        uint256 length = ids.length;
        if (length == 0) revert EmptyBatch();

        for (uint256 i; i < length; ++i) {
            uint256 id = ids[i];
            _validateId(id);
            if (claimant[id] != address(0)) revert AlreadyClaimed(id);
            if (IFoundingCharter(CHARTER).ownerOf(id) != msg.sender) revert NotCharterOwner(id);

            claimant[id] = msg.sender;
            emit Claimed(id, msg.sender, INSTANT, false);
        }

        token.safeTransfer(msg.sender, INSTANT * length);
    }

    /// @notice Claim the remaining 90% once the caller holds no Founding Charter of any ID.
    /// @dev Uses the original claimant, never ownerOf; burned or revoked IDs still qualify.
    function claimRest(uint256[] calldata ids) external nonReentrant {
        uint256 length = ids.length;
        if (length == 0) revert EmptyBatch();
        if (IFoundingCharter(CHARTER).balanceOf(msg.sender) != 0) revert StillHoldsCharter();

        for (uint256 i; i < length; ++i) {
            uint256 id = ids[i];
            _validateId(id);
            if (claimant[id] != msg.sender) revert NotClaimant(id);
            if (restClaimed[id]) revert RestAlreadyClaimed(id);

            restClaimed[id] = true;
            emit Claimed(id, msg.sender, REST, true);
        }

        token.safeTransfer(msg.sender, REST * length);
    }

    /// @notice Whether an ID's initial payment has succeeded, including after its rest payment.
    function instantClaimed(uint256 id) external view returns (bool) {
        return claimant[id] != address(0);
    }

    /// @notice Amounts account is currently eligible to claim, in BIC minor units (18 decimals).
    /// @dev A bounded scan; missing/burned IDs are skipped for the initial payment. Rest eligibility
    /// does not query ownership or existence of individual IDs. Assumes the launch funded ALLOCATION.
    function claimable(address account) external view returns (uint256 instant, uint256 rest) {
        if (account == address(0)) return (0, 0);
        bool holdsCharter = IFoundingCharter(CHARTER).balanceOf(account) != 0;

        for (uint256 id = 1; id <= MAX_ID; ++id) {
            address recorded = claimant[id];
            if (holdsCharter) {
                if (recorded == address(0)) {
                    try IFoundingCharter(CHARTER).ownerOf(id) returns (address holder) {
                        if (holder == account) instant += INSTANT;
                    } catch {
                        // ownerOf reverts for IDs that do not exist or have been burned/revoked.
                    }
                }
            } else if (recorded == account && !restClaimed[id]) {
                rest += REST;
            }
        }
    }

    function _validateId(uint256 id) private pure {
        if (id == 0 || id > MAX_ID) revert InvalidId(id);
    }
}
