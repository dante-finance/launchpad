// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakingPool 
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo 
    {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        
        // available to withdraw
        uint256 available;

        mapping(uint256 => uint256) unlocks;
        uint256[] timestamps;
    }

    // Info of each pool.
    struct PoolInfo 
    {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. tSHAREs to distribute per block.
        uint256 lastRewardTime; // Last time that tSHAREs distribution occurs.
        uint256 accRewardPerShare; // Accumulated tSHAREs per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
    }

    IERC20 public token;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when token mining starts.
    uint256 public poolStartTime;

    // The time when token mining ends.
    uint256 public poolEndTime;

    uint256 public tokenPerSecond = 0.00186122 ether; // 59500 token / (370 days * 24h * 60min * 60s)
    uint256 public runningTime = 370 days; // 370 days
    uint256 public constant TOTAL_REWARDS = 59500 ether;

    mapping(uint256 => uint256) public tiers;
    uint256 public numTiers;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _token,
        uint256 _poolStartTime) 
    {
        require(block.timestamp < _poolStartTime, "late");

        if (_token != address(0))
        {
            token = IERC20(_token);
        }

        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
    }

    modifier onlyOperator() 
    {
        require(operator == msg.sender, "caller is not the operator");
        _;
    }

    function setTiers(uint[] calldata _tiers) external onlyOperator 
    {
        numTiers = _tiers.length;

        for(uint i = 0; i < _tiers.length; i++) 
        {
            tiers[i] = _tiers[i];
        }
    }

    function checkTier(address user) external view returns(uint256) 
    {
        uint256 totalStaked = 0;

        // check all pools and find how many tokens have been deposited
        for (uint256 pid = 0; pid < poolInfo.length; ++pid)
        {
            if(poolInfo[pid].token == token)
            {
                uint256 staked = userInfo[pid][user].amount;
                totalStaked = totalStaked + staked;
            }
        }

        for (uint256 i = 0; i < numTiers; ++i)
        {
            uint256 limit = tiers[i];

            if(totalStaked <= limit)
            {
                return i;
            }
        }

        return numTiers - 1;
    }

    function checkPoolDuplicate(IERC20 _token) internal view 
    {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) 
        {
            require(poolInfo[pid].token != _token, "existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) public onlyOperator {
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted =
        (_lastRewardTime <= poolStartTime) ||
        (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
            token : _token,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accRewardPerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's tSHARE allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(tokenPerSecond);
            return poolEndTime.sub(_fromTime).mul(tokenPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(tokenPerSecond);
            return _toTime.sub(_fromTime).mul(tokenPerSecond);
        }
    }

    // View function to see pending tSHAREs on frontend.
    function pendingShare(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _tshareReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(_tshareReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public 
    {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) 
        {
            return;
        }
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) 
        {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) 
        {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) 
        {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _tshareReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accRewardPerShare = pool.accRewardPerShare.add(_tshareReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public 
    {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);

        if (user.amount > 0) 
        {
            uint256 _pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) 
            {
                safeRewardTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }

        if (_amount > 0) 
        {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            user.available = user.available.add(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    function withdrawRequest(
        uint256 pid, 
        uint256 amount) 
        external
    {
        require(_withdrawRequest(msg.sender, pid, amount));
    }

    function _withdrawRequest(
        address _user,
        uint256 _pid, 
        uint256 _amount) 
        private
        returns (bool)
    {
        UserInfo storage user = userInfo[_pid][_user];

        require(user.available >= _amount, "not enough available");

        // 7 day cooldown after withdraw request
        uint256 timestamp = block.timestamp + 7 days;

        require(user.unlocks[timestamp] == 0);

        user.timestamps.push(timestamp);
        user.unlocks[timestamp] = _amount;
        user.available = user.available.sub(_amount);

        return true;
    }

    function withdraw(
        uint256 pid, 
        uint256 timestamp)
        public
    {
        require(_withdraw(msg.sender, pid, timestamp));
    }

    // withdraw unlocked tokens
    function _withdraw(
        address _user,
        uint256 _pid, 
        uint256 _timestamp) 
        private 
        returns (bool)
    {
        // current time is greater than timestamp
        require(block.timestamp > _timestamp, "not yet time to withdraw.");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        // amount of tokens set to unlock at this time
        uint _amount = user.unlocks[_timestamp];
        
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        
        if (_pending > 0) 
        {
            safeRewardTransfer(_user, _pending);
            emit RewardPaid(_user, _pending);
        }
        
        if (_amount > 0) 
        {
            user.amount = user.amount.sub(_amount);
            user.unlocks[_timestamp] = 0;

            pool.token.safeTransfer(_user, _amount);
        }
        
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Withdraw(_user, _pid, _amount);

        return true;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public 
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough tSHAREs.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 _tshareBal = token.balanceOf(address(this));
        if (_tshareBal > 0) {
            if (_amount > _tshareBal) {
                token.safeTransfer(_to, _tshareBal);
            } else {
                token.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (tSHARE or lps) if less than 90 days after pool ends
            require(_token != token, "token");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}
