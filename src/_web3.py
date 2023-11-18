__fname = '_web3'
__filename = __fname + '.py'
cStrDivider = '#================================================================#'
print('', cStrDivider, f'GO _ {__filename} -> starting IMPORTs & declaring globals', cStrDivider, sep='\n')
cStrDivider_1 = '#----------------------------------------------------------------#'

from web3 import Account, Web3, HTTPProvider
# from web3.middleware import geth_poa_middleware
import env

class WEB3:
    def __init__(self):
        self.rpc_req_timeout = 60 # *tested_111523: 10=50s,30=150s,45=225s,60=300s
        self.RPC_URL = None
        self.CHAIN_ID = None
        self.CHAIN_SEL = None
        self.SENDER_ADDRESS = None
        self.SENDER_SECRET = None
        self.W3 = None
        self.ACCOUNT = None

        self.LST_CONTRACTS = []

        self.GAS_LIMIT = None
        self.GAS_PRICE = None
        self.MAX_FEE = None
        self.MAX_PRIOR_FEE_RATIO = None
        self.MAX_PRIOR_FEE = None

        self.GTA_CONTRACT = None
        self.GTA_CONTRACT_ADDR = None

    def init_inp(self):
        rpc_url, chain_id, chain_sel    = self.inp_sel_chain()
        sender_address, sender_secret   = self.inp_sel_sender()
        w3, account                     = self.init_web3()
        gas_tup                         = self.get_gas_settings(w3)
        return self

    def add_contract_GTA(self, dict_contr):
        assert self.W3 != None, 'err: web3 not initialzed'
        contr_addr              = self.inp_sel_contract([(k,v['symb']) for k,v in dict_contr.items()])
        contr_abi, contr_bytes  = self.read_abi_bytecode(dict_contr[contr_addr]['abi_file'], dict_contr[contr_addr]['bin_file'])
        contract, contr_addr    = self.init_contract(contr_addr, contr_abi, self.W3)
        self.GTA_CONTRACT = contract
        self.GTA_CONTRACT_ADDR = contr_addr

    def add_contract(self, dict_contr):
        assert self.W3 != None, 'err: web3 not initialzed'
        contr_addr              = self.inp_sel_contract([(k,v['symb']) for k,v in dict_contr.items()])
        contr_abi, contr_bytes  = self.read_abi_bytecode(dict_contr[contr_addr]['abi_file'], dict_contr[contr_addr]['bin_file'])
        contract, contr_addr    = self.init_contract(contr_addr, contr_abi, self.W3)
        self.LST_CONTRACTS.append((contract, contr_addr))

    def inp_sel_chain(self):
        self.CHAIN_SEL = input('\nSelect chain:\n  0 = ethereum mainnet\n  1 = pulsechain mainnet\n  > ')
        assert 0 <= int(self.CHAIN_SEL) <= 1, 'Invalid entry, abort'
        self.RPC_URL, self.CHAIN_ID = (env.eth_main, env.eth_main_cid) if int(self.CHAIN_SEL) == 0 else (env.pc_main, env.pc_main_cid)
        print(f'  selected {(self.RPC_URL, self.CHAIN_ID)}')
        return self.RPC_URL, self.CHAIN_ID, self.CHAIN_SEL

    def inp_sel_sender(self):
        sel_send = input(f'\nSelect sender: (_event_listener: n/a)\n  0 = {env.sender_address_3}\n  1 = {env.sender_address_1}\n  > ')
        assert 0 <= int(sel_send) <= 1, 'Invalid entry, abort'
        self.SENDER_ADDRESS, self.SENDER_SECRET = (env.sender_address_3, env.sender_secret_3) if int(sel_send) == 0 else (env.sender_address_1, env.sender_secret_1)
        print(f'  selected {self.SENDER_ADDRESS}')
        return self.SENDER_ADDRESS, self.SENDER_SECRET
    
    def init_web3(self):
        print(f'''\nINITIALIZING web3 ...
            RPC: {self.RPC_URL} _ w/ timeout: {self.rpc_req_timeout}
            ChainID: {self.CHAIN_ID}
            SENDER: {self.SENDER_ADDRESS}
            CONTRACTS: {self.LST_CONTRACTS}''')

        self.W3 = Web3(HTTPProvider(self.RPC_URL, request_kwargs={'timeout': self.rpc_req_timeout}))
        #self.W3.middleware_stack.inject(geth_poa_middleware, layer=0) # chatGPT: for PoA chains; for gas or something
        self.ACCOUNT = Account.from_key(self.SENDER_SECRET)
        return self.W3, self.ACCOUNT
    
    def get_gas_settings(self, w3):
        print('\ncalc gas settings...')
        if int(self.CHAIN_SEL) == 0:
            self.GAS_LIMIT = 3_000_000
            self.GAS_PRICE = w3.to_wei('10', 'gwei')
            self.MAX_FEE = w3.to_wei('14', 'gwei')
            self.MAX_PRIOR_FEE_RATIO = 1.0
            self.MAX_PRIOR_FEE = int(w3.eth.max_priority_fee * self.MAX_PRIOR_FEE_RATIO)
        else:
            self.GAS_LIMIT = 20_000_000
            self.GAS_PRICE = w3.to_wei('0.0005', 'ether')
            self.MAX_FEE = w3.to_wei('0.001', 'ether')
            self.MAX_PRIOR_FEE_RATIO = 1.0
            self.MAX_PRIOR_FEE = int(w3.eth.max_priority_fee * self.MAX_PRIOR_FEE_RATIO)

        print(f'''Setting gas params ...
            GAS_LIMIT: {self.GAS_LIMIT}
            GAS_PRICE: {self.GAS_PRICE} *'gasPrice' param fails on PC
            MAX_FEE: {self.MAX_FEE} ({self.MAX_FEE / 10**18} ether)
            MAX_PRIOR_FEE: {self.MAX_PRIOR_FEE}''')
        
        return self.GAS_LIMIT, self.GAS_PRICE, self.MAX_FEE, self.MAX_PRIOR_FEE_RATIO, self.MAX_PRIOR_FEE

    def inp_sel_contract(self, _lst_contr_addr=[]):
        print(f'\nSelect contract to add:')
        for i, v in enumerate(_lst_contr_addr): print(' ',i,'=',v[0],v[1]) # parse through tuple
        idx = input('  > ')
        assert 0 <= int(idx) < len(_lst_contr_addr), 'Invalid input, aborting...\n'
        contr_addr = str(_lst_contr_addr[int(idx)][0]) # parse through tuple
        print(f'  selected {contr_addr}')
        return contr_addr
    
    def read_abi_bytecode(self, abi_file, bin_file):
        print(f'\nreading contract abi & bytecode files ...\n   {abi_file, bin_file}')
        with open(bin_file, "r") as file: contr_bytes = '0x'+file.read()
        with open(abi_file, "r") as file: contr_abi = file.read()
        return contr_abi, contr_bytes
    
    def init_contract(self, contr_addr, contr_abi, w3):
        print(f'\ninitializing contract {contr_addr} ...')
        contr_addr = w3.to_checksum_address(contr_addr)
        contract = w3.eth.contract(address=contr_addr, abi=contr_abi)
        return contract, contr_addr
    
