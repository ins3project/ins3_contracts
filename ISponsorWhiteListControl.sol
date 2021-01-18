
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
pragma solidity ^0.6.0;

interface ISponsorWhiteListControl {
    function getSponsorForGas(address contractAddr) external view returns (address);
    function getSponsoredBalanceForGas(address contractAddr) external view returns (uint) ;
    function getSponsoredGasFeeUpperBound(address contractAddr) external view returns (uint) ;
    function getSponsorForCollateral(address contractAddr) external view returns (address) ;
    function getSponsoredBalanceForCollateral(address contractAddr) external view returns (uint) ;
    function isWhitelisted(address contractAddr, address user) external view returns (bool) ;
    function isAllWhitelisted(address contractAddr) external view returns (bool) ;
    function addPrivilegeByAdmin(address contractAddr, address[] memory addresses) external ;
    function removePrivilegeByAdmin(address contractAddr, address[] memory addresses) external ;
    function setSponsorForGas(address contractAddr, uint upperBound) external payable ;
    function setSponsorForCollateral(address contractAddr) external payable ;
    function addPrivilege(address[] memory) external ;
    function removePrivilege(address[] memory) external ;
}
