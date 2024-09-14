// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract BOT is ERC20, ERC20Permit {
    address immutable owner;
    modifier onlyOwner{
        require(msg.sender == owner);
        _;
    }
    constructor() ERC20("Bighu_Open_TOKEN", "BOT") ERC20Permit("Bighu_Open_TOKEN") {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
