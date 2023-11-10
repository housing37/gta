// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

    //mapping(address => address) public game_to_hosts; // game_code to host_addr
    //mapping(addess => uint256[]) public game_to_fees; // game_code to array [entry_fee, host_fee]
    //mapping(address => address[]) public game_to_players; // game_code to players array
    
    /* ... need to design & store mapping for host created games
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
    // admin support
    address public owner;
    address private keeper; // 37, curator, manager, caretaker, keeper
    
    // token support
    string public override name = "Gamer Token Award";
    string public override symbol = "GTA";
    uint8 public override decimals = 18;
    uint256 public override totalSupply;

    // token support mappings
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // game support
    struct Game {
        string gameName;
        uint256 entryFee;
        uint256 hostFee;
        address[] players;
        uint256 creationDate;
        uint256 startDate;
        uint256 expDate;
    }
    
    // map generated gameCodes (addresses) to Game structs
    mapping(address => Game) public games;
    
    // required GTA balance ratio to host game (ratio of entry_fee desired)
    uint16 public hostRequirementPercent = 100; // max = 65,535 (uint16 max)
    
    // track activeGameCount to loop through 'gameCodes', for cleaning expired 'games'
    uint256 public activeGameCount = 0;

    // track gameCodes, for cleaning expired 'games'
    address[] private gameCodes;
    
    // game experation time _ 1 day = 86400 seconds
    uint64 private gameExpSec = 86400 * 1;
    
    // CONSTRUCTOR
    constructor(uint256 initialSupply) {
        // Set creator to owner & keeper
        owner = msg.sender;
        keeper = msg.sender;
        totalSupply = initialSupply * 10**uint8(decimals);
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
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
        require(bytes(games[gameCode].gameName).length > 0, "err: gameCode not found :(");
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
    
    // GETTERS / SETTERS
    function getHostRequirementForEntryFee(uint256 _entryFee) pure returns (uint256) {
        return _entryFee * (hostRequirementPercent/100);
        // can also just get the public class var directly: 'hostRequirementPercent'
    }
    function getGameCode(address _host, string memory _gameName) public view returns (address) {
        require(_host != address(0x0), "err: no host address :{}"); // verify _host address input
        require(bytes(_gameName).length > 0, "err: no game name :{}"); // verifiy _gameName input
        require(activeGameCount > 0, "err: no games :{}"); // verify there are active games

        // generate gameCode from host address and game name
        address gameCode = generateAddressHash(_host, gameName);
        require(bytes(games[gameCode].gameName).length > 0, "err: game code not found :{}"); // verify gameCode exists
        
        return gameCode;
    }
    function getPlayers(address gameCode) public view validGame(gameCode) returns (address[] memory) {
        return games[gameCode].players;
    }
    
    // max _entryFee, _hostFee = 4,294,967,295 (uint32 max)
    function createGame(string memory _gameName, uint64 _startDate, uint256 _entryFee, uint256 _hostFee) public returns (address) {
        require(_startDate > block.timestamp, "err: start too soon :/");
        require(_entryFee > 0, "err: no entry fee :/");

        uint256 bal = IERC20(address(this)).balanceOf(msg.sender); // returns x10**18
        require(bal >= (_entryFee * (hostRequirementPercent/100)), "err: not enough GTA to host :/");

        address gameCode = generateAddressHash(msg.sender, gameName);
        require(bytes(games[gameCode].gameName).length == 0, "err: game name already exists :/");

        // Creates a default empty 'Game' struct (if doesn't yet exist in 'games' mapping)
        Game storage newGame = games[gameCode];
        //Game storage newGame; // create new default empty struct
        
        // set properties for default empty 'Game' struct
        newGame.gameName = _gameName;
        newGame.entryFee = _entryFee;
        newGame.hostFee = _hostFee;
        newGame.creationDate = block.timestamp;
        newGame.startDate = _startDate;
        newGame.expDate = _startDate + gameExpSec;

        // Assign the newly modified 'Game' struct back to 'games' 'mapping
        games[gameCode] = newGame;
        
        // log new code in gameCodes array, for 'games' supprot in 'cleanExpiredGames'
        gameCodes.push(gameCode);
        
        // increment 'activeGameCount', for 'games' supprot in 'cleanExpiredGames'
        activeGameCount++;
        
        // return gameCode to caller
        return gameCode;
    }
    
    function joinGame(address _gameCode, address _playerAddress) public validGame(_gameCode) {
        require(_playerAddress != address(0x0), "err: no player address :["); // verify _playerAddress input
        address[] playerList = games[gameCode].players;
        for (uint i = 0; i < playerList.length; i++) {
            require(playerList[i] != _playerAddress, "err: player alrady joined game :[");
        }

        // ... LET OFF HERE: player has to pay entry fee somehow
        uint256 gameEntryFee = games[gameCode].entryFee;

        /*
            maintaining value:
            - % of game's prize pool goes back to dex LPs
            - % of game's prize pool goes to buying GTA off the open market (into GTA contract)
            - host wallets must retain a certain amount of GTA in order to create games
                (probably some multiple of the intended player_entry_fee)
        */
        // add player to gameCode mapping
        games[gameCode].gameName.players.push(_playerAddress);
    }
    
    function addPlayer(address gameCode, address playerAddress) public validGame(gameCode) {
        Game storage selectedGame = games[gameCode];
        selectedGame.players.push(playerAddress);
        
        // TOOD: player needs to pay entry fee
    }
    
    function payWinners() {
        /*
            maintaining value:
            - % of game's prize pool goes back to dex LPs
            - % of game's prize pool goes to buying GTA off the open market (into GTA contract)
            - host wallets must retain a certain amount of GTA in order to create games
                (probably some multiple of the intended player_entry_fee)
        */
    }
    
    function generateAddressHash(address host, string memory uid) private pure returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));
        address generatedAddress = address(uint160(uint256(hash)));
        return generatedAddress;
    }
    
    // Delete games w/ an empty players array and expDate has past
    function cleanExpiredGames() public {
        // loop w/ 'activeGameCount' to find game addies w/ empty players array & passed 'expDate'
        for (uint256 i = 0; i < activeGameCount; i++) {
        
            // has the expDate passed?
            if (block.timestamp > games[gameCodes[i]].expDate) {
            
                // is game's players array empty?
                if (games[gameCodes[i]].players.length == 0) {
                    delete games[gameCodes[i]]; // remove gameCode mapping entry
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

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
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
