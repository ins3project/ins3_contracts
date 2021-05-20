
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


interface IIns3ProductToken{
    function totalSellQuantity() external view returns(uint256);
    function paid() external view returns(uint256);
    function expireTimestamp() external view returns(uint256);
    function closureTimestamp() external view returns(uint256);
    function totalPremiums() external view returns(uint256);
    function needPay() external view returns(bool);
    function isValid() external view returns(bool);
    function balanceOf(address account) external view returns (uint256);
    function burn(address account, uint256 amount) external;
    function calcDistributePremiums() external view returns(uint256,uint256);
    function approvePaid() external;
    function rejectPaid() external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}


interface IStakingPool 
{
    function putTokenHolder(uint256 tokenId,uint256 amount,uint256 timestamp) external;
    function calcPremiumsRewards(uint256 stakingAmount, uint256 timestamp) external view returns(uint256);
    function isClosed() external view returns(bool);
    function isNormalClosed() external view returns(bool);

    function totalStakingAmount() external view returns(uint256); 

    function totalNeedPayFromStaking() external view returns(uint256); 

    function totalRealPayFromStaking() external view returns(uint256) ; 

    function payAmount() external view returns(uint256); 

    function productTokenRemainingAmount() external view returns(uint256);
    function productTokenExpireTimestamp() external view returns(uint256);
    function calculateCapacity() external view returns(uint256);
    function takeTokenHolder(uint256 tokenId) external;
    function productToken() external view returns(IIns3ProductToken);
    function queryAndCheckClaimAmount(address userAccount) view external returns(uint256,uint256/*token balance*/);
}

interface IClaimPool is IStakingPool
{
    function tokenAddress() external view returns(address);
    function returnRemainingAToken(address account) external;
    function getAToken(uint256 userPayAmount, address account) external;
    function needPayFlag() external view returns(bool); 
    function totalClaimProductQuantity() external view returns(uint256);

    function stakingWeight() external view returns(uint256);
    function stakingLeverageWeight() external view returns(uint256);
}

interface IStakingPoolToken{
    function putTokenHolderInPool(uint256 tokenId,uint256 amount) external;
    function getTokenHolderAmount(uint256 tokenId,address poolAddr) view external returns(uint256);
    function getTokenHolder(uint256 tokenId) view external returns(uint256,uint256,uint256,uint256,address [] memory);
    function coinHolderRemainingPrincipal(uint256 tokenId) view external returns(uint256);
    function bookkeepingFromPool(uint256 amount) external;
    function isTokenExist(uint256 tokenId) view external returns(bool);
}