// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

    //mapping(address => address) public game_to_hosts; // game_code to host_addr
    //mapping(addess => uint256[]) public game_to_fees; // game_code to array [entry_fee, host_fee]
    //mapping(address => address[]) public game_to_players; // game_code to players array
    
    /* ... need to design & store mapping for host created activeGames
            input param: entry fee, host fee
            generate & store game code,
    */

        // ... generate & store game code
        // ... store entry_fee mapped to game code
        // ... store host_fee mapped to game code
        // ... store host_addr mapped to game code
        
        /* use case to consider:
            host wants to pay entire prize pool
                how are player addresses added to game code mapping
                 w/o paying an entry fee
            host wants to a create free game for anyone (w/ no prize pool)
                don't use GTA :O
        */
        
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
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
    address private constant TOK_eDAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address private constant TOK_eDAI_pcwrap = address(0xefD766cCb38EaF1dfd701853BFCe31359239F305);
    
    // PulseXSwapRouter 'v1' ref: MM tx | PulseXRouter02 'v1|2' ref: https://www.irccloud.com/pastebin/6ftmqWuk
    address private constant ROUTER_pulsex_vX = address(0xa619F23c632CA9f36CD4Dcea6272E1eA174aAC27);
    address private constant ROUTER_pulsex_v1 = address(0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02);
    address private constant ROUTER_pulsex_v2 = address(0x165C3410fC91EF562C50559f7d2289fEbed552d9);
    
    // array of all dex routers to check for 'getDexQuoteUSD'
    address[] storage private routersUniswapV2 = [ROUTER_pulsex_v1, ROUTER_pulsex_v2, ROUTER_pulsex_vX];
        
    /* _ GAME SUPPORT _ */
    struct Game {
        address host;
        string gameName;
        uint256 entryFeeUSD;
        uint8 hostFeePerc;
        uint8[] winPercs;
        // address[] players;
        mapping(address => bool) players;
        uint256 playerCnt;
        uint256 prizePoolUSD;
        uint256 createTime;
        uint256 startTime;
        uint256 launchTime;
        uint256 launchBlockNum;
        uint256 endTime;
        uint256 endBlockNum;
        bool launched;
        bool ended;
        bool expired;
        uint256 expTime;
    }
    
    // map generated gameCode address to Game structs
    mapping(address => Game) public activeGames;
    
    // required GTA balance ratio to host game (ratio of entry_fee desired)
    uint16 public hostRequirementPercent = 100; // max = 65,535 (uint16 max)
    
    // track activeGameCount to loop through 'gameCodes', for cleaning expired 'activeGames'
    uint256 public activeGameCount = 0;

    // track gameCodes, for cleaning expired 'activeGames'
    address[] storage private gameCodes;
    
    // game experation time _ 1 day = 86400 seconds
    uint64 private gameExpSec = 86400 * 1;
    
    // // maintain whitelist tokens that can be used for deposit
    // mapping(address => bool) public depositTokens;
    
    // // maintain local mapping of this contracts ERC20 token balances
    // mapping(address => uint256) private gtaAltBalances;
    // uint256 private gtaAltBalsLastBlockNum = 0;
    
    // track last block # that 'creditsUSD' has been udpated with
    uint32 private lastBlockNumUpdate = 0; // takes 1355 years to max out uint32

    // mapping of accepted usd stable coins for player deposits
    mapping(address => bool) public whitelistStables;
    mapping(address => bool) public whitelistAlts;

    // usd credits for players to pay entryFeeUSD to join games
    mapping(address => uint256) private creditsUSD;
    address[] storage private creditsAddrArray;

    // usd deposit fee taken out of amount used for creditsUSD updates
    //  - this is a simple fee 'per deposit' (goes to contract)
    //  - keeper has the option to set this fee
    uint256 private usdStableDepositFeePerc = 0;

    // max percent of prize pool the host may charge
    uint8 private maxHostFeePerc = 100;

    // track this contract's whitelist token balances & debits (required for keeper 'SANITY CHECK')
    mapping(address => uint256) storage whitelistBalances;
    mapping(address => uint256) storage whitelistPendingDebits;

    // CONSTRUCTOR
    constructor(uint256 initialSupply) {
        // Set creator to owner & keeper
        owner = msg.sender;
        keeper = msg.sender;
        totalSupply = initialSupply * 10**uint8(decimals);
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function setMaxHostFeePerc(uint8 perc) public onlyKeeper returns (bool) {
        maxHostFeePerc = perc;
        return true;
    }

    function getCredits() public onlyKeeper returns (mapping(address => uint256)) {
        return creditsUSD;
    }

    // returns GTA total stable balances - total player credits ('whitelistStables' - 'creditsUSD')
    //  can be done simply from client side as well (ie. w/ 'getCredits()', client side can calc balances)
    function getGrossNetBalances() public onlyKeeper {
        uint256 stable_bal = 0;
        for (uint i=0; i < whitelistStables.length; i++) {
            stable_bal += IERC20(whitelistStables[i]).balanceOf(address(this));
        }
        
        uint256 owedCredits = 0;
        for (uint i=0; i < creditsAddrArray.length; i++) {
            owedCredits += creditsUSD[creditsAddrArray[i]];
        }

        uint256 net_bal = stable_bal - owedCredits;
        return [stable_bal, owedCredits, net_bal];
    }

    // _winners: [0x1st_place, 0x2nd_place, ...]
    function hostEndEventWithWinners(address _gameCode, address[] memory _winners) public returns (bool) {
        require(_gameCode != address(0), 'err: no game code :p');
        require(_winner.length > 0, 'err: no winner :p');
        require(_winners.length == _distrPercs.length, 'err: winner/percs length mismatch =(');

        // get/validate active game
        struct storage game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I')

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // check if number of winners lines up with winpercs array lenght set in event create
        require(game.winPercs.length == _winners.length, 'err: number of winners =(')

        // loop through _winners: distribute 'game.winPercs'
        for (uint i=0; i < _winners.length; i++) {
            // check if winner address was a player in the game
            require(game.players[_winners[i]], 'err: invalid player found :/, retry with ALL valid players');

            // calc win_usd
            address winner = _winners[i];
            uint8 win_perc = game.winPercs[i];
            uint256 win_pool = game.prizePoolUSD;
            uint256 win_usd = win_pool * (win_perc/100);

            // LEFT OFF HERE... need to design away to choose stables from 'whitelistStables'
            address tok_addr = 0x0; // stable token address chosen
            IERC20(tok_addr).transfer(winner, win_usd); // send 'win_usd' amount to 'winner'

            // syncs w/ 'settleBalances' algorithm
            _increasePendingDebit(tok_addr, win_usd);
        }

        // set game end state (doesn't matter if its about to be deleted)
        game.endTime = block.timestamp;
        game.endBlockNum = block.number;
        game.ended = true;

        // delete game mapping
        delete activeGames[_gameCode];
        activeGameCount--;

        return true;
    }

    // host can start event w/ players pre-registerd for gameCode
    function hostStartEvent(address _gameCode) public returns (bool) {
        require(_gameCode != address(0), 'err: no game code :p');

        // get/validate active game
        struct storage game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I')

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // set game launched state
        game.launchTime = block.timestamp;
        game.launchBlockNum = block.number;
        game.launched = true;
        return true;
    }

    // msg.sender can add themself to any game (debits from msg.sender credits)
    //  *WARNING* preferred way for user registration, after manual transfer to this contract
    //     (instead of providing address to host and waiting for host to claim)
    function registerEvent(address gameCode) public returns (bool) {
        require(gameCode != address(0), 'err: no game code ;o');

        // get/validate active game
        struct storage game = activeGames[gameCode];
        require(game.host != address(0), 'err: invalid game code :I')

        // check if game launched
        require(!game.launched, 'err: event launched :(');

        // check msg.sender for enough credits
        require(game.entryFeeUSD < creditsUSD[msg.sender], 'err: not enough credits :(, send whitelistAlts or whitelistStables');
        
        // debit entry fee from msg.sender credits (player)
        // creditsUSD[msg.sender] -= game.entryFeeUSD;
        // handles tracking addresses w/ creditsAddrArray
        _updateCredit(msg.sender, uint256 game.entryFeeUSD, true); // true = debit

        // -1) add msg.sender to game event
        // game.players.push(msg.sender);
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
        struct storage game = activeGames[_gameCode];
        require(game.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // check if game launched
        require(!game.launched, 'err: event launched :(');

        // check msg.sender for enough credits
        require(game.entryFeeUSD < creditsUSD[msg.sender], 'err: not enough credits :(, send whitelistAlts or whitelistStables');

        // debit entry fee from msg.sender credits (host)
        // creditsUSD[msg.sender] -= game.entryFeeUSD;
        // handles tracking addresses w/ creditsAddrArray
        _updateCredit(msg.sender, game.entryFeeUSD, true); // true = debit

        // -1) add player to game event
        // game.players.push(player);
        game.players[_player] = true;
        game.playerCnt += 1;

        return true;
    }

    // host can add players to their own games, by claiming address credits waiting in creditsUSD (debits from player credits)
    //  *WARNING* players should not share their addresses with anyone 'except' the host
    //      (player credits can be freely claimed by any hosted game, if enough credits are available; brute-force required)
    function hostRegisterEventClaim(address player, address gameCode) public returns (bool) {
        require(player != address(0), 'err: no player ;l');

        // get/validate active game
        struct storage game = activeGames[gameCode];
        require(game.host != address(0), 'err: invalid game code :I');

        // check if msg.sender is game host
        require(game.host == msg.sender, 'err: only host :/');

        // check if game launched
        require(!game.launched, 'err: event launched :(');

        // check player for enough credits
        require(game.entryFeeUSD < creditsUSD[player], 'err: not enough claimable credits :(');

        // debit entry fee from player credits
        // creditsUSD[player] -= game.entryFeeUSD;
        // handles tracking addresses w/ creditsAddrArray
        _updateCredit(player, game.entryFeeUSD, true); // true = debit

        // -1) add player to game event
        // game.players.push(player);
        game.players[player] = true;
        game.playerCnt += 1;

        return true;
    }


    function setDepositFeePerc(uint8 perc) public onlyKeeper {
        usdStableDepositFeePerc = perc;
    }

    function getLastBlockNumUpdate() public view onlyKeeper {
        return lastBlockNumUpdate;
    }

    
    //  DONE: ready to pass data from 'Transfer' event logs on python side
    //  DONE:    - need to update mapping for player usd credits
    //  N/A:     - may need to maintain mapping of GTA contract alt coin balances
    //  DONE:        or maybe just swap for usd stables immediately (i forgot)
    //  DONE: should only pass the bare-min data needed
    //  N/A:  should probably use pyton side to calc USD credit vals for alt coin transfers
    //  DONE:    however, we need to actually make the swaps on chain

    // LEFT OFF HERE... 
    //       note: need to keep track of all 'expenses' and deduct from usd credit balances
    //          ie. gas fees, dex swap fees, etc.    
    struct TxDeposit {
        address token;
        address sender;
        uint256 amount;
    }
    
    // invoked by keeper client side, every ~10sec (~blocktime), to ...
    //  1) update credits logged from 'Transfer' emits
    //  2) settle 'whitelistBalances' & 'whitelistPendingDebits' (keeper 'SANITY CHECK')
    function settleBalances(TxDeposit[] memory dataArray, uint32 _lastBlockNum) public onlyKeeper {
        gasStart = gasleft(); // record start gas amount
        require(lastBlockNumUpdate < _lastBlockNum, 'err: invalid _lastBlockNum :O');

        // loop through ERC-20 'Transfer' events received from client side
        // NOTE: to save gas (refunded by contract), keeper 'should' pre-filter event for ...
        //  1) 'whitelistStables' & 'whitelistAlts' (else 'require' fails)
        //  2) recipient = this contract address (else '_sanityCheck' fails)
        for (uint i = 0; i < dataArray.length; i++) { // python side: lst_evts_min[{token,sender,amount}, ...]
            address tok_addr = dataArray[i].token;
            address src_addr = dataArray[i].sender;
            uint256 tok_amnt = dataArray[i].amount;
            require(tok_addr != address(0), 'err: found transfer w/ no token address :/');
            require(src_addr != address(0), 'err: found transfer w/ no sender address :/');
            require(tok_amnt != 0, 'err: found transfer w/ no amount :/');
            require(whitelistStables[tok_addr] || whitelistAlts[tok_addr], 'err: found transfer w/ non-whitelist token =(');
            require(_sanityCheck(tok_addr, tok_amnt), 'err: whitelist<->chain balance mismatch :-{} _ KEEPER LIED!');

            // default: if found in 'whitelistStables'
            uint256 amntUsdCredit = tok_amnt; 

            // if not in whitelistStables, swap alt for stable: tok_addr, tok_amnt
            if (!whitelistStables[tok_addr]) {
                // LEFT OFF HERE ... globals needed: stable_addr to generate 'path'
                address[] memory path = [tok_addr]; // generate path: [tok_addr, stable_addr]
                rtrIdx = best_swap_v2_router_idx(path, tok_amnt) // get best price router idx (traverse 'routersUniswapV2')
                amntUsdCredit = swap_v2_wrap(path, routersUniswapV2[rtrIdx], tok_amnt); // swap alt -> stable
            }

            // 1) add 'amntUsdCredit' to 'mapping(src_addr => amount) creditsUSD'
            //  dex fees already taken out
            //  'usdStableDepositFeePerc' set by keeper (optional)
            //  handles tracking addresses w/ creditsAddrArray
            uint256 amnt = (amntUsdCredit - (amntUsdCredit * usdStableDepositFeePerc/100));
            _updateCredit(src_addr, amnt, false); // false = credit
        }

        // update last block number
        lastBlockNumUpdate = _lastBlockNum;

        // -1) calc gas used to this point & refund to 'keeper' (in wei)
        uint256 gasUsed = gasStart - gasleft(); // calc gas used
        payable(msg.sender).transfer(gasUsed * tx.gasprice); // gasprice in wei
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

    // aggregate debits incurred from 'hostEndEventWithWinners'
    function _increasePendingDebit(address token, uint256 amount) private {
        // whitelistPendingDebits[tok_addr] += win_usd; // syncs w/ 'settleBalances' algorithm
        whitelistPendingDebits[token] += amount;
    }

    function _updateCredit(address _player, uint256 _amount, bool _debit) private {
        if (_debit) { 
            // ensure there is enough credit before debit
            require(creditsUSD[_player] >= _amount, 'err: invalid credits to debit :[');
            creditsUSD[_player] -= _amount;

            // if balance is now 0, remove _player from balance tracking
            if (creditsUSD[_player] == 0) {
                _remCreditsAddrArray(_player);
            }
        } else { 
            creditsUSD[_player] += _amount; 
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
    function best_swap_v2_router_idx(addressp[] memory path, uint256 amount) private returns (uint8) {
        uint8 currHighIdx = 37;
        uint256 currHigh = 0;
        for (uint i = 0; i < routersUniswapV2.length, i++) {
            uint256[] memory amountsOut = IUniswapV2(routersUniswapV2[i]).getAmountsOut(amount, path); // quote swap
            if (amountsOut[amountsOut.length-1] > currHigh) {
                currHigh = amountsOut[amountsOut.length-1];
                currHighIdx = i;
            }
        }

        return currHighIdx;
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

    /** LEGACY CREDIT MODEL */
    // function logCredit(address _player, address _token, uint256 _amount, uint256 lastBlock) public onlyKeeper {
    //     uint256 prev_bal = gtaAltBalances[_token];
    //     uint256 new_bal = IERC20(_token).balanceOf(address(this));
    //     required(new_bal > prev_bal, "err: token bal mismatch");
    //         // 'logCredit' gets called after ever time a token transfer to this contract occurs
    //         // hence, if new_bal < prev_bal
    //         //  then that means this contract spent some _token
    //         //  after a token transfer occurred (mined)
    //         //   and before this 'logCredit' was called
            
    //         // LEFT OFF HERE... is this correct? ^
            
    //     //gtaAltBalances[_token] += _amount;
    //     gtaAltBalances[_token] = new_bal;
        
    //     // LEFT OFF HERE... does this logic work? ^
        
    //     amountUSD = getDexQuoteUSD(_token, _amount);
    //     creditsUSD[_player] += amountUSD;
    // }
    
    // //address[] memory thisContractTransfer;
    // struct PaidEntries {
    //     address[] gameCode;
    //     uint256[] ammount;
    // }
    // struct PaidEntry {
    //     address gameCode;
    //     uint256 ammount;
    // }
    
    // // one player address can have many PaidEntries
    // //mapping(address => PaidEntries[]) memory playerEntries;
    // mapping(address => PaidEntry[]) memory playerEntries;
    
    // function findGameCode(PaidEntry[] memory entries, address _gameCode) private pure returns (bool) {
    //     for (uint i; i < entries.length; i++) {
    //         PaidEntry memory entry = entries[i];
    //         if (entry.gameCode == _gameCode) {
    //             // player has already paid for this gameCode
    //             return true;
    //         }
    //     }
    //     return false;
    // }
    
    // function joinGame(address _gameCode, address _playerAddress) public validGame(_gameCode) {
    //     require(_playerAddress != address(0x0), "err: no player address :["); // verify _playerAddress input
    //     address[] playerList = activeGames[gameCode].players;
    //     for (uint i = 0; i < playerList.length; i++) {
    //         require(playerList[i] != _playerAddress, "err: player already joined game :[");
    //     }

    //     // ... LET OFF HERE: player has to pay entry fee somehow
    //     uint256 gameEntryFee = activeGames[gameCode].entryFeeUSD;
        
    //     // ... left off here...
    //     //  want to keep track of all balances that players send to this contract
    //     //   but players can pay entry fee in any token they want (respectful approved list)
        
        
    //     // need to check if msg.sender has paid for this gameCode
    //     PaidEntry[] memory entries = playerEntries[msg.sender];
    //     bool playerJoined = findGameCode(entries, _gameCode);
        
    //     bool playerPaid = findGameCode(entries, _gameCode);
    //     require(playerPaid, "err: play")
    //     //bool playerPaid = False;
        
    //     for (uint i; i < entries.length; i++) {
    //         PaidEntry memory entry = entries[i];
    //         if (entry.gameCode == _gameCode) {
    //             // player has already paid for this gameCode
    //             playerPaid = true;
    //             break;
    //         }
    //         newEntry.amount =
    //     }
        
        
    //     /*
    //         maintaining value:
    //         - % of game's prize pool goes back to dex LPs
    //         - % of game's prize pool goes to buying GTA off the open market (into GTA contract)
    //         - host wallets must retain a certain amount of GTA in order to create activeGames
    //             (probably some multiple of the intended player_entry_fee)
    //     */
    //     // add player to gameCode mapping
    //     activeGames[gameCode].gameName.players.push(_playerAddress);
    // }
    
    // function addPlayer(address gameCode, address playerAddress) public validGame(gameCode) {
    //     Game storage selectedGame = activeGames[gameCode];
    //     selectedGame.players.push(playerAddress);
        
    //     // TOOD: player needs to pay entry fee
    // }
    
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
    function getDexQuoteUSD(address _token, uint256 _amountIn) private view returns (uint256) {
        require(_token != address(0x0), "err: no token");
        require(_amountIn > 0, "err: no token amount");
        path = [_token, dai_ethmain_pcwrap]
        uint256 curr_low = 37373737; // unlikely that any amnt will equal 37373737
        rtrs = routersUniswapV2;
        for (uint i; i < rtrs.length; i++) {
            router = rtrs[i];
            uint256[] memory amountsOut = IUniswapV2(router).getAmountsOut(_amountIn, path); // quote swap
            uint256 amnt = amountsOut[amountsOut.length -1];
            if (curr_low == 37373737 || curr_low > amnt) {
                curr_low = amnt;
            }
        }
        return curr_low;
    }
    
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
    
    // EVENTS
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // MODIFIERS
    modifier onlyAdmins(address gameCode) {
        require(activeGames[gameCode].host != address(0), 'err: gameCode not found :(');
        bool isHost = msg.sender == activeGames[gameCode].host;
        bool isKeeper = msg.sender == keeper;
        bool isOwner = msg.sender == owner;
        require(isKeeper || isOwner || isHost, 'err: only host :/*');
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
        return _entryFeeUSD * (hostRequirementPercent/100);
        // can also just get the public class var directly: 'hostRequirementPercent'
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
    
    // _winPercs: [%_1st_place, %_2nd_place, ...]
    function createGame(string memory _gameName, uint64 _startTime, uint256 _entryFeeUSD, uint8 _hostFeePerc, uint8[] _winPercs) public returns (address) {
        require(_startTime > block.timestamp, "err: start too soon :/");
        require(_entryFeeUSD >= 1, "required: entry fee >= 1 USD :/");
        require(_hostFeePerc <= maxHostFeePerc, 'host fee too high');
        require(_winPercs.length > 0, 'no winners? :O');

        // verify msg.sender has enough GTA to host
        uint256 bal = IERC20(address(this)).balanceOf(msg.sender); // returns x10**18
        require(bal >= (_entryFeeUSD * (hostRequirementPercent/100)), "err: not enough GTA to host :/");

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
        newGame.hostFeePerc = _hostFeePerc;
        newGame.winPercs = _winPercs;
        newGame.createTime = block.timestamp;
        newGame.startTime = _startTime;
        newGame.expTime = _startTime + gameExpSec;
        newGame.playerCnt = 0;
        newGame.prizePoolUSD = 0;
        newGame.launched = false;
        newGame.ended = false;
        newGame.expired = false;

        // Assign the newly modified 'Game' struct back to 'activeGames' 'mapping
        activeGames[gameCode] = newGame;
        
        // log new code in gameCodes array, for 'activeGames' support in 'cleanExpiredGames'
        gameCodes.push(gameCode);
        
        // increment 'activeGameCount', for 'activeGames' support in 'cleanExpiredGames'
        activeGameCount++;
        
        // return gameCode to caller
        return gameCode;
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
