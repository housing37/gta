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
evt_sign = web3.keccak(text="MyEvent(uint256,address,uint256,uint256,uint256)")
    # event MyEvent(uint256 topic1, address topic2, uint256 value);
wild_card = None
filt_addr = "0x1234567890123456789012345678901234567890"
event_name = 'MyEvent'
event_filter = {
    "fromBlock": 0,
    "toBlock": 'latest',
    "address": contract.address,
    "topics": [evt_sign, # event signature
                wild_card, # wildcare
                filt_addr] # typically sender
}

events = contract.events[event_name]().processReceipt(
    web3.eth.filter(event_filter)
)

for event in events:
    # event MyEvent(uint256 topic1, address topic2, uint256 value, uint256 from, uint256 to);
    print("Topic1 (uint256):", event["args"]["topic1"])
    print("Topic2 (address):", event["args"]["topic1"])
    print("Value (uint256):", event["args"]["value"])
    print("From:", event["args"]["from"]) # sender
    print("To:", event["args"]["to"]) # recipient (contract)

    # tx meta
    block = web3.eth.getBlock(event["blockNumber"])
    print("Timestamp:", block["timestamp"])
    print("Transaction Hash:", event["transactionHash"].hex())
    print("Block Number:", event["blockNumber"])
    
    print()
