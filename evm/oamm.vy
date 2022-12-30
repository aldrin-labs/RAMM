# @version ^0.3.0

from vyper.interfaces import ERC20

interface LPToken:
    def totalSupply() -> uint256: view
    def mint(_to: address, _value: uint256) -> bool: nonpayable
    def burnFrom(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from : address, _to : address, _value : uint256) -> bool: nonpayable
    def transfer(_to : address, _value : uint256) -> bool: nonpayable
    def set_minter(_minter: address): nonpayable

# Constants

## Pool parameters

N : constant(uint8) = 3 # number of assets of the pool
BASE_FEE: constant(decimal) = 0.0008 # 0.08%
BASE_LEVERAGE: constant(decimal) = 100.0
PROTOCOL_FEE: constant(decimal) = 0.5 # 50% of collected BASE_FEEs go to the protocol
DELTA: constant(decimal) = 0.25 # maximum permitted deviation of the imbalance ratios from 1.0

## Conversion rates according to number of decimals of each token

LPTOKENS_DECIMALS: constant(uint8) = 10
RATE_10_DECIMALS: constant(decimal) = 10000000000.0   # 10**LPTOKENS_DECIMALS
LPTOKENS_FACTOR: constant(decimal) = RATE_10_DECIMALS  # 10**LPTOKENS_DECIMALS
CONVERSION_RATES: constant(decimal[N]) = [RATE_10_DECIMALS, RATE_10_DECIMALS, RATE_10_DECIMALS]

## Other constants
LIST_OF_ZEROES: constant(decimal[N]) = [0.0,0.0,0.0] # modify according to value of N


# State variables

balances: public(decimal[N])
lp_tokens_issued: decimal[N]
owner: public(address)
assets: public(address[N])
lptokens: public(LPToken[N])
contract_address: public(address)
fee_address: address

# Events

event Log_msg:
    message: String[100]

event Log_address:
    message: address

event Log_uint_value:
    message: String[100]
    value: uint256

event Log_value:
    message: String[100]
    value: decimal

event Log_list:
    message: String[100]
    value: decimal[N]

event Log_BL:
    message: String[10]
    value1: decimal
    value2: decimal

event Log_pool_state:
    message1: String[100]
    value1: decimal[N]
    message2: String[100]
    value2: decimal[N]
    message3: String[100]
    value3: decimal[N]

event Log_trade_output:
    amount_in: decimal
    amount_out: decimal
    protocol_fee: decimal
    execute_trade: bool

event Log_deposit:
    amount: decimal
    amount_lp_tokens: decimal

event Log_withdrawal:
    amount_lp_tokens: decimal
    amounts: decimal[N]

# Structs

struct TradeOutput:
    amount: decimal
    protocol_fee: decimal
    execute_trade: bool

struct WithdrawalOutput:
    amounts: decimal[N]
    value: decimal
    remaining: decimal



@external
def __init__(_owner: address, assetslist: address[N], lptokenslist: address[N]):
    self.owner=_owner
    for j in range(N):
        assert assetslist[j] != ZERO_ADDRESS, "Invalid asset address"
    self.assets=assetslist
    for j in range(N):
        self.lptokens[j] = LPToken(lptokenslist[j])
    self.balances = LIST_OF_ZEROES
    self.lp_tokens_issued = LIST_OF_ZEROES
    self.fee_address = _owner
    #self.contract_address = 0x9E4c14403d7d9A8A782044E86a93CAE09D7B2ac9

@external
def initialize_mints(_contract_address: address):
    assert msg.sender == self.owner, "You are not the pool owner."
    for j in range(N):
        self.lptokens[j].set_minter(_contract_address)
    self.contract_address = _contract_address

######################## Math ########################


@internal
def weights(balances: decimal[N], prices: decimal[N]) -> decimal[N]:
    """Returns a list with the weights of the tokens with respect to the current prices."""
    B: decimal = 0.0
    W: decimal[N] = LIST_OF_ZEROES
    for j in range(N):
        B+=prices[j]*balances[j]
    for j in range(N):
        W[j]=prices[j]*balances[j]/B
    return W

