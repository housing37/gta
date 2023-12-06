// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;        
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Factory.sol";

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
contract GamerTokeAward is IERC20, Ownable {

    /* _ ADMIN SUPPORT _ */
    address public owner;
    address private keeper; // 37, curator, manager, caretaker, keeper
    
    /* _ TOKEN SUPPORT _ */
    string public override name = "Gamer Token Award";
    string public override symbol = "GTA";
    uint8 public override decimals = 18;
    uint256 public override totalSupply;

    /* _ TOKEN SUPPORT MAPPINGS _ */
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /* _ DEX SUPPORT _ */ // WARNING: router addresses only for testing (remove for launch)
    // usd stable coins for 'getDexQuoteUSD'
    address private constant TOK_pDAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address private constant TOK_eDAI = address(0xefD766cCb38EaF1dfd701853BFCe31359239F305);
    address private constant TOK_WPLS = address(0xA1077a294dDE1B09bB078844df40758a5D0f9a27);
    
    // PulseXSwapRouter 'v1' ref: MM tx | PulseXRouter02 'v1|2' ref: https://www.irccloud.com/pastebin/6ftmqWuk
    address private constant ROUTER_pulsex_vX = address(0xa619F23c632CA9f36CD4Dcea6272E1eA174aAC27);
    address private constant ROUTER_pulsex_v1 = address(0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02);
    address private constant ROUTER_pulsex_v2 = address(0x165C3410fC91EF562C50559f7d2289fEbed552d9);
    
    // array of all dex routers to check for 'getDexQuoteUSD'
    address[] storage private routersUniswapV2 = [ROUTER_pulsex_v1, ROUTER_pulsex_v2, ROUTER_pulsex_vX];
        
    /* _ GAME SUPPORT _ */
    struct Game {
        address host;           // input param
        string gameName;        // input param
        uint32 entryFeeUSD;     // input param
        uint32 prizePoolUSD;    // entryFeeUSD * playerCnt

        uint8 hostFeePerc;      // % of prizePoolUSD (dynamic)
        uint8 keeperFeePerc;    // % of prizePoolUSD (1% ?)
        uint8 serviceFeePerc;   // % of prizePoolUSD (10% ?)
        uint8 supportFeePerc;   // % of prizePoolUSD (needed ?)
        uint8 buyAndBurnPerc;   // % of serviceFeeUSD (50% ?)
        uint8 mintDistrPerc;    // % of ?
        uint8[] winPercs;       // %'s of prizePoolUSD - (serviceFeeUSD + hostFeeUSD + keeperFeeUSD + supportFeeUSD)
        uint32[] payoutsUSD;    // prizePoolUSD * winPercs[]

        uint32 hostFeeUSD;      // prizePoolUSD * hostFeePerc
        uint32 keeperFeeUSD;    // prizePoolUSD * keeperFeePerc
        uint32 serviceFeeUSD;   // prizePoolUSD * serviceFeePerc
        uint32 supportFeeUSD;   // prizePoolUSD * supportFeePerc (optional)
        uint32 totalFeesUSD;    // _evt.hostFeeUSD + _evt.keeperFeeUSD + _evt.serviceFeeUSD + _evt.supportFeeUSD;

        uint32 hostFeeUSD_ind;      // entryFeeUSD * hostFeePerc
        uint32 keeperFeeUSD_ind;    // entryFeeUSD * keeperFeePerc
        uint32 serviceFeeUSD_ind;   // entryFeeUSD * serviceFeePerc
        uint32 supportFeeUSD_ind;   // entryFeeUSD * supportFeePerc (optional)
        uint32 refundUSD_ind;       // entryFeeUSD - (keeperFeeUSD_ind + serviceFeeUSD_ind + supportFeeUSD_ind)
        uint32 refundsUSD;          // refundUSD_ind * evt.playerCnt
        uint32 totalFeesUSD_ind;    // _evt.keeperFeeUSD_ind + _evt.serviceFeeUSD_ind + _evt.supportFeeUSD_ind

        uint32 buyAndBurnUSD;   // serviceFeeUSD * buyAndBurnPerc
        
        mapping(address => bool) players; // true = registerd 
        uint32 playerCnt;       // length or players; max 4,294,967,295

        uint256 createTime;
        uint256 createBlockNum;
        uint256 startTime;      // host scheduled
        uint256 launchTime;
        uint256 launchBlockNum;
        uint256 endTime;
        uint256 endBlockNum;
        uint256 expTime;
        uint256 expBlockNum;

        bool launched;
        bool ended;
        bool expired;
    }
    
    // map generated gameCode address to Game structs
    mapping(address => Game) public activeGames;
    
    // required GTA balance ratio to host game (ratio of entry_fee desired)
    uint8 public hostRequirementPerc = 100; // max = 65,535 (uint16 max)
    
    // track activeGameCount to loop through 'gameCodes', for cleaning expired 'activeGames'
    uint64 public activeGameCount = 0;

    // track gameCodes, for cleaning expired 'activeGames'
    address[] storage private gameCodes;
    
    // game experation time _ 1 day = 86400 seconds
    uint32 private gameExpSec = 86400 * 1; // max 4,294,967,295
    
    // // maintain whitelist tokens that can be used for deposit
    // mapping(address => bool) public depositTokens;
    
    // // maintain local mapping of this contracts ERC20 token balances
    // mapping(address => uint256) private gtaAltBalances;
    // uint256 private gtaAltBalsLastBlockNum = 0;
    
    // track last block # that 'creditsUSD' has been udpated with
    uint32 private lastBlockNumUpdate = 0; // takes 1355 years to max out uint32

    // mapping of accepted usd stable coins for player deposits
    mapping(address => bool) public whitelistAlts;
    mapping(address => bool) public whitelistStables;
    uint8 private whitelistStablesUseIdx; // _getNextStableTokDeposit()

    // usd credits for players to pay entryFeeUSD to join games
    mapping(address => uint256) private creditsUSD;
    address[] storage private creditsAddrArray;

    // usd deposit fee taken out of amount used for creditsUSD updates
    //  - this is a simple fee 'per deposit' (goes to contract)
    //  - keeper has the option to set this fee
    uint256 private depositFeePerc = 0;

    // max percent of prize pool the host may charge
    uint8 public maxHostFeePerc = 100; // % of prize pool

    // service held by contract for all defi services
    uint8 public serviceFeePerc = 0; // % of prize pool

    // track this contract's whitelist token balances & debits (required for keeper 'SANITY CHECK')
    mapping(address => uint256) storage private whitelistBalances;
    mapping(address => uint256) storage private whitelistPendingDebits;

    struct TxDeposit {
        address token;
        address sender;
        uint256 amount;
    }

    // minimum deposits allowed (in usd value)
    uint8 public constant minPlayerDepositUSD_floor = 1; // 1 USD 
    uint8 public constant minPlayerDepositUSD_ceiling = 100; // 100 USD
    uint8 public minPlayerDepositUSD = 0; // dynamic, set by keeper
    uint256 private lastSwapTxGasFee = 0; // last gas paid for alt swap in 'settleBalances'

    // enbale/disable refunds for less than min deposit
    bool public enableMinDepositRefunds = true;

    // track gas fee wei losses due min deposit refunds
    uint256 private accruedGasFeeRefundLoss = 0;

    // minimum usd entry fee that host can create event with
    uint256 public minEventEntryFeeUSD = 0;

    // EVENTS
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // emit to client side when mnimium deposit refund is not met
    event MinimumDepositRefund(address sender, address token, uint256 amount, uint256 gasfee, uint256 accrued);

    // emit to client side when deposit fails; only due to min deposit fail (120323)
    event DepositFailed(address sender, address token, uint256 tokenAmount, uint256 stableAmount, uint256 minDepositUSD, bool refundsEnabled);

    // emit to client side when deposit processed (after sender's manual transfer to contract)
    event DepositProcessed(address sender, address token, uint256 amount, uint256 altSwapFee, uint256 depositFee, uint256 balance);

    // notify client side that an event distribution (winner payout) has occurred successuflly
    event EndEventDistribution(address winner, uint16 win_place, uint8 win_perc, uint32 win_usd, uint32 win_pool_usd, address stable);

    // notify client side that an end event has occurred successfully
    event EndEventActivity(address evtCode, address host, address[] memory winners, uint32 prizePoolUSD, uint32 hostFeelUSD, uint32 keeperFeeUSD, uint64 activeEvtCount, uint64 block_timestamp, uint256 block_number);

    // notify client side that an event has been canceled
    event ProcessedRefund(address player, uint32 refundAmountUSD, address evtCode, bool evtLaunched, uint256 evtExpTime);
    event CanceledEvent(address canceledBy, address evtCode, bool evtLaunched, uint256 evtExpTime, uint32 playerCount, uint32 prizePoolUSD, uint32 totalFeesUSD, uint32 totalRefundsUSD, uint32 indRefundUSD);

    // CONSTRUCTOR
    constructor(uint256 initialSupply) {
        // Set creator to owner & keeper
        owner = msg.sender;
        keeper = msg.sender;
        totalSupply = initialSupply * 10**uint8(decimals);
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function myCredits() public view returns (uint32) {
        return creditsUSD[msg.sender];
    }
    
    function addWhitelistStables(address[] _tokens) public onlyKeeper {
        for (uint i=0; i < _tokens.length; i++) {
            whitelistStables[_tokens[i]] = true;
        }
    }
    function remWhitelistStables(address[] _tokens) public onlyKeeper {
        for (uint i=0; i < _tokens.length; i++) {
            delete whitelistStables[_tokens[i]];
        }
    }
    function addWhitelistAlts(address[] _tokens) public onlyKeeper {
        for (uint i=0; i < _tokens.length; i++) {
            whitelistAlts[_tokens[i]] = true;
        }
    }
    function remWhitelistAlts(address[] _tokens) public onlyKeeper {
        for (uint i=0; i < _tokens.length; i++) {
            delete whitelistAlts[_tokens[i]];
        }
    }

    function setDepositFeePerc(uint8 perc) public onlyKeeper {
        depositFeePerc = perc;
    }

    function getLastBlockNumUpdate() public view onlyKeeper {
        return lastBlockNumUpdate;
    }

    function setMaxHostFeePerc(uint8 perc) public onlyKeeper returns (bool) {
        maxHostFeePerc = perc;
        return true;
    }

    function getCredits() public onlyKeeper returns (mapping(address => uint256)) {
        return creditsUSD;
    }

    function setMinimumEventEntryFeeUSD(uint8 _amount) public onlyKeeper {
        require(_amount > minPlayerDepositUSD, 'err: amount must be greater than minPlayerDepositUSD =)');
        minEventEntryFeeUSD = _amount;
    }

    function getAccruedGFRL() public view onlyKeeper returns (uint256) {
        return accruedGasFeeRefundLoss;
    }

    function setMinimumUsdValueDeposit(uint8 _amount) public onlyKeeper {
        require(minPlayerDepositUSD_floor <= _amount && _amount <= minPlayerDepositUSD_ceiling, 'err: invalid amount =)');
        minPlayerDepositUSD = _amount;
    }

    // returns GTA total stable balances - total player credits ('whitelistStables' - 'creditsUSD')
    //  can be done simply from client side as well (ie. w/ 'getCredits()', client side can calc balances)
    function getGrossNetBalances() public onlyKeeper {
        uint256 stable_bal = 0;
        for (uint i=0; i < whitelistStables.length; i++) {
            stable_bal += IERC20(whitelistStables[i]).balanceOf(address(this));
        }

        // LEFT OFF HERE... does it make any sense to integrate this?
        // uint256 stable_bal = 0;
        // for (uint i=0; i < whitelistPendingDebits.length; i++) {
        //     stable_bal += IERC20(whitelistPendingDebits[i]).balanceOf(address(this));
        // }

        uint256 owedCredits = 0;
        for (uint i=0; i < creditsAddrArray.length; i++) {
            owedCredits += creditsUSD[creditsAddrArray[i]];
        }

        uint256 net_bal = stable_bal - owedCredits;
        return [stable_bal, owedCredits, net_bal];
    }

    function _getTotalForUintArray(uint8 _arr) returns (uint8) {
        uint8 t = 0;
        for (uint i=0; i < _arr.length; i++) { t += _arr[i]; }
        return t;
    }

    // _winPercs: [%_1st_place, %_2nd_place, ...] = total 100%
    function createGame(string memory _gameName, uint64 _startTime, uint256 _entryFeeUSD, uint8 _hostFeePerc, uint8[] _winPercs) public returns (address) {
        require(_startTime > block.timestamp, "err: start too soon :/");
        require(_entryFeeUSD >= minEventEntryFeeUSD, "required: entry fee too low :/");
        require(_hostFeePerc <= maxHostFeePerc, 'host fee too high :O, check maxHostFeePerc');
        require(_winPercs.length > 0, 'no winners? :O');
        require(_getTotalForUintArray(_winPercs) == 100, 'err: invalid _winPercs values, requires 100 total :/');

        // verify msg.sender has enough GTA to host, by comparing against 'hostRequirementPerc' of '_entryFreeUSD'
        uint256 gta_bal = IERC20(address(this)).balanceOf(msg.sender); // returns x10**18

        // get stable quote for host's gta_bal (traverses 'routersUniswapV2')
        (uint8 rtrIdx, uint256 stable_quote) = best_swap_v2_router_idx_quote([address(this), _getNextStableTokDeposit()], gta_bal);
        require(stable_quote >= ((_entryFeeUSD * 10**18) * (hostRequirementPerc/100)), "err: not enough GTA to host :/");

        // verify active game name/code doesn't exist yet
        address gameCode = generateAddressHash(msg.sender, gameName);
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

        // Assign the newly modified 'Game' struct back to 'activeGames' 'mapping
        activeGames[gameCode] = newGame;
        
        // log new code in gameCodes array, for 'activeGames' support in 'cleanExpiredGames'
        gameCodes.push(gameCode);
        
        // increment 'activeGameCount', for 'activeGames' support in 'cleanExpiredGames'
        activeGameCount++;
        
        // return gameCode to caller
        return gameCode;
    }

    // msg.sender can add themself to any game (debits from msg.sender credits)
    //  *WARNING* preferred way for user registration, after manual transfer to this contract
    //     (instead of providing address to host and waiting for host to claim)
    // UPDATE_120223: make deposit then tweet to register
    //              1) send stable|alt deposit to gta contract
    //              2) tweet: @GamerTokenAward register <wallet_address> <game_code>
    //                  OR ... for free play w/ host register
    //              3) tweet: @GamerTokenAward play <wallet_address> <game_code>
    function registerEvent(address gameCode) public returns (bool) {
        require(gameCode != address(0), 'err: no game code ;o');

        // get/validate active game
        Game storage game = activeGames[gameCode];
        require(game.host != address(0), 'err: invalid game code :I')

        // check if game launched
        require(!game.launched, 'err: event launched :(');

        // check msg.sender for enough credits
        require(game.entryFeeUSD < creditsUSD[msg.sender], 'err: not enough credits :(, send whitelistAlts or whitelistStables');

        // debit entry fee from msg.sender credits (player)
        //  tracks addresses w/ creditsAddrArray
        _updateCredit(msg.sender, game.entryFeeUSD, true); // true = debit

        // -1) add msg.sender to game event
        game.players[msg.sender] = true;
        game.playerCnt += 1;
        
        return true;

        // address[] playerList = activeGames[gameCode].players;
        // for (uint i = 0; i < playerList.length; i++) {
        //     require(playerList[i] != _playerAddress, "err: player already joined game :[");
        // }
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

        // check msg.sender for enough credits
        require(game.entryFeeUSD < creditsUSD[msg.sender], 'err: not enough credits :(, send whitelistAlts or whitelistStables');

        // debit entry fee from msg.sender credits (host)
        //  tracks addresses w/ creditsAddrArray
        _updateCredit(msg.sender, game.entryFeeUSD, true); // true = debit

        // -1) add player to game event
        // game.players.push(player);
        game.players[_player] = true;
        game.playerCnt += 1;

        return true;
    }

    // cancel event and process refunds (host, players, keeper)
    //  host|keeper can cancel if event not 'launched' yet
    //  players can cancel if event not 'launched' & 'expTime' has passed
    function cancelEventProcessRefunds(address _eventCode) public {
        require(_eventCode != address(0), 'err: no event code :<>');

        // get/validate active event
        Game storage evt = activeGames[_eventCode];
        require(evt.host != address(0), 'err: invalid event code :<>')
        
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
            //  refunding full 'entryFeeUSD' means refunding w/o service fees removed
            //   *required: subtract all fees of all kind from 'entryFeeUSD' .... LEFT OFF HERE
                //
                // // loop through 'whitelistStables', generate stables available (bals ok for debit)
                // address[] memory stables_avail = _getStableTokensAvailDebit(win_usd);
                //
                // // traverse stables available for debit, select stable w/ the lowest market value            
                // address stable = _getStableTokenLowMarketValue(stables_avail);
                // require(stable != address(0), 'err: low market stable address is 0 _ :+0');            
                //
                // // send 'entryFeeUSD' back to player on chain (using lowest market value whitelist stable)
                // IERC20(stable).transfer(evt.players[i], evt.entryFeeUSD * 10**18); 

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
            _updateCredit(evt.players[i], evt.refundUSD_ind, false); // false = credit (tracks addresses w/ creditsAddrArray)

            // notify listeners of processed refund
            emit ProcessedRefund(evt.players[i], evt.refundUSD_ind, _eventCode, evt.launched, evt.expTime);
        }

        // notify listeners of canceled event
        emit CanceledEvent(msg.sender, _eventCode, evt.launched, evt.expTime, evt.playerCnt, evt.prizePoolUSD, evt.totalFeesUSD, evt.refundsUSD, evt.refundUSD_ind);
    }

    // host can start event w/ players pre-registerd for gameCode
    function hostStartEvent(address _gameCode) public returns (bool) {
        require(_gameCode != address(0), 'err: no game code :p');

        // get/validate active game
        Game storage game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I')

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // calc/set 'prizePoolUSD' & 'payoutsUSD' from 'entryFeeUSD' collected
        //  deduct all service fees (AFTER 'registerEvent|hostRegisterEvent)
        game = _generatePrizePool(game); // ? Game storage game = _generatePrizePool(game); ?
        game = _launchEvent(game); // set event state to 'launched = true'

        // LEFT OFF HERE ... 
        //  GTA token distribution (minting & burning)
        //   ref: 'registerEvent', 'hostRegisterEvent', 'cancelEventProcessRefunds', 'settleBalances' (maybe)
        //  1) buy & burn|hold integration (host chooses service-fee discount if paid in GTA)
        //  2) host & winners get minted some amount after event ends
        //      *required: mint amount < buy & burn amount

	    // LEFT OFF HERE … need to design how 'evt.buyAndBurnPerc|USD' comes into play

        return true;
    }

    // _winners: [0x1st_place, 0x2nd_place, ...]
    function hostEndEventWithWinners(address _gameCode, address[] memory _winners) public returns (bool) {
        require(_gameCode != address(0), 'err: no game code :p');
        require(_winner.length > 0, 'err: no winner :p');

        // get/validate active game
        struct memory game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I')

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // check if # of _winners == .winPercs array length (set during eventCreate)
        require(game.winPercs.length == _winners.length, 'err: number of winners =(')

        // loop through _winners: distribute 'game.winPercs'
        for (uint i=0; i < _winners.length; i++) {
            // verify winner address was registered in the game
            require(game.players[_winners[i]], 'err: invalid player found :/, check getPlayers & retry w/ all valid players');

            // calc win_usd
            address winner = _winners[i];
            uint256 win_usd = game.payoutsUSD[i];

            // pay winner
            address stable = _transferBestStable(winner, win_usd);

            // syncs w/ 'settleBalances' algorithm
            _increaseWhitelistPendingDebit(stable, win_usd);

            // notify client side that an end event distribution occurred successfully
            emit EndEventDistribution(winner, i, game.winPercs[i], win_usd, game.prizePoolUSD, stable);
        }

        // pay host & keeper
        address stable_host = _transferBestStable(game.host, game.hostFeeUSD);
        address stable_keep = _transferBestStable(keeper, game.keeperFeeUSD);

        // set event params to end state
        game = _endEvent(game, _gameCode);

        // notify client side that an end event occurred successfully
        emit EndEventActivity(_gameCode, game.host, _winners, game.prizePoolUSD, game.hostFeeUSD, game.keeperFeeUSD, activeGameCount, block.timestamp, block.number);
        
        return true;
    }

    // invoked by keeper client side, every ~10sec (~blocktime), to ...
    //  1) update credits logged from 'Transfer' emits
    //  2) convert alt deposits to stables (if needed)
    //  3) settle 'creditsUSD', 'whitelistBalances' & 'whitelistPendingDebits' (keeper 'SANITY CHECK')
    function settleBalances(TxDeposit[] memory dataArray, uint32 _lastBlockNum) public onlyKeeper {
        uint256 gasStart = gasleft(); // record start gas amount
        require(lastBlockNumUpdate < _lastBlockNum, 'err: invalid _lastBlockNum :O');

        // loop through ERC-20 'Transfer' events received from client side
        //  NOTE: to save gas (refunded by contract), keeper 'should' pre-filter event for ...
        //      1) 'whitelistStables' & 'whitelistAlts' (else 'require' fails)
        //      2) recipient = this contract address (else '_sanityCheck' fails)
        for (uint i = 0; i < dataArray.length; i++) { // python side: lst_evts_min[{token,sender,amount}, ...]
            if (!whitelistStables[dataArray[i].token] && !whitelistAlts[dataArray[i].token]) { continue; } // skip non-whitelist tokens
            
            address tok_addr = dataArray[i].token;
            address src_addr = dataArray[i].sender;
            uint256 tok_amnt = dataArray[i].amount;
            
            if (tok_addr == address(0) || src_addr == address(0)) { continue; } // skip 0x0 addresses
            if (tok_amnt == 0) { continue; } // skip 0 amount

            // verifiy keeper sent legit amounts from their 'Transfer' event captures (1 FAIL = revert everything)
            //   ie. force start over w/ new call & no gas refund; encourages keeper to not fuck up
            require(_sanityCheck(tok_addr, tok_amnt), 'err: whitelist<->chain balance mismatch :-{} _ KEEPER LIED!');

            // default: if found in 'whitelistStables'
            uint256 amntUsdCredit = tok_amnt; 
            uint256 altSwapFee = 0; // gas fee loss for swap: alt -> stable

            // if not in whitelistStables, swap alt for stable: tok_addr, tok_amnt
            if (!whitelistStables[tok_addr]) {

                // get stable coin to use & create swap path to it
                stable_addr = _getNextStableTokDeposit();
                address[] memory path = [tok_addr, stable_addr];

                // get stable amount quote for this alt deposit (traverses 'routersUniswapV2')
                (uint8 rtrIdx, uint256 stableAmnt) = best_swap_v2_router_idx_quote(path, tok_amnt);

                // if stable amount quote is below min deposit required
                if (stableAmnt < minPlayerDepositUSD) {  

                    // if rehunds enabled, process refund: send 'tok_amnt' of 'tok_addr' back to 'src_addr'
                    if (enableMinDepositRefunds) {
                        // log gas used for refund
                        uint256 start_trans = gasleft();

                        // send 'tok_amnt' of 'tok_addr' back to 'src_addr'
                        IERC20(tok_addr).transfer(src_addr, tok_amnt); 

                        // log gas used for refund
                        uint256 gasfeeloss = (start_trans - gasleft()) * tx.gasprice;
                        accruedGasFeeRefundLoss += gasfeeloss;

                        // notify client listeners that refund was processed
                        emit MinimumDepositRefund(src_addr, tok_addr, tok_amnt, gasfeeloss, accruedGasFeeRefundLoss);
                    }

                    // notify client side, deposit failed
                    emit DepositFailed(src_addr, tok_addr, tok_amnt, stableAmnt, minPlayerDepositUSD, enableMinDepositRefunds);

                    // skip to next transfer in 'dataArray'
                    continue;
                }

                // swap tok_amnt alt -> stable (log swap fee / gas loss)
                uint256 start_swap = gasleft();
                amntUsdCredit = swap_v2_wrap(path, routersUniswapV2[rtrIdx], tok_amnt);
                uint256 gasfeeloss = (start_swap - gasleft()) * tx.gasprice;

                // get stable quote for this swap fee / gas fee loss (traverses 'routersUniswapV2')
                (uint8 rtrIdx, altSwapFee) = best_swap_v2_router_idx_quote([TOK_WPLS, stable_addr]], gasfeeloss);

                // debit swap fee from 'amntUsdCredit'
                amntUsdCredit -= altSwapFee;                
            }

            // 1) debit deposit fees from 'amntUsdCredit' (keeper optional)
            uint256 depositFee = amntUsdCredit * (depositFeePerc/100);
            uint256 amnt = amntUsdCredit - depositFee;

            // LEFT OFF HERE ... take out all fees, this may need to be done in 'registerEvent|hostRegisterEvent'
            //  all fees of all kinds MUST be removed before call to '_updateCredit' in 'settleBalances'
            //   allows 'registerEvent|hostRegisterEvent' & 'cancelEventProcessRefunds' to sync w/ regard to 'entryFeeUSD'
            //      - 'settleBalances' credits 'creditsUSD' AFTER all fees removed
            //      - 'registerEvent|hostRegisterEvent' debits 'entryFeeUSD' from 'creditsUSD' (AFTER all fees removed)
            //      - 'cancelEventProcessRefunds' credits 'entryFeeUSD' to 'creditsUSD' (w/o regard for any fees)

            // 2) add 'amntUsdCredit' to 'mapping(src_addr => amount) creditsUSD' _ all fees removed
            //  handles tracking addresses w/ creditsAddrArray
            _updateCredit(src_addr, amnt, false); // false = credit

            // notify client side, deposit successful
            emit DepositProcessed(src_addr, tok_addr, tok_amnt, altSwapFee, depositFee, amnt);
        }

        // update last block number
        lastBlockNumUpdate = _lastBlockNum;

        // -1) calc gas used to this point & refund to 'keeper' (in wei)
        payable(msg.sender).transfer((gasStart - gasleft()) * tx.gasprice); // tx.gasprice in wei
    }

    function _transferBestStable(address _receiver, uint32 _amountUSD) private returns (address) {
        // loop through 'whitelistStables', generate stables available (bals ok for debit)
        address[] memory stables_avail = _getStableTokensAvailDebit(_amountUSD);

        // traverse stables available for debit, select stable w/ the lowest market value            
        address stable = _getStableTokenLowMarketValue(stables_avail);
        require(stable != address(0), 'err: low market stable address is 0 _ :+0');

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
            current service fees: 'depositFeePerc', 'hostFeePerc', 'keeperFeePerc', 'serviceFeePerc', 'supportFeePerc', 'winPercs'
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
        _evt.supportFeeUSD_ind = _evt.entryFeeUSD * (_evt.supportFeePerc/100); // optional

        // calc total fees for each individual 'entryFeeUSD' paid
        _evt.totalFeesUSD_ind = _evt.keeperFeeUSD_ind + _evt.serviceFeeUSD_ind + _evt.supportFeeUSD_ind;

        // calc: 'hostFeeUSD_ind' = 'hostFeePerc' of single 'entryFeeUSD' - 'totalFeesUSD_ind'
        _evt.hostFeeUSD_ind = (_evt.entryFeeUSD - _evt.totalFeesUSD_ind) * (_evt.hostFeePerc/100);

        // calc total fees for all 'entryFeeUSD' paid
        _evt.keeperFeeUSD = _evt.keeperFeeUSD_ind * _evt.playerCnt;
        _evt.serviceFeeUSD = _evt.serviceFeeUSD_ind * _evt.playerCnt;
        _evt.supportFeeUSD = _evt.supportFeeUSD_ind * _evt.playerCnt; // optional
        _evt.totalFeesUSD = _evt.keeperFeeUSD + _evt.serviceFeeUSD + _evt.supportFeeUSD;

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

    // *WARNING* whitelistStables could have duplicates (set by keeper)
    function _getStableTokensAvailDebit(uint32 _debitAmntUSD) private view returns (address[] memory) {
        // loop through white list stables, generate stables available (ok for debit)
        address[] memory stablesAvail = []; // stables available to cover debit
        for (uint 1 = 0; i < whitelistStables.length; i++) {

            // get balnce for this whitelist stable (push to stablesAvail if has enough)
            uint256 stableBal = IERC20(whitelistStables[i]).balanceOf(address(this));
            if (stableBal > _debitAmntUSD * 10**18) { 
                stablesAvail.push(whitelistStables[i]);
            }
        }
        return stablesAvail;
    }

    // *WARNING* stables_avail could have duplicates (from 'whitelistStables' set by keeper)
    function _getStableTokenLowMarketValue(address[] memory stables) private view returns (address) {
        // traverse stables available for debit, select stable w/ the lowest market value
        uint256 curr_high_tok_val = 0;
        address curr_low_val_stable = 0x0;
        for (uint i=0; i < stables.length, i++) {
            
            // get quote for this available stable (traverses 'routersUniswapV2')
            //  looking for the stable that returns the most when swapped 'from' WPLS
            //  the more USD stable received for 1 WPLS ~= the less overall market value that stable has
            address stable_addr = stables[i];
            (uint8 rtrIdx, uint256 tok_val) = best_swap_v2_router_idx_quote([TOK_WPLS, stable_addr]], 1 * 10**18);
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

        IUniswapV2Factory public uniswapFactory = IUniswapV2Factory(_factoryAddress);
        address pair = uniswapFactory.getPair(_token1, _token2);
        require(pair != address(0), 'err: pair does not exist');

        tok_liq_1 = _getLiquidityInPair(_token1, pair);
        tok_liq_2 = _getLiquidityInPair(_token2, pair);
        return (tok_liq_1, tok_liq_2);
    }

    // traverse 'whiltelistStables' using 'whitelistStablesUseIdx'
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
        _settlePendingDebit(token); // sync 'whitelistBalances' w/ 'whitelistPendingDebits'
        _increaseWhitelistBalance(token, amount); // sync 'whitelistBalances' w/ this 'Transfer' emit
        uint256 chainBal = IERC20(token).balanceOf(address(this));
        return whitelistBalances[token] == chainBal;
    }

    // deduct debits accrued from 'hostEndEventWithWinners'
    function _settlePendingDebit(address token) private {
        require(whitelistBalances[tok_addr] >= whitelistPendingDebits[tok_addr], 'err: insefficient balance to settle debit :O');
        whitelistBalances[tok_addr] -= whitelistPendingDebits[tok_addr];
        delete whitelistPendingDebits[tok_addr];
    }

    // update stable balance from IERC20 'Transfer' emit (delegated by keeper -> 'settleBalances')
    function _increaseWhitelistBalance(address token, uint256 amount) private {
        require(token != address(0), 'err: no address :{');
        require(amount != 0, 'err: no amount :{');
        whitelistBalances[tok_addr] += tok_amnt;
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
                _remCreditsAddrArray(_player);
            }
        } else { 
            creditsUSD[_player] += _amountUSD; 
            _addCreditsAddrArraySafe[_player]; // removes first
        }
    }

    // ensures _player address is logged only once in creditsAddrArray (ie. safely)
    function _addCreditsAddrArraySafe(address _player) private returns (bool) {
        require(_player != address(0), "err: invalid _player");
        bool success = _remCreditsAddrArray(_player);
        creditsAddrArray.push(_player);
        return true;
    }

    // remove algorithm does NOT maintain order
    function _remCreditsAddrArray(address _player) private returns (bool) {
        require(_player != address(0), "err: invalid _player");
        arr = creditsAddrArray;
        for (i = 0; i < rtrs.length; i++) {
            if (_player == arr[i]) {
                arr[i] = arr[rtrs.length - 1];
                arr.pop();
                creditsAddrArray = arr;
                return true;
            }
        }
        return false;
    }

    // uniswap v2 protocol based: get router w/ best quote in 'routersUniswapV2'
    function best_swap_v2_router_idx_quote(addressp[] memory path, uint256 amount) private returns (uint8) {
        uint8 currHighIdx = 37;
        uint256 currHigh = 0;
        for (uint i = 0; i < routersUniswapV2.length, i++) {
            uint256[] memory amountsOut = IUniswapV2(routersUniswapV2[i]).getAmountsOut(amount, path); // quote swap
            if (amountsOut[amountsOut.length-1] > currHigh) {
                currHigh = amountsOut[amountsOut.length-1];
                currHighIdx = i;
            }
        }

        return (currHighIdx, currHigh);
    }

    // uniwswap v2 protocol based: get quote and execute swap
    function swap_v2_wrap(address[] memory path, address router, uint256 amntIn) private returns (uint256) {
        //address[] memory path = [weth, wpls];
        uint256[] memory amountsOut = IUniswapV2(router).getAmountsOut(amntIn, path); // quote swap
        uint256 amntOut = swap_v2(router, path, amntIn, amountsOut[amountsOut.length -1], false); // execute swap
                
        // verifiy new balance of token received
        uint256 new_bal = IERC20(path[path.length -1]).balanceOf(address(this));
        require(new_bal >= amntOut, "err: balance low :{");
        
        return amntOut;
    }
    
    // v2: solidlycom, kyberswap, pancakeswap, sushiswap, uniswap v2, pulsex v1|v2, 9inch
    function swap_v2(address router, address[] memory path, uint256 amntIn, uint256 amntOutMin, bool fromETH) private returns (uint256) {
        emit logRFL(address(this), msg.sender, "logRFL 6a");
        IUniswapV2 swapRouter = IUniswapV2(router);
        
        emit logRFL(address(this), msg.sender, "logRFL 6b");
        IERC20(address(path[0])).approve(address(swapRouter), amntIn);
        uint deadline = block.timestamp + 300;
        
        emit logRFL(address(this), msg.sender, "logRFL 6c");
        if (fromETH) {
            uint[] memory amntOut = swapRouter.swapExactETHForTokens{value: amountUSD}(
                            amntOutMin,
                            path, //address[] calldata path,
                            address(this), // to
                            deadline
                        );
        } else {
            uint[] memory amntOut = swapRouter.swapExactTokensForTokens(
                            amntIn,
                            amntOutMin,
                            path, //address[] calldata path,
                            address(this),
                            deadline
                        );
        }
        emit logRFL(address(this), msg.sender, "logRFL 6d");
        return uint256(amntOut[amntOut.length - 1]); // idx 0=path[0].amntOut, 1=path[1].amntOut, etc.
    }
    
    function addDexRouter(address router) public onlyKeeper {
        require(router != address(0x0), "err: invalid address");
        rtrs = routersUniswapV2;
        for (i = 0; i < rtrs.length; i++) {
            if (router == rtrs[i]) {
                revert("err: duplicate router");
            }
        }
        routersUniswapV2.push(router);
    }
    
    function remDexRouter(address router) public onlyKeeper returns (bool) {
        require(router != address(0x0), "err: invalid address");
        
        // NOTE: remove algorithm does NOT maintain order
        
        rtrs = routersUniswapV2;
        for (i = 0; i < rtrs.length; i++) {
            if (router == rtrs[i]) {
                rtrs[i] = rtrs[rtrs.length - 1];
                rtrs.pop();
                routersUniswapV2 = rtrs;
                return true;
            }
        }
        return false;
    }
    
    // house_112023: don't think this function is needed anymore, was being used in legacy 'logCredit'
    //  something like this is indeed now being used in 'settleBalances'
    // function getDexQuoteUSD(address _token, uint256 _amountIn) private view returns (uint256) {
    //     require(_token != address(0x0), "err: no token");
    //     require(_amountIn > 0, "err: no token amount");
    //     path = [_token, dai_ethmain_pcwrap]
    //     uint256 curr_low = 37373737; // unlikely that any amnt will equal 37373737
    //     rtrs = routersUniswapV2;
    //     for (uint i; i < rtrs.length; i++) {
    //         router = rtrs[i];
    //         uint256[] memory amountsOut = IUniswapV2(router).getAmountsOut(_amountIn, path); // quote swap
    //         uint256 amnt = amountsOut[amountsOut.length -1];
    //         if (curr_low == 37373737 || curr_low > amnt) {
    //             curr_low = amnt;
    //         }
    //     }
    //     return curr_low;
    // }
    
    // LEFT OFF HERE... legacy code that was trying to use this contract code's
    //   to handle all ERC20 token transfers to it
    //  but i think this 'transfer' function is needed as part of IERC20
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        // want to try to keep track of each ERC20 transfer to this contract from each recipient
        // each ERC20 transfer to this contract is an 'entry_fee' being paid by a player
        //  need to map those payments to gameCodes
        if (recipient == address(this)) {
            // Creates a default empty 'Game' struct (if doesn't yet exist in 'activeGames' mapping)
            PaidEntry[] memory entries = playerEntries[msg.sender];
            entries.gameCode = 0x0;
            entries.amount = _amount;
        }
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    // MODIFIERS
    modifier onlyAdmins(address gameCode) {
        require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
        bool isHost = msg.sender == activeGames[gameCode].host;
        bool isKeeper = msg.sender == keeper;
        bool isOwner = msg.sender == owner;
        require(isKeeper || isOwner || isHost, 'err: only admins :/*');
        _;
    }
    modifier onlyHost(address gameCode) {
        require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
        require(msg.sender == activeGames[gameCode].host, "Only the host :0");
        _;
    }    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner :0");
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
        
    // GETTERS / SETTERS (keeper)
    function getKeeper() public view onlyKeeper returns (address) {
        return keeper;
    }
    function getGameCodes() public view onlyKeeper returns (address[] memory) {
        return gameCodes;
    }
    function getGameExpSec() public view onlyKeeper returns (uint64) {
        return gameExpSec;
    }
    function setKeeper(address _newKeepr) public onlyKeeper {
        keeper = _newKeepr;
    }
    function setOwner(address _newOwner) public onlyKeeper {
        owner = _newOwner;
    }
    function setGameExpSec(uint64 sec) public onlyKeeper {
        gameExpSec = sec;
    }
    function addDepositToken(address _token) public onlyKeeper {
        depositTokens[_token] = true;
    }
    function removeDepositToken(address _token) public onlyKeeper {
        delete depositTokens[_token];
    }
    
    // GETTERS / SETTERS
    function getHostRequirementForEntryFee(uint256 _entryFeeUSD) public pure returns (uint256) {
        return _entryFeeUSD * (hostRequirementPerc/100);
        // can also just get the public class var directly: 'hostRequirementPerc'
    }
    function getGameCode(address _host, string memory _gameName) public view returns (address) {
        require(_host != address(0x0), "err: no host address :{}"); // verify _host address input
        require(bytes(_gameName).length > 0, "err: no game name :{}"); // verifiy _gameName input
        require(activeGameCount > 0, "err: no activeGames :{}"); // verify there are active activeGames

        // generate gameCode from host address and game name
        address gameCode = generateAddressHash(_host, gameName);
        require(bytes(activeGames[gameCode].gameName).length > 0, "err: game code not found :{}"); // verify gameCode exists
        
        return gameCode;
    }

    // LEFT OFF HERE... needs to be refactored to handle returning a mapping instead of array
    function getPlayers(address gameCode) public view onlyAdmins(gameCode) returns (address[] memory) {
        return activeGames[gameCode].players;
    }
    
    function payWinners() {
        /*
            maintaining value:
            - % of game's prize pool goes back to dex LPs
            - % of game's prize pool goes to buying GTA off the open market (into GTA contract)
            - host wallets must retain a certain amount of GTA in order to create activeGames
                (probably some multiple of the intended player_entry_fee)
        */
    }
    
    function generateAddressHash(address host, string memory uid) private pure returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));
        address generatedAddress = address(uint160(uint256(hash)));
        return generatedAddress;
    }
    
    // LEFT OFF HERE... need to refactor to handle games.players mapping instead of array
    // Delete activeGames w/ an empty players array and expTime has past
    function cleanExpiredGames() public {
        // loop w/ 'activeGameCount' to find game addies w/ empty players array & passed 'expTime'
        for (uint256 i = 0; i < activeGameCount; i++) {
        
            // has the expTime passed?
            if (block.timestamp > activeGames[gameCodes[i]].expTime) {
            
                // is game's players array empty?
                if (activeGames[gameCodes[i]].players.length == 0) {
                    delete activeGames[gameCodes[i]]; // remove gameCode mapping entry
                    delete gameCodes[i]; // remove gameCodes array entry
                    activeGameCount--; // decrement total game count
                }
            }
        }
    }
    
    // STANDARD IERC20
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(sender != address(0), "TransferFrom: sender cannot be the zero address");
        require(recipient != address(0), "TransferFrom: recipient cannot be the zero address");
        require(_balances[sender] >= amount, "TransferFrom: sender does not have enough balance");
        require(_allowances[sender][msg.sender] >= amount, "TransferFrom: allowance exceeded");

        _transfer(sender, recipient, amount);

        // Update the allowance
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "DecreaseAllowance: allowance cannot be decreased below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    function mint(address to, uint256 amount) public onlyOwner returns (bool) {
        require(to != address(0), "Mint: cannot mint to the zero address");

        _totalSupply = _totalSupply + amount;
        _balances[to] = _balances[to] + amount;

        emit Transfer(address(0), to, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid new owner address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/*****************/
/*** DEAD CODE ***/
/*****************/

// host can add players to their own games, by claiming address credits waiting in creditsUSD (debits from player credits)
//  *WARNING* players should not share their addresses with anyone 'except' the host
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
