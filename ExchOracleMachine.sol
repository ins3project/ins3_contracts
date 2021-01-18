
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


import "./OracleNodeMgr.sol";
import "./PledgePool.sol";
import "./ITFCoinHolderBase.sol";
import "./@openzeppelin/math/SafeMath.sol";
import "./PriceMetaInfoDB.sol";
import "./@openzeppelin/utils/EnumerableMap.sol";

contract ExchOracleMachine is PledgePool {
    using SafeMath for uint256;
    using EnumerableMap for EnumerableMap.UintToUintMap;

    string public category;
    string public name;

    struct VoteResult {
        uint256 timestamp;    
        bool feedsResult;
        bool accountResult;
        bool withdrawResult;
        uint256 openTimestamp;  
    }


    uint256[8] public _ORACLE_REWARD_SCHEDULE;

    uint256[9] public _ORACLE_CUM_REWARD_SCHEDULE;


    

    mapping(address=>VoteResult) private _voteResults;
    VoteResult[]  _voteResultHistory;

    EnumerableMap.UintToUintMap private _timeRewardsMap;

    uint256 _latestOpenTimestamp;

    mapping(uint256=>uint256) _voteResultCount;

    OracleNodeMgr _oracleNodeMgr;
    PriceMetaInfoDB _priceMetaInfoDb;
    ITFCoinHolderBase _itfCoinHolder;

    uint256 public _histCumPremium;

    event NewVoted(address voter,bool feedsResult, bool accountResult, bool withdrawResult,uint256 timestamp);
    event Opened(uint256 timestamp);
    event Closed(uint256 timestamp);

    constructor(string memory exchName,string memory category_,uint256 minPlededAmt,uint256[8] memory oracleRewardSchedule, uint256[9] memory oracleCumRewardSchedule) public
        PledgePool(minPlededAmt)  
    {
        name=exchName;
        category=category_;

        _ORACLE_REWARD_SCHEDULE = oracleRewardSchedule;
        _ORACLE_CUM_REWARD_SCHEDULE = oracleCumRewardSchedule;
    }


    function setOracleSchedule(uint256[8] memory oracleRewardSchedule, uint256[9] memory oracleCumRewardSchedule) public onlyOwner {
        _ORACLE_REWARD_SCHEDULE = oracleRewardSchedule;
        _ORACLE_CUM_REWARD_SCHEDULE = oracleCumRewardSchedule;
    }

    function getOracleRewardSchedule() public view returns(uint256[8] memory) {
        return _ORACLE_REWARD_SCHEDULE;
    }

    function getOracleCumRewardSchedule() public view returns(uint256[9] memory) {
        return _ORACLE_CUM_REWARD_SCHEDULE;
    }

    function calculateOracleReward(uint256 histCumPremium, uint256 currentPremium) view private returns (uint256) {
        uint256 ITFAmount = _priceMetaInfoDb.TOTAL_ITF_AMOUNT();

        uint256 stageAmount = ITFAmount.mul(_priceMetaInfoDb.ORACLE_PAYOUT_RATE()).div(100).div(_priceMetaInfoDb.ORACLE_NUM()).div(_priceMetaInfoDb.ORACLE_STAGE_NUM());  
        

        uint256 currentReward = 0;
        uint256 leftAmount = currentPremium;
        uint256 calcAmt;

        for (uint256 i=_ORACLE_CUM_REWARD_SCHEDULE.length-1; i >= 0; i--) {
            if (leftAmount <= 0){
                break;
            }
            if (_ORACLE_CUM_REWARD_SCHEDULE[i]*_priceMetaInfoDb.ORACLE_SCHEDULE_MULTIPLIER() > leftAmount + histCumPremium){
                continue;
            }

            require(i < _ORACLE_REWARD_SCHEDULE.length,"oracle reward schedule out of bounds");
            uint256 reward = _ORACLE_CUM_REWARD_SCHEDULE[i].mul(_priceMetaInfoDb.ORACLE_SCHEDULE_MULTIPLIER());
            calcAmt = histCumPremium >=  reward ? leftAmount : leftAmount.add(histCumPremium).sub(reward);
            uint256 stageReward =  calcAmt.mul(stageAmount).div(_ORACLE_REWARD_SCHEDULE[i]).div(_priceMetaInfoDb.ORACLE_SCHEDULE_MULTIPLIER());
            currentReward = currentReward.add(stageReward);
            leftAmount = leftAmount.sub(calcAmt);
        }
        
        return currentReward > 0 ? currentReward : 0;
    }

    function openTimestamp() view public returns(uint256){
        return _latestOpenTimestamp;
    }

    function closeTimestamp() view public returns(uint256){
        return _latestOpenTimestamp.add(_priceMetaInfoDb.ORACLE_VALID_PERIOD());
    }

    function open() onlyOwner public {
        _latestOpenTimestamp=now;
        _timeRewardsMap.set(_latestOpenTimestamp,0);
        emit Opened(_latestOpenTimestamp);
    }

    function close(uint256 premium) onlyOwner public{
        uint rewards=calculateOracleReward(_histCumPremium,premium);
        _histCumPremium=_histCumPremium.add(premium);
        uint256 currRewards=_timeRewardsMap.get(_latestOpenTimestamp);
        _timeRewardsMap.set(_latestOpenTimestamp,currRewards.add(rewards));
        emit Closed(_latestOpenTimestamp);
    }

    function reopen(uint256 premium) onlyOwner public {
        close(premium);
        open();
    }

    function isOpened() view public returns(bool){
        return _timeRewardsMap.contains(_latestOpenTimestamp) && _timeRewardsMap.get(_latestOpenTimestamp)==0;
    }

    function  updateDependentContractAddress() public virtual override{
        super.updateDependentContractAddress();
        _oracleNodeMgr=OracleNodeMgr(register.getContract("ONMG"));
        _priceMetaInfoDb=PriceMetaInfoDB(register.getContract("MIDB"));
        address itfCoinHolderAddress = register.getContract("ITFH");
        _itfCoinHolder=ITFCoinHolderBase(itfCoinHolderAddress);
        require(itfCoinHolderAddress!=address(0),"Null for ITFH");
    }

    function voteResultHistory(uint256 index) view public returns(bool,bool,bool,uint256){
        if (_voteResultHistory.length<index+1){
            return (true,true,true,0);
        }
        VoteResult storage v = _voteResultHistory[_voteResultHistory.length-1-index];
        return (v.feedsResult,v.accountResult,v.withdrawResult,v.timestamp);
    }

    function getVoteResult() view public returns(bool){
        bool feedsResult=false;
        bool accountResult=false;
        bool withdrawResult=false;
        uint256 resultsLength=_voteResultHistory.length;
        if (resultsLength==0){
            return true;
        }
        for (uint256 i=0;i<resultsLength;++i){
            VoteResult storage v = _voteResultHistory[resultsLength-1-i];
            if (now.sub(v.timestamp)>_priceMetaInfoDb.ORACLE_VALID_PERIOD()){
                break;
            }
            if (v.feedsResult){
                feedsResult=true;
            }
            if (v.accountResult){
                accountResult=true;
            }
            if (v.withdrawResult){
                withdrawResult=true;
            }

            if (feedsResult || accountResult || withdrawResult){
                return true;
            }
        }
        return false;    
    }

    function voteTimes() view public returns (uint256){
        return _voteResultHistory.length;
    }

    function latestResult() view public returns(bool,bool,bool,uint256){
        return voteResultHistory(0);
    }

    function voterResult(address voter) view public returns(bool,bool,bool,uint256){
        if(!hasVoted(voter)){
            return (true,true,true,0);
        }
        VoteResult storage v=_voteResults[voter];
        return (v.feedsResult,v.accountResult,v.withdrawResult,v.timestamp);
    }


    function hasVoted(address voter) view public returns(bool){
        return _voteResults[voter].timestamp!=0;
    }

    function isVoteResultExpired(address voter) view public returns(bool){
        if (!hasVoted(voter)){
            return true;
        }

        return (now.sub(_voteResults[voter].timestamp)) >= _priceMetaInfoDb.ORACLE_VALID_PERIOD();
    }

    function verifyVote(address voter, address nodePublicKey, bool feedsResult, bool accountResult, bool withdrawResult,
                    uint256 generatedAt, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) public view returns(bool){
        require(address(_priceMetaInfoDb)!=address(0),"priceMetaInfoDb not set");
        require(_oracleNodeMgr.isNodePublicKeyValid(nodePublicKey),"The node public key is not valid");
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                voter,
                nodePublicKey, 
                feedsResult,
                accountResult,
                withdrawResult,
                generatedAt,
                expiresAt
            )
        );
        return _priceMetaInfoDb.verifySign(messageHash, nodePublicKey, expiresAt, v, r, s);
    }

    function voteEx(address voter, address nodePublicKey, bool feedsResult, bool accountResult, bool withdrawResult, 
                    uint256 generatedAt, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) nonReentrant whenNotPaused external{

        require(isOpened(),"OracleVote has not been opened");
        require(hasPledged(voter),"The account must has been pledged");


        require(verifyVote(voter,nodePublicKey,feedsResult,accountResult,withdrawResult,generatedAt,expiresAt,v,r,s),"vertify sign failed");

        if (hasVoted(voter)){
            VoteResult storage voteResult=_voteResults[voter];
            uint periodSecs=now.sub(voteResult.timestamp);
            require(periodSecs>= _priceMetaInfoDb.ORACLE_VALID_PERIOD(),"The vote has not expired");
        }
        VoteResult memory voteResult = VoteResult(now,feedsResult,accountResult,withdrawResult,_latestOpenTimestamp);
        _voteResults[voter]=voteResult;
        _voteResultHistory.push(voteResult);
        _voteResultCount[_latestOpenTimestamp]=_voteResultCount[_latestOpenTimestamp].add(1);
        emit NewVoted(voter,feedsResult,accountResult,withdrawResult,now);
    }

    function ransom() whenNotPaused external {
        address account=_msgSender();
        require(hasPledged(account),"The account must has been pledged");
        require(!hasVoted(account),"An account has been voted");
        ransomTo(account);
    }

    function unvote() whenNotPaused external{ 
        address voter=_msgSender();
        require(hasPledged(voter),"The account must has been pledged");
        require(hasVoted(voter),"An account has not been voted");
        VoteResult storage v=_voteResults[voter];
        uint periodSecs=now.sub(v.timestamp);

        require(periodSecs>= _priceMetaInfoDb.ORACLE_VALID_PERIOD(),"The vote has not expired");

        ransomTo(voter);

        v.timestamp=0;
        v.openTimestamp=0;
    }



    function getNoSettledRewards(uint256 currentProductPremium) view public returns(uint256){
        uint256 count=_voteResultCount[_latestOpenTimestamp];
        if (count==0){
            return 0;
        }
        uint newRewards=calculateOracleReward(_histCumPremium,currentProductPremium);
        uint256 currRewards=_timeRewardsMap.get(_latestOpenTimestamp);
        return currRewards.add(newRewards).div(count);
    }


    function getClaimRewards(address voter) view public returns(uint256){
        require(hasVoted(voter),"An account has not been voted");
        VoteResult storage v=_voteResults[voter];
        if (v.openTimestamp==0){
            return 0;
        }
        uint256 rewards=_timeRewardsMap.get(v.openTimestamp);
        if (rewards==0){
            return 0;
        }
        uint256 count=_voteResultCount[v.openTimestamp];
        require(count>0,"The count of voters should not be 0");

        return rewards.div(count);
    }

    function claimRewards() whenNotPaused public{
        address voter=_msgSender();
        require(hasPledged(voter),"The account must has been pledged");
        require(hasVoted(voter),"An account has not been voted");
        uint256 rewards=getClaimRewards(voter);
        require(rewards>0,"No rewards to claim");

        VoteResult storage v=_voteResults[voter];
        _itfCoinHolder.reward(voter,rewards,"","");
        _timeRewardsMap.set(v.openTimestamp,_timeRewardsMap.get(v.openTimestamp).sub(rewards));
        v.openTimestamp=0;
    }

}

