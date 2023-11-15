__fname = '_web3'
__filename = __fname + '.py'
cStrDivider = '#================================================================#'
print('', cStrDivider, f'GO _ {__filename} -> starting IMPORTs & declaring globals', cStrDivider, sep='\n')
cStrDivider_1 = '#----------------------------------------------------------------#'

from web3 import Account, Web3, HTTPProvider
#import web3
import env
#------------------------------------------------------------#
def inp_sel_chain():
    sel_chain = input('\nSelect chain:\n  0 = ethereum mainnet\n  1 = pulsechain mainnet\n  > ')
    assert 0 <= int(sel_chain) <= 1, 'Invalid entry, abort'
    (RPC_URL, CHAIN_ID) = (env.eth_main, env.eth_main_cid) if int(sel_chain) == 0 else (env.pc_main, env.pc_main_cid)
    print(f'  selected {(RPC_URL, CHAIN_ID)}')
    return RPC_URL, CHAIN_ID, sel_chain
#------------------------------------------------------------#
def inp_sel_sender():
    sel_send = input(f'\nSelect sender: (_event_listener: n/a)\n  0 = {env.sender_address_3}\n  1 = {env.sender_address_1}\n  > ')
    assert 0 <= int(sel_send) <= 1, 'Invalid entry, abort'
    (SENDER_ADDRESS, SENDER_SECRET) = (env.sender_address_3, env.sender_secret_3) if int(sel_send) == 0 else (env.sender_address_1, env.sender_secret_1)
    print(f'  selected {SENDER_ADDRESS}')
    return SENDER_ADDRESS, SENDER_SECRET
#------------------------------------------------------------#
def inp_sel_contract(LST_CONTR_ADDR=[]):
    print(f'\nSelect arbitrage contract to use:')
    for i, v in enumerate(LST_CONTR_ADDR): print(' ',i, '=', v)
    idx = input('  > ')
    assert 0 <= int(idx) < len(LST_CONTR_ADDR), 'Invalid input, aborting...\n'
    CONTR_ADDR = str(LST_CONTR_ADDR[int(idx)])
    print(f'  selected {CONTR_ADDR}')
    return CONTR_ADDR
#------------------------------------------------------------#
def init_web3(RPC_URL, CHAIN_ID, SENDER_ADDRESS, SENDER_SECRET, CONTR_ADDR='nil_contract'):
    print(f'''\nINITIALIZING web3 ...
        RPC: {RPC_URL}
        ChainID: {CHAIN_ID}
        SENDER: {SENDER_ADDRESS}
        CONTRACT: {CONTR_ADDR}''')
        
    ## CLIENT SIDE TIMEOUT RESULTS
    # RAISES: requests.exceptions.ReadTimeout: HTTPSConnectionPool(host='rpc.pulsechain.com', port=443): Read timed out. (read timeout=X)
    # W3 = Web3(HTTPProvider(RPC_URL)) # 50sec timeout logged _ defaults to 'timeout': 10
    # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 10})) # 50sec timeout logged
    # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 30})) # 150sec (2.5min) timeout logged
    # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 45})) # 225sec (3.75min) timeout logged
    W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 60})) # 5min timeout logged

    ## SERVER SIDE TIMEOUT RESULTS
    # RAISES: 504 Server Error: Gateway Time-out
    # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 65})) # 5min timeout logged
    # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 90})) # 5min timeout logged
    # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 120})) # 5min timeout logged

    # W3 = Web3(Web3.HTTPProvider(endpoint_uri=RPC_URL, request_kwargs={'timeout': 70}))
    ACCOUNT = Account.from_key(SENDER_SECRET) # default
    return W3, ACCOUNT
#------------------------------------------------------------#
def read_abi_bytecode(abi_file, bin_file):
    print(f'\nreading contract abi & bytecode files ...\n   {abi_file, bin_file}')
    with open(bin_file, "r") as file: CONTR_BYTES = '0x'+file.read()
    with open(abi_file, "r") as file: CONTR_ABI = file.read()
    return CONTR_ABI, CONTR_BYTES
#------------------------------------------------------------#
def init_contract(CONTR_ADDR, CONTR_ABI, W3:Web3):
    print(f'\ninitializing contract {CONTR_ADDR} ...')
    CONTR_ADDR = W3.to_checksum_address(CONTR_ADDR) # convert something ?
    CONTRACT = W3.eth.contract(address=CONTR_ADDR, abi=CONTR_ABI)
    return CONTRACT
#------------------------------------------------------------#
def get_gas_settings(sel_chain, W3:Web3):
    print('calc gas settings...')
    if int(sel_chain) == 0:
        # ethereum main net (update_102923)
        GAS_LIMIT = 3_000_000# max gas units to use for tx (required)
        GAS_PRICE = W3.to_wei('10', 'gwei') # price to pay for each unit of gas (optional?)
        MAX_FEE = W3.to_wei('14', 'gwei') # max fee per gas unit to pay (optional?)
        MAX_PRIOR_FEE_RATIO = 1.0 # W3.eth.max_priority_fee * mpf_ratio # max fee per gas unit to pay for priority (faster) (optional)
        MAX_PRIOR_FEE = int(W3.eth.max_priority_fee * MAX_PRIOR_FEE_RATIO) # max fee per gas unit to pay for priority (faster) (optional)
    else:
        # pulsechain main net (update_103123)
        GAS_LIMIT = 20_000_000 # max gas units to use for tx (required)
        GAS_PRICE = W3.to_wei('0.0005', 'ether') # price to pay for each unit of gas ('gasPrice' param fails on PC)
        MAX_FEE = W3.to_wei('0.001', 'ether') # max fee per gas unit to pay (optional?)
        MAX_PRIOR_FEE_RATIO = 1.0
        MAX_PRIOR_FEE = int(W3.eth.max_priority_fee * MAX_PRIOR_FEE_RATIO) # max fee per gas unit to pay for priority (faster) (optional)

    print(f'''\nSetting gas params ...
        GAS_LIMIT: {GAS_LIMIT}
        GAS_PRICE: {GAS_PRICE} *'gasPrice' param fails on PC
        MAX_FEE: {MAX_FEE} ({MAX_FEE / 10**18} wei)
        MAX_PRIOR_FEE: {MAX_PRIOR_FEE}''')
    
    return GAS_LIMIT, GAS_PRICE, MAX_FEE, MAX_PRIOR_FEE_RATIO, MAX_PRIOR_FEE
#------------------------------------------------------------#
#------------------------------------------------------------#