// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;        
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
// import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV1Factory.sol";

interface IUniswapV2Factory {
    // ref: https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/V1/IUniswapV1Factory.sol
    function getExchange(address) external view returns (address);
}
interface IUniswapV2 {
    // ref: https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router01.sol
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external payable returns (uint[] memory amounts);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

/* terminology...
        join -> game, event, activity
    register -> player, delegates, users, participants, entrants
        payout -> winnings, earnings, rewards, recipients 
*/
contract GamerTokeAward is ERC20, Ownable {
    /* -------------------------------------------------------- */
    /* GLOBALS                                                  */
    /* -------------------------------------------------------- */
    /* _ ADMIN SUPPORT _ */
    address private keeper; // 37, curator, manager, caretaker, keeper
    
    /* _ TOKEN INIT SUPPORT _ */
    string private constant tok_name = "_TEST GTA IERC20";
    string private constant tok_symb = "_TEST_GTA";
    
    /* _ DEX GLOBAL SUPPORT _ */
    address[] public routersUniswapV2; // modifiers: addDexRouter/remDexRouter
    address private constant TOK_WPLS = address(0xA1077a294dDE1B09bB078844df40758a5D0f9a27);
        
    /* _ GAME SUPPORT _ */
    // map generated gameCode address to Game struct
    mapping(address => Game) public activeGames;
    
    // required GTA balance ratio to host game (ratio of entryFeeUSD desired)
    uint8 public hostRequirementPerc = 100; // uint8 max = 255
    
    // track activeGameCount using 'createGame' & '_endEvent'
    uint64 public activeGameCount = 0; 

    // track activeGameCodes array for keeper 'getGameCodes'
    address[] private activeGameCodes;
    
    // game experation time (keeper control)
    uint32 private gameExpSec = 86400 * 1; // 1 day = 86400 seconds; max 4,294,967,295
    
    /** _ DEFI SUPPORT _ */
    // track last block # used to update 'creditsUSD' in 'settleBalances'
    uint32 private lastBlockNumUpdate = 0; // takes 1355 years to max out uint32

    // arrays of accepted usd stable & alts for player deposits
    address[] public whitelistAlts;
    address[] public whitelistStables;
    uint8 private whitelistStablesUseIdx; // _getNextStableTokDeposit()

    // track all stables & alts that this contract has whitelisted
    address[] private contractStables;
    address[] private contractAlts;

    // track this contract's stable token balances & debits (required for keeper 'SANITY CHECK')
    mapping(address => uint256) private contractBalances;
    mapping(address => uint256) private whitelistPendingDebits;

    // usd credits used to process player deposits, registers, refunds
    mapping(address => uint256) private creditsUSD;

    // set by '_updateCredit'; get by 'getCreditAddress|getCredits'
    address[] private creditsAddrArray; 

    // minimum deposits allowed (in usd value)
    uint8 public constant minDepositUSD_floor = 1; // 1 USD 
    uint8 public constant minDepositUSD_ceiling = 100; // 100 USD
    uint8 public minDepositUSD = 0; // dynamic (keeper controlled)

    // enable/disable refunds for less than min deposit (keeper controlled)
    bool public enableMinDepositRefunds = true;

    // track gas fee wei losses due to min deposit refunds (keeper controlled reset)
    uint256 private accruedGasFeeRefundLoss = 0; 

    // min entryFeeUSD host can create event with (keeper control)
    uint256 public minEventEntryFeeUSD = 0;

    // max % of prizePoolUSD the host may charge (keeper controlled)
    uint8 public maxHostFeePerc = 100;

    // % of all deposits taken from 'creditsUSD' in 'settleBalances' (keeper controlled)
    uint256 private depositFeePerc = 0;

    // % of events total 'entryFeeUSD' collected (keeper controlled)
    uint8 public keeperFeePerc = 0;
    uint8 public serviceFeePerc = 0;
    uint8 public supportFeePerc = 0;

    // % of event 'serviceFeeUSD' to use to buy & burn GTA (keeper controlled)
    //  and % of buy & burn GTA to mint for winners
    // NOTE: 'ensures GTA amount burned' > 'GTA amount mint' (per event)
    uint8 public buyAndBurnPerc = 50;
    uint8 public buyAndBurnMintPerc;

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
    /* _ GAME SUPPORT _ */
    struct Game {
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
        uint256 expBlockNum;    // 'cancelEventProcessRefunds'
        bool launched;  // 'hostStartEvent'
        bool ended;     // 'hostEndEventWithWinners'
        bool expired;   // 'cancelEventProcessRefunds'

        mapping(address => bool) players; // true = registerd 
        uint32 playerCnt;       // length or players; max 4,294,967,295

        /** host set */
        uint8 hostFeePerc;      // x% of prizePoolUSD

        /** keeper set */
        uint8 keeperFeePerc;    // 1% of total entryFeeUSD
        uint8 serviceFeePerc;   // 10% of total entryFeeUSD
        uint8 supportFeePerc;   // 0% of total entryFeeUSD
        uint8 buyAndBurnPerc;   // 50% of serviceFeeUSD

        // uint8 mintDistrPerc;    // % of ?
        
        /** _generatePrizePool */
        uint32 keeperFeeUSD;    // (entryFeeUSD * playerCnt) * keeperFeePerc
        uint32 serviceFeeUSD;   // (entryFeeUSD * playerCnt) * serviceFeePerc
        uint32 supportFeeUSD;   // (entryFeeUSD * playerCnt) * supportFeePerc
        uint32 totalFeesUSD;    // keeperFeeUSD + serviceFeeUSD + supportFeeUSD
        uint32 hostFeeUSD;      // prizePoolUSD * hostFeePerc
        uint32 prizePoolUSD;    // (entryFeeUSD * playerCnt) - totalFeesUSD - hostFeeUSD

        uint8[] winPercs;       // %'s of prizePoolUSD - hostFeeUSD
        uint32[] payoutsUSD;    // prizePoolUSD * winPercs[]
        
        uint32 keeperFeeUSD_ind;    // entryFeeUSD * keeperFeePerc
        uint32 serviceFeeUSD_ind;   // entryFeeUSD * serviceFeePerc
        uint32 supportFeeUSD_ind;   // entryFeeUSD * supportFeePerc
        uint32 totalFeesUSD_ind;    // keeperFeeUSD_ind + serviceFeeUSD_ind + supportFeeUSD_ind
        uint32 refundUSD_ind;       // entryFeeUSD - totalFeesUSD_ind
        uint32 refundsUSD;          // refundUSD_ind * evt.playerCnt
        uint32 hostFeeUSD_ind;      // (entryFeeUSD - totalFeesUSD_ind) * hostFeePerc

        uint32 buyAndBurnUSD;   // serviceFeeUSD * buyAndBurnPerc
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
    event DepositFailed(address sender, address token, uint256 tokenAmount, uint256 stableAmount, uint256 minDepositUSD, bool refundsEnabled);

    // emit to client side when deposit processed (after sender's manual transfer to contract)
    event DepositProcessed(address sender, address token, uint256 amount, uint256 stable_swap_fee, uint256 depositFee, uint256 balance);

    // notify client side that an event distribution (winner payout) has occurred successuflly
    event EndEventDistribution(address winner, uint16 win_place, uint8 win_perc, uint32 win_usd, uint32 win_pool_usd, address stable);

    // notify client side that an end event has occurred successfully
    event EndEventActivity(address evtCode, address host, address[] winners, uint32 prizePoolUSD, uint32 hostFeelUSD, uint32 keeperFeeUSD, uint64 activeEvtCount, uint64 block_timestamp, uint256 block_number);

    // notify client side that an event has been canceled
    event ProcessedRefund(address player, uint32 refundAmountUSD, address evtCode, bool evtLaunched, uint256 evtExpTime);
    event CanceledEvent(address canceledBy, address evtCode, bool evtLaunched, uint256 evtExpTime, uint32 playerCount, uint32 prizePoolUSD, uint32 totalFeesUSD, uint32 totalRefundsUSD, uint32 indRefundUSD);

    // notify client side that someoen cracked the burn code and burned all gta in this contract
    event BurnedGTA(uint256 amount_burned, address code_cracker, uint64 guess_count);
    
    // notify clients a new burn code is set with type (easy, hard)
    event BurnCodeReset(bool setToHard);

    // notify client side that a player was registerd for event
    event RegisteredForEvent(address evtCode, uint32 entryFeeUSD, address player, uint32 playerCnt);

    /* -------------------------------------------------------- */
    /* CONSTRUCTOR                                              */
    /* -------------------------------------------------------- */
    // constructor(uint256 _initSupply, string memory _name, string memory _symbol) ERC20(_name, _symbol) Ownable(msg.sender) {
    constructor(uint256 _initSupply) ERC20(tok_name, tok_symb) Ownable(msg.sender) {
        // Set sender to keeper ('Ownable' maintains '_owner')
        keeper = msg.sender;
        _mint(msg.sender, _initSupply * 10**uint8(decimals())); // 'emit Transfer'
    }

    /* -------------------------------------------------------- */
    /* MODIFIERS                                                */
    /* -------------------------------------------------------- */
    modifier onlyAdmins(address gameCode) {
        require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
        bool isHost = msg.sender == activeGames[gameCode].host;
        bool isKeeper = msg.sender == keeper;
        bool isOwner = msg.sender == owner(); // from 'Ownable'
        require(isKeeper || isOwner || isHost, 'err: only admins :/*');
        _;
    }
    modifier onlyHost(address gameCode) {
        require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
        require(msg.sender == activeGames[gameCode].host, "Only the host :0");
        _;
    }    
    modifier onlyKeeper() {
        require(msg.sender == keeper, "Only the keeper :p");
        _;
    }
    modifier validGameCode(address gameCode) {
        require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
        _;
    }

    /* -------------------------------------------------------- */
    /* SIDE QUEST... CRACK THE BURN CODE                        */
    /* -------------------------------------------------------- */
    // public can try to guess the burn code (burn buyAndBurnPerc of the balance, earn the rest)
    // code required for 'burnGTA'
    //  EASY -> uint16: 65,535 (~1day=86,400 @ 10s blocks w/ 1 wallet)
    //  HARD -> uint32: 4,294,967,295 (~100yrs=3,110,400,00 @ 10s blocks w/ 1 wallet)
    function burnGTA_HARD(uint32 burnCode) public returns (bool) {
        BURN_CODE_GUESS_CNT++; // keep track of guess count
        require(USE_BURN_CODE_HARD, 'err: burn code set to easy, use burnGTA_EASY :p');
        require(burnCode == BURN_CODE_HARD, 'err: invalid burn_code, guess again :p');
        return _burnGTA();
    }
    function burnGTA_EASY(uint16 burnCode) public returns (bool) {
        BURN_CODE_GUESS_CNT++; // keep track of guess count
        require(!USE_BURN_CODE_HARD, 'err: burn code set to hard, use burnGTA_HARD :p');
        require(burnCode == BURN_CODE_EASY, 'err: invalid burn_code, guess again :p');
        return _burnGTA();
    }
    function _burnGTA() private returns (bool) {
        uint256 bal = super._balances[address(this)];
        require(bal > 0, 'err: no GTA to burn :p');

        // burn it.. burn it real good...
        //  burn 'buyAndBurnPerc' of 'bal', send rest to cracker
        uint256 bal_burn = bal * (buyAndBurnPerc/100);
        uint256 bal_earn = bal - bal_burn;
        IERC20(address(this)).transfer(address(0), bal_burn);
        IERC20(address(this)).transfer(msg.sender, bal_earn);

        // notify the world that shit was burned
        emit BurnedGTA(bal, msg.sender, BURN_CODE_GUESS_CNT);

        // reset guess count
        BURN_CODE_GUESS_CNT = 0;

        return true;
    }

    // code required for 'burnGTA'
    function setBurnCodeEasy(uint16 bc) public onlyKeeper {
        require(bc != BURN_CODE_EASY, 'err: same burn code, no changes made ={}');
        BURN_CODE_EASY = bc;
        USE_BURN_CODE_HARD = false;
        emit BurnCodeReset(USE_BURN_CODE_HARD);
    }
    function setBurnCodeHard(uint32 bc) public onlyKeeper {
        require(bc != BURN_CODE_HARD, 'err: same burn code, no changes made ={}');
        BURN_CODE_HARD = bc;
        USE_BURN_CODE_HARD = true;
        emit BurnCodeReset(USE_BURN_CODE_HARD);
    }
    function getBurnCodes() public onlyKeeper returns (uint32[] calldata) {
        return [uint32(BURN_CODE_EASY), BURN_CODE_HARD];
    }

    // % of event 'serviceFeeUSD' to use to buy & burn GTA (keeper controlled)
    //  and % of buy & burn GTA to mint for winners
    // NOTE: 'ensures GTA amount burned' > 'GTA amount mint' (per event)
    function setBuyAndBurnPerc(uint8 _perc) public onlyKeeper {
        require(_perc <= 100, 'err: invalid percent :(');
        buyAndBurnPerc = _perc;
    }
    function setBuyAndBurnMintPerc(uint8 _perc) public onlyKeeper {
        require(_perc <= 100, 'err: invalid percent :O');
        buyAndBurnMintPerc = _perc;
    }

    /* -------------------------------------------------------- */
    /* KEEPER - PUBLIC GETTERS / SETTERS                        */
    /* -------------------------------------------------------- */
    // GETTERS / SETTERS (keeper)
    function getKeeper() public view onlyKeeper returns (address) {
        return keeper;
    }
    function getGameCodes() public view onlyKeeper returns (address[] memory) {
        return activeGameCodes;
    }
    function getGameExpSec() public view onlyKeeper returns (uint64) {
        return gameExpSec;
    }
    function setKeeper(address _newKeeper) public onlyKeeper {
        require(_newKeeper != address(0), 'err: zero address ::)');
        keeper = _newKeeper;
    }
    function setGameExpSec(uint64 sec) public onlyKeeper {
        gameExpSec = sec;
    }
    function setDepositFeePerc(uint8 _perc) public onlyKeeper {
        require(_perc <= 100, 'err: max 100%');
        depositFeePerc = _perc;
    }
    function getLastBlockNumUpdate() public view onlyKeeper {
        return lastBlockNumUpdate;
    }
    function setMaxHostFeePerc(uint8 _perc) public onlyKeeper returns (bool) {
        require(_perc <= 100, 'err: max 100%');
        maxHostFeePerc = _perc;
        return true;
    }
    function getCreditAddresses() public onlyKeeper returns (address[] memory) {
        require(creditsAddrArray.length > 0, 'err: no addresses found with credits :0');
        return creditsAddrArray;
    }
    function getCredits(address _player) public onlyKeeper returns (uint256) {
        return creditsUSD[_player];
    }
    function setMinimumEventEntryFeeUSD(uint8 _amount) public onlyKeeper {
        require(_amount > minDepositUSD, 'err: amount must be greater than minDepositUSD =)');
        minEventEntryFeeUSD = _amount;
    }
    function getAccruedGFRL() public view onlyKeeper returns (uint256) {
        return accruedGasFeeRefundLoss;
    }
    function resetAccruedGFRL() public onlyKeeper returns (bool) {
        require(accruedGasFeeRefundLoss > 0, 'err: AccruedGFRL already 0');
        accruedGasFeeRefundLoss = 0;
        return true;
    }
    function getContractStablesAndAlts() public onlyKeeper returns (address[] memory, address[] memory) {
        return (contractStables, contractAlts); // tokens that have ever been whitelisted
    }
    
    function setMinimumUsdValueDeposit(uint8 _amount) public onlyKeeper {
        require(minDepositUSD_floor <= _amount && _amount <= minDepositUSD_ceiling, 'err: invalid amount =)');
        minDepositUSD = _amount;
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
        routersUniswapV2 = _addAddressToArraySafe(_router, routersUniswapV2, true); // true = no dups
    }
    function remDexRouter(address router) public onlyKeeper returns (bool) {
        require(router != address(0x0), "err: invalid address");

        // NOTE: remove algorithm does NOT maintain order
        routersUniswapV2 = _remAddressFromArray(router, routersUniswapV2);
        return true;
    }

    /* -------------------------------------------------------- */
    /* PUBLIC ACCESSORS                                         */
    /* -------------------------------------------------------- */
    function getPlayersForGame(address _host, string memory _gameName) public view returns (address[] memory) {
        require(_host != address(0), "err: invalid host address :/" );
        require(bytes(_gameName).length > 0, "err: no game name :/");
        address _gameCode = getGameCode(_host, _gameName); // generate hash
        return getPlayers(_gameCode);
    }
    function getPlayers(address _gameCode) public view onlyAdmins(_gameCode) returns (address[] memory) {
        require(_gameCode != address(0), 'err: invalid game code :O');
        for (uint i=0; i < activeGameCodes.length; i++) {
            if (_gameCode == activeGameCodes[i]) {
                return activeGames[_gameCode].players;
            }
        }
        return [];
    }

    /* -------------------------------------------------------- */
    /* PUBLIC - HOST / PLAYER SUPPORT                           */
    /* -------------------------------------------------------- */
    // get this user credits ('creditsUSD' are not available for withdrawel)
    function myCredits() public view returns (uint32) {
        return creditsUSD[msg.sender];
    }

    // gameCode = hash(_host, _gameName)
    function getGameCode(address _host, string memory _gameName) public view returns (address) {
        require(activeGameCount > 0, "err: no activeGames :{}"); // verify there are active activeGames
        require(_host != address(0x0), "err: no host address :{}"); // verify _host address input
        require(bytes(_gameName).length > 0, "err: no game name :{}"); // verifiy _gameName input

        // generate gameCode from host address and game name
        address gameCode = _generateAddressHash(_host, _gameName);
        require(bytes(activeGames[gameCode].gameName).length > 0, "err: game code not found :{}"); // verify gameCode exists
        
        return gameCode;
    }

    function verifyHostRequirementsForEntryFee(uint32 _entryFeeUSD) public returns (bool) {
        require(_entryFeeUSD > 0, 'err: no entry fee :/');
        require(_hostCanCreateEvent(_entryFeeUSD), 'err: not enough GTA to host :/');
        return true;
    }

    // _winPercs: [%_1st_place, %_2nd_place, ...] = total 100%
    function createGame(string memory _gameName, uint64 _startTime, uint32 _entryFeeUSD, uint8 _hostFeePerc, uint8[] calldata _winPercs) public returns (address) {
        require(_startTime > block.timestamp, "err: start too soon :/");
        require(_entryFeeUSD >= minEventEntryFeeUSD, "err: entry fee too low :/");
        require(_hostFeePerc <= maxHostFeePerc, 'err: host fee too high :O, check maxHostFeePerc');
        require(_winPercs.length > 0, 'err: no winners? :O');
        require(_getTotalsOfArray(_winPercs) == 100, 'err: invalid _winPercs values, requires 100 total :/');
        require(_hostCanCreateEvent(_entryFeeUSD), "err: not enough GTA to host :/");

        // verify active game name/code doesn't exist yet
        address gameCode = _generateAddressHash(msg.sender, _gameName);
        require(bytes(activeGames[gameCode].gameName).length == 0, "err: game name already exists :/");

        // Creates a default empty 'Game' struct (if doesn't yet exist in 'activeGames' mapping)
        Game storage newGame = activeGames[gameCode];
        //Game storage newGame; // create new default empty struct
        
        // set properties for default empty 'Game' struct
        newGame.host = msg.sender;
        newGame.gameName = _gameName;
        newGame.entryFeeUSD = _entryFeeUSD;
        newGame.winPercs = _winPercs; // %'s of prizePoolUSD - (serviceFeeUSD + hostFeeUSD)
        newGame.hostFeePerc = _hostFeePerc; // % of prizePoolUSD
        newGame.createTime = block.timestamp;
        newGame.createBlockNum = block.number;
        newGame.startTime = _startTime;
        newGame.expTime = _startTime + gameExpSec;

        // Assign the newly modified 'Game' struct back to 'activeGames' mapping
        activeGames[gameCode] = newGame;

        // increment support
        activeGameCodes = _addAddressToArraySafe(gameCode, activeGameCodes, true); // true = no dups
        activeGameCount++;
        
        // return gameCode to caller
        return gameCode;
    }

    // msg.sender can add themself to any game; debits from 'creditsUSD[msg.sender]'
    // UPDATE_120223: make deposit then tweet to register
    //              1) send stable|alt deposit to gta contract
    //              2) tweet: @GamerTokenAward register <wallet_address> <game_code>
    //                  OR ... for free play w/ host register
    //              3) tweet: @GamerTokenAward play <wallet_address> <game_code>
    function registerEvent(address gameCode) public returns (bool) {
        require(gameCode != address(0), 'err: no game code ;o');

        // get/validate active game
        Game storage game = activeGames[gameCode];
        require(game.host != address(0), 'err: invalid game code :I');

        // check if game launched
        require(!game.launched, "err: event launched :(");

        // check msg.sender already registered
        require(!game.players[msg.sender], 'err: already registered for this gameCode :p');

        // check msg.sender for enough credits
        require(game.entryFeeUSD < creditsUSD[msg.sender], 'err: invalid credits, send whitelistAlts or whitelistStables to this contract :P');

        // debit entry fee from msg.sender credits (player)
        _updateCredit(msg.sender, game.entryFeeUSD, true); // true = debit

        // -1) add msg.sender to game event
        game.players[msg.sender] = true;
        game.playerCnt += 1;
        
        // notify client side that a player was registerd for event
        emit RegisteredForEvent(gameCode, game.entryFeeUSD, msg.sender, game.playerCnt);
        
        return true;
    }

    // hosts can pay to add players to their own games (debits from host credits)
    function hostRegisterEvent(address _player, address _gameCode) public returns (bool) {
        require(_player != address(0), 'err: no player ;l');
        require(_gameCode != address(0), 'err: no game code ;l');

        // get/validate active game
        Game storage game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // check if game launched
        require(!game.launched, 'err: event launched :(');

        // check _player already registered
        require(!game.players[_player], 'err: player already registered for this gameCode :p');

        // check msg.sender for enough credits
        require(game.entryFeeUSD < creditsUSD[msg.sender], 'err: not enough credits :(, send whitelistAlts or whitelistStables');

        // debit entry fee from msg.sender credits (host)
        _updateCredit(msg.sender, game.entryFeeUSD, true); // true = debit

        // -1) add player to game event
        // game.players.push(player);
        game.players[_player] = true;
        game.playerCnt += 1;

        // notify client side that a player was registerd for event
        emit RegisteredForEvent(_gameCode, game.entryFeeUSD, _player, game.playerCnt);

        return true;
    }

    // cancel event and process refunds (host, players, keeper)
    //  host|keeper can cancel if event not 'launched' yet
    //  players can cancel if event not 'launched' & 'expTime' has passed
    function cancelEventProcessRefunds(address _eventCode) public {
        require(_eventCode != address(0), 'err: no event code :<>');

        // get/validate active event
        Game storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid event code :<>');
        
        // check for valid sender to cancel (only registered players, host, or keeper)
        bool isValidSender = evt.players[msg.sender] || msg.sender == evt.host || msg.sender == keeper;
        require(isValidSender, 'err: only players or host :<>');

        // for host|player|keeper cancel, verify event not launched
        require(!evt.launched, 'err: event started :<>'); 

        // for player cancel, also verify event expTime must be passed 
        if (evt.players[msg.sender]) {
            require(evt.expTime < block.timestamp, 'err: event code not expired yet :<>');
        } 

        //  loop through players, choose stable for refund, transfer from IERC20
        for (uint i=0; i < evt.players.length; i++) {
            // (OPTION_0) _ REFUND ENTRY FEE (via ON-CHAIN STABLE) ... to player wallet
            // send 'refundUSD_ind' back to player on chain (using lowest market value whitelist stable)
            // address stable = _transferBestDebitStableUSD(evt.players[i], evt.refundUSD_ind);

            // (OPTION_1) _ REFUND ENTRY FEES (via IN-CONTRACT CREDITS) ... to 'creditsUSD'
            //  service fees: calc/set in 'hostStartEvent' (AFTER 'registerEvent|hostRegisterEvent')
            //  deposit fees: 'depositFeePerc' calc/removed in 'settleBalances' (BEFORE 'registerEvent|hostRegisterEvent')
            //   this allows 'registerEvent|hostRegisterEvent' & 'cancelEventProcessRefunds' to sync w/ regard to 'entryFeeUSD'
            //      - 'settleBalances' credits 'creditsUSD' for Transfer.src_addr (AFTER 'depositFeePerc' removed)
            //      - 'registerEvent|hostRegisterEvent' debits full 'entryFeeUSD' from 'creditsUSD' (BEFORE service fees removed)
            //      - 'hostStartEvent' calcs 'prizePoolUSD' & 'payoutsUSD'
            //      - 'hostStartEvent' sets remaining fees -> hostFeeUSD, keeperFeeUSD, serviceFeeUSD, supportFeeUSD
            //      - 'cancelEventProcessRefunds' credits 'refundUSD_ind' to 'creditsUSD' (w/o regard for any fees)

            // credit player in 'creditsUSD' w/ amount 'refundUSD_ind' (calc/set in 'hostStartEvent')
            _updateCredit(evt.players[i], evt.refundUSD_ind, false); // false = credit

            // notify listeners of processed refund
            emit ProcessedRefund(evt.players[i], evt.refundUSD_ind, _eventCode, evt.launched, evt.expTime);
        }

        // set event params to end state
        evt = _endEvent(evt, _eventCode);

        // notify listeners of canceled event
        emit CanceledEvent(msg.sender, _eventCode, evt.launched, evt.expTime, evt.playerCnt, evt.prizePoolUSD, evt.totalFeesUSD, evt.refundsUSD, evt.refundUSD_ind);
    }

    // host can start event w/ players pre-registerd for gameCode
    function hostStartEvent(address _gameCode) public returns (bool) {
        require(_gameCode != address(0), 'err: no game code :p');

        // get/validate active game
        Game storage game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // calc/set 'prizePoolUSD' & 'payoutsUSD' from 'entryFeeUSD' collected
        //  calc/deduct all fees & generate 'buyAndBurnUSD' from 'serviceFeeUSD'
        game = _generatePrizePool(game); // ? Game storage game = _generatePrizePool(game); ?
        game = _launchEvent(game); // set event state to 'launched = true'

        return true;
    }

    // _winners: [0x1st_place, 0x2nd_place, ...]
    function hostEndEventWithWinners(address _gameCode, address[] memory _winners) public returns (bool) {
        require(_gameCode != address(0), 'err: no game code :p');
        require(_winners.length > 0, 'err: no winners :p');

        // get/validate active game
        Game memory game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // check if # of _winners == .winPercs array length (set during eventCreate)
        require(game.winPercs.length == _winners.length, 'err: number of winners =(');

        // buy GTA from open market (using 'buyAndBurnUSD')
        uint256 gta_amnt_burn = _processBuyAndBurnStableSwap(_getBestDebitStableUSD(), game.buyAndBurnUSD);

        // calc 'gta_amnt_mint' using 'buyAndBurnMintPerc' of 'gta_amnt_burn', divided equally to all '_winners'
        uint256 gta_amnt_mint = (gta_amnt_burn * (buyAndBurnMintPerc/100)) / _winners.length;

        // loop through _winners: distribute 'game.winPercs'
        for (uint i=0; i < _winners.length; i++) {
            // verify winner address was registered in the game
            require(game.players[_winners[i]], 'err: invalid player found :/, check getPlayers & retry w/ all valid players');

            // calc win_usd
            address winner = _winners[i];
            uint256 win_usd = game.payoutsUSD[i];

            // pay winner
            address stable = _transferBestDebitStableUSD(winner, win_usd);

            // syncs w/ 'settleBalances' algorithm
            _increaseWhitelistPendingDebit(stable, win_usd);

            // mint GTA to this winner (amount is same for all winners)
            _mint(winner, gta_amnt_mint);

            // notify client side that an end event distribution occurred successfully
            emit EndEventDistribution(winner, i, game.winPercs[i], win_usd, game.prizePoolUSD, stable);
        }

        // pay host & keeper
        address stable_host = _transferBestDebitStableUSD(game.host, game.hostFeeUSD);
        address stable_keep = _transferBestDebitStableUSD(keeper, game.keeperFeeUSD);

        // set event params to end state
        game = _endEvent(game, _gameCode);

        // notify client side that an end event occurred successfully
        emit EndEventActivity(_gameCode, game.host, _winners, game.prizePoolUSD, game.hostFeeUSD, game.keeperFeeUSD, activeGameCount, block.timestamp, block.number);
        
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
            bool is_wl_stab = _isTokenInArray(dataArray[i].token, whitelistStables);
            bool is_wl_alt = _isTokenInArray(dataArray[i].token, whitelistAlts);
            if (!is_wl_stab && !is_wl_alt) { continue; } // skip non-whitelist tokens
            
            address tok_addr = dataArray[i].token;
            address src_addr = dataArray[i].sender;
            uint256 tok_amnt = dataArray[i].amount;
            
            if (tok_addr == address(0) || src_addr == address(0)) { continue; } // skip 0x0 addresses
            if (tok_amnt == 0) { continue; } // skip 0 amount

            // verifiy keeper sent legit amounts from their 'Transfer' event captures (1 FAIL = revert everything)
            //   ie. force start over w/ new call & no gas refund; encourages keeper to not fuck up
            require(_sanityCheck(tok_addr, tok_amnt), 'err: whitelist<->chain balance mismatch :-{} _ KEEPER LIED!');

            // default: if found in 'whitelistStables'
            uint256 stable_credit_amnt = tok_amnt; 
            uint256 stable_swap_fee = 0; // gas fee loss for swap: alt -> stable

            // if not in whitelistStables, swap alt for stable: tok_addr, tok_amnt
            if (!is_wl_stab) {

                // get stable coin to use & create swap path to it
                address stable_addr = _getNextStableTokDeposit();
                address[] memory path = [tok_addr, stable_addr];

                // get stable amount quote for this alt deposit (traverses 'routersUniswapV2')
                (uint8 rtrIdx, uint256 stableAmnt) = _best_swap_v2_router_idx_quote(path, tok_amnt);

                // if stable amount quote is below min deposit required
                if (stableAmnt < minDepositUSD) {  

                    // if refunds enabled, process refund: send 'tok_amnt' of 'tok_addr' back to 'src_addr'
                    if (enableMinDepositRefunds) {
                        // log gas used for refund
                        uint256 start_trans = gasleft();

                        // send 'tok_amnt' of 'tok_addr' back to 'src_addr'
                        IERC20(tok_addr).transfer(src_addr, tok_amnt); 

                        // log gas used for refund
                        uint256 gas_trans_loss = (start_trans - gasleft()) * tx.gasprice;
                        accruedGasFeeRefundLoss += gas_trans_loss;

                        // notify client listeners that refund was processed
                        emit MinimumDepositRefund(src_addr, tok_addr, tok_amnt, gas_trans_loss, accruedGasFeeRefundLoss);
                    }

                    // notify client side, deposit failed
                    emit DepositFailed(src_addr, tok_addr, tok_amnt, stableAmnt, minDepositUSD, enableMinDepositRefunds);

                    // skip to next transfer in 'dataArray'
                    continue;
                }

                // swap tok_amnt alt -> stable (log swap fee / gas loss)
                uint256 start_swap = gasleft();
                stable_credit_amnt = _swap_v2_wrap(path, routersUniswapV2[rtrIdx], tok_amnt);
                uint256 gas_swap_loss = (start_swap - gasleft()) * tx.gasprice;

                // get stable quote for this swap fee / gas fee loss (traverses 'routersUniswapV2')
                (uint8 idx, uint256 amountOut) = _best_swap_v2_router_idx_quote([TOK_WPLS, stable_addr], gas_swap_loss);
                stable_swap_fee = amountOut;

                // debit swap fee from 'stable_credit_amnt'
                stable_credit_amnt -= stable_swap_fee;                
            }

            // 1) debit deposit fees from 'stable_credit_amnt' (keeper optional)
            uint256 depositFee = stable_credit_amnt * (depositFeePerc/100);
            uint256 stable_net_amnt = stable_credit_amnt - depositFee; 

            // convert wei to ether (uint256 to uint32)
            uint32 usd_net_amnt = uint32(stable_net_amnt / 1e18);

            // 2) add 'net_amnt' to 'src_addr' in 'creditsUSD'
            _updateCredit(src_addr, usd_net_amnt, false); // false = credit

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
    /* PRIVATE - EVENT SUPPORTING                               */
    /* -------------------------------------------------------- */
    function _addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) private returns (address[] memory) {
        if (_addr == address(0)) { return _arr; }

        // safe = remove first (no duplicates)
        if (_safe) { _arr = _remAddressFromArray(_addr, _arr); }
        _arr.push(_addr);
        return _arr;
    }
    function _remAddressFromArray(address _addr, address[] memory _arr) private returns (address[] memory) {
        if (_addr == address(0) || _arr.length == 0) { return _arr; }
        
        // NOTE: remove algorithm does NOT maintain order & only removes first occurance
        for (uint i = 0; i < _arr.length; i++) {
            if (_addr == _arr[i]) {
                _arr[i] = _arr[_arr.length - 1];
                _arr.pop();
                return _arr;
            }
        }
        return _arr;
    }
    function _isTokenInArray(address _addr, address[] memory _arr) private returns (bool) {
        if (_addr == address(0) || _arr.length == 0) { return false; }
        for (uint i=0; i < _arr.length; i++) {
            if (_addr = _arr[i]) { return true; }
        }
        return false;
    }
    function _hostCanCreateEvent(address _host, uint32 _entryFeeUSD) private returns (bool) {
        // get best stable quote for host's gta_bal (traverses 'routersUniswapV2')
        uint256 gta_bal = IERC20(address(this)).balanceOf(_host); // returns x10**18
        (uint8 rtrIdx, uint256 stable_quote) = _best_swap_v2_router_idx_quote([address(this), _getNextStableTokDeposit()], gta_bal);
        return stable_quote >= ((_entryFeeUSD * 10**18) * (hostRequirementPerc/100));
    }

    function _getTotalsOfArray(uint8 _arr) private returns (uint8) {
        uint8 t = 0;
        for (uint i=0; i < _arr.length; i++) { t += _arr[i]; }
        return t;
    }

    // swap 'buyAndBurnUSD' amount of best market stable, for GTA (traverses 'routersUniswapV2')
    function _processBuyAndBurnStableSwap(address stable, uint32 _buyAndBurnUSD) private returns (uint256) {
        address[] memory path = [stable, address(this)];
        (uint8 rtrIdx, uint256 gta_amnt) = _best_swap_v2_router_idx_quote(path, _buyAndBurnUSD * 10**18);
        uint256 gta_amnt_out = _swap_v2_wrap(path, routersUniswapV2[rtrIdx], _buyAndBurnUSD * 10**18);
        return gta_amnt_out;
    }

    function _getBestDebitStableUSD(uint32 _amountUSD) private returns (address) {
        // loop through 'whitelistStables', generate stables available (bals ok for debit)
        address[] memory stables_avail = _getStableTokensAvailDebit(_amountUSD);

        // traverse stables available for debit, select stable w/ the lowest market value            
        address stable = _getStableTokenLowMarketValue(stables_avail);
        require(stable != address(0), 'err: low market stable address is 0 _ :+0');
        return stable;
    }

    function _transferBestDebitStableUSD(address _receiver, uint32 _amountUSD) private returns (address) {
        // traverse 'whitelistStables' w/ bals ok for debit, select stable with lowest market value
        address stable = _getBestDebitStableUSD(_amountUSD);

        // send 'win_usd' amount to 'winner', using 'currHighIdx' whitelist stable
        IERC20(stable).transfer(_receiver, _amountUSD * 10**18);
        return stable;
    }

    // set event param to end state
    function _endEvent(Game storage _evt, address _evtCode) private returns (Game storage) {
        // set game end state (doesn't matter if its about to be deleted)
        _evt.endTime = block.timestamp;
        _evt.endBlockNum = block.number;
        _evt.ended = true;

        // delete game mapping
        delete activeGames[_evtCode];

        // decrement support
        activeGameCodes = _remAddressFromArray(_evtCode, activeGameCodes);
        activeGameCount--;
        return _evt;
    }

    // set event params to launched state
    function _launchEvent(Game storage _evt) private returns (Game storage ) {
        // set event fee calculations & prizePoolUSD
        // set event launched state
        _evt.launchTime = block.timestamp;
        _evt.launchBlockNum = block.number;
        _evt.launched = true;
        return _evt;
    }

    // calculate prize pool, payoutsUSD, fees, refunds, totals
    function _generatePrizePool(Game storage _evt) private returns (Game storage) {
        /* DEDUCTING FEES
            current contract debits: 'depositFeePerc', 'hostFeePerc', 'keeperFeePerc', 'serviceFeePerc', 'supportFeePerc', 'winPercs'
             - depositFeePerc -> taken out of each deposit (alt|stable 'transfer' to contract) _ in 'settleBalances'
             - keeper|service|support fees -> taken from gross 'entryFeeUSD' calculated below
             - host fees -> taken from gross 'prizePoolUSD' generated below (ie. net 'entryFeeUSD')
             - win payouts -> taken from net 'prizePoolUSD' generated below

            Formula ...
                keeperFeeUSD = (entryFeeUSD * playerCnt) * keeperFeePerc
                serviceFeeUSD = (entryFeeUSD * playerCnt) * serviceFeePerc
                supportFeeUSD = (entryFeeUSD * playerCnt) * supportFeePerc

                GROSS prizePoolUSD = (entryFeeUSD * playerCnt) - (keeperFeeUSD + serviceFeeUSD + supportFeeUSD)
                    hostFeeUSD = prizePoolUSD * hostFeePerc
                NET prizePoolUSD -= hostFeeUSD
                    payoutsUSD[i] = prizePoolUSD * 'winPercs[i]'
        */

        // calc individual player fees (BEFORE generating 'prizePoolUSD') 
        //  '_ind' used for refunds in 'cancelEventProcessRefunds' (excludes 'hostFeeUSD_ind')
        _evt.keeperFeeUSD_ind = _evt.entryFeeUSD * (_evt.keeperFeePerc/100);
        _evt.serviceFeeUSD_ind = _evt.entryFeeUSD * (_evt.serviceFeePerc/100);
        _evt.supportFeeUSD_ind = _evt.entryFeeUSD * (_evt.supportFeePerc/100);

        // calc total fees for each individual 'entryFeeUSD' paid
        _evt.totalFeesUSD_ind = _evt.keeperFeeUSD_ind + _evt.serviceFeeUSD_ind + _evt.supportFeeUSD_ind;

        // calc: 'hostFeeUSD_ind' = 'hostFeePerc' of single 'entryFeeUSD' - 'totalFeesUSD_ind'
        _evt.hostFeeUSD_ind = (_evt.entryFeeUSD - _evt.totalFeesUSD_ind) * (_evt.hostFeePerc/100);

        // calc total fees for all 'entryFeeUSD' paid
        _evt.keeperFeeUSD = _evt.keeperFeeUSD_ind * _evt.playerCnt;
        _evt.serviceFeeUSD = _evt.serviceFeeUSD_ind * _evt.playerCnt; // GROSS
        _evt.supportFeeUSD = _evt.supportFeeUSD_ind * _evt.playerCnt;
        _evt.totalFeesUSD = _evt.keeperFeeUSD + _evt.serviceFeeUSD + _evt.supportFeeUSD;

        // LEFT OFF HERE ... always divide up 'serviceFeeUSD' w/ 'buyAndBurnPerc'?
        //                      or do we want to let the host choose?
        // calc: tot 'buyAndBurnUSD' = 'buyAndBurnPerc' of 'serviceFeeUSD'
        //       net 'serviceFeeUSD' = 'serviceFeeUSD' - 'buyAndBurnUSD'
        _evt.buyAndBurnUSD = _evt.serviceFeeUSD * (_evt.buyAndBurnPerc/100);
        _evt.serviceFeeUSD -= _evt.buyAndBurnUSD; // NET

        // calc idividual & total refunds (for 'cancelEventProcessRefunds', 'ProcessedRefund', 'CanceledEvent')
        _evt.refundUSD_ind = _evt.entryFeeUSD - _evt.totalFeesUSD_ind; 
        _evt.refundsUSD = _evt.refundUSD_ind * _evt.playerCnt;

        // calc: GROSS 'prizePoolUSD' = all 'entryFeeUSD' - 'totalFeesUSD'
        _evt.prizePoolUSD = (_evt.entryFeeUSD * _evt.playerCnt) - _evt.totalFeesUSD;

        // calc: 'hostFeeUSD' = 'hostFeePerc' of 'prizePoolUSD' (AFTER 'totalFeesUSD' deducted first)
        _evt.hostFeeUSD = _evt.prizePoolUSD * (_evt.hostFeePerc/100);

        // calc: NET 'prizePoolUSD' = gross 'prizePoolUSD' - 'hostFeeUSD'
        _evt.prizePoolUSD -= _evt.hostFeeUSD;
        
        // calc payoutsUSD (finally, AFTER all deductions )
        for (uint i=0; i < _evt.winPercs.length; i++) {
            _evt.payoutsUSD.push(_evt.prizePoolUSD * _evt.winPercs[i]);
        }

        return _evt;
    }

    function _generateAddressHash(address host, string memory uid) private pure returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));
        address generatedAddress = address(uint160(uint256(hash)));
        return generatedAddress;
    }

    /* -------------------------------------------------------- */
    /* PRIVATE - BOOK KEEPING                                   */
    /* -------------------------------------------------------- */
    // traverse 'whitelistStables' using 'whitelistStablesUseIdx'
    function _getNextStableTokDeposit() private {
        address stable_addr = whitelistStables[whitelistStablesUseIdx];
        whitelistStablesUseIdx++;
        if (whitelistStablesUseIdx >= whitelistStables.length) { whitelistStablesUseIdx=0; }
        return stable_addr;
    }

    // keeper 'SANITY CHECK' for 'settleBalances'
    function _sanityCheck(address token, uint256 amount) private {
        // SANITY CHECK: 
        //  settles whitelist debits accrued during 'hostEndEventWithWinners'
        //  updates whitelist balance from IERC20 'Transfer' emit (delagated through keeper -> 'settleBalances')
        //  require: keeper calculated (delegated) balance == on-chain balance
        _settlePendingDebit(token); // sync 'contractBalances' w/ 'whitelistPendingDebits'
        _increaseContractBalance(token, amount); // sync 'contractBalances' w/ this 'Transfer' emit
        uint256 chainBal = IERC20(token).balanceOf(address(this));
        return contractBalances[token] == chainBal;
    }

    // deduct debits accrued from 'hostEndEventWithWinners'
    function _settlePendingDebit(address _token) private {
        require(contractBalances[_token] >= whitelistPendingDebits[_token], 'err: insefficient balance to settle debit :O');
        contractBalances[_token] -= whitelistPendingDebits[_token];
        delete whitelistPendingDebits[_token];
    }

    // update stable balance from IERC20 'Transfer' emit (delegated by keeper -> 'settleBalances')
    function _increaseContractBalance(address _token, uint256 _amount) private {
        require(_token != address(0), 'err: no address :{');
        require(_amount != 0, 'err: no amount :{');
        contractBalances[_token] += _amount;
    }

    // aggregate debits incurred from 'hostEndEventWithWinners'; syncs w/ 'settleBalances' algorithm
    function _increaseWhitelistPendingDebit(address token, uint256 amount) private {
        whitelistPendingDebits[token] += amount;
    }

    // debits/credits for a _player in 'creditsUSD' (used during deposits and event registrations)
    function _updateCredit(address _player, uint32 _amountUSD, bool _debit) private {
        if (_debit) { 
            // ensure there is enough credit before debit
            require(creditsUSD[_player] >= _amountUSD, 'err: invalid credits to debit :[');
            creditsUSD[_player] -= _amountUSD;

            // if balance is now 0, remove _player from balance tracking
            if (creditsUSD[_player] == 0) {
                delete creditsUSD[_player];
                creditsAddrArray = _remAddressFromArray(_player, creditsAddrArray);
            }
        } else { 
            creditsUSD[_player] += _amountUSD; 
            creditsAddrArray = _addAddressToArraySafe(_player, creditsAddrArray, true); // true = no dups
        }
    }

    /* -------------------------------------------------------- */
    /* PRIVATE - DEX SUPPORT                                    */
    /* -------------------------------------------------------- */
    // NOTE: *WARNING* stables_avail could have duplicates (from 'whitelistStables' set by keeper)
    function _getStableTokensAvailDebit(uint32 _debitAmntUSD) private view returns (address[] memory) {
        // loop through white list stables, generate stables available (ok for debit)
        address[] memory stables_avail = []; // stables available to cover debit
        for (uint i = 0; i < whitelistStables.length; i++) {

            // get balnce for this whitelist stable (push to stablesAvail if has enough)
            uint256 stableBal = IERC20(whitelistStables[i]).balanceOf(address(this));
            if (stableBal > _debitAmntUSD * 10**18) { 
                stables_avail.push(whitelistStables[i]);
            }
        }
        return stables_avail;
    }

    // NOTE: *WARNING* stables_avail could have duplicates (from 'whitelistStables' set by keeper)
    function _getStableTokenLowMarketValue(address[] memory stables) private view returns (address) {
        // traverse stables available for debit, select stable w/ the lowest market value
        uint256 curr_high_tok_val = 0;
        address curr_low_val_stable = 0x0;
        for (uint i=0; i < stables.length; i++) {
            
            // get quote for this available stable (traverses 'routersUniswapV2')
            //  looking for the stable that returns the most when swapped 'from' WPLS
            //  the more USD stable received for 1 WPLS ~= the less overall market value that stable has
            address stable_addr = stables[i];
            (uint8 rtrIdx, uint256 tok_val) = _best_swap_v2_router_idx_quote([TOK_WPLS, stable_addr], 1 * 10**18);
            if (tok_val >= curr_high_tok_val) {
                curr_high_tok_val = tok_val;
                curr_low_val_stable = stable_addr;
            }
        }
        return curr_low_val_stable;
    }

    // support hostEndEventWithWinners
    function _getLiquidityInPair(address _token, address _pair) private view returns (uint256) {
        require(_token != address(0), 'err: no token :O');
        require(_pair != address(0), 'err: no pair :O');

        IUniswapV2Pair pair = IUniswapV2Pair(_pair);
        require(_token == pair.token0() || _token == pair.token1(), 'err: invalid token->pair address :P');

        (uint reserve0, uint reserve1) = pair.getReserves();
        if (_token == pair.token0()) { return reserve0; }
        else { return reserve1; }
    }

    // support hostEndEventWithWinners (120223: not in use)
    function _getPairLiquidity(address _token1, address _token2, address _factoryAddress) private view returns (uint256, uint256) {
        require(_token1 != address(0), 'err: no token1 :O');
        require(_token2 != address(0), 'err: no token2 :O');

        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(_factoryAddress);
        address pair = uniswapFactory.getPair(_token1, _token2);
        require(pair != address(0), 'err: pair does not exist');

        uint256 tok_liq_1 = _getLiquidityInPair(_token1, pair);
        uint256 tok_liq_2 = _getLiquidityInPair(_token2, pair);
        return (tok_liq_1, tok_liq_2);
    }

    // uniswap v2 protocol based: get router w/ best quote in 'routersUniswapV2'
    function _best_swap_v2_router_idx_quote(address[] memory path, uint256 amount) private returns (uint8) {
        uint8 currHighIdx = 37;
        uint256 currHigh = 0;
        for (uint i = 0; i < routersUniswapV2.length; i++) {
            uint256[] memory amountsOut = IUniswapV2(routersUniswapV2[i]).getAmountsOut(amount, path); // quote swap
            if (amountsOut[amountsOut.length-1] > currHigh) {
                currHigh = amountsOut[amountsOut.length-1];
                currHighIdx = i;
            }
        }

        return (currHighIdx, currHigh);
    }

    // uniwswap v2 protocol based: get quote and execute swap
    function _swap_v2_wrap(address[] memory path, address router, uint256 amntIn) private returns (uint256) {
        //address[] memory path = [weth, wpls];
        uint256[] memory amountsOut = IUniswapV2(router).getAmountsOut(amntIn, path); // quote swap
        uint256 amntOut = _swap_v2(router, path, amntIn, amountsOut[amountsOut.length -1], false); // execute swap
                
        // verifiy new balance of token received
        uint256 new_bal = IERC20(path[path.length -1]).balanceOf(address(this));
        require(new_bal >= amntOut, "err: balance low :{");
        
        return amntOut;
    }
    
    // v2: solidlycom, kyberswap, pancakeswap, sushiswap, uniswap v2, pulsex v1|v2, 9inch
    function _swap_v2(address router, address[] memory path, uint256 amntIn, uint256 amntOutMin, bool fromETH) private returns (uint256) {
        // emit logRFL(address(this), msg.sender, "logRFL 6a");
        IUniswapV2 swapRouter = IUniswapV2(router);
        
        // emit logRFL(address(this), msg.sender, "logRFL 6b");
        IERC20(address(path[0])).approve(address(swapRouter), amntIn);
        uint deadline = block.timestamp + 300;
        uint[] memory amntOut;
        // emit logRFL(address(this), msg.sender, "logRFL 6c");
        if (fromETH) {
            amntOut = swapRouter.swapExactETHForTokens{value: amntIn}(
                            amntOutMin,
                            path, //address[] calldata path,
                            address(this), // to
                            deadline
                        );
        } else {
            amntOut = swapRouter.swapExactTokensForTokens(
                            amntIn,
                            amntOutMin,
                            path, //address[] calldata path,
                            address(this),
                            deadline
                        );
        }
        // emit logRFL(address(this), msg.sender, "logRFL 6d");
        return uint256(amntOut[amntOut.length - 1]); // idx 0=path[0].amntOut, 1=path[1].amntOut, etc.
    }
}

