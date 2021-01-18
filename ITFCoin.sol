
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
import "./@openzeppelin/math/SafeMath.sol";
import "./@openzeppelin/token/ERC777/ERC777.sol" ;

contract ITFCoin is ERC777, IUpgradable
{
    using SafeMath for uint256;

    uint256 public maxSupply;
    address public holder;

    constructor(uint256 initialSupply,uint256 maxSupplyValue,address[] memory defaultOperators,address registerAddress) public
        ERC777("Ins3.Finance Coin","ITF",defaultOperators,registerAddress)
    {
        _mint(_msgSender(), initialSupply,"","");
        maxSupply = maxSupplyValue;
    }

    function updateDependentContractAddress() public virtual override {
        holder = register.getContract("ITFH");
        require(holder!=address(0),"Null for ITFH");
    }

    modifier onlyHolder {
        require(holder == _msgSender(),"not holder");
        _;
    }

    function mint(address account,uint256 amount,bytes memory userData,bytes memory operatorData) external onlyHolder{
        require(maxSupply>=amount.add(totalSupply()),"mint - max supply limit");
        _mint(account, amount, userData, operatorData);
    }
}

