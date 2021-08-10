pragma solidity ^0.6.0;

// File: @openzeppelin/contracts/math/Math.sol

import '@openzeppelin/contracts/math/Math.sol';

// File: @openzeppelin/contracts/math/SafeMath.sol

import '@openzeppelin/contracts/math/SafeMath.sol';

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// File: @openzeppelin/contracts/utils/Address.sol

import '@openzeppelin/contracts/utils/Address.sol';

// File: @openzeppelin/contracts/token/ERC20/SafeERC20.sol

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import '@openzeppelin/contracts/access/Ownable.sol';

import '../token/LPTokenWrapper.sol';

import '../InviteController.sol';

contract BTCUSDTSharePool is
    LPTokenWrapper, Ownable
{
    IERC20 public sharetoken;
    uint256 public DURATION = 90 days;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    InviteController public _inviteController;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        address sharetoken_,
        address lptoken_,
        uint256 starttime_
    ) public {
        sharetoken = IERC20(sharetoken_);
        lpt = IERC20(lptoken_);
        starttime = starttime_;
        lastUpdateTime = starttime;
        periodFinish = starttime.add(DURATION);
    }

    modifier checkStart() {
        require(
            block.timestamp >= starttime,
            'BTCUSDTSharePool: not start'
        );
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }


     function stakeWithInviter(uint256 amount, address inviter) public {
         stake(amount);
         _inviteController.registInviter(inviter);
     }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, 'BTCUSDTSharePool: Cannot stake 0');
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        override
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, 'BTCUSDTSharePool: Cannot withdraw 0');
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) checkStart {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            sharetoken.safeTransfer(msg.sender, reward);
            _inviteController.rewardInviter(reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function setStartTime(uint256 _starttime)
    external
    onlyOwner
    {
        starttime = _starttime;
        lastUpdateTime = starttime;
        periodFinish = starttime.add(DURATION);
    }

    function setLPMaxLimit(uint256 _maxLimit)
    external
    onlyOwner
    {
        maxLimit = _maxLimit;
    }

    function setInviteController(InviteController inviteController)
    external
    onlyOwner
    {
        _inviteController = inviteController;
    }

    function updateRewardAmount(uint256 reward)
    external
    onlyOwner
    updateReward(address(0))
    {
        if (block.timestamp > starttime) {
            if (block.timestamp >= periodFinish) {
                rewardRate = reward.div(DURATION);
                periodFinish = block.timestamp.add(DURATION);
            } else {
                uint256 remaining = periodFinish.sub(block.timestamp);
                uint256 leftover = remaining.mul(rewardRate);
                if(reward < leftover){
                    sharetoken.safeTransfer(msg.sender, leftover - reward);
                }else{
                    sharetoken.safeTransferFrom(msg.sender, address(this), reward - leftover);
                }
                rewardRate = reward.div(remaining);
            }
            lastUpdateTime = block.timestamp;
            emit RewardAdded(reward);
        } else {
            uint256 leftover = DURATION.mul(rewardRate);
            if(reward < leftover){
                sharetoken.safeTransfer(msg.sender, leftover - reward);
            }else{
                sharetoken.safeTransferFrom(msg.sender, address(this), reward - leftover);
            }
            rewardRate = reward.div(DURATION);
            lastUpdateTime = block.timestamp;
            emit RewardAdded(reward);
        }
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin 
     * @param token The address of the ERC-20 token to sweep
     * @param amount The amount of the ERC-20 token to sweep
     */
    function sweepToken(address token,uint256 amount) public onlyOwner{
        if(token != address(0) && token != address(lpt)){
            IERC20(token).safeTransfer(owner(), amount);
        }else if(token == address(0)){
            payable(owner()).transfer(amount);
        }
    }


}
