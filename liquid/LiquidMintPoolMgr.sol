
//           DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
//                   Version 2, December 2004
// 
//Copyright (C) 2021 ins3project <ins3project@yahoo.com>
//
//Everyone is permitted to copy and distribute verbatim or modified
//copies of this license document, and changing it is allowed as long
//as the name is changed.
// 
//           DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
//  TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
//
// You just DO WHAT THE FUCK YOU WANT TO.
pragma solidity >=0.6.0 <0.7.0;

import "../@openzeppelin/math/SafeMath.sol";
import "../@openzeppelin/introspection/IERC1820Registry.sol";
import "../@openzeppelin/token/ERC777/IERC777Recipient.sol";
import "../@openzeppelin/utils/Address.sol";
import "../@openzeppelin/token/ERC777/IERC777.sol";
import "../@openzeppelin/token/ERC20/IERC20.sol";
import "../@openzeppelin/token/ERC20/SafeERC20.sol";
import '../@openzeppelin/math/Math.sol';
import "../IUpgradable.sol";
import "../ITFCoinHolderBase.sol";

contract LiquidMintPoolMgr is IUpgradable, IERC777Recipient {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;


  IERC1820Registry private _erc1820 ;
  bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
    0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

  struct UserInfo {
    uint256 amount;     
    uint256 rewardDebt; 
    uint256 timestamp;  
  }

  struct PoolInfo {
    IERC20 lpToken;           
    uint256 allocPoint;       
    uint256 lastRewardBlock;  
    uint256 accTokenPerShare; 
  }

  address public itfTokenHolder;

  uint256 public itfSupply;  

  uint256 public itfBalance; 

  uint256 public tokenPerSecond; 

  uint256 public startFarmBlock;

  PoolInfo[] public poolInfo;
  mapping (uint256 => mapping (address => UserInfo)) public userInfo;

  uint256 public totalAllocPoint = 0;

  PriceMetaInfoDB _priceMetaInfoDb;
  mapping(address => uint256) public poolIndexes;

  mapping (address => bool) private _accountCheck;
  address[] private _accountList;

  event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint value);
  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event RewardsHarvest(address indexed user,uint256 indexed pid, uint256 amount);

  constructor(
        address ERC1820Register_,
        address itfTokenHolder_,
        uint256 itfSupply_,
        uint256 tokenPerSecond_,
        uint256 startBlock_,
        address ownable_
    ) public {
        itfTokenHolder = itfTokenHolder_;
        itfSupply = itfSupply_;
        itfBalance = itfSupply_;
        tokenPerSecond = tokenPerSecond_; 
        startFarmBlock = startBlock_;

        if (ERC1820Register_==address(0)){
            _erc1820 = IERC1820Registry(address(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820));
        }else{
            _erc1820 = IERC1820Registry(ERC1820Register_);
        }

        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        setOwnable(ownable_);
    }

    function  updateDependentContractAddress() public override{
        address priceMetaInfoDbAddress = register.getContract("MIDB");
        _priceMetaInfoDb=PriceMetaInfoDB(priceMetaInfoDbAddress);
        require(priceMetaInfoDbAddress!=address(0),"Null for MIDB");
    }

    function poolsCount() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(uint256 allocPoint_, IERC20 lpToken_, bool withUpdate_) public onlyOwner {
        if (withUpdate_) {
            updateAllPools();
        }
        require(poolIndexes[address(lpToken_)] < 1, "LpToken exists");
        uint256 lastRewardBlock = block.number > startFarmBlock ? block.number : startFarmBlock;
        totalAllocPoint = totalAllocPoint.add(allocPoint_);
        poolInfo.push(PoolInfo({
            lpToken: lpToken_,
            allocPoint: allocPoint_,
            lastRewardBlock: lastRewardBlock,
            accTokenPerShare: 0
        }));

        poolIndexes[address(lpToken_)] = poolInfo.length;
    }

    function setPoolAllocPoint(uint256 pid_, uint256 allocPoint_, bool withUpdate_) public onlyOwner {
        if (withUpdate_) {
            updateAllPools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[pid_].allocPoint).add(allocPoint_);
        poolInfo[pid_].allocPoint = allocPoint_;
    }

    function setTokenPerSecond(uint256 tokenPerSecond_) public onlyOwner {
        updateAllPools();
        tokenPerSecond = tokenPerSecond_;
    }

    function setStartFarmBlock(uint256 startBlock_) public onlyOwner {
        uint256 length = poolInfo.length;
        require(startBlock_ > block.number, "startBlock error");
        startFarmBlock = startBlock_;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = startFarmBlock;
        }
    }

    function pendingRewards(uint256 pid_, address user_) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid_];
        UserInfo storage user = userInfo[pid_][user_];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 tokenReward = _getPoolReward(pool.lastRewardBlock, pool.allocPoint);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }

        return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    function updateAllPools() public whenNotPaused {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 pid_) public whenNotPaused {
        PoolInfo storage pool = poolInfo[pid_];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 poolLpBalance = pool.lpToken.balanceOf(address(this));
        if (poolLpBalance == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 tokenReward = _getPoolReward(pool.lastRewardBlock, pool.allocPoint);

        pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e12).div(poolLpBalance));
        pool.lastRewardBlock = block.number;
    }

    function harvestITFRewards(uint256 pid_,address to_) public whenNotPaused{
        if(to_ == address(0)){
            to_ = address(_msgSender());
        }

        PoolInfo storage pool = poolInfo[pid_];
        UserInfo storage user = userInfo[pid_][to_];
        updatePool(pid_);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            _safeTokenTransfer(to_, pending);
            emit RewardsHarvest(to_,pid_,pending);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
    }

    function deposit(uint256 pid_, uint256 amount_, address to_) public whenNotPaused {
        if(to_ == address(0)){
            to_ = address(_msgSender());
        }

        PoolInfo storage pool = poolInfo[pid_];
        UserInfo storage user = userInfo[pid_][to_];
        updatePool(pid_);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            _safeTokenTransfer(to_, pending);
            emit RewardsHarvest(to_,pid_,pending);

        }
        pool.lpToken.safeTransferFrom(address(_msgSender()), address(this), amount_);
        user.amount = user.amount.add(amount_);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        user.timestamp = block.timestamp;

        if (!_accountCheck[to_]) {
            _accountCheck[to_] = true;
            _accountList.push(to_);
        }
        emit Deposit(to_, pid_, amount_);
    }

    function withdraw(uint256 pid_, uint256 amount_) public whenNotPaused {
        PoolInfo storage pool = poolInfo[pid_];
        UserInfo storage user = userInfo[pid_][_msgSender()];
        require(amount_ > 0, "user amount is zero");
        require(user.amount >= amount_, "withdraw: amount is larger than hold");
        updatePool(pid_);
        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        _safeTokenTransfer(_msgSender(), pending);
        emit RewardsHarvest(_msgSender(),pid_,pending);
        user.amount = user.amount.sub(amount_);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(_msgSender()), amount_);
        emit Withdraw(_msgSender(), pid_, amount_);
    }

    function emergencyWithdraw(uint256 pid_) public {
        PoolInfo storage pool = poolInfo[pid_];
        UserInfo storage user = userInfo[pid_][_msgSender()];
        uint256 amount_ = user.amount;
        require(amount_ > 0, "user amount is zero");
        user.amount = 0;
        user.rewardDebt = 0;

        pool.lpToken.safeTransfer(address(_msgSender()), amount_);
        emit EmergencyWithdraw(_msgSender(), pid_, amount_);
    }


    function _safeTokenTransfer(address to_, uint256 amount_) internal {
        require(amount_ <= itfBalance, "Balance insufficient");
        ITFCoinHolderBase(itfTokenHolder).reward(to_, amount_,"","");
        itfBalance=itfBalance.sub(amount_);
    }

    function addITFSupply(uint256 amount) public onlyOwner {
        itfSupply=itfSupply.add(amount);
        itfBalance=itfBalance.add(amount);
    }

    function _getPoolReward(uint256 poolLastRewardBlock_, uint256 poolAllocPoint_) internal view returns(uint256) {
        return block.number.sub(poolLastRewardBlock_).mul(_priceMetaInfoDb.blockTime()).mul(tokenPerSecond).div(1000)
          .mul(poolAllocPoint_).div(totalAllocPoint);
    }

    function tokensReceived(address /*operator_*/, address from_, address to_, uint amount_,
                            bytes calldata /*userData_*/,
                            bytes calldata /*operatorData_*/) override external {

          emit TokenTransfer(_msgSender(), from_, to_, amount_);
    }

    function accountTotal() public view returns (uint256) {
       return _accountList.length;
    }

    function accountList(uint256 begin_) public view returns (address[100] memory) {
        require(begin_ >= 0 && begin_ < _accountList.length, "accountList out of range");
        address[100] memory res;
        uint256 range = Math.min(_accountList.length, begin_.add(100));
        for (uint256 i = begin_; i < range; i++) {
            res[i-begin_] = _accountList[i];
        }
        return res;
    }
}