/*****************/
/*** DEAD CODE ***/
/*****************/
// NOTE: this integratoin won't work because anyone can monitor 'Transfer' emits and get player addresses on deposits
// host can add players to their own games, by claiming address credits waiting in creditsUSD (debits from player credits)
//  *ALERT* players should not share their addresses with anyone 'except' the host
//      (player credits can be freely claimed by any hosted game, if enough credits are available; brute-force required)
// function hostRegisterEventClaim(address player, address gameCode) public returns (bool) {
//     require(player != address(0), 'err: no player ;l');

//     // get/validate active game
//     struct storage game = activeGames[gameCode];
//     require(game.host != address(0), 'err: invalid game code :I');

//     // check if msg.sender is game host
//     require(game.host == msg.sender, 'err: only host :/');

//     // check if game launched
//     require(!game.launched, 'err: event launched :(');

//     // check player for enough credits
//     require(game.entryFeeUSD < creditsUSD[player], 'err: not enough claimable credits :(');

//     // debit entry fee from player credits
//     // creditsUSD[player] -= game.entryFeeUSD;
//     // handles tracking addresses w/ creditsAddrArray
//     _updateCredit(player, game.entryFeeUSD, true); // true = debit

//     // -1) add player to game event
//     // game.players.push(player);
//     game.players[player] = true;
//     game.playerCnt += 1;

//     return true;
// }
