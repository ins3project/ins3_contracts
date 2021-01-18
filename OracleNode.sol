
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

import "./@openzeppelin/access/Ownable.sol";
import "./@openzeppelin/token/ERC20/IERC20.sol";

contract OracleNode is Ownable
{
    string public url ;
    address public nodePublicKey;

    constructor(string memory svrUrl, address nodePublicKeyVal) public{
        url = svrUrl;
        nodePublicKey = nodePublicKeyVal;
    }

    function transferERC20(address token, address recipient, uint256 amount) public onlyOwner returns (bool){
        return IERC20(token).transfer(recipient, amount);
    }
}
