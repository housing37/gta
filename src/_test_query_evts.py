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

# set from|to block numbers
from_block = start_block_num # int | w3.eth.block_number
to_block = 'latest' # int | 'latest'
str_from_to = f'from_block: {from_block} _ to_block: {to_block}'

# fetch transfer events w/ simple fromBlock/toBlock
str_evt = 'Transfer(address,address,uint256)'
print(f"\nGETTING EVENT LOGS: '{str_evt}' _ {get_time_now()}\n ... {str_from_to}")
events = contract.events.Transfer().get_logs(fromBlock=from_block, toBlock=to_block) # toBlock='latest' (default)

# ## ALTERNATE _ for getting events with 'create_filter' (not working _ 111623)
# args = {'dst':'0x7b1C460d0Ad91c8A453B7b0DBc0Ae4F300423FFB'} # 'src', 'dst', 'wad'
# # event_filter = contract.events.Transfer().create_filter(fromBlock=from_block, toBlock=to_block, argument_filters=args)
# event_filter = contract.events['Transfer'].create_filter(fromBlock=from_block, toBlock=to_block, argument_filters=args)
# events = event_filter.get_new_entries()

# ## ALTERNATE _ for getting events with 'topics'
# #   note: still have to filter manually for 'src,dst,wad'
# transfer_event_signature = w3.keccak(text='Transfer(address,address,uint256)').hex()
# filter_params = {'fromBlock':from_block, 'toBlock':to_block, 
#                     'address':contract.address, # defaults to conract.address
#                     'topics': [transfer_event_signature, # event signature
#                                 None, # 'from' (not included with 'Transfer' event)
#                                 None], # 'to' (not included with 'Transfer' event)
# }
# events = w3.eth.get_logs(filter_params)

# NOTE_111623: prints aren't correct (in fact this entire file is un-tested, review keeper.py)
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