@internal
def compute_B_and_L(balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> decimal[2]:
    """Returns a tuple with the values of B and L"""
    B: decimal = 0.0
    L: decimal = 0.0
    for j in range(N):
        B+=prices[j]*balances[j]
        L+=prices[j]*lp_tokens_issued[j]
    #log Log_BL("BL",B,L)
    return [B,L]

@internal
def imbalance_ratios(balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> decimal[N]:
    """Returns a list with the imbalance ratios of the tokens."""
    Imb: decimal[N] = LIST_OF_ZEROES
    BL: decimal[2] = self.compute_B_and_L(balances, lp_tokens_issued, prices)
    B: decimal = BL[0]
    L: decimal = BL[1]
    for j in range(N):
        if lp_tokens_issued[j] != 0.0:
            Imb[j]=(balances[j]*L)/(B*lp_tokens_issued[j])
        else:
            Imb[j]=-1.0
    return Imb


@internal
def check_imbalance_ratios(balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N], i: uint8, o: uint8, ai: decimal, ao: decimal, pr_fee: decimal) -> bool:
    ### We check imbalance ratios
    balances_before: decimal[N] = balances # check that the list is copied and that the original list is not modified
    balances_after: decimal[N] = balances  # check that the list is copied and that the original list is not modified
    balances_after[i]=balances[i]+ai-pr_fee
    balances_after[o]=balances[o]-ao
    imb_ratios_before_trade: decimal[N] = self.imbalance_ratios(balances_before, lp_tokens_issued, prices)
    imb_ratios_after_trade: decimal[N] = self.imbalance_ratios(balances_after, lp_tokens_issued, prices)

    #print(f'Imbalance ratios after trade: {imb_ratios_after_trade}')

    if (imb_ratios_after_trade[o]<1.0-DELTA and imb_ratios_after_trade[o]<imb_ratios_before_trade[o]) or (imb_ratios_after_trade[i]>1.0+DELTA and imb_ratios_after_trade[i]>imb_ratios_before_trade[i]):
        return False
    return True

@internal
def funct_adjust_leverage_parameter(x: decimal) -> decimal:
    """Base function that adjusts the leverage parameter."""
    return x*x*x

@internal
def funct_adjust_BASE_FEE(x: decimal) -> decimal:
    """Base function that adjusts the BASE_FEE."""
    return x*x*x

@internal
def scaled_fee_and_leverage(balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N], i: uint8, o: uint8) -> decimal[2]:
    """Returns the scaled BASE_FEE and leverage parameter for a trade where token i goes into the pool and
    token o goes out of the pool."""
    imbalance: decimal[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
    #log Log_list('Imbalance ratios:',imbalance)
    scaled_BASE_FEE: decimal = self.funct_adjust_BASE_FEE(imbalance[i])/self.funct_adjust_BASE_FEE(imbalance[o])*BASE_FEE
    scaled_leverage: decimal = self.funct_adjust_leverage_parameter(imbalance[o])/self.funct_adjust_leverage_parameter(imbalance[i])*BASE_LEVERAGE
    return [scaled_BASE_FEE,scaled_leverage]

@internal
def abs_dec(x: decimal) -> decimal:
    """Returns the absolute value of x"""
    if x>= 0.0:
        return x
    else:
        return -1.0*x


@internal
def pow_n(x: decimal, n: int256) -> decimal:
    """Computes x^n, where n is a non-negative integer."""
    assert n>=0, "The parameter n must be a positive integer."
    assert n<=20, "The parameter n is too big."
    m: int256 = n
    result: decimal = 1.0
    a: decimal = x
    #while m!=0:  # while is not supported in Vyper
    # We can find an upper bound for n (should be n<=20)
    # and then hard code number_of loops as
    # number_of_loops = floor(log_2(n))+1 .
    # For example, if the upper bound for n is 20, a number of loops equal to 5 should work.
    #number_of_loops: int256 = n
    #for j in range(number_of_loops):
    for j in range(5):
        if m%2 == 1:
            result=result*a
        a=a*a
        m_dec: decimal = convert(m,decimal)
        m=floor(m_dec/2.0) #m=m//2
        if m==0:
            return result
    return result


@internal
def pow_d(x: decimal, a: decimal) -> decimal:
    """Computes x^a, where a is a real number between 0 and 1."""
    # We will use a Taylor series. The taylor series converges for x in (0,2).
    # If the leverage parameter k is greater 11 then in the formula of Ai employs exponentiation
    # with 1<x<1.1 .
    # On the other hand, in the formula for Ao, we employ exponentiation with 0<x<1.
    # In addition, if Ai<kBi/2 then we use an x with 1/2<x<1.
    # Thus, we can find a lower bound for the number of iterations to obtain the desired precision.
    # Tasks:
    # **** compute necessary number of iterations to obtain the desired precision.
    # **** write mathematical explanation with proofs.


    if x<0.0 or x>2.0:
        #print("Invalid parameter x")
        return 0.0
    if x<0.6666666666 or x>1.5:
        #print("The parameter x given could give a result with bad precision. Try with x in [2/3,1.5].")
        return 0.0
    result: decimal = 1.0 # first partial sum of the series
    n: decimal = 0.0
    tn: decimal = 1.0 # n-th term (for n=0 here)

    #steps_bound: uint8 =30 # gives precision of 0.1**10 for 2/3<x<1.5 and 0<a<1.
    #for j in range(steps_bound):
    for j in range(30):
        tn1: decimal = tn*(a-n)*(x-1.0)/(n+1.0)  #(n+1)-th term
        result+=tn1
        n+=1.0
        tn=tn1
        if self.abs_dec(tn) < 0.0000000001 : # this number is 0.1**10.0 or 1x10^(-10) :
            # abs(tn) gives an approximation of the precision.
            # If abs(tn) is small we can end the loop.
            return result
    return result

@internal
def power(x: decimal, a: decimal) -> decimal:
    n: int256 = floor(a)
    floor_a: decimal = convert(floor(a), decimal)
    b: decimal = a-floor_a
    return self.pow_n(x,n)*self.pow_d(x,b)

@internal
def trade_i(i: uint8, o: uint8, ai: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> TradeOutput :
    """Performs a trade where an amount ai of token i goes into the pool
    and token o goes out of the pool. Returns the amount ao of token o that goes
    out of the pool, the BASE_FEE that is charged and a boolean that indicates if the trade has to be executed or not."""
    # We check conditions first.
    if lp_tokens_issued[i]==0.0:
        #if Verbose: print(f'Trade not allowed. No LP {self.labels[i]} tokens in circulation.')
        return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})
    if balances[o]==0.0:
        #if Verbose: print(f"The trade can't be performed. No token {self.labels[o]} in the pool.")
        return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})
    # First we update the weights
    W: decimal[N] = self.weights(balances, prices)
    # We divide into different cases
    if balances[i]==0.0:
        ao: decimal = (1.0-BASE_FEE)*ai*prices[i]/prices[o]
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        return TradeOutput({amount: ao, protocol_fee: pr_fee, execute_trade: execute})
    if lp_tokens_issued[o]==0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        leverage: decimal = BASE_LEVERAGE
        trading_fee: decimal = BASE_FEE
        bi: decimal = balances[i]*leverage
        wi: decimal = W[i]
        bo: decimal = balances[o]*leverage
        wo: decimal = W[o]
        ao: decimal = bo*(1.0-self.power(bi/(bi+(1.0-BASE_FEE)*ai),wi/wo))
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        return TradeOutput({amount: ao, protocol_fee: pr_fee, execute_trade: execute})
    if lp_tokens_issued[o]!=0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        # We check imbalance ratio of token o
        imb_ratios_initial_o: decimal = self.imbalance_ratios(balances, lp_tokens_issued, prices)[o]
        if imb_ratios_initial_o<1.0-DELTA:
            #print(f'Imbalance ratio of Token {o} too low.')
            return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})
        ## Now we update the fee and the leverage parameter
        FeeLev: decimal[2] = self.scaled_fee_and_leverage(balances, lp_tokens_issued, prices,i,o)
        trading_fee: decimal = FeeLev[0]
        #log Log_value("trading BASE_FEE:", trading_fee)
        leverage: decimal = FeeLev[1]
        #log Log_value("leverage:", leverage)
        ## Now we compute the amounts of the trade
        bi: decimal = balances[i]*leverage
        wi: decimal = W[i]
        bo: decimal = balances[o]*leverage
        wo: decimal = W[o]
        #log Log_value("base:", bi/(bi+(1.0-trading_fee)*ai))
        #log Log_value("exp:", wi/wo)
        #log Log_value("power:", self.power(bi/(bi+(1.0-trading_fee)*ai),wi/wo))
        ao: decimal = bo*(1.0-self.power(bi/(bi+(1.0-trading_fee)*ai),wi/wo))
        #log Log_value("ao:", ao)
        pr_fee: decimal = PROTOCOL_FEE*trading_fee*ai
        if ao>=balances[o]:
            # We check if there is enough balance of token o.
            #print(f"Not enough balance of token {o}.")
            return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao, pr_fee)
        return TradeOutput({amount: ao, protocol_fee:pr_fee, execute_trade: execute})
    return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})

