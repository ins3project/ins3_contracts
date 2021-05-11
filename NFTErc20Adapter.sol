
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
import "./IUpgradable.sol";
import "./@openzeppelin/token/ERC20/ERC20Burnable.sol";
import "./@openzeppelin/token/ERC721/ERC721.sol";


interface NFTValuable{
    function getTokenHolder(uint256 tokenId) view external returns(uint256,uint256,uint256,uint256,address [] memory);
}

interface NFTValuableV2 is NFTValuable{
    function capitalToken(uint256 tokenId) view external returns(address);
}


struct NFTKey
{
    address NFTContractAddress;
    uint256 tokenId;
}


contract IERC20Token is ERC20Burnable, IUpgradable{

    mapping(address=>bool) public minerMap;

    constructor(string memory name,string memory symbol) public
        ERC20(name,symbol)
    {

    }

    function  updateDependentContractAddress() public virtual override{

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

    function mint(address account,uint256 amount) external onlyMiner {
        _mint(account, amount);
    }

}

contract NFTErc20Adapter is IUpgradable{
    using SafeMath for uint256;

    mapping(string=>address) public iERC20Tokens;
    mapping(address/* user */=>NFTKey[])  public nftKeys;

    mapping (address=>string/* tokenName */) public validNFTContracts;

    constructor() public{
    }

    function  updateDependentContractAddress() public virtual override{

    } 

    function registerIERC20Token(address iERC20TokenAddress,string memory tokenName) onlyOwner public{
        require(iERC20Tokens[tokenName]==address(0),"The iERC20token exists");
        iERC20Tokens[tokenName]=iERC20TokenAddress;
        address[] memory miners = new address[](1);
        miners[0] = address(this);
        IERC20Token(iERC20TokenAddress).addMiners(miners);
    }


    function registerNFTContract(address NFTContract,string memory capitalTokenName) onlyOwner public {
        validNFTContracts[NFTContract]=capitalTokenName;
    }

    function checkString(string memory str1,string memory str2) pure public returns(bool){
        return (keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2)));
    }

    function getNFTCapitalTokenName(address NFTContract,uint256 tokenId) view public returns(string memory){
        string memory capitalTokenName=validNFTContracts[NFTContract];
        if (checkString(capitalTokenName,"*")){
            ERC20 capToken=ERC20(NFTValuableV2(NFTContract).capitalToken(tokenId));
            capitalTokenName=capToken.symbol();
        }
        return capitalTokenName;
    }

    function pledgeNFT(address NFTContract,uint256 tokenId) public {
        require(ERC721(NFTContract).ownerOf(tokenId)==_msgSender(),"Sender is not owner");
        string memory capitalTokenName=getNFTCapitalTokenName(NFTContract,tokenId);
        require(!checkString(capitalTokenName,""),"Invalid NFT contract");
        IERC20Token iToken=IERC20Token(iERC20Tokens[capitalTokenName]);
        require(address(iToken)!=address(0),"Unknown capital token name");
        NFTValuable nft=NFTValuable(NFTContract);
        ERC721(NFTContract).transferFrom(_msgSender(),address(this),tokenId);
        (uint256 value,,,,)=nft.getTokenHolder(tokenId);
        iToken.mint(_msgSender(),value);
        nftKeys[_msgSender()].push(NFTKey(NFTContract,tokenId));
    }

    function isNFTOwner(address NFTContract,uint256 tokenId,address owner) view public returns(bool){
        NFTKey[] storage keys=nftKeys[owner];
        for (uint256 i=0;i<keys.length;++i){
            NFTKey storage key=keys[i];
            if (key.NFTContractAddress==NFTContract && key.tokenId==tokenId){
                return true;
            }
        }
        return false;
    }

    function redeemNFT(address NFTContract,uint256 tokenId) public {
        require(isNFTOwner(NFTContract,tokenId,_msgSender()));

        string memory capitalTokenName=getNFTCapitalTokenName(NFTContract,tokenId);
        require(!checkString(capitalTokenName,""),"Invalid NFT contract");

        NFTValuable nft=NFTValuable(NFTContract);
        (uint256 iTokenAmount,,,,)=nft.getTokenHolder(tokenId);

        IERC20Token iToken=IERC20Token(iERC20Tokens[capitalTokenName]);
        require(address(iToken)!=address(0),"Unknown capital token name");
        require(iToken.balanceOf(_msgSender())>=iTokenAmount,"Not enought iToken");
        iToken.transferFrom(_msgSender(),address(this),iTokenAmount);
        iToken.burn(iTokenAmount);
        ERC721(NFTContract).transferFrom(address(this),_msgSender(),tokenId);
    }

}
