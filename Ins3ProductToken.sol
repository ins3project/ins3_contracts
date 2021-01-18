
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

import "./Ins3ProductTokenBase.sol";
import "./@openzeppelin/token/ERC20/IERC20.sol" ;
import "./CompatibleERC20.sol";


contract Ins3ProductToken is Ins3ProductTokenBase
{
    using CompatibleERC20 for address;

    mapping(address=>uint256) public channelPremiumsRewards; 


	constructor(string memory categoryValue,string memory subCategoryValue,
		string memory tokenNameValue,string memory tokenSymbolValue,
		uint256 paidValue,uint256 expireTimestampValue)
		Ins3ProductTokenBase(categoryValue,subCategoryValue,tokenNameValue, tokenSymbolValue,paidValue,expireTimestampValue) public 
	{
	}

    function tokenERC20(bytes8 coinName) view public returns(address,uint256){
        address token = _tokenRegister.getToken(coinName);
        return (token,token.decimalsERC20());
    }

	function buy(bytes8 coinName,address priceNodePublicKey, uint256 quantity, uint256 price, 
                uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) whenNotPaused public returns(bool) {
        address erc20Token=_tokenRegister.getToken(coinName);
        uint256 amount = erc20Token.getCleanAmount(price.mul(quantity));
        uint256 allowance=erc20Token.allowanceERC20(_msgSender(),address(this));
        
        require(allowance>=amount,"allowance is not enough for calling buy()");
        if (!_checkBuyAvailable(priceNodePublicKey,quantity,price,expiresAt,_v,_r,_s)){
            return false;
        }
        erc20Token.transferFromERC20(_msgSender(),address(this),amount); 

        return _buy(amount,priceNodePublicKey,quantity,price,expiresAt,_v,_r,_s);
    }

    function buyByChannel(uint256 channelId,bytes8 coinName,address priceNodePublicKey, uint256 quantity, uint256 price, 
                uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) whenNotPaused external returns(bool) {
        address channelAddress=_priceMetaInfoDb.getCoverChannelAddress(channelId);
        require(channelAddress!=address(0),"No such channelId");
        bool done=buy(coinName,priceNodePublicKey,quantity,price,expiresAt,_v,_r,_s); 
        require(done,"Failed to buy convers");

        address erc20Token=_tokenRegister.getToken(coinName);
        uint256 amount = erc20Token.getCleanAmount(price.mul(quantity));
        uint256 channelAmount=amount.mul(_priceMetaInfoDb.CHANNEL_PREMIUMS_PERCENT()).div(1000);
        require(amount > channelAmount,"channel premiums percent error");
        if (channelAmount>0){
            channelPremiumsRewards[channelAddress]=channelPremiumsRewards[channelAddress].add(channelAmount);
            erc20Token.transferERC20(channelAddress,channelAmount); 
            totalPremiums=totalPremiums.sub(channelAmount); 
            statusChanged();
        }
        return done;
    }

	function withdraw(address priceNodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) whenNotPaused external returns(bool){
		uint256 returnAmount=_withdraw(priceNodePublicKey,quantity,price,expiresAt,_v,_r,_s);
		if (returnAmount==0){
			return false;
		}
        (uint256 [] memory balances, address [] memory tokenAddrs) = _tokenRegister.getTransferAmount(address(this),returnAmount,"    ");
        for (uint256 i=0;i<balances.length;++i){
            uint256 balance=balances[i];
            address token=tokenAddrs[i];
            if (balance>0){
                token.transferERC20(_msgSender(),balance);
            }
        }
		return true;
	}

	function close() public onlyOwner {
		require(isValid,"The product has been closed");
		isValid = false;

	}

    function approvePaid() public onlyPool {
        isValid = false;
        needPay = true;
        address [] memory tokenAddrs=_tokenRegister.getAllTokens();
        address stakingPoolAddress = address(stakingPool);
        for (uint256 i=0;i<tokenAddrs.length;++i){  
            address token=tokenAddrs[i];
            uint256 balance=token.balanceOfERC20(address(this));
            if(balance>0){
                token.transferERC20(stakingPoolAddress,balance);
            }
        }
    }

    function calcDistributePremiums() public view returns(uint256,uint256){
        uint256 toOwnerAmount = totalPremiums.mul(_priceMetaInfoDb.PREMIUMS_SHARE_PERCENT()).div(1000);
        uint256 toPoolTokenAmount = totalPremiums.sub(toOwnerAmount);
        return (toOwnerAmount,toPoolTokenAmount);
    }

    function _transferERC20To(address to,uint256 amount,bytes8 coinName) private {
        (uint256 [] memory balances,address [] memory tokens)= _tokenRegister.getTransferAmount(address(this),amount,coinName);
        for (uint256 i=0;i<balances.length;++i){
            if (balances[i]>0){
                tokens[i].transferERC20(to,balances[i]); 
            }
        }
    }

    function rejectPaid() public onlyPool {

        isValid = false;
        address adminAddress = admin();
        (uint256 toOwnerAmount, uint256 toPoolTokenAmount) = calcDistributePremiums();
        if(toPoolTokenAmount>0){
            _transferERC20To(stakingPoolToken, toPoolTokenAmount, "    ");
        }
        if(toOwnerAmount>0){
            _transferERC20To(adminAddress, toOwnerAmount, "    ");
        }
    }

    

}