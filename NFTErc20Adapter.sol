
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

import "./@openzeppelin/math/SafeMath.sol";
import "./@openzeppelin/math/Math.sol";
import "./@openzeppelin/token/ERC20/ERC20Burnable.sol";
import "./@openzeppelin/token/ERC721/ERC721.sol";
import "./@openzeppelin/utils/EnumerableMap.sol";

import "./IStakingPool.sol";
import "./IUpgradable.sol";

interface NFTValuable{
    function getTokenHolder(uint256 tokenId) view external returns(uint256,uint256,uint256,uint256,address [] memory);
}

interface NFTValuableV2 is NFTValuable{
    function capitalTokenAddress(uint256 tokenId) view external returns(address);
}




contract IERC20Token is ERC20Burnable, IUpgradable{

    mapping(address=>bool) public minerMap;

    mapping(address=>bool) _allowedAddress;

    constructor(string memory name, string memory symbol, address ownable) public
        ERC20(name,symbol) IUpgradable()
    {
        setOwnable(ownable);
    }

    function updateDependentContractAddress() public virtual override{

    }

    modifier checkAllowed(address sender,address recipient) {
        require(_allowedAddress[sender]==true || _allowedAddress[recipient]==true,"Do not transfer at will");
        _;
    }

    function addAllowedRecipient(address recipient) public onlyOwner{
        _allowedAddress[recipient]=true;
    }

    function addMiners(address[] memory miners) public onlyOwner{
        for(uint256 i=0; i<miners.length; i++) {
            minerMap[miners[i]] = true;
            _allowedAddress[miners[i]]=true;
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

    function mint(address account,uint256 amount) external onlyMiner {
        _mint(account, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) checkAllowed(sender,recipient) internal  override {
        super._transfer(sender,recipient,amount);
    }


}

contract NFTErc20Adapter is IUpgradable{
    using SafeMath for uint256;

    using EnumerableMap for EnumerableMap.UintToUintMap;

    mapping(string/*tokenName*/=>mapping(uint256/*expireTimestamp*/=>address)) public iERC20Tokens;
    mapping(address/* user */ => mapping(address /* NFTContractAddress */=> EnumerableMap.UintToUintMap/*tokenId=>iTokenAmount*/))   nftKeys;

    mapping (address=>string/* tokenName */) public validNFTContracts;
    address [] public NFTContractsList;

    uint256 public weightNumeratorFactor;
    uint256 public weightDenominatorFactor;

    constructor(address ownable) IUpgradable() public {
        weightNumeratorFactor=9;
        weightDenominatorFactor=8;
        setOwnable(ownable);
    }

    function updateDependentContractAddress() public virtual override{

    } 

    function setWeightFactor(uint256 numerator,uint256 denominator) public onlyOwner{
        weightNumeratorFactor=numerator;
        weightDenominatorFactor=denominator;
    }

    function calcWeightFactor(uint256 n,uint256 weightRadix) view public returns(uint256){
        return weightRadix.mul(weightNumeratorFactor).div(n.add(weightDenominatorFactor));
    }

    function registerIERC20Token(address iERC20TokenAddress,string memory tokenName,uint256 expireTime) onlyOwner public{
        require(IERC20Token(iERC20TokenAddress).minerMap(address(this)),"The iToken should add this as minter");
        require(iERC20Tokens[tokenName][expireTime]==address(0),"The iToken exists");
        iERC20Tokens[tokenName][expireTime]=iERC20TokenAddress;
    }

    function getIERC20Token(address NFTContract,uint256 tokenId) view public returns(address){
        string memory capitalTokenName=getNFTCapitalTokenName(NFTContract,tokenId);
        require(!checkString(capitalTokenName,""),"Invalid NFT contract");

        uint256 expireTimestamp=getNFTExpireTimestamp(NFTContract,tokenId);
        require(expireTimestamp>0,"Invalid NFT contract expire time");
        return iERC20Tokens[capitalTokenName][expireTimestamp];
    }

    function registerNFTContract(address NFTContract,string memory capitalTokenName) onlyOwner public {
        if (checkString(validNFTContracts[NFTContract],"")){
            NFTContractsList.push(NFTContract);
        }
        validNFTContracts[NFTContract]=capitalTokenName;
    }

    function checkString(string memory str1,string memory str2) pure public returns(bool){
        return (keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2)));
    }

    function getNFTCapitalTokenName(address NFTContract,uint256 tokenId) view public returns(string memory){
        string memory capitalTokenName=validNFTContracts[NFTContract];
        if (checkString(capitalTokenName,"*")){
            ERC20 capToken=ERC20(NFTValuableV2(NFTContract).capitalTokenAddress(tokenId));
            capitalTokenName=capToken.symbol();
        }
        return capitalTokenName;
    }

    function getNFTExpireTimestamp(address NFTContract,uint256 tokenId) view public returns(uint256){
        NFTValuable nft=NFTValuable(NFTContract);
        (,,,,address [] memory pools)=nft.getTokenHolder(tokenId);
        uint256 recentTime=0;
        for( uint256 i=0;i<pools.length;++i){
            uint256 ts=IStakingPool(pools[i]).productToken().expireTimestamp();
            recentTime = recentTime==0?ts:Math.min(recentTime,ts);
        }
        return recentTime;
    }

    function getNFTValueWeight(address NFTContract,uint256 tokenId) view public returns(uint256){

        NFTValuable nft=NFTValuable(NFTContract);
        (,,,,address [] memory pools)=nft.getTokenHolder(tokenId);

        string memory capitalTokenName=validNFTContracts[NFTContract];
        bool isV2=checkString(capitalTokenName,"*");
        if (isV2){
            uint256 weightSum=0;
            uint256 maxWeight=0;
            for( uint256 i=0;i<pools.length;++i){
                uint256 weight=IClaimPool(pools[i]).stakingWeight(); //based on 10000
                weightSum=weightSum.add(weight);
                maxWeight=Math.max(weight,maxWeight);
            }
            return Math.max(calcWeightFactor(pools.length,weightSum),maxWeight);  //=max(9/(n+8)*sum,max(weight))
        }else{
            return calcWeightFactor(pools.length,pools.length.mul(10000));  //=9/(n+8)*1
        }

    }


    function NFTOfOwnerByIndex(address owner, address NFTContract,uint256 index) view public returns (uint256) {
        (uint256 tokenId,)=nftKeys[owner][NFTContract].at(index);
        return tokenId;
    }
    function NFTBalanceOf(address owner, address NFTContract) view public returns (uint256) {
        return nftKeys[owner][NFTContract].length();
    }

    function getIERC20BalanceOf(address NFTContract,uint256 tokenId) view public returns(uint256){
        NFTValuable nft=NFTValuable(NFTContract);
        (uint256 value,,,,)=nft.getTokenHolder(tokenId);

        uint256 weight=getNFTValueWeight(NFTContract,tokenId);
        assert(weight<=10000);
        return value.mul(weight).div(10000) ;
    }


    function pledgeNFT(address NFTContract,uint256 tokenId) public {
        require(ERC721(NFTContract).ownerOf(tokenId)==_msgSender(),"Not owner");

        address iTokenAddress = getIERC20Token(NFTContract, tokenId);
        IERC20Token iToken=IERC20Token(iTokenAddress);
        require(address(iToken)!=address(0),"Unknown capital token name");

        uint256 value=getIERC20BalanceOf(NFTContract,tokenId);
        require(value>0,"NFT capital value is 0");
        ERC721(NFTContract).transferFrom(_msgSender(),address(this),tokenId);
        iToken.mint(_msgSender(),value);

        nftKeys[_msgSender()][NFTContract].set(tokenId,value);

    }

    function isNFTOwner(address NFTContract,uint256 tokenId,address owner) view public returns(bool){
        return nftKeys[owner][NFTContract].contains(tokenId);
    }

    function redeemNFT(address NFTContract,uint256 tokenId) public {
        require(isNFTOwner(NFTContract,tokenId,_msgSender()),"Not owner");

        string memory capitalTokenName=getNFTCapitalTokenName(NFTContract,tokenId);
        require(!checkString(capitalTokenName,""),"Invalid NFT contract");

        uint256 expireTimestamp=getNFTExpireTimestamp(NFTContract,tokenId);
        require(expireTimestamp>0,"Invalid NFT contract expire time");

        IERC20Token iToken=IERC20Token(iERC20Tokens[capitalTokenName][expireTimestamp]);
        require(address(iToken)!=address(0),"Unknown capital token name");

        uint256 iTokenAmount=nftKeys[_msgSender()][NFTContract].get(tokenId);

        iToken.transferFrom(_msgSender(),address(this),iTokenAmount);
        iToken.burn(iTokenAmount);
        ERC721(NFTContract).transferFrom(address(this),_msgSender(),tokenId);
        nftKeys[_msgSender()][NFTContract].remove(tokenId);
    }

}
