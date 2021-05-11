
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
pragma experimental ABIEncoderV2;


import "./@openzeppelin/token/ERC721/ERC721.sol";
import "./@openzeppelin/access/Ownable.sol";
import "./@openzeppelin/math/SafeMath.sol";
import "./@openzeppelin/math/Math.sol";
import "./@openzeppelin/token/ERC20/SafeERC20.sol";
import "./@openzeppelin/token/ERC20/ERC20.sol";
import "./@openzeppelin/utils/ReentrancyGuard.sol";

import "./IUpgradable.sol";
import "./IStakingPool.sol";
import "./PriceMetaInfoDB.sol";
import "./CompatibleERC20.sol";
import "./flashloan/IFlashLoanReceiver.sol";

struct CoinHolderV2 {
    uint256     principal;  


    uint256     beginTimestamp;
    address[]   pools;
}


contract StakingTokenHolderV2
{
    using SafeMath for uint256;
    mapping(uint256=>CoinHolderV2) public _coinHolders; 

    address _operator;

    function setOperator(address addr) public {
        require(_operator==address(0),"only once");
        _operator=addr;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "Ownable: caller is not the operator");
        _;
    }

    function canReleaseTokenHolder(uint256 tokenId) view public returns(bool/*,address [] memory*/){
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        for (uint256 i=0;i<holder.pools.length;++i){
            address poolAddr=holder.pools[i];
            require(poolAddr!=address(0),"Pool address should not be 0");
            IClaimPool pool=IClaimPool(poolAddr);
            if(!pool.isClosed()){
                if(pool.productTokenRemainingAmount() < holder.principal || now >= pool.productTokenExpireTimestamp()){
                    return false;
                }
            }
        }
        return true;

    }



    function coinHolderRemainingPrincipal(uint256 tokenId) view public returns(uint256){
        CoinHolderV2 storage holder = _coinHolders[tokenId];
        uint256 remainingPrincipal = holder.principal;
        for (uint256 i=0;i<holder.pools.length;++i){
            address addr=holder.pools[i];
            IClaimPool pool=IClaimPool(addr);
            uint256 totalNeedPayFromStaking = pool.totalNeedPayFromStaking();
            if(totalNeedPayFromStaking>0){
                uint256 totalStakingAmount = pool.totalStakingAmount();
                uint256 stakingAmount = holder.principal;
                uint256 userPayAmount = stakingAmount.mul(totalNeedPayFromStaking).div(totalStakingAmount);
                if(remainingPrincipal>=userPayAmount){
                    remainingPrincipal = remainingPrincipal.sub(userPayAmount);
                }else{
                    remainingPrincipal = 0;
                    break;
                }
            }
        }
        return remainingPrincipal;
    }

    function capitalTokenAddress(uint256 tokenId) view public returns(address){
        CoinHolderV2 storage holder = _coinHolders[tokenId];
        return IClaimPool(holder.pools[0]).tokenAddress();
    }

    function calcPremiumsRewards(uint256 tokenId) view public returns(uint256 rewards){
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        /*if(holder.haveHarvestPremiums){
            return 0;
        }*/
        rewards=0;
        for (uint256 i=0;i<holder.pools.length;++i){
            address poolAddr=holder.pools[i];
            IClaimPool pool=IClaimPool(poolAddr);
            if (pool.isNormalClosed()){
                rewards=rewards.add(pool.calcPremiumsRewards(holder.principal, holder.beginTimestamp));
            }
        }
        return rewards;
    }


    function isAllPoolsClosed(uint256 tokenId) view public returns(bool){
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        for (uint256 i=0;i<holder.pools.length;++i){
            IClaimPool pool=IClaimPool(holder.pools[i]);
            if (!pool.isClosed()){
                return false;
            }
        }
        return true;
    }

    function getTokenHolderAmount(uint256 tokenId,address/* poolAddr*/) view public returns(uint256){ //TODO
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        return holder.principal;
    }

    function getTokenHolder(uint256 tokenId) view public returns(uint256,uint256,uint256,uint256,address [] memory){   
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        uint256 remainingPrincipal = coinHolderRemainingPrincipal(tokenId);

        return (holder.principal,remainingPrincipal,0,holder.beginTimestamp,holder.pools);
    }

    function getTokenHolderV2(uint256 tokenId) view public returns(CoinHolderV2 memory){   
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        return holder;
    }

    function getTokenHolderPools(uint256 tokenId) view public returns(address [] memory){   
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        return holder.pools; 
    }

    function putTokenHolderInPool(address poolAddr,uint256 tokenId/*,uint256 amount*/) onlyOperator public {
        CoinHolderV2 storage holder=_coinHolders[tokenId];
        holder.pools.push(poolAddr);
    }


    function set(uint256 tokenId,uint256 principal,/*uint256 availableMarginAmount,*/uint256 beginTimestamp/*,bytes8 coinName*/) onlyOperator public{
        _coinHolders[tokenId]=CoinHolderV2(principal,/*availableMarginAmount,*/beginTimestamp,/*coinName,*/new address[](0));
    }

    function initSponsor() external {
        ISponsorWhiteListControl SPONSOR = ISponsorWhiteListControl(address(0x0888000000000000000000000000000000000001));
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }
}


