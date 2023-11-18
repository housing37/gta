__fname = 'keeper'
__filename = __fname + '.py'
cStrDivider = '#================================================================#'
print('', cStrDivider, f'GO _ {__filename} -> starting IMPORTs & declaring globals', cStrDivider, sep='\n')
cStrDivider_1 = '#----------------------------------------------------------------#'

#------------------------------------------------------------#
#   IMPORTS                                                  #
#------------------------------------------------------------#
import sys, os, traceback, time, pprint, json
from attributedict.collections import AttributeDict # required w/ pprint for contract events
from datetime import datetime
import _constants, _web3 # from web3 import Account, Web3, HTTPProvider

# additional common support
#from web3.exceptions import ContractLogicError
#import inspect # this_funcname = inspect.stack()[0].function
#parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
#sys.path.append(parent_dir) # import from parent dir of this file

#------------------------------------------------------------#
#   GLOABALS SUPPORT                                         #
#------------------------------------------------------------#
GTA_CONTRACT_ADDR = '0xGtaContractAddress'

#------------------------------------------------------------#
#   FUNCTION SUPPORT                                         #
#------------------------------------------------------------#
def get_latest_bals(w3:object, contract:object, start_block_num:int, raw_print:bool=False, filter_gta=True):
    # set from|to block numbers
    from_block = start_block_num # int | w3.eth.block_number
    to_block = 'latest' # int | 'latest'
    str_from_to = f'from_block: {from_block} _ to_block: {to_block}'
    
    # fetch transfer events w/ simple fromBlock/toBlock
    str_evt = 'Transfer(address,address,uint256)'
    print(f"\nGETTING EVENT LOGS: '{str_evt}' _ {get_time_now()}\n ... {str_from_to}")
    events = contract.events.Transfer().get_logs(fromBlock=from_block, toBlock=to_block) # toBlock='latest' (default)

    # print events
    last_block_num = last_time_stamp = 0
    dict_evts = {}
    for i, event in enumerate(events):
        evt_num = i
        token = contract.address

        # check for various param names for 'event Transfer(address,address,uint256);'
        if token == '0xA1077a294dDE1B09bB078844df40758a5D0f9a27': # WPLS support
            src = event["args"]["src"]
            dst = event["args"]["dst"]
            amt = event["args"]["wad"]
        if token == '0x95B303987A60C71504D99Aa1b13B4DA07b0790ab': # PLSX support
            src = event["args"]["from"]
            dst = event["args"]["to"]
            amt = event["args"]["value"]

        # # ignore token txs NOT sent to gta contract
        if dst != GTA_CONTRACT_ADDR and filter_gta:
            # print('dst != GTA_CONTRACT_ADDR', f'({dst} != {GTA_CONTRACT_ADDR})')
            print(' .', end='', flush=True)
            continue

        # exe call to get block timestamp (min amount of times)
        if int(event["blockNumber"]) != last_block_num:
            last_block_num = int(event["blockNumber"])
            last_time_stamp = int(w3.eth.get_block(event["blockNumber"])["timestamp"])

            # initalize block_num key to empty block event dict array (if needed)
            if str(last_block_num) not in dict_evts:
                dict_evts[str(last_block_num)] = []

        print(cStrDivider_1, f'event #{i} ... {str_from_to}', sep='\n')
        if raw_print:
            # imports required: pprint, AttributeDict
            str_timestamp = f'\n\n Timestamp: {last_time_stamp}\n BlockNumber: {last_block_num}'
            print(pprint.PrettyPrinter().pformat(AttributeDict(event)), str_timestamp)
        else:
            block_num = event["blockNumber"]
            tx_hash = event["transactionHash"].hex()
            print(" token (address):", token) # token
            print(" sender (address):", src) # sender
            print(" recipient (address):", dst) # recipient
            print(" amount (uint256):", amt) # amount

            # tx meta data
            print(" Timestamp:", last_time_stamp, last_block_num)
            print(" Block Number:", block_num)
            print(" Transaction Hash:", tx_hash)

            # append block event dict to block_num array
            block_evt = {   'evt_num':evt_num,
                            'tx_hash':tx_hash,
                            'token':token,
                            'evt_sign':str_evt,
                            'sender':src,
                            'recipient':dst,
                            'amount':amt,
                            'time_stamp':last_time_stamp,
                            'block_num':block_num
                        }
            dict_evts[str(last_block_num)].append(block_evt)
            
        print()
    return dict_evts, last_block_num, last_time_stamp

    # LEFT OFF HERE... need to update alt balances in contract w/ 'Transfer' event data
    #   DONE - parse filtered data from ‘Transfer’ event, and update contract
    #   - send dict_evts to gta contract 

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

