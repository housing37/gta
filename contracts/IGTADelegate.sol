// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "./IGTALib.sol"; // interface for struct GTAEvent
interface IGTADelegate {
    // public auto-generated getter
    function keeper() external view returns (address);
    function uswapV2routers() external view returns (address[] memory);
    function infoGtaBalanceRequired() external view returns (uint256); 
    function burnGtaBalanceRequired() external view returns (uint256);
    function cancelGtaBalanceRequired() external view returns (uint256);
    function minDepositForAltsUSD() external view returns (uint32);
    function hostGtaBalReqPerc() external view returns (uint8);
    function depositFeePerc() external view returns (uint8);
    function whitelistStables() external view returns (address[] memory);
    function whitelistAlts() external view returns (address[] memory);
    function enableMinDepositRefundsForAlts() external view returns(bool);
    function activeEventCount() external view returns (uint64);
    function burnGtaPerc() external view returns (uint8);
    function mintGtaPerc() external view returns (uint8);
    function mintGtaToHost() external view returns (bool);
    function BURN_CODE_GUESS_CNT() external view returns (uint64);
    function USE_BURN_CODE_HARD() external view returns (bool);
    function GET_BURN_CODES() external view returns (uint32[2] memory);
    function SET_BURN_CODE_GUESS_CNT(uint64 _cnt) external;
    
    // public access
    function _generateAddressHash(address host, string memory uid) external view returns (address);
    // function addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) external pure returns (address[] memory);
    // function remAddressFromArray(address _addr, address[] memory _arr) external pure returns (address[] memory);
    function _isTokenInArray(address _addr, address[] memory _arr) external pure returns (bool);

    // onlyKeeper access
    function _increaseWhitelistPendingDebit(address token, uint256 amount) external;
    function processContractDebitsAndCredits(address _token, uint256 _amnt) external;
    function contractStablesSanityCheck() external view returns (bool);
    function getNextStableTokDeposit() external returns (address);
    function addAccruedGFRL(uint256 _gasAmnt) external returns (uint256);
    function getAccruedGFRL() external view returns (uint256);
    function getSwapRouters() external view returns (address[] memory);
    function getSupportStaffWithIndFees(uint32 _totFee) external view returns (address[] calldata, uint32[] calldata);
    function setContractGTA(address _gta) external;
    function _addGuestToEvent(address _guest, address _evtCode) external;
    function _endEvent(address _evtCode) external;

    function getActiveEvent_0(address _evtCode) external view returns (IGTALib.Event_0 calldata);
    function getActiveEvent_1(address _evtCode) external view returns (IGTALib.Event_1 calldata);
    function getActiveEvent_2(address _evtCode) external view returns (IGTALib.Event_2 calldata);
    function isGuestRegistered(address _evtCode, address _guest) external view returns (bool);
    function _getPublicActiveEventDetails(address _evtCode) external view returns (address, address, string memory, uint32, uint8[] memory, uint8, uint256, uint256, uint256, uint256);
    function createNewEvent(string memory _eventName, uint256 _startTime, uint32 _entryFeeUSD, uint8 _hostFeePerc, uint8[] calldata _winPercs) external returns (address, uint256);
    function _calcFeesAndPayouts(address _evtCode) external;
    function _launchEvent(address _evtCode) external;
    function _getStableTokensAvailDebit(uint32 _debitAmntUSD) external view returns (address[] memory);
    function _getGameCode(address _host, string memory _evtName) external view returns (address);
    function _getPlayers(address _evtCode) external view returns (address[] memory);
}