contract StakingPoolTokenV2 is ERC721, IUpgradable, ReentrancyGuard
{
    using SafeMath for uint256;
    using CompatibleERC20 for address;
    using SafeERC20 for IERC20;


    StakingTokenHolderV2 public _coinHolders;

    uint256 public _tokenCount; 

    mapping(address=>string) _pools;
    PriceMetaInfoDB  _priceMetaInfoDb;
    bool public flashLoanEnable;


    uint256 public totalFlashLoanCount; 

    uint256 public totalFlashLoanAmount; 

    uint256 public totalFlashLoanPremiums; 

    uint256 public exitFeesRate; //50 0.5%

    mapping(address=>uint256) _compensation;

    event NewTokenHolderCreated(uint256 tokenId);
    event TokenHolderReleased(uint256 tokenId);

  event FlashLoan(
    address indexed target,
    address indexed initiator,
    address indexed asset,
    uint256 amount,
    uint256 premium,
    uint16 referralCode
  );

    constructor(address coinHolder) ERC721("Ins3.finance Capital Token","iNFT") public{
        _coinHolders = StakingTokenHolderV2(coinHolder);
        _coinHolders.setOperator(address(this));
        exitFeesRate = 50;
    }


    function  updateDependentContractAddress() public override{
        _priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));
    }

    function checkPoolsAmounts(address [] memory pools/*, uint256 []  memory amounts, uint256 amount,uint256 maxAmount*/) view public returns(bool){ 
        require(pools.length>0 && pools.length<=_priceMetaInfoDb.STAKING_TOKEN_MARGIN(),"pool length error");
        
        IClaimPool pool1=IClaimPool(pools[0]);
        uint256 expireTimestamp = pool1.productTokenExpireTimestamp();
        address tokenAddress = pool1.tokenAddress();
        for (uint256 i=0;i<pools.length;++i){
            address addr=pools[i];
            IClaimPool pool=IClaimPool(addr);
            require(isPool(addr),"all pools should be registered");
            require(pool.productTokenExpireTimestamp()==expireTimestamp,"pool expire time error");
            require(pool.tokenAddress()==tokenAddress,"pool address not same");

        }
        return true;
    }

    function canReleaseTokenHolder(uint256 tokenId) view public returns(bool/*,address [] memory*/){
        require(_exists(tokenId),"No such tokenId");

        return _coinHolders.canReleaseTokenHolder(tokenId);
    }



    function isPool(address poolAddr) view public returns(bool){
        return bytes(_pools[poolAddr]).length!=0;
    }

    modifier onlyPool(){
        require(isPool(_msgSender()),"Unknown staking pool");
        _;
    }



    function newTokenHolder(address [] memory pools, /*uint256 []  memory amounts,bytes8 coinName,*/uint256 amount) whenNotPaused external  {
        require(amount>0,"amount must > 0");
        require(checkPoolsAmounts(pools/*,amounts,amount,maxAmount*/),"Check pools failed");
        address token= IClaimPool(pools[0]).tokenAddress();

        require(token.allowanceERC20(_msgSender(),address(this))>=amount,"No enough allowance for new token holder");
        token.transferFromERC20(_msgSender(),address(this),amount);
        
        uint256 tokenId = _tokenCount;
        uint256 beginTimestamp = now;
        _coinHolders.set(tokenId,amount,/*maxAmount,*/beginTimestamp/*,coinName*/);

        for (uint256 i=0;i<pools.length;++i){
            address addr=pools[i];
            IClaimPool pool=IClaimPool(addr);
            pool.putTokenHolder(tokenId,amount,beginTimestamp);
            _coinHolders.putTokenHolderInPool(addr,tokenId/*,amount*/);
        }
        _tokenCount+=1;

        _mint(_msgSender(),tokenId);
        emit NewTokenHolderCreated(tokenId);
    }



    function calcPoolPayAmount(uint256 tokenId, address poolAddr) view public returns(uint256) {
        address [] memory poolAddrs = _coinHolders.getTokenHolderPools(tokenId);
        uint256 totalPayAmount = 0;
        uint256 poolPayAmount = 0;
        for (uint256 i=0;i<poolAddrs.length;++i) {
            IClaimPool pool=IClaimPool(poolAddrs[i]);
            uint256 totalNeedPayFromStaking = pool.totalNeedPayFromStaking();
            if(totalNeedPayFromStaking > 0) {
                uint256 stakingAmount = getTokenHolderAmount(tokenId, poolAddrs[i]);
                uint256 userPayAmount = stakingAmount.mul(totalNeedPayFromStaking).div(pool.totalStakingAmount());
                totalPayAmount = totalPayAmount.add(userPayAmount);
                if(poolAddrs[i]==poolAddr){
                    poolPayAmount = userPayAmount;
                }
            }
        }
        if(totalPayAmount==0){
            return 0;
        } else{
            uint256 stakingAmount = getTokenHolderAmount(tokenId, poolAddr);
            return poolPayAmount.mul(stakingAmount).div(totalPayAmount);
        }
    }

    function releaseTokenHolder(uint256 tokenId) nonReentrant whenNotPaused external {
        require(ownerOf(tokenId)==_msgSender(),"The tokenId does not belong to you");
        bool canRelease = canReleaseTokenHolder(tokenId);
        require(canRelease,"Can not release the tokenId");

        bool isAllClosed = _coinHolders.isAllPoolsClosed(tokenId);
        if (isAllClosed){
            uint256 rewards = calcPremiumsRewards(tokenId);
            if (rewards>0){
                address tokenAddress = capitalTokenAddress(tokenId);
                tokenAddress.transferERC20(_msgSender(),rewards);
            }
        }

        CoinHolderV2 memory coinHolder = _coinHolders.getTokenHolderV2(tokenId);
        address [] memory poolAddrs = coinHolder.pools;
        for (uint256 i=0;i<poolAddrs.length;++i){ 
            IClaimPool pool=IClaimPool(poolAddrs[i]);
            if(!pool.isClosed()){
                pool.takeTokenHolder(tokenId);
            } else {
                uint256 totalNeedPayFromStaking = pool.totalNeedPayFromStaking();
                if(totalNeedPayFromStaking > 0) {
                    uint256 payAmount = calcPoolPayAmount(tokenId, poolAddrs[i]);
                    pool.getAToken(payAmount, _msgSender());
                }
            }
        }

        uint256 remainingPrincipal=coinHolderRemainingPrincipal(tokenId);
        _burn(tokenId);
        if(remainingPrincipal>0){
            uint256 returnAmount = remainingPrincipal;
            uint256 feesAmount = 0;
            uint256 stakingSeconds = now.sub(coinHolder.beginTimestamp);
            if(!isAllClosed && stakingSeconds < 7 days){
                feesAmount = returnAmount.mul(exitFeesRate).div(10000);
                returnAmount = returnAmount.sub(feesAmount);
            }
            address tokenAddress = capitalTokenAddress(tokenId);
            if(feesAmount>0){
                tokenAddress.transferERC20(admin(),feesAmount);
            }
            if(returnAmount>0){
                tokenAddress.transferERC20(_msgSender(),returnAmount);
            }
        }
        emit TokenHolderReleased(tokenId);
    }


 
    function bookkeepingFromPool(uint256 amount) onlyPool public{
        address poolAddr=_msgSender();

        _compensation[poolAddr]=_compensation[poolAddr].add(amount);
        uint256 totalBalance = IClaimPool(poolAddr).tokenAddress().balanceOfERC20(address(this));
        require(totalBalance >= _compensation[poolAddr],"Amount is too large");
        
    }

    function claim(address poolAddr) nonReentrant whenNotPaused public{
       address userAddr=_msgSender();
       require(isPool(poolAddr),"unknown staking pool");
       IClaimPool pool=IClaimPool(poolAddr);
       (uint256 amount,/*uint256 tokenBalance*/) = pool.queryAndCheckClaimAmount(userAddr);
       require(amount>0,"not claim");
       require(_compensation[poolAddr]>=amount,"amount must < pool's pay amount");
           _compensation[poolAddr]=_compensation[poolAddr].sub(amount);
            address tokenAddress = pool.tokenAddress();
            tokenAddress.transferERC20(userAddr,amount);
            pool.returnRemainingAToken(userAddr);

    }

    function coinHolderRemainingPrincipal(uint256 tokenId) view public returns(uint256){
        return _coinHolders.coinHolderRemainingPrincipal(tokenId);
    }

    function capitalTokenAddress(uint256 tokenId) view public returns(address){
        return _coinHolders.capitalTokenAddress(tokenId);
    }


    function calcPremiumsRewards(uint256 tokenId) view public returns(uint256 rewards/*,address [] memory*/){
        require(_exists(tokenId),"The tokenId does not exist");
        return _coinHolders.calcPremiumsRewards(tokenId);
    }



    function getTokenHolder(uint256 tokenId) view public returns(uint256,uint256,uint256,uint256,address [] memory){   
        require(_exists(tokenId),"Token does not exist");
        return _coinHolders.getTokenHolder(tokenId);

    }

    function registerStakingPool(address poolAddr,string memory poolName) onlyOwner public {
        require(!isPool(poolAddr),"Staking pool has been already registered");
        _pools[poolAddr]=poolName;
    }

    function unregisterStakingPool(address poolAddr) onlyOwner public{
        require(isPool(poolAddr),"Staking pool has not been registered");
        delete _pools[poolAddr];
    }

    function getStakingPoolName(address poolAddr) view public returns(string memory){
        return _pools[poolAddr];
    }

    function getTokenHolderAmount(uint256 tokenId,address poolAddr) view public returns(uint256){
        require(_exists(tokenId),"Token does not exist when put it into pool");
        return _coinHolders.getTokenHolderAmount(tokenId,poolAddr);
    }

    function isTokenExist(uint256 tokenId) view public returns(bool){
        return _exists(tokenId);
    }

    function setExitFeesRate(uint256 rate) onlyOwner public{
        exitFeesRate = rate;
    }

    struct FlashLoanLocalVars {
        IFlashLoanReceiver receiver;
        uint256 i;
        address currentAsset;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
    }
  function flashLoan(
    address receiverAddress,
    address[] calldata assets,
    uint256[] calldata amounts,
    bytes calldata params,
    uint16 referralCode
  ) external nonReentrant whenNotPaused
  {
    require(flashLoanEnable,"flash loan not enable");

    totalFlashLoanCount = totalFlashLoanCount.add(1);

    FlashLoanLocalVars memory vars;

    require(assets.length == amounts.length, "invalid loan params");

    uint256[] memory premiums = new uint256[](assets.length);

    vars.receiver = IFlashLoanReceiver(receiverAddress);

    for (vars.i = 0; vars.i < assets.length; vars.i++) {

      premiums[vars.i] = amounts[vars.i].mul(_priceMetaInfoDb.FLASHLOAN_PREMIUMS_PERCENT()).div(_priceMetaInfoDb.FLASHLOAN_PREMIUMS_DIVISOR());
      totalFlashLoanAmount = totalFlashLoanAmount.add(amounts[vars.i]);
      totalFlashLoanPremiums = totalFlashLoanPremiums.add(premiums[vars.i]);

      address payable receiverAddressPayable = address(uint160(receiverAddress));
      IERC20(assets[vars.i]).safeTransfer(receiverAddressPayable, amounts[vars.i]);
    }

    require(vars.receiver.executeOperation(assets, amounts, premiums, msg.sender, params),"invalid flash loan executor return");

    for (vars.i = 0; vars.i < assets.length; vars.i++) {
      vars.currentAsset = assets[vars.i];
      vars.currentAmount = amounts[vars.i];
      vars.currentPremium = premiums[vars.i];
      vars.currentAmountPlusPremium = vars.currentAmount.add(vars.currentPremium);

      IERC20(vars.currentAsset).safeTransferFrom(
        receiverAddress,
        address(this),
        vars.currentAmountPlusPremium
      );

      IERC20(vars.currentAsset).safeTransfer(admin(), vars.currentPremium);

      emit FlashLoan(
        receiverAddress,
        msg.sender,
        vars.currentAsset,
        vars.currentAmount,
        vars.currentPremium,
        referralCode
      );
    }
  }

    function setFlashLoanEnable(bool enable) public onlyOwner{
        flashLoanEnable = enable;
    }

}
