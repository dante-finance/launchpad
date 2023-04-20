// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStakingPool 
{
    function getTierCount() external view returns(uint);
    function checkTier(address user) external view returns(uint);
}