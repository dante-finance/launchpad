//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is Ownable, ERC20 
{
    constructor() 
        ERC20("Token", "TOK") 
    {
        _mint(msg.sender, 10000 ether);
    }

    function burn(
        uint256 value) 
        external 
    {
        _burn(msg.sender, value);
    }
}