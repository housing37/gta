// Assume uniswapFactory is a Uniswap V2 Factory contract (chatGPT)

address tokenA = ...; // address of TokenA
address tokenB = ...; // address of TokenB

// Try to create the pair
address pairAddress = uniswapFactory.getPair(tokenA, tokenB);

// If the pair doesn't exist, create it
if (pairAddress == address(0)) {
    uniswapFactory.createPair(tokenA, tokenB);
}
