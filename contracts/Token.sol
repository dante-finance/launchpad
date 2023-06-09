// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";

contract Token is ERC20Burnable, Operator 
{
    using SafeMath for uint256;

    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 59500 ether;
    uint256 public constant COMMUNITY_FUND_POOL_ALLOCATION = 5500 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 5000 ether;

    uint256 public constant VESTING_DURATION = 180 days;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public communityFundRewardRate;
    uint256 public devFundRewardRate;

    address public communityFund;
    address public devFund;

    uint256 public communityFundLastClaimed;
    uint256 public devFundLastClaimed;

    uint256 public rewardPoolDistributed = 0;

    constructor(
        uint256 _startTime, 
        address _communityFund, 
        address _devFund) 
        ERC20("TOKEN", "TOKEN") 
    {
        /// testing
        _mint(msg.sender, 10000 ether);

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        communityFundLastClaimed = startTime;
        devFundLastClaimed = startTime;

        communityFundRewardRate = COMMUNITY_FUND_POOL_ALLOCATION.div(VESTING_DURATION);
        devFundRewardRate = DEV_FUND_POOL_ALLOCATION.div(VESTING_DURATION);

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;

        require(_communityFund != address(0), "Address cannot be 0");
        communityFund = _communityFund;
    }

    function setTreasuryFund(address _communityFund) external 
    {
        require(msg.sender == devFund, "!dev");
        communityFund = _communityFund;
    }

    function setDevFund(address _devFund) external 
    {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedTreasuryFund() public view returns (uint256 _pending) 
    {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (communityFundLastClaimed >= _now) return 0;
        _pending = _now.sub(communityFundLastClaimed).mul(communityFundRewardRate);
    }

    function unclaimedDevFund() public view returns (uint256 _pending) 
    {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() 
        external 
        onlyOperator
    {
        uint256 _pending = unclaimedTreasuryFund();
        
        if (_pending > 0 && communityFund != address(0)) 
        {
            _mint(communityFund, _pending);
            communityFundLastClaimed = block.timestamp;
        }

        _pending = unclaimedDevFund();
        
        if (_pending > 0 && devFund != address(0)) 
        {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool 
     */
    function distributeRewards(
        address _farmingIncentiveFund,
        uint _amount) 
        external 
        onlyOperator 
    {
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        _mint(_farmingIncentiveFund, _amount);
        rewardPoolDistributed += _amount;
        require(rewardPoolDistributed <= FARMING_POOL_REWARD_ALLOCATION);
    }

    function burn(uint256 amount) public override 
    {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to) 
        external 
        onlyOperator 
    {
        _token.transfer(_to, _amount);
    }
}
