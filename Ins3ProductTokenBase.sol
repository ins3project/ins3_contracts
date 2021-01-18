
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

import "./@openzeppelin/token/ERC20/ERC20.sol" ;

import "./IStakingPool.sol";
import "./IUpgradable.sol";
import "./ERC20TokenRegister.sol";
import "./PriceMetaInfoDB.sol";

abstract contract Ins3ProductTokenBase is ERC20,IUpgradable
{
	string public category; 
	string public subCategory; 

	uint256 public expireTimestamp; 

	function closureTimestamp() view public returns(uint256){ 
		return expireTimestamp-_priceMetaInfoDb.ORACLE_VALID_PERIOD();
	}
	bool public isValid; 

	bool public needPay; 

	uint256 public paid; 

	uint256 public totalSellQuantity; 
	
	uint256 public totalPremiums; 

	IStakingPool public stakingPool;
	address public stakingPoolToken;
    ERC20TokenRegister internal _tokenRegister;

	PriceMetaInfoDB  _priceMetaInfoDb;

	event EventStatusChanged(uint256 totalSellQuantity,uint256 totalPremiums);
	event EventBuy(address indexed user,uint256 quantity,uint256 amount);

	constructor(string memory categoryValue,string memory subCategoryValue,
		string memory tokenNameValue,string memory tokenSymbolValue,
		uint256 paidValue,uint256 expireTimestampValue)
		ERC20(tokenNameValue, tokenSymbolValue) IUpgradable() internal 
    {
		_setupDecimals(0);
		category = categoryValue;
		subCategory = subCategoryValue;

		expireTimestamp = expireTimestampValue;
		isValid = true;


		paid = paidValue;

    }


    function updateDependentContractAddress() public virtual override {
		stakingPoolToken = register.getContract("SKPT");
		address tokenRegisterAddr=register.getContract("TKRG");
        assert(tokenRegisterAddr!=address(0));
        _tokenRegister=ERC20TokenRegister(tokenRegisterAddr);
		_priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));
    } 

	function setStakingPool(address poolAddress) public onlyOwner returns(bool){
		require(address(stakingPool) == address(0),"The setStakingPool() can only be called once");
		stakingPool = IStakingPool(poolAddress);
		return true;
	}

    modifier onlyPool(){
        require(_msgSender()==address(stakingPool) || _msgSender()==stakingPoolToken);
        _;
    }

	function burn(address account, uint256 amount) public onlyPool {
		_burn(account,amount);
	}

	function statusChanged() internal {
		emit EventStatusChanged(totalSellQuantity,totalPremiums);
	}

	function remaining() public view returns(uint256) { 
		return stakingPool.calculateCapacity().div(paid);
	}

	function verifyPrice(address priceNodePublicKey, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) public view returns(bool){
		require(address(_priceMetaInfoDb)!=address(0),"priceMetaInfoDb not set");
		require(_priceMetaInfoDb.PRICE_NODE_PUBLIC_KEY()==priceNodePublicKey,"The price node public key is not valid");

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                priceNodePublicKey,
                price,
                expiresAt
            )
        );
		return _priceMetaInfoDb.verifySign(messageHash,priceNodePublicKey,expiresAt,v,r,s);
    }

    function _checkBuyAvailable(address priceNodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) view internal returns(bool){
        require(now < expireTimestamp,"The proudct has expired");
		require(quantity>0, "quantity should > 0");
		require(isValid, "the product has been closed");
		require(quantity <= remaining(), "quantity should <= remaining");
		require(price > 0, "price should > 0");

		require(verifyPrice(priceNodePublicKey,price,expiresAt,v,r,s),"buy verify sign failed");
        return true;
    }

	function _buy(uint256 amount,address priceNodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) internal returns(bool) {
        if (!_checkBuyAvailable(priceNodePublicKey,quantity,price,expiresAt,v,r,s)){
            return false;
        }
		_mint(_msgSender(), quantity);
		
		totalPremiums = totalPremiums.add(amount);
		totalSellQuantity = totalSellQuantity.add(quantity);

		emit EventBuy(_msgSender(),quantity,amount);
		statusChanged();
		return true;
	}


    function _checkWithdrawAvailable(address priceNodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) view internal returns(bool){
		require(isValid,"the product has been closed");
		uint256 userQuantity = balanceOf(_msgSender());
		require(quantity<=userQuantity,"invalid withdraw quantity");
		require(verifyPrice(priceNodePublicKey,price,expiresAt,v,r,s),"withdraw vertify sign failed");
        return true;
    }

    function _calcWithDrawAmount(uint256 quantity, uint256 price,uint256 totalSellQty) view public returns(uint256){
		uint256 avgPrice = totalPremiums.div(totalSellQty);
		uint256 returnPrice = avgPrice < price ? avgPrice : price;
		uint256 amount = returnPrice.mul(quantity);
		uint256 returnAmount =  amount.mul(1000 - _priceMetaInfoDb.PRODUCT_WITHDRAW_PERCENT()).div(1000);
        return returnAmount;
    }

	function _withdraw(address nodePublicKey, uint256 quantity, uint256 price, uint256 expiresAt, uint8 _v, bytes32 _r, bytes32 _s) internal returns(uint256){
        if (!_checkWithdrawAvailable(nodePublicKey,quantity,price,expiresAt,_v,_r,_s)){
            return 0;
        }
		_burn(_msgSender(), quantity);
		uint256 returnAmount =  _calcWithDrawAmount(quantity,price,totalSellQuantity);
		totalSellQuantity = totalSellQuantity.sub(quantity);
		totalPremiums = totalPremiums.sub(returnAmount);

   		statusChanged();
        return returnAmount;
	}


}