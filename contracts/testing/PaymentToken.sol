//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PaymentToken is ERC20
{
    constructor() ERC20("PAYMENTTOKEN", "PAY") 
    {
        _mint(msg.sender, 10000 ether);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}