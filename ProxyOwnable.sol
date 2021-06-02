
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

import "./@openzeppelin/GSN/Context.sol";
import "./@openzeppelin/access/Ownable.sol";
import "./@openzeppelin/utils/Address.sol";

abstract contract ProxyOwnable is Context{
    using Address for address;

    Ownable _ownable;
    Ownable _adminable;

    constructor() public{
        
    }

    function setOwnable(address ownable) internal{ 
        require(ownable!=address(0),"setOwnable should not be 0");
        _ownable=Ownable(ownable);
        if (address(_adminable)==address(0)){
            require(!address(_adminable).isContract(),"admin should not be contract");
            _adminable=Ownable(ownable);
        }
    }

    function setAdminable(address adminable) internal{
        require(adminable!=address(0),"setOwnable should not be 0");
        _adminable=Ownable(adminable);
    }
    modifier onlyOwner {
        require(address(_ownable)!=address(0),"proxy ownable should not be 0");
        require(_ownable.isOwner(_msgSender()),"Not owner");
        _;
    }

    modifier onlyAdmin {
        require(address(_adminable)!=address(0),"proxy adminable should not be 0");
        require(_adminable.isOwner(_msgSender()),"Not admin");
        _;
    }

    function admin() view public returns(address){
        require(address(_adminable)!=address(0),"proxy admin should not be 0");
        return _adminable.owner();
    }

    function owner() view external returns(address){
        require(address(_ownable)!=address(0),"proxy ownable should not be 0");
        return _ownable.owner();
    }

    function getOwner() view external returns(address){
        require(address(_ownable)!=address(0),"proxy ownable should not be 0");
        return _ownable.owner();
    }

    function isOwner(address addr) public view returns(bool){
        require(address(_ownable)!=address(0),"proxy ownable should not be 0");
        return _ownable.isOwner(addr);
    }

}
