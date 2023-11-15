__fname = 'keeper'
__filename = __fname + '.py'
cStrDivider = '#================================================================#'
print('', cStrDivider, f'GO _ {__filename} -> starting IMPORTs & declaring globals', cStrDivider, sep='\n')
cStrDivider_1 = '#----------------------------------------------------------------#'

#from web3 import Web3
import sys, os, traceback
# import sys, os, time, traceback, json, pprint
from datetime import datetime
import _web3
import _constants

def go_main():
    RPC_URL, CHAIN_ID, sel_chain    = _web3.inp_sel_chain()
    SENDER_ADDRESS, SENDER_SECRET   = _web3.inp_sel_sender()
    # CONTR_ADDR                      = _web3.inp_sel_contract(_constants.LST_CONTR_ARB_ADDR)
    # CONTR_ADDR                      = '0xCc78A0acDF847A2C1714D2A925bB4477df5d48a6'
    CONTR_ADDR                      = '0xA1077a294dDE1B09bB078844df40758a5D0f9a27'
    W3, ACCOUNT                     = _web3.init_web3(RPC_URL, CHAIN_ID, SENDER_ADDRESS, SENDER_SECRET, CONTR_ADDR)
    CONTR_ABI, CONTR_BYTES          = _web3.read_abi_bytecode(_constants.abi_file, _constants.bin_file)
    CONTRACT                        = _web3.init_contract(CONTR_ADDR, CONTR_ABI, W3)
    GAS_LIMIT, GAS_PRICE, MAX_FEE, MAX_PRIOR_FEE_RATIO, MAX_PRIOR_FEE = _web3.get_gas_settings(sel_chain, W3)
    print('\nALL INPUTS ...', 
            sel_chain, RPC_URL, CHAIN_ID, SENDER_ADDRESS, ACCOUNT.address, 
            CONTR_ADDR, CONTRACT.address, GAS_LIMIT, GAS_PRICE, MAX_FEE, 
            MAX_PRIOR_FEE_RATIO, MAX_PRIOR_FEE, sep='\n ')
    print('ALL INPUTS _ DONE')

    # set from|to block numbers
    from_block = 18840779 # int | W3.eth.block_number
    to_block = 18840789 # int | 'latest'

    # ## OPTIONAL: use event filters (chatGPT complex suggestion)
    # ##   note_111523: not quite sure how these filters work, but basic from/to block works fine
    # evt_sign = W3.keccak(text="Transfer(address,address,uint256)").hex()
    # evt_name = 'Transfer'
    # wild_card = None
    # filt_addr = CONTR_ADDR
    # event_filter = {
    #     "fromBlock": from_block,
    #     "toBlock": to_block,
    #     # "address": CONTRACT.address,
    #     # "topics": [evt_sign] # [evt_sign, filt_addr] # [evt_sign, wild_card, filt_addr]
    # }
    # print('\nEVENT FILTERS ...', evt_sign, evt_name, from_block, to_block, wild_card, sep='\n ')
    # print('EVENT FILTERS _ DONE')
    # ## fetch transfer events w/ complex filter
    # print(f'\nGETTING_LOGS: {get_time_now()}\n _ from_block: {from_block}\n _ to_block: {to_block}')
    # logs = CONTRACT.events[evt_name].get_logs(event_filter)
    # print(f'GETTING_LOGS: {get_time_now()} _ DONE\n')

    # fetch transfer events w/ simple fromBlock/toBlock
    print(f'\nGETTING_LOGS: {get_time_now()}\n _ from_block: {from_block}\n _ to_block: {to_block}')
    logs = CONTRACT.events.Transfer().get_logs(fromBlock=from_block, toBlock=to_block) # toBlock='latest' (default)
    print(f'GETTING_LOGS: {get_time_now()} _ DONE\n')

    # Pretty print the dictionary
    import pprint
    from attributedict.collections import AttributeDict # required w/ pprint: tx_receipt & event logs
    for i, event in enumerate(logs):
        logx = AttributeDict(event) # import required
        logx_print = pprint.PrettyPrinter().pformat(logx)
        print(cStrDivider_1, f'log {i} print:\n {logx_print}', sep='\n')
        print()
        # print(f"Transfer of {W3.from_wei(log.args.wad, 'ether')} WETH from {log.args.src} to {log.args.dst}")

        # event Transfer(address sender, address recipient, uint256 amount);
        print("sender (address):", event["args"]["src"]) # sender
        print("recipient (address):", event["args"]["dst"]) # recipient
        print("amount (uint256):", event["args"]["wad"]) # amount

        # tx meta data
        block = W3.eth.getBlock(event["blockNumber"])
        print("Timestamp:", block["timestamp"])
        print("Transaction Hash:", event["transactionHash"].hex())
        print("Block Number:", event["blockNumber"])
        
        print()
        
        # ... check for "emit Transfer(sender, recipient, amount);"
        # ... call solidity function

#------------------------------------------------------------#
#   DEFAULT SUPPORT                                          #
#------------------------------------------------------------#
READ_ME = f'''
    *DESCRIPTION*
        execute keeper runloop

    *NOTE* INPUT PARAMS...
        nil
        
    *EXAMPLE EXECUTION*
        $ python3 {__filename} -<nil> <nil>
        $ python3 {__filename}
'''
#ref: https://stackoverflow.com/a/1278740/2298002
def print_except(e, debugLvl=0):
    # prints instance, args, __str__ allows args to be printed directly
    #print(type(e), e.args, e)
    print('', cStrDivider, f' Exception Caught _ e: {e}', cStrDivider, sep='\n')
    if debugLvl > 0:
        print('', cStrDivider, f' Exception Caught _ type(e): {type(e)}', cStrDivider, sep='\n')
    if debugLvl > 1:
        print('', cStrDivider, f' Exception Caught _ e.args: {e.args}', cStrDivider, sep='\n')

    exc_type, exc_obj, exc_tb = sys.exc_info()
    fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
    strTrace = traceback.format_exc()
    print('', cStrDivider, f' type: {exc_type}', f' file: {fname}', f' line_no: {exc_tb.tb_lineno}', f' traceback: {strTrace}', cStrDivider, sep='\n')

def get_time_now(dt=True):
    if dt: return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[0:-4]
    return datetime.now().strftime("%H:%M:%S.%f")[0:-4]

def read_cli_args():
    print(f'\nread_cli_args...\n # of args: {len(sys.argv)}\n argv lst: {str(sys.argv)}')
    for idx, val in enumerate(sys.argv): print(f' argv[{idx}]: {val}')
    print('read_cli_args _ DONE\n')
    return sys.argv, len(sys.argv)

if __name__ == "__main__":
    ## start ##
    RUN_TIME_START = get_time_now()
    print(f'\n\nRUN_TIME_START: {RUN_TIME_START}\n'+READ_ME)
    lst_argv_OG, argv_cnt = read_cli_args()
    
    ## exe ##
    try:
        go_main()
        # if sys.argv[-1] == '-loan': go_loan()
        # if sys.argv[-1] == '-trans': go_transfer()
        # if sys.argv[-1] == '-withdraw': go_withdraw()
        
    except Exception as e:
        print_except(e, debugLvl=0)
    
    ## end ##
    print(f'\n\nRUN_TIME_START: {RUN_TIME_START}\nRUN_TIME_END:   {get_time_now()}\n')

print('', cStrDivider, f'# END _ {__filename}', cStrDivider, sep='\n')