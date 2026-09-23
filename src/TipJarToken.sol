// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply TIPS. Deployment through ProjectFactory mints the entire supply to that factory.
contract TipJarToken is ERC20 {
    constructor() ERC20("Tip Jar", "TIPS") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