# #------------------------------------------------------------#
# def inp_CHAIN_SEL():
#     CHAIN_SEL = input('\nSelect chain:\n  0 = ethereum mainnet\n  1 = pulsechain mainnet\n  > ')
#     assert 0 <= int(CHAIN_SEL) <= 1, 'Invalid entry, abort'
#     (RPC_URL, CHAIN_ID) = (env.eth_main, env.eth_main_cid) if int(CHAIN_SEL) == 0 else (env.pc_main, env.pc_main_cid)
#     print(f'  selected {(RPC_URL, CHAIN_ID)}')
#     return RPC_URL, CHAIN_ID, CHAIN_SEL
# #------------------------------------------------------------#
# def inp_sel_sender():
#     sel_send = input(f'\nSelect sender: (_event_listener: n/a)\n  0 = {env.sender_address_3}\n  1 = {env.sender_address_1}\n  > ')
#     assert 0 <= int(sel_send) <= 1, 'Invalid entry, abort'
#     (SENDER_ADDRESS, SENDER_SECRET) = (env.sender_address_3, env.sender_secret_3) if int(sel_send) == 0 else (env.sender_address_1, env.sender_secret_1)
#     print(f'  selected {SENDER_ADDRESS}')
#     return SENDER_ADDRESS, SENDER_SECRET
# #------------------------------------------------------------#
# def inp_sel_contract(LST_CONTR_ADDR=[]):
#     print(f'\nSelect arbitrage contract to use:')
#     for i, v in enumerate(LST_CONTR_ADDR): print(' ',i, '=', v)
#     idx = input('  > ')
#     assert 0 <= int(idx) < len(LST_CONTR_ADDR), 'Invalid input, aborting...\n'
#     CONTR_ADDR = str(LST_CONTR_ADDR[int(idx)])
#     print(f'  selected {CONTR_ADDR}')
#     return CONTR_ADDR
# #------------------------------------------------------------#
# def init_web3(RPC_URL, CHAIN_ID, SENDER_ADDRESS, SENDER_SECRET, CONTR_ADDR='nil_contract'):
#     print(f'''\nINITIALIZING web3 ...
#         RPC: {RPC_URL}
#         ChainID: {CHAIN_ID}
#         SENDER: {SENDER_ADDRESS}
#         CONTRACT: {CONTR_ADDR}''')
        
