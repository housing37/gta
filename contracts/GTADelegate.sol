// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;        
import "./GTASwapTools.sol"; // inheritance

// deploy
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
// import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// local _ $ npm install @openzeppelin/contracts @uniswap/v2-core @uniswap/v2-periphery
import "./node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./node_modules/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol"; 
import "./node_modules/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";

/* terminology...
                 join -> room, game, event, activity
             register -> guest, seat, player, delegates, users, participants, entrants
    payout/distribute -> rewards, winnings, earnings, recipients 
*/
contract GTADelegate is GTASwapTools {
    /* -------------------------------------------------------- */
    /* GLOBALS                                                  */
    /* -------------------------------------------------------- */
    /* _ ADMIN SUPPORT _ */
    address public keeper; // 37, curator, manager, caretaker, keeper
    address public contractGTA;
    address[] public supportStaff;

    /* _ DEX GLOBAL SUPPORT _ */
    address[] public uswapV2routers; // modifiers: addDexRouter/remDexRouter
        
    /* _ TOKEN SUPPORT _ */
    // arrays of accepted usd stable & alts for guest deposits
    address[] public whitelistAlts;
    address[] public whitelistStables;
    uint8 private whitelistStablesUseIdx; // _getNextStableTokDeposit()

    // track history of all stables & alts that this contract has ever whitelisted
    address[] private contractStables;
    address[] private contractAlts;

    // track this contract's stable token balances & debits (required for keeper 'SANITY CHECK')
    mapping(address => uint256) private contractBalances;
    mapping(address => uint256) private whitelistPendingDebits;

    // minimum deposits allowed (in usd value)
    //  set constant floor/ceiling so keeper can't lock people out
    uint32 public constant minDepositUSD_floor = 1; // 1 USD 
    uint32 public constant minDepositUSD_ceiling = 100; // 100 USD
    uint32 public minDepositUSD = 0; // dynamic (keeper controlled w/ 'setMinimumUsdValueDeposit')

    // enable/disable refunds for less than min deposit (keeper controlled)
    bool public enableMinDepositRefunds = true;

    // track gas fee wei losses due to min deposit refunds (keeper controlled reset)
    uint256 private accruedGasFeeRefundLoss = 0; 

    // min entryFeeUSD host can create event with (keeper control)
    uint32 public minEventEntryFeeUSD = 0; // uint32 max = 4,294,967,295

    // required GTA balance ratio to host game (ratio of entryFeeUSD desired)
    //  NOTE: can indeed be > 255% (ie. 2.55x entryFeeUSD, hence uint16 required)
    //   but, 65,535% max = host 'gta_bal' req of ~655x entryFeeUSD (in '_hostCanCreateEvent')
    //   hence, keeper needs to be limited to a lower max (for security)
    uint16 public hostGtaBalReqPerc = 100; // uint16 max = 65,535
    uint16 public constant hostGtaBalReqPercMax = 3000; // max ratio = 30:1 entryFeeUSD

    // GTA balance required in order to call public functions
    uint256 public infoGtaBalanceRequired = 10 * 10**18;
    uint256 public burnGtaBalanceRequired = 20 * 10**18;
    uint256 public cancelGtaBalanceRequired = 30 * 10**18;

    // max % of prizePoolUSD the host may charge (keeper controlled)
    uint8 public maxHostFeePerc = 100;

    // % of all deposits taken from 'creditsUSD' in 'settleBalances' (keeper controlled)
    uint256 public depositFeePerc = 0;

    // % of events total 'entryFeeUSD' collected (keeper controlled)
    uint8 public keeperFeePerc = 1; // 1% of event total entryFeeUSD
    uint8 public serviceFeePerc = 10; // 10% of event total entryFeeUSD
    uint8 public supportFeePerc = 0; // 0% of event total entryFeeUSD

    /* -------------------------------------------------------- */
    /* CONSTRUCTOR                                              */
    /* -------------------------------------------------------- */
    // NOTE: initialize before GTA.sol required
    //      sets keeper to msg.sender
    constructor() {
        keeper = msg.sender;
    }

    /* -------------------------------------------------------- */
    /* MODIFIERS                                                */
    /* -------------------------------------------------------- */
    modifier onlyKeeper() {
        require(msg.sender == keeper, "Only the keeper :p");
        _;
    }
    modifier onlyKeeperOrGTA() {
        require(msg.sender == contractGTA || msg.sender == keeper, "Only the keeper OR GTA contract :p");
        _;
    }

    /* -------------------------------------------------------- */
    /* PUBLIC ACCESSORS                                         */
    /* -------------------------------------------------------- */
    // function getWhitelistStables() external view returns (address[] memory) {
    //     return whitelistStables;
    // }
    // function getWhitelistAlts() external view returns (address[] memory) {
    //     return whitelistAlts;
    // }

    /* -------------------------------------------------------- */
    /* KEEPER - PUBLIC GETTERS / SETTERS                        */
    /* -------------------------------------------------------- */
    // GETTERS / SETTERS (keeper)
    function setKeeper(address _newKeeper) external onlyKeeper {
        require(_newKeeper != address(0), 'err: zero address ::)');
        keeper = _newKeeper;
    }
    function setContractGTA(address _gta) external onlyKeeper {
        require(_gta != address(0), 'err: zero address ::)');
        contractGTA = _gta;
    }
    function addSupportStaff(address _newStaff) external onlyKeeper {
        require(_newStaff != address(0), 'err: zero address ::)');
        supportStaff = _addAddressToArraySafe(_newStaff, supportStaff, true); // true = no dups
    }
    function remSupportStaff(address _remStaff) external onlyKeeper {
        require(_remStaff != address(0), 'err: zero address ::)');
        supportStaff = _remAddressFromArray(_remStaff, supportStaff);
    }
    function getSupportStaffWithIndFees(uint32 _totFee) external view onlyKeeperOrGTA returns (address[] memory, uint32[] memory) {
        // NOTE v1: simply divide _totFee evenly
        //  launch new GTADelegate.sol to change this
        uint32 indFee = _totFee / uint32(supportStaff.length);
        uint32[] memory indFees  = new uint32[](supportStaff.length);
        for (uint i=0; i < supportStaff.length; i++) {
            indFees[i] = indFee;
        }
        return (supportStaff, indFees);
    }
    
    function setInfoGtaBalRequired(uint256 _gtaBalReq) external onlyKeeper {
        infoGtaBalanceRequired = _gtaBalReq;
    }
    function setBurnGtaBalRequired(uint256 _gtaBalReq) external onlyKeeper {
        burnGtaBalanceRequired = _gtaBalReq;
    }
    // enable/disable refunds for less than min deposit (keeper controlled)
    function setEnableMinDepositRefunds(bool _enable) public onlyKeeper {
        enableMinDepositRefunds = _enable;
    }
    function setHostGtaBalReqPerc(uint16 _perc) public onlyKeeper {
        require(_perc <= hostGtaBalReqPercMax, 'err: required balance too high, check hostGtaBalReqPercMax :/');
        hostGtaBalReqPerc = _perc;
    }
    function setEntryFeePercs(uint8 _keeperPerc, uint8 _servicePerc, uint8 _supportPerc) public onlyKeeper {
        require(_keeperPerc <= 100 && _servicePerc <= 100 && _supportPerc <= 100, 'err: max 100%');
        keeperFeePerc = _keeperPerc;
        serviceFeePerc = _servicePerc;
        supportFeePerc = _supportPerc;
    }
    function setDepositFeePerc(uint8 _perc) public onlyKeeper {
        require(_perc <= 100, 'err: max 100%');
        depositFeePerc = _perc;
    }
    function setMaxHostFeePerc(uint8 _perc) public onlyKeeper returns (bool) {
        require(_perc <= 100, 'err: max 100%');
        maxHostFeePerc = _perc;
        return true;
    }
    function setMinimumEventEntryFeeUSD(uint32 _amountUSD) public onlyKeeper {
        require(_amountUSD > minDepositUSD, 'err: amount must be greater than minDepositUSD =)');
        minEventEntryFeeUSD = _amountUSD;
    }
    function addAccruedGFRL(uint256 _gasAmnt) external onlyKeeper returns (uint256) {
        accruedGasFeeRefundLoss += _gasAmnt;
        return accruedGasFeeRefundLoss;
    }
    function getAccruedGFRL() external view onlyKeeper returns (uint256) {
        return accruedGasFeeRefundLoss;
    }
    function resetAccruedGFRL() public onlyKeeper returns (bool) {
        require(accruedGasFeeRefundLoss > 0, 'err: AccruedGFRL already 0');
        accruedGasFeeRefundLoss = 0;
        return true;
    }
    function getContractStablesAndAlts() public view onlyKeeper returns (address[] memory, address[] memory) {
        return (contractStables, contractAlts); // tokens that have ever been whitelisted
    }
    
    // minimum deposits allowed (in usd value)
    //  set constant floor/ceiling so keeper can't lock people out
    function setMinimumUsdValueDeposit(uint32 _amountUSD) public onlyKeeper {
        require(minDepositUSD_floor <= _amountUSD && _amountUSD <= minDepositUSD_ceiling, 'err: invalid amount =)');
        minDepositUSD = _amountUSD;
    }
    function updateWhitelistStables(address[] calldata _tokens, bool _add) public onlyKeeper { // allows duplicates
        // NOTE: integration allows for duplicate addresses in 'whitelistStables'
        //        hence, simply pass dups in '_tokens' as desired (for both add & remove)
        for (uint i=0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), 'err: found zero address to update :L');
            if (_add) {
                whitelistStables = _addAddressToArraySafe(_tokens[i], whitelistStables, false); // false = allow dups
                contractStables = _addAddressToArraySafe(_tokens[i], contractStables, true); // true = no dups
            } else {
                whitelistStables = _remAddressFromArray(_tokens[i], whitelistStables);
            }
        }
    }
    function updateWhitelistAlts(address[] calldata _tokens, bool _add) public onlyKeeper { // no dups allowed
        for (uint i=0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), 'err: found zero address for update :L');
            if (_add) {
                whitelistAlts = _addAddressToArraySafe(_tokens[i], whitelistAlts, true); // true = no dups
                contractAlts = _addAddressToArraySafe(_tokens[i], contractAlts, true); // true = no dups
            } else {
                whitelistAlts = _remAddressFromArray(_tokens[i], whitelistAlts);   
            }
        }
    }
    function addDexRouter(address _router) public onlyKeeper {
        require(_router != address(0x0), "err: invalid address");
        uswapV2routers = _addAddressToArraySafe(_router, uswapV2routers, true); // true = no dups
    }
    function remDexRouter(address router) public onlyKeeper returns (bool) {
        require(router != address(0x0), "err: invalid address");

        // NOTE: remove algorithm does NOT maintain order
        uswapV2routers = _remAddressFromArray(router, uswapV2routers);
        return true;
    }

    /* -------------------------------------------------------- */
    /* KEEPER - ACCESSORS TO PRIVATES                           */
    /* -------------------------------------------------------- */
    function getNextStableTokDeposit() external onlyKeeper returns (address) {
        return _getNextStableTokDeposit(); // increments 'whitelistStablesUseIdx'
    }
    function addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) external pure returns (address[] memory) {
        // NOTE: no require checks needed
        return _addAddressToArraySafe(_addr, _arr, _safe);
    }
    function remAddressFromArray(address _addr, address[] memory _arr) external pure returns (address[] memory) {
        // NOTE: no require checks needed
        return _remAddressFromArray(_addr, _arr);
    }

    /* -------------------------------------------------------- */
    /* PRIVATE - EVENT SUPPORTING                               */
    /* -------------------------------------------------------- */
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

    // LEFT OFF HERE ... should review what functions in GTADelegate.sol, are only used in GTA.sol
    //      ... and think about that organizational design 
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

    // get lowest market value stable
    function _getBestDebitStableUSD(uint32 _amountUSD) external view onlyKeeper returns (address) {
        // loop through 'whitelistStables', generate stables available (bals ok for debit)
        address[] memory stables_avail = _getStableTokensAvailDebit(_amountUSD);

        // traverse stables available for debit, select stable w/ the lowest market value            
        address stable = _getStableTokenLowMarketValue(stables_avail, uswapV2routers);
        require(stable != address(0), 'err: low market stable address is 0 _ :+0');
        return stable;
    }

    function _generateAddressHash(address host, string memory uid) external pure returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));

        // LEFT OFF HERE ... is this a bug? 'uint160' ? shoudl be uint16? 
        address generatedAddress = address(uint160(uint256(hash)));
        return generatedAddress;
    }

    /* -------------------------------------------------------- */
    /* PRIVATE - BOOK KEEPING                                   */
    /* -------------------------------------------------------- */
    // traverse 'whitelistStables' using 'whitelistStablesUseIdx'
    function _getNextStableTokDeposit() private returns (address) {
        address stable_addr = whitelistStables[whitelistStablesUseIdx];
        whitelistStablesUseIdx++;
        if (whitelistStablesUseIdx >= whitelistStables.length) { whitelistStablesUseIdx=0; }
        return stable_addr;
    }

    // keeper SANITY CHECK for 'settleBalances->processContractDebitsAndCredits'
    // verify keeper calc 'contractBalances' == on-chain balances
    //  for all 'whitelistStables' (NOTE: 1 FAIL = return false)
    function contractStablesSanityCheck() external view onlyKeeperOrGTA returns (bool) {
        for (uint i=0; i < whitelistStables.length; i++) {
            address tok = whitelistStables[i];
            uint256 chainBal = IERC20(tok).balanceOf(contractGTA);
            if (contractBalances[tok] != chainBal) { return false; }
        }
        return true;
    }

    function processContractDebitsAndCredits(address _token, uint256 _amnt) external onlyKeeperOrGTA {
        _settlePendingDebits(_token); // sync 'contractBalances' w/ 'whitelistPendingDebits'
        _processIncommingTransfer(_token, _amnt); // sync 'contractBalances' w/ this 'Transfer' emit
    }

    // deduct debits accrued from 'hostEndEventWithGuestRecipients'
    function _settlePendingDebits(address _token) private {
        require(contractBalances[_token] >= whitelistPendingDebits[_token], 'err: insefficient balance to settle debit :O');
        contractBalances[_token] -= whitelistPendingDebits[_token];
        delete whitelistPendingDebits[_token];
    }

    // update stable balance from IERC20 'Transfer' emit (delegated by keeper -> 'settleBalances')
    function _processIncommingTransfer(address _token, uint256 _amount) private {
        require(_token != address(0), 'err: no address :{');
        require(_amount != 0, 'err: no amount :{');
        contractBalances[_token] += _amount;
    }

    // aggregate debits incurred from 'hostEndEventWithGuestRecipients'; syncs w/ 'settleBalances' algorithm
    function _increaseWhitelistPendingDebit(address token, uint256 amount) external onlyKeeper {
        whitelistPendingDebits[token] += amount;
    }

    /* -------------------------------------------------------- */
    /* PRIVATE - DEX SUPPORT                                    */
    /* -------------------------------------------------------- */
    // NOTE: *WARNING* 'whitelistStables' could have duplicates (hence, using '_addAddressToArraySafe')
    function _getStableTokensAvailDebit(uint32 _debitAmntUSD) private view returns (address[] memory) {
        // loop through white list stables, generate stables available (ok for debit)
        address[] memory stables_avail;
        for (uint i = 0; i < whitelistStables.length; i++) {

            // get balnce for this whitelist stable (push to stablesAvail if has enough)
            uint256 stableBal = IERC20(whitelistStables[i]).balanceOf(address(this));
            if (stableBal >= _debitAmntUSD * 10**18) { 
                stables_avail = _addAddressToArraySafe(whitelistStables[i], stables_avail, true); // true = no dups
            }
        }
        return stables_avail;
    }
}
