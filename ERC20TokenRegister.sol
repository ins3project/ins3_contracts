
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

import "./Ins3Register.sol";
import "./@openzeppelin/math/SafeMath.sol";
import "./CompatibleERC20.sol";


contract ERC20TokenRegister is Ins3Register
{
    using SafeMath for uint256;
    using CompatibleERC20 for address;

    constructor(address ownable) public
        Ins3Register(ownable)
    {
    }
    
    function getToken(bytes8 name) view public returns(address){
        require(hasContract(name),"No such ERC20 token");
        return getContract(name);
    }

    function getAllTokens() view public returns(address [] memory){
        bytes8 [] memory names=contractNames();
        address [] memory addrs=new address[](names.length);
        for (uint256 i=0;i<names.length;++i){
            addrs[i]=getContract(names[i]);
        }
        return addrs;
    }

    function getAllTokenBalances(address addr) view public returns(uint256 /**sum */,uint256 [] memory, address [] memory){
        address [] memory tokenAddrs=getAllTokens();
        uint256 sumBalance=0;
        uint256 [] memory balances=new uint256 [] (tokenAddrs.length);
        for (uint256 i=0;i<tokenAddrs.length;++i){
            address token=tokenAddrs[i];
            uint256 balance=token.balanceOfERC20(addr);
            balances[i]=balance;
            sumBalance=sumBalance.add(balance);
        }
        return (sumBalance,balances,tokenAddrs);
    }


    function getTransferAmount(address addr,uint256 rawAmount,bytes8 coinName) view public returns(uint256 [] memory, address [] memory) {
        (uint256 sum,uint256 [] memory balances,address[] memory tokens)=getAllTokenBalances(addr);
        if (rawAmount==0){
            rawAmount=sum;
        }
        uint256 amount=rawAmount;
        require(amount<=sum,"Amount is too large");
        address coinAddress=address(0);
        uint256 coinBalance=0;
        if (hasContract(coinName)){
            coinAddress=getToken(coinName);
            coinBalance=coinAddress.balanceOfERC20(addr);
            if (coinBalance>=amount){
                uint256 [] memory amounts=new uint256[](1);
                address[] memory tokenAddrs=new address[](1);
                amounts[0]=amount;
                tokenAddrs[0]=coinAddress;
                return (amounts,tokenAddrs);
            }else{
                sum=sum.sub(coinBalance);
                amount=amount.sub(coinBalance);
            }
        }

        require(sum>0,"sum should >0");
        uint256 [] memory amounts=new uint256[](balances.length);
        uint256 calcSum=0;
        for (uint256 i=0;i<amounts.length;++i){
            if (tokens[i]==coinAddress){
                amounts[i]=coinBalance;
                calcSum=calcSum.add(coinBalance);
            }else{
                amounts[i]=amount.mul(balances[i]).div(sum);
                calcSum=calcSum.add(amounts[i]);
            }
        }
        require(calcSum<=rawAmount,"Sum of calc should <= amount");
        if (calcSum<rawAmount){
            uint256 oddAmount=rawAmount.sub(calcSum);
            for (uint256 j=0;j<balances.length;++j){
                if(balances[j]>amounts[j]){
                    uint256 leftAmount = balances[j].sub(amounts[j]);
                    if(leftAmount>=oddAmount){
                        amounts[j]=amounts[j].add(oddAmount);
                        break;
                    }else{
                        amounts[j]=amounts[j].add(leftAmount);
                        oddAmount = oddAmount.sub(leftAmount);
                    }
                }
            }
        }
        return (amounts,tokens);
    }
}