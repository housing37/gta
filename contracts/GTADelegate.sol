// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;        

// deploy
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

// local
// import "./node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "./node_modules/@openzeppelin/contracts/access/Ownable.sol"; 
// import "./node_modules/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol"; 

// $ npm install @openzeppelin/contracts
// $ npm install @uniswap/v2-core
// import "./@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "./@openzeppelin/contracts/access/Ownable.sol"; 
// import "./@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol"; 
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";


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

// LEFT OFF HERE ... compilation fails
//  remix error....
/** 
    Warning: Contract code size is 50685 bytes and exceeds 24576 bytes (a limit introduced in Spurious Dragon). This contract may not be deployable on Mainnet. Consider enabling the optimizer (with a low "runs" value!), turning off revert strings, or using libraries.
    --> contracts/gta.sol:52:1:
    |
    52 | contract GamerTokeAward is ERC20, Ownable {
    | ^ (Relevant source part starts here and spans across multiple lines).

    StructDefinition
    contracts/gta.sol 150:4

 */
 // LEFT OFF HERE ... divide up contract to lower the size
contract GTADelegate {
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
    mapping(address => Event_0) private activeGames;
    
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
    mapping(address => uint32) private creditsUSD;

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
        uint256 expBlockNum;    // 'cancelEventProcessRefunds'

        // mapping(address => Event_1) event_1;
        // mapping(address => Event_2) event_2;
        Event_1 event_1;
        Event_2 event_2;
    }
    struct Event_1 { 
        // ------------------------------------------
        bool launched;  // 'hostStartEvent'
        bool ended;     // 'hostEndEventWithWinners'
        bool expired;   // 'cancelEventProcessRefunds'
        // LEFT OFF HERE ... 'expired' is never used

        // ------------------------------------------
        mapping(address => bool) players; // true = registerd 
        address[] playerAddresses; // traversal access
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

    }
    struct Event_2 { 
        uint32 totalFeesUSD;    // keeperFeeUSD + serviceFeeUSD + supportFeeUSD
        uint32 hostFeeUSD;      // prizePoolUSD * hostFeePerc
        uint32 prizePoolUSD;    // (entryFeeUSD * playerCnt) - totalFeesUSD - hostFeeUSD

        // ------------------------------------------
        uint8[] winPercs;       // %'s of prizePoolUSD - hostFeeUSD
        uint32[] payoutsUSD;    // prizePoolUSD * winPercs[]
        
        /** _generatePrizePool */
        uint32 keeperFeeUSD_ind;    // entryFeeUSD * keeperFeePerc
        uint32 serviceFeeUSD_ind;   // entryFeeUSD * serviceFeePerc
        uint32 supportFeeUSD_ind;   // entryFeeUSD * supportFeePerc
        uint32 totalFeesUSD_ind;    // keeperFeeUSD_ind + serviceFeeUSD_ind + supportFeeUSD_ind
        uint32 refundUSD_ind;       // entryFeeUSD - totalFeesUSD_ind
        uint32 refundsUSD;          // refundUSD_ind * evt.event_1.playerCnt
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
    event EndEventActivity(address evtCode, address host, address[] winners, uint32 prize_pool_usd, uint32 host_fee_usd, uint32 keeper_fee_usd, uint64 activeEvtCount, uint256 block_timestamp, uint256 block_number);

    // notify client side that an event has been canceled
    event ProcessedRefund(address player, uint32 refundAmountUSD, address evtCode, bool evtLaunched, uint256 evtExpTime);
    event CanceledEvent(address canceledBy, address evtCode, bool evtLaunched, uint256 evtExpTime, uint32 playerCount, uint32 prize_pool_usd, uint32 totalFeesUSD, uint32 totalRefundsUSD, uint32 indRefundUSD);

    // notify client side that someoen cracked the burn code and burned all gta in this contract
    event BurnedGTA(uint256 amount_burned, address code_cracker, uint64 guess_count);
    
    // notify clients a new burn code is set with type (easy, hard)
    event BurnCodeReset(bool setToHard);

    // notify client side that a player was registerd for event
    event RegisteredForEvent(address evtCode, uint32 entryFeeUSD, address player, uint32 playerCnt);

    /* -------------------------------------------------------- */
    /* CONSTRUCTOR                                              */
    /* -------------------------------------------------------- */
    constructor() {
        keeper = msg.sender;
    }
    
    // constructor(uint256 _initSupply, string memory _name, string memory _symbol) ERC20(_name, _symbol) Ownable(msg.sender) {
    // constructor(uint256 _initSupply) ERC20(tok_name, tok_symb) Ownable(msg.sender) {
    //     // Set sender to keeper ('Ownable' maintains '_owner')
    //     keeper = msg.sender;
    //     _mint(msg.sender, _initSupply * 10**uint8(decimals())); // 'emit Transfer'
    // }

    /* -------------------------------------------------------- */
    /* MODIFIERS                                                */
    /* -------------------------------------------------------- */
    // modifier onlyAdmins(address gameCode) {
    //     require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
    //     bool isHost = msg.sender == activeGames[gameCode].host;
    //     bool isKeeper = msg.sender == keeper;
    //     bool isOwner = msg.sender == owner(); // from 'Ownable'
    //     require(isKeeper || isOwner || isHost, 'err: only admins :/*');
    //     _;
    // }
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
    // function burnGTA_HARD(uint32 burnCode) public returns (bool) {
    //     BURN_CODE_GUESS_CNT++; // keep track of guess count
    //     require(USE_BURN_CODE_HARD, 'err: burn code set to easy, use burnGTA_EASY :p');
    //     require(burnCode == BURN_CODE_HARD, 'err: invalid burn_code, guess again :p');
    //     return _burnGTA();
    // }
    // function burnGTA_EASY(uint16 burnCode) public returns (bool) {
    //     BURN_CODE_GUESS_CNT++; // keep track of guess count
    //     require(!USE_BURN_CODE_HARD, 'err: burn code set to hard, use burnGTA_HARD :p');
    //     require(burnCode == BURN_CODE_EASY, 'err: invalid burn_code, guess again :p');
    //     return _burnGTA();
    // }
    // function _burnGTA() private returns (bool) {
    //     uint256 bal = balanceOf(address(this));
    //     require(bal > 0, 'err: no GTA to burn :p');

    //     // burn it.. burn it real good...
    //     //  burn 'buyAndBurnPerc' of 'bal', send rest to cracker
    //     uint256 bal_burn = bal * (buyAndBurnPerc/100);
    //     uint256 bal_earn = bal - bal_burn;
    //     IERC20(address(this)).transfer(address(0), bal_burn);
    //     IERC20(address(this)).transfer(msg.sender, bal_earn);

    //     // notify the world that shit was burned
    //     emit BurnedGTA(bal, msg.sender, BURN_CODE_GUESS_CNT);

    //     // reset guess count
    //     BURN_CODE_GUESS_CNT = 0;

    //     return true;
    // }

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
    function getBurnCodes() public onlyKeeper returns (uint32[2] memory) {
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
    function setGameExpSec(uint32 _sec) public onlyKeeper {
        gameExpSec = _sec;
    }
    function setDepositFeePerc(uint8 _perc) public onlyKeeper {
        require(_perc <= 100, 'err: max 100%');
        depositFeePerc = _perc;
    }
    function getLastBlockNumUpdate() public view onlyKeeper returns (uint32) {
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
    /* PRIVATE - EVENT SUPPORTING                               */
    /* -------------------------------------------------------- */
    function _addAddressToArraySafe(address _addr, address[] memory _arr, bool _safe) public view onlyKeeper returns (address[] memory) {
        if (_addr == address(0)) { return _arr; }

        // safe = remove first (no duplicates)
        if (_safe) { _arr = _remAddressFromArray(_addr, _arr); }

        // perform add to memory array type w/ static size
        address[] memory _ret = new address[](_arr.length+1);
        for (uint i=0; i < _arr.length; i++) { _ret[i] = _arr[i]; }
        _ret[_ret.length] = _addr;
        return _ret;
    }
    function _remAddressFromArray(address _addr, address[] memory _arr) public view onlyKeeper returns (address[] memory) {
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

    function _isTokenInArray(address _addr, address[] memory _arr) public view onlyKeeper returns (bool) {
        if (_addr == address(0) || _arr.length == 0) { return false; }
        for (uint i=0; i < _arr.length; i++) {
            if (_addr == _arr[i]) { return true; }
        }
        return false;
    }
    function _hostCanCreateEvent(address _host, uint32 _entryFeeUSD) public returns (bool) {
        // get best stable quote for host's gta_bal (traverses 'routersUniswapV2')
        uint256 gta_bal = IERC20(address(this)).balanceOf(_host); // returns x10**18
        address[] memory gta_stab_path = new address[](2);
        gta_stab_path[0] = address(this);
        gta_stab_path[1] = _getNextStableTokDeposit();
        (uint8 rtrIdx, uint256 stable_quote) = _best_swap_v2_router_idx_quote(gta_stab_path, gta_bal);
        return stable_quote >= ((_entryFeeUSD * 10**18) * (hostRequirementPerc/100));
    }

    function _getTotalsOfArray(uint8[] calldata _arr) public view onlyKeeper returns (uint8) {
        uint8 t = 0;
        for (uint i=0; i < _arr.length; i++) { t += _arr[i]; }
        return t;
    }

    // swap 'buyAndBurnUSD' amount of best market stable, for GTA (traverses 'routersUniswapV2')
    function _processBuyAndBurnStableSwap(address stable, uint32 _buyAndBurnUSD) public onlyKeeper returns (uint256) {
        address[] memory stab_gta_path = new address[](2);
        stab_gta_path[0] = stable;
        stab_gta_path[1] = address(this);
        (uint8 rtrIdx, uint256 gta_amnt) = _best_swap_v2_router_idx_quote(stab_gta_path, _buyAndBurnUSD * 10**18);
        uint256 gta_amnt_out = _swap_v2_wrap(stab_gta_path, routersUniswapV2[rtrIdx], _buyAndBurnUSD * 10**18);
        return gta_amnt_out;
    }

    function _getBestDebitStableUSD(uint32 _amountUSD) public view onlyKeeper returns (address) {
        // loop through 'whitelistStables', generate stables available (bals ok for debit)
        address[] memory stables_avail = _getStableTokensAvailDebit(_amountUSD);

        // traverse stables available for debit, select stable w/ the lowest market value            
        address stable = _getStableTokenLowMarketValue(stables_avail);
        require(stable != address(0), 'err: low market stable address is 0 _ :+0');
        return stable;
    }

    // function _transferBestDebitStableUSD(address _receiver, uint32 _amountUSD) private returns (address) {
    //     // traverse 'whitelistStables' w/ bals ok for debit, select stable with lowest market value
    //     address stable = _getBestDebitStableUSD(_amountUSD);

    //     // send 'win_usd' amount to 'winner', using 'currHighIdx' whitelist stable
    //     IERC20(stable).transfer(_receiver, _amountUSD * 10**18);
    //     return stable;
    // }

    // function _addPlayerToEvent(address _player, Event_0 memory _evt) public returns (Event_0 memory) {
    //     _evt.event_1.players[_player] = true;
    //     _evt.event_1.playerAddresses.push(_player);
    //     _evt.event_1.playerCnt = uint32(_evt.event_1.playerAddresses.length);
    //     return _evt;
    // }

    // // set event param to end state
    // function _endEvent(Event_0 storage _evt, address _evtCode) private returns (Event_0 storage) {
    //     // set game end state (doesn't matter if its about to be deleted)
    //     _evt.endTime = block.timestamp;
    //     _evt.endBlockNum = block.number;
    //     _evt.event_1.ended = true;

    //     // delete game mapping
    //     delete activeGames[_evtCode];

    //     // decrement support
    //     activeGameCodes = _remAddressFromArray(_evtCode, activeGameCodes);
    //     activeGameCount--;
    //     return _evt;
    // }

    // // set event params to launched state
    // function _launchEvent(Event_0 storage _evt) private returns (Event_0 storage ) {
    //     // set event fee calculations & prizePoolUSD
    //     // set event launched state
    //     _evt.launchTime = block.timestamp;
    //     _evt.launchBlockNum = block.number;
    //     _evt.event_1.launched = true;
    //     return _evt;
    // }

    // // calculate prize pool, payoutsUSD, fees, refunds, totals
    // function _generatePrizePool(Event_0 storage _evt) private returns (Event_0 storage) {
    //     /* DEDUCTING FEES
    //         current contract debits: 'depositFeePerc', 'hostFeePerc', 'keeperFeePerc', 'serviceFeePerc', 'supportFeePerc', 'winPercs'
    //          - depositFeePerc -> taken out of each deposit (alt|stable 'transfer' to contract) _ in 'settleBalances'
    //          - keeper|service|support fees -> taken from gross 'entryFeeUSD' calculated below
    //          - host fees -> taken from gross 'prizePoolUSD' generated below (ie. net 'entryFeeUSD')
    //          - win payouts -> taken from net 'prizePoolUSD' generated below

    //         Formula ...
    //             keeperFeeUSD = (entryFeeUSD * playerCnt) * keeperFeePerc
    //             serviceFeeUSD = (entryFeeUSD * playerCnt) * serviceFeePerc
    //             supportFeeUSD = (entryFeeUSD * playerCnt) * supportFeePerc

    //             GROSS prizePoolUSD = (entryFeeUSD * playerCnt) - (keeperFeeUSD + serviceFeeUSD + supportFeeUSD)
    //                 hostFeeUSD = prizePoolUSD * hostFeePerc
    //             NET prizePoolUSD -= hostFeeUSD
    //                 payoutsUSD[i] = prizePoolUSD * 'winPercs[i]'
    //     */

    //     // calc individual player fees (BEFORE generating 'prizePoolUSD') 
    //     //  '_ind' used for refunds in 'cancelEventProcessRefunds' (excludes 'hostFeeUSD_ind')
    //     _evt.event_2.keeperFeeUSD_ind = _evt.entryFeeUSD * (_evt.event_1.keeperFeePerc/100);
    //     _evt.event_2.serviceFeeUSD_ind = _evt.entryFeeUSD * (_evt.event_1.serviceFeePerc/100);
    //     _evt.event_2.supportFeeUSD_ind = _evt.entryFeeUSD * (_evt.event_1.supportFeePerc/100);

    //     // calc total fees for each individual 'entryFeeUSD' paid
    //     _evt.event_2.totalFeesUSD_ind = _evt.event_2.keeperFeeUSD_ind + _evt.event_2.serviceFeeUSD_ind + _evt.event_2.supportFeeUSD_ind;

    //     // calc: 'hostFeeUSD_ind' = 'hostFeePerc' of single 'entryFeeUSD' - 'totalFeesUSD_ind'
    //     _evt.event_2.hostFeeUSD_ind = (_evt.entryFeeUSD - _evt.event_2.totalFeesUSD_ind) * (_evt.event_1.hostFeePerc/100);

    //     // calc total fees for all 'entryFeeUSD' paid
    //     _evt.event_1.keeperFeeUSD = _evt.event_2.keeperFeeUSD_ind * _evt.event_1.playerCnt;
    //     _evt.event_1.serviceFeeUSD = _evt.event_2.serviceFeeUSD_ind * _evt.event_1.playerCnt; // GROSS
    //     _evt.event_1.supportFeeUSD = _evt.event_2.supportFeeUSD_ind * _evt.event_1.playerCnt;
    //     _evt.event_2.totalFeesUSD = _evt.event_1.keeperFeeUSD + _evt.event_1.serviceFeeUSD + _evt.event_1.supportFeeUSD;

    //     // LEFT OFF HERE ... always divide up 'serviceFeeUSD' w/ 'buyAndBurnPerc'?
    //     //                      or do we want to let the host choose?
    //     // calc: tot 'buyAndBurnUSD' = 'buyAndBurnPerc' of 'serviceFeeUSD'
    //     //       net 'serviceFeeUSD' = 'serviceFeeUSD' - 'buyAndBurnUSD'
    //     _evt.event_2.buyAndBurnUSD = _evt.event_1.serviceFeeUSD * (_evt.event_1.buyAndBurnPerc/100);
    //     _evt.event_1.serviceFeeUSD -= _evt.event_2.buyAndBurnUSD; // NET

    //     // calc idividual & total refunds (for 'cancelEventProcessRefunds', 'ProcessedRefund', 'CanceledEvent')
    //     _evt.event_2.refundUSD_ind = _evt.entryFeeUSD - _evt.event_2.totalFeesUSD_ind; 
    //     _evt.event_2.refundsUSD = _evt.event_2.refundUSD_ind * _evt.event_1.playerCnt;

    //     // calc: GROSS 'prizePoolUSD' = all 'entryFeeUSD' - 'totalFeesUSD'
    //     _evt.event_2.prizePoolUSD = (_evt.entryFeeUSD * _evt.event_1.playerCnt) - _evt.event_2.totalFeesUSD;

    //     // calc: 'hostFeeUSD' = 'hostFeePerc' of 'prizePoolUSD' (AFTER 'totalFeesUSD' deducted first)
    //     _evt.event_2.hostFeeUSD = _evt.event_2.prizePoolUSD * (_evt.event_1.hostFeePerc/100);

    //     // calc: NET 'prizePoolUSD' = gross 'prizePoolUSD' - 'hostFeeUSD'
    //     _evt.event_2.prizePoolUSD -= _evt.event_2.hostFeeUSD;
        
    //     // calc payoutsUSD (finally, AFTER all deductions )
    //     for (uint i=0; i < _evt.event_2.winPercs.length; i++) {
    //         _evt.event_2.payoutsUSD.push(_evt.event_2.prizePoolUSD * _evt.event_2.winPercs[i]);
    //     }

    //     return _evt;
    // }

    function _generateAddressHash(address host, string memory uid) public view onlyKeeper returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));
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

    // LEFT OFF HERE ... changing 'private' to 'public' causes contract code size error
    //                      exceeding limit by about 1000 bytes
    //      "Warning: Contract code size is 25699 bytes and exceeds 24576 bytes"
    // keeper 'SANITY CHECK' for 'settleBalances'
    function _sanityCheck(address token, uint256 amount) private returns (bool) {
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
    function _increaseWhitelistPendingDebit(address token, uint256 amount) public onlyKeeper {
        whitelistPendingDebits[token] += amount;
    }

    // debits/credits for a _player in 'creditsUSD' (used during deposits and event registrations)
    function _updateCredit(address _player, uint32 _amountUSD, bool _debit) public onlyKeeper {
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
    // NOTE: *WARNING* stables_avail could have random idx's w/ address(0) (default in static length memory array)
    function _getStableTokensAvailDebit(uint32 _debitAmntUSD) private view returns (address[] memory) {
        // loop through white list stables, generate stables available (ok for debit)
        address[] memory stables_avail = new address[](whitelistStables.length);
        for (uint i = 0; i < whitelistStables.length; i++) {

            // get balnce for this whitelist stable (push to stablesAvail if has enough)
            uint256 stableBal = IERC20(whitelistStables[i]).balanceOf(address(this));
            if (stableBal > _debitAmntUSD * 10**18) { 
                stables_avail[i] = whitelistStables[i];

            }
        }
        return stables_avail;
    }

    // NOTE: *WARNING* stables_avail could have duplicates (from 'whitelistStables' set by keeper)
    function _getStableTokenLowMarketValue(address[] memory stables) private view returns (address) {
        // traverse stables available for debit, select stable w/ the lowest market value
        uint256 curr_high_tok_val = 0;
        address curr_low_val_stable = address(0x0);
        for (uint i=0; i < stables.length; i++) {
            address stable_addr = stables[i];
            if (stable_addr == address(0)) { continue; }

            // get quote for this available stable (traverses 'routersUniswapV2')
            //  looking for the stable that returns the most when swapped 'from' WPLS
            //  the more USD stable received for 1 WPLS ~= the less overall market value that stable has
            address[] memory wpls_stab_path = new address[](2);
            wpls_stab_path[0] = TOK_WPLS;
            wpls_stab_path[1] = stable_addr;
            (uint8 rtrIdx, uint256 tok_val) = _best_swap_v2_router_idx_quote(wpls_stab_path, 1 * 10**18);
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

        (uint reserve0, uint reserve1, uint32 blockTimestampLast) = pair.getReserves();
        if (_token == pair.token0()) { return reserve0; }
        else { return reserve1; }
    }

    // uniswap v2 protocol based: get router w/ best quote in 'routersUniswapV2'
    function _best_swap_v2_router_idx_quote(address[] memory path, uint256 amount) private view returns (uint8, uint256) {
        uint8 currHighIdx = 37;
        uint256 currHigh = 0;
        for (uint8 i = 0; i < routersUniswapV2.length; i++) {
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
