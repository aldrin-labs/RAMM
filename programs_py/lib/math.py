# oamm
# Built with Seahorse v0.2.4

from seahorse.prelude import *

def weights(balances: Array[f64,3],price_list: Array[f64,3]) -> Array[f64,3]:
  """Returns an array with the weights of the tokens with respect to the current prices."""
  assert len(balances)==len(price_list) , "Balance list and price list do not have the same length."
  n=len(balances)
  B=0.0
  W=array(0.0,0.0,0.0)
  for j in range(n):
    price=price_list[j]
    balance=balances[j]
    B+=price*balance
  for j in range(n):
    price=price_list[j]
    balance=balances[j]
    W[j]=price*balance/B
  return W


def compute_B_and_L(balances: Array[f64,3], LP_tokens_issued: Array[f64,3], price_list: Array[f64,3]) -> Tuple[f64,f64]:
  """Returns a tuple with the values of B and L"""
  assert len(balances)==len(price_list) , "Balance list and price list do not have the same length."
  assert len(balances)==len(LP_tokens_issued) , "Balance list and list of amount of LP tokens issued do not have the same length."
  n= len(balances)
  B=0.0
  L=0.0
  for j in range(n):
    price=price_list[j]
    balance=balances[j]
    lptok=LP_tokens_issued[j]
    B+=price*balance
    L+=price*lptok
    #print(f'B: {B}.')
  return B,L


def imbalance_ratios(balances: Array[f64,3], LP_tokens_issued: Array[f64,3], price_list: Array[f64,3]) -> Array[f64,3]:
  """Returns a list with the imbalance ratios of the tokens."""
  assert len(balances)==len(price_list) , "Balance list and price list do not have the same length."
  assert len(balances)==len(LP_tokens_issued) , "Balance list and list of amount of LP tokens issued do not have the same length."
  n= len(balances)
  W=array(0.0,0.0,0.0)
  LP_tokens_list=list(LP_tokens_issued)
  balances_list=list(balances)
  LP_tokens_issued_copy=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
  B,L=compute_B_and_L(balances, LP_tokens_issued_copy, price_list)
  for j in range(n):
    lptok=LP_tokens_list[j]
    #print(f"{B} {L} {lptok}")
    if lptok != 0.0:
      balance=balances_list[j]
      W[j]=(balance*L)/(B*lptok)
    else:
      W[j]=-1.0
  return W

def check_imbalance_ratios(balances: Array[f64,3], LP_tokens_issued: Array[f64,3], prices: Array[f64,3],i: u8,o: u8,ai:f64, ao:f64, pr_fee: f64, delta: f64) -> bool:
  ### We check imbalance ratios
  balances_list=list(balances)
  LP_tokens_list=list(LP_tokens_issued)
  prices_list=list(prices)
  balances_before=array(balances_list[0],balances_list[1],balances_list[2])
  LP_tokens_issued_before=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
  prices_before=array(prices[0],prices[1],prices[2])
  bi=balances_list[i]
  balances_list[i]=bi+ai-pr_fee
  bo=balances_list[o]
  balances_list[o]=bo-ao
  balances_after=array(balances_list[0],balances_list[1],balances_list[2])
  LP_tokens_issued_after=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
  prices_after=array(prices[0],prices[1],prices[2])
  imb_ratios_before_trade_array=imbalance_ratios(balances_before, LP_tokens_issued_before, prices_before)
  imb_ratios_before=list(imb_ratios_before_trade_array)
  imb_ratios_after_trade_array=imbalance_ratios(balances_after, LP_tokens_issued_after, prices_after)
  imb_ratios_after=list(imb_ratios_after_trade_array)
  print(f'Imbalance ratios after trade: {imb_ratios_after}')
  print(f'{imb_ratios_after[o]<1.0-delta} {imb_ratios_after[o]<imb_ratios_before[o]} {imb_ratios_after[i]>1.0+delta} {imb_ratios_after[i]>imb_ratios_before[i]}')
  if (imb_ratios_after[o]<1.0-delta and imb_ratios_after[o]<imb_ratios_before[o]) or (imb_ratios_after[i]>1.0+delta and imb_ratios_after[i]>imb_ratios_before[i]):
    # execute_trade=False
    return False
  #else: execute_trade=True
  return True


