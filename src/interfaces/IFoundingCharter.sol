// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The only Founding Charter reads needed by CharterClaim.
interface IFoundingCharter {
    function ownerOf(uint256 id) external view returns (address);
    function balanceOf(address account) external view returns (uint256);
}
