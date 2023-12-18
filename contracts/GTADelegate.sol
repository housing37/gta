// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;        

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
        join -> game, event, activity
    register -> player, delegates, users, participants, entrants
        payout -> winnings, earnings, rewards, recipients 
*/
contract GTADelegate {
    /* -------------------------------------------------------- */
    /* GLOBALS                                                  */
    /* -------------------------------------------------------- */
    /* _ ADMIN SUPPORT _ */
    address private keeper; // 37, curator, manager, caretaker, keeper
    
    /* _ DEX GLOBAL SUPPORT _ */
    address[] public routersUniswapV2; // modifiers: addDexRouter/remDexRouter
    function getSwapRouters() public view onlyKeeper returns (address[] memory) {
        return routersUniswapV2;
    }
    address public constant TOK_WPLS = address(0xA1077a294dDE1B09bB078844df40758a5D0f9a27);
        
    /* _ GAME SUPPORT _ */
    // map generated gameCode address to Game struct
    // mapping(address => Event_0) private activeGames;
    
    // track activeGameCount using 'createGame' & '_endEvent'
    uint64 public activeGameCount = 0; 

    // track activeGameCodes array for keeper 'getGameCodes'
    address[] private activeGameCodes;
    // LEFT OFF HERE ... should be sourced in GTADelegate? (is this even needed anymore)

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
    mapping(address => uint32) public creditsUSD;

    // set by '_updateCredit'; get by 'getCreditAddress|getCredits'
    address[] private creditsAddrArray; 

    // minimum deposits allowed (in usd value)
    //  set constant floor/ceiling so keeper can't lock people out
    uint8 public constant minDepositUSD_floor = 1; // 1 USD 
    uint8 public constant minDepositUSD_ceiling = 100; // 100 USD
    uint8 public minDepositUSD = 0; // dynamic (keeper controlled w/ 'setMinimumUsdValueDeposit')

    // enable/disable refunds for less than min deposit (keeper controlled)
    bool public enableMinDepositRefunds = true;

    // track gas fee wei losses due to min deposit refunds (keeper controlled reset)
    uint256 public accruedGasFeeRefundLoss = 0; 

    // min entryFeeUSD host can create event with (keeper control)
    uint32 public minEventEntryFeeUSD = 0;

    // required GTA balance ratio to host game (ratio of entryFeeUSD desired)
    uint16 public hostGtaBalReqPerc = 100; // uint16 max = 65,535

    // LEFT OFF HERE ... should there be a lower max than 65,535 ?
    //      (that keeper should be limited to send)
    function setHostGtaBalReqPerc(uint16 _perc) public onlyKeeper {
        require(_perc <= type(uint16).max, 'err: required balance too high :/');
        hostGtaBalReqPerc = _perc;
    }

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
    function getGameExpSec() public view onlyKeeper returns (uint32) {
        return gameExpSec;
    }
    function setGameExpSec(uint32 _sec) public onlyKeeper {
        require(_sec > 0, 'err: no zero :{}');
        gameExpSec = _sec;
    }
    function setKeeper(address _newKeeper) public onlyKeeper {
        require(_newKeeper != address(0), 'err: zero address ::)');
        keeper = _newKeeper;
    }
    function setDepositFeePerc(uint8 _perc) public onlyKeeper {
        require(_perc <= 100, 'err: max 100%');
        depositFeePerc = _perc;
    }
    function getLastBlockNumUpdate() public view onlyKeeper returns (uint32) {
        return lastBlockNumUpdate;
    }
    function setLastBlockNumUpdate(uint32 _lastBlockNum) public onlyKeeper {
        if (_lastBlockNum > lastBlockNumUpdate) { lastBlockNumUpdate = lastBlockNumUpdate; }
        // LEFT OFF HERE ... this means keeper can just set last block number to what they want :/
    }
    function setMaxHostFeePerc(uint8 _perc) public onlyKeeper returns (bool) {
        require(_perc <= 100, 'err: max 100%');
        maxHostFeePerc = _perc;
        return true;
    }
    function getCreditAddresses() public view onlyKeeper returns (address[] memory) {
        require(creditsAddrArray.length > 0, 'err: no addresses found with credits :0');
        return creditsAddrArray;
    }
    function getCredits(address _player) public view onlyKeeper returns (uint32) {
        return creditsUSD[_player];
    }
    function setMinimumEventEntryFeeUSD(uint8 _amount) public onlyKeeper {
        require(_amount > minDepositUSD, 'err: amount must be greater than minDepositUSD =)');
        minEventEntryFeeUSD = _amount;
    }
    function addAccruedGFRL(uint256 _gasAmnt) public onlyKeeper returns (uint256) {
        accruedGasFeeRefundLoss += _gasAmnt;
        return accruedGasFeeRefundLoss;
    }
    function getAccruedGFRL() public view onlyKeeper returns (uint256) {
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
    function setMinimumUsdValueDeposit(uint8 _amount) public onlyKeeper {
        require(minDepositUSD_floor <= _amount && _amount <= minDepositUSD_ceiling, 'err: invalid amount =)');
        minDepositUSD = _amount;
    }
    function getWhitelistStables() public view onlyKeeper returns (address[] memory) {
        return whitelistStables;
    }
    function getWhitelistAlts() public view onlyKeeper returns (address[] memory) {
        return whitelistAlts;
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
        return stable_quote >= ((_entryFeeUSD * 10**18) * (hostGtaBalReqPerc/100));
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
    function _getNextStableTokDeposit() public onlyKeeper returns (address) {
        address stable_addr = whitelistStables[whitelistStablesUseIdx];
        whitelistStablesUseIdx++;
        if (whitelistStablesUseIdx >= whitelistStables.length) { whitelistStablesUseIdx=0; }
        return stable_addr;
    }

    // keeper 'SANITY CHECK' for 'settleBalances'
    function _sanityCheck(address token, uint256 amount) public onlyKeeper returns (bool) {
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
    function _best_swap_v2_router_idx_quote(address[] memory path, uint256 amount) public view onlyKeeper returns (uint8, uint256) {
        uint8 currHighIdx = 37;
        uint256 currHigh = 0;
        for (uint8 i = 0; i < routersUniswapV2.length; i++) {
            uint256[] memory amountsOut = IUniswapV2Router02(routersUniswapV2[i]).getAmountsOut(amount, path); // quote swap
            if (amountsOut[amountsOut.length-1] > currHigh) {
                currHigh = amountsOut[amountsOut.length-1];
                currHighIdx = i;
            }
        }

        return (currHighIdx, currHigh);
    }

    // uniwswap v2 protocol based: get quote and execute swap
    function _swap_v2_wrap(address[] memory path, address router, uint256 amntIn) public onlyKeeper returns (uint256) {
        //address[] memory path = [weth, wpls];
        uint256[] memory amountsOut = IUniswapV2Router02(router).getAmountsOut(amntIn, path); // quote swap
        uint256 amntOut = _swap_v2(router, path, amntIn, amountsOut[amountsOut.length -1], false); // execute swap
                
        // verifiy new balance of token received
        uint256 new_bal = IERC20(path[path.length -1]).balanceOf(address(this));
        require(new_bal >= amntOut, "err: balance low :{");
        
        return amntOut;
    }
    
    // v2: solidlycom, kyberswap, pancakeswap, sushiswap, uniswap v2, pulsex v1|v2, 9inch
    function _swap_v2(address router, address[] memory path, uint256 amntIn, uint256 amntOutMin, bool fromETH) private returns (uint256) {
        // emit logRFL(address(this), msg.sender, "logRFL 6a");
        IUniswapV2Router02 swapRouter = IUniswapV2Router02(router);
        
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
