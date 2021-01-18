
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

import "./@openzeppelin/math/SafeMath.sol";
import "./Ins3Pausable.sol";

contract Ins3Controller is Ins3Pausable 
{
	using SafeMath for uint256;
	mapping(uint256 => address) private _indexProductMap;
	mapping(uint256 => address) private _indexOracleVoteTokenMap;
	uint256 _nextProductIndex;
	uint256 _nextOracleVoteTokenIndex;
	event NewProductAdded(address productTokenAddress);
	event NewOracleVoteTokenAdded(address oracleVoteTokenAddress);

	constructor(address ownable) Ins3Pausable() public {
		setOwnable(ownable);
	}

	function addProduct(address productTokenAddress) public onlyOwner returns(bool){
		_indexProductMap[_nextProductIndex] = productTokenAddress;
		_nextProductIndex = _nextProductIndex.add(1);
		emit NewProductAdded(productTokenAddress);
		return true;
	}

	function getProduct(uint256 index) public view returns(address) {
		require(index < productSize(),"index should < productSize");
		address tokenAddress = _indexProductMap[index];
		return tokenAddress;
	}
	
	function productSize() public view returns(uint256) {
		return _nextProductIndex;
	}

	function addOracleVoteToken(address tokenAddress) public onlyOwner returns(bool){
		_indexOracleVoteTokenMap[_nextOracleVoteTokenIndex] = tokenAddress;
		_nextOracleVoteTokenIndex = _nextOracleVoteTokenIndex.add(1);
		emit NewOracleVoteTokenAdded(tokenAddress);
		return true;
	}

	function getOracleMachine(uint256 index) public view returns(address) {
		require(index < oracleMachineSize(),"index should < oracleMachineSize");
		address tokenAddress = _indexOracleVoteTokenMap[index];
		return tokenAddress;
	}
	
	function oracleMachineSize() public view returns(uint256) {
		return _nextOracleVoteTokenIndex;
	}
}