@internal
def trade_o(i: uint8,o: uint8,ao: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> TradeOutput :
    """Performs a trade where an amount ao of token o goes out of the pool
    and token i goes into the pool. Returns the amount ai of token i that goes
    into the pool, the BASE_FEE that is charged and a boolean that indicates if the trade has to be executed or not."""
    if ao<=0.0:
        #print(f"Invalid amount of token {o}")
        return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})
    # We check conditions first.
    if lp_tokens_issued[i]==0.0:
        #print(f'Trade not allowed. No LP {i} tokens in circulation.')
        return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})
    if ao>=balances[o]:
        # We check if there is enough balance of token o.
        # This also prevents the balance of token 0 from being zero.
        # print(f"Not enough balance of token {o}")
        return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})
    # First we update the weights
    W: decimal[N] = self.weights(balances, prices)
    # We divide into different cases
    if balances[i]==0.0:
        ai: decimal = ao*prices[o]/prices[i]/(1.0-BASE_FEE)
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute})
    if lp_tokens_issued[o]==0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        leverage: decimal = BASE_LEVERAGE
        bi: decimal = balances[i]*leverage
        wi: decimal = W[i]
        bo: decimal = balances[o]*leverage
        wo: decimal = W[o]
        ai: decimal = bi/(1.0-BASE_FEE)*(self.power(bo/(bo-ao),wo/wi)-1.0)
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute})

    if lp_tokens_issued[o]!=0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        # We check imbalance ratio of token o
        imb_ratios_initial: decimal[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
        if imb_ratios_initial[o]<1.0-DELTA:
            #print(f'Imbalance ratio of {o} too low.')
            return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})

        # Now we update the fee and the leverage parameter
        FeeLev: decimal[2] = self.scaled_fee_and_leverage(balances, lp_tokens_issued, prices,i,o)
        trading_fee: decimal = FeeLev[0]
        leverage: decimal = FeeLev[1]
        # Now we perform the trade
        bi: decimal = balances[i]*leverage
        wi: decimal = W[i]
        bo: decimal = balances[o]*leverage
        wo: decimal = W[o]
        ai: decimal = bi/(1.0-trading_fee)*(self.power(bo/(bo-ao),wo/wi)-1.0)
        pr_fee: decimal = PROTOCOL_FEE*trading_fee*ai
        # We check imbalance ratios
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute})
    return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False})

