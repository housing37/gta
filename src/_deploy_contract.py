__fname = '_deploy_contract' # ported from 'defi-arb' (121023)
__filename = __fname + '.py'
cStrDivider = '#================================================================#'
print('', cStrDivider, f'GO _ {__filename} -> starting IMPORTs & declaring globals', cStrDivider, sep='\n')
cStrDivider_1 = '#----------------------------------------------------------------#'

#------------------------------------------------------------#
#   IMPORTS                                                  #
#------------------------------------------------------------#
import sys, os, traceback, time, pprint, json
from datetime import datetime

from web3 import Web3, HTTPProvider
from web3.middleware import construct_sign_and_send_raw_middleware
from web3.gas_strategies.time_based import fast_gas_price_strategy
import env
import pprint
from attributedict.collections import AttributeDict # tx_receipt requirement
import _constants, _web3 # from web3 import Account, Web3, HTTPProvider

# init _w3, user select abi to deploy, generate contract & deploy
_w3 = _web3.WEB3().init_inp()
abi_file, bin_file = _w3.inp_sel_abi_bin(_constants.LST_CONTR_ABI_BIN)
_CONTRACT = _w3.add_contract_deploy(abi_file, bin_file)

print(f'\nDEPLOYING bytecode: {bin_file}')
print(f'DEPLOYING abi: {abi_file}')

assert input('\n (1) procced? [y/n]\n > ') == 'y', "aborted...\n"

def estimate_gas(contract):
    # Replace with your contract's ABI and bytecode
    # contract_abi = CONTR_ABI
    # contract_bytecode = CONTR_BYTES
    
    # Replace with your wallet's private key
    private_key = _w3.SENDER_SECRET

    # Create a web3.py contract object
    # contract = _w3.W3.eth.contract(abi=contract_abi, bytecode=contract_bytecode)

    # Set the sender's address from the private key
    sender_address = _w3.W3.eth.account.from_key(private_key).address

    # Estimate gas for contract deployment
    # gas_estimate = contract.constructor().estimateGas({'from': sender_address})
    gas_estimate = contract.constructor().estimate_gas({'from': sender_address})

    print(f"\nEstimated gas cost _ 0: {gas_estimate}")

    import statistics
    block = _w3.W3.eth.get_block("latest", full_transactions=True)
    gas_estimate = int(statistics.median(t.gas for t in block.transactions))
    gas_price = _w3.W3.eth.gas_price
    gas_price_eth = _w3.W3.from_wei(gas_price, 'ether')
    print(f"Estimated gas cost _ 1: {gas_estimate}")
    print(f" Current gas price: {gas_price_eth} ether (PLS) == {gas_price} wei")
    # Optionally, you can also estimate the gas price (in Gwei) using a gas price strategy
    # Replace 'fast' with other strategies like 'medium' or 'slow' as needed
    #gas_price = W3.eth.generateGasPrice(fast_gas_price_strategy)
    #print(f"Estimated gas price (Gwei): {W3.fromWei(gas_price, 'gwei')}")
    
    return input('\n (2) procced? [y/n]\n > ') == 'y'

# note: params checked/set in priority order; 'def|max_params' uses 'mpf_ratio'
#   if all params == False, falls back to 'min_params=True' (ie. just use 'gas_limit')
def get_gas_params_lst(rpc_url, min_params=False, max_params=False, def_params=True):
    # Estimate the gas cost for the transaction
    #gas_estimate = buy_tx.estimate_gas()
    gas_limit = _w3.GAS_LIMIT # max gas units to use for tx (required)
    gas_price = _w3.GAS_PRICE # price to pay for each unit of gas (optional?)
    max_fee = _w3.MAX_FEE # max fee per gas unit to pay (optional?)
    max_prior_fee = _w3.MAX_PRIOR_FEE # max fee per gas unit to pay for priority (faster) (optional)
    #max_priority_fee = W3.to_wei('0.000000003', 'ether')

    if min_params:
        return [{'gas':gas_limit}]
    elif max_params:
        #return [{'gas':gas_limit}, {'gasPrice': gas_price}, {'maxFeePerGas': max_fee}, {'maxPriorityFeePerGas': max_prior_fee}]
        return [{'gas':gas_limit}, {'maxFeePerGas': max_fee}, {'maxPriorityFeePerGas': max_prior_fee}]
    elif def_params:
        return [{'gas':gas_limit}, {'maxPriorityFeePerGas': max_prior_fee}]
    else:
        return [{'gas':gas_limit}]
        
