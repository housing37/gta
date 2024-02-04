__fname = '_mempool'
__filename = __fname + '.py'
cStrDivider = '#================================================================#'
cStrDivider_1 = '#----------------------------------------------------------------#'
print('', cStrDivider, f'GO _ {__filename} -> starting IMPORTs & declaring globals', cStrDivider, sep='\n')

#------------------------------------------------------------#
#   IMPORTS                                                  #
#------------------------------------------------------------#
import _web3 # from web3 import Account, Web3, HTTPProvider
import json, time, os, traceback, sys
from datetime import datetime

#------------------------------------------------------------#
#   GLOBALS                                                  #
#------------------------------------------------------------#
SEARCH_ADDR = 'nil_addr'
LST_HEX_TO_INT = ['gas', 'maxPriorityFeePerGas', 'maxFeePerGas', 'gasPrice', 'nonce', 'value', 'type', 'chainId']
DICT_MAP_TYPES = {0:'standard', 1:'create', 2:'message'}
SEARCH_HASHES = {'baseFee':[], 'pending':[], 'queued':[]}
SEARCH_WAIT_SEC = 5
SEARCH_PRINT = {}
FOUND_FROM = False

#------------------------------------------------------------#
#   FUNCTIONS                                                #
#------------------------------------------------------------#
def go_mempool(_rpc_url, _w3, _search=False):
    global SEARCH_PRINT # REQUIRED (using assignment)
    if _search:
        search_cnt = 0
        while True:
            tx_pool = _web3.myWEB3().check_mempool(_rpc_url)
            baseFee = dict(tx_pool['baseFee'])
            pending = dict(tx_pool['pending'])
            queued = dict(tx_pool['queued'])
            refactor_dict(_w3, baseFee, 'baseFee', search_cnt, _search)
            refactor_dict(_w3, pending, 'pending', search_cnt, _search)
            refactor_dict(_w3, queued, 'queued', search_cnt, _search)
            print('\n', cStrDivider_1, f'PRINTING SEARCH_PRINT ... {search_cnt} _ {get_time_now()}', sep='\n')
            print(json.dumps(SEARCH_PRINT, indent=4))
            print(f"\nALL b'aseFee HASHES found for SEARCH_ADDR: {SEARCH_ADDR}")
            print(*SEARCH_HASHES['baseFee'], sep='\n')
            print(f"ALL p'ending HASHES found for SEARCH_ADDR: {SEARCH_ADDR}")
            print(*SEARCH_HASHES['pending'], sep='\n')
            print(f"ALL q'ueued HASHES found for SEARCH_ADDR: {SEARCH_ADDR}")
            print(*SEARCH_HASHES['queued'], sep='\n')
            SEARCH_PRINT = {}
            print(f'\nwaiting... {SEARCH_WAIT_SEC} sec _ RUN_TIME_START: {RUN_TIME_START}')
            for s in range(0, SEARCH_WAIT_SEC, 1):
                print(s, end=' ', flush=True)
                time.sleep(1)
            search_cnt += 1
    else:
        tx_pool = _web3.myWEB3().check_mempool(_rpc_url)
        baseFee = dict(tx_pool['baseFee'])
        pending = dict(tx_pool['pending'])
        queued = dict(tx_pool['queued'])
        refactor_dict(_w3, baseFee, 'baseFee')
        refactor_dict(_w3, pending, 'pending')
        refactor_dict(_w3, queued, 'queued')

        print(cStrDivider_1, 'PRINTING baseFee ...', sep='\n')
        print(json.dumps(baseFee, indent=4))

        print(cStrDivider_1, 'PRINTING pending ...', sep='\n')
        print(json.dumps(pending, indent=4))

        print(cStrDivider_1, 'PRINTING queued ...', sep='\n')
        print(json.dumps(queued, indent=4))
        exit()

def refactor_dict(_w3, _d, _type, _cnt=0, _search=False):
    # global SEARCH_PRINT # NOT REQUIRED (only modifying)
    for k, v in _d.items():
        v['type'] = _type
        from_addr = v
        for k1, v1 in from_addr.items():
            if k1 == 'type': continue
            num_dict = v1
            FOUND_FROM = False
            for k2, v2 in num_dict.items():
                if k2 in LST_HEX_TO_INT:
                    num_dict[k2] = int(v2, 16)
                if k2 == 'type':
                    num_dict[k2] = f"{num_dict[k2]} {DICT_MAP_TYPES[num_dict[k2]]}"
                if k2 == 'gas':
                    num_dict[k2] = f"{num_dict[k2]:,} units"
                if k2 == 'maxPriorityFeePerGas' or k2 == 'maxFeePerGas' or k2 == 'gasPrice':
                    num_dict[k2] = f"{num_dict[k2]:,} wei == " + f"{round(_w3.from_wei(num_dict[k2], 'gwei'),0):,}" + " beats"
                if _search:
                    if k2 == 'hash' and FOUND_FROM: 
                        # search_hash_curr = v2
                        if v2 not in SEARCH_HASHES[_type]: SEARCH_HASHES[_type].append(v2)
                    if k2 == 'from' and v2.lower() == SEARCH_ADDR.lower():
                        num_dict['input'] = 'n/a'
                        SEARCH_PRINT[k+f" _ {_cnt}"] = v
                        FOUND_FROM = True    

def go_user_inputs():
    global SEARCH_ADDR # REQUIRED (using assignment)
    rpc_url, chain_id, chain_sel    = _web3.myWEB3().inp_sel_chain()
    w3, account = _web3.myWEB3().init_web3(empty=True)
    ans = input('\n Search address? [y/n]\n  > ')
    b_ans = ans == 'y' or ans == '1'
    if b_ans:
        SEARCH_ADDR = input('\n Enter address:\n  > ')
        print(f' searching for: {SEARCH_ADDR}')
    else:
        print(f'ans = {b_ans}')
    print('\n\n')
    return rpc_url, w3, b_ans

#------------------------------------------------------------#
#   DEFAULT SUPPORT                                          #
#------------------------------------------------------------#
READ_ME = f'''
    *DESCRIPTION*
        choose blockchain
        get latest tx pool
            OR
        search for 'from' address 
         and loop get tx pool

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
    if dt: return '['+datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[0:-4]+']'
    return '['+datetime.now().strftime("%H:%M:%S.%f")[0:-4]+']'

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
        rpc_url_, w3_, b_ans_ = go_user_inputs()
        go_mempool(rpc_url_, w3_, b_ans_)
    except Exception as e:
        print_except(e, debugLvl=0)
    
    ## end ##
    print(f'\n\nRUN_TIME_START: {RUN_TIME_START}\nRUN_TIME_END:   {get_time_now()}\n')

print('', cStrDivider, f'# END _ {__filename}', cStrDivider, sep='\n')