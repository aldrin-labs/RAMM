# @version ^0.3.0

from vyper.interfaces import ERC20


interface Token:
    def balanceOf(_owner: address) -> uint256: view
    def transferFrom(_from : address, _to : address, _value : uint256) -> bool: nonpayable
    def transfer(_to : address, _value : uint256) -> bool: nonpayable

interface LPToken:
    def totalSupply() -> uint256: view
    def balanceOf(_owner: address) -> uint256: view
    def mint(_to: address, _value: uint256) -> bool: nonpayable
    def burnFrom(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from : address, _to : address, _value : uint256) -> bool: nonpayable
    def transfer(_to : address, _value : uint256) -> bool: nonpayable
    def set_minter(_minter: address): nonpayable

interface AggregatorV3Interface:
    def decimals() -> uint8: view
    def description() -> String[1000]: view
    def version() -> uint256: view
    def getRoundData(_roundId: uint80) -> (uint80, int256, uint256, uint256, uint80): view
    def latestRoundData() -> (uint80, int256, uint256, uint256, uint80): view


# Constants

## Pool parameters

N : constant(uint8) = 3 # number of assets of the pool
BASE_FEE: constant(decimal) = 0.0008 # 0.08%
BASE_LEVERAGE: constant(decimal) = 100.0
PROTOCOL_FEE: constant(decimal) = 0.5 # 50% of collected BASE_FEEs go to the protocol
DELTA: constant(decimal) = 0.25 # maximum permitted deviation of the imbalance ratios from 1.0
MINIMUM_TRADE_AMOUNTS: constant(decimal[N]) = [0.01,1.0,1.0] # Initial minimum amounts for trades

## Conversion rates according to number of decimals of each token

LPTOKENS_DECIMALS: constant(uint8) = 10
RATE_6_DECIMALS: constant(decimal) = 1000000.0   #
RATE_10_DECIMALS: constant(decimal) = 10000000000.0   # 10**LPTOKENS_DECIMALS
LPTOKENS_FACTOR: constant(decimal) = RATE_10_DECIMALS  # 10**LPTOKENS_DECIMALS
CONVERSION_RATES: constant(decimal[N]) = [RATE_10_DECIMALS, RATE_10_DECIMALS, RATE_10_DECIMALS]

## Other constants
LIST_OF_ZEROES: constant(decimal[N]) = [0.0,0.0,0.0] # modify according to the value of N
LIST_OF_TRUE: constant(bool[N]) = [True,True,True] # modify according to the value of N


# State variables

balances: public(decimal[N])
lp_tokens_issued: decimal[N]
owner: public(address)
assets: public(address[N])
lptokens: public(LPToken[N])
price_feeds: AggregatorV3Interface[N]
fee_address: address
deposits_enabled: public(bool[N])
minimum_trade_amounts: public(decimal[N])

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
    message: String[100]

struct WithdrawalOutput:
    amounts: decimal[N]
    value: decimal
    remaining: decimal


######################## Pool initialization and management ########################

@external
def __init__(_owner: address, assetslist: address[N], lptokenslist: address[N], _price_feed_address: address[N], fee_collector: address):
    self.owner=_owner
    for j in range(N):
        assert assetslist[j] != ZERO_ADDRESS, "Invalid asset address"
    self.assets=assetslist
    for j in range(N):
        self.lptokens[j] = LPToken(lptokenslist[j])
        self.price_feeds[j] = AggregatorV3Interface(_price_feed_address[j])
    self.balances = LIST_OF_ZEROES
    self.lp_tokens_issued = LIST_OF_ZEROES
    self.fee_address = fee_collector
    self.deposits_enabled = LIST_OF_TRUE
    self.minimum_trade_amounts = MINIMUM_TRADE_AMOUNTS

@external
def set_owner(_owner: address):
    assert msg.sender == self.owner, "You do not have permission to set a new owner."
    self.owner = _owner

