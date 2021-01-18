
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
import "./@openzeppelin/utils/EnumerableMap.sol";
import "./@openzeppelin/utils/ReentrancyGuard.sol";
import "./ERC20TokenRegister.sol";
import "./@openzeppelin/math/SafeMath.sol";
import "./CompatibleERC20.sol";

contract PledgePool is IUpgradable , ReentrancyGuard
{
    using SafeMath for uint256;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.AddressToBytes8Map;
    using CompatibleERC20 for address;


    ERC20TokenRegister _tokenRegister;

    EnumerableMap.AddressToUintMap private _pledge;
    EnumerableMap.AddressToBytes8Map private _pledgeCoinName;

    uint256 public minPledgedAmount;

    uint256 public totalPledgeAmount; 

    event MinPledgedAmountChanged(uint256 oldMinAmount,uint256 minAmount);
    event NewPledged(address account,uint256 totalAmount);

    constructor(uint256 minPlededAmt) public 
    {
        minPledgedAmount=minPlededAmt ;
    }

    function hasPledged(address addr) public view returns(bool){
        return _pledge.contains(addr);
    }

    function setMinPledgedAmount(uint amount) onlyOwner public {
        uint256 oldMinAmount=minPledgedAmount;
        minPledgedAmount=amount;
        emit MinPledgedAmountChanged(oldMinAmount,minPledgedAmount);
    }


    function pledge(bytes8 coinName,uint256 amount) nonReentrant whenNotPaused external{
        address token= _tokenRegister.getToken(coinName);

        require(amount>=minPledgedAmount,"Amount should great then the min pledged amount");
        require(token.allowanceERC20(_msgSender(),address(this))>=amount,"No enough USDT/DAI allowance for pledge");
        require(!hasPledged(_msgSender()),"The account has been pledged");
        token.transferFromERC20(_msgSender(),address(this),amount);
        
        uint256 pledgeAmount=amount;
        _pledge.set(_msgSender(),pledgeAmount);
        _pledgeCoinName.set(_msgSender(),coinName);
        totalPledgeAmount=totalPledgeAmount.add(pledgeAmount);
        emit NewPledged(_msgSender(),pledgeAmount);
    }

    function ransomTo(address account) nonReentrant whenNotPaused internal{
        require(hasPledged(account),"The account did not pledge");
        uint256 value=_pledge.get(account);
        require(_pledgeCoinName.contains(account),"account invalid");
        (uint256 [] memory balances,address [] memory tokens)= _tokenRegister.getTransferAmount(address(this),value,_pledgeCoinName.get(account));
        for (uint256 i=0;i<balances.length;++i){ 
            if (balances[i]>0){
                tokens[i].transferERC20(account,balances[i]); 
            }
        }
        _pledge.remove(account);
        _pledgeCoinName.remove(account);
        totalPledgeAmount=totalPledgeAmount.sub(value);
    }


    function  updateDependentContractAddress() public virtual override{
        address tokenRigisterAddr=register.getContract("TKRG");
        assert(tokenRigisterAddr!=address(0));
        _tokenRegister =ERC20TokenRegister(tokenRigisterAddr);
    }

    function recoveryOfWasteHeat() onlyOwner public {
        require(_pledge.length()==0);
        (uint256 [] memory balances,address [] memory tokens)= _tokenRegister.getTransferAmount(address(this),0,"    ");
        for (uint256 i=0;i<balances.length;++i){ 
            if (balances[i]>0){
                tokens[i].transferERC20(admin(),balances[i]); 
            }
        }
    }


}