@internal
def single_asset_deposit(i: uint8, ai: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N])-> decimal:
    """Performs a single asset deposit of amount i of token i.
    Returns the amount of LP tokens that must be given to the liquidity provider.
    """
    # we divide into cases
    if lp_tokens_issued[i]==0.0 or (lp_tokens_issued[i]!=0.0 and balances[i]==0.0):
        BL: decimal[2] = self.compute_B_and_L(balances, lp_tokens_issued, prices)
        B: decimal = BL[0]
        L: decimal = BL[1]
        if B==0.0:
            lpt: decimal = ai
            #print("in:",ai,"Token",i,"--- out:",lpt,"LP tokens")
            return lpt
        if B!=0.0:
            lpt: decimal = ai*L/B
            #print("in:",ai,"Token",i,"--- out:",lpt,"LP tokens")
            return lpt

    if lp_tokens_issued[i]!=0.0 and balances[i]!=0.0:
        imb_ratios: decimal[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
        bi: decimal = balances[i]
        ri: decimal = imb_ratios[i]
        lpt: decimal = (ai/bi)*ri*lp_tokens_issued[i]
        #print("in:",ai,"Token",i,"--- out:",lpt,"LP tokens")
        return lpt

    return 0.0


@internal
def single_asset_withdrawal(o: uint8, lpt: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> WithdrawalOutput:
    """ Given an amount of LP tokens and its type o,
    returns the amounts of each token to be given to the LP,
    the value given to the LP in terms of token o, and the remaining
    amount of token o to be given to the LP (if any) in case the
    process could not be completed.
    """

    amounts_out: decimal[N] = LIST_OF_ZEROES
    a_remaining: decimal = 0.0
    bo: decimal = balances[o]
    imb_ratios: decimal[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
    ao: decimal = 0.0

    if bo==0.0:
        BL: decimal[2] = self.compute_B_and_L(balances, lp_tokens_issued, prices)
        B: decimal = BL[0]
        L: decimal = BL[1]
        ao = lpt*B/L
        #print(f'Liquidity provider receives 0 token {o}.')
        a_remaining = ao
        # continue withdrawal with other token

    if bo!=0.0:
        ro: decimal = imb_ratios[o]
        Lo: decimal = lp_tokens_issued[o]
        ao = lpt*bo/(Lo*ro)
        if lpt<Lo:
            M1: decimal = 0.0
            if ro<=1.0-DELTA:
                M1 = lpt*bo/Lo
            if ro>1.0-DELTA:
                BL: decimal[2] = self.compute_B_and_L(balances, lp_tokens_issued, prices)
                B: decimal = BL[0]
                L: decimal = BL[1]
                M1=bo-(1.0-DELTA)*(Lo-lpt)*B/L
            if ao<=M1:
                #balances[o]-=ao
                amounts_out[o]+=ao
                #print(f'Liquidity provider receives {ao} token {o}.')
                #lp_tokens_issued[o]-=lpt
                return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: 0.0})
            if ao>M1:
                #balances[o]-=M1
                amounts_out[o]+=M1
                #print(f'Liquidity provider receives {M1} token {o}.')
                a_remaining=ao-M1
                imb_ratios[o]=0.0 # to avoid choosing token o again in the next steps
                # continue withdrawal with other token

        else:
            ao=bo/ro
            if ao<=bo:
                #balances[o]-=ao
                amounts_out[o]+=ao
                #print(f'Liquidity provider receives {ao} token {o}.')
                #lp_tokens_issued[o]-=lpt
                return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: 0.0})
            if ao>bo:
                #balances[o]=0.0
                amounts_out[o]+=bo
                #print(f'Liquidity provider receives {bo} token {o}.')
                a_remaining=ao-bo
                imb_ratios[o]=0.0 # to avoid choosing token o again in the next steps
                # continue withdrawal with other token

    # withdrawal continues with another token
    # employs remaining amount

    Loop: bool = True
    prev_index: uint8 = o
    max_imb_ratio: decimal = 0.0
    index: uint8 = o

    for j in range(N):
        if a_remaining!=0.0 and Loop:
            # k=imb_ratios.index(max([x for x in imb_ratios if x >= 0.0]))
            # list comprehensions are not implemented in Vyper
            # index is not implemented yet, max does not work with lists

            # we compute the maximum among the remaining imbalance ratios
            max_imb_ratio = 0.0
            #print(imb_ratios)
            for l in range(N):
                if imb_ratios[l] > max_imb_ratio:
                    index = l
                    max_imb_ratio=imb_ratios[l]
                    #print(max_imb_ratio)
            k: uint8 = index

            if k==prev_index:
                Loop=False

            if k!=prev_index:
                price_o: decimal = prices[o]
                price_k: decimal = prices[k]
                ak: decimal = a_remaining*price_o/price_k
                bk: decimal = balances[k]
                Lk: decimal = lp_tokens_issued[k]
                BL: decimal[2] = self.compute_B_and_L(balances, lp_tokens_issued, prices)
                B: decimal = BL[0]
                L: decimal = BL[1]
                Mk: decimal = bk-(1.0-DELTA)*Lk*B/L
                if ak<=Mk:
                    amounts_out[k]+=ak
                    #print(f'Liquidity provider receives {ak} token {k}.')
                    a_remaining=0.0
                if ak>Mk:
                    amounts_out[k]+=Mk
                    #print(f'Liquidity provider receives {Mk} token {k}.')
                    a_remaining-=Mk*prices[k]/prices[o]
                prev_index=k

    return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: a_remaining})