def funct_adjust_leverage_parameter(x: f64) -> f64:
    """Base function that adjusts the leverage parameter."""
    return x**3.0

def funct_adjust_fee(x: f64) -> f64:
    """Base function that adjusts the fee."""
    return x**3.0

def scaled_fee_and_leverage(balances: Array[f64,3], LP_tokens_issued: Array[f64,3], price_list: Array[f64,3], base_fee: f64, base_leverage_parameter: f64, i: u8, o: u8) -> Tuple[f64,f64]:
    """Returns the scaled fee and leverage parameter for a trade where token i goes into the pool and
    token o goes out of the pool."""
    imbalance=imbalance_ratios(balances, LP_tokens_issued, price_list)
    print(f'Imbalance: {imbalance}')
    scaled_fee=funct_adjust_fee(imbalance[i])/funct_adjust_fee(imbalance[o])*base_fee
    scaled_leverage=funct_adjust_leverage_parameter(imbalance[o])/funct_adjust_leverage_parameter(imbalance[i])*base_leverage_parameter
    return scaled_fee,scaled_leverage



def trade_i(i: u8,o: u8,ai: f64, balances: Array[f64,3], LP_tokens_issued: Array[f64,3], prices: Array[f64,3],fee: f64,protocol_fee: f64,leverage: f64,delta: f64) -> Tuple[f64,f64,bool]:
    """Performs a trade where an amount ai of token i goes into the pool
    and token o goes out of the pool. Returns the amount ao of token o that goes
    out of the pool."""
    LP_tokens_list=list(LP_tokens_issued)
    balances_list=list(balances)
    # We check conditions first.
    if LP_tokens_list[i]==0.0:
        print(f'Trade not allowed. No LP tokens {i} in circulation.')
        return 0.0,0.0,False
    if balances_list[o]==0.0:
        print(f"The trade can't be performed. No token {o} in the pool.")
        return 0.0,0.0,False
    ## First we update the weights
    prices_copy_1=array(prices[0],prices[1],prices[2])
    balances_copy_1=array(balances[0],balances[1],balances[2])
    price_list=list(prices)
    W=weights(balances_copy_1, prices_copy_1)
    # We divide into different cases
    if balances_list[i]==0.0:
        ao=(1.0-fee)*ai*price_list[i]/price_list[o]
        pr_fee=protocol_fee*fee*ai
        print(f"--- Trade --- in: {i} --- out: {o}")
        print(f"Price list: {price_list}.")
        print(f"in: {ai} {i} --- out: {ao} {o}")
        print(f"Effective price: {(1.0-fee)*ai/ao} {i}/{o} --- {ao/((1.0-fee)*ai)} {o}/{i}")
        balances_copy_4=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_4=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_4=array(prices[0],prices[1],prices[2])
        execute_trade=check_imbalance_ratios(balances_copy_4, LP_tokens_issued_copy_4, prices_copy_4,i,o,ai,ao, pr_fee, delta)
        return ao,pr_fee,execute_trade
    if LP_tokens_list[o]==0.0 and balances_list[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        bi1=balances_list[i]
        bi=bi1*leverage
        wi=W[i]
        bo1=balances_list[o]
        bo=bo1*leverage
        wo=W[o]
        ao=bo*(1.0-(bi/(bi+(1.0-fee)*ai))**(wi/wo))
    if LP_tokens_list[o]!=0.0 and balances_list[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        ## We check imbalance ratio of token o
        prices_copy_2=array(prices[0],prices[1],prices[2])
        balances_copy_2=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        imb_ratios_initial=imbalance_ratios(balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2)
        if imb_ratios_initial[o]<1.0-delta:
            print(f'Imbalance ratio of Token {o} too low.')
            return 0.0,0.0,False
        ## Now we update the fees and the leverage parameter
        prices_copy_3=array(prices[0],prices[1],prices[2])
        balances_copy_3=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_3=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        trading_fee,leverage=scaled_fee_and_leverage(balances_copy_3, LP_tokens_issued_copy_3, prices_copy_3,fee,leverage,i,o)
        ## Now we perform the trade
        bi1=balances_list[i]
        bi=bi1*leverage
        wi=W[i]
        bo1=balances_list[o]
        bo=bo1*leverage
        wo=W[o]
        ao=bo*(1.0-(bi/(bi+(1.0-trading_fee)*ai))**(wi/wo))
        pr_fee=protocol_fee*trading_fee*ai
        ## if Verbose: print("computations",wi/wo,bi/(bi+(1.0-trading_fee)*ai),1.0-(bi/(bi+(1.0-trading_fee)*ai))**(wi/wo),bo,ao)
        if ao>=balances_list[o]:
            # We check if there is enough balance of token o.
            print(f"Not enough balance of token {o}.")
            return 0.0,0.0,False
        balances_copy_5=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_5=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_5=array(prices[0],prices[1],prices[2])
        execute_trade=check_imbalance_ratios(balances_copy_5, LP_tokens_issued_copy_5, prices_copy_5,i,o,ai,ao, pr_fee, delta)
        return ao,pr_fee,execute_trade

    return 0.0,0.0,False




def trade_o(i: u8,o: u8,ao: f64, balances: Array[f64,3], LP_tokens_issued: Array[f64,3], prices: Array[f64,3],fee: f64,protocol_fee: f64,leverage: f64,delta: f64) -> Tuple[f64,f64,bool]:
    """Performs a trade where an amount ao of token o goes out of the pool
    and token i goes into the pool. Returns the amount ai of token i that goes
    into the pool."""
    if ao<=0.0:
        print(f"Invalid amount of token {o}")
        return 0.0,0.0,False
    # We check conditions first.
    LP_tokens_list=list(LP_tokens_issued)
    balances_list=list(balances)
    if LP_tokens_list[i]==0.0:
        print(f'Trade not allowed. No LP {i} tokens in circulation.')
        return 0.0,0.0,False
    if ao>=balances_list[o]:
        # We check if there is enough balance of token o.
        # This also prevents the balance of token 0 from being zero.
        print(f"Not enough balance of token {o}")
        return 0.0,0.0,False
    # First we update the weights
    prices_copy_1=array(prices[0],prices[1],prices[2])
    balances_copy_1=array(balances[0],balances[1],balances[2])
    price_list=list(prices)
    W=weights(balances_copy_1, prices_copy_1)
    # We divide into different cases
    if balances_list[i]==0.0:
        ai=ao*price_list[o]/price_list[i]/(1.0-fee)
        pr_fee=protocol_fee*fee*ai
        print(f"--- Trade --- in: {i} --- out: {o}")
        print(f"Price list: {price_list}.")
        print(f"in: {ai} {i} --- out: {ao} {o}")
        print(f"Effective price: {(1.0-fee)*ai/ao} {i}/{o} --- {ao/((1.0-fee)*ai)} {o}/{i}")
        balances_copy_4=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_4=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_4=array(prices[0],prices[1],prices[2])
        execute_trade=check_imbalance_ratios(balances_copy_4, LP_tokens_issued_copy_4, prices_copy_4,i,o,ai,ao, pr_fee, delta)
        return ai,pr_fee,execute_trade
    if LP_tokens_list[o]==0.0 and balances_list[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        bi1=balances_list[i]
        bi=bi1*leverage
        wi=W[i]
        bo1=balances_list[o]
        bo=bo1*leverage
        wo=W[o]
        ai=bi/(1.0-fee)*((bo/(bo-ao))**(wo/wi)-1.0)
        pr_fee=protocol_fee*fee*ai
        balances_copy_5=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_5=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_5=array(prices[0],prices[1],prices[2])
        execute_trade=check_imbalance_ratios(balances_copy_5, LP_tokens_issued_copy_5, prices_copy_5,i,o,ai,ao, pr_fee, delta)
        return ao,pr_fee,execute_trade

    if LP_tokens_list[o]!=0.0 and balances_list[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        # We check imbalance ratio of token o
        balances_copy_2=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_2=array(prices[0],prices[1],prices[2])
        imb_ratios_initial=imbalance_ratios(balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2)
        if imb_ratios_initial[o]<1.0-delta:
            print(f'Imbalance ratio of {o} too low.')
            return 0.0,0.0,False

        # Now we update the fees and the leverage parameter
        balances_copy_3=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_3=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_3=array(prices[0],prices[1],prices[2])
        trading_fee,leverage=scaled_fee_and_leverage(balances_copy_3, LP_tokens_issued_copy_3, prices_copy_3,fee,leverage,i,o)
        # Now we perform the trade
        bi1=balances_list[i]
        bi=bi1*leverage
        wi=W[i]
        bo1=balances_list[o]
        bo=bo1*leverage
        wo=W[o]
        ai=bi/(1.0-trading_fee)*((bo/(bo-ao))**(wo/wi)-1.0)
        pr_fee=protocol_fee*trading_fee*ai
        # We check imbalance ratios
        balances_copy_6=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_6=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_6=array(prices[0],prices[1],prices[2])
        execute_trade=check_imbalance_ratios(balances_copy_6, LP_tokens_issued_copy_6, prices_copy_6,i,o,ai,ao, pr_fee, delta)
        print(f"--- Trade --- in: {i} --- out: {o}")
        print(f"Price list: {price_list}.")
        print(f"Leverage parameter: {leverage} --- Fee: {trading_fee} %")
        print(f"in: {ai} {i} --- out: {ao} {o}")
        print(f"Effective price: {(1.0-trading_fee)*ai/ao} {i}/{o} --- {ao/((1.0-trading_fee)*ai)} {o}/{i}")
        return ao,pr_fee,execute_trade
    return 0.0,0.0,False


def single_asset_deposit(i: u8, ai: f64, balances: Array[f64,3], LP_tokens_issued: Array[f64,3], prices: Array[f64,3])-> Tuple[f64,u8]:
    """Performs a single asset deposit of amount i of token i.
    Returns the amount of LP tokens and its type (i) that must be given to the liquidity provider.
    """
    LP_tokens_list=list(LP_tokens_issued)
    balances_list=list(balances)
    # we divide into cases
    if LP_tokens_list[i]==0.0 or (LP_tokens_list[i]!=0.0 and balances_list[i]==0.0):
        balances_copy_1=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_1=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_1=array(prices[0],prices[1],prices[2])
        B,L=compute_B_and_L(balances_copy_1, LP_tokens_issued_copy_1, prices_copy_1)
        lpt=ai*L/B
        print("in:",ai,"Token",i,"--- out:",lpt,"LP tokens")
        return lpt,i

    if LP_tokens_list[i]!=0.0 and balances_list[i]!=0.0:
        balances_copy_2=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_2=array(prices[0],prices[1],prices[2])
        imb_ratios_array=imbalance_ratios(balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2)
        bi=balances_list[i]
        ri=imb_ratios_array[i]
        lpt=(ai/bi)*ri*LP_tokens_list[i]
        print("in:",ai,"Token",i,"--- out:",lpt,"LP tokens")
        return lpt,i

    return 0.0,0



def single_asset_withdrawal(o: u8, lpt: f64, balances: Array[f64,3], LP_tokens_issued: Array[f64,3], prices: Array[f64,3],delta:f64) -> f64:
    """ Given an amount of LP tokens and its type o,
    returns the amount of token o to be given to the LP.
    """
    LP_tokens_list=list(LP_tokens_issued)
    balances_list=list(balances)

    a_remaining=[0.0]
    aol=[0.0]

    bo=balances_list[o]
    if bo==0.0:
        balances_copy_1=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_1=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_1=array(prices[0],prices[1],prices[2])
        B,L=compute_B_and_L(balances_copy_1, LP_tokens_issued_copy_1, prices_copy_1)

        ao=lpt*B/L
        aol[0]=ao
        print(f'Liquidity provider receives 0 token {o}.')
        a_remaining[0]=ao
        # continue withdrawal with other token

    if bo!=0.0:
        balances_copy_2=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_2=array(prices[0],prices[1],prices[2])
        imb_ratios_array=imbalance_ratios(balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2)
        ro=imb_ratios_array[o]
        Lo=LP_tokens_list[o]
        ao=lpt*bo/(Lo*ro)
        aol[0]=ao
        if lpt<Lo:
            M1=[0.0]
            if ro<=1.0-delta:
                M1[0]=lpt*bo/Lo
            if ro>1.0-delta:
                balances_copy_3=array(balances[0],balances[1],balances[2])
                LP_tokens_issued_copy_3=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
                prices_copy_3=array(prices[0],prices[1],prices[2])
                B,L=compute_B_and_L(balances_copy_3, LP_tokens_issued_copy_3, prices_copy_3)

                M1[0]=bo-(1.0-delta)*(Lo-lpt)*B/L
            if ao<=M1[0]:
                balances_list[o]-=ao
                print(f'Liquidity provider receives {ao} token {o}.')
                LP_tokens_list[o]-=lpt
                return ao
            if ao>M1[0]:
                balances_list[o]-=M1[0]
                print(f'Liquidity provider receives {M1[0]} token {o}.')
                a_remaining[0]=ao-M1[0]
                # continue withdrawal with other token

        else:
            ao=bo/ro
            aol[0]=ao
            if ao<=bo:
                balances_list[o]-=ao
                print(f'Liquidity provider receives {ao} token {o}.')
                LP_tokens_list[o]-=lpt
                return ao
            if ao>bo:
                balances_list[o]=0.0
                print(f'Liquidity provider receives {bo} token {o}.')
                a_remaining[0]=ao-bo
                # continue withdrawal with other token

    # withdrawal continues with another token
    # employs remaining amount
    Loop=[True]

    prev_index=[o]

    price_list=list(prices)

    while a_remaining[0]!=0.0 and Loop[0]:
        balances_copy_4=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_4=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_4=array(prices[0],prices[1],prices[2])
        imb_ratios_array=imbalance_ratios(balances_copy_4, LP_tokens_issued_copy_4, prices_copy_4)
        imb_ratios=list(imb_ratios_array)
        #k=imb_ratios.index(max([x for x in imb_ratios if x >= 0.0]))
        #index is not implemented yet, max does not work with lists
        maximum_imb_ratio=0.0
        max_imb_ratio_list=[0.0]
        mylist=[u8(0)]
        for j in [0,1,2]:
          imb_ratios_j=imb_ratios[j]
          print(imb_ratios)
          print(max_imb_ratio_list[0])
          if imb_ratios_j > max_imb_ratio_list[0]:
            mylist[0]=u8(j)
            max_imb_ratio_list[0]=imb_ratios_j
        k=mylist[0]
        a_rem=a_remaining[0]
        price_o=price_list[o]
        price_k=price_list[k]
        ak=a_rem*price_o/price_k
        bk=balances_list[k]
        Lk=LP_tokens_list[k]
        balances_copy_5=array(balances[0],balances[1],balances[2])
        LP_tokens_issued_copy_5=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
        prices_copy_5=array(prices[0],prices[1],prices[2])
        B,L=compute_B_and_L(balances_copy_5, LP_tokens_issued_copy_5, prices_copy_5)

        Mk=bk-(1.0-delta)*Lk*B/L
        if ak<=Mk:
            balances_list[k]-=ak
            print(f'Liquidity provider receives {ak} token {k}.')
            a_remaining[0]=0.0
        if ak>Mk:
            balances_list[k]-=Mk
            print(f'Liquidity provider receives {Mk} token {k}.')
            a_remaining[0]-=Mk*price_list[k]/price_list[o]
        if prev_index[0]==k:
            Loop[0]=False
            a_rem=a_remaining[0]
            price_o=price_list[o]
            price_k=price_list[k]
            ak=a_rem*price_o/price_k
            if ak<=balances_list[k]:
                balances_list[k]-=ak
                a_remaining[0]=0.0
            else:
                print(f'Remaining {a_remaining[0]} token {o}')
        prev_index[0]=k

    ao=aol[0]
    LP_tokens_list[o]-=lpt
    print("in:",lpt,"LP tokens","--- out:",ao,"token",o,"(in value)")

    return ao
