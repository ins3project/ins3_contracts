
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

import "./IStakingPool.sol";
import "./PriceMetaInfoDB.sol";
import "./IUpgradable.sol";
import "./@openzeppelin/math/SafeMath.sol";
import "./@openzeppelin/math/Math.sol";
import "./@openzeppelin/utils/ReentrancyGuard.sol";
import "./ERC20TokenRegister.sol";
import "./CompatibleERC20.sol";

interface IStakingPoolToken{
    function putTokenHolderInPool(uint256 tokenId,uint256 amount) external;
    function getTokenHolderAmount(uint256 tokenId,address poolAddr) view external returns(uint256);
    function getTokenHolder(uint256 tokenId) view external returns(uint256,uint256,uint256,uint256,address [] memory);
    function coinHolderRemainingPrincipal(uint256 tokenId) view external returns(uint256);
    function bookkeepingFromPool(uint256 amount) external;
    function isTokenExist(uint256 tokenId) view external returns(bool);
}

contract StakingPool is IStakingPool, IUpgradable, ReentrancyGuard
{
    using SafeMath for uint256;
    using CompatibleERC20 for address;

    uint256 [] public tokenHolderIds;  


    mapping(uint256/*tokenId*/=>uint256) _timestamps; 
    IStakingPoolToken public stakingPoolToken;
    IIns3ProductToken public override productToken;
    ERC20TokenRegister _tokenRegister;
    PriceMetaInfoDB  _priceMetaInfoDb;

    uint256 public stakingAmountLimit; 

    uint256 public minStakingAmount; 

	uint256 public capacityLimitPercent; 

    uint256 private _totalStakingAmount; 

    uint256 public _totalStakingTimeAmount; 


    uint256 private _totalNeedPayFromStaking; 

    uint256 private _totalRealPayFromStaking; 

    uint256 private _payAmount; 
    bool public _isClosed;

    bool public claimEnable; 

    uint256 _totalPremiumsAfterClose;

    constructor(uint256 stakingAmountLimit_, uint256 minStakingAmount_, uint256 capacityLimitPercent_) public{
        stakingAmountLimit = stakingAmountLimit_;
        minStakingAmount = minStakingAmount_;
        capacityLimitPercent = capacityLimitPercent_;


    }




    function calculateCapacity() view public override returns(uint256) {
        uint256 activeCovers = productToken.totalSellQuantity().mul(productToken.paid());
        uint256 maxMCRCapacity = _totalStakingAmount.mul(capacityLimitPercent).div(1000);
        uint256 maxCapacity = maxMCRCapacity < stakingAmountLimit ? maxMCRCapacity : stakingAmountLimit;
        uint256 availableCapacity = activeCovers >= maxCapacity ? 0 : maxCapacity.sub(activeCovers);
        return availableCapacity;
    }

    function productTokenRemainingAmount() view public override returns(uint256){ 
        require(address(productToken)!=address(0),"The productToken should not be 0");
        return calculateCapacity();
    }

    function tokenHolderIdLength() view public returns(uint256){
        return tokenHolderIds.length;
    }

    function productTokenExpireTimestamp() view public override returns(uint256){
        require(address(productToken)!=address(0),"The productToken should not be 0");
        return productToken.expireTimestamp();
    }

    function setProductToken(address tokenAddress) onlyOwner public returns(bool){
		require(address(productToken) == address(0),"The setProductToken() can only be called once");
		productToken = IIns3ProductToken(tokenAddress);
		return true;
	}

    modifier onlyPoolToken(){
        require(address(stakingPoolToken)==address(_msgSender()));
        _;
    }

    function putTokenHolder(uint256 tokenId,uint256 amount,uint256 timestamp) onlyPoolToken public override {
        require(amount>=minStakingAmount,"amount should > minStakingAmount");
        require(remainingStakingAmount()>=amount,"putTokenHolder - remainingStakingAmount not enough");
        require(_timestamps[tokenId]==0,"putTokenHolder - The tokenId already exists");
        require(timestamp<productToken.closureTimestamp(),"Clouser period, can not staking");
        _totalStakingAmount = _totalStakingAmount.add(amount);
        uint256 period = productToken.expireTimestamp().sub(timestamp);
        _totalStakingTimeAmount = _totalStakingTimeAmount.add(amount.mul(period).mul(period));
        tokenHolderIds.push(tokenId);
        _timestamps[tokenId]=timestamp;

    }

    function takeTokenHolder(uint256 tokenId) onlyPoolToken public override{ 
        require(!_isClosed,"pool has colsed");
        require(_timestamps[tokenId]!=0,"The tokenId does not exist");
        uint256 amount=stakingPoolToken.getTokenHolderAmount(tokenId,address(this));
        uint256 period = productToken.expireTimestamp().sub(_timestamps[tokenId]);
        delete _timestamps[tokenId];
        _totalStakingAmount = _totalStakingAmount.sub(amount);
        _totalStakingTimeAmount = _totalStakingTimeAmount.sub(amount.mul(period).mul(period));
    }


    function remainingStakingAmount() view public returns(uint256){
        return stakingAmountLimit.sub(_totalStakingAmount);
    }

    function  updateDependentContractAddress() public override{
        _priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));
        stakingPoolToken=IStakingPoolToken(register.getContract("SKPT"));
        require(address(stakingPoolToken)!=address(0),"updateDependentContractAddress - staking pool token does not init");
        _tokenRegister=ERC20TokenRegister(register.getContract("TKRG"));
    }

    function calcPremiumsRewards(uint256 stakingAmount, uint256 beginTimestamp) view public override returns(uint256){
        (, uint256 toPoolTokenPremiums) = productToken.calcDistributePremiums();
        uint256 timePeriod = productToken.expireTimestamp().sub(beginTimestamp);
        if (_totalStakingTimeAmount == 0) {
            return 0;
        }
        return toPoolTokenPremiums.mul(stakingAmount).mul(timePeriod).mul(timePeriod).div(_totalStakingTimeAmount); 
    }

    function isClosed() view public override returns(bool){
        return _isClosed;
    }

    function isNormalClosed() view public override returns(bool){
        return _isClosed && !productToken.needPay();
    }

    function totalStakingAmount() view public override returns(uint256){
        return _totalStakingAmount;
    }



    function totalNeedPayFromStaking() view public override returns(uint256){
        return _totalNeedPayFromStaking;
    }

    function totalRealPayFromStaking() view public override returns(uint256){
        return _totalRealPayFromStaking;
    }

    function payAmount() view public override returns(uint256){
        return _payAmount;
    }

    function canStake() view public returns(bool){
        return now<productToken.closureTimestamp(); 
    }



    function _transferERC20To(address to,uint256 amount,bytes8 coinName) private {
        (uint256 [] memory balances,address [] memory tokens)= _tokenRegister.getTransferAmount(address(this),amount,coinName);
        for (uint256 i=0;i<balances.length;++i){
            if (balances[i]>0){
                tokens[i].transferERC20(to,balances[i]);
            }
        }
    }

    function close(bool needPay, uint256 totalRealPayFromStakingToken) public onlyOwner {
        require(!_isClosed,"Staking pool has been closed");
        _isClosed = true;
        if(needPay){
            productToken.approvePaid();
        }else{
            productToken.rejectPaid();
        }
        uint256 totalSellQuantity = productToken.totalSellQuantity();

        if(needPay && totalSellQuantity>0) { 
            uint256 totalPaidAmount = totalSellQuantity.mul(productToken.paid());

            (uint256 totalPremiums,,) = _tokenRegister.getAllTokenBalances(address(this));

            uint256 totalNeedPayAmount = totalPaidAmount.sub(totalPremiums);
            require(totalRealPayFromStakingToken <= totalNeedPayAmount,"please check pay amount");


            _totalNeedPayFromStaking = totalNeedPayAmount;
            _totalRealPayFromStaking = totalRealPayFromStakingToken;
            
            if(_totalRealPayFromStaking>0){
                _transferERC20To(address(stakingPoolToken),totalPremiums,"    ");
                _totalPremiumsAfterClose=totalPremiums;
                stakingPoolToken.bookkeepingFromPool(_totalRealPayFromStaking.add(_totalPremiumsAfterClose));
            }

            updatePayAmount();

        }
    }

    function calcPayAmountFromStaking(uint256 totalNeedPayAmount, uint256 beginIndex, uint256 endIndex) public view returns(uint256){
        require(beginIndex <= endIndex,"index error");
        require(endIndex < tokenHolderIds.length,"end index out of range");
        uint256 totalRealPayAmount = 0;

        for(uint256 i=beginIndex; i <= endIndex; ++i) {
            uint256 tokenId=tokenHolderIds[i];
            if (!stakingPoolToken.isTokenExist(tokenId)){
                continue;
            }
            uint256 stakingAmount = stakingPoolToken.getTokenHolderAmount(tokenId,address(this));
            uint256 userPayAmount = stakingAmount.mul(totalNeedPayAmount).div(_totalStakingAmount);
            if(userPayAmount>0){
                uint256 remainingPrincipal = stakingPoolToken.coinHolderRemainingPrincipal(tokenId);
                uint256 userRealPayAmount = Math.min(userPayAmount, remainingPrincipal);
                if(userRealPayAmount>0){
                    totalRealPayAmount = totalRealPayAmount.add(userRealPayAmount);
                }
            }
        }
        return totalRealPayAmount;
    }

    function updatePayAmount() public onlyOwner {
        require(_isClosed,"Pool must be closed");
        require(!claimEnable,"claim already enable");
        (uint256 totalAmount,,) = _tokenRegister.getAllTokenBalances(address(this));
        uint256 totalSellQuantity = productToken.totalSellQuantity();
        if(totalSellQuantity>0) {
            _payAmount = totalAmount.add(_totalRealPayFromStaking).add(_totalPremiumsAfterClose).div(totalSellQuantity);
        }else {
            _payAmount = 0;
        }

        if (totalAmount>0){
            _totalPremiumsAfterClose=_totalPremiumsAfterClose.add(totalAmount);
            _transferERC20To(address(stakingPoolToken),totalAmount,"    ");
            stakingPoolToken.bookkeepingFromPool(totalAmount);
        }
    }

    function setClaimEnable() public onlyOwner{
        require(_isClosed,"Pool must be closed");
        claimEnable = true;
    }

    function queryAndCheckClaimAmount(address userAccount) view external override returns(uint256,uint256/*token balance*/){
        require(claimEnable,"claim not enable");
        require(_payAmount>0,"no money for claim");
        uint256 productTokenQuantity = productToken.balanceOf(userAccount);
        require(productTokenQuantity>0,"user need have product token");
        
        return (productTokenQuantity.mul(_payAmount),productTokenQuantity);
    }







}