// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Test-only NFT model: mint/burn simulate issuance and issuer revocation.
contract MockCharter {
    mapping(uint256 => address) private owners;
    mapping(address => uint256) private balances;
    mapping(uint256 => address) public getApproved;
    bool public ownerReadsFail;
    bool public balanceReadsFail;

    error NonexistentToken(uint256 id);
    error ReadUnavailable();

    function ownerOf(uint256 id) public view returns (address) {
        if (ownerReadsFail) revert ReadUnavailable();
        address holder = owners[id];
        if (holder == address(0)) revert NonexistentToken(id);
        return holder;
    }

    function balanceOf(address account) external view returns (uint256) {
        require(account != address(0), "zero account");
        if (balanceReadsFail) revert ReadUnavailable();
        return balances[account];
    }

    function mint(address to, uint256 id) external {
        require(to != address(0) && owners[id] == address(0), "invalid mint");
        owners[id] = to;
        balances[to]++;
    }

    function approve(address to, uint256 id) external {
        require(ownerOf(id) == msg.sender, "not owner");
        getApproved[id] = to;
    }

    function transferFrom(address from, address to, uint256 id) external {
        require(ownerOf(id) == from && to != address(0), "invalid transfer");
        require(msg.sender == from || msg.sender == getApproved[id], "unauthorized");
        owners[id] = to;
        delete getApproved[id];
        balances[from]--;
        balances[to]++;
    }

    function burn(uint256 id) external {
        address holder = ownerOf(id);
        delete owners[id];
        delete getApproved[id];
        balances[holder]--;
    }

    function failOwnerReads(bool fail) external {
        ownerReadsFail = fail;
    }

    function failBalanceReads(bool fail) external {
        balanceReadsFail = fail;
    }

    function nextId() external pure returns (uint256) {
        revert("nextId must never be used");
    }
}
