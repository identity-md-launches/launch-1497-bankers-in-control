// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply BIC. The launch factory receives the entire supply and distributes it.
contract LaunchToken is ERC20 {
    constructor() ERC20("Bankers In Control", "BIC") {
        _mint(msg.sender, 1_000_000_000 ether);
    }
}
