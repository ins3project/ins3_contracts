
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

import "./ITFCoinHolderBase.sol";
import "./IUpgradable.sol";
import "./@openzeppelin/utils/EnumerableMap.sol";
import "./@openzeppelin/utils/ReentrancyGuard.sol";
import "./@openzeppelin/math/Math.sol";
import "./@openzeppelin/token/ERC20/IERC20.sol";
import "./OracleNode.sol";

contract OracleNodeMgr is IUpgradable, ReentrancyGuard
{
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    struct OracleNodeHolder
    {
        bool available;
        uint256 bornTime;
        uint256 lockedITFAmount;
        OracleNode node;
    }

    EnumerableMap.AddressToUintMap _nodes;
    OracleNodeHolder [] _nodeHolders;
    EnumerableMap.AddressToUintMap _nodePublicKeys;
    mapping(address/*node address*/=>bool) public nodeWhiteList;

    ITFCoinHolderBase private _itfCoinHolder;
    uint256 public minNodeAssets;

    constructor(uint256 minLockedITFAmount) public {
        minNodeAssets=minLockedITFAmount;
    }

    event NodeRegistered(address indexed node,string url,uint256 itfAmount);
    event NodeUnregistered(address indexed node,string url,uint256 itfAmount);

    function setMinLockedITFAmount(uint256 minLockedITFAmount) public onlyOwner{
        minNodeAssets = minLockedITFAmount;
    }
    
    function selectNode() view public returns(string memory,address){
        uint256 idx=Math.rand(_nodes.length());
        require(idx>=0 && idx<_nodes.length(),"The index of node should be in [0,count-1)");
        (,uint256 index)=_nodes.at(idx);
        OracleNodeHolder storage nodeHolder=_nodeHolders[index];
        return (nodeHolder.node.url(),address(nodeHolder.node));
    }

    function getNode(uint256 idx) view public returns(address){
        require(idx>=0 && idx<_nodes.length(),"The index of node should be in [0,count-1)");
        (,uint256 index)=_nodes.at(idx);
        OracleNodeHolder storage nodeHolder=_nodeHolders[index];
        assert(nodeHolder.available==true);
        return address(nodeHolder.node);
    }


    function nodeCount() view public returns(uint256){
        return _nodes.length();
    }

    function  updateDependentContractAddress() public virtual override{
        address itfCoinHolderAddress = register.getContract("ITFH");
        _itfCoinHolder=ITFCoinHolderBase(itfCoinHolderAddress);
        require(itfCoinHolderAddress!=address(0),"Null for ITFH");
    }

    function isNode(address nodeAddr) view public returns(bool){
        return _nodes.contains(nodeAddr);
    }

    function isNodePublicKeyValid(address nodeAccountAddr) view public returns(bool){
        return _nodePublicKeys.contains(nodeAccountAddr);
    }

    function addNodeToWhiteList(address nodeAddr) public onlyOwner returns (bool) {
        nodeWhiteList[nodeAddr] = true;
        return true;
    }

    function removeNodeFromWhiteList(address nodeAddr) public onlyOwner returns (bool) {
        nodeWhiteList[nodeAddr] = false;
        return true;
    }

    function registerNode(address nodeAddr) nonReentrant whenNotPaused external returns(address){
        require(nodeWhiteList[nodeAddr],"node address not on the white list");
        require(!isNode(nodeAddr),"The node has been register");

        uint256 nodeBalance=_itfCoinHolder.balanceOf(_msgSender());
        require(nodeBalance>=minNodeAssets,"Not enough ITF in account");

        OracleNode node=OracleNode(nodeAddr);
        IERC20(_itfCoinHolder.itfCoinAddress()).transferFrom(_msgSender(),address(this),minNodeAssets); 
        uint idx=_nodeHolders.length;
        _nodeHolders.push(OracleNodeHolder(true,now,minNodeAssets,node));
        _nodes.set(nodeAddr,idx);
        address nodePublicKey = node.nodePublicKey();
        _nodePublicKeys.set(nodePublicKey,idx);
        emit NodeRegistered(nodeAddr,node.url(),minNodeAssets);
        return nodeAddr;
    }

    function unregisterNode(address nodeAddr) nonReentrant whenNotPaused external{
        require(nodeAddr!=address(0),"The node address on unregisterNode() should not be 0");
        require(isNode(nodeAddr),"The address of this nodes is not a valid address");
        OracleNode node=OracleNode(nodeAddr);
        require(node.owner()==_msgSender() || isOwner(_msgSender()),"Only the owner of nodes can unregister itself");
        uint idx=_nodes.get(nodeAddr);
        address nodePublicKey = node.nodePublicKey();
        OracleNodeHolder storage holder= _nodeHolders[idx];

        IERC20(_itfCoinHolder.itfCoinAddress()).transfer(node.owner(),holder.lockedITFAmount);
        
        assert(idx>=0); 
        _nodes.remove(nodeAddr);
        _nodePublicKeys.remove(nodePublicKey);
        emit NodeUnregistered(nodeAddr,holder.node.url(),holder.lockedITFAmount);
        _nodeHolders[idx].available=false;
    }

}