@internal
def decimal_to_uint_lptokens(x: decimal) -> uint256:
    if x>=0.0:
        return convert(floor(x*LPTOKENS_FACTOR),uint256)
    return 0

@internal
def decimal_to_uint_assets(x: decimal, i: uint8) -> uint256:
    if x>=0.0:
        factor: decimal = CONVERSION_RATES[i]
        return convert(floor(x*factor),uint256)
    return 0

######################## OAMM ########################



@external
def pool_state(prices: decimal[N]):
    Imb: decimal[N] = self.imbalance_ratios(self.balances, self.lp_tokens_issued, prices)
    log Log_pool_state('Balances:',self.balances,'LP tokens issued:',self.lp_tokens_issued,'Imbalance ratios:',Imb)

@external
def trade_amount_in(i: uint8, o: uint8, ai: decimal, prices: decimal[N]):
    ## *** remove prices (take from oracle)
    trade: TradeOutput = self.trade_i(i, o, ai, self.balances, self.lp_tokens_issued, prices)
    if trade.execute_trade:
        #log Log_msg("1.")
        input_asset: address = self.assets[i]
        amount_in: uint256 = self.decimal_to_uint_assets(ai, i)
        amount_fee: uint256 = self.decimal_to_uint_assets(trade.protocol_fee, i)
        LPToken(input_asset).transferFrom(msg.sender,self.contract_address,amount_in)
        LPToken(input_asset).transfer(self.fee_address,amount_fee)
        # For the final version we will need to call ERC20 instead of LPToken, as in the line below, which serves as an example.
        #ERC20(input_asset).transferFrom(msg.sender,self.contract_address,amount_in)
        output_asset: address = self.assets[o]
        amount_out: uint256 = self.decimal_to_uint_assets(trade.amount, o)
        #log Log_msg("2.")
        #ERC20(output_asset).transferFrom(self.contract_address,msg.sender,amount_out)
        LPToken(output_asset).transfer(msg.sender,amount_out)
        self.balances[i]+=ai-trade.protocol_fee
        self.balances[o]-=trade.amount
        log Log_trade_output(ai,trade.amount,trade.protocol_fee,trade.execute_trade)
    else:
        log Log_msg("Trade not executed.")

