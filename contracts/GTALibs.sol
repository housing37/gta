// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
library GTALib {
    function addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) external pure returns (address[] memory) {
        // NOTE: no require checks needed
        return _addAddressToArraySafe(_addr, _arr, _safe);
    }
    function remAddressFromArray(address _addr, address[] memory _arr) external pure returns (address[] memory) {
        // NOTE: no require checks needed
        return _remAddressFromArray(_addr, _arr);
    }
    function _addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) private pure returns (address[] memory) {
        if (_addr == address(0)) { return _arr; }

        // safe = remove first (no duplicates)
        if (_safe) { _arr = _remAddressFromArray(_addr, _arr); }

        // perform add to memory array type w/ static size
        address[] memory _ret = new address[](_arr.length+1);
        for (uint i=0; i < _arr.length; i++) { _ret[i] = _arr[i]; }
        _ret[_ret.length] = _addr;
        return _ret;
    }
    function _remAddressFromArray(address _addr, address[] memory _arr) private pure returns (address[] memory) {
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
    function _getTotalsOfArray(uint8[] calldata _arr) external pure returns (uint8) {
        uint8 t = 0;
        for (uint i=0; i < _arr.length; i++) { t += _arr[i]; }
        return t;
    }
    function _validatePercsInArr(uint8[] calldata _percs) external pure returns (bool) {
        for (uint i=0; i < _percs.length; i++) { 
            if (!_validatePercent(_percs[i]))
                return false;
        } 
        return true;
    }
    function _validatePercent(uint8 _perc) private pure returns (bool) {
        return (0 < _perc && _perc <= 100);
    }
    function _generateAddressHash(address host, string memory uid) external pure returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));

        // LEFT OFF HERE ... is this a bug? 'uint160' ? shoudl be uint16? 
        address generatedAddress = address(uint160(uint256(hash)));
        return generatedAddress;
    }
}