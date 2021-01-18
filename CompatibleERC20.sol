
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

import "./@openzeppelin/token/ERC20/IERC20.sol" ;
import "./@openzeppelin/token/ERC20/SafeERC20.sol" ;
import "./IUSDT.sol";
import "./@openzeppelin/math/SafeMath.sol";

interface IERC20Full is IERC20
{
    function decimals() external view returns (uint8);
}

library CompatibleERC20  {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address constant USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function decimalsERC20(address token) internal view returns (uint256){
        if (token==USDT_ADDRESS){
            return IUSDT(token).decimals();
        }else{
            return uint256(IERC20Full(token).decimals());
        }
    }

    function getDiffDecimals(address token) internal view returns(uint256){
        uint256 dec=decimalsERC20(token);
        require(dec<=18,"token's decimals must <=18");
        return 10**(18-dec);
    }

    function getCleanAmount(address token,uint256 amount) internal view returns (uint256){
        uint256 dec=getDiffDecimals(token);
        return amount.div(dec).mul(dec);
    }

    function balanceOfERC20(address token,address addr) internal view returns(uint256){
        uint256 dec=getDiffDecimals(token);
        if (token==USDT_ADDRESS){
            return IUSDT(token).balanceOf(addr).mul(dec);
        }else{
            return IERC20(token).balanceOf(addr).mul(dec);
        }
    }

    function transferERC20(address token,address recipient, uint256 amount) internal{
        uint256 dec=getDiffDecimals(token);
        if (token==USDT_ADDRESS){
            IUSDT(token).transfer(recipient,amount.div(dec));  
        }else{
            IERC20(token).safeTransfer(recipient,amount.div(dec));
        }
    }

    function allowanceERC20(address token,address account,address spender) view internal returns(uint256){
        uint256 dec=getDiffDecimals(token);
        if (token==USDT_ADDRESS){
            return IUSDT(token).allowance(account,spender).mul(dec);
        }else{
            return IERC20(token).allowance(account,spender).mul(dec);
        }
    }
    
    function approveERC20(address token,address spender, uint256 amount) internal {
        uint256 dec=getDiffDecimals(token);
        if (token==USDT_ADDRESS){
            IUSDT(token).approve(spender,amount.div(dec));
        }else{
            IERC20(token).safeApprove(spender,amount.div(dec));
        }
    }

    function transferFromERC20(address token,address sender, address recipient, uint256 amount) internal {
        uint256 dec=getDiffDecimals(token);
        if (token==USDT_ADDRESS){
            IUSDT(token).transferFrom(sender,recipient,amount.div(dec));
        }else{
            IERC20(token).safeTransferFrom(sender,recipient,amount.div(dec));
        }
    }
}