proceed = estimate_gas(_CONTRACT)
assert proceed, "\ndeployment canceled after gas estimate\n"

print('calculating gas ...')
tx_nonce = _w3.W3.eth.get_transaction_count(_w3.SENDER_ADDRESS)
tx_params = {
    'chainId': _w3.CHAIN_ID,
    'nonce': tx_nonce,
}
lst_gas_params = get_gas_params_lst(_w3.RPC_URL, min_params=False, max_params=True, def_params=True)
for d in lst_gas_params: tx_params.update(d) # append gas params

print(f'building tx w/ NONCE: {tx_nonce} ...')
constructor_tx = _CONTRACT.constructor().build_transaction(tx_params)

print('signing and sending tx ...')
# Sign and send the transaction # Deploy the contract
tx_signed = _w3.W3.eth.account.sign_transaction(constructor_tx, private_key=_w3.SENDER_SECRET)
tx_hash = _w3.W3.eth.send_raw_transaction(tx_signed.rawTransaction)

print(cStrDivider_1, 'waiting for receipt ...', sep='\n')
print(f'    tx_hash: {tx_hash.hex()}')
# Wait for the transaction to be mined
tx_receipt = _w3.W3.eth.wait_for_transaction_receipt(tx_hash)

# print incoming tx receipt (requires pprint & AttributeDict)
tx_receipt = AttributeDict(tx_receipt) # import required
tx_rc_print = pprint.PrettyPrinter().pformat(tx_receipt)
print(cStrDivider_1, f'RECEIPT:\n {tx_rc_print}', sep='\n')
print(cStrDivider_1, f"\n\n Contract deployed at address: {tx_receipt['contractAddress']}\n\n", sep='\n')

# #------------------------------------------------------------#
# #   DEFAULT SUPPORT                                          #
# #------------------------------------------------------------#
# READ_ME = f'''
#     *DESCRIPTION*
#         execute keeper runloop

#     *NOTE* INPUT PARAMS...
#         nil
        
#     *EXAMPLE EXECUTION*
#         $ python3 {__filename} -<nil> <nil>
#         $ python3 {__filename}
# '''
# #ref: https://stackoverflow.com/a/1278740/2298002
# def print_except(e, debugLvl=0):
#     #print(type(e), e.args, e)
#     print('', cStrDivider, f' Exception Caught _ e: {e}', cStrDivider, sep='\n')
#     if debugLvl > 0:
#         print('', cStrDivider, f' Exception Caught _ type(e): {type(e)}', cStrDivider, sep='\n')
#     if debugLvl > 1:
#         print('', cStrDivider, f' Exception Caught _ e.args: {e.args}', cStrDivider, sep='\n')

#     exc_type, exc_obj, exc_tb = sys.exc_info()
#     fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
#     strTrace = traceback.format_exc()
#     print('', cStrDivider, f' type: {exc_type}', f' file: {fname}', f' line_no: {exc_tb.tb_lineno}', f' traceback: {strTrace}', cStrDivider, sep='\n')

# def get_time_now(dt=True):
#     if dt: return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[0:-4]
#     return datetime.now().strftime("%H:%M:%S.%f")[0:-4]

# def read_cli_args():
#     print(f'\nread_cli_args...\n # of args: {len(sys.argv)}\n argv lst: {str(sys.argv)}')
#     for idx, val in enumerate(sys.argv): print(f' argv[{idx}]: {val}')
#     print('read_cli_args _ DONE\n')
#     return sys.argv, len(sys.argv)

# if __name__ == "__main__":
#     ## start ##
#     RUN_TIME_START = get_time_now()
#     print(f'\n\nRUN_TIME_START: {RUN_TIME_START}\n'+READ_ME)
#     lst_argv_OG, argv_cnt = read_cli_args()
    
#     ## exe ##
#     try:
#         pass
#     except Exception as e:
#         print_except(e, debugLvl=0)
    
#     ## end ##
#     print(f'\n\nRUN_TIME_START: {RUN_TIME_START}\nRUN_TIME_END:   {get_time_now()}\n')

# print('', cStrDivider, f'# END _ {__filename}', cStrDivider, sep='\n')