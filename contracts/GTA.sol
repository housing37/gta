// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;        
import "./GTADelegate.sol"; // interface
import "./GTASwapTools.sol"; // inheritance

// deploy
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// local _ $ npm install @openzeppelin/contracts
import "./node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./node_modules/@openzeppelin/contracts/access/Ownable.sol"; 

/* terminology...
                 join -> room, game, event, activity
             register -> seat, guest, delegates, users, participants, entrants
    payout/distribute -> rewards, winnings, earnings, recipients 
*/
interface IGTADelegate {
    // public auto-generated getter
    function keeper() external view returns (address);
    function uswapV2routers() external view returns (address[] memory);
    function infoGtaBalanceRequired() external view returns (uint256); 
    function burnGtaBalanceRequired() external view returns (uint256);
    function cancelGtaBalanceRequired() external view returns (uint256);
    // function minEventEntryFeeUSD() external view returns (uint32);
    function minDepositForAltsUSD() external view returns (uint32);
    // function maxHostFeePerc() external view returns (uint8);
    function hostGtaBalReqPerc() external view returns (uint8);
    function depositFeePerc() external view returns (uint8);
    function keeperFeePerc() external view returns (uint8);
    function serviceFeePerc() external view returns (uint8);
    function supportFeePerc() external view returns (uint8);
    function whitelistStables() external view returns (address[] memory);
    function whitelistAlts() external view returns (address[] memory);
    function enableMinDepositRefundsForAlts() external view returns(bool);
    function activeEventCount() external view returns (uint64);
    function activeEventCodes() external view returns (address[] memory);
    function buyGtaPerc() external view returns (uint8);
    function burnGtaPerc() external view returns (uint8);
    function mintGtaPerc() external view returns (uint8);
    function mintGtaToHost() external view returns (bool);
    
    // public access
    function setKeeper(address _newKeeper) external;
    function _generateAddressHash(address host, string memory uid) external view returns (address);
    // function _getTotalsOfArray(uint8[] calldata _arr) external pure returns (uint8);
    // function _validatePercsInArr(uint8[] calldata _percs) external pure returns (bool);
    function addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) external pure returns (address[] memory);
    function remAddressFromArray(address _addr, address[] memory _arr) external pure returns (address[] memory);
    // function getWhitelistStables() external view returns (address[] memory);
    // function getWhitelistAlts() external view returns (address[] memory);
    function _isTokenInArray(address _addr, address[] memory _arr) external pure returns (bool);

    // onlyKeeper access
    function _getBestDebitStableUSD(uint32 _amountUSD) external view returns (address);
    function _increaseWhitelistPendingDebit(address token, uint256 amount) external;
    // function sanityCheck(address token, uint256 amount) external returns (bool);
    function processContractDebitsAndCredits(address _token, uint256 _amnt) external;
    function contractStablesSanityCheck() external view returns (bool);
    function getNextStableTokDeposit() external returns (address);
    function addAccruedGFRL(uint256 _gasAmnt) external returns (uint256);
    function getAccruedGFRL() external view returns (uint256);
    function getSwapRouters() external view returns (address[] memory);
    function getSupportStaffWithIndFees(uint32 _totFee) external view returns (address[] calldata, uint32[] calldata);
    function setContractGTA(address _gta) external;
    function _addGuestToEvent(address _guest, address _evtCode) external;
    function hostEndEvent(address _eventCode, address[] memory _guests) external returns(address, GTALib.Event_1 calldata, GTALib.Event_2 calldata);
    function _endEvent(address _evtCode) external;
    function getActiveEventHost(address _evtCode) external returns(address);

    function getActiveEvent_0(address _evtCode) external view returns (GTALib.Event_0 calldata);
    function getActiveEvent_1(address _evtCode) external view returns (GTALib.Event_1 calldata);
    function getActiveEvent_2(address _evtCode) external view returns (GTALib.Event_2 calldata);
    function isGuestRegistered(address _evtCode, address _guest) external view returns (bool);
    function _getPublicActiveEventDetails(address _evtCode) external view returns (address, address, string memory, uint32, uint8[] memory, uint8, uint256, uint256, uint256, uint256);
    function createNewEvent(string memory _eventName, uint256 _startTime, uint32 _entryFeeUSD, uint8 _hostFeePerc, uint8[] calldata _winPercs) external returns (address, uint256);
    function _calcFeesAndPayouts(address _evtCode) external;
    function _launchEvent(address _evtCode) external;
}