#     ## CLIENT SIDE TIMEOUT RESULTS *tested_111523: 10=50s,30=150s,45=225s,60=300s
#     # RAISES: requests.exceptions.ReadTimeout: HTTPSConnectionPool(host='rpc.pulsechain.com', port=443): Read timed out. (read timeout=X)
#     # W3 = Web3(HTTPProvider(RPC_URL)) # 50sec timeout logged _ defaults to 'timeout': 10
#     # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 10})) # 50sec timeout logged
#     # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 30})) # 150sec (2.5min) timeout logged
#     # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 45})) # 225sec (3.75min) timeout logged
#     W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 60})) # 5min timeout logged

#     ## SERVER SIDE TIMEOUT RESULTS
#     # RAISES: 504 Server Error: Gateway Time-out
#     # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 65})) # 5min timeout logged
#     # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 90})) # 5min timeout logged
#     # W3 = Web3(HTTPProvider(RPC_URL, request_kwargs={'timeout': 120})) # 5min timeout logged

#     # W3 = Web3(Web3.HTTPProvider(endpoint_uri=RPC_URL, request_kwargs={'timeout': 70}))
#     ACCOUNT = Account.from_key(SENDER_SECRET) # default
#     return W3, ACCOUNT
# #------------------------------------------------------------#
# def read_abi_bytecode(abi_file, bin_file):
#     print(f'\nreading contract abi & bytecode files ...\n   {abi_file, bin_file}')
#     with open(bin_file, "r") as file: CONTR_BYTES = '0x'+file.read()
#     with open(abi_file, "r") as file: CONTR_ABI = file.read()
#     return CONTR_ABI, CONTR_BYTES
# #------------------------------------------------------------#
# def init_contract(CONTR_ADDR, CONTR_ABI, W3:Web3):
#     print(f'\ninitializing contract {CONTR_ADDR} ...')
#     CONTR_ADDR = W3.to_checksum_address(CONTR_ADDR) # convert something ?
#     CONTRACT = W3.eth.contract(address=CONTR_ADDR, abi=CONTR_ABI)
#     return CONTRACT
# #------------------------------------------------------------#
# def get_gas_settings(CHAIN_SEL, W3:Web3):
#     print('calc gas settings...')
#     if int(CHAIN_SEL) == 0:
#         # ethereum main net (update_102923)
#         GAS_LIMIT = 3_000_000# max gas units to use for tx (required)
#         GAS_PRICE = W3.to_wei('10', 'gwei') # price to pay for each unit of gas (optional?)
#         MAX_FEE = W3.to_wei('14', 'gwei') # max fee per gas unit to pay (optional?)
#         MAX_PRIOR_FEE_RATIO = 1.0 # W3.eth.max_priority_fee * mpf_ratio # max fee per gas unit to pay for priority (faster) (optional)
#         MAX_PRIOR_FEE = int(W3.eth.max_priority_fee * MAX_PRIOR_FEE_RATIO) # max fee per gas unit to pay for priority (faster) (optional)
#     else:
#         # pulsechain main net (update_103123)
#         GAS_LIMIT = 20_000_000 # max gas units to use for tx (required)
#         GAS_PRICE = W3.to_wei('0.0005', 'ether') # price to pay for each unit of gas ('gasPrice' param fails on PC)
#         MAX_FEE = W3.to_wei('0.001', 'ether') # max fee per gas unit to pay (optional?)
#         MAX_PRIOR_FEE_RATIO = 1.0
#         MAX_PRIOR_FEE = int(W3.eth.max_priority_fee * MAX_PRIOR_FEE_RATIO) # max fee per gas unit to pay for priority (faster) (optional)

#     print(f'''\nSetting gas params ...
#         GAS_LIMIT: {GAS_LIMIT}
#         GAS_PRICE: {GAS_PRICE} *'gasPrice' param fails on PC
#         MAX_FEE: {MAX_FEE} ({MAX_FEE / 10**18} wei)
#         MAX_PRIOR_FEE: {MAX_PRIOR_FEE}''')
    
#     return GAS_LIMIT, GAS_PRICE, MAX_FEE, MAX_PRIOR_FEE_RATIO, MAX_PRIOR_FEE
# #------------------------------------------------------------#
# #------------------------------------------------------------#