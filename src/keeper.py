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
    lst_evts_min = []
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

        print(cStrDivider_1, f'event #{i} ... {str_from_to}', sep='\n')
        if raw_print:
            # imports required: pprint, AttributeDict
            str_timestamp = f'\n\n Timestamp: {last_time_stamp}\n BlockNumber: {last_block_num}'
            print(pprint.PrettyPrinter().pformat(AttributeDict(event)), str_timestamp)
        else:
            block_num = event["blockNumber"]
            tx_hash = event["transactionHash"].hex()

            # generate block event dict & append to block events array
            block_evt_min = {   
                                'token':w3.to_checksum_address(token),
                                'sender':w3.to_checksum_address(src),
                                'amount':int(amt)
                            }
            lst_evts_min.append(block_evt_min)

            print(" token (address):", token) # token
            print(" sender (address):", src) # sender
            print(" recipient (address):", dst) # recipient
            print(" amount (uint256):", amt) # amount

            # tx meta data
            print(" Timestamp:", last_time_stamp, last_block_num)
            print(" Block Number:", block_num)
            print(" Transaction Hash:", tx_hash)
            print(" solidity call params: ", block_evt_min)

        print(f'events min for solidity side ... ', *lst_evts_min, '', sep='\n')
    return list(lst_evts_min), last_block_num, last_time_stamp

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

        # choose alt tokens for event logs
        _w3.add_contract(_constants.DICT_CONTR_ABI_BIN)

        # choose GTA contract to work with
        _w3.add_contract_GTA(_constants.DICT_CONTR_ABI_BIN)

        print('\nWEB3 INITIALIZED ...', 
                _w3.CHAIN_SEL, _w3.RPC_URL, _w3.CHAIN_ID, _w3.SENDER_ADDRESS, _w3.ACCOUNT.address, 
                [tup[1] for tup in _w3.LST_CONTRACTS], _w3.GAS_LIMIT, _w3.GAS_PRICE, _w3.MAX_FEE, 
                _w3.MAX_PRIOR_FEE_RATIO, _w3.MAX_PRIOR_FEE, sep='\n ')

        # testing...
        # start_blocknum = 18851861
        start_blocknum = _w3.W3.eth.block_number - 10
        print('\nBlock# start: ', start_blocknum)
        for contr_tup in _w3.LST_CONTRACTS: # _w3.LST_CONTRACTS (ERC20 tokens from cli input selection)
            contr_inst = contr_tup[0]
            contr_addr = contr_tup[1]
            lst_evts_min, blocknum, timstamp = get_latest_bals(_w3.W3, contr_inst, start_blocknum, filter_gta=False)

            # Convert python lst_evts_min to Solidity-friendly format
            # LEFT OFF HERE ... add 'v["receiver"]' to send to contract
            solidity_data = [
                    (
                        v["token"], v["sender"], v["amount"]
                    ) for v in lst_evts_min
                ]
            # send 'lst_evts_min' credit updates to solidity contract
            #   note: send credit updates for stable token: 'contr_inst'  (for all players)
            _w3.GTA_CONTRACT.settleBalances(solidity_data, blocknum, {'from': _w3.ACCOUNT})

        print('\n\nBlock# range: ', start_blocknum, blocknum)

        # live...
        while False:
            time.sleep(10) # ~10sec block times (pc)
            last_block_num = _w3.CONTRACT.functions.getLastBlockNumUpdate().call()
            print("GTA alt bals _ last block# ", last_block_num)
            get_latest_bals(_w3, last_block_num)

    except Exception as e:
        print_except(e, debugLvl=0)
    
    ## end ##
    print(f'\n\nRUN_TIME_START: {RUN_TIME_START}\nRUN_TIME_END:   {get_time_now()}\n')

print('', cStrDivider, f'# END _ {__filename}', cStrDivider, sep='\n')


#===============================================================================#
# dead code
#===============================================================================#
# # dict_block_evts support: append block event dict to block_num array
# block_evt = {   'evt_num':evt_num,
#                 'tx_hash':tx_hash,
#                 'token':token,
#                 'evt_sign':str_evt,
#                 'sender':src,
#                 'recipient':dst,
#                 'amount':amt,
#                 'time_stamp':last_time_stamp,
#                 'block_num':block_num
#             }
# dict_block_evts[str(last_block_num)].append(block_evt)

# def wait_sleep(wait_sec:int, b_print=True, bp_one_line=True): # sleep 'wait_sec'
#     if b_print: print(f'waiting... {wait_sec} sec')
#     for s in range(wait_sec, 0, -1):
#         if b_print and bp_one_line: print(wait_sec-s+1, end=' ', flush=True)
#         if b_print and not bp_one_line: print('wait ', s, sep='', end='\n')
#         time.sleep(1)
#     if bp_one_line and b_print: print() # line break if needed
#     print(f'waiting... {wait_sec} sec _ DONE')