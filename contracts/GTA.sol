// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;        

// deploy
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// local _ $ npm install @openzeppelin/contracts
import "./node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./node_modules/@openzeppelin/contracts/access/Ownable.sol"; 

// iterface
import "./GTADelegate.sol";

/* terminology...
                 join -> room, game, event, activity
             register -> seat, player, delegates, users, participants, entrants
    payout/distribute -> rewards, winnings, earnings, recipients 
*/
interface IGTADelegate {
    // LEFT OFF HERE ... need external getters for these public variables
    // uint32 public minEventEntryFeeUSD;
    // uint8 public maxHostFeePerc;
    // uint8 public minDepositUSD;
    // address public TOK_WPLS;
    // uint256 public depositFeePerc; // % of all deposits taken from 'creditsUSD' in 'settleBalances' (keeper controlled)
    // uint8 public keeperFeePerc; // 1% of event total entryFeeUSD
    // uint8 public serviceFeePerc; // 10% of event total entryFeeUSD
    // uint8 public supportFeePerc; // 0% of event total entryFeeUSD

    // public access
    function infoGtaBalanceRequired() external view returns (uint256); // auto-generated getter
    function burnGtaBalanceRequired() external view returns (uint256); // auto-generated getter
    function cancelGtaBalanceRequired() external view returns (uint256); // auto-generated getter
    function minEventEntryFeeUSD() external view returns (uint32); // auto-generated getter
    function maxHostFeePerc() external view returns (uint8);
    function _generateAddressHash(address host, string memory uid) external view returns (address);
    function _hostCanCreateEvent(address _host, uint32 _entryFeeUSD) external view returns (bool);
    function gtaHoldingRequiredToHost(address _tok_gta, uint32 _entryFeeUSD) external returns (uint256);
    function _getTotalsOfArray(uint8[] calldata _arr) external pure returns (uint8);
    function _validatePercsInArr(uint8[] calldata _percs) external pure returns (bool);
    function addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) external pure returns (address[] memory);
    function remAddressFromArray(address _addr, address[] memory _arr) external pure returns (address[] memory);
    function getWhitelistStables() external view returns (address[] memory);
    function getWhitelistAlts() external view returns (address[] memory);
    function _isTokenInArray(address _addr, address[] memory _arr) external pure returns (bool);

    // onlyKeeper access
    function getKeeper() external view returns (address);
    function _getBestDebitStableUSD(uint32 _amountUSD) external view returns (address);
    function _processBuyAndBurnStableSwap(address stable, uint32 _buyAndBurnUSD) external returns (uint256);
    function _increaseWhitelistPendingDebit(address token, uint256 amount) external;
    function _sanityCheck(address token, uint256 amount) external returns (bool);
    function getNextStableTokDeposit() external returns (address);
    function best_swap_v2_router_idx_quote(address[] memory path, uint256 amount) external view returns (uint8, uint256);
    function addAccruedGFRL(uint256 _gasAmnt) external returns (uint256);
    function getAccruedGFRL() external view returns (uint256);
    function getSwapRouters() external view returns (address[] memory);
    function swap_v2_wrap(address[] memory path, address router, uint256 amntIn, address gtaContract) external returns (uint256);

    // LEFT OFF HERE ... finish creating this interface
}
contract GamerTokeAward is ERC20, Ownable {
    /* -------------------------------------------------------- */
    /* GLOBALS                                                  */
    /* -------------------------------------------------------- */
    /* _ ADMIN SUPPORT _ */
    IGTADelegate private GTAD; // 'keeper' maintained within
    
    /* _ TOKEN INIT SUPPORT _ */
    string private constant tok_name = "_TEST GTA IERC20";
    string private constant tok_symb = "_TEST_GTA";
        
    /* _ GAME SUPPORT _ */
    // map generated gameCode address to Game struct
    mapping(address => Event_0) private activeGames;
    
    // track activeGameCount using 'createGame' & '_endEvent'
    uint64 private activeGameCount = 0; 

    // track activeGameCodes array for keeper 'keeperGetGameCodes'
    address[] private activeGameCodes = new address[](0);

    // track transfer of active events to dead events
    mapping(address => Event_0) private deadEvents;
    uint64 private deadEventCount = 0; 
    address[] private deadEventCodes = new address[](0);

    // game experation time (keeper control); uint32 max = 4,294,967,295 (~49,710 days)
    uint32 private gameExpSec = 86400 * 1; // 1 day = 86400 seconds

    /* _ CREDIT SUPPORT _ */
    // usd credits used to process player deposits, registers, refunds
    mapping(address => uint32) private creditsUSD;

    // set by '_updateCredits'; get by 'keeperGetCreditAddresses|keeperGetCredits'
    address[] private creditsAddrArray;
    
    // track last block# used to update 'creditsUSD' in 'settleBalances'
    uint32 private lastBlockNumUpdate = 0; // takes 1355 years to max out uint32

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

    /* -------------------------------------------------------- */
    /* STRUCTURES                                               */
    /* -------------------------------------------------------- */
    // LEFT OFF HERE ... migrate event structs over to GTADelegate
    //  maybe rename GTADelegate.sol to GTAEVent.sol ?

    /* _ GAME SUPPORT _ */
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

        Event_1 event_1;
        Event_2 event_2;
    }
    struct Event_1 { 
        // ------------------------------------------
        bool launched;  // 'hostStartEvent'
        bool ended;     // 'hostEndEventWithGuestRecipients'
        // bool expired;   // 'cancelEventAndProcessRefunds'
        // LEFT OFF HERE ... 'expired' is never used

        // ------------------------------------------
        mapping(address => bool) players; // true = registerd 
        address[] playerAddresses; // traversal access
        uint32 playerCnt;       // length or players; max 4,294,967,295

        /** host set */
        uint8 hostFeePerc;      // x% of prizePoolUSD

        // uint8 mintDistrPerc;    // % of ?
        
        /** _calcFeesAndPayouts */
        uint32 keeperFeeUSD;    // (entryFeeUSD * playerCnt) * keeperFeePerc
        uint32 serviceFeeUSD;   // (entryFeeUSD * playerCnt) * serviceFeePerc
        uint32 supportFeeUSD;   // (entryFeeUSD * playerCnt) * supportFeePerc
    }
    struct Event_2 { 
        uint32 totalFeesUSD;    // keeperFeeUSD + serviceFeeUSD + supportFeeUSD
        uint32 hostFeeUSD;      // prizePoolUSD * hostFeePerc
        uint32 prizePoolUSD;    // (entryFeeUSD * playerCnt) - totalFeesUSD - hostFeeUSD

        // ------------------------------------------
        uint8[] winPercs;       // %'s of prizePoolUSD - hostFeeUSD
        uint32[] payoutsUSD;    // prizePoolUSD * winPercs[]
        
        /** _calcFeesAndPayouts */
        uint32 keeperFeeUSD_ind;    // entryFeeUSD * keeperFeePerc
        uint32 serviceFeeUSD_ind;   // entryFeeUSD * serviceFeePerc
        uint32 supportFeeUSD_ind;   // entryFeeUSD * supportFeePerc
        uint32 totalFeesUSD_ind;    // keeperFeeUSD_ind + serviceFeeUSD_ind + supportFeeUSD_ind
        uint32 refundUSD_ind;       // entryFeeUSD - totalFeesUSD_ind
        uint32 refundsUSD;          // refundUSD_ind * evt.event_1.playerCnt
        uint32 hostFeeUSD_ind;      // (entryFeeUSD - totalFeesUSD_ind) * hostFeePerc

        uint32 buyGtaUSD;   // serviceFeeUSD * buyGtaPerc
    }

    /** _ DEFI SUPPORT _ */
    // used for deposits in keeper call to 'settleBalances'
    struct TxDeposit {
        address token;
        address sender;
        uint256 amount;
    }
    
    /* -------------------------------------------------------- */
    /* EVENTS                                                   */
    /* -------------------------------------------------------- */
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
    event ProcessedRefund(address player, uint32 refundAmountUSD, address evtCode, bool evtLaunched, uint256 evtExpTime);
    event CanceledEvent(address canceledBy, address evtCode, bool evtLaunched, uint256 evtExpTime, uint32 playerCount, uint32 prize_pool_usd, uint32 totalFeesUSD, uint32 totalRefundsUSD, uint32 indRefundUSD);

    // notify client side that someoen cracked the burn code and burned all gta in this contract
    event BurnedGTA(uint256 bal_cleaned, uint256 bal_burned, uint256 bal_earned, address code_cracker, uint64 guess_count);
    
    // notify clients a new burn code is set with type (easy, hard)
    event BurnCodeReset(bool setToHard);

    // notify client side that a player was registerd for event
    event RegisteredForEvent(address evtCode, uint32 entryFeeUSD, address player, uint32 playerCnt);

    /* -------------------------------------------------------- */
    /* CONSTRUCTOR                                              */
    /* -------------------------------------------------------- */
    // NOTE: pre-initialized 'GTADelegate' address required
    //      initializer w/ 'keeper' not required ('GTADelegate' maintained)
    //      sets msg.sender to '_owner' ('Ownable' maintained)
    constructor(uint256 _initSupply, address _gtad) ERC20(tok_name, tok_symb) Ownable(msg.sender) {
        GTAD = IGTADelegate(_gtad);
        _mint(msg.sender, _initSupply * 10**uint8(decimals())); // 'emit Transfer'
    }

    // NOTE: call from contructor not required
    //      call from 'keeper' not required
    function setGTAD(address _gtad) public onlyKeeper {
        require(_gtad != address(0), 'err: invalid delegate contract address :/');
        GTAD = IGTADelegate(_gtad);

        // LEFT OFF HERE ... mint GTA to msg.sender whenever this function is called
    }

    /* -------------------------------------------------------- */
    /* MODIFIERS                                                */
    /* -------------------------------------------------------- */
    modifier onlyAdmins(address gameCode) {
        require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
        bool isHost = msg.sender == activeGames[gameCode].host;
        bool isKeeper = msg.sender == GTAD.getKeeper();
        bool isOwner = msg.sender == owner(); // from 'Ownable'
        require(isKeeper || isOwner || isHost, 'err: only admins :/*');
        _;

        // LEFT OFF HERE ... not sure check for owner() is valid here
        //     onlyAdmins is only used in 'getPlayers'
    }
    modifier onlyKeeper() {
        require(msg.sender == GTAD.getKeeper(), "Only the keeper :p");
        _;
    }
    modifier onlyHolder(uint256 _requiredAmount) {
        require(balanceOf(msg.sender) >= _requiredAmount, 'err: need more GTA');
        _;
    }

    /* -------------------------------------------------------- */
    /* PUBLIC ACCESSORS - KEEPER SUPPORT                        */
    /* -------------------------------------------------------- */
    function keeperGetGameCodes() external view onlyKeeper returns (address[] memory, uint64) {
        return (activeGameCodes, activeGameCount);
    }
    function keeperGetCreditAddresses() external view onlyKeeper returns (address[] memory) {
        require(creditsAddrArray.length > 0, 'err: no addresses found with credits :0');
        return creditsAddrArray;
    }
    function keeperGetCredits(address _player) external view onlyKeeper returns (uint32) {
        require(_player != address(0), 'err: no zero address :{=}');
        return creditsUSD[_player];
    }
    function keeperSetGameExpSec(uint32 _sec) external onlyKeeper {
        require(_sec > 0, 'err: no zero :{}');
        gameExpSec = _sec;
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
    function keeperDeleteDeadEvent(address _evtCode) external onlyKeeper {
        require(_evtCode != address(0) && deadEvents[_evtCode].host != address(0), 'err: invalid event code :/');
        _deleteDeadEvent(_evtCode);
    }
    function keeperCleanOutDeadEvents() external onlyKeeper {
        for (uint i; i < deadEventCodes.length; i++) {
            // NOTE: no error check for address(0), want to clean regardless            
            delete deadEvents[deadEventCodes[i]]; // delete event mapping
        }
        deadEventCodes = new address[](0);
        deadEventCount = 0;
    }
    function keeperSetMintGtaToHost(bool _mintToHost) external onlyKeeper {
        mintGtaToHost = _mintToHost;
    }
    
    /* -------------------------------------------------------- */
    /* PUBLIC ACCESSORS - GTA HOLDER SUPPORT                    */
    /* -------------------------------------------------------- */
    function infoGetPlayersForGameCode(address _gameCode) external view onlyHolder(GTAD.infoGtaBalanceRequired()) returns (address[] memory) {
        require(_gameCode != address(0) && activeGames[_gameCode].host != address(0), 'err: invalid game code :O');
        return _getPlayers(_gameCode);
    }
    function infoGetBurnGtaBalanceRequired() external view onlyHolder(GTAD.infoGtaBalanceRequired()) returns (uint256) {
        return GTAD.burnGtaBalanceRequired();
    }
    function infoGetDetailsForEventCode(address _eventCode) external view onlyHolder(GTAD.infoGtaBalanceRequired()) returns (address, address, string memory, uint32, uint8[] memory, uint8, uint256, uint256, uint256, uint256) {
        require(_eventCode != address(0) && activeGames[_eventCode].host != address(0), 'err: invalid event code :O');
        return _getPublicEventDetails(_eventCode);
    }
    function _getPublicEventDetails(address _eventCode) private view returns (address, address, string memory, uint32, uint8[] memory, uint8, uint256, uint256, uint256, uint256) {
        require(activeGames[_eventCode].host != address(0), 'err: invalid event');
        Event_0 storage e = activeGames[_eventCode];
        Event_1 storage e1 = e.event_1;
        Event_2 memory e2 = e.event_2;
        string memory eventName = e.gameName;
        return (_eventCode, e.host, eventName, e.entryFeeUSD, e2.winPercs, e1.hostFeePerc, e.createBlockNum, e.createTime, e.startTime, e.expTime);
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
    function checkMyRegistrationForEvent(address _eventCode) external view returns (bool) {
        require(_eventCode != address(0), 'err: no event code ;o');

        // validate _eventCode exists
        Event_0 storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid event code :I');

        // check msg.sender is registered
        return evt.event_1.players[msg.sender];
    }

    // verify your own GTA holding required to host
    function checkMyGtaBalanceRequiredToHost(uint32 _entryFeeUSD) external view returns (bool) {
        require(_entryFeeUSD > 0, 'err: no entry fee :/');
        require(GTAD._hostCanCreateEvent(msg.sender, _entryFeeUSD), 'err: not enough GTA to host :/');
        return true;
    }

    function getGtaBalanceRequiredToHost(uint32 _entryFeeUSD) external view returns (uint256) {
        require(_entryFeeUSD > 0, 'err: _entryFeeUSD is 0 :/');
        return GTAD.gtaHoldingRequiredToHost(address(this), _entryFeeUSD);
    }
    function getGtaBalanceRequiredForInfo() external view returns (uint256) {
        return GTAD.infoGtaBalanceRequired();
    }
    function getGameCode(address _host, string memory _gameName) external view returns (address) {
        require(activeGameCount > 0, "err: no activeGames :{}"); // verify there are active activeGames
        require(_host != address(0x0), "err: no host address :{}"); // verify _host address input
        require(bytes(_gameName).length > 0, "err: no game name :{}"); // verifiy _gameName input

        // gameCode = hash(_host, _gameName)
        return _getGameCode(_host, _gameName);
    }

    function createEvent(string memory _eventName, uint64 _startTime, uint32 _entryFeeUSD, uint8 _hostFeePerc, uint8[] calldata _winPercs) public returns (address) {
        require(_startTime > block.timestamp, "err: start too soon :/");
        require(_entryFeeUSD >= GTAD.minEventEntryFeeUSD(), "err: entry fee too low :/");
        require(_hostFeePerc <= GTAD.maxHostFeePerc(), 'err: host fee too high :O, check maxHostFeePerc');
        require(_winPercs.length >= 0, 'err: _winPercs.length, SHOULD NOT OCCUR :/'); // NOTE: _winPercs.length = 0, means no winners paid
        require(GTAD._validatePercsInArr(_winPercs), 'err: invalid _winPercs; only 1 -> 100 allowed <=[]'); // NOTE: _winPercs.length = 0, return true
        require(GTAD._getTotalsOfArray(_winPercs) + _hostFeePerc == 100, 'err: _winPercs + _hostFeePerc != 100 (total 100% required) :/');
        
        require(GTAD._hostCanCreateEvent(msg.sender, _entryFeeUSD), "err: not enough GTA to host, check getGtaBalanceRequiredToHost :/");

        // SAFE-ADD
        uint64 expTime = _startTime + uint64(gameExpSec);
        require(expTime > _startTime, "err: stop f*ckin around :X");

        // verify name/code doesn't yet exist in 'activeGames'
        address eventCode = GTAD._generateAddressHash(msg.sender, _eventName);
        require(activeGames[eventCode].host == address(0), 'err: game name already exists :/');

        // Creates a default empty 'Event_0' struct for 'eventCode' (doesn't exist yet)
        //  NOTE: declaring storage ref to a struct, works directly w/ storage slot that the struct occupies. 
        //    ie. modifying the newEvent will indeed directly affect the state stored in activeGames[eventCode].
        Event_0 storage newEvent = activeGames[eventCode];
    
        // set properties for default empty 'Game' struct
        newEvent.host = msg.sender;
        newEvent.gameName = _eventName;
        newEvent.entryFeeUSD = _entryFeeUSD;
        newEvent.event_2.winPercs = _winPercs; // [%_1st_place, %_2nd_place, ...] = prizePoolUSD - hostFeePerc
        newEvent.event_1.hostFeePerc = _hostFeePerc; // hostFeePerc = prizePoolUSD - winPercs
        newEvent.createTime = block.timestamp;
        newEvent.createBlockNum = block.number;
        newEvent.startTime = _startTime;
        newEvent.expTime = expTime;

        // increment support
        activeGameCodes = GTAD.addAddressToArraySafe(eventCode, activeGameCodes, true); // true = no dups
        activeGameCount++;
        
        // LEFT OFF HERE ... need emit notification for 'createEvent' event

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
        Event_0 storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid _eventCode :I');

        // check if game launched
        require(!evt.event_1.launched, "err: event already started :(");

        // check if host trying to register
        require(evt.host != msg.sender, 'err: invalid guest, no host registration :{}');

        // check msg.sender already registered
        require(!evt.event_1.players[msg.sender], 'err: already registered for this _eventCode :p');

        // check msg.sender for enough credits
        require(evt.entryFeeUSD < creditsUSD[msg.sender], 'err: invalid credits, use checkMyCredits & send whitelistAlts|whitelistStables to this contract :P');

        // debit guest entry fee from creditsUSD[msg.sender] (ie. guest credits)
        _updateCredits(msg.sender, evt.entryFeeUSD, true); // true = debit

        // -1) add msg.sender to event
        _addGuestToEvent(msg.sender, _eventCode);
        
        // notify client side that a player was registerd for event
        emit RegisteredForEvent(_eventCode, evt.entryFeeUSD, msg.sender, evt.event_1.playerCnt);
        
        return true;
    }

    // hosts can pay to add guests to their own events (debits from host credits)
    function hostRegisterSeatForEvent(address _guest, address _eventCode) public returns (bool) {
        require(_guest != address(0), 'err: no _guest ;l');
        require(_eventCode != address(0), 'err: no _eventCode ;l');

        // get/validate active game
        Event_0 storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid _eventCode :I');

        // check if msg.sender is _eventCode host
        require(evt.host == msg.sender, 'err: only event host :/');

        // check if host trying to register host
        require(evt.host != _guest, 'err: invalid guest, no host registration :{}');

        // check if event launched
        require(!evt.event_1.launched, 'err: event already started :(');

        // check _guest already registered
        require(!evt.event_1.players[_guest], 'err: _guest already registered for this _eventCode :p');

        // check msg.sender for enough credits
        require(evt.entryFeeUSD < creditsUSD[msg.sender], 'err: invalid credits :(, use checkMyCredits & send whitelistAlts|whitelistStables to this contract :p');

        // debit guest entry fee from creditsUSD[msg.sender] (ie. host credits)
        _updateCredits(msg.sender, evt.entryFeeUSD, true); // true = debit

        // -1) add player to game event
        _addGuestToEvent(_guest, _eventCode);

        // notify client side that a _guest was registerd for event
        emit RegisteredForEvent(_eventCode, evt.entryFeeUSD, _guest, evt.event_1.playerCnt);

        return true;
    }

    // cancel event and process refunds (host, guests, keeper)
    //  host|keeper can cancel if event not 'launched' yet
    //  guests can cancel if event not 'launched' & 'expTime' has passed
    function cancelEventAndProcessRefunds(address _eventCode) external onlyHolder(GTAD.cancelGtaBalanceRequired()){
        require(_eventCode != address(0), 'err: no event code :<>');

        // get/validate active event
        Event_0 storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid event code :<>');
        
        // check for valid sender to cancel (only registered players, host, or keeper)
        bool isValidSender = evt.event_1.players[msg.sender] || msg.sender == evt.host || msg.sender == GTAD.getKeeper();
        require(isValidSender, 'err: only registerd guests or host :<>');

        // for host|guest|keeper cancel, verify event not launched
        require(!evt.event_1.launched, 'err: event already started :<>'); 

        // for guest cancel, also verify event expTime must be passed 
        if (evt.event_1.players[msg.sender]) {
            require(evt.expTime < block.timestamp, 'err: event code not expired yet :<>');
        } 

        // loop through guests & process refunds via '_updateCredits'
        for (uint i=0; i < evt.event_1.playerAddresses.length; i++) {
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

            // credit guest in 'creditsUSD' w/ amount 'refundUSD_ind' (calc/set in 'hostStartEvent')
            _updateCredits(evt.event_1.playerAddresses[i], evt.event_2.refundUSD_ind, false); // false = credit

            // notify listeners of processed refund
            emit ProcessedRefund(evt.event_1.playerAddresses[i], evt.event_2.refundUSD_ind, _eventCode, evt.event_1.launched, evt.expTime);
        }
        
        // set event params to end state
        _endEvent(_eventCode);

        // notify listeners of canceled event
        emit CanceledEvent(msg.sender, _eventCode, evt.event_1.launched, evt.expTime, evt.event_1.playerCnt, evt.event_2.prizePoolUSD, evt.event_2.totalFeesUSD, evt.event_2.refundsUSD, evt.event_2.refundUSD_ind);
    }

    // host can start event w/ guests pre-registerd for _eventCode
    function hostStartEvent(address _eventCode) public returns (bool) {
        require(_eventCode != address(0), 'err: no event code :p');

        // get/validate active game
        Event_0 storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is game host
        require(evt.host == msg.sender, 'err: only host :/');

        // check if event not started yet
        require(!evt.event_1.launched, 'err: event already started');

        // calc/set 'prizePoolUSD' & 'payoutsUSD' from 'entryFeeUSD' collected
        //  calc/deduct all fees & generate 'buyGtaUSD' from 'serviceFeeUSD'
        evt = _calcFeesAndPayouts(evt); // ? Event_0 storage evt = _calcFeesAndPayouts(evt); ?
        evt = _launchEvent(evt); // set event state to 'launched = true'

        return true;
    }

    // _winners: [0x1st_place, 0x2nd_place, ...]
    // earners, gainers, recipients, receivers, achievers, Leaders, Victors, PaidGuests
    function hostEndEventWithGuestRecipients(address _eventCode, address[] memory _guests) public returns (bool) {
        require(_eventCode != address(0), 'err: no event code :p');

        // NOTE: _guests.lengh = 0, means no winners are paid
        require(_guests.length >= 0, 'err: _guests.length, SHOULD NOT OCCUR :p');

        // get/validate active game
        Event_0 storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is event host
        require(evt.host == msg.sender, 'err: only host :/');

        // check if event started
        require(evt.event_1.launched, 'err: event not started yet');

        // check if # of _guests.length == winPercs.length == payoutsUSD.length (set during createEvent & hostStartEvent)
        require(evt.event_2.winPercs.length == _guests.length && _guests.length == evt.event_2.payoutsUSD.length, 'err: _guests.length != size of winPercs[] & payoutsUSD[] =(');

        // LEFT OFF HERE ... currently '_processBuyAndBurnStableSwap' swaps through GTADelegate.sol
        //  but GTA.sol contract address needs to provide the stable and receive the GTA (during swap)
        //  NOTE: it appears that the only way to do this is to have GTA.sol directly call 'swapExactTokensForTokens'
        //     ... maybe use GTADelegate as an abstract calls and have GTA.sol inherit from it as a child contract

        // buy GTA from open market (using 'buyGtaUSD' = 'buyGtaPerc' of 'serviceFeeUSD')
        //  NOTE: invokes 'GTAD._swap_v2_wrap' & uses msg.sender as 'outReceiver'
        uint256 gta_amnt_buy = GTAD._processBuyAndBurnStableSwap(GTAD._getBestDebitStableUSD(evt.event_2.buyGtaUSD), evt.event_2.buyGtaUSD);

        // calc 'gta_amnt_mint' using 'mintGtaPerc' of 'gta_amnt_buy' 
        //  gta_amnt_mint gets divided equally to all '_winners' + host (if 'mintGtaToHost'; keeper controlled)
        // NOTE: remaining 'gta_amnt_buy' is simply held by this GTA contract
        uint256 gta_amnt_mint_ind = (gta_amnt_buy * (mintGtaPerc/100)) / (_guests.length + (mintGtaToHost ? 1 : 0)); // +1 = host

        // mint GTA to host (if applicable; keeper controlled)
        if (mintGtaToHost) { _mint(evt.host, gta_amnt_mint_ind); }

        // loop through _guests: distribute 'evt.event_2.winPercs'
        //  NOTE: if _guests.length == 0, then winPercs & payoutsUSD are empty arrays
        for (uint16 i=0; i < _guests.length; i++) {
            // verify winner address was registered in the event
            require(evt.event_1.players[_guests[i]], 'err: invalid player found :/, check getPlayers & retry w/ all valid players');

            // calc win_usd
            address winner = _guests[i];
            uint32 win_usd = evt.event_2.payoutsUSD[i];

            // pay winner (w/ lowest market value stable)
            address stable = _transferBestDebitStableUSD(winner, win_usd);

            // syncs w/ 'settleBalances' algorithm
            GTAD._increaseWhitelistPendingDebit(stable, win_usd);

            // mint GTA to this winner; amount is same for all winners & host (if applicable)
            _mint(winner, gta_amnt_mint_ind);

            // notify client side that an end event distribution occurred successfully
            emit EndEventDistribution(winner, i, evt.event_2.winPercs[i], win_usd, evt.event_2.prizePoolUSD, stable);
        }

        // pay host & keeper (w/ lowest market value stable; contract should maintain highest market value stables)
        //  NOTE: if _guests.length == 0, then 'hostFeePerc' == 100 (set in 'createEvent')
        //    HENCE, evt.event_2.hostFeeUSD == 100% of prizePoolUSD
        address stable_host = _transferBestDebitStableUSD(evt.host, evt.event_2.hostFeeUSD);
        address stable_keep = _transferBestDebitStableUSD(GTAD.getKeeper(), evt.event_1.keeperFeeUSD);

        // LEFT OFF HERE ... need to pay 'supportFeeUSD' to support staff somewhere
        //  also, maybe we should pay keeper and support in 'hostStartEvent'
        //  also, 'serviceFeeUSD' is simply maintained in contract, 
        //    but should we do something else with it? perhaps track it in global? perhaps send it to some service fee wallet address?
        
        // set event params to end state & transfer to deadEvents array
        _endEvent(_eventCode);

        // notify client side that an end event occurred successfully
        emit EndEventActivity(_eventCode, evt.host, _guests, evt.event_2.prizePoolUSD, evt.event_2.hostFeeUSD, evt.event_1.keeperFeeUSD, activeGameCount, block.timestamp, block.number);
        
        return true;
    }

    /* -------------------------------------------------------- */
    /* KEEPER CALL-BACK                                         */
    /* -------------------------------------------------------- */
    // invoked by keeper client side, every ~10sec (~blocktime), to ...
    //  1) update credits logged from 'Transfer' emits
    //  2) convert alt deposits to stables (if needed)
    //  3) settle 'creditsUSD', 'contractBalances' & 'whitelistPendingDebits' (keeper 'SANITY CHECK')
    function settleBalances(TxDeposit[] memory dataArray, uint32 _lastBlockNum) public onlyKeeper {
        uint256 start_refund = gasleft(); // record start gas amount
        require(lastBlockNumUpdate < _lastBlockNum, 'err: invalid _lastBlockNum :O');

        // loop through ERC-20 'Transfer' events received from client side
        //  NOTE: to save gas (refunded by contract), keeper 'should' pre-filter event for ...
        //      1) 'whitelistStables' & 'whitelistAlts' (else 'require' fails)
        //      2) recipient = this contract address (else '_sanityCheck' fails)
        for (uint i = 0; i < dataArray.length; i++) { // python side: lst_evts_min[{token,sender,amount}, ...]
            bool is_wl_stab = GTAD._isTokenInArray(dataArray[i].token, GTAD.getWhitelistStables());
            bool is_wl_alt = GTAD._isTokenInArray(dataArray[i].token, GTAD.getWhitelistAlts());
            if (!is_wl_stab && !is_wl_alt) { continue; } // skip non-whitelist tokens
            
            address tok_addr = dataArray[i].token;
            address src_addr = dataArray[i].sender;
            uint256 tok_amnt = dataArray[i].amount;
            
            if (tok_addr == address(0) || src_addr == address(0)) { continue; } // skip 0x0 addresses
            if (tok_amnt == 0) { continue; } // skip 0 amount

            // verifiy keeper sent legit amounts from their 'Transfer' event captures (1 FAIL = revert everything)
            //   ie. force start over w/ new call & no gas refund; encourages keeper to not fuck up
            require(GTAD._sanityCheck(tok_addr, tok_amnt), "err: whitelist<->chain balance mismatch :-{} _ KEEPER LIED!");

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
                (uint8 rtrIdx, uint256 stableAmnt) = GTAD.best_swap_v2_router_idx_quote(alt_stab_path, tok_amnt);

                // if stable amount quote is below min deposit required
                if (stableAmnt < GTAD.minDepositUSD()) {  

                    // if refunds enabled, process refund: send 'tok_amnt' of 'tok_addr' back to 'src_addr'
                    if (GTAD.enableMinDepositRefunds) {
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
                    emit DepositFailed(src_addr, tok_addr, tok_amnt, stableAmnt, GTAD.minDepositUSD(), GTAD.enableMinDepositRefunds);

                    // skip to next transfer in 'dataArray'
                    continue;
                }

                // LEFT OFF HERE ... currently 'GTAD.swap_v2_wrap' swaps through GTADelegate.sol
                //  but GTA.sol contract address needs to provide the alt and receive the stable (during swap)
                //  NOTE: it appears that the only way to do this is to have GTA.sol directly call 'swapExactTokensForTokens'
                //     ... maybe use GTADelegate as an abstract calls and have GTA.sol inherit from it as a child contract

                // swap tok_amnt alt -> stable (log swap fee / gas loss)
                uint256 start_swap = gasleft();
                stable_credit_amnt = GTAD.swap_v2_wrap(alt_stab_path, GTAD.getSwapRouters()[rtrIdx], tok_amnt, address(this));
                uint256 gas_swap_loss = (start_swap - gasleft()) * tx.gasprice;

                // get stable quote for this swap fee / gas fee loss (traverses 'uswapV2routers')
                address[] memory wpls_stab_path = new address[](2);
                wpls_stab_path[0] = GTAD.TOK_WPLS();
                wpls_stab_path[1] = stable_addr;
                (uint8 idx, uint256 amountOut) = GTAD.best_swap_v2_router_idx_quote(wpls_stab_path, gas_swap_loss);
                
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
        uint256 bal_burn = bal * (burnGtaPerc/100);
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
        require(activeGames[gameCode].host != address(0), 'err: game name for host not found :{}');
        return gameCode;
    }
    function _getPlayers(address _gameCode) private view returns (address[] memory) {
        require(activeGames[_gameCode].host != address(0), 'err: _gameCode not found :{}');
        return activeGames[_gameCode].event_1.playerAddresses; // '.event_1.players' is mapping
    }
    // debits/credits for a _player in 'creditsUSD' (used during deposits and event registrations)
    function _updateCredits(address _player, uint32 _amountUSD, bool _debit) private {
        if (_debit) { 
            // ensure there is enough credit before debit
            require(creditsUSD[_player] >= _amountUSD, 'err: invalid credits to debit :[');
            creditsUSD[_player] -= _amountUSD;

            // if balance is now 0, remove _player from balance tracking
            if (creditsUSD[_player] == 0) {
                delete creditsUSD[_player];
                creditsAddrArray = GTAD.remAddressFromArray(_player, creditsAddrArray);
            }
        } else { 
            creditsUSD[_player] += _amountUSD; 
            creditsAddrArray = GTAD.addAddressToArraySafe(_player, creditsAddrArray, true); // true = no dups
        }
    }
    function _transferBestDebitStableUSD(address _receiver, uint32 _amountUSD) private returns (address) {
        // traverse 'whitelistStables' w/ bals ok for debit, select stable with lowest market value
        address stable = GTAD._getBestDebitStableUSD(_amountUSD);

        // send 'win_usd' amount to 'winner', using 'currHighIdx' whitelist stable
        IERC20(stable).transfer(_receiver, _amountUSD * 10**18);
        return stable;
    }

    function _addGuestToEvent(address _player, address _evtCode) private {
        Event_0 storage _evt = activeGames[_evtCode];
        _evt.event_1.players[_player] = true;
        _evt.event_1.playerAddresses.push(_player);
        _evt.event_1.playerCnt = uint32(_evt.event_1.playerAddresses.length);
    }

    // set event param to end state
    function _endEvent(address _evtCode) private {
        require(_evtCode != address(0) && activeGames[_evtCode].host != address(0), 'err: invalid event code :P');
        require(activeGames[_evtCode].event_1.launched, 'err: event not launched');

        Event_0 storage _evt = activeGames[_evtCode];
        // set game end state (doesn't matter if its about to be deleted)
        _evt.endTime = block.timestamp;
        _evt.endBlockNum = block.number;
        _evt.event_1.ended = true;

        // transfer active events to dead events
        deadEvents[_evtCode] = activeGames[_evtCode];
        deadEventCodes = GTAD.addAddressToArraySafe(_evtCode, deadEventCodes, true);
        deadEventCount++;

        // remove active event
        delete activeGames[_evtCode]; // delete event mapping
        activeGameCodes = GTAD.remAddressFromArray(_evtCode, activeGameCodes);
        activeGameCount--;
    }
    function _deleteDeadEvent(address _evtCode) private {
        require(_evtCode != address(0) && deadEvents[_evtCode].host != address(0), 'err: invalid event code :/');
        delete deadEvents[_evtCode]; // delete event mapping
        deadEventCodes = GTAD.remAddressFromArray(_evtCode, deadEventCodes);
        deadEventCount--;
    }

    // set event params to launched state
    function _launchEvent(Event_0 storage _evt) private returns (Event_0 storage ) {
        require(!_evt.event_1.launched, 'err: event already launched');

        // set event fee calculations & prizePoolUSD
        // set event launched state
        _evt.launchTime = block.timestamp;
        _evt.launchBlockNum = block.number;
        _evt.event_1.launched = true;
        return _evt;
    }

    // calc prizePoolUSD, payoutsUSD, keeperFeeUSD, serviceFeeUSD, supportFeeUSD, refundsUSD, totalFeesUSD
    function _calcFeesAndPayouts(Event_0 storage _evt) private returns (Event_0 storage) {
        /* DEDUCTING FEES
            current contract debits: 'depositFeePerc', 'hostFeePerc', 'keeperFeePerc', 'serviceFeePerc', 'supportFeePerc', 'winPercs'
             - depositFeePerc -> taken out of each deposit (alt|stable 'transfer' to contract) _ in 'settleBalances'
             - keeper|service|support fees -> taken from gross 'entryFeeUSD' calculated below
             - host fees -> taken from GROSS 'prizePoolUSD' generated below (ie. net 'entryFeeUSD')
             - win payouts -> taken from GROSS 'prizePoolUSD' generated below

            Formulas ...
                keeperFeeUSD = (entryFeeUSD * playerCnt) * keeperFeePerc
                serviceFeeUSD = (entryFeeUSD * playerCnt) * serviceFeePerc
                supportFeeUSD = (entryFeeUSD * playerCnt) * supportFeePerc
                totalFeesUSD = keeperFeeUSD + serviceFeeUSD + supportFeeUSD

                buyGtaUSD = serviceFeeUSD * buyGtaPerc

                GROSS entryFeeUSD = entryFeeUSD * playerCnt
                  NET entryFeeUSD = GROSS entryFeeUSD - totalFeesUSD

                GROSS serviceFeeUSD = GROSS entryFeeUSD * serviceFeePerc
                  NET serviceFeeUSD = GROSS serviceFeeUSD - buyGtaUSD
                
                NOTE: buyGtaUSD used to buy GTA from market (in 'hostEndEventWithGuestRecipients'),
                       which is then held by GTA contract address (until '_burnGTA' invoked)
                      then '_burnGTA' burns 'burnGtaPerc' of all GTA held
                       w/ remaining GTA held being sent to msg.sender

                GROSS prizePoolUSD = (entryFeeUSD * playerCnt) - (keeperFeeUSD + serviceFeeUSD + supportFeeUSD)
                        hostFeeUSD = GROSS prizePoolUSD * hostFeePerc
                  NET prizePoolUSD = GROSS prizePoolUSD - hostFeeUSD
                     payoutsUSD[i] = NET prizePoolUSD * 'winPercs[i]'

                NOTE: if 'winPercs.length' == 0 (then 'hostFeePerc' == 100, set in 'createEvent'), results in empty 'payoutsUSD' array
                 HENCE, this event will allow no _guests to be passed into 'hostEndEventWithGuestRecipients',
                    resulting in host receiving 100% of 'prizePoolUSD'
                
                NOTE: contract won't take responsibility for any errors w/ no winners declared by withholding funds or refunding credits, etc.
                 HENCE, full 'prizePoolUSD' will always be distributed (ie. to host)
        */

        // calc individual player fees (BEFORE generating 'prizePoolUSD') 
        //  '_ind' used for refunds in 'cancelEventAndProcessRefunds' (excludes 'hostFeeUSD_ind')
        _evt.event_2.keeperFeeUSD_ind = _evt.entryFeeUSD * (GTAD.keeperFeePerc()/100);
        _evt.event_2.serviceFeeUSD_ind = _evt.entryFeeUSD * (GTAD.serviceFeePerc()/100);
        _evt.event_2.supportFeeUSD_ind = _evt.entryFeeUSD * (GTAD.supportFeePerc()/100);

        // calc total fees for each individual 'entryFeeUSD' paid
        _evt.event_2.totalFeesUSD_ind = _evt.event_2.keeperFeeUSD_ind + _evt.event_2.serviceFeeUSD_ind + _evt.event_2.supportFeeUSD_ind;

        // calc: 'hostFeeUSD_ind' = 'hostFeePerc' of single 'entryFeeUSD' - 'totalFeesUSD_ind'
        _evt.event_2.hostFeeUSD_ind = (_evt.entryFeeUSD - _evt.event_2.totalFeesUSD_ind) * (_evt.event_1.hostFeePerc/100);

        // calc total fees for all 'entryFeeUSD' paid
        _evt.event_1.keeperFeeUSD = _evt.event_2.keeperFeeUSD_ind * _evt.event_1.playerCnt;
        _evt.event_1.serviceFeeUSD = _evt.event_2.serviceFeeUSD_ind * _evt.event_1.playerCnt; // GROSS
        _evt.event_1.supportFeeUSD = _evt.event_2.supportFeeUSD_ind * _evt.event_1.playerCnt;
        _evt.event_2.totalFeesUSD = _evt.event_1.keeperFeeUSD + _evt.event_1.serviceFeeUSD + _evt.event_1.supportFeeUSD;

        // LEFT OFF HERE ... always divide up 'serviceFeeUSD' w/ 'buyGtaPerc'?
        //                      or do we want to let the host choose?
        // potential model...
        // 1) remove GTA from the market: 
        //    LEGACY MODEL (N/A)
        //     - host choice: to pay service fee in GTA for a discount (and then we buy and burn)
        //    NEW MODEL
        //     - keeper set: buyGtaPerc of serviceFeeUSD = buyGtaUSD (for every event)
        //     - buyGtaUSD calculated & removed from 'serviceFeeUSD' (buys GTA from market in 'hostEndEventWithGuestRecipients')
        //     - host required to hold some GTA in order to host (handled in 'createEvent')
        //     - 'info|burn|cancel' public functions require holding GTA
        // 
        // 2) add GTA to the market: 
        //     - host gets minted some amount for hosting games (handled in 'hostEndEventWithGuestRecipients')
        //     - player gets minted some amount for winning games (handled in 'hostEndEventWithGuestRecipients')
        //
        // #2 always has to be less than #1 for every hosted event 
        //     - the value of amounts minted must always be less than the service fee
        //     NOTE: total amount minted to winners + host = 'mintGtaPerc' of GTA amount recieved from 'buyGtaUSD' from market

        // calc: TOT 'buyGtaUSD' = 'buyGtaPerc' of 'serviceFeeUSD'
        //       NET 'serviceFeeUSD' = 'serviceFeeUSD' - 'buyGtaUSD'
        //  NOTE: remaining NET 'serviceFeeUSD' is simply held by GTA contract address
        _evt.event_2.buyGtaUSD = _evt.event_1.serviceFeeUSD * (buyGtaPerc/100);
        _evt.event_1.serviceFeeUSD -= _evt.event_2.buyGtaUSD; // NET

        // calc idividual & total refunds (for 'cancelEventAndProcessRefunds', 'ProcessedRefund', 'CanceledEvent')
        _evt.event_2.refundUSD_ind = _evt.entryFeeUSD - _evt.event_2.totalFeesUSD_ind; 
        _evt.event_2.refundsUSD = _evt.event_2.refundUSD_ind * _evt.event_1.playerCnt;

        // calc: GROSS 'prizePoolUSD' = all 'entryFeeUSD' - 'totalFeesUSD'
        _evt.event_2.prizePoolUSD = (_evt.entryFeeUSD * _evt.event_1.playerCnt) - _evt.event_2.totalFeesUSD;

        // calc: 'hostFeeUSD' = 'hostFeePerc' of 'prizePoolUSD' (AFTER 'totalFeesUSD' deducted first)
        _evt.event_2.hostFeeUSD = _evt.event_2.prizePoolUSD * (_evt.event_1.hostFeePerc/100);

        // calc: NET 'prizePoolUSD' = gross 'prizePoolUSD' - 'hostFeeUSD'
        //  NOTE: not setting NET, allows for correct calc of payoutsUSD & correct emit logs
        // _evt.event_2.prizePoolUSD -= _evt.event_2.hostFeeUSD;
        
        // calc payoutsUSD (finally, AFTER all deductions)
        for (uint i=0; i < _evt.event_2.winPercs.length; i++) {
            _evt.event_2.payoutsUSD.push(_evt.event_2.prizePoolUSD * (_evt.event_2.winPercs[i]/100));
        }

        return _evt;
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