contract GamerTokeAward is ERC20, Ownable, GTASwapTools {
    // Import MyStruct from ContractB
    // using GTALib for GTALib.Event_0;

    /* -------------------------------------------------------- */
    /* GLOBALS                                                  */
    /* -------------------------------------------------------- */
    /* _ ADMIN SUPPORT _ */
    IGTADelegate private GTAD; // 'keeper' maintained within
    
    /* _ TOKEN INIT SUPPORT _ */
    string private constant tok_name = "_TEST GTA IERC20";
    string private constant tok_symb = "_TEST_GTA";

    /* _ CREDIT SUPPORT _ */
    // usd credits used to process guest deposits, registers, refunds
    mapping(address => uint32) private creditsUSD;

    // set by '_updateCredits'; get by 'keeperGetCreditAddresses|keeperGetCredits'
    address[] private creditsAddrArray;
    
    // track last block# used to update 'creditsUSD' in 'settleBalances'
    uint32 private lastBlockNumUpdate = 0; // takes 1355 years to max out uint32

    // code required for 'burnGTA'
    //  EASY -> uint16: 65,535 (~1day=86,400 @ 10s blocks w/ 1 wallet)
    //  HARD -> uint32: 4,294,967,295 (~100yrs=3,110,400,00 @ 10s blocks w/ 1 wallet)
    uint16 private BURN_CODE_EASY;
    uint32 private BURN_CODE_HARD; 
    uint64 public BURN_CODE_GUESS_CNT = 0;
    bool public USE_BURN_CODE_HARD = false;
    
    /* -------------------------------------------------------- */
    /* EVENTS                                                   */
    /* -------------------------------------------------------- */
    // emit to client side that a new event was created
    event GTAEventCreated(address _host, string _eventName, address _eventCode, uint256 _createTime, uint256 _startTime, uint256 _expTime, uint32 _entryFeeUSD, uint8 _hostFeePerc, uint8[]  _winPercs);
    
    // emit to client side when mnimium deposit refund is not met
    event MinimumDepositRefund(address sender, address token, uint256 amount, uint256 gasfee, uint256 accrued);

    // emit to client side when deposit fails; only due to min deposit fail (120323)
    event DepositFailed(address sender, address token, uint256 tokenAmount, uint256 stableAmount, uint256 minDepUSD, bool refundsEnabled);

    // emit to client side when deposit processed (after sender's manual transfer to contract)
    event DepositProcessed(address sender, address token, uint256 amount, uint256 stable_swap_fee, uint256 depositFee, uint256 balance);

    // notify client side that an event distribution (winner payout) has occurred successuflly
    event EndEventDistribution(address winner, uint16 win_place, uint8 win_perc, uint32 win_usd, uint32 win_pool_usd, address stable);

    // notify client side that an end event has occurred successfully
    event EndEventActivity(address evtCode, address host, address[] winners, uint32 prize_pool_usd, uint32 host_fee_usd, uint32 keeper_fee_usd, uint64 activeEvtCount, uint256 block_timestamp, uint256 block_number);

    // notify client side that an event has been canceled
    event ProcessedRefund(address guest, uint32 refundAmountUSD, address evtCode, bool evtLaunched, uint256 evtExpTime);
    event CanceledEvent(address canceledBy, address evtCode, bool evtLaunched, uint256 evtExpTime, uint32 guestCount, uint32 prize_pool_usd, uint32 totalFeesUSD, uint32 totalRefundsUSD, uint32 indRefundUSD);

    // notify client side that someoen cracked the burn code and burned all gta in this contract
    event BurnedGTA(uint256 bal_cleaned, uint256 bal_burned, uint256 bal_earned, address code_cracker, uint64 guess_count);
    
    // notify clients a new burn code is set with type (easy, hard)
    event BurnCodeReset(bool setToHard);

    // notify client side that a guest was registered for event
    event RegisteredForEvent(address evtCode, uint32 entryFeeUSD, address guest, uint32 guestCnt);

    // notify client side of event fee payouts (_payHost, _payKeepr, _paySupport)
    event PaidHostFee(address _host, uint32 _amntUSD, address _eventCode);
    event PaidKeeperFee(address _keeper, uint32 _amntUSD, address _eventCode);
    event PaidSupportFee(address _supportStaff, uint32 _indAmntUSD, uint32 _totAmntUSD, address _eventCode);

    // notiify client side that '_paySupport' failed for some reason
    event FailedPaySupportFee(uint32 _amntUSD, address _eventCode, string _info);

    /* -------------------------------------------------------- */
    /* CONSTRUCTOR                                              */
    /* -------------------------------------------------------- */
    // NOTE: pre-initialized 'GTADelegate' address required
    //      initializer w/ 'keeper' not required ('GTADelegate' maintained)
    //      sets msg.sender to '_owner' ('Ownable' maintained)
    constructor(address _gtad, uint256 _initSupply) ERC20(tok_name, tok_symb) Ownable(msg.sender) {
        require(_gtad != address(0), 'err: invalid delegate contract address :/');
        GTAD = IGTADelegate(_gtad);
        GTAD.setContractGTA(address(this));
        _mint(msg.sender, _initSupply * 10**uint8(decimals())); // 'emit Transfer'
    }

    // NOTE: call from contructor, not required
    //      call from 'keeper' of new _gtad, not required
    //      call from 'keeper' of old GTAD, indeed required
    function setGTAD(address _gtad, uint256 _keeperSupply) external onlyKeeper {
        require(_gtad != address(0), 'err: invalid delegate contract address :/');
        GTAD = IGTADelegate(_gtad);
        GTAD.setContractGTA(address(this));
        _mint(GTAD.keeper(), _keeperSupply * 10**uint8(decimals())); // 'emit Transfer'
    }

    /* -------------------------------------------------------- */
    /* MODIFIERS                                                */
    /* -------------------------------------------------------- */
    modifier onlyAdmins(address _evtCode) {
        require(GTAD.getActiveEvent_0(_evtCode).host != address(0), 'err: gameCode not found :(');
        bool isHost = msg.sender == GTAD.getActiveEvent_0(_evtCode).host;
        bool isKeeper = msg.sender == GTAD.keeper();
        require(isKeeper || isHost, 'err: only admins :/*');
        
        // NOTE: onlyAdmins is only used in 'getPlayers' (no need for owner() check)
        // bool isOwner = msg.sender == owner(); // from 'Ownable'
        // require(isKeeper || isOwner || isHost, 'err: only admins :/*');

        _;
    }
    modifier onlyKeeper() {
        require(msg.sender == GTAD.keeper(), "Only the keeper :p");
        _;
    }
    modifier onlyHolder(uint256 _requiredAmount) {
        require(balanceOf(msg.sender) >= _requiredAmount, 'err: need more GTA');
        _;
    }

    /* -------------------------------------------------------- */
    /* PUBLIC ACCESSORS - KEEPER SUPPORT                        */
    /* -------------------------------------------------------- */
    function keeperGetCreditAddresses() external view onlyKeeper returns (address[] memory) {
        require(creditsAddrArray.length > 0, 'err: no addresses found with credits :0');
        return creditsAddrArray;
    }
    function keeperGetCredits(address _guest) external view onlyKeeper returns (uint32) {
        require(_guest != address(0), 'err: no zero address :{=}');
        return creditsUSD[_guest];
    }
    function keeperGetLastBlockNumUpdate() external view onlyKeeper returns (uint32) {
        return lastBlockNumUpdate;
    }
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
    function keeperGetBurnCodes() external view onlyKeeper returns (uint32[2] memory) {
        return [uint32(BURN_CODE_EASY), BURN_CODE_HARD];
    }
    
    /* -------------------------------------------------------- */
    /* PUBLIC ACCESSORS - GTA HOLDER SUPPORT                    */
    /* -------------------------------------------------------- */
    function infoGetPlayersForGameCode(address _evtCode) external view onlyHolder(GTAD.infoGtaBalanceRequired()) returns (address[] memory) {
        require(_evtCode != address(0) && GTAD.getActiveEvent_0(_evtCode).host != address(0), 'err: invalid game code :O');
        return _getPlayers(_evtCode);
    }
    function infoGetBurnGtaBalanceRequired() external view onlyHolder(GTAD.infoGtaBalanceRequired()) returns (uint256) {
        return GTAD.burnGtaBalanceRequired();
    }
    function infoGetDetailsForEventCode(address _evtCode) external view onlyHolder(GTAD.infoGtaBalanceRequired()) returns (address, address, string memory, uint32, uint8[] memory, uint8, uint256, uint256, uint256, uint256) {
        require(_evtCode != address(0) && GTAD.getActiveEvent_0(_evtCode).host != address(0), 'err: invalid event code :O');
        return GTAD._getPublicActiveEventDetails(_evtCode);
    }

    /* SIDE QUEST... CRACK THE (BURN) CODE                        */
    // public can try to guess the burn code (to burn buyGtaPerc of the balance, earn the rest)
    // code required for 'burnGTA'
    //  EASY -> uint16: 65,535 (~1day=86,400 @ 10s blocks w/ 1 wallet)
    //  HARD -> uint32: 4,294,967,295 (~100yrs=3,110,400,00 @ 10s blocks w/ 1 wallet)
    function burnGTA_HARD(uint32 burnCode) external onlyHolder(GTAD.burnGtaBalanceRequired()) returns (bool) {
        BURN_CODE_GUESS_CNT++; // keep track of guess count
        require(USE_BURN_CODE_HARD, 'err: burn code set to easy, use burnGTA_EASY :p');
        require(burnCode == BURN_CODE_HARD, 'err: invalid burn_code, guess again :p');
        return _burnGTA();
    }
    function burnGTA_EASY(uint16 burnCode) external onlyHolder(GTAD.burnGtaBalanceRequired()) returns (bool) {
        BURN_CODE_GUESS_CNT++; // keep track of guess count
        require(!USE_BURN_CODE_HARD, 'err: burn code set to hard, use burnGTA_HARD :p');
        require(burnCode == BURN_CODE_EASY, 'err: invalid burn_code, guess again :p');
        return _burnGTA();
    }

    /* -------------------------------------------------------- */
    /* PUBLIC - HOST / PLAYER SUPPORT                           */
    /* -------------------------------------------------------- */
    // view your own credits ('creditsUSD' are not available for withdrawel)
    function checkMyCredits() external view returns (uint32) {
        return creditsUSD[msg.sender];
    }

    // verify your registration for event 
    function checkMyRegistrationForEvent(address _evtCode) external view returns (bool) {
        require(_evtCode != address(0), 'err: no event code ;o');
        return GTAD.isGuestRegistered(_evtCode, msg.sender);
    }

    // verify your own GTA holding required to host
    function checkMyGtaBalanceRequiredToHost(uint32 _entryFeeUSD) external view returns (bool) {
        require(_entryFeeUSD > 0, 'err: no entry fee :/');
        require(_hostCanCreateEvent(msg.sender, _entryFeeUSD), 'err: not enough GTA to host :/');
        return true;
    }

    function getGtaBalanceRequiredToHost(uint32 _entryFeeUSD) external view returns (uint256) {
        require(_entryFeeUSD > 0, 'err: _entryFeeUSD is 0 :/');
        return _gtaHoldingRequiredToHost(_entryFeeUSD);
    }
    function getGtaBalanceRequiredForInfo() external view returns (uint256) {
        return GTAD.infoGtaBalanceRequired();
    }
    function getGameCode(address _host, string memory _gameName) external view returns (address) {
        require(GTAD.activeEventCount() > 0, "err: no activeEvents :{}"); // verify there are active activeEvents
        require(_host != address(0x0), "err: no host address :{}"); // verify _host address input
        require(bytes(_gameName).length > 0, "err: no game name :{}"); // verifiy _gameName input

        // gameCode = hash(_host, _gameName)
        return _getGameCode(_host, _gameName);
    }

    function createEvent(string memory _eventName, uint256 _startTime, uint32 _entryFeeUSD, uint8 _hostFeePerc, uint8[] calldata _winPercs) public returns (address) {        
        require(_hostCanCreateEvent(msg.sender, _entryFeeUSD), "err: not enough GTA to host, check getGtaBalanceRequiredToHost :/");
        (address eventCode, uint256 expTime) = GTAD.createNewEvent(_eventName, _startTime, _entryFeeUSD, _hostFeePerc, _winPercs);
        
        // emit client side notification for 'createEvent' event
        emit GTAEventCreated(msg.sender, _eventName, eventCode, block.timestamp, _startTime, expTime, _entryFeeUSD, _hostFeePerc, _winPercs);

        // return eventCode to caller
        return eventCode;
    }

    // msg.sender can add themself to any event; debits from 'creditsUSD[msg.sender]'
    // UPDATE_120223: make deposit then tweet to register
    //              1) send stable|alt deposit to gta contract
    //              2) tweet: @GamerTokenAward register <wallet_address> <game_code>
    //                  OR ... for free play w/ host register
    //              3) tweet: @GamerTokenAward play <wallet_address> <game_code>
    function registerForEvent(address _eventCode) public returns (bool) {
        require(_eventCode != address(0), 'err: no game code ;o');

        // get/validate active game
        GTALib.Event_0 memory evt = GTAD.getActiveEvent_0(_eventCode);
        require(evt.host != address(0), 'err: invalid _eventCode :I');

        // check if game launched
        GTALib.Event_1 memory evt1 = GTAD.getActiveEvent_1(_eventCode);
        require(!evt1.launched, "err: event already started :(");

        // check if host trying to register
        //  NOTE: keeper may indeed register for any event
        require(evt.host != msg.sender, 'err: invalid guest, no host registration :{}');

        // check msg.sender already registered
        // require(!evt1.guests[msg.sender], 'err: already registered for this _eventCode :p');
        require(!GTAD.isGuestRegistered(_eventCode, msg.sender), 'err: already registered for this _eventCode :p');

        // check msg.sender for enough credits
        require(evt.entryFeeUSD < creditsUSD[msg.sender], 'err: invalid credits, use checkMyCredits & send whitelistAlts|whitelistStables to this contract :P');

        // debit guest entry fee from creditsUSD[msg.sender] (ie. guest credits)
        _updateCredits(msg.sender, evt.entryFeeUSD, true); // true = debit

        // -1) add msg.sender to event
        GTAD._addGuestToEvent(msg.sender, _eventCode);
        
        // notify client side that a guest was registered for event
        emit RegisteredForEvent(_eventCode, evt.entryFeeUSD, msg.sender, evt1.guestCnt);
        
        return true;
    }

    // hosts can pay to add guests to their own events (debits from host credits)
    function hostRegisterSeatForEvent(address _guest, address _eventCode) public returns (bool) {
        require(_guest != address(0), 'err: no _guest ;l');
        require(_eventCode != address(0), 'err: no _eventCode ;l');

        // get/validate active game
        GTALib.Event_0 memory evt = GTAD.getActiveEvent_0(_eventCode);
        require(evt.host != address(0), 'err: invalid _eventCode :I');

        // check if msg.sender is _eventCode host
        //  NOTE: keeper may register any guest for any event
        require(evt.host == msg.sender || msg.sender == GTAD.keeper(), 'err: only event host :/');

        // check if host trying to register host
        require(evt.host != _guest, 'err: invalid guest, no host registration :{}');

        // check if event launched
        GTALib.Event_1 memory evt1 = GTAD.getActiveEvent_1(_eventCode);
        require(!evt1.launched, 'err: event already started :(');

        // check _guest already registered
        require(!GTAD.isGuestRegistered(_eventCode, _guest), 'err: _guest already registered for this _eventCode :p');

        // check msg.sender for enough credits
        require(evt.entryFeeUSD < creditsUSD[msg.sender], 'err: invalid credits :(, use checkMyCredits & send whitelistAlts|whitelistStables to this contract :p');

        // debit guest entry fee from creditsUSD[msg.sender] (ie. host credits)
        _updateCredits(msg.sender, evt.entryFeeUSD, true); // true = debit

        // -1) add guest to game event
        GTAD._addGuestToEvent(_guest, _eventCode);

        // notify client side that a _guest was registered for event
        emit RegisteredForEvent(_eventCode, evt.entryFeeUSD, _guest, evt1.guestCnt);

        return true;
    }

    // host can start event w/ guests pre-registered for _eventCode
    //  calc fees and payouts, pay keeper & support
    function hostStartEvent(address _eventCode) public returns (bool) {
        require(_eventCode != address(0), 'err: no event code :p');

        // get/validate active game
        GTALib.Event_0 memory evt = GTAD.getActiveEvent_0(_eventCode);
        require(evt.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is event host
        require(evt.host == msg.sender, 'err: only host :/');

        // check if event not started yet
        GTALib.Event_1 memory evt1 = GTAD.getActiveEvent_1(_eventCode);
        require(!evt1.launched, 'err: event already started');

        // calc all fees & 'prizePoolUSD' & 'payoutsUSD' from total 'entryFeeUSD'
        //  calc 'buyGtaUSD' from 'serviceFeeUSD'
        GTAD._calcFeesAndPayouts(_eventCode);

        // set event state to 'launched = true'
        GTAD._launchEvent(_eventCode); 

        // pay keeper & support staff w/ lowest market value stable
        //  (contract maintains highest market value stables)
        // NOTE: host paid in 'hostEndEventWithGuestRecipients'
        _payKeeper(evt1.keeperFeeUSD, _eventCode);
        _paySupport(evt1.supportFeeUSD, _eventCode);        

        return true;
    }

    // _guests[i] => payoutsUSD[i]
    // earners, gainers, recipients, receivers, achievers, Leaders, Victors, PaidGuests
    function hostEndEventWithGuestRecipients(address _eventCode, address[] memory _guests) public returns (bool) {
        require(_eventCode != address(0), 'err: no event code :p');

        // NOTE: _guests.lengh = 0, means no winners set (ie. 100% of prizePoolUSD paid to host)
        require(_guests.length >= 0, 'err: _guests.length, SHOULD NOT OCCUR :p');

        // get/validate active game
        GTALib.Event_0 memory evt = GTAD.getActiveEvent_0(_eventCode);
        require(evt.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is event host
        require(evt.host == msg.sender, 'err: only host :/');

        // check if event started
        GTALib.Event_1 memory evt1 = GTAD.getActiveEvent_1(_eventCode);
        require(evt1.launched, 'err: event not started yet');

        // check if # of _guests.length == winPercs.length == payoutsUSD.length (set during createEvent & hostStartEvent)
        GTALib.Event_2 memory evt2 = GTAD.getActiveEvent_2(_eventCode);
        require(evt2.winPercs.length == _guests.length && _guests.length == evt2.payoutsUSD.length, 'err: _guests.length != size of winPercs[] & payoutsUSD[] =(');

        // buy GTA from open market (using 'buyGtaUSD' = 'buyGtaPerc' of 'serviceFeeUSD')
        //  NOTE: invokes inherited '_swap_v2_wrap' & uses address(this) as 'outReceiver'
        uint256 gta_amnt_buy = _processBuyAndBurnStableSwap(GTAD._getBestDebitStableUSD(evt2.buyGtaUSD), evt2.buyGtaUSD);

        // calc 'gta_amnt_mint' using 'mintGtaPerc' of 'gta_amnt_buy' 
        //  gta_amnt_mint gets divided equally to all '_winners' + host (if 'mintGtaToHost'; keeper controlled)
        // NOTE: remaining 'gta_amnt_buy' is simply held by this GTA contract
        uint256 gta_amnt_mint_ind = (gta_amnt_buy * (GTAD.mintGtaPerc()/100)) / (_guests.length + (GTAD.mintGtaToHost() ? 1 : 0)); // +1 = host

        // mint GTA to host (if applicable; keeper controlled)
        if (GTAD.mintGtaToHost()) { _mint(evt.host, gta_amnt_mint_ind); }

        // loop through _guests: distribute 'evt.event_2.winPercs'
        //  NOTE: if _guests.length == 0, then winPercs & payoutsUSD are empty arrays
        for (uint16 i=0; i < _guests.length; i++) {
            // verify winner address was registered in the event
            require(GTAD.isGuestRegistered(_eventCode, _guests[i]), 'err: invalid guest found :/, check getPlayers & retry w/ all valid guests');
            
            // calc win_usd = _guests[i] => payoutsUSD[i]
            address winner = _guests[i];
            uint32 win_usd = evt2.payoutsUSD[i];

            // LEFT OFF HERE ... new feature, keeper enable/disable winner autopay or claim
            //  ... need winner claim integration 
            //  ... maybe winner can pick to be paid in stable, or recieve digital visa (if applicable)

            // pay winner (w/ lowest market value stable)
            address stable = _transferBestDebitStableUSD(winner, win_usd);

            // mint GTA to this winner; amount is same for all winners & host (if applicable)
            _mint(winner, gta_amnt_mint_ind);

            // notify client side that an end event distribution occurred successfully
            emit EndEventDistribution(winner, i, evt2.winPercs[i], win_usd, evt2.prizePoolUSD, stable);
        }

        // pay host w/ lowest market value stable 
        //  (contract maintains highest market value stables)
        // NOTE: if _guests.length == 0, then 'hostFeePerc' == 100 (set in 'createEvent')
        //    HENCE, hostFeeUSD is 100% of prizePoolUSD
        // NOTE: keeper & support paid in 'hostStartEvent'
        _payHost(evt.host, evt2.hostFeeUSD, _eventCode);
        
        // set event params to end state & transfer to closedEvents array
        GTAD._endEvent(_eventCode);

        // notify client side that an end event occurred successfully
        emit EndEventActivity(_eventCode, evt.host, _guests, evt2.prizePoolUSD, evt2.hostFeeUSD, evt1.keeperFeeUSD, GTAD.activeEventCount(), block.timestamp, block.number);
        
        return true;
    }

    // cancel event and process refunds (host, guests, keeper)
    //  host|keeper can cancel if event not 'launched' yet OR indeed launched (emergency use case)
    //  guests can only cancel if event not 'launched' yet AND 'expTime' has passed
    // NOTE: if event canceled: guests get refunds in 'creditsUSD' & host does NOT get paid
    function cancelEventAndProcessRefunds(address _eventCode) external onlyHolder(GTAD.cancelGtaBalanceRequired()){
        require(_eventCode != address(0), 'err: no event code :<>');

        // get/validate active event
        GTALib.Event_0 memory evt = GTAD.getActiveEvent_0(_eventCode);
        require(evt.host != address(0), 'err: invalid event code :<>');
        
        // check for valid sender to cancel (only registered guests, host, or keeper)
        GTALib.Event_1 memory evt1 = GTAD.getActiveEvent_1(_eventCode);
        GTALib.Event_2 memory evt2 = GTAD.getActiveEvent_2(_eventCode);
        // bool isValidSender = evt1.guests[msg.sender] || msg.sender == evt.host || msg.sender == GTAD.keeper();
        bool isValidSender = GTAD.isGuestRegistered(_eventCode, msg.sender) || msg.sender == evt.host || msg.sender == GTAD.keeper();
        require(isValidSender, 'err: only registered guests or host :<>');

        // if guest is canceling, verify event not launched & expTime indeed passed 
        //  NOTE: considers keeper's allowance to register for any events
        if (GTAD.isGuestRegistered(_eventCode, msg.sender) && msg.sender != GTAD.keeper()) { 
            
            require(!evt1.launched && evt.expTime < block.timestamp, 'err: _eventCode not expTime yet :<>');
        } 

        // calc fees for keeperFeeUSD, supportFeeUSD, refundUSD_ind
        GTAD._calcFeesAndPayouts(_eventCode);

        // if event NOT launched yet: pay keeper & support staff accordingly
        //  else: keeper & support already paid in hostStartEvent
        // NOTE: host does not get paid here (ie. security risk: could create & cancel events for fees)
        if (!evt1.launched) {
            _payKeeper(evt1.keeperFeeUSD, _eventCode);
            _paySupport(evt1.supportFeeUSD, _eventCode);
        }

        // loop through guests & process refunds via '_updateCredits'
        for (uint i=0; i < evt1.guestAddresses.length; i++) {
            // REFUND ENTRY FEES (via IN-CONTRACT CREDITS) ... to 'creditsUSD'
            //  deposit fees: 'depositFeePerc' calc/removed in 'settleBalances' (BEFORE 'registerForEvent|hostRegisterSeatForEvent')
            //  service fees: 'totalFeesUSD' calc/set in 'hostStartEvent' w/ '_calcFeesAndPayouts' (AFTER 'registerForEvent|hostRegisterSeatForEvent')
            //   this allows 'registerForEvent|hostRegisterSeatForEvent' & 'cancelEventAndProcessRefunds' to sync w/ regard to 'entryFeeUSD'
            //      - 'settleBalances' credits 'creditsUSD' for Transfer.src_addr (AFTER 'depositFeePerc' removed)
            //      - 'settleBalances' deletes 'whitelistPendingDebits' as 'hostEndEventWithGuestRecipients' adds to them
            //      - 'registerForEvent|hostRegisterSeatForEvent' debits full 'entryFeeUSD' from 'creditsUSD' (BEFORE service fees removed)
            //      - 'hostStartEvent' calcs/sets 'totalFeesUSD' -> hostFeeUSD, keeperFeeUSD, serviceFeeUSD, supportFeeUSD
            //      - 'hostStartEvent' calcs/sets 'prizePoolUSD' & 'payoutsUSD' & 'refundUSD_ind' (from total 'entryFeeUSD' collected - 'totalFeesUSD')
            //      - 'hostEndEventWithGuestRecipients' processes buy & burn, pays winners w/ 'payoutsUSD', mints GTA to winners
            //      - 'hostEndEventWithGuestRecipients' adds to 'whitelistPendingDebits' as 'settleBalances' deletes them
            //      - 'hostEndEventWithGuestRecipients' pay host; pay keeper & support here or pay them in 'hostStartEvent'?
            //      - 'cancelEventAndProcessRefunds' credits 'refundUSD_ind' to 'creditsUSD' (refundUSD_ind = entryFeeUSD - totalFeesUSD_ind)

            // credit guest in 'creditsUSD' w/ amount 'refundUSD_ind' (NET of totalFeesUSD; set in '_calcFeesAndPayouts')
            _updateCredits(evt1.guestAddresses[i], evt2.refundUSD_ind, false); // false = credit

            // notify listeners of processed refund
            emit ProcessedRefund(evt1.guestAddresses[i], evt2.refundUSD_ind, _eventCode, evt1.launched, evt.expTime);
        }
    
        // set event params to end state
        GTAD._endEvent(_eventCode);

        // notify listeners of canceled event
        emit CanceledEvent(msg.sender, _eventCode, evt1.launched, evt.expTime, evt1.guestCnt, evt2.prizePoolUSD, evt2.totalFeesUSD, evt2.refundsUSD, evt2.refundUSD_ind);
    }

    // LEFT OFF HERE ... review settleBalances logic and algoirthmic integration
    //  011724_1725: i think the review is now complete...
    //  ready for one last logic walk through, then commit to git

    /* -------------------------------------------------------- */
    /* KEEPER CALL-BACK                                         */
    /* -------------------------------------------------------- */
    // invoked by keeper client side, every ~10sec (~blocktime), to ...
    //  1) 'processContractDebitsAndCredits': 
    //       debit 'whitelistPendingDebits' & credit 'contractBalances' w/ incoming 'Transfer' emits
    //  2) convert alt deposits to stables (if needed)
    //  3) update 'creditsUSD' w/ all NET incoming 'Transfer' emits ('sender' & 'amount')
    //  4) SANITIY CHECK: 'contractStablesSanityCheck'
    //      verifiy keeper sent legit 'amount' for each 'Transfer' event capture
    function settleBalances(GTALib.TxDeposit[] memory dataArray, uint32 _lastBlockNum) external onlyKeeper {
        uint256 start_refund = gasleft(); // record start gas amount
        require(lastBlockNumUpdate < _lastBlockNum, 'err: invalid _lastBlockNum :O');

        // loop through ERC-20 'Transfer' events received from client side
        //  NOTE: to save keeper gas (NOT refunded by contract), keeper required to pre-filter events for ...
        //   1) 'whitelistStables' & 'whitelistAlts' (else 'require' fails)
        //   2) receiver = this contract address (else 'require' fails)
        for (uint i = 0; i < dataArray.length; i++) { // python side: lst_evts_min[{token,sender,amount}, ...]
            address tok_addr = dataArray[i].token;
            uint256 tok_amnt = dataArray[i].amount;
            address src_addr = dataArray[i].sender;
            address dst_addr = dataArray[i].receiver;

            // verifiy keeper params from their 'Transfer' event captures (1 FAIL = revert everything)
            //   ie. force start over w/ new call & no gas refund; encourages keeper to NOT fuck up
            require(tok_addr != address(0), "err: invalid token, stop FUCKING AROUND! ={=}");
            require(tok_amnt != 0, "err: invalid amount, stop FUCKING AROUND! ={=}");
            require(src_addr != address(0) && src_addr != address(this), "err: invalid sender, stop FUCKING AROUND! ={=}");
            require(dst_addr == address(this), "err: receiver ain't this, stop FUCKING AROUND! :-{=}");

            bool is_wl_stab = GTAD._isTokenInArray(tok_addr, GTAD.whitelistStables());
            bool is_wl_alt = GTAD._isTokenInArray(tok_addr, GTAD.whitelistAlts());
            require(is_wl_stab || is_wl_alt, "err: non-whitelist token, stop FUCKING AROUND! :-{=}");
            
            // Settle ALL 'whitelistPendingDebits' & update 'contractBalances'
            //  via: _settlePendingDebits & _processIncommingTransfer
            //   1) deduct debits accrued from 'hostEndEventWithGuestRecipients->_increaseWhitelistPendingDebit'
            //   2) update stable balances from incoming IERC20 'Transfer' emits
            GTAD.processContractDebitsAndCredits(tok_addr, tok_amnt);

            // verifiy keeper sent legit 'amount' from their 'Transfer' event captures (1 FAIL = revert everything)
            //   ie. force start over w/ new call & no gas refund; encourages keeper to NOT fuck up
            // NOTE: settles ALL 'whitelistPendingDebits' accrued during 'hostEndEventWithGuestRecipients'
            // require(GTAD.sanityCheck(tok_addr, tok_amnt), "err: whitelist<->chain balance mismatch :-{} _ KEEPER LIED!");

            // default: if found in 'whitelistStables'
            uint256 stable_credit_amnt = tok_amnt; 
            uint256 stable_swap_fee = 0; // gas fee loss for swap: alt -> stable

            // if not in whitelistStables, swap alt for stable: tok_addr, tok_amnt
            if (!is_wl_stab) {

                // get stable coin to use & create swap path to it
                address stable_addr = GTAD.getNextStableTokDeposit();

                // get stable amount quote for this alt deposit (traverses 'uswapV2routers')
                address[] memory alt_stab_path = new address[](2);
                alt_stab_path[0] = tok_addr;
                alt_stab_path[1] = stable_addr;
                (uint8 rtrIdx, uint256 stableAmnt) = _best_swap_v2_router_idx_quote(alt_stab_path, tok_amnt, GTAD.uswapV2routers());

                // if stable quote is below min USD deposit required for alts
                //  then process refund (if 'enableMinDepositRefundsForAlts')
                // NOTE: need 'minDepositForAltsUSD' because 'stable_swap_fee' could be greater than 'stable_credit_amnt'
                if (stableAmnt < GTAD.minDepositForAltsUSD()) {  

                    // if refunds enabled, process refund: send 'tok_amnt' of 'tok_addr' back to 'src_addr'
                    if (GTAD.enableMinDepositRefundsForAlts()) {
                        // log gas used for refund
                        uint256 start_trans = gasleft();

                        // send 'tok_amnt' of 'tok_addr' back to 'src_addr'
                        IERC20(tok_addr).transfer(src_addr, tok_amnt); 

                        // log gas used for refund
                        uint256 gas_trans_loss = (start_trans - gasleft()) * tx.gasprice;
                        GTAD.addAccruedGFRL(gas_trans_loss);

                        // notify client listeners that refund was processed
                        emit MinimumDepositRefund(src_addr, tok_addr, tok_amnt, gas_trans_loss, GTAD.getAccruedGFRL());
                    }

                    // notify client side, deposit failed
                    emit DepositFailed(src_addr, tok_addr, tok_amnt, stableAmnt, GTAD.minDepositForAltsUSD(), GTAD.enableMinDepositRefundsForAlts());

                    // skip to next transfer in 'dataArray'
                    continue;
                }

                // swap tok_amnt alt -> stable (log swap fee / gas loss)
                //  NOTE: invokes inherited '_swap_v2_wrap' & uses address(this) as 'outReceiver'
                uint256 start_swap = gasleft();
                stable_credit_amnt = _swap_v2_wrap(alt_stab_path, GTAD.getSwapRouters()[rtrIdx], tok_amnt, address(this));
                uint256 gas_swap_loss = (start_swap - gasleft()) * tx.gasprice;

                // get stable quote for this swap fee / gas fee loss (traverses 'uswapV2routers')
                address[] memory wpls_stab_path = new address[](2);
                wpls_stab_path[0] = TOK_WPLS;
                wpls_stab_path[1] = stable_addr;
                (uint8 idx, uint256 amountOut) = _best_swap_v2_router_idx_quote(wpls_stab_path, gas_swap_loss, GTAD.uswapV2routers());
                
                stable_swap_fee = amountOut;

                // debit swap fee from 'stable_credit_amnt'
                stable_credit_amnt -= stable_swap_fee;                
            }

            // 1) debit deposit fees from 'stable_credit_amnt' (keeper optional)
            uint256 depositFee = stable_credit_amnt * (GTAD.depositFeePerc()/100);
            uint256 stable_net_amnt = stable_credit_amnt - depositFee; 

            // convert wei to ether (uint256 to uint32)
            uint32 usd_net_amnt = uint32(stable_net_amnt / 1e18);

            // 2) add 'net_amnt' to 'src_addr' in 'creditsUSD'
            _updateCredits(src_addr, usd_net_amnt, false); // false = credit

            // notify client side, deposit successful
            emit DepositProcessed(src_addr, tok_addr, tok_amnt, stable_swap_fee, depositFee, usd_net_amnt);
        }

        // SANITIY CHECK: verifiy keeper sent legit 'amount' for each 'Transfer' event capture 
        //  checks 'contractBalances' == on-chain balances (for all 'whitelistStables')
        // NOTE: 1 FAIL = revert everything (force start over w/ no gas refund; encourages keeper to NOT fuck up)
        require(GTAD.contractStablesSanityCheck(), "err: whitelist<->chain balance mismatch :-{} _ KEEPER LIED!");
        
        // update last block number
        lastBlockNumUpdate = _lastBlockNum;

        // -1) calc gas used to this point & refund to 'keeper' (in wei)
        uint256 gas_refund = (start_refund - gasleft()) * tx.gasprice;
        payable(msg.sender).transfer(gas_refund); // tx.gasprice in wei
    }

    /* -------------------------------------------------------- */
    /* PRIVATE - SUPPORTING                                     */
    /* -------------------------------------------------------- */
    function _burnGTA() private returns (bool) {
        uint256 bal = balanceOf(address(this));
        require(bal > 0, 'err: no GTA to burn :p');

        // burn it.. burn it real good...
        //  burn 'burnGtaPerc' of 'bal', send rest to cracker
        uint256 bal_burn = bal * (GTAD.burnGtaPerc()/100);
        uint256 bal_earn = bal - bal_burn;
        transferFrom(address(this), address(0), bal_burn);
        transferFrom(address(this), msg.sender, bal_earn);

        // notify the world that shit was burned
        emit BurnedGTA(bal, bal_burn, bal_earn, msg.sender, BURN_CODE_GUESS_CNT);

        // reset guess count
        BURN_CODE_GUESS_CNT = 0;

        return true;
    }
    function _getGameCode(address _host, string memory _gameName) private view returns (address) {
        // generate gameCode from host address and game name
        address gameCode = GTAD._generateAddressHash(_host, _gameName);
        require(GTAD.getActiveEvent_0(gameCode).host != address(0), 'err: game name for host not found :{}');
        return gameCode;
    }
    function _getPlayers(address _gameCode) private view returns (address[] memory) {
        require(GTAD.getActiveEvent_0(_gameCode).host != address(0), 'err: _gameCode not found :{}');
        return GTAD.getActiveEvent_1(_gameCode).guestAddresses; // 'Event_1.guests' is mapping
    }
    // debits/credits for a _guest in 'creditsUSD' (used during deposits and event registrations)
    function _updateCredits(address _guest, uint32 _amountUSD, bool _debit) private {
        if (_debit) { 
            // ensure there is enough credit before debit
            require(creditsUSD[_guest] >= _amountUSD, 'err: invalid credits to debit :[');
            creditsUSD[_guest] -= _amountUSD;

            // if balance is now 0, remove _guest from balance tracking
            if (creditsUSD[_guest] == 0) {
                delete creditsUSD[_guest];
                creditsAddrArray = GTAD.remAddressFromArray(_guest, creditsAddrArray);
            }
        } else { 
            creditsUSD[_guest] += _amountUSD; 
            creditsAddrArray = GTAD.addAddressToArraySafe(_guest, creditsAddrArray, true); // true = no dups
        }
    }
    function _transferBestDebitStableUSD(address _receiver, uint32 _amountUSD) private returns (address) {
        // traverse 'whitelistStables' w/ bals ok for debit, select stable with lowest market value
        address stable = GTAD._getBestDebitStableUSD(_amountUSD);

        // send '_amountUSD' to '_receiver', using lowest market value whitelist stable
        IERC20(stable).transfer(_receiver, _amountUSD * 10**18);

        // syncs w/ 'settleBalances' algorithm
        GTAD._increaseWhitelistPendingDebit(stable, _amountUSD);

        return stable;

        // LEFT OFF HERE ... all '*USD' vars are currently converted to wei using '*USD * 10**18'
        //  during 'transfer' or calcs for misc comparisons, but this might be wrong,
        //  need to verify this conversion w/ stable contract integrations (could be 10**6 thats need, maybe)
    }

    // swap 'buyAndBurnUSD' amount of best market stable, for GTA (traverses 'uswapV2routers')
    function _processBuyAndBurnStableSwap(address stable, uint32 _buyAndBurnUSD) private returns (uint256) {
        address[] memory stab_gta_path = new address[](2);
        stab_gta_path[0] = stable;
        stab_gta_path[1] = address(this);
        (uint8 rtrIdx, uint256 gta_amnt) = _best_swap_v2_router_idx_quote(stab_gta_path, _buyAndBurnUSD * 10**18, GTAD.uswapV2routers());
        uint256 gta_amnt_out = _swap_v2_wrap(stab_gta_path, GTAD.uswapV2routers()[rtrIdx], _buyAndBurnUSD * 10**18, address(this));
        return gta_amnt_out;
    }
    function _hostCanCreateEvent(address _host, uint32 _entryFeeUSD) private view returns (bool) {
        // get best stable quote for host's gta_bal (traverses 'uswapV2routers')
        uint256 gta_bal = IERC20(address(this)).balanceOf(_host); // returns x10**18
        address[] memory gta_stab_path = new address[](2);
        gta_stab_path[0] = address(this);
        gta_stab_path[1] = _getStableTokenHighMarketValue(GTAD.whitelistStables(), GTAD.uswapV2routers());
        (uint8 rtrIdx, uint256 stable_quote) = _best_swap_v2_router_idx_quote(gta_stab_path, gta_bal, GTAD.uswapV2routers());
        return stable_quote >= ((_entryFeeUSD * 10**18) * (GTAD.hostGtaBalReqPerc()/100));
    }
    function _gtaHoldingRequiredToHost(uint32 _entryFeeUSD) private view returns (uint256) {
        require(_entryFeeUSD > 0, 'err: _entryFeeUSD is 0 :/');
        address[] memory stab_gta_path = new address[](2);
        stab_gta_path[0] = _getStableTokenHighMarketValue(GTAD.whitelistStables(), GTAD.uswapV2routers());
        stab_gta_path[1] = address(this);
        (uint8 rtrIdx, uint256 gta_quote) = _best_swap_v2_router_idx_quote(stab_gta_path, (_entryFeeUSD * 10**18) * (GTAD.hostGtaBalReqPerc()/100), GTAD.uswapV2routers());
        return gta_quote;
    }

    // LEFT OFF HERE ... need external keeper support functions
    //  to get current profits (maybe track accumulated *feeUSD)
    function _payHost(address _host, uint32 _amntUSD, address _eventCode) private {
        address stable_host = _transferBestDebitStableUSD(_host, _amntUSD);
        emit PaidHostFee(_host, _amntUSD, _eventCode);
    }
    function _payKeeper(uint32 _amntUSD, address _eventCode) private {
        address stable_keeper = _transferBestDebitStableUSD(GTAD.keeper(), _amntUSD);
        emit PaidHostFee(GTAD.keeper(), _amntUSD, _eventCode);
    }
    function _paySupport(uint32 _amntUSD, address _eventCode) private {
        (address[] memory staff, uint32[] memory indFees) = GTAD.getSupportStaffWithIndFees(_amntUSD);
        if (staff.length != indFees.length ) {
            string memory err = 'staff and indFees length mismatch, from GTAD.getSupportStaffWithIndFees :/';
            emit FailedPaySupportFee(_amntUSD, _eventCode, err);
            return;
        }
        for (uint i=0; i < staff.length; i++) {
            address stable_supp = _transferBestDebitStableUSD(staff[i], indFees[i]);
            emit PaidSupportFee(staff[i], indFees[i], _amntUSD, _eventCode);
        }
    }

    /* -------------------------------------------------------- */
    /* ERC20 - OVERRIDES                                        */
    /* -------------------------------------------------------- */
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (from != address(this)) {
            return super.transferFrom(from, to, value);
        } else {
            _transfer(from, to, value); // balance checks, etc. indeed occur
        }
        return true;
    }
}
