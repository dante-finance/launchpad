//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDT is ERC20
{
    constructor() ERC20("USDT", "USDT") 
    {
        _mint(msg.sender, 10000000000);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}