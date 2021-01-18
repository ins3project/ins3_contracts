
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
import './ISponsorWhiteListControl.sol';
import "./@openzeppelin/math/SafeMath.sol";


contract PriceMetaInfoDB is Ownable 
{
    using SafeMath for uint256;    
    mapping(uint256=>address) _channels;
    
    uint256 public CHANNEL_PREMIUMS_PERCENT; 

    uint256 public FLASHLOAN_PREMIUMS_PERCENT; 

    uint256 public FLASHLOAN_PREMIUMS_DIVISOR; 

    address public PRICE_NODE_PUBLIC_KEY; 

    uint256 public TOTAL_ITF_AMOUNT ;

    uint256 public STAKING_MINT_PERCENT; 

    uint256 public PREMIUMS_SHARE_PERCENT; 

    uint256 public PRODUCT_WITHDRAW_PERCENT; 

    uint256 public ORACLE_PAYOUT_RATE; 

    uint256 public ORACLE_STAGE_NUM; 

    uint256 public ORACLE_NUM; 

    uint256 public ORACLE_SCHEDULE_MULTIPLIER; 

    uint256 public ORACLE_VALID_PERIOD; 

    uint256 public ITFAPY; 
    
    address[4] private _itfReleaseAccountArray;
    uint256[4] private _itfReleaseAccountMultiplierArray;
    uint256 private _itfReleaseDivisor;

    uint256 _lastBlockNumber;
    uint256 _lastBlockTimestamp;
    uint256 public blockTime  ; 

    function currentTimestamp() view public returns(uint256){
        return (block.number-_lastBlockNumber).mul(blockTime).div(1000).add(_lastBlockTimestamp);
    }

    uint256 public STAKING_TOKEN_MARGIN; 

    constructor(uint256 totalITFAmount, uint256 stakingMintPercent, 
                uint256 oraclePayoutRate,uint256 oracleStageNum,uint256 oracleNum,uint256 oracleScheduleMultiplier,
                uint256 premiumsSharePercent, 
                address[4] memory itfReleaseAccounts, 
                uint256[4] memory itfReleaseAccountMultipliers, 
                uint256 itfReleaseDivisor,
                uint256 channelPremiumsPercent,
                uint256 oracleValidPeriod,
                address priceNodePublicKey,
                uint256 flashLoanPremiumsPercent,
                uint256 flashLoanPremiumsDivisor,
                uint256 blockTime_
                ) public{
        require(blockTime_>0,"block time must be >0");

        TOTAL_ITF_AMOUNT=totalITFAmount;
        STAKING_MINT_PERCENT = stakingMintPercent;
        ORACLE_PAYOUT_RATE = oraclePayoutRate;
        ORACLE_STAGE_NUM = oracleStageNum;
        ORACLE_NUM = oracleNum;
        ORACLE_SCHEDULE_MULTIPLIER = oracleScheduleMultiplier;
        PREMIUMS_SHARE_PERCENT = premiumsSharePercent;
        ORACLE_VALID_PERIOD = oracleValidPeriod;
        setITFReleaseAccounts(itfReleaseAccounts,itfReleaseAccountMultipliers,itfReleaseDivisor);
        PRICE_NODE_PUBLIC_KEY = priceNodePublicKey;
        CHANNEL_PREMIUMS_PERCENT=channelPremiumsPercent;
        FLASHLOAN_PREMIUMS_PERCENT = flashLoanPremiumsPercent;
        FLASHLOAN_PREMIUMS_DIVISOR = flashLoanPremiumsDivisor;

        ITFAPY = 200;
        PRODUCT_WITHDRAW_PERCENT = 300;
        _lastBlockNumber=block.number;
        _lastBlockTimestamp=block.timestamp;
        blockTime = blockTime_;

        STAKING_TOKEN_MARGIN=10;
    }

    function refreshBlockTime() public {
        _lastBlockNumber=block.number;
        _lastBlockTimestamp=block.timestamp;
    }

    function setBlockTime(uint256 blockTime_) public onlyOwner {
        if (blockTime_!=blockTime){
            require(blockTime_>0,"block time must be >0");
            blockTime = blockTime_;
        }
        refreshBlockTime();
    }

    function seStakingTokenMargin(uint256 margin) public onlyOwner{
        STAKING_TOKEN_MARGIN=margin;
    }

    function hasCoverChannel(uint256 id) view public returns(bool){
        return _channels[id]!=address(0);
    } 

    function getCoverChannelAddress(uint256 id) view public returns(address){
        return _channels[id];
    }

    function registerCoverChannel(uint256 id,address receiverAccount) public onlyOwner{
        require(!hasCoverChannel(id),"The id exists");
        _channels[id]=receiverAccount;
    }

    function unregisterCoverChannel(uint256 id) public onlyOwner{
        require(hasCoverChannel(id),"The id does not exists");
        delete _channels[id];
    }

    function setChannelPremiumsPercent(uint256 channelPremiumsPercent) public onlyOwner {
        CHANNEL_PREMIUMS_PERCENT = channelPremiumsPercent;
    }

    function setFlashLoanPremiumsPercent(uint256 flashLoanPremiumsPercent) public onlyOwner {
        FLASHLOAN_PREMIUMS_PERCENT = flashLoanPremiumsPercent;
    }

    function setStakingMintPercent(uint256 stakingMintPercent) public onlyOwner {
        STAKING_MINT_PERCENT = stakingMintPercent;
    }

    function setOraclePayoutRate(uint256 oraclePayoutRate) public onlyOwner {
        ORACLE_PAYOUT_RATE = oraclePayoutRate;
    }

    function setOracleNum(uint256 oracleNum) public onlyOwner {
        ORACLE_NUM = oracleNum;
    }

    function setOracleStageNum(uint256 oracleStageNum) public onlyOwner {
        ORACLE_STAGE_NUM = oracleStageNum;
    }

    function setOracleScheduleMultiplier(uint256 oracleScheduleMultiplier) public onlyOwner {
        ORACLE_SCHEDULE_MULTIPLIER = oracleScheduleMultiplier;
    }



    function setOracleValidPeriod(uint256 oracleValidPeriod) public onlyOwner {
        ORACLE_VALID_PERIOD = oracleValidPeriod;
    }

    function setITFAPY(uint256 itfApy) public onlyOwner {
        require(itfApy < 1000,"invalid itf APY");
        ITFAPY = itfApy;
    }

    function setPremiumsSharePercent(uint256 premiumsSharePercent) public onlyOwner {
        require(premiumsSharePercent < 1000,"invalid premiums share percent");
        PREMIUMS_SHARE_PERCENT = premiumsSharePercent;
    }

    function setProductWithdrawPercent(uint256 productWithdrawPercent) public onlyOwner {
        require(productWithdrawPercent < 1000,"invalid product withdraw percent");
        PRODUCT_WITHDRAW_PERCENT = productWithdrawPercent;
    }

    function setITFReleaseAccounts(address[4] memory itfReleaseAccounts, uint256[4] memory itfReleaseAccountMultipliers, uint256 itfReleaseDivisor) public onlyOwner {
        _itfReleaseAccountArray = itfReleaseAccounts;
        _itfReleaseAccountMultiplierArray = itfReleaseAccountMultipliers;
        _itfReleaseDivisor = itfReleaseDivisor;
    }

    function getITFReleaseAccountArray() public view returns(address[4] memory) {
        return _itfReleaseAccountArray;
    }

    function getITFReleaseAccountMultiplierArray() public view returns(uint256[4] memory) {
        return _itfReleaseAccountMultiplierArray;
    }

    function getITFReleaseDivisor() public view returns(uint256) {
        return _itfReleaseDivisor;
    }

    function setPriceNodePublicKey(address priceNodePublicKey) public onlyOwner {
        PRICE_NODE_PUBLIC_KEY = priceNodePublicKey;
    }

    function verifySign(bytes32 messageHash, address publicKey, uint256 expiresAt, uint8 v, bytes32 r, bytes32 s) public view returns(bool){
		require(expiresAt > now, "time expired");
        bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        address addr = ecrecover(prefixedHash, v, r, s);
        if(addr!=publicKey){
            prefixedHash = keccak256(abi.encodePacked("\x19Conflux Signed Message:\n32", messageHash));
            addr = ecrecover(prefixedHash, v, r, s);
        }
        return (addr==publicKey);
    }

    function initSponsor() external { 
        ISponsorWhiteListControl SPONSOR = ISponsorWhiteListControl(address(0x0888000000000000000000000000000000000001));
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

}