@external
def trade_amount_out(i: uint8, o: uint8, ao: decimal, prices: decimal[N]):
    ## *** remove prices (take from oracle)
    trade: TradeOutput = self.trade_o(i, o, ao, self.balances, self.lp_tokens_issued, prices)
    if trade.execute_trade:
        ai: decimal = trade.amount-trade.protocol_fee
        input_asset: address = self.assets[i]
        amount_in: uint256 = self.decimal_to_uint_assets(trade.amount, i)
        amount_fee: uint256 = self.decimal_to_uint_assets(trade.protocol_fee, i)
        # For the final version we will need to call ERC20 instead of LPToken, as in the line below, which serves as an example.
        #ERC20(input_asset).transferFrom(msg.sender,self.contract_address,amount_in)
        LPToken(input_asset).transferFrom(msg.sender,self.contract_address,amount_in)
        LPToken(input_asset).transfer(self.fee_address,amount_fee)
        output_asset: address = self.assets[o]
        amount_out: uint256 = self.decimal_to_uint_assets(ao, o)
        #ERC20(output_asset).transferFrom(self.contract_address,msg.sender,amount_out)
        LPToken(output_asset).transfer(msg.sender,amount_out)
        self.balances[i]+=ai
        self.balances[o]-=ao
        log Log_trade_output(trade.amount,ao,trade.protocol_fee,trade.execute_trade)
    else:
        log Log_msg("Trade not executed.")

