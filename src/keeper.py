from web3 import Web3

# Replace with your Ethereum node URL
ethereum_node_url = 'YOUR_ETHEREUM_NODE_URL'

web3 = Web3(Web3.HTTPProvider(ethereum_node_url))

# Replace with your ERC-20 contract address and ABI
contract_address = 'YOUR_ERC20_CONTRACT_ADDRESS'
contract_abi = [
    {
        "constant": True,
        "inputs": [{"name": "_owner", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "balance", "type": "uint256"}],
        "type": "function",
    }
]

contract = web3.eth.contract(address=contract_address, abi=contract_abi)

# Define the event name and filter parameters
evt_sign = web3.keccak(text="Transfer(address,address,uint256)")
wild_card = None
event_filter = {
    "fromBlock": 0,
    "toBlock": 'latest',
    "address": contract.address,
    "topics": [evt_sign]
}

events = contract.events[event_name]().processReceipt(
    web3.eth.filter(event_filter)
)

for event in events:
    # event Transfer(address sender, address recipient, uint256 amount);
    print("sender (address):", event["args"]["sender"])
    print("recipient (address):", event["args"]["recipient"])
    print("amount (uint256):", event["args"]["amount"])

    # tx meta data
    block = web3.eth.getBlock(event["blockNumber"])
    print("Timestamp:", block["timestamp"])
    print("Transaction Hash:", event["transactionHash"].hex())
    print("Block Number:", event["blockNumber"])
    
    print()
    
    # ... check for "emit Transfer(sender, recipient, amount);"
    # ... call solidity function
