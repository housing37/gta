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
    
    // PulseXRouter02 'v1' ref: https://www.irccloud.com/pastebin/6ftmqWuk
    address private constant ROUTER_pulsex_v1 = address(0x98bf93ebf5c380C0e6Ae8e192A7e2AE08edAcc02);
    
    // PulseXRouter02 'v2' ref: https://www.irccloud.com/pastebin/6ftmqWuk
    address private constant ROUTER_pulsex_v2 = address(0x165C3410fC91EF562C50559f7d2289fEbed552d9);
    
    // PulseXSwapRouter 'v1' ref: MM tx
    address private constant ROUTER_pulsex_vX = address(0xa619F23c632CA9f36CD4Dcea6272E1eA174aAC27);
    
    // array of all dex routers to check for 'getDexQuoteUSD'
    address[] storage private routersUniswapV2 = [ROUTER_pulsex_v1, ROUTER_pulsex_v2, ROUTER_pulsex_vX];
        
    /* _ GAME SUPPORT _ */
    struct Game {
        string gameName;
        uint256 entryFeeUSD;
        uint256 hostFee;
        address[] players;
        uint256 creationDate;
        uint256 startDate;
        uint256 expDate;
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
    
    // maintain whitelist tokens that can be used for deposit
    mapping(address => bool) public depositTokens;
    
    // usd credits for players to pay entryFeeUSD to join games
    mapping(address => uint256) private creditsUSD;

    // maintain local mapping of this contracts ERC20 token balances
    mapping(address => uint256) private gtaAltBalances;
    uint256 private gtaAltBalsLastBlockNum = 0;
    
    // CONSTRUCTOR
    constructor(uint256 initialSupply) {
        // Set creator to owner & keeper
        owner = msg.sender;
        keeper = msg.sender;
        totalSupply = initialSupply * 10**uint8(decimals);
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function getLastBlockNumUpdate() public view onlyKeeper {
        return gtaAltBalsLastBlockNum;
    }

    // LEFT OFF HERE... 
    //  ready to pass data from 'Transfer' event logs on python side
    //      - need to update mapping for player usd credits
    //      - may need to maintain mapping of GTA contract alt coin balances
    //          or maybe just swap for usd stables immediately (i forgot)
    //  should only pass the bare-min data needed
    //  should probably use pyton side to calc USD credit vals for alt coin transfers
    //      however, we need to actually make the swaps on chain
    //       note: need to keep track of all 'expenses' and deduct from usd credit balances
    //          ie. gas fees, dex swap fees, etc.
    struct InnerStruct {
        uint256 k1;
        uint256 k2;
        // Add more nested values as needed
    }
    struct MyStruct {
        uint256 key;
        InnerStruct[] innerStructs;
    }
    function myMethod(MyStruct[] memory dataArray) public {
        for (uint256 i = 0; i < dataArray.length; i++) {
            uint256 key = dataArray[i].key;
            InnerStruct[] memory innerStructs = dataArray[i].innerStructs;

            for (uint256 j = 0; j < innerStructs.length; j++) {
                uint256 k1 = innerStructs[j].k1;
                uint256 k2 = innerStructs[j].k2;

                // Perform operations with k1, k2
                // ...

                // Do something with the data
            }
        }
    }

    function logCredit(address _player, address _token, uint256 _amount, uint256 lastBlock) public onlyKeeper {
        uint256 prev_bal = gtaAltBalances[_token];
        uint256 new_bal = IERC20(_token).balanceOf(address(this));
        required(new_bal > prev_bal, "err: token bal mismatch");
            // 'logCredit' gets called after ever time a token transfer to this contract occurs
            // hence, if new_bal < prev_bal
            //  then that means this contract spent some _token
            //  after a token transfer occurred (mined)
            //   and before this 'logCredit' was called
            
            // LEFT OFF HERE... is this correct? ^
            
        //gtaAltBalances[_token] += _amount;
        gtaAltBalances[_token] = new_bal;
        
        // LEFT OFF HERE... does this logic work? ^
        
        amountUSD = getDexQuoteUSD(_token, _amount);
        creditsUSD[_player] += amountUSD;
    }
    
    //address[] memory thisContractTransfer;
    struct PaidEntries {
        address[] gameCode;
        uint256[] ammount;
    }
    struct PaidEntry {
        address gameCode;
        uint256 ammount;
    }
    
    // one player address can have many PaidEntries
    //mapping(address => PaidEntries[]) memory playerEntries;
    mapping(address => PaidEntry[]) memory playerEntries;
    
    function findGameCode(PaidEntry[] memory entries, address _gameCode) private pure returns (bool) {
        for (uint i; i < entries.length; i++) {
            PaidEntry memory entry = entries[i];
            if (entry.gameCode == _gameCode) {
                // player has already paid for this gameCode
                return true;
            }
        }
        return false;
    }
    
    function joinGame(address _gameCode, address _playerAddress) public validGame(_gameCode) {
        require(_playerAddress != address(0x0), "err: no player address :["); // verify _playerAddress input
        address[] playerList = activeGames[gameCode].players;
        for (uint i = 0; i < playerList.length; i++) {
            require(playerList[i] != _playerAddress, "err: player already joined game :[");
        }

        // ... LET OFF HERE: player has to pay entry fee somehow
        uint256 gameEntryFee = activeGames[gameCode].entryFeeUSD;
        
        // ... left off here...
        //  want to keep track of all balances that players send to this contract
        //   but players can pay entry fee in any token they want (respectful approved list)
        
        
        // need to check if msg.sender has paid for this gameCode
        PaidEntry[] memory entries = playerEntries[msg.sender];
        bool playerJoined = findGameCode(entries, _gameCode);
        
        bool playerPaid = findGameCode(entries, _gameCode);
        require(playerPaid, "err: play")
        //bool playerPaid = False;
        
        for (uint i; i < entries.length; i++) {
            PaidEntry memory entry = entries[i];
            if (entry.gameCode == _gameCode) {
                // player has already paid for this gameCode
                playerPaid = true;
                break;
            }
            newEntry.amount =
        }
        
        
        /*
            maintaining value:
            - % of game's prize pool goes back to dex LPs
            - % of game's prize pool goes to buying GTA off the open market (into GTA contract)
            - host wallets must retain a certain amount of GTA in order to create activeGames
                (probably some multiple of the intended player_entry_fee)
        */
        // add player to gameCode mapping
        activeGames[gameCode].gameName.players.push(_playerAddress);
    }
    
    function addPlayer(address gameCode, address playerAddress) public validGame(gameCode) {
        Game storage selectedGame = activeGames[gameCode];
        selectedGame.players.push(playerAddress);
        
        // TOOD: player needs to pay entry fee
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
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner :0");
        _;
    }
    
    modifier onlyKeeper() {
        require(msg.sender == keeper, "Only the keeper :p");
        _;
    }
    
    modifier validGame(address gameCode) {
        require(bytes(activeGames[gameCode].gameName).length > 0, "err: gameCode not found :(");
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
    function getHostRequirementForEntryFee(uint256 _entryFeeUSD) pure returns (uint256) {
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
    function getPlayers(address gameCode) public view validGame(gameCode) returns (address[] memory) {
        return activeGames[gameCode].players;
    }
    
    function createGame(string memory _gameName, uint64 _startDate, uint256 _entryFeeUSD, uint256 _hostFee) public returns (address) {
        require(_startDate > block.timestamp, "err: start too soon :/");
        require(_entryFeeUSD >= 1, "required: entry fee >= 1 USD :/");
        
        uint256 bal = IERC20(address(this)).balanceOf(msg.sender); // returns x10**18
        require(bal >= (_entryFeeUSD * (hostRequirementPercent/100)), "err: not enough GTA to host :/");

        address gameCode = generateAddressHash(msg.sender, gameName);
        require(bytes(activeGames[gameCode].gameName).length == 0, "err: game name already exists :/");

        // Creates a default empty 'Game' struct (if doesn't yet exist in 'activeGames' mapping)
        Game storage newGame = activeGames[gameCode];
        //Game storage newGame; // create new default empty struct
        
        // set properties for default empty 'Game' struct
        newGame.gameName = _gameName;
        newGame.entryFeeUSD = _entryFeeUSD;
        newGame.hostFee = _hostFee;
        newGame.creationDate = block.timestamp;
        newGame.startDate = _startDate;
        newGame.expDate = _startDate + gameExpSec;

        // Assign the newly modified 'Game' struct back to 'activeGames' 'mapping
        activeGames[gameCode] = newGame;
        
        // log new code in gameCodes array, for 'activeGames' supprot in 'cleanExpiredGames'
        gameCodes.push(gameCode);
        
        // increment 'activeGameCount', for 'activeGames' supprot in 'cleanExpiredGames'
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
    
    // Delete activeGames w/ an empty players array and expDate has past
    function cleanExpiredGames() public {
        // loop w/ 'activeGameCount' to find game addies w/ empty players array & passed 'expDate'
        for (uint256 i = 0; i < activeGameCount; i++) {
        
            // has the expDate passed?
            if (block.timestamp > activeGames[gameCodes[i]].expDate) {
            
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
