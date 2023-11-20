# product design (GTA = gamer token award)

## GTA.sol finalized design & integration ##
    - current integration
        - host calls 'createEvent(entry_fee)'; generates event_code; holding GTA required (ratio of entry_fee)
        - players (entrants/delegates) call 'transfer' (w/ whitelistedStables|Alts) for deposits to GTA contract (for entry_fees)
        - players (entrants/delegates) call 'registerEvent(event_code)' to use credits & register for event_code
        - host can call 'hostRegisterEventClaim(player, event_code)' to freely register players w/ enough credits
        - host calls 'hostStartEvent(event_code)' to launch the event (set 'launched' in struct)
        - host calls 'hostEndEventWithWinners(event_code, winners)', validates and pays out winners in stables

    - remaining integrations
        - host chooses service-fee discount if paid in GTA
            1) buy & burn|hold integration
            2) host & winners get minted some amount after event ends
                *required: mint amount < buy & burn amount

    - hanging blockers / tasks / edge-cases to solve
        - hostRegisterEventClaim: someone could listen for 'Transfer' events to GTA contract
            and then use 'hostRegisterEventClaim' to immediately take the credits
        - creditUpdates: verify that keeper cannot lie when calling 'creditUpdates' (deposits)

## edage case use cases
    - payment processing

### end-to-end walkthrough
    - host creates game (entryFeeUSD, payoutPercents) _ requires % GTA in wallet 
        receives game_code
    - host provides game_code to potential players
    - players pay entryFeeUSD
        players send choice alt token to GTA contract address (equal to entryFeeUSD value)
        GTA contract logs this in "mapping(address => uint256) private _creditsUSD"
            python listens for transfer events involving GTA contract address
            python calls 'logTransferToGTA(address token, address from, uint256 amnt)'
                - problem: python could lie about observing the event
            
    - players notify host of address used to pay entryFeeUSD
    - host starts game with addresses received
        contract: startGame(address gameCode, address[] playersClaimPaid)
    
### maintaining the market
    current option (team):
        With the following model, we have a way of adding tokens to the market and removing tokens from the market… 
        I believe this creates an open market, while not flooding the market, and maintains more buy pressure than sell pressure
        I believe this also allows us to actually make money, even if the token doesn’t perform (because we are providing a service)

        1) remove GTA from the market: 
        - host can choose to pay service fee in GTA for a discount (we buy and burn)
        - host required to hold some GTA in order to host 

        2) add GTA to the market: 
        - host gets minted some amount for hosting games
        - player gets minted some amount for winning games 

        #2 always has to be less than #1 for every hosted event 
        - the value of amounts minted must always be less than the service fee

    gabe notes (call):
        - cannot take player deposits and add to GTA LPs for winners to cashout immediately
            this is because arb bots will grab that added value before winners do
         	this means winners cannot be paid in GTA
        - deposits should be held in escrow by the contract
            contract converts all deposits to stable coins for holding
            player usd balances tracked in 'mapping(address => uint256) private creditsUSD;'  

    rabbit_notes (TG):
        "if you charge 5% and add it to the lp, then you are making that charge a common value for everyone to invest in."
        "- when chart is high acquiring new users becomes more costly. when less users its cheap and attractive to use."
        "requiring people to hold some gta to host a game (alone without a fee) plays the role of delaying sell pressure giving a temporary poisitve above zero chart"
        "you have to give people something, and the token something"
        "you have hosts and joiners
            hosts assumes they know a little more than joiners.
            thus they need to be empowered somehow to get that social network effect going to get the wheel to turn"
            
        So your suggesting…
        1) The hosts need to hold in order to host
        2) a % of each prize pool goes to LP on the dexes
        3) we do not take any fee ourselves at all

        another buy pressure you are adding with the %to pool is: 
            as a host it is smart for me to buy and hodl gta if i intend to play a lot games or bet higher in the future.
            if the amount of gta is a % of the bid deposit then it is more expensive in the future when the chart keeps accumulating. 
            and this very speculation can drive the market otherwise you have a systemic chart with a zero range or at best a delayed sell pressure with a basic hold x amount of gta to use the contract.
    
    maintaining value:
        - % of game's prize pool goes back to dex LPs
        - % of game's prize pool goes to buying GTA off the open market (into GTA contract)
        - host wallets must retain a certain amount of GTA in order to create games
            (probably some multiple of the intended player_entry_fee) 
            
    providing value
    
    1) when we launch the contract, we also create the intial liquidity pools on the dexes (pulseX, 9inch, uniswap, etc.)
        NOTE: we don't need to put up a lot of money at all to start, 
                because liquidity will be added from each game's 'prize_pool'
                 (i'm thinking less than $100, i'll front this money)
        
    2) Q: whats the initial token price?
        A: i don't know, what do you think? rabbit?
            
    3) Q: can winners cash out right away
        A: yes, they can take their wallet and go to any dex and get PLS (or whatever)
        NOTE: the price won't drop because the exact value from the 'prize_pool' will be added to the dexes
            rabbit: please confirm this logic
            
    4) Q: can a malicious host create fake games and fake players?
        A: yes, but they will simply be winning their own money back (and losing gas fees)
        NOTE: the price can't drop when they do this, because their 'entry_fees' will be added to the dexes to cover the sales
            rabbit: please confirm this logic
    
### use case:
    1) someone in the world wants to play a game (any game in the world) and let people win real money from it
        - he is called the 'host'
        
    2) the host picks any game in the world
        - lets use call of duty (COD) as an example, which is a first person shooter game
        
    3) the host initializes the 'game' 
        - 1) creates a game on the COD platform (has nothing to do with our smart contract)
        - 2) creates a 'game' on our smart contract (our contract is an ERC20 token based smart contract and is called "GTA" = Gamer Token Award)
                - when creating the game...
                    the host sets an 'entry_fee' for each player (required)
                    the host sets a 'start_date_time' for the game to start (required)
                    the host may also choose to set a 'host_fee' for being the 'host' (optional)
                        (the host_fee could generally be a percentage of the total 'entry_fees' collected)
                - after creating the game, the host will get a 'game_code' to give to other players he wants to invite
                
    4) the host invites other people to the game
        - 1) host gives people the 'game_code' to use with our GTA smart contract
        - 2) host gives people a link to the actual game to join (on the COD platform or whatever, nothing to do with our GTA contract)
        
    5) players accept invite and join the game
        - 1) players join the GTA contract game, using the 'game_code' they received
                and at this time, they must send their 'entry_fee' to the GTA contract as well
                all the 'entry_fees' received by the contract for this 'game_code', will generate the 'prize_pool'
                NOTE: if the 'host' actually wants to play the game and have a chance at winning the 'prize_pool'
                        then he must also 'join the game' like any other normal 'player'
        - 2) players join the actual COD game on the COD platform or whatever (nothing to do with our GTA smart contract)
        
    6) players play the game
        - players then play the game like normal, on the COD platform (nothing to do with our GTA smart contract)
        
    7) paying out winners
        - 1) host records the winners of the game
        - 2) host uses the GTA contract w/ the 'game_code' to select the winners
        - 3) the GTA contract then automatically pays the winners
        NOTE_1: if the host doesn't select winners after a certain amount of time
                	then all 'entry_fees' are automatically returned to the players
        NOTE_2: if the host lies about who are the winners, then those winners will never play that host's games again
                    (capitalism at its finest)

