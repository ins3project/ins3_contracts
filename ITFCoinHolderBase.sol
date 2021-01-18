
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

import "./IUpgradable.sol";
import "./PriceMetaInfoDB.sol";
import "./ITFCoin.sol";
import "./@openzeppelin/math/SafeMath.sol";
import "./@openzeppelin/token/ERC20/IERC20.sol";
import "./@openzeppelin/math/Math.sol";


abstract contract ITFCoinHolderBase is IUpgradable
{
    using SafeMath for uint256;

    mapping(address=>bool) public minerMap;

    address public itfCoinAddress;  

    address[4] itfReleaseAccounts;
    uint256[4] itfReleaseAccountMultipliers;
    uint256 itfReleaseDivisor;

    constructor(address itfCoinAddr) internal
    {
        itfCoinAddress = itfCoinAddr;
    }

    function balanceOf(address account) external view returns (uint256){
        return IERC20(itfCoinAddress).balanceOf(account);
    }

    function reward(address account,uint256 amount,bytes memory userData,bytes memory operatorData) external virtual;

    function updateDependentContractAddress() public virtual override {
        PriceMetaInfoDB _priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));
        itfReleaseAccounts =            _priceMetaInfoDb.getITFReleaseAccountArray();
        itfReleaseAccountMultipliers =  _priceMetaInfoDb.getITFReleaseAccountMultiplierArray();
        itfReleaseDivisor =     _priceMetaInfoDb.getITFReleaseDivisor();
    }

    function addMiners(address[] memory miners) public onlyOwner{
        for(uint256 i=0; i<miners.length; i++) {
            minerMap[miners[i]] = true;
        }
    }

    function removeMiners(address[] memory miners) public onlyOwner{
        for(uint256 i=0; i<miners.length; i++){
            minerMap[miners[i]] = false;
        }
    }

    modifier onlyMiner {
        require(minerMap[_msgSender()]==true,"not miner");
        _;
    }
}

contract ITFCoinHolder is ITFCoinHolderBase
{
    constructor(address itfCoinAddr) ITFCoinHolderBase(itfCoinAddr) public
    {

    }

    function reward(address account,uint256 amount,bytes memory userData,bytes memory operatorData) external virtual override onlyMiner whenNotPaused {
        ITFCoin itfCoin = ITFCoin(itfCoinAddress);
        uint256 userAmount=Math.min(itfCoin.maxSupply().sub(itfCoin.totalSupply()),amount);
        if (userAmount>0){
            itfCoin.mint(account, userAmount, userData, operatorData);
        }
        for (uint256 i = 0; i < itfReleaseAccounts.length; i++) {  
            if(itfReleaseAccounts[i] != address(0)){
                uint256 accountReleaseAmount = amount.mul(itfReleaseAccountMultipliers[i]).div(itfReleaseDivisor);
                uint256 arAmount=Math.min(itfCoin.maxSupply().sub(itfCoin.totalSupply()),accountReleaseAmount);
                if (arAmount>0){
                    itfCoin.mint(itfReleaseAccounts[i], arAmount, userData, operatorData);
                }
            }
        }
    }
}

contract CITFCoinHolder is ITFCoinHolderBase
{
    constructor(address cITFCoinAddr) ITFCoinHolderBase(cITFCoinAddr) public
    {
        
    }

    function reward(address account,uint256 amount,bytes memory /*userData*/,bytes memory /*operatorData*/) external virtual override onlyMiner whenNotPaused {

            IERC20  itfCoin = IERC20(itfCoinAddress);
            uint256 userAmount=Math.min(itfCoin.balanceOf(address(this)),amount);
            if (userAmount>0){
                itfCoin.transfer(account, userAmount);
            }
            for (uint256 i = 0; i < itfReleaseAccounts.length; i++) {
                if(itfReleaseAccounts[i] != address(0)){
                    uint256 accountReleaseAmount = amount.mul(itfReleaseAccountMultipliers[i]).div(itfReleaseDivisor);
                    uint256 arAmount=Math.min(itfCoin.balanceOf(address(this)),accountReleaseAmount);
                    if (arAmount>0){
                        itfCoin.transfer(itfReleaseAccounts[i], arAmount);
                    }
                }
            }

    }
}

