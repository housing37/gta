// SPDX-License-Identifier: UNLICENSED
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
                 join -> room, game, event, activity
             register -> seat, player, delegates, users, participants, entrants
    payout/distribute -> rewards, winnings, earnings, recipients 
*/
contract GTADelegate {
    /* -------------------------------------------------------- */
    /* GLOBALS                                                  */
    /* -------------------------------------------------------- */
    /* _ ADMIN SUPPORT _ */
    address private keeper; // 37, curator, manager, caretaker, keeper
    
    /* _ DEX GLOBAL SUPPORT _ */
    address[] public uswapV2routers; // modifiers: addDexRouter/remDexRouter
    function getSwapRouters() external view onlyKeeper returns (address[] memory) {
        return uswapV2routers;
    }
    address public constant TOK_WPLS = address(0xA1077a294dDE1B09bB078844df40758a5D0f9a27);
        
    /* _ TOKEN SUPPORT _ */
    // arrays of accepted usd stable & alts for player deposits
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
    uint8 public constant minDepositUSD_floor = 1; // 1 USD 
    uint8 public constant minDepositUSD_ceiling = 100; // 100 USD
    uint8 public minDepositUSD = 0; // dynamic (keeper controlled w/ 'setMinimumUsdValueDeposit')

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

    /* -------------------------------------------------------- */
    /* PUBLIC ACCESSORS                                         */
    /* -------------------------------------------------------- */
    function getWhitelistStables() external view returns (address[] memory) {
        return whitelistStables;
    }
    function getWhitelistAlts() external view returns (address[] memory) {
        return whitelistAlts;
    }

    /* -------------------------------------------------------- */
    /* KEEPER - PUBLIC GETTERS / SETTERS                        */
    /* -------------------------------------------------------- */
    // GETTERS / SETTERS (keeper)
    function getKeeper() external view returns (address) {
        return keeper;
    }
    function setKeeper(address _newKeeper) external onlyKeeper {
        require(_newKeeper != address(0), 'err: zero address ::)');
        keeper = _newKeeper;
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
    function setMinimumEventEntryFeeUSD(uint8 _amount) public onlyKeeper {
        require(_amount > minDepositUSD, 'err: amount must be greater than minDepositUSD =)');
        minEventEntryFeeUSD = _amount;
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
    // LEFT OFF HERE ... maybe this function just be a public tool, and not onlyKeeper
    function swap_v2_wrap(address[] memory path, address router, uint256 amntIn) external onlyKeeper returns (uint256) {
        require(path.length > 1, 'err: bad path, need >= 2 addies :)');
        require(router != address(0), 'err: zero address? :0');
        require(amntIn > 0, 'err: no amount? :{}' );
        return _swap_v2_wrap(path, router, amntIn, msg.sender);
    }
    function best_swap_v2_router_idx_quote(address[] memory path, uint256 amount) external view onlyKeeper returns (uint8, uint256) {
        require(path.length > 1, 'err: bad path, need >= 2 addies :)');
        require(amount > 0, 'err: no amount? :{}' );
        return _best_swap_v2_router_idx_quote(path, amount);
    }
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
    function _hostCanCreateEvent(address _host, address _tok_gta, uint32 _entryFeeUSD) external view returns (bool) {
        // get best stable quote for host's gta_bal (traverses 'uswapV2routers')
        uint256 gta_bal = IERC20(address(this)).balanceOf(_host); // returns x10**18
        address[] memory gta_stab_path = new address[](2);
        gta_stab_path[0] = _tok_gta;
        gta_stab_path[1] = _getStableTokenHighMarketValue(whitelistStables);
        (uint8 rtrIdx, uint256 stable_quote) = _best_swap_v2_router_idx_quote(gta_stab_path, gta_bal);
        return stable_quote >= ((_entryFeeUSD * 10**18) * (hostGtaBalReqPerc/100));
    }
    function gtaHoldingRequiredToHost(address _tok_gta, uint32 _entryFeeUSD) external view returns (uint256) {
        require(_entryFeeUSD > 0, 'err: _entryFeeUSD is 0 :/');
        require(_tok_gta != address(0), 'err: _tok_gta address is 0 :/');
        address[] memory stab_gta_path = new address[](2);
        stab_gta_path[0] = _getStableTokenHighMarketValue(whitelistStables);
        stab_gta_path[1] = _tok_gta;
        (uint8 rtrIdx, uint256 gta_quote) = _best_swap_v2_router_idx_quote(stab_gta_path, (_entryFeeUSD * 10**18) * (hostGtaBalReqPerc/100));
        return gta_quote;
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
    // swap 'buyAndBurnUSD' amount of best market stable, for GTA (traverses 'uswapV2routers')
    function _processBuyAndBurnStableSwap(address stable, uint32 _buyAndBurnUSD, address _gtaContract) external onlyKeeper returns (uint256) {
        address[] memory stab_gta_path = new address[](2);
        stab_gta_path[0] = stable;
        stab_gta_path[1] = address(this);
        (uint8 rtrIdx, uint256 gta_amnt) = _best_swap_v2_router_idx_quote(stab_gta_path, _buyAndBurnUSD * 10**18);
        uint256 gta_amnt_out = _swap_v2_wrap(stab_gta_path, uswapV2routers[rtrIdx], _buyAndBurnUSD * 10**18, _gtaContract);
        return gta_amnt_out;

        // LEFT OFF HERE ... can't use address(this) here, or inside '_swap_v2_wrap'
        //      'this' is GTADelegate, not GTA token contract
        //      need to pass GTA contract address and use for swap, or something like that
        //      GTA contract address needs to end up with 'gta_amnt_out'
    }

    // get lowest market value stable
    function _getBestDebitStableUSD(uint32 _amountUSD) external view onlyKeeper returns (address) {
        // loop through 'whitelistStables', generate stables available (bals ok for debit)
        address[] memory stables_avail = _getStableTokensAvailDebit(_amountUSD);

        // traverse stables available for debit, select stable w/ the lowest market value            
        address stable = _getStableTokenLowMarketValue(stables_avail);
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

    // keeper 'SANITY CHECK' for 'settleBalances'
    function _sanityCheck(address token, uint256 amount) external onlyKeeper returns (bool) {
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
    function _increaseWhitelistPendingDebit(address token, uint256 amount) external onlyKeeper {
        whitelistPendingDebits[token] += amount;
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

    // NOTE: *WARNING* _stables could have duplicates (from 'whitelistStables' set by keeper)
    function _getStableTokenLowMarketValue(address[] memory _stables) private view returns (address) {
        // traverse _stables & select stable w/ the lowest market value
        uint256 curr_high_tok_val = 0;
        address curr_low_val_stable = address(0x0);
        for (uint i=0; i < _stables.length; i++) {
            address stable_addr = _stables[i];
            if (stable_addr == address(0)) { continue; }

            // get quote for this stable (traverses 'uswapV2routers')
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

    // NOTE: *WARNING* _stables could have duplicates (from 'whitelistStables' set by keeper)
    function _getStableTokenHighMarketValue(address[] memory _stables) private view returns (address) {
        // traverse _stables & select stable w/ the highest market value
        uint256 curr_low_tok_val = 0;
        address curr_high_val_stable = address(0x0);
        for (uint i=0; i < _stables.length; i++) {
            address stable_addr = _stables[i];
            if (stable_addr == address(0)) { continue; }

            // get quote for this stable (traverses 'uswapV2routers')
            //  looking for the stable that returns the least when swapped 'from' WPLS
            //  the less USD stable received for 1 WPLS ~= the more overall market value that stable has
            address[] memory wpls_stab_path = new address[](2);
            wpls_stab_path[0] = TOK_WPLS;
            wpls_stab_path[1] = stable_addr;
            (uint8 rtrIdx, uint256 tok_val) = _best_swap_v2_router_idx_quote(wpls_stab_path, 1 * 10**18);
            if (tok_val >= curr_low_tok_val) {
                curr_low_tok_val = tok_val;
                curr_high_val_stable = stable_addr;
            }
        }
        return curr_high_val_stable;
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

    // uniswap v2 protocol based: get router w/ best quote in 'uswapV2routers'
    function _best_swap_v2_router_idx_quote(address[] memory path, uint256 amount) private view returns (uint8, uint256) {
        uint8 currHighIdx = 37;
        uint256 currHigh = 0;
        for (uint8 i = 0; i < uswapV2routers.length; i++) {
            uint256[] memory amountsOut = IUniswapV2Router02(uswapV2routers[i]).getAmountsOut(amount, path); // quote swap
            if (amountsOut[amountsOut.length-1] > currHigh) {
                currHigh = amountsOut[amountsOut.length-1];
                currHighIdx = i;
            }
        }

        return (currHighIdx, currHigh);
    }

    // uniwswap v2 protocol based: get quote and execute swap
    function _swap_v2_wrap(address[] memory path, address router, uint256 amntIn, address outReceiver) private returns (uint256) {
        require(path.length >= 2, 'err: path.length :/');
        uint256[] memory amountsOut = IUniswapV2Router02(router).getAmountsOut(amntIn, path); // quote swap
        uint256 amntOut = _swap_v2(router, path, amntIn, amountsOut[amountsOut.length -1], outReceiver, false); // approve & execute swap
                
        // verifiy new balance of token received
        uint256 new_bal = IERC20(path[path.length -1]).balanceOf(address(this));
        require(new_bal >= amntOut, "err: balance low :{");
        
        return amntOut;
    }
    
    // v2: solidlycom, kyberswap, pancakeswap, sushiswap, uniswap v2, pulsex v1|v2, 9inch
    function _swap_v2(address router, address[] memory path, uint256 amntIn, uint256 amntOutMin, address outReceiver, bool fromETH) private returns (uint256) {
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
                            outReceiver, // to
                            deadline
                        );
        } else {
            amntOut = swapRouter.swapExactTokensForTokens(
                            amntIn,
                            amntOutMin,
                            path, //address[] calldata path,
                            outReceiver, //  The address that will receive the output tokens after the swap. 
                            deadline
                        );
        }
        // emit logRFL(address(this), msg.sender, "logRFL 6d");
        return uint256(amntOut[amntOut.length - 1]); // idx 0=path[0].amntOut, 1=path[1].amntOut, etc.
    }
}
