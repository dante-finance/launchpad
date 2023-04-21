// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ISnapshotStaking.sol";
import "hardhat/console.sol";

contract SnapshotStaking is ISnapshotStaking, Ownable, ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 public constant DAY_IN_SECONDS = 86400;

    mapping(address => uint256) stakedAmount;

    struct UserInfo 
    {
        uint256 amount; // How many token the user has provided
        uint256 rewardPending;
        uint256 lastRewardTime; // Last timestamp that rewards distribution occurs.
        
        // available to withdraw
        uint256 available;
        mapping(uint256 => uint256) unlocks;
        uint256[] timestamps;
    }

    struct PoolInfo 
    {
        IERC20 stakeToken; // Address of LP token contract.
        IERC20 rewardToken; // Address of reward token.
        uint256 poolSize; // The capital of LP token in this pool.
        uint256 poolBalance; // The balance of LP token in this pool.
        uint256 startTime; // The timestamp when staking has started.
        uint256 endTime; // The timestamp when staking has ended.
        uint256 apr; // Anual percentage rate of this pool.
    }

    uint256 public constant APR_DENOMINATION = 1e4; //  APR = pool.apr / APR_DENOMINATION
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public cooldown = 7 days;
    
    constructor() 
    {
    }

    function getUserUnlocks(uint pid) external view returns (uint[] memory)
    {
        return userInfo[pid][msg.sender].timestamps;
    }

    function getUserUnlockAmount(uint pid, uint timestamp) external view returns (uint)
    {
        return userInfo[pid][msg.sender].unlocks[timestamp];
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see pending rewards on frontend.
    function pendingReward(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        (uint256 reward, ) = _getReward(_pid, _user);
        return reward + userInfo[_pid][_user].rewardPending;
    }

    // Get reward and time of last reward
    function _getReward(uint256 _pid, address _user)
        public
        view
        returns (uint256 _reward, uint256 _rewardTime)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 lpSupply = user.amount;
                
        if (block.timestamp <= pool.startTime) 
        {
            //console.log("exit");
            return (0, user.lastRewardTime);
        }
        
        // multiples of days
        _rewardTime = block.timestamp - ((block.timestamp - pool.startTime) % DAY_IN_SECONDS);
        
        if (lpSupply == 0) 
        {
            return (0, _rewardTime);
        }

        uint256 lastRewardTime = user.lastRewardTime > pool.startTime
            ? user.lastRewardTime
            : pool.startTime;

        uint256 day = _getDaysFromLastReward(
            lastRewardTime,
            _rewardTime,
            pool.endTime
        );

        _reward = lpSupply * day / 365 * pool.apr / APR_DENOMINATION;
    }

    // Return reward multiplier over the given _from to _to block.
    function _getDaysFromLastReward(
        uint256 _from,
        uint256 _to,
        uint256 _endTime) 
        private 
        pure 
        returns (uint256) 
    {
        // Consider when user stake and unstake at the same time
        // lastRewardBlock when stake is (t) but accounted time for unstake will (t - 1)
        // To avoid user can't unstake in this case we manualy check _from > _to
        if (_from >= _to) 
        {
            return 0;
        } 
        else if (_from >= _endTime) 
        {
            return 0;
        } 
        else if (_to >= _endTime) 
        {
            _to = _endTime;
        }

        return (_to - _from) / DAY_IN_SECONDS;
    }

    // Deposit LP tokens to snapshot staking
    function stake(
        uint256 _pid, 
        uint256 _amount)
        nonReentrant
        external
    {
        require(_amount > 0);

        address sender = _msgSender();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][sender];

        // Total staking balance do not exceed pool size
        uint256 poolBalance = pool.poolBalance;
        uint256 poolSize = pool.poolSize;
        if (poolSize > 0 && _amount > (poolSize - poolBalance)) {
            _amount = poolSize - poolBalance;
        }

        require(_amount > 0, "Staking cap is filled");

        // Update User Staking state

        (uint256 reward, uint256 lastTime) = _getReward(_pid, sender);
        user.rewardPending += reward;
        user.lastRewardTime = lastTime;
        
        user.amount += _amount;
        user.available += _amount;
        
        pool.poolBalance += _amount;

        pool.stakeToken.safeTransferFrom(sender, address(this), _amount);
        stakedAmount[address(pool.stakeToken)] += _amount;

        emit Deposit(sender, _pid, _amount);
    }

    function unstakeRequest(
        uint256 pid, 
        uint256 amount)
        nonReentrant
        external
    {
        require(amount > 0);
        require(_unstakeRequest(pid, amount));
    }

    function _unstakeRequest(
        uint256 _pid, 
        uint256 _amount)
        private
        returns (bool)
    {
        UserInfo storage user = userInfo[_pid][_msgSender()];

        require(user.available >= _amount, "not enough available");

        uint256 timestamp = block.timestamp + cooldown;

        require(user.unlocks[timestamp] == 0);

        user.timestamps.push(timestamp);
        user.unlocks[timestamp] = _amount;
        user.available -= _amount;

        return true;
    }

    function unstake(
        uint256 pid, 
        uint256 timestamp)
        external    
        nonReentrant
    {
        require(block.timestamp >= timestamp, "Not yet time to withdraw");
        require(_unstake(pid, timestamp));
    }

    // Withdraw LP tokens from snapshot contract.
    function _unstake(
        uint256 _pid, 
        uint256 _timestamp)
        private
        returns (bool)
    {
        address sender = _msgSender();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][sender];

        // amount of tokens set to unlock at this time
        uint _amount = user.unlocks[_timestamp];

        require(
            _amount > 0,
            "No amount scheduled for unlock"
        );

        require(
            user.amount >= _amount,
            "Cannot withdraw more then staked amount"
        );

        (uint256 reward, uint256 lastTime) = _getReward(_pid, sender);
        uint256 pending = user.rewardPending + reward;
        if (pending > 0) {
            pool.rewardToken.safeTransfer(sender, pending);
            user.rewardPending = 0;
        }

        user.lastRewardTime = lastTime;

        user.amount -= _amount;
        user.unlocks[_timestamp] = 0;

        pool.poolBalance -= _amount;
        pool.stakeToken.safeTransfer(sender, _amount);
        stakedAmount[address(pool.stakeToken)] -= _amount;

        emit Withdraw(sender, _pid, _amount);

        return true;
    }

    ////////////////////////////////////////////////////////////////////////
    //                        ADMIN FUNCTIONS                             //
    ////////////////////////////////////////////////////////////////////////

    function setCooldown(uint256 _cooldown)
        external
        onlyOwner
    {
        cooldown = _cooldown;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function addPool(
        address _stakeToken,
        address _rewardToken,
        uint256 _poolSize,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _apr) 
        external 
        onlyOwner 
    {
        _add(_stakeToken, _rewardToken, _poolSize, _startTime, _endTime, _apr);
    }

    function _add(
        address _lpToken,
        address _rewardToken,
        uint256 _poolSize,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _apr) 
        private
    {
        require(
            _startTime >= block.timestamp,
            "Start time must not be in the past"
        );
        require(_startTime < _endTime, "Start time must be less than End time");
        require(_lpToken.isContract(), "LP Token is invalid");
        require(_rewardToken.isContract(), "Reward Token is invalid");
        require(_apr >= 0 && _apr <= APR_DENOMINATION, "apr is out of range");

        uint256 dayRemainder = (_endTime - _startTime) % DAY_IN_SECONDS;
        if (dayRemainder > 0) {
            // different between _startTime and _endTime must be a multiple of day
            _endTime = _endTime - dayRemainder;
        }

        // staking pool
        poolInfo.push(
            PoolInfo({
                stakeToken: IERC20(_lpToken),
                rewardToken: IERC20(_rewardToken),
                poolSize: _poolSize,
                poolBalance: 0,
                startTime: _startTime,
                endTime: _endTime,
                apr: _apr
            })
        );

        emit AddPool(poolInfo.length - 1, block.timestamp);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        address sender = _msgSender();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][sender];

        uint256 lpSupply = user.amount;
        user.amount = 0;
        user.rewardPending = 0;
        pool.poolBalance -= lpSupply;
        pool.stakeToken.safeTransfer(sender, lpSupply);
        stakedAmount[address(pool.stakeToken)] -= lpSupply;

        emit EmergencyWithdraw(sender, _pid, lpSupply);
    }

    function withdrawRewards(
        address _token)
        external
        onlyOwner
    {
        uint256 totalBal = IERC20(_token).balanceOf(address(this));

        uint256 totalReward = totalBal - stakedAmount[_token];
        IERC20(_token).safeTransfer(_msgSender(), totalReward);
    }
}