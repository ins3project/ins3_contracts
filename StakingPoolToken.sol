
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
import "./ERC20TokenRegister.sol";
import "./CompatibleERC20.sol";
import "./flashloan/IFlashLoanReceiver.sol";

struct CoinHolder {
    uint256     principal;  

    uint256     availableMarginAmount; 

    uint256     beginTimestamp;
    bytes8      coinName;  
    address[]   pools;
    mapping(address=>uint256)   poolHoldAmount;
    mapping(address=>bool)   poolHoldPremiums;
}


contract StakingTokenHolder
{
    using SafeMath for uint256;
    mapping(uint256=>CoinHolder)  _coinHolders; 

    address _operator;

    function setOperator(address addr) public {
        require(_operator==address(0),"only once");
        _operator=addr;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "Ownable: caller is not the operator");
        _;
    }

    function canReleaseTokenHolder(uint256 tokenId) view public returns(bool,address [] memory){
        CoinHolder storage holder=_coinHolders[tokenId];
        address [] memory pools=new address[](holder.pools.length);
        bool canRelease=true;
        for (uint256 i=0;i<holder.pools.length;++i){
            address poolAddr=holder.pools[i];
            require(poolAddr!=address(0),"Pool address should not be 0");
            IStakingPool pool=IStakingPool(poolAddr);
            uint256 holdAmount=holder.poolHoldAmount[poolAddr];
            if(pool.isClosed()){
                pools[i]=address(0);
            }else{
                if(pool.productTokenRemainingAmount()>=holdAmount && now < pool.productTokenExpireTimestamp()){
                    pools[i]=poolAddr;
                }else{ 
                    pools[i]=address(0);
                    canRelease=false;
                }
            }
        }
        return (canRelease,pools);

    }

    function getCoinName(uint256 tokenId) view public returns(bytes8){
        CoinHolder storage holder=_coinHolders[tokenId];

        return holder.coinName;
    }


    function coinHolderRemainingPrincipal(uint256 tokenId) view public returns(uint256){
        CoinHolder storage holder = _coinHolders[tokenId];
        uint256 remainingPrincipal = holder.principal;
        for (uint256 i=0;i<holder.pools.length;++i){
            address addr=holder.pools[i];
            IStakingPool pool=IStakingPool(addr);
            uint256 totalNeedPayFromStaking = pool.totalNeedPayFromStaking();
            if(totalNeedPayFromStaking>0){
                uint256 totalStakingAmount = pool.totalStakingAmount();
                uint256 stakingAmount = holder.poolHoldAmount[addr];
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

    function calcPremiumsRewards(uint256 tokenId) view public returns(uint256 rewards,address [] memory){
        CoinHolder storage holder=_coinHolders[tokenId];
        rewards=0;
        address [] memory closedPoolAddrs=new address[](holder.pools.length);
        for (uint256 i=0;i<holder.pools.length;++i){
            address poolAddr=holder.pools[i];
            IStakingPool pool=IStakingPool(poolAddr);
            if (pool.isNormalClosed() && !holder.poolHoldPremiums[poolAddr]){
                rewards=rewards.add(pool.calcPremiumsRewards(holder.poolHoldAmount[poolAddr], holder.beginTimestamp));
                closedPoolAddrs[i]=poolAddr;
            }
        }
        return (rewards,closedPoolAddrs);
    }


    function isAllPoolsClosed(uint256 tokenId) view public returns(bool){
        CoinHolder storage holder=_coinHolders[tokenId];
        for (uint256 i=0;i<holder.pools.length;++i){
            IStakingPool pool=IStakingPool(holder.pools[i]);
            if (!pool.isClosed()){
                return false;
            }
        }
        return true;
    }

    function getTokenHolderAmount(uint256 tokenId,address poolAddr) view public returns(uint256){
        CoinHolder storage holder=_coinHolders[tokenId];
        return holder.poolHoldAmount[poolAddr];
    }

    function getTokenHolder(uint256 tokenId) view public returns(uint256,uint256,uint256,uint256,address [] memory){   
        CoinHolder storage holder=_coinHolders[tokenId];
        uint256 remainingPrincipal = coinHolderRemainingPrincipal(tokenId);

        return (holder.principal,remainingPrincipal,holder.availableMarginAmount,holder.beginTimestamp,holder.pools); 
    }

    function putTokenHolderInPool(address poolAddr,uint256 tokenId,uint256 amount) onlyOperator public {
        CoinHolder storage holder=_coinHolders[tokenId];
        require(holder.availableMarginAmount>=amount,"The token holder amount remaining not enough");
        require(holder.poolHoldAmount[poolAddr]==0,"The holder is not empty");
        holder.availableMarginAmount=holder.availableMarginAmount.sub(amount);
        holder.poolHoldAmount[poolAddr]=amount;
        holder.pools.push(poolAddr);
    }

    function  updatePoolHoldPremiums(uint256 tokenId,address poolAddr,bool value) onlyOperator public {
        CoinHolder storage holder=_coinHolders[tokenId];
        holder.poolHoldPremiums[poolAddr]=value;
    }

    function set(uint256 tokenId,uint256 principal,uint256 availableMarginAmount,uint256 beginTimestamp,bytes8 coinName) onlyOperator public{
        _coinHolders[tokenId]=CoinHolder(principal,availableMarginAmount,beginTimestamp,coinName,new address[](0));
    }

    function initSponsor() external {
        ISponsorWhiteListControl SPONSOR = ISponsorWhiteListControl(address(0x0888000000000000000000000000000000000001));
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }
}


contract StakingPoolToken is ERC721, IUpgradable, ReentrancyGuard
{
    using SafeMath for uint256;
    using CompatibleERC20 for address;
    using SafeERC20 for IERC20;


    StakingTokenHolder _coinHolders;

    uint256 _tokenCount; 

    mapping(address=>string) _pools;
    PriceMetaInfoDB  _priceMetaInfoDb;
    ERC20TokenRegister _tokenRegister;
    bool public flashLoanEnable;


    uint256 public totalFlashLoanCount; 

    uint256 public totalFlashLoanAmount; 

    uint256 public totalFlashLoanPremiums; 

    mapping(address=>uint256) _compensation;
    uint256 _totalCompensation;

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
        _coinHolders = StakingTokenHolder(coinHolder);
        _coinHolders.setOperator(address(this));
    }


    function  updateDependentContractAddress() public override{
        _priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));
        _tokenRegister =ERC20TokenRegister(register.getContract("TKRG"));
    }

    function checkPoolsAmounts(address [] memory pools, uint256 []  memory amounts, uint256 amount,uint256 maxAmount) view public returns(bool){ 
        require(pools.length==amounts.length,"Pools and amounts should be the same length");
        require(pools.length>0,"Pools is empty");
        uint256 totalAmount = 0;
        for (uint256 i=0;i<pools.length;++i){
            address addr=pools[i];
            require(isPool(addr),"all pools should be registered");

            uint256 amt=amounts[i];
            require(amt>0 && amt<=amount,"amt should >0 and <= amount");
            totalAmount = totalAmount.add(amt);
            require(totalAmount <= maxAmount,"No enough money");
        }
        return true;
    }

    function canReleaseTokenHolder(uint256 tokenId) view public returns(bool,address [] memory){
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



    function newTokenHolder(address [] memory pools, uint256 []  memory amounts,bytes8 coinName,uint256 amount) whenNotPaused external  {
        require(amount>0,"amount must > 0");
        uint256 maxAmount = amount.mul(_priceMetaInfoDb.STAKING_TOKEN_MARGIN());
        require(checkPoolsAmounts(pools,amounts,amount,maxAmount),"Check pools failed");
        address token= _tokenRegister.getToken(coinName);

        require(token.allowanceERC20(_msgSender(),address(this))>=amount,"No enough allowance for new token holder");
        token.transferFromERC20(_msgSender(),address(this),amount);
        
        uint256 tokenId=uint256(keccak256(abi.encodePacked(_tokenCount)));
        uint256 beginTimestamp = now;
        _coinHolders.set(tokenId,amount,maxAmount,beginTimestamp,coinName);

        for (uint256 i=0;i<pools.length;++i){
            address addr=pools[i];
            IStakingPool pool=IStakingPool(addr);
            uint256 amt=amounts[i];
            pool.putTokenHolder(tokenId,amt,beginTimestamp);
            _coinHolders.putTokenHolderInPool(addr,tokenId,amt);
        }
        _tokenCount+=1;

        _mint(_msgSender(),tokenId);
        emit NewTokenHolderCreated(tokenId);
    }




    function releaseTokenHolder(uint256 tokenId) nonReentrant whenNotPaused external {
        require(ownerOf(tokenId)==_msgSender(),"The tokenId does not belong to you");
        (bool canRelease,address [] memory poolAddrs)=canReleaseTokenHolder(tokenId);
        require(canRelease,"Can not release the tokenId");
        bytes8 coinName=_coinHolders.getCoinName(tokenId);

        harvestPremiums(tokenId); 

        for (uint256 i=0;i<poolAddrs.length;++i){ 
            address poolAddr=poolAddrs[i];
            if (poolAddr!=address(0)){
                IStakingPool pool=IStakingPool(poolAddrs[i]);
                pool.takeTokenHolder(tokenId);
            }
        }

        uint256 remainingPrincipal=coinHolderRemainingPrincipal(tokenId);
        _burn(tokenId);
        if(remainingPrincipal>0){
            _transferERC20To(_msgSender(),remainingPrincipal,coinName);
        }
        emit TokenHolderReleased(tokenId);
    }


    function _transferERC20To(address to,uint256 amount,bytes8 coinName) private {
        (uint256 [] memory balances,address [] memory tokens)= _tokenRegister.getTransferAmount(address(this),amount,coinName);
        for (uint256 i=0;i<balances.length;++i){
            if (balances[i]>0){
                tokens[i].transferERC20(to,balances[i]); 
            }
        }
    }
 
    function bookkeepingFromPool(uint256 amount) onlyPool public{
        address poolAddr=_msgSender();
        (uint256 sum,,)=_tokenRegister.getAllTokenBalances(address(this));
        uint256 realTotalBalance=sum.sub(_totalCompensation);

        require(realTotalBalance>=amount,"Amount is too large");
        _compensation[poolAddr]=_compensation[poolAddr].add(amount);
        _totalCompensation=_totalCompensation.add(amount);
        
    }

    function claim(address poolAddr) nonReentrant whenNotPaused public{
       address userAddr=_msgSender();
       require(isPool(poolAddr),"unknown staking pool");
       IStakingPool pool=IStakingPool(poolAddr);
       (uint256 amount,uint256 tokenBalance) = pool.queryAndCheckClaimAmount(userAddr);
       require(amount>0,"not claim");
       require(_compensation[poolAddr]>=amount,"amount must < pool's pay amount");
           _compensation[poolAddr]=_compensation[poolAddr].sub(amount);
           _totalCompensation=_totalCompensation.sub(amount);
           _transferERC20To(userAddr,amount,"    ");
           pool.productToken().burn(userAddr,tokenBalance);

    }

    function coinHolderRemainingPrincipal(uint256 tokenId) view public returns(uint256){
        return _coinHolders.coinHolderRemainingPrincipal(tokenId);
    }


    function calcPremiumsRewards(uint256 tokenId) view public returns(uint256 rewards,address [] memory){
        require(_exists(tokenId),"The tokenId does not exist");
        return _coinHolders.calcPremiumsRewards(tokenId);
    }


    function harvestPremiums(uint256 tokenId) whenNotPaused public{
        require(_exists(tokenId),"The tokenId does not exist");
        require(ownerOf(tokenId)==_msgSender(),"The tokenId does not belong to you");
        if (_coinHolders.isAllPoolsClosed(tokenId)){
            (uint256 rewards,address [] memory closedPoolAddrs)=calcPremiumsRewards(tokenId);
            if (rewards>0){
                
                for (uint256 i=0;i<closedPoolAddrs.length;++i){
                    address poolAddr = closedPoolAddrs[i];
                    if (poolAddr!=address(0)){
                        _coinHolders.updatePoolHoldPremiums(tokenId,poolAddr,true);
                    }
                }
                _transferERC20To(_msgSender(),rewards,"    ");
            }
        }
    }

    function getTokenHolder(uint256 tokenId) view public returns(uint256,uint256,uint256,uint256,address [] memory){   
        require(_exists(tokenId),"Token does not exist when put it into pool");
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
