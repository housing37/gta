# product design (GTA = gamer token award)

### maintaining the market
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