@external
def liquidity_deposit(i: uint8, ai: decimal, prices: decimal[N]):
    ## *** remove prices (take from oracle)
    lpt: decimal = self.single_asset_deposit(i, ai, self.balances, self.lp_tokens_issued, prices)
    if lpt == 0.0:
        log Log_msg("Deposit not executed.")
    else:
        # transfer amount of token i
        input_asset: address = self.assets[i]
        amount_in: uint256 = self.decimal_to_uint_assets(ai, i)
        LPToken(input_asset).transferFrom(msg.sender,self.contract_address,amount_in)
        # For the final version we will need to call ERC20 instead of LPToken, as in the line below, which serves as an example.
        #ERC20(input_asset).transferFrom(msg.sender,self.contract_address,amount_in)
        self.balances[i]+=ai
        # mint corresponding LP token
        lptok: LPToken = self.lptokens[i]
        mint_amount: uint256 = self.decimal_to_uint_lptokens(lpt)
        lptok.mint(msg.sender,mint_amount)
        self.lp_tokens_issued[i]+=lpt
        log Log_deposit(ai, lpt)

@external
def liquidity_withdrawal(o: uint8, lpt: decimal, prices: decimal[N]):
    ## *** remove prices (take from oracle)
    out: WithdrawalOutput = self.single_asset_withdrawal(o, lpt, self.balances, self.lp_tokens_issued, prices)
    # burn corresponding amount of lp tokens
    lptok: LPToken = self.lptokens[o]
    lpt_amount: decimal = lpt*(out.value-out.remaining)/out.value
    burn_amount: uint256 = self.decimal_to_uint_lptokens(lpt_amount)
    lptok.burnFrom(msg.sender,burn_amount)
    self.lp_tokens_issued[o]-=lpt_amount
    # deposit corresponding amount of each token
    for j in range(N):
        if out.amounts[j] != 0.0:
            # transfer to liquidity provider
            output_asset: address = self.assets[j]
            amount_out: uint256 = self.decimal_to_uint_assets(out.amounts[j], j)
            # For the final version we will need to call ERC20 instead of LPToken, as in the line below, which serves as an example.
            #ERC20(output_asset).transfer(msg.sender,amount_out)
            LPToken(output_asset).transfer(msg.sender,amount_out)
            self.balances[j]-=out.amounts[j]
    log Log_withdrawal(lpt, out.amounts)


