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
    address private thirtyseven;
    
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
    mapping(address => Game) public games; // map generated gameCodes (addresses) to Game structs
    address[] public gameCodes; // track gameCodes, for cleaning expired 'games'
    uint256 gameCount = 0; // track gameCount to loop through 'gameCodes', for cleaning expired 'games'
    uint64 private gameExpSec = 86400 * 1; // 1 day = 86400 seconds
    
    constructor(uint256 initialSupply) {
        thirtyseven = msg.sender // contract creator
        owner = msg.sender; // Set the contract creator as the owner
        totalSupply = initialSupply * 10**uint8(decimals);
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner");
        _;
    }
    
    modifier solo_37() {
        require(msg.sender == thirtyseven, "solo treinta y siete");
        _;
    }
    
    modifier validGame(address gameCode) {
        require(bytes(games[gameCode].gameName).length > 0, "err: gameCode not found");
        _;
    }
    
    function createGame(string memory _gameName, uint64 _startDate, uint256 _entryFee, uint256 _hostFee) public returns (address) {
        require(startDate > block.timestamp, "err: must start later :/");
        require(entryFee > 0, "err: no entry fee :/");

        address gameCode = generateAddressHash(msg.sender, gameName);
        require(bytes(games[gameCode].gameName).length == 0, "err: game name already exists :/");
        
        // Creates a default empty 'Game' struct (if doesn't yet exist in 'games' mapping)
        Game storage newGame = games[gameCode];
        //Game storage newGame; // create new default empty struct
        
        // set properties for default empty 'Game' struct
        newGame.gameName = _gameName;
        newGame.entryFee = _entryFee * 10**uint8(decimals);
        newGame.hostFee = _hostFee * 10**uint8(decimals);
        newGame.creationDate = block.timestamp;
        newGame.startDate = _startDate;
        newGame.expDate = _startDate + gameExpSec;

        // Assign the newly modified 'Game' struct back to 'games' 'mapping
        games[gameCode] = newGame;
        
        // log new code in gameCodes array, for 'games' supprot in 'cleanExpiredGames'
        gameCodes.push(gameCode);
        
        // increment 'gameCount', for 'games' supprot in 'cleanExpiredGames'
        gameCount++;
        
        // return gameCode to caller
        return gameCode;
    }
    
    function getGameCode(address _host, string memory _gameName) view returns (address) {
        require(_host != address(0x0), "err: no host address :{}");
        require(bytes(_gameName).length > 0, "err: no game name :{}");
        require(gameCount > 0, "err: no games :{}");

        address gameCode = generateAddressHash(_host, gameName);
        require(bytes(games[gameCode].gameName).length > 0, "err: game code not found :{}");
        
        return gameCode;
    }
    function addPlayer(address gameCode, address playerAddress) public validGame(gameCode) {
        Game storage selectedGame = games[gameCode];
        selectedGame.players.push(playerAddress);
        
        // TOOD: player needs to pay entry fee
    }

    function getPlayers(address gameCode) public view validGame(gameCode) returns (address[] memory) {
        return games[gameCode].players;
    }
    
    function generateAddressHash(address host, string memory uid) private pure returns (address) {
        // Concatenate the address and the string, and then hash the result
        bytes32 hash = keccak256(abi.encodePacked(host, uid));
        address generatedAddress = address(uint160(uint256(hash)));
        return generatedAddress;
    }
    
    // Delete games w/ an empty players array and expDate has past
    function cleanExpiredGames() public {
        // loop w/ 'gameCount' to find game addies w/ empty players array & passed 'expDate'
        for (uint256 i = 0; i < gameCount; i++) {
        
            // has the expDate passed?
            if (block.timestamp > games[gameCodes[i]].expDate) {
            
                // is game's players array empty?
                if (games[gameCodes[i]].players.length == 0) {
                    delete games[gameCodes[i]]; // remove gameCode mapping entry
                    delete gameCodes[i]; // remove gameCodes array entry
                    gameCount--; // decrement total game count
                }
            }
        }
    }
    
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
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] - subtractedValue);
        return true;
    }

    function mint(address account, uint256 amount) public onlyOwner {
        require(account != address(0), "ERC20: mint to the zero address");
        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
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
        owner = newOwner; // Transfer ownership to a new address
    }
}
