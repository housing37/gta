// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
library GTALib {
   /* -------------------------------------------------------- */
    /* STRUCTURES                                               */
    /* -------------------------------------------------------- */
    // LEFT OFF HERE ... migrate event structs over to GTADelegate
    //  maybe rename GTADelegate.sol to GTAEVent.sol ?

    /* _ GAME SUPPORT _ */
    struct GTAEvent {
        mapping(address => bool) guests; // true = registered 
        Event_0 event_0;
        Event_1 event_1;
        Event_2 event_2;
    }
    struct Event_0 {
        /** cons */
        address host;           // input param
        string gameName;        // input param
        uint32 entryFeeUSD;     // input param
        
        /** EVENT SUPPORT - mostly host set */
        uint256 createTime;     // 'createGame'
        uint256 createBlockNum; // 'createGame'
        uint256 startTime;      // host scheduled start time
        uint256 launchTime;     // 'hostStartEvent'
        uint256 launchBlockNum; // 'hostStartEvent'
        uint256 endTime;        // 'hostEndGameWithWinners'
        uint256 endBlockNum;    // 'hostEndGameWithWinners'
        uint256 expTime;        // expires if not launched by this time
        uint256 expBlockNum;    // 'cancelEventAndProcessRefunds'

        // mapping(address => bool) guests; // true = registered 
        // Event_1 event_1;
        // Event_2 event_2;
    }
    struct Event_1 { 
        // ------------------------------------------
        bool launched;  // 'hostStartEvent'
        bool ended;     // 'hostEndEventWithGuestRecipients'

        // ------------------------------------------
        // mapping(address => bool) guests; // true = registered 
        address[] guestAddresses; // traversal access
        uint32 guestCnt;       // length or guests; max 4,294,967,295

        /** host set */
        uint8 hostFeePerc;      // x% of prizePoolUSD

        // uint8 mintDistrPerc;    // % of ?
        
        /** _calcFeesAndPayouts */
        uint32 keeperFeeUSD;    // (entryFeeUSD * guestCnt) * keeperFeePerc
        uint32 serviceFeeUSD;   // (entryFeeUSD * guestCnt) * serviceFeePerc
        uint32 supportFeeUSD;   // (entryFeeUSD * guestCnt) * supportFeePerc
    }
    struct Event_2 { 
        uint32 totalFeesUSD;    // keeperFeeUSD + serviceFeeUSD + supportFeeUSD
        uint32 hostFeeUSD;      // prizePoolUSD * hostFeePerc
        uint32 prizePoolUSD;    // (entryFeeUSD * guestCnt) - totalFeesUSD - hostFeeUSD

        // ------------------------------------------
        uint8[] winPercs;       // %'s of prizePoolUSD - hostFeeUSD
        uint32[] payoutsUSD;    // prizePoolUSD * winPercs[]
        
        /** _calcFeesAndPayouts */
        uint32 keeperFeeUSD_ind;    // entryFeeUSD * keeperFeePerc
        uint32 serviceFeeUSD_ind;   // entryFeeUSD * serviceFeePerc
        uint32 supportFeeUSD_ind;   // entryFeeUSD * supportFeePerc
        uint32 totalFeesUSD_ind;    // keeperFeeUSD_ind + serviceFeeUSD_ind + supportFeeUSD_ind
        uint32 refundUSD_ind;       // entryFeeUSD - totalFeesUSD_ind
        uint32 refundsUSD;          // refundUSD_ind * evt.event_1.guestCnt
        uint32 hostFeeUSD_ind;      // (entryFeeUSD - totalFeesUSD_ind) * hostFeePerc

        uint32 buyGtaUSD;   // serviceFeeUSD * buyGtaPerc
    }

    /** _ DEFI SUPPORT _ */
    // used for deposits in keeper call to 'settleBalances'
    struct TxDeposit {
        address token;
        uint256 amount;
        address sender;
        address receiver;
    }

    function _addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) internal pure returns (address[] memory) {
        if (_addr == address(0)) { return _arr; }

        // safe = remove first (no duplicates)
        if (_safe) { _arr = _remAddressFromArray(_addr, _arr); }

        // perform add to memory array type w/ static size
        address[] memory _ret = new address[](_arr.length+1);
        for (uint i=0; i < _arr.length; i++) { _ret[i] = _arr[i]; }
        _ret[_ret.length] = _addr;
        return _ret;
    }
    function _remAddressFromArray(address _addr, address[] memory _arr) internal pure returns (address[] memory) {
        if (_addr == address(0) || _arr.length == 0) { return _arr; }
        
        // NOTE: remove algorithm does NOT maintain order & only removes first occurance
        for (uint i = 0; i < _arr.length; i++) {
            if (_addr == _arr[i]) {
                _arr[i] = _arr[_arr.length - 1];
                assembly { // reduce memory _arr length by 1 (simulate pop)
                    mstore(_arr, sub(mload(_arr), 1))
                }
                return _arr;
            }
        }
        return _arr;
    }
    function _isTokenInArray(address _addr, address[] memory _arr) external pure returns (bool) {
        if (_addr == address(0) || _arr.length == 0) { return false; }
        for (uint i=0; i < _arr.length; i++) {
            if (_addr == _arr[i]) { return true; }
        }
        return false;
    }
    function _getTotalsOfArray(uint8[] calldata _arr) internal pure returns (uint8) {
        uint8 t = 0;
        for (uint i=0; i < _arr.length; i++) { t += _arr[i]; }
        return t;
    }
    function _validatePercsInArr(uint8[] calldata _percs) internal pure returns (bool) {
        for (uint i=0; i < _percs.length; i++) { 
            if (!_validatePercent(_percs[i]))
                return false;
        } 
        return true;
    }
    function _validatePercent(uint8 _perc) private pure returns (bool) {
        return (0 < _perc && _perc <= 100);
    }
    function _generateAddressHash(address host, string memory uid) public pure returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));

        // LEFT OFF HERE ... is this a bug? 'uint160' ? shoudl be uint16? 
        address generatedAddress = address(uint160(uint256(hash)));
        return generatedAddress;
    }
}