# def wait_sleep(wait_sec:int, b_print=True, bp_one_line=True): # sleep 'wait_sec'
#     if b_print: print(f'waiting... {wait_sec} sec')
#     for s in range(wait_sec, 0, -1):
#         if b_print and bp_one_line: print(wait_sec-s+1, end=' ', flush=True)
#         if b_print and not bp_one_line: print('wait ', s, sep='', end='\n')
#         time.sleep(1)
#     if bp_one_line and b_print: print() # line break if needed
#     print(f'waiting... {wait_sec} sec _ DONE')

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
        _w3 = _web3.WEB3().init_inp()
        _w3.add_contract(_constants.DICT_CONTR_ABI_BIN)
        #_w3.add_contract(_constants.DICT_CONTR_ABI_BIN) # choose 2nd token for event logs
        print('\nWEB3 INITIALIZED ...', 
                _w3.CHAIN_SEL, _w3.RPC_URL, _w3.CHAIN_ID, _w3.SENDER_ADDRESS, _w3.ACCOUNT.address, 
                [tup[1] for tup in _w3.LST_CONTRACTS], _w3.GAS_LIMIT, _w3.GAS_PRICE, _w3.MAX_FEE, 
                _w3.MAX_PRIOR_FEE_RATIO, _w3.MAX_PRIOR_FEE, sep='\n ')

        # testing...
        # start_block_num = 18851861
        start_block_num = _w3.W3.eth.block_number - 10
        # start_block_num = _w3.W3.eth.block_number
        print('\nBlock# start: ', start_block_num)
        lst_dict_evts = [] # store multiple token events
        for contr_tup in _w3.LST_CONTRACTS:
            dict_evts, last_block_num, last_time_stamp = get_latest_bals(_w3.W3, contr_tup[0], start_block_num, filter_gta=False)
            lst_dict_evts.append(dict_evts)
        print('\n\nBlock# range: ', start_block_num, last_block_num)
        print(json.dumps(lst_dict_evts, indent=4))

        # live...
        while False:
            time.sleep(10) # ~10sec block times (pc)
            last_block_num = _w3.CONTRACT.functions.getLastBlockNumUpdate().call()
            print("GTA alt bals _ last block# ", last_block_num)
            get_latest_bals(_w3, last_block_num)

        # LEFT OFF HERE... need to update alt balances in contract w/ 'Transfer' event data
        #   DONE - parse filtered data from ‘Transfer’ event, and update contract
        #   - send dict_evts to gta contract

        #go_main(_WEB3, last_block_num)
        # if sys.argv[-1] == '-loan': go_loan()
        # if sys.argv[-1] == '-trans': go_transfer()
        # if sys.argv[-1] == '-withdraw': go_withdraw()
        
    except Exception as e:
        print_except(e, debugLvl=0)
    
    ## end ##
    print(f'\n\nRUN_TIME_START: {RUN_TIME_START}\nRUN_TIME_END:   {get_time_now()}\n')

print('', cStrDivider, f'# END _ {__filename}', cStrDivider, sep='\n')