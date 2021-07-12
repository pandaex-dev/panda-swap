pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

contract InviteController is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public _rewardToken;
    IERC20 public _pool;
    mapping(address => address) public _inviterRegist;
    mapping(address => address[]) public _inviteDetails;
    mapping(address => bool) public _contractWhiteList;
    mapping(address => RewardSnapshot[]) public _rewardHistory;
    mapping(address => uint256) public _accumulateInviterReward;
    mapping(address => uint256) public _accumulateInviteeReward;
    uint256 public _stakeLpLimit;

    address[] public _inviterRewardList;
    uint256[] public _inviterRewardAmountList;
    mapping(address => uint256) public _inviterIndexs;

    uint256 public _inviterRewardRatio = 20;
    uint256 public _inviteeRewardRatio = 50;

    struct RewardSnapshot {
        uint256 time;
        address caller;
        address account;
        uint256 reward;
    }

    event RegistInviter(address indexed invitee, address indexed inviter);
    event RewardInviter(address indexed caller, address indexed invitee, address indexed inviter, uint256 amount);
    event RewardInvitee(address indexed caller, address indexed invitee, address indexed inviter, uint256 amount);

    constructor() public {
    }

    function initialize(
        IERC20 rewardToken,
        IERC20 pool,
        uint256 stakeLpLimit
    ) public onlyOwner{
        _rewardToken = rewardToken;
        _pool = pool;
        _stakeLpLimit = stakeLpLimit;
    }

    function addWhitelist(address poolAddress) public onlyOwner{
        _contractWhiteList[poolAddress] = true;
    }

    function removeWhitelist(address poolAddress) public onlyOwner{
        _contractWhiteList[poolAddress] = false;
    }

    function setInviterRewardRatio(uint256 ratio) public onlyOwner{
        _inviterRewardRatio = ratio;
    }

    function setInviteeRewardRatio(uint256 ratio) public onlyOwner{
        _inviteeRewardRatio = ratio;
    }

    function setStakeLpLimit(uint256 stakeLpLimit) public onlyOwner{
        _stakeLpLimit = stakeLpLimit;
    }

    function isInviter(address account) public view returns (bool) {
        return _pool.balanceOf(account) >= _stakeLpLimit;
    }

    function poolBalanceOf(address account) public view returns (uint256) {
        return _pool.balanceOf(account);
    }

    function getInviter(address account) public view returns (bool isValid, address inviterAccount) {
        inviterAccount = _inviterRegist[account];
        isValid = (inviterAccount != address(0) && _pool.balanceOf(inviterAccount) >= _stakeLpLimit);
    }

    function getInviterRewardLength() public view returns (uint){
        return _inviterRewardList.length;
    }

    function getRewardHistoryList(address account) public view returns (RewardSnapshot[] memory) {
    	return _rewardHistory[account];
    }

    function getInviterRewardList() public view returns (address[] memory) {
    	return _inviterRewardList;
    }

    function getInviterRewardAmountList() public view returns (uint256[] memory) {
    	return _inviterRewardAmountList;
    }

    function getInviteDetail(address account) public view returns (address[] memory) {
    	return _inviteDetails[account];
    }

    function registInviter(address account) public {
        require(_contractWhiteList[msg.sender],'caller not in whitelist');
        // require(tx.origin != account, 'cannot be same');
        // require(account != address(0), '0x0 address');
        if(tx.origin != account && account != address(0)){
            if(_inviterRegist[tx.origin] == address(0) && isInviter(account)){
                _inviterRegist[tx.origin] = account;
                _inviteDetails[account].push(tx.origin);
                emit RegistInviter(tx.origin, account);
            }
        }
    }

    function rewardInviter(uint256 claimAmount) public {
        if(claimAmount > 0){
            require(_contractWhiteList[msg.sender],'not in whitelist');
            (bool isValid, address inviterAccount) = getInviter(tx.origin);
            if(isValid){
                //reward inviter
                {
                    uint256 amount = claimAmount.mul(_inviterRewardRatio).div(1000);
                    if(amount > 0){
                        _rewardToken.safeTransfer(inviterAccount, amount);
                        RewardSnapshot memory snapshot = RewardSnapshot({
                            time: block.number,
                            caller: msg.sender,
                            account: tx.origin,
                            reward: amount
                        });
                        _rewardHistory[inviterAccount].push(snapshot);
                        uint256 accumulate = _accumulateInviterReward[inviterAccount];
                        if(accumulate == 0 && _accumulateInviteeReward[inviterAccount] == 0){
                            _inviterIndexs[inviterAccount] = _inviterRewardList.length;
                            _inviterRewardList.push(inviterAccount);
                            _inviterRewardAmountList.push(amount);
                        }else{
                            uint256 index = _inviterIndexs[inviterAccount];
                            uint256 reward = _inviterRewardAmountList[index];
                            _inviterRewardAmountList[index] = reward.add(amount);
                        }
                        _accumulateInviterReward[inviterAccount] = accumulate.add(amount);
                        emit RewardInviter(msg.sender, tx.origin, inviterAccount, amount);
                    }
                }
                //reward invitee
                {
                    uint256 amount = claimAmount.mul(_inviteeRewardRatio).div(1000);
                    if(amount > 0){
                        _rewardToken.safeTransfer(tx.origin, amount);
                        RewardSnapshot memory snapshot = RewardSnapshot({
                            time: block.number,
                            caller: msg.sender,
                            account: tx.origin,
                            reward: amount
                        });
                        _rewardHistory[tx.origin].push(snapshot);
                        uint256 accumulate = _accumulateInviteeReward[tx.origin];
                        if(accumulate == 0 && _accumulateInviterReward[tx.origin] == 0){
                            _inviterIndexs[tx.origin] = _inviterRewardList.length;
                            _inviterRewardList.push(tx.origin);
                            _inviterRewardAmountList.push(amount);
                        }else{
                            uint256 index = _inviterIndexs[tx.origin];
                            uint256 reward = _inviterRewardAmountList[index];
                            _inviterRewardAmountList[index] = reward.add(amount);
                        }
                        _accumulateInviteeReward[tx.origin] = accumulate.add(amount);
                        emit RewardInvitee(msg.sender, tx.origin, inviterAccount, amount);
                    }
                }
            }
        }
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin 
     * @param token The address of the ERC-20 token to sweep
     * @param amount The amount of the ERC-20 token to sweep
     */
    function sweepToken(address token,uint256 amount) public onlyOwner{
        if(token != address(0)){
            IERC20(token).safeTransfer(owner(), amount);
        }else{
            payable(owner()).transfer(amount);
        }
    }
}