@external
def set_new_fee_collector(fee_collector: address):
    assert msg.sender == self.owner, "You do not have permission to set a new fee collector."
    self.fee_address = fee_collector

@external
def disable_deposits(i: uint8):
    assert msg.sender == self.owner, "You do not have permission to disable deposits."
    self.deposits_enabled[i] = False

@external
def enable_deposits(i: uint8):
    assert msg.sender == self.owner, "You do not have permission to enable deposits."
    self.deposits_enabled[i] = True

@external
def set_new_price_feed(i: uint8, price_feed_address: address):
    assert msg.sender == self.owner, "You do not have permission to set a new price feed."
    self.price_feeds[i] = AggregatorV3Interface(price_feed_address)

@external
def set_new_minimum_trade_amount(i: uint8, amount: decimal):
    assert msg.sender == self.owner, "You do not have permission to set new minimum trade amounts."
    assert amount >= 0.0, "The minimum trading amount must be non-negative."
    self.minimum_trade_amounts[i] = amount


#@external
#@view
#def log_prices():
    #for j in range(N):
        #price: int256 = self.get_latest_price(j)
        #price_decimal: decimal = self.price_to_decimal(price)
        #log Log_value("Price:", price_decimal)

@internal
@view
def get_latest_price(i: uint8) -> int256:
    a: uint80 = 0
    price: int256 = 0
    b: uint256 = 0
    c: uint256 = 0
    d: uint80 = 0
    (a, price, b, c, d) = self.price_feeds[i].latestRoundData()
    #log Log_uint_value("Price:", convert(price,uint256))
    #price_decimal: decimal = self.price_to_decimal(price)
    #log Log_value("Price:", price_decimal)
    return price



######################## Math ########################

###### Numbers ######

@internal
@view
def abs_dec(x: decimal) -> decimal:
    """Returns the absolute value of x"""
    if x>= 0.0:
        return x
    else:
        return -1.0*x


@internal
@view
def pow_n(x: decimal, n: int256) -> decimal:
    """Computes x^n, where n is a non-negative integer."""
    assert n>=0, "The parameter n must be a positive integer."
    #log Log_uint_value("n",convert(n,uint256)) # ***
    assert n<=127, "The parameter n is too big."
    m: int256 = n
    result: decimal = 1.0
    a: decimal = x
    #while m!=0:  # while is not supported in Vyper
    # We can find an upper bound for n (should be n<=100 if the weights are between 0.01 and 1. )
    # and then hard code number_of loops as
    # number_of_loops = floor(log_2(n))+1 .
    # For example, if the upper bound for n is 127, a number of loops equal to 7 works,
    # since we need 7 digits to write n in base 2.
    #number_of_loops: int256 = n
    #for j in range(number_of_loops):
    for j in range(7):
        if m%2 == 1:
            result=result*a
        a=a*a
        m_dec: decimal = convert(m,decimal)
        m=floor(m_dec/2.0) #m=m//2
        if m==0:
            return result
    # We can throw an error message here, since the result must be reached within the for loop.
    return result


@internal
@view
def pow_d(x: decimal, a: decimal) -> decimal:
    """Computes x^a, where a is a real number between 0 and 1."""
    # We will use a Taylor series. The taylor series converges for x in (0,2).
    # If the leverage parameter k is greater than 11 then the formula of Ai employs exponentiation
    # with 1<x<1.1 .
    # On the other hand, in the formula for Ao, we employ exponentiation with 0<x<1.
    # In addition, if Ai<kBi/2 then we use an x with 1/2<x<1.
    # Thus, we can find a lower bound for the number of iterations to obtain the desired precision.
    # Tasks:
    # **** compute necessary number of iterations to obtain the desired precision.
    # **** write mathematical explanation with proofs.

    assert (0.6666666666<=x and x<=1.5), "The base of the exponentiation is out of the desired bounds."

    #if x<0.0 or x>2.0:
        ##print("Invalid parameter x")
        #return 0.0
    #if x<0.6666666666 or x>1.5:
        ##print("The parameter x given could give a result with bad precision. Try with x in [2/3,1.5].")
        #return 0.0

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
@view
def power(x: decimal, a: decimal) -> decimal:
    n: int256 = floor(a)
    floor_a: decimal = convert(floor(a), decimal)
    b: decimal = a-floor_a
    return self.pow_n(x,n)*self.pow_d(x,b)


@internal
@view
def decimal_to_uint_lptokens(x: decimal) -> uint256:
    if x>=0.0:
        return convert(floor(x*LPTOKENS_FACTOR),uint256)
    return 0

@internal
@view
def decimal_to_uint_assets(x: decimal, i: uint8) -> uint256:
    if x>=0.0:
        factor: decimal = CONVERSION_RATES[i]
        return convert(floor(x*factor),uint256)
    return 0

@internal
@view
def price_to_decimal(x: int256) -> decimal:
    if x>=0:
        return convert(x,decimal)/100000000.0
    return 0.0


###### Functions ######

@internal
@view
def weights(balances: decimal[N], prices: decimal[N]) -> decimal[N]:
    """Returns a list with the weights of the tokens with respect to the given prices."""
    B: decimal = 0.0
    W: decimal[N] = LIST_OF_ZEROES
    for j in range(N):
        B+=prices[j]*balances[j]
    for j in range(N):
        W[j]=prices[j]*balances[j]/B
    return W

@internal
@view
def compute_B_and_L(balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> decimal[2]:
    """Returns a list with the values of B and L."""
    B: decimal = 0.0
    L: decimal = 0.0
    for j in range(N):
        B+=prices[j]*balances[j]
        L+=prices[j]*lp_tokens_issued[j]
    #log Log_BL("BL",B,L)
    return [B,L]

@internal
@view
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
@view
def check_imbalance_ratios(balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N], i: uint8, o: uint8, ai: decimal, ao: decimal, pr_fee: decimal) -> bool:
    """ Checks if the imbalance ratios after a trade belong to the corresponding range (or if they are closer to the range than before the trade."""
    balances_before: decimal[N] = balances # check that the list is copied and that the original list is not modified
    balances_after: decimal[N] = balances  # check that the list is copied and that the original list is not modified
    balances_after[i]=balances[i]+ai-pr_fee
    balances_after[o]=balances[o]-ao
    imb_ratios_before_trade: decimal[N] = self.imbalance_ratios(balances_before, lp_tokens_issued, prices)
    imb_ratios_after_trade: decimal[N] = self.imbalance_ratios(balances_after, lp_tokens_issued, prices)

    if (imb_ratios_after_trade[o]<1.0-DELTA and imb_ratios_after_trade[o]<imb_ratios_before_trade[o]) or (imb_ratios_after_trade[i]>1.0+DELTA and imb_ratios_after_trade[i]>imb_ratios_before_trade[i]):
        return False
    return True

@internal
@view
def check_imbalance_ratios_message(execute: bool) -> String[100]:
    if execute == True:
        return "Trade executed."
    else:
        return "The trade was not executed because of pool imbalance."



@internal
@view
def funct_adjust_leverage_parameter(x: decimal) -> decimal:
    """Base function that adjusts the leverage parameter."""
    return x*x*x

@internal
@view
def funct_adjust_base_fee(x: decimal) -> decimal:
    """Base function that adjusts the base fee."""
    return x*x*x

@internal
@view
def scaled_fee_and_leverage(balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N], i: uint8, o: uint8) -> decimal[2]:
    """Returns the scaled base fee and leverage parameter for a trade where token i goes into the pool and
    token o goes out of the pool."""
    imbalance: decimal[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
    #log Log_list('Imbalance ratios:',imbalance)
    scaled_base_fee: decimal = self.funct_adjust_base_fee(imbalance[i])/self.funct_adjust_base_fee(imbalance[o])*BASE_FEE
    scaled_leverage: decimal = self.funct_adjust_leverage_parameter(imbalance[o])/self.funct_adjust_leverage_parameter(imbalance[i])*BASE_LEVERAGE
    return [scaled_base_fee,scaled_leverage]


@internal
@view
def trade_i(i: uint8, o: uint8, ai: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> TradeOutput :
    """
    Computes the paramters of a trade where an amount ai of token i goes into the pool
    and token o goes out of the pool. Returns the amount ao of token o that goes
    out of the pool, the base fee that is charged, a boolean that indicates if the trade has to be executed or not,
    and a message that explains why the the trade will not be executed, if that is the case.
    """

    # First we compute the weights.
    W: decimal[N] = self.weights(balances, prices)
    # We divide into different cases.
    if balances[i]==0.0:
        ao: decimal = (1.0-BASE_FEE)*ai*prices[i]/prices[o]
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ao, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    if lp_tokens_issued[o]==0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        leverage: decimal = BASE_LEVERAGE
        trading_fee: decimal = BASE_FEE
        bi: decimal = balances[i]*leverage
        wi: decimal = W[i]
        bo: decimal = balances[o]*leverage
        wo: decimal = W[o]
        #log Log_list("Weights", W) # ***
        ao: decimal = bo*(1.0-self.power(bi/(bi+(1.0-BASE_FEE)*ai),wi/wo))
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ao, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    if lp_tokens_issued[o]!=0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        # We check imbalance ratio of token o.
        imb_ratios_initial_o: decimal = self.imbalance_ratios(balances, lp_tokens_issued, prices)[o]
        if imb_ratios_initial_o<1.0-DELTA:
            # In this case the trade is not performed because the imbalance ratio of token o is too low.
            return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False, message: "The trade was not executed because the imbalance ratio of the out-token is too low."})
        # Now we update the fee and the leverage parameter.
        FeeLev: decimal[2] = self.scaled_fee_and_leverage(balances, lp_tokens_issued, prices,i,o)
        trading_fee: decimal = FeeLev[0]
        #log Log_value("trading fee:", trading_fee)
        leverage: decimal = FeeLev[1]
        #log Log_value("leverage:", leverage)
        ## Now we compute the amounts of the trade.
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
        # Now we check if there is enough balance of token o.
        if ao>balances[o] or (ao == balances[o] and lp_tokens_issued[o] != 0.0):
            # In this case the trade is not executed because there is not enough balance of token o.
            return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False, message: "The trade was not executed because there is not enough balance of the out-token."})
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao, pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ao, protocol_fee:pr_fee, execute_trade: execute, message: _message})
    return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False, message: "The trade was not executed."})

@internal
@view
def trade_o(i: uint8,o: uint8,ao: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> TradeOutput :
    """
    Computes the parameters of a trade where an amount ao of token o goes out of the pool
    and token i goes into the pool. Returns the amount ai of token i that goes
    into the pool, the base fee that is charged, a boolean that indicates if the trade has to be executed or not,
    and a message that explains why the the trade will not be executed, if that is the case.
    """

    # First we compute the weights.
    W: decimal[N] = self.weights(balances, prices)
    # Now we divide into different cases.
    if balances[i]==0.0:
        ai: decimal = ao*prices[o]/prices[i]/(1.0-BASE_FEE)
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    if lp_tokens_issued[o]==0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        leverage: decimal = BASE_LEVERAGE
        bi: decimal = balances[i]*leverage
        wi: decimal = W[i]
        bo: decimal = balances[o]*leverage
        wo: decimal = W[o]
        ai: decimal = bi/(1.0-BASE_FEE)*(self.power(bo/(bo-ao),wo/wi)-1.0)
        pr_fee: decimal = PROTOCOL_FEE*BASE_FEE*ai
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute, message: _message})

    if lp_tokens_issued[o]!=0.0 and balances[i]!=0.0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        # We check the imbalance ratio of token o.
        imb_ratios_initial: decimal[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
        if imb_ratios_initial[o]<1.0-DELTA:
            # In this case we do not execute the trade because the imbalance ratio of token o is too low.')
            return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False, message: "The trade was not executed because the imbalance ratio of the out-token is too low."})

        # Now we update the fee and the leverage parameter.
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
        # We check the imbalance ratios
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices,i,o,ai,ao,pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    return TradeOutput({amount: 0.0, protocol_fee:0.0, execute_trade: False, message: "The trade was not executed."})

@internal
@view
def single_asset_deposit(i: uint8, ai: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N])-> decimal:
    """
    Performs a single asset deposit of amount i of token i.
    Returns the amount of LP tokens that must be given to the liquidity provider.
    """
    # we divide into cases
    if lp_tokens_issued[i]==0.0 or (lp_tokens_issued[i]!=0.0 and balances[i]==0.0):
        BL: decimal[2] = self.compute_B_and_L(balances, lp_tokens_issued, prices)
        B: decimal = BL[0]
        L: decimal = BL[1]
        if B==0.0:
            lpt: decimal = ai
            return lpt
        if B!=0.0:
            lpt: decimal = ai*L/B
            return lpt

    if lp_tokens_issued[i]!=0.0 and balances[i]!=0.0:
        imb_ratios: decimal[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
        bi: decimal = balances[i]
        ri: decimal = imb_ratios[i]
        lpt: decimal = (ai/bi)*ri*lp_tokens_issued[i]
        return lpt

    return 0.0


@internal
@view
def single_asset_withdrawal(o: uint8, lpt: decimal, balances: decimal[N], lp_tokens_issued: decimal[N], prices: decimal[N]) -> WithdrawalOutput:
    """
    Given an amount of LP tokens and its type o,
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
        a_remaining = ao
        # The liquidity provider receives 0 token o.
        # We continue the withdrawal with another token.

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
                amounts_out[o]+=ao
                # The liquidity provider receives ao token o.
                return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: 0.0})
            if ao>M1:
                amounts_out[o]+=M1
                # The liquidity provider receives M1 token o
                a_remaining=ao-M1
                imb_ratios[o]=0.0 # to avoid choosing token o again in the next steps
                # We continue the withdrawal with another token.

        else:
            ao=bo/ro
            if ao<=bo:
                amounts_out[o]+=ao
                # The liquidity provider receives ao token o.
                return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: 0.0})
            if ao>bo:
                amounts_out[o]+=bo
                # The liquidity provider receives bo token o
                a_remaining=ao-bo
                imb_ratios[o]=0.0 # to avoid choosing token o again in the next steps
                # We continue the withdrawal with another token

    # Now the withdrawal continues with another token
    # and employs the remaining amount.

    Loop: bool = True
    prev_index: uint8 = o
    max_imb_ratio: decimal = 0.0
    index: uint8 = o

    for j in range(N):
        if a_remaining!=0.0 and Loop:
            # We compute the maximum among the remaining imbalance ratios.
            # We would like to do:
            # k=imb_ratios.index(max([x for x in imb_ratios if x >= 0.0]))
            # but list comprehensions are not implemented in Vyper.
            max_imb_ratio = 0.0
            for l in range(N):
                if imb_ratios[l] > max_imb_ratio:
                    index = l
                    max_imb_ratio=imb_ratios[l]
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
                    # The liquidity provider receives ak token k.
                    a_remaining=0.0
                if ak>Mk:
                    amounts_out[k]+=Mk
                    # The liquidity provider receives Mk token k.
                    a_remaining-=Mk*prices[k]/prices[o]
                prev_index=k

    return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: a_remaining})


######################## OAMM ########################

@external
def pool_state(prices: decimal[N]):
    # Here the prices are given manually to avoid paying fees for calling the oracle.
    # think about some restriction on trades (minimal amount, for example) to avoid losing money paying fees to call the oracle.
    Imb: decimal[N] = self.imbalance_ratios(self.balances, self.lp_tokens_issued, prices)
    log Log_pool_state('Balances:',self.balances,'LP tokens issued:',self.lp_tokens_issued,'Imbalance ratios:',Imb)

@external
def trade_amount_in(i: uint8, o: uint8, ai: decimal):
    assert ai >= 0.0, "The trading amount must be non-negative."
    assert ai >= self.minimum_trade_amounts[i], "The trading amount is too small."
    assert self.lp_tokens_issued[i] > 0.0, "The trade is not allowed because there are no LP tokens of the in-token type in circulation."
    assert self.balances[o] > 0.0, "The trade is not possible because there is currently no out-token left in the pool."
    # We take the market prices from the oracle
    prices: decimal[N] = LIST_OF_ZEROES
    for j in range(N):
        price_j_int256: int256 = self.get_latest_price(j)
        prices[j] = self.price_to_decimal(price_j_int256)
    # Now we compute the parameters of the trade
    trade: TradeOutput = self.trade_i(i, o, ai, self.balances, self.lp_tokens_issued, prices)
    if trade.execute_trade:
        # The following lines are not needed because this check is already performed in the self.trade_i function.
        #ao = trade.amount
        #assert ao<=self.balances[o], "The trade was not executed because there is not enough balance of the out-token."
        #if ao == self.balances[o]:
            #assert self.lp_tokens_issued[o] = 0.0, "The trade was not executed because there is not enough balance of the out-token."
        input_asset: address = self.assets[i]
        amount_in: uint256 = self.decimal_to_uint_assets(ai, i)
        amount_fee: uint256 = self.decimal_to_uint_assets(trade.protocol_fee, i)
        Token(input_asset).transferFrom(msg.sender,self,amount_in)
        Token(input_asset).transfer(self.fee_address,amount_fee)
        # For the final version we will need to call ERC20 perhaps instead of Token, as in the line below, which serves as an example.
        # Check this.
        #ERC20(input_asset).transferFrom(msg.sender,self,amount_in)
        output_asset: address = self.assets[o]
        amount_out: uint256 = self.decimal_to_uint_assets(trade.amount, o)
        #ERC20(output_asset).transferFrom(self,msg.sender,amount_out)
        Token(output_asset).transfer(msg.sender,amount_out)
        self.balances[i]+=ai-trade.protocol_fee
        self.balances[o]-=trade.amount
        log Log_trade_output(ai,trade.amount,trade.protocol_fee,trade.execute_trade)
    else:
        log Log_msg(trade.message)


@external
def trade_amount_out(i: uint8, o: uint8, ao: decimal):
    # First we perform some simple checks.
    assert ao >= 0.0, "The trading amount must be non-negative."
    assert ao >= self.minimum_trade_amounts[o], "The trading amount is too small."
    assert self.lp_tokens_issued[i] > 0.0, "The trade is not allowed because there are no LP tokens of the in-token type in circulation."
    assert ao<=self.balances[o], "The trade was not executed because there is not enough balance of the out-token."
    if ao == self.balances[o]:
        assert self.lp_tokens_issued[o] == 0.0, "The trade was not executed because there is not enough balance of the out-token."
    # We take the market prices from the oracle
    prices: decimal[N] = LIST_OF_ZEROES
    for j in range(N):
        price_j_int256: int256 = self.get_latest_price(j)
        prices[j] = self.price_to_decimal(price_j_int256)
    # Now we compute the parameters of the trade
    trade: TradeOutput = self.trade_o(i, o, ao, self.balances, self.lp_tokens_issued, prices)
    if trade.execute_trade:
        ai: decimal = trade.amount-trade.protocol_fee
        input_asset: address = self.assets[i]
        amount_in: uint256 = self.decimal_to_uint_assets(trade.amount, i)
        amount_fee: uint256 = self.decimal_to_uint_assets(trade.protocol_fee, i)
        # For the final version we will need to call ERC20 perhaps instead of Token, as in the line below, which serves as an example.
        # Check this.
        #ERC20(input_asset).transferFrom(msg.sender,self,amount_in)
        Token(input_asset).transferFrom(msg.sender,self,amount_in)
        Token(input_asset).transfer(self.fee_address,amount_fee)
        output_asset: address = self.assets[o]
        amount_out: uint256 = self.decimal_to_uint_assets(ao, o)
        #ERC20(output_asset).transferFrom(self,msg.sender,amount_out)
        Token(output_asset).transfer(msg.sender,amount_out)
        self.balances[i]+=ai
        self.balances[o]-=ao
        log Log_trade_output(trade.amount,ao,trade.protocol_fee,trade.execute_trade)
    else:
        log Log_msg(trade.message)

@external
def liquidity_deposit(i: uint8, ai: decimal):
    input_asset: address = self.assets[i]
    assert self.deposits_enabled[i] == True, "Deposits of this asset are temporarily disabled."
    assert ai > 0.0, "The amount to deposit must be a positive number."
    assert Token(input_asset).balanceOf(msg.sender) >= self.decimal_to_uint_assets(ai,i) , "You do not have enough tokens to deposit."
    prices: decimal[N] = LIST_OF_ZEROES
    for j in range(N):
        price_j_int256: int256 = self.get_latest_price(j)
        prices[j] = self.price_to_decimal(price_j_int256)

    lpt: decimal = self.single_asset_deposit(i, ai, self.balances, self.lp_tokens_issued, prices)
    if lpt == 0.0:
        log Log_msg("Deposit not executed.")
    else:
        # transfer amount of token i
        amount_in: uint256 = self.decimal_to_uint_assets(ai, i)
        # For the final version we will need to call ERC20 instead of Token, as in the line below, which serves as an example.
        # Check this.
        Token(input_asset).transferFrom(msg.sender,self,amount_in)
        #ERC20(input_asset).transferFrom(msg.sender,self,amount_in)
        self.balances[i]+=ai
        # mint corresponding LP token
        lptok: LPToken = self.lptokens[i]
        mint_amount: uint256 = self.decimal_to_uint_lptokens(lpt)
        lptok.mint(msg.sender,mint_amount)
        self.lp_tokens_issued[i]+=lpt
        log Log_deposit(ai, lpt)

@external
def liquidity_withdrawal(o: uint8, lpt: decimal):
    lptok: LPToken = self.lptokens[o]
    assert lptok.balanceOf(msg.sender) >= self.decimal_to_uint_lptokens(lpt) , "You do not have enough LP tokens."
    prices: decimal[N] = LIST_OF_ZEROES
    for j in range(N):
        price_j_int256: int256 = self.get_latest_price(j)
        prices[j] = self.price_to_decimal(price_j_int256)
    out: WithdrawalOutput = self.single_asset_withdrawal(o, lpt, self.balances, self.lp_tokens_issued, prices)
    # burn corresponding amount of lp tokens
    lpt_amount: decimal = lpt
    if out.remaining > 0.0:
        lpt_amount = lpt*(out.value-out.remaining)/out.value
    burn_amount: uint256 = self.decimal_to_uint_lptokens(lpt_amount)
    lptok.burnFrom(msg.sender,burn_amount)
    self.lp_tokens_issued[o]-=lpt_amount
    # deposit corresponding amount of each token
    for j in range(N):
        if out.amounts[j] != 0.0:
            # transfer to liquidity provider
            output_asset: address = self.assets[j]
            amount_out: uint256 = self.decimal_to_uint_assets(out.amounts[j], j)
            # For the final version we will need to call ERC20 instead of Token, as in the line below, which serves as an example.
            # Check this.
            #ERC20(output_asset).transfer(msg.sender,amount_out)
            Token(output_asset).transfer(msg.sender,amount_out)
            self.balances[j]-=out.amounts[j]
    log Log_withdrawal(lpt, out.amounts)




