// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

contract LaunchpadV1 is Ownable, ReentrancyGuard 
{
    using SafeERC20 for IERC20;

    // The address of the token to be launched
    IERC20 public launchedToken;

    // The address of the token to be accepted as payment for claiming the launched token
    IERC20 public paymentToken;

    // Total amount of launched tokens to be claimable by others
    uint public totalClaimable;

    // Total amount of tokens already claimed
    uint public totalClaimed;

    // time the sale starts
    uint public startWhitelistPhase;

    // time the whitelist claiming period ends
    uint public startFCFSPhase;

    // time the first come first served phase ends
    uint public endSale;

    // price of 1 payment token per launchpad token in basis points
    // 80  => 0.8 
    // 120 => 1.2
    uint public price;

    // Stores allocated values for each user
    // 0x => 1000
    mapping (address => uint) public allocated;

    bool public allocationsDistributed = false;

    // Stores all claims per address
    // 0x => 0  => 1000
    // 0x => 30 => 9000
    mapping (address => mapping (uint => uint)) public claims;

    // stores how many tokens have been released
    mapping (address => mapping (uint => uint)) public released;

    // defines vesting options
    uint public vestingStartTimestamp = 0;
    
    // ratio of tokens allocated to each vesting period (in days)
    // 0 =>  20  
    // 20% released immediately
    // 30 => 80  
    // 80% vested over 30 days
    mapping (uint => uint) public vestingPeriodAllocationRatios;

    // set the list of vesting duration periods
    // 0 => 0
    // 1 => 30
    uint[] public vestingDurationPeriods;

    // Limit executions to uninitalized launchpad state only
    modifier onlyUninitialized() 
    {
        require(address(launchedToken) == address(0x0), "You can only initialize a launchpad once!");
        _;
    }

    // Limit executions to initalized launchpad state only
    modifier onlyInitialized() 
    {
        require(totalClaimable > 0, "Launchpad has not been initialized yet!");
        _;
    }

    // Limit executions to unstarted launchpad state only
    modifier onlyUnstarted() 
    {
        require(startWhitelistPhase == 0, "You can only start a launchpad once!");
        _;
    }

    modifier onlyWhitelistPhase()
    {
        require(block.timestamp >= startWhitelistPhase);
        require(block.timestamp <  startFCFSPhase);
        _;
    }

    modifier onlyFCFSPhase()
    {
        require(block.timestamp >= startFCFSPhase);
        require(block.timestamp <  endSale);
        _;
    }

    modifier onlyDistributionPhase()
    {
        require(vestingStartTimestamp > 0);
        require(block.timestamp >= vestingStartTimestamp);
        _;
    }

    modifier onlyAllocationsDistributed()
    {
        require(allocationsDistributed == true, "Allocations not yet distributed.");
        _;
    }

    function claimWhitelist(uint amount) 
        external 
        onlyWhitelistPhase 
        nonReentrant 
        returns(bool) 
    {
        address user = msg.sender;

        require(allocated[user] >= amount, "User does not have a whitelist allocation.");

        require(_claim(user, amount));

        allocated[user] -= amount;

        return true;
    }

    function claim(uint amount) 
        external 
        onlyFCFSPhase
        nonReentrant 
        returns(bool) 
    {        
        require(_claim(msg.sender, amount));
        return true;
    }

    function _claim(
        address user, 
        uint amount) 
        private 
        returns (bool)
    {
        require(amount > 0);
        require(totalClaimed + amount <= totalClaimable, "Claiming attempt exceeds total claimable amount!");

        paymentToken.safeTransferFrom(
            user,
            address(this),
            _convertToPaymentTokenAmount(amount));

        for(uint i = 0; i < vestingDurationPeriods.length; ++i)
        {
            uint period = vestingDurationPeriods[i];
            uint allocation = vestingPeriodAllocationRatios[period];
            claims[user][period] += (amount * allocation / 100);
        }        

        totalClaimed += amount;

        return true;
    }

    function _convertToPaymentTokenAmount(uint256 amount) 
        private 
        view 
        returns (uint256)
    {
        uint paymentTokenDecimals = ERC20(address(paymentToken)).decimals();
        uint launchedTokenDecimals = ERC20(address(launchedToken)).decimals();
        
        return amount * price / 100 / 10 ** (launchedTokenDecimals - paymentTokenDecimals);
    }

    function getTotalClaimedInPaymentTokens() 
        external 
        view    
        returns (uint256)
    {
        return _convertToPaymentTokenAmount(totalClaimed);
    }

    function getTotalClaimableInPaymentTokens() 
        external 
        view 
        returns (uint256)
    {
        return _convertToPaymentTokenAmount(totalClaimable);
    }

    // Releases claim for a single address
    function release() 
        external 
        onlyDistributionPhase
        nonReentrant 
        returns(bool) 
    {
        require(_release(msg.sender));
        return true;
    }

    function _release(address user) 
        private 
        returns(bool) 
    {
        uint total = 0;
        uint timestamp = block.timestamp;

        for(uint i = 0; i < vestingDurationPeriods.length; ++i)
        {
            uint period = vestingDurationPeriods[i];
            uint amount = releasableAt(user, period, timestamp);
            released[user][period] += amount;
            total += amount;
        }

        require(total > 0, "No more tokens to release");

        launchedToken.safeTransfer(user, total);

        return true;
    }

    // gets the amount of tokens that are yet to be released
    function releasableAt(
        address user, 
        uint period,
        uint timestamp) 
        public 
        view 
        returns (uint) 
    {
        return _vestedAmount(user, period, timestamp) - released[user][period];
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function _vestedAmount(
        address user, 
        uint period, 
        uint timestamp) 
        internal
        virtual 
        view 
        returns (uint) 
    {
        uint totalAllocation = claims[user][period];

        if (period == 0)
        {
            return totalAllocation;
        }
        
        if (timestamp < vestingStartTimestamp) 
        {
            return 0;
        } 
        else if (timestamp > vestingStartTimestamp + period) 
        {
            return totalAllocation;
        } 
        else 
        {
            return (totalAllocation * (timestamp - vestingStartTimestamp)) / period;
        }
    }

    ////////////////////////////////////////////////////////////////////////
    //                        ADMIN FUNCTIONS                             //
    ////////////////////////////////////////////////////////////////////////
    function init(
        address _launchedToken,
        address _paymentToken,
        uint[] calldata periods,
        uint[] calldata ratios) 
        external 
        onlyUninitialized 
        onlyOwner 
        returns(bool) 
    {
        require(_launchedToken != address(0x0), "Zero Address: Not Allowed");
        require(_paymentToken != address(0x0), "Zero Address: Not Allowed");

        launchedToken = IERC20(_launchedToken);
        paymentToken = IERC20(_paymentToken);
        totalClaimable = launchedToken.balanceOf(address(this));

        require(totalClaimable > 0, "You need to initalize the launchpad with claimable tokens!");
        
        uint total = 0;
        for(uint i = 0; i < periods.length; ++i)
        {
            vestingDurationPeriods.push(periods[i]);
            vestingPeriodAllocationRatios[periods[i]] = ratios[i];
            total += ratios[i];
        }

        require(total == 100);

        return true;
    }

    function setStartTime(
        uint _whitelistSaleTimestamp,
        uint _fcfsSaleTimestamp,
        uint _endSaleTimestamp,
        uint _price) 
        external 
        onlyOwner 
        onlyInitialized 
        onlyUnstarted
        onlyAllocationsDistributed
        returns(bool) 
    {        
        startWhitelistPhase = _whitelistSaleTimestamp;
        startFCFSPhase = _fcfsSaleTimestamp;
        endSale = _endSaleTimestamp;
        
        price = _price;
        
        return true;
    }

    function setStartDistributionTime(uint time) 
        external 
        onlyOwner 
        returns (bool)
    {
        vestingStartTimestamp = time;
        return true;
    }

    // Releases payment token to the owner.
    function releasePayments() 
        external 
        onlyOwner 
        nonReentrant 
        returns(bool) 
    {
        paymentToken.safeTransfer(owner(), paymentToken.balanceOf(address(this)));

        return true;
    }

    // Releases unclaimed launched tokens back to the owner.
    function releaseUnclaimed() 
        external
        //todo only after sale 
        onlyOwner 
        nonReentrant 
        returns(bool) 
    {
        uint256 unclaimed = totalClaimable - totalClaimed;
        launchedToken.safeTransfer(owner(), unclaimed);
        totalClaimable = 0;

        return true;
    }

    function setAllocations(
        address[] calldata _users, 
        uint[] calldata _amount)
        external
        onlyOwner
    {
        require(
            _users.length == _amount.length, 
            "Number of users should be same as the amount length");

        for (uint i = 0; i < _users.length; i++) 
        {
            allocated[_users[i]] = _amount[i];
        }

        allocationsDistributed = true;
    }
}