// SPDX-License-Identifier: UNLICENSED
// NOTE: code size limit = 24576 bytes (a limit introduced in Spurious Dragon _ 2016)
// NOTE: code size limit = 49152 bytes (a limit introduced in Shanghai _ 2023)
pragma solidity ^0.8.20;

// interfaces
import "./IGTALib.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // deploy
import "./node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol"; // local

/* terminology...
                 join -> room, game, event, activity
             register -> guest, seat, player, delegates, users, participants, entrants
    payout/distribute -> rewards, winnings, earnings, recipients 
*/
// contract GTADelegate is GTASwapTools {
contract GTADelegate {
    IGTALib private GTAL;

    /* -------------------------------------------------------- */
    /* GLOBALS                                                  */
    /* -------------------------------------------------------- */
    /* _ GAME SUPPORT _ */
    // map generated gameCode address to Game struct
    mapping(address => IGTALib.GTAEvent) private activeEvents;
    
    // track activeEventCount using 'createGame' & '_endEvent'
    uint64 public activeEventCount = 0; 

    // track activeEventCodes array for keeper 'keeperGetGameCodes'
    address[] public activeEventCodes = new address[](0);

    // track transfer of active events to dead events
    mapping(address => IGTALib.GTAEvent) private closedEvents;
    uint64 private closedEventCount = 0; 
    address[] private closedEventCodes = new address[](0);

    // event experation time (keeper control); uint32 max = 4,294,967,295 (~49,710 days)
    //  BUT, block.timestamp is express in seconds since 1970 as uint256
    uint256 private eventExpSec = 86400 * 1; // 1 day = 86400 seconds 

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
    uint32 public constant minDepositForAltsUSD_floor = 1; // 1 USD 
    uint32 public constant minDepositForAltsUSD_ceiling = 100; // 100 USD
    uint32 public minDepositForAltsUSD = 0; // dynamic (keeper controlled w/ 'setMinimumUsdValueDeposit')
    bool public enableMinDepositRefundsForAlts = true; // enable/disable refunds for < minDepositForAltsUSD (keeper controlled)

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

    /* _ BUY & BURN & MINT SUPPORT _ */
    // % of event 'serviceFeeUSD' to use to buy & burn GTA (keeper controlled)
    //  and % of buy & burn GTA to mint for winners
    // NOTE: 'ensures GTA amount burned' > 'GTA amount mint' (per event)
    uint8 public buyGtaPerc = 50; // % of total 'serviceFeeUSD' collected (set to buyGtaUSD)
    uint8 public burnGtaPerc = 50; // % of total GTA token held by this contract (to burn)
    uint8 public mintGtaPerc = 50; // % of GTA allocated from 'serviceFeeUSD' (minted/divided to winners)
    bool public mintGtaToHost = true; // host included in mintGtaPerc (calc in 'hostEndEventWithGuestRecipients')

    // code required for 'burnGTA'
    //  EASY -> uint16: 65,535 (~1day=86,400 @ 10s blocks w/ 1 wallet)
    //  HARD -> uint32: 4,294,967,295 (~100yrs=3,110,400,00 @ 10s blocks w/ 1 wallet)
    uint16 private BURN_CODE_EASY;
    uint32 private BURN_CODE_HARD; 
    uint64 public BURN_CODE_GUESS_CNT = 0;
    bool public USE_BURN_CODE_HARD = false;
    
    // notify clients a new burn code is set with type (easy, hard)
    event BurnCodeReset(bool setToHard);

    /* -------------------------------------------------------- */
    /* CONSTRUCTOR                                              */
    /* -------------------------------------------------------- */
    // NOTE: initialize before GTA.sol required
    //      sets keeper to msg.sender
    constructor(address _gtal) {
        keeper = msg.sender;
        GTAL = IGTALib(_gtal);
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

    /* -------------------------------------------------------- */
    /* KEEPER - PUBLIC GETTERS / SETTERS                        */
    /* -------------------------------------------------------- */
    // '_burnGTA' support
    function keeperResetBurnCodeEasy(uint16 bc) external onlyKeeper {
        require(bc != BURN_CODE_EASY, 'err: same burn code, no changes made ={}');
        BURN_CODE_EASY = bc;
        USE_BURN_CODE_HARD = false;
        emit BurnCodeReset(USE_BURN_CODE_HARD);
    }
    function keeperResetBurnCodeHard(uint32 bc) external onlyKeeper {
        require(bc != BURN_CODE_HARD, 'err: same burn code, no changes made ={}');
        BURN_CODE_HARD = bc;
        USE_BURN_CODE_HARD = true;
        emit BurnCodeReset(USE_BURN_CODE_HARD);
    }
    function keeperSetBurnCodeHard(bool _hard) external onlyKeeper {
        USE_BURN_CODE_HARD = _hard;
        emit BurnCodeReset(USE_BURN_CODE_HARD);
    }
    function GET_BURN_CODES() external view onlyKeeperOrGTA returns (uint32[2] memory) {
        return [uint32(BURN_CODE_EASY), BURN_CODE_HARD];
    }
    function SET_BURN_CODE_GUESS_CNT(uint64 _cnt) external onlyKeeperOrGTA {
        BURN_CODE_GUESS_CNT = _cnt;
    }

    // GETTERS / SETTERS (keeper)
    function keeperGetGameCodes() external view onlyKeeper returns (address[] memory, uint64) {
        return (activeEventCodes, activeEventCount);
    }
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
        supportStaff = GTAL.addAddressToArraySafe(_newStaff, supportStaff, true); // true = no dups
    }
    function remSupportStaff(address _remStaff) external onlyKeeper {
        require(_remStaff != address(0), 'err: zero address ::)');
        supportStaff = GTAL.remAddressFromArray(_remStaff, supportStaff);
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
    
    function setBuyGtaPerc(uint8 _perc) external onlyKeeper {
        buyGtaPerc = _perc;
    }
    function setBurnGtaPerc(uint8 _perc) external onlyKeeper {
        burnGtaPerc = _perc;
    }
    function setMintGtaPerc(uint8 _perc) external onlyKeeper {
        mintGtaPerc = _perc;
    }
    function setMintGtaToHost(bool _mintToHost) external onlyKeeper {
        mintGtaToHost = _mintToHost;
    }
    function setInfoGtaBalRequired(uint256 _gtaBalReq) external onlyKeeper {
        infoGtaBalanceRequired = _gtaBalReq;
    }
    function setBurnGtaBalRequired(uint256 _gtaBalReq) external onlyKeeper {
        burnGtaBalanceRequired = _gtaBalReq;
    }
    // enable/disable refunds for less than min deposit (keeper controlled)
    function setEnableMinDepositRefunds(bool _enable) external onlyKeeper {
        enableMinDepositRefundsForAlts = _enable;
    }
    function setHostGtaBalReqPerc(uint16 _perc) external onlyKeeper {
        require(_perc <= hostGtaBalReqPercMax, 'err: required balance too high, check hostGtaBalReqPercMax :/');
        hostGtaBalReqPerc = _perc;
    }
    function setEntryFeePercs(uint8 _keeperPerc, uint8 _servicePerc, uint8 _supportPerc) external onlyKeeper {
        require(_keeperPerc <= 100 && _servicePerc <= 100 && _supportPerc <= 100, 'err: max 100%');
        keeperFeePerc = _keeperPerc;
        serviceFeePerc = _servicePerc;
        supportFeePerc = _supportPerc;
    }
    function setDepositFeePerc(uint8 _perc) external onlyKeeper {
        require(_perc <= 100, 'err: max 100%');
        depositFeePerc = _perc;
    }
    function setMaxHostFeePerc(uint8 _perc) external onlyKeeper returns (bool) {
        require(_perc <= 100, 'err: max 100%');
        maxHostFeePerc = _perc;
        return true;
    }
    function setMinimumEventEntryFeeUSD(uint32 _amountUSD) external onlyKeeper {
        require(_amountUSD > minDepositForAltsUSD, 'err: amount must be greater than minDepositForAltsUSD =)');
        minEventEntryFeeUSD = _amountUSD;
    }
    function addAccruedGFRL(uint256 _gasAmnt) external onlyKeeper returns (uint256) {
        accruedGasFeeRefundLoss += _gasAmnt;
        return accruedGasFeeRefundLoss;
    }
    function getAccruedGFRL() external view onlyKeeper returns (uint256) {
        return accruedGasFeeRefundLoss;
    }
    function resetAccruedGFRL() external onlyKeeper returns (bool) {
        require(accruedGasFeeRefundLoss > 0, 'err: AccruedGFRL already 0');
        accruedGasFeeRefundLoss = 0;
        return true;
    }
    function getContractStablesAndAlts() external view onlyKeeper returns (address[] memory, address[] memory) {
        return (contractStables, contractAlts); // tokens that have ever been whitelisted
    }
    
    // minimum deposits allowed (in usd value)
    //  set constant floor/ceiling so keeper can't lock people out
    function setMinimumUsdValueDeposit(uint32 _amountUSD) external onlyKeeper {
        require(minDepositForAltsUSD_floor <= _amountUSD && _amountUSD <= minDepositForAltsUSD_ceiling, 'err: invalid amount =)');
        minDepositForAltsUSD = _amountUSD;
    }
    function updateWhitelistStables(address[] calldata _tokens, bool _add) external onlyKeeper { // allows duplicates
        // NOTE: integration allows for duplicate addresses in 'whitelistStables'
        //        hence, simply pass dups in '_tokens' as desired (for both add & remove)
        for (uint i=0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), 'err: found zero address to update :L');
            if (_add) {
                whitelistStables = GTAL.addAddressToArraySafe(_tokens[i], whitelistStables, false); // false = allow dups
                contractStables = GTAL.addAddressToArraySafe(_tokens[i], contractStables, true); // true = no dups
            } else {
                whitelistStables = GTAL.remAddressFromArray(_tokens[i], whitelistStables);
            }
        }
    }
    function updateWhitelistAlts(address[] calldata _tokens, bool _add) external onlyKeeper { // no dups allowed
        for (uint i=0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0), 'err: found zero address for update :L');
            if (_add) {
                whitelistAlts = GTAL.addAddressToArraySafe(_tokens[i], whitelistAlts, true); // true = no dups
                contractAlts = GTAL.addAddressToArraySafe(_tokens[i], contractAlts, true); // true = no dups
            } else {
                whitelistAlts = GTAL.remAddressFromArray(_tokens[i], whitelistAlts);   
            }
        }
    }
    function addDexRouter(address _router) external onlyKeeper {
        require(_router != address(0x0), "err: invalid address");
        uswapV2routers = GTAL.addAddressToArraySafe(_router, uswapV2routers, true); // true = no dups
    }
    function remDexRouter(address router) external onlyKeeper returns (bool) {
        require(router != address(0x0), "err: invalid address");

        // NOTE: remove algorithm does NOT maintain order
        uswapV2routers = GTAL.remAddressFromArray(router, uswapV2routers);
        return true;
    }

    /* -------------------------------------------------------- */
    /* KEEPER - ACCESSORS TO PRIVATES                           */
    /* -------------------------------------------------------- */
    function getNextStableTokDeposit() external onlyKeeper returns (address) {
        return _getNextStableTokDeposit(); // increments 'whitelistStablesUseIdx'
    }
    // function addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) external pure returns (address[] memory) {
    //     // NOTE: no require checks needed
    //     return GTAL.addAddressToArraySafe(_addr, _arr, _safe);
    // }
    // function remAddressFromArray(address _addr, address[] memory _arr) external pure returns (address[] memory) {
    //     // NOTE: no require checks needed
    //     return GTAL.remAddressFromArray(_addr, _arr);
    // }

    /* -------------------------------------------------------- */
    /* PRIVATE - EVENT SUPPORTING                               */
    /* -------------------------------------------------------- */
    // // get lowest market value stable
    // function _getBestDebitStableUSD(uint32 _amountUSD) external view onlyKeeper returns (address) {
    //     // loop through 'whitelistStables', generate stables available (bals ok for debit)
    //     address[] memory stables_avail = _getStableTokensAvailDebit(_amountUSD);

    //     // traverse stables available for debit, select stable w/ the lowest market value            
    //     address stable = _getStableTokenLowMarketValue(stables_avail, uswapV2routers);
    //     require(stable != address(0), 'err: low market stable address is 0 _ :+0');
    //     return stable;
    // }

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
    // NOTE: *WARNING* 'whitelistStables' could have duplicates (hence, using 'addAddressToArraySafe')
    function _getStableTokensAvailDebit(uint32 _debitAmntUSD) external view returns (address[] memory) {
        // loop through white list stables, generate stables available (ok for debit)
        address[] memory stables_avail;
        for (uint i = 0; i < whitelistStables.length; i++) {

            // get balnce for this whitelist stable (push to stablesAvail if has enough)
            uint256 stableBal = IERC20(whitelistStables[i]).balanceOf(address(this));
            if (stableBal >= _debitAmntUSD * 10**18) { 
                stables_avail = GTAL.addAddressToArraySafe(whitelistStables[i], stables_avail, true); // true = no dups
            }
        }
        return stables_avail;
    }
    function _addGuestToEvent(address _guest, address _evtCode) external onlyKeeperOrGTA() {
        IGTALib.GTAEvent storage gtaEvt = activeEvents[_evtCode];
        gtaEvt.guests[_guest] = true;
        gtaEvt.event_1.guestAddresses.push(_guest);
        gtaEvt.event_1.guestCnt = uint32(gtaEvt.event_1.guestAddresses.length);
    }

    // set event param to end state
    function _endEvent(address _evtCode) external onlyKeeperOrGTA() {
        require(_evtCode != address(0) && activeEvents[_evtCode].event_0.host != address(0), 'err: invalid event code :P');
        require(activeEvents[_evtCode].event_1.launched, 'err: event not launched');

        IGTALib.GTAEvent storage _evt = activeEvents[_evtCode];
        // set game end state (doesn't matter if its about to be deleted)
        _evt.event_0.endTime = block.timestamp;
        _evt.event_0.endBlockNum = block.number;
        _evt.event_1.ended = true;

        // transfer from activeEvents to closedEvents & delete from activeEvents
        _migrateToClosedEvents(_evtCode);
    }
    function _migrateToClosedEvents(address _evtCode) private {
        // copies to closedEvents, appends to closedEventCodes, increments closedEventCount
        _copyActiveEventToClosedEvent(_evtCode); 

        // delete from activeEvents, removes from activeEventCodes, decrements activeEventCount
        _deleteActiveEvent(_evtCode); 
    }
    function _deleteActiveEvent(address _evtCode) private {
        require(_evtCode != address(0) && activeEvents[_evtCode].event_0.host != address(0), 'err: invalid event code :/');
        delete activeEvents[_evtCode]; // delete event mapping
        activeEventCodes = GTAL.remAddressFromArray(_evtCode, activeEventCodes);
        activeEventCount--;
    }
    function _deleteClosedEvent(address _evtCode) private {
        require(_evtCode != address(0) && closedEvents[_evtCode].event_0.host != address(0), 'err: invalid event code :/');
        delete closedEvents[_evtCode]; // delete event mapping
        closedEventCodes = GTAL.remAddressFromArray(_evtCode, closedEventCodes);
        closedEventCount--;
    }
    function _copyActiveEventToClosedEvent(address _evtCode) private {
        // append to closedEventCodes array & increment closedEventCount (traversal support)
        closedEventCodes = GTAL.addAddressToArraySafe(_evtCode, closedEventCodes, true); // true = no dups
        closedEventCount++;

        // Copy values to closedEvents
        closedEvents[_evtCode].event_0.host = activeEvents[_evtCode].event_0.host;
        closedEvents[_evtCode].event_0.gameName = activeEvents[_evtCode].event_0.gameName;
        closedEvents[_evtCode].event_0.entryFeeUSD = activeEvents[_evtCode].event_0.entryFeeUSD;
        closedEvents[_evtCode].event_0.createTime = activeEvents[_evtCode].event_0.createTime;
        closedEvents[_evtCode].event_0.createBlockNum = activeEvents[_evtCode].event_0.createBlockNum;
        closedEvents[_evtCode].event_0.startTime = activeEvents[_evtCode].event_0.startTime;
        closedEvents[_evtCode].event_0.launchTime = activeEvents[_evtCode].event_0.launchTime;
        closedEvents[_evtCode].event_0.launchBlockNum = activeEvents[_evtCode].event_0.launchBlockNum;
        closedEvents[_evtCode].event_0.endTime = activeEvents[_evtCode].event_0.endTime;
        closedEvents[_evtCode].event_0.endBlockNum = activeEvents[_evtCode].event_0.endBlockNum;
        closedEvents[_evtCode].event_0.expTime = activeEvents[_evtCode].event_0.expTime;
        closedEvents[_evtCode].event_0.expBlockNum = activeEvents[_evtCode].event_0.expBlockNum;
        
        // Explicitly copy event_1 values
        closedEvents[_evtCode].event_1.launched = activeEvents[_evtCode].event_1.launched;
        closedEvents[_evtCode].event_1.ended = activeEvents[_evtCode].event_1.ended;
        closedEvents[_evtCode].event_1.hostFeePerc = activeEvents[_evtCode].event_1.hostFeePerc;
        closedEvents[_evtCode].event_1.keeperFeeUSD = activeEvents[_evtCode].event_1.keeperFeeUSD;
        closedEvents[_evtCode].event_1.serviceFeeUSD = activeEvents[_evtCode].event_1.serviceFeeUSD;
        closedEvents[_evtCode].event_1.supportFeeUSD = activeEvents[_evtCode].event_1.supportFeeUSD;

        // Manually copy guest address array, guest count, & guests mapping (event registration & traversal support) 
        closedEvents[_evtCode].event_1.guestAddresses = activeEvents[_evtCode].event_1.guestAddresses;
        closedEvents[_evtCode].event_1.guestCnt = activeEvents[_evtCode].event_1.guestCnt;
        address[] memory pAddies = activeEvents[_evtCode].event_1.guestAddresses;
        for (uint256 i = 0; i < pAddies.length; i++) {
            closedEvents[_evtCode].guests[pAddies[i]] = true; // true = registered 
        }

        // Explicitly copy event_2 values
        closedEvents[_evtCode].event_2.totalFeesUSD = activeEvents[_evtCode].event_2.totalFeesUSD;
        closedEvents[_evtCode].event_2.hostFeeUSD = activeEvents[_evtCode].event_2.hostFeeUSD;
        closedEvents[_evtCode].event_2.prizePoolUSD = activeEvents[_evtCode].event_2.prizePoolUSD;
        closedEvents[_evtCode].event_2.winPercs = activeEvents[_evtCode].event_2.winPercs;
        closedEvents[_evtCode].event_2.payoutsUSD = activeEvents[_evtCode].event_2.payoutsUSD;
        closedEvents[_evtCode].event_2.keeperFeeUSD_ind = activeEvents[_evtCode].event_2.keeperFeeUSD_ind;
        closedEvents[_evtCode].event_2.serviceFeeUSD_ind = activeEvents[_evtCode].event_2.serviceFeeUSD_ind;
        closedEvents[_evtCode].event_2.supportFeeUSD_ind = activeEvents[_evtCode].event_2.supportFeeUSD_ind;
        closedEvents[_evtCode].event_2.totalFeesUSD_ind = activeEvents[_evtCode].event_2.totalFeesUSD_ind;
        closedEvents[_evtCode].event_2.refundUSD_ind = activeEvents[_evtCode].event_2.refundUSD_ind;
        closedEvents[_evtCode].event_2.refundsUSD = activeEvents[_evtCode].event_2.refundsUSD;
        closedEvents[_evtCode].event_2.hostFeeUSD_ind = activeEvents[_evtCode].event_2.hostFeeUSD_ind;
        closedEvents[_evtCode].event_2.buyGtaUSD = activeEvents[_evtCode].event_2.buyGtaUSD;
    }
    function keeperDeleteClosedEvent(address _evtCode) external onlyKeeper {
        require(_evtCode != address(0) && closedEvents[_evtCode].event_0.host != address(0), 'err: invalid event code :/');

        // delete from closedEvents, removes from closedEventCodes, decrements closedEventCount
        _deleteClosedEvent(_evtCode);
    }
    function keeperCleanOutClosedEvents() external onlyKeeper {
        for (uint i; i < closedEventCodes.length; i++) {
            // NOTE: no error check for address(0), want to clean regardless            
            delete closedEvents[closedEventCodes[i]]; // delete event mapping
        }

        // NOTE: simply wipe closedEventCodes all at once after closedEvents mapping is cleaned
        //  *DO NOT ALTER closedEventCodes array while looping through it*
        closedEventCodes = new address[](0);
        closedEventCount = 0;
    }
    function keeperSetGameExpSec(uint256 _sec) external onlyKeeper {
        require(_sec > 0, 'err: no zero :{}');
        eventExpSec = _sec;
    }
    function createNewEvent(string memory _eventName, uint256 _startTime, uint32 _entryFeeUSD, uint8 _hostFeePerc, uint8[] calldata _winPercs) external onlyKeeperOrGTA() returns (address, uint256) {
        require(_startTime > block.timestamp, "err: start too soon :/");
        require(_entryFeeUSD >= minEventEntryFeeUSD, "err: entry fee too low :/");
        require(_hostFeePerc <= maxHostFeePerc, 'err: host fee too high :O, check maxHostFeePerc');
        require(_winPercs.length >= 0, 'err: _winPercs.length, SHOULD NOT OCCUR :/'); // NOTE: _winPercs.length = 0, means no winners paid
        require(GTAL._validatePercsInArr(_winPercs), 'err: invalid _winPercs; only 1 -> 100 allowed <=[]'); // NOTE: _winPercs.length = 0, return true
        require(GTAL._getTotalsOfArray(_winPercs) + _hostFeePerc == 100, 'err: _winPercs + _hostFeePerc != 100 (total 100% required) :/');

        // SAFE-ADD
        uint256 expTime = _startTime + eventExpSec;
        require(expTime > _startTime, "err: stop f*ckin around :X");

        // verify name/code doesn't yet exist in 'activeEvents'
        address eventCode = GTAL._generateAddressHash(msg.sender, _eventName);
        require(activeEvents[eventCode].event_0.host == address(0), 'err: game name already exists :/');

        // Creates a default empty 'IGTALib.Event_0' struct for 'eventCode' (doesn't exist yet)
        //  NOTE: declaring storage ref to a struct, works directly w/ storage slot that the struct occupies. 
        //    ie. modifying the newEvent will indeed directly affect the state stored in activeEvents[eventCode].
        IGTALib.GTAEvent storage newEvent = activeEvents[eventCode];
    
        // set properties for default empty 'Game' struct
        newEvent.event_0.host = msg.sender;
        newEvent.event_0.gameName = _eventName;
        newEvent.event_0.entryFeeUSD = _entryFeeUSD;
        newEvent.event_2.winPercs = _winPercs; // [%_1st_place, %_2nd_place, ...] = prizePoolUSD - hostFeePerc
        newEvent.event_1.hostFeePerc = _hostFeePerc; // hostFeePerc = prizePoolUSD - winPercs
        newEvent.event_0.createTime = block.timestamp;
        newEvent.event_0.createBlockNum = block.number;
        newEvent.event_0.startTime = _startTime;
        newEvent.event_0.expTime = expTime;

        // increment support
        activeEventCodes = GTAL.addAddressToArraySafe(eventCode, activeEventCodes, true); // true = no dups
        activeEventCount++;

        // return eventCode to caller
        return (eventCode, expTime);
    }
    function _getGameCode(address _host, string memory _evtName) external view onlyKeeperOrGTA() returns (address) {
        // generate gameCode from host address and game name
        address evtCode = GTAL._generateAddressHash(_host, _evtName);
        require(activeEvents[evtCode].event_0.host != address(0), 'err: event name for host not found :{}');
        return evtCode;
    }
    function _getPlayers(address _evtCode) external view onlyKeeperOrGTA returns (address[] memory) {
        require(activeEvents[_evtCode].event_0.host != address(0), 'err: _gameCode not found :{}');
        return activeEvents[_evtCode].event_1.guestAddresses; // 'Event_1.guests' is mapping
    }
    function getActiveEventHost(address _evtCode) external view onlyKeeperOrGTA() returns(address) {
        return activeEvents[_evtCode].event_0.host;
    }
    function isGuestRegistered(address _evtCode, address _guest) external view onlyKeeperOrGTA() returns (bool) {
        require(_evtCode != address(0), 'err: no event code ;o');

        // validate _eventCode exists
        IGTALib.Event_0 storage evt = activeEvents[_evtCode].event_0;
        require(evt.host != address(0), 'err: invalid event code :I');

        // check msg.sender is registered
        IGTALib.GTAEvent storage gtaEvt = activeEvents[_evtCode];
        return gtaEvt.guests[_guest]; // true = registered
    }
    function getActiveEvent_0(address _evtCode) external view onlyKeeperOrGTA() returns(IGTALib.Event_0 memory) {
        return activeEvents[_evtCode].event_0;
    }
    function getActiveEvent_1(address _evtCode) external view onlyKeeperOrGTA() returns(IGTALib.Event_1 memory) {
        return activeEvents[_evtCode].event_1;
    }
    function getActiveEvent_2(address _evtCode) external view onlyKeeperOrGTA() returns(IGTALib.Event_2 memory) {
        return activeEvents[_evtCode].event_2;
    }
    function _getPublicActiveEventDetails(address _evtCode) external view onlyKeeperOrGTA returns (address, address, string memory, uint32, uint8[] memory, uint8, uint256, uint256, uint256, uint256) {
        require(activeEvents[_evtCode].event_0.host != address(0), 'err: invalid event');
        IGTALib.Event_0 storage e = activeEvents[_evtCode].event_0;
        IGTALib.Event_1 storage e1 = activeEvents[_evtCode].event_1;
        IGTALib.Event_2 memory e2 = activeEvents[_evtCode].event_2;
        string memory eventName = e.gameName;
        return (_evtCode, e.host, eventName, e.entryFeeUSD, e2.winPercs, e1.hostFeePerc, e.createBlockNum, e.createTime, e.startTime, e.expTime);
    }

    // set event params to launched state
    // function _launchEvent(IGTALib.Event_0 storage _evt) private returns (IGTALib.Event_0 storage ) {
    function _launchEvent(address _evtCode) external {
        IGTALib.GTAEvent storage _evt = activeEvents[_evtCode];
        require(!_evt.event_1.launched, 'err: event already launched');

        // set event fee calculations & prizePoolUSD
        // set event launched state
        _evt.event_0.launchTime = block.timestamp;
        _evt.event_0.launchBlockNum = block.number;
        _evt.event_1.launched = true;
    }

    // calc all fees & 'prizePoolUSD' & 'payoutsUSD' from total 'entryFeeUSD' collected
    //  calc 'buyGtaUSD' from 'serviceFeeUSD'
    // calc: prizePoolUSD, payoutsUSD, keeperFeeUSD, serviceFeeUSD, supportFeeUSD, refundsUSD, totalFeesUSD, buyGtaUSD
    // function _calcFeesAndPayouts(IGTALib.Event_0 storage _evt) external returns (IGTALib.Event_0 storage) {
    function _calcFeesAndPayouts(address _evtCode) external {
        IGTALib.GTAEvent storage _evt = activeEvents[_evtCode];
        /* DEDUCTING FEES
            current contract debits: 'depositFeePerc', 'hostFeePerc', 'keeperFeePerc', 'serviceFeePerc', 'supportFeePerc', 'winPercs'
             - depositFeePerc -> taken out of each deposit (alt|stable 'transfer' to contract) _ in 'settleBalances'
             - keeper|service|support fees -> taken from gross 'entryFeeUSD' calculated below
             - host fees -> taken from GROSS 'prizePoolUSD' generated below (ie. net 'entryFeeUSD')
             - win payouts -> taken from GROSS 'prizePoolUSD' generated below

            Formulas ...
                keeperFeeUSD = (entryFeeUSD * guestCnt) * keeperFeePerc
                serviceFeeUSD = (entryFeeUSD * guestCnt) * serviceFeePerc
                supportFeeUSD = (entryFeeUSD * guestCnt) * supportFeePerc
                totalFeesUSD = keeperFeeUSD + serviceFeeUSD + supportFeeUSD

                buyGtaUSD = serviceFeeUSD * buyGtaPerc

                GROSS entryFeeUSD = entryFeeUSD * guestCnt
                  NET entryFeeUSD = GROSS entryFeeUSD - totalFeesUSD

                GROSS serviceFeeUSD = GROSS entryFeeUSD * serviceFeePerc
                  NET serviceFeeUSD = GROSS serviceFeeUSD - buyGtaUSD
                
                NOTE: buyGtaUSD used to buy GTA from market (in 'hostEndEventWithGuestRecipients'),
                       which is then held by GTA contract address (until '_burnGTA' invoked)
                      then '_burnGTA' burns 'burnGtaPerc' of all GTA held
                       w/ remaining GTA held being sent to msg.sender

                GROSS prizePoolUSD = (entryFeeUSD * guestCnt) - (keeperFeeUSD + serviceFeeUSD + supportFeeUSD)
                        hostFeeUSD = GROSS prizePoolUSD * hostFeePerc
                  NET prizePoolUSD = GROSS prizePoolUSD - hostFeeUSD
                     payoutsUSD[i] = NET prizePoolUSD * 'winPercs[i]'

                NOTE: if 'winPercs.length' == 0 (then 'hostFeePerc' == 100, set in 'createEvent'), results in empty 'payoutsUSD' array
                 HENCE, this event will allow no _guests to be passed into 'hostEndEventWithGuestRecipients',
                    resulting in host receiving 100% of 'prizePoolUSD'
                
                NOTE: contract won't take responsibility for any errors w/ no winners declared by withholding funds or refunding credits, etc.
                 HENCE, full 'prizePoolUSD' will always be distributed (ie. to host)
        */

        // calc individual guest fees (BEFORE generating 'prizePoolUSD') 
        //  '_ind' used for refunds in 'cancelEventAndProcessRefunds' (excludes 'hostFeeUSD_ind')
        _evt.event_2.keeperFeeUSD_ind = _evt.event_0.entryFeeUSD * (keeperFeePerc/100);
        _evt.event_2.serviceFeeUSD_ind = _evt.event_0.entryFeeUSD * (serviceFeePerc/100);
        _evt.event_2.supportFeeUSD_ind = _evt.event_0.entryFeeUSD * (supportFeePerc/100);

        // calc total fees for each individual 'entryFeeUSD' paid
        _evt.event_2.totalFeesUSD_ind = _evt.event_2.keeperFeeUSD_ind + _evt.event_2.serviceFeeUSD_ind + _evt.event_2.supportFeeUSD_ind;

        // calc: 'hostFeeUSD_ind' = 'hostFeePerc' of single 'entryFeeUSD' - 'totalFeesUSD_ind'
        _evt.event_2.hostFeeUSD_ind = (_evt.event_0.entryFeeUSD - _evt.event_2.totalFeesUSD_ind) * (_evt.event_1.hostFeePerc/100);

        // calc total fees for all 'entryFeeUSD' paid
        _evt.event_1.keeperFeeUSD = _evt.event_2.keeperFeeUSD_ind * _evt.event_1.guestCnt;
        _evt.event_1.serviceFeeUSD = _evt.event_2.serviceFeeUSD_ind * _evt.event_1.guestCnt; // GROSS
        _evt.event_1.supportFeeUSD = _evt.event_2.supportFeeUSD_ind * _evt.event_1.guestCnt;
        _evt.event_2.totalFeesUSD = _evt.event_1.keeperFeeUSD + _evt.event_1.serviceFeeUSD + _evt.event_1.supportFeeUSD;

        /** TOKENOMICS...
            1) remove GTA from the market: 
                LEGACY MODEL (N/A)
                    - host choice: to pay service fee in GTA for a discount (and then we buy and burn)
                NEW MODEL
                    - keeper set: buyGtaPerc of serviceFeeUSD = buyGtaUSD (for every event)
                    - buyGtaUSD calculated & removed from 'serviceFeeUSD' (buys GTA from market in 'hostEndEventWithGuestRecipients')
                    - host required to hold some GTA in order to host (handled in 'createEvent')
                    - 'info|burn|cancel' public functions require holding GTA
                
            2) add GTA to the market: 
                - host gets minted some amount for hosting games (handled in 'hostEndEventWithGuestRecipients')
                - guest gets minted some amount for winning games (handled in 'hostEndEventWithGuestRecipients')
            
            #2 always has to be less than #1 for every hosted event 
                - the value of amounts minted must always be less than the service fee
                NOTE: total amount minted to winners + host = 'mintGtaPerc' of GTA amount recieved from 'buyGtaUSD' from market
        */

        // calc: TOT 'buyGtaUSD' = 'buyGtaPerc' of 'serviceFeeUSD'
        //       NET 'serviceFeeUSD' = 'serviceFeeUSD' - 'buyGtaUSD'
        //  NOTE: remaining NET 'serviceFeeUSD' is simply held by GTA contract address
        //   LEFT OFF HERE ... should we do something with it? track it in global? perhaps send it to some 'serviceFeeAddress'?
        _evt.event_2.buyGtaUSD = _evt.event_1.serviceFeeUSD * (buyGtaPerc/100);
        _evt.event_1.serviceFeeUSD -= _evt.event_2.buyGtaUSD; // NET

        // calc idividual & total refunds (for 'cancelEventAndProcessRefunds', 'ProcessedRefund', 'CanceledEvent')
        _evt.event_2.refundUSD_ind = _evt.event_0.entryFeeUSD - _evt.event_2.totalFeesUSD_ind; 
        _evt.event_2.refundsUSD = _evt.event_2.refundUSD_ind * _evt.event_1.guestCnt;

        // calc: GROSS 'prizePoolUSD' = all 'entryFeeUSD' - 'totalFeesUSD'
        _evt.event_2.prizePoolUSD = (_evt.event_0.entryFeeUSD * _evt.event_1.guestCnt) - _evt.event_2.totalFeesUSD;

        // calc: 'hostFeeUSD' = 'hostFeePerc' of 'prizePoolUSD' (AFTER 'totalFeesUSD' deducted first)
        _evt.event_2.hostFeeUSD = _evt.event_2.prizePoolUSD * (_evt.event_1.hostFeePerc/100);

        // calc: NET 'prizePoolUSD' = gross 'prizePoolUSD' - 'hostFeeUSD'
        //  NOTE: not setting NET, allows for correct calc of payoutsUSD & correct emit logs
        // _evt.event_2.prizePoolUSD -= _evt.event_2.hostFeeUSD;
        
        // calc payoutsUSD (finally, AFTER all deductions)
        for (uint i=0; i < _evt.event_2.winPercs.length; i++) {
            _evt.event_2.payoutsUSD.push(_evt.event_2.prizePoolUSD * (_evt.event_2.winPercs[i]/100));
        }
    }
}
