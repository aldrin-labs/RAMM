# @version ^0.3.0
"""
@title Oracle-based AMM
@license To be determined.
@author Miguel Ottina - DeFi Research Analyst at Aldrin Labs
@notice An AMM that greatly reduces impermanent loss.
"""

from vyper.interfaces import ERC20


interface Token:
    def balanceOf(_owner: address) -> uint256: view
    def transferFrom(_from : address, _to : address, _value : uint256) -> bool: nonpayable
    def transfer(_to : address, _value : uint256) -> bool: nonpayable

interface LPToken:
    def totalSupply() -> uint256: view
    def minter() -> address: view
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
_BASE_FEE: constant(uint256) = 8 # (in basis points) BASE_FEE=8 corresponds to 0.0008 or 0.08%.
_BASE_LEVERAGE: constant(uint256) = 100
_PROTOCOL_FEE: constant(uint256) = 50 # 50% of collected BASE_FEEs go to the protocol
_DELTA: constant(uint256) = 25 # maximum permitted deviation of the imbalance ratios from 1.0. 2 decimal places are considered. Hence DELTA=25 is interpreted as 0.25.
MINIMUM_TRADE_AMOUNTS: constant(uint256[N]) = [1*10**16,1*10**18,1*10**6] # Initial minimum amounts for trades (in the smallest unit of each asset)
ASSETS_DECIMAL_PLACES: constant(uint8[N]) = [18,18,6]

## Decimal places and related constants

PRICES_DECIMAL_PLACES: constant(uint8) = 8
PRECISION_DECIMAL_PLACES: constant(uint256) = 20   # at least 18 and no more than 38.
ONE: constant(uint256) = 10**PRECISION_DECIMAL_PLACES

BASE_FEE: constant(uint256) = _BASE_FEE * 10**(PRECISION_DECIMAL_PLACES-4)
BASE_LEVERAGE: constant(uint256) = _BASE_LEVERAGE * ONE
PROTOCOL_FEE: constant(uint256) = _PROTOCOL_FEE*10**(PRECISION_DECIMAL_PLACES-2)
DELTA: constant(uint256) = _DELTA * 10**(PRECISION_DECIMAL_PLACES-2)
FACTOR: constant(uint256) = 10**(PRECISION_DECIMAL_PLACES-18)
FACTOR_PRICES: constant(uint256) = 10**(PRECISION_DECIMAL_PLACES-PRICES_DECIMAL_PLACES)

## Other constants

LIST_OF_ZEROES: constant(uint256[N]) = [0,0,0] # modify according to the value of N
LIST_OF_TRUE: constant(bool[N]) = [True,True,True] # modify according to the value of N
LIST_OF_FALSE: constant(bool[N]) = [False,False,False] # modify according to the value of N




# State variables

balances: public(uint256[N])
lp_tokens_issued: uint256[N]
owner: public(address)
assets: public(address[N])
lptokens: public(LPToken[N])
price_feeds: public(AggregatorV3Interface[N])
fee_address: address
deposits_enabled: public(bool[N])
minimum_trade_amounts: public(uint256[N])
trading_volume: public(uint256)
pool_initialized: public(bool)

# Events

event Log_msg:
    message: String[100]

event Log_pool_state:
    balances: uint256[N]
    LP_tokens_issued: uint256[N]
    imbalance_ratios: uint256[N]
    prices_given: uint256[N]

event Log_trade_output:
    token_in: uint8
    token_out: uint8
    amount_in: uint256
    amount_out: uint256
    protocol_fee: uint256
    execute_trade: bool
    transaction_type: String[10]
    pool_address: indexed(address)
    trader_address: indexed(address)

event Log_deposit:
    token: uint8
    amount: uint256
    amount_lp_tokens: uint256
    transaction_type: String[10]
    pool_address: indexed(address)
    lp_address: indexed(address)

event Log_withdrawal:
    token: uint8
    amount_lp_tokens: uint256
    amounts: uint256[N]
    transaction_type: String[10]
    pool_address: indexed(address)
    lp_address: indexed(address)


# Structs

struct TradeOutput:
    amount: uint256
    protocol_fee: uint256
    execute_trade: bool
    message: String[100]

struct WithdrawalOutput:
    amounts: uint256[N]
    value: uint256
    remaining: uint256


######################## Pool initialization and management ########################


@external
def __init__(
    _owner: address,
    assetslist: address[N],
    lptokenslist: address[N],
    _price_feed_addresses: address[N],
    fee_collector: address
    ):
    """
    @notice Initializes the pool.
    @param _owner Pool's owner's address.
    @param assetslist List of addresses of the assets of the pool.
    @param lptokenslist List of addresses of the lptokens of the pool.
    @param _price_feed_addresses List of addresses of the Chainlink price feeds of the assets of the pool.
    @param fee_collector Address that collects the fees.
    """
    self.owner=_owner
    for j in range(N):
        assert assetslist[j] != ZERO_ADDRESS, "Invalid asset address."
    self.assets=assetslist
    for j in range(N):
        assert LPToken(lptokenslist[j]).totalSupply() == 0, "Invalid LP token address."
        #LPToken(lptokenslist[j]).set_minter(self)
        self.lptokens[j] = LPToken(lptokenslist[j])
        self.price_feeds[j] = AggregatorV3Interface(_price_feed_addresses[j])
    self.balances = LIST_OF_ZEROES
    self.lp_tokens_issued = LIST_OF_ZEROES
    self.fee_address = fee_collector
    self.deposits_enabled = LIST_OF_FALSE
    self.minimum_trade_amounts = MINIMUM_TRADE_AMOUNTS
    self.pool_initialized = False


@external
def initialize_pool():
    """
    @notice This function starts the pool enabling deposits. It asserts that there have not been LP tokens minted after the pool is initialized and before the pool starts functioning. This protects liquidity providers against malicious use of this contract.
    """
    assert msg.sender == self.owner, "You do not have permission to call this function."
    for j in range(N):
        assert self.lptokens[j].minter() == self, "The pool must be the minter of the LP tokens."
        assert self.lptokens[j].totalSupply() == 0, "Invalid LP token address."
    self.pool_initialized = True
    self.deposits_enabled = LIST_OF_TRUE


@external
def set_owner(_owner: address):
    """
    @notice Sets a new pool owner. Can only be executed by the pool owner.
    @param _owner Address of the new pool owner.
    """
    assert msg.sender == self.owner, "You do not have permission to set a new owner."
    self.owner = _owner


@external
def set_new_fee_collector(fee_collector: address):
    """
    @notice Sets a new address to collect fees. Can only be executed by the pool owner.
    @param fee_collector Address where the fees will be sent to.
    """
    assert msg.sender == self.owner, "You do not have permission to set a new fee collector."
    self.fee_address = fee_collector


@external
def disable_deposits(i: uint8):
    """
    @notice Disables deposits of a certain asset of the pool. Can only be executed by the pool owner.
    @param i Index of the asset (from 0 to N-1) that will be disabled for deposits.
    """
    assert msg.sender == self.owner, "You do not have permission to disable deposits."
    self.deposits_enabled[i] = False


@external
def enable_deposits(i: uint8):
    """
    @notice Enables deposits of a certain asset of the pool. Can only be executed by the pool owner.
    @param i Index of the asset (from 0 to N-1) that will be enabled for deposits.
    """
    assert msg.sender == self.owner, "You do not have permission to enable deposits."
    assert self.pool_initialized == True, "You have to initialize the pool first."
    self.deposits_enabled[i] = True


@external
def set_new_minimum_trade_amount(i: uint8, amount: uint256):
    """
    @notice Sets a new minimum trade amount for a certain asset. Can only be executed by the pool owner.
    @param i Index of the asset (from 0 to N-1) of which we will set a new minimum trade amount.
    @param amount The new minimum trading amount that will be set.
    """
    assert msg.sender == self.owner, "You do not have permission to set new minimum trade amounts."
    #assert amount >= 0.0, "The minimum trading amount must be non-negative."
    self.minimum_trade_amounts[i] = amount


@internal
@view
def get_latest_price(i: uint8) -> int256:
    """Obtains the latest price of token i from the oracle."""
    a: uint80 = 0
    price: int256 = 0
    b: uint256 = 0
    c: uint256 = 0
    d: uint80 = 0
    (a, price, b, c, d) = self.price_feeds[i].latestRoundData()
    return price



######################## Math ########################

###### Numbers ######


@internal
@view
def mul(x: uint256, y: uint256) -> uint256:
    """
    Multiplies two uint256 that represent decimal numbers with PRECISION_DECIMAL_PLACES
    and returns the result as another uint256 with the same amount of decimal places.
    """
    assert x <= 10**38 and y <= 10**38 , "Multiplication overflow."

    return x*y/10**PRECISION_DECIMAL_PLACES


@internal
@view
def mul3(x: uint256, y: uint256, z: uint256) -> uint256:
    return self.mul(self.mul(x,y), z)


@internal
@view
def div(x: uint256, y: uint256) -> uint256:
    """
    Divides two uint256 that represent decimal numbers with PRECISION_DECIMAL_PLACES decimal places
    and returns the result as another uint256 with the same amount of decimal places.
    """
    assert x <= 10**38, "Dividend is too large."
    return x*10**PRECISION_DECIMAL_PLACES/y


@internal
@view
def pow_n(x: uint256, n: uint256) -> uint256:
    """
    Computes x^n, where n is a non-negative integer and x is a uint256 that represents a decimal number with
    PRECISION_DECIMAL_PLACES decimal places.
    """
    assert n>=0, "The parameter n must be a positive integer."
    #log Log_uint_value("n",convert(n,uint256)) # ***
    assert n<=127, "The parameter n is too large."
    assert x <= 10**38, "The base is too large."
    m: uint256 = n
    result: uint256 = ONE
    a: uint256 = x
    #while m!=0:  # while is not supported in Vyper
    # We can find an upper bound for n (should be n<=100 if the weights are between 0.01 and 1. )
    # and then hard code number_of loops as
    # number_of_loops = floor(log_2(n))+1 .
    # For example, if the upper bound for n is 127, a number of loops equal to 7 works,
    # since we need 7 digits to write n in base 2.
    for j in range(7):
        if m%2 == 1:
            result = self.mul(result, a)
        a = self.mul(a, a)
        m = m / 2  # recall that m is uint256, so this is integer division
        if m==0:
            return result
    # We can throw an error message here, since the result must be reached within the for loop.
    return result


@internal
@view
def pow_d(x: uint256, a: uint256) -> uint256:
    """Computes x^a, where a is a real number between 0 and 1. Both a and x have to be given with
    PRECISION_DECIMAL_PLACES decimal places. The result is given in the same format.
    """
    # We will use a Taylor series. The taylor series converges for x in (0,2).
    # If the leverage parameter k is greater than 11 then the formula of Ai employs exponentiation
    # with 1<x<1.1 .
    # On the other hand, in the formula for Ao, we employ exponentiation with 0<x<1.
    # In addition, if Ai<kBi/2 then we use an x with 1/2<x<1.
    # Thus, we can find a lower bound for the number of iterations to obtain the desired precision.
    # Tasks:
    # **** compute necessary number of iterations to obtain the desired precision.
    # **** write mathematical explanation with proofs.

    # We check that 0.67 <= x <= 1.5.

    assert (67*10**(PRECISION_DECIMAL_PLACES-2) <= x and x <= 150*10**(PRECISION_DECIMAL_PLACES-2)), "The base of the exponentiation is out of the desired bounds."


    result: uint256 = ONE # first partial sum of the series
    n: uint256 = 0
    tn: uint256 = ONE # n-th term (for n=0 here)

    #steps_bound: uint8 =30 # gives precision of 0.1**10 for 2/3<x<1.5 and 0<a<1.
    #for j in range(steps_bound):
    sign: int8 = 1
    for j in range(30):
        #tn1 = tn*(a-n)*(x-1.0)/(n+1.0)  #(n+1)-th term
        factor1: uint256 = 0
        factor2: uint256 = 0
        if a >= n*ONE:
            factor1 = a - n*ONE
        else:
            factor1 = n*ONE - a
            sign = -sign
        if x >= ONE:
            factor2 = x - ONE
        else:
            factor2 = ONE - x
            sign = -sign
        #(n+1)-th term
        tn1: uint256 = self.div(self.mul3(tn, factor1, factor2), n * ONE + ONE)
        if tn1 == 0:
            return result
        if sign == 1:
            result = result + tn1
        else:
            result = result - tn1
        # The partial sums of the series must not be negative, otherwise this computation will fail.
        # This seems to be the case, but do the maths to prove this.
        n+=1
        tn=tn1
    return result


@internal
@view
def power(x: uint256, a: uint256) -> uint256:
    """Computes x^a, where a is a real number that belongs to the interval [0,128). Both a and x have to be given with PRECISION_DECIMAL_PLACES decimal places. The result is given in the same format."""
    n: uint256 = a / 10**PRECISION_DECIMAL_PLACES
    return self.mul(self.pow_n(x,n),self.pow_d(x,a-n*ONE))



###### Functions ######


@internal
@view
def weights(balances: uint256[N], prices: uint256[N]) -> uint256[N]:
    """Returns a list with the weights of the tokens with respect to the given prices.
    The result is given in uint256 with PRECISION_DECIMAL_PLACES decimal places. """
    B: uint256 = 0
    W: uint256[N] = LIST_OF_ZEROES
    for j in range(N):
        B += self.mul(prices[j] * FACTOR_PRICES, balances[j] * FACTOR)
    for j in range(N):
        W[j] = self.div(self.mul(prices[j] * FACTOR_PRICES, balances[j] * FACTOR), B)
    return W


@internal
@view
def compute_B_and_L(
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N]
    ) -> (uint256,uint256):
    """Returns a list with the values of B and L.
    The result is given in uint256 with PRECISION_DECIMAL_PLACES decimal places."""
    B: uint256 = 0
    L: uint256 = 0
    for j in range(N):
        B+= self.mul(prices[j] * FACTOR_PRICES, balances[j] * FACTOR)
        L+= self.mul(prices[j] * FACTOR_PRICES, lp_tokens_issued[j] * FACTOR)
    return (B,L)


@internal
@view
def imbalance_ratios(
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N]
    ) -> uint256[N]:
    """Returns a list with the imbalance ratios of the tokens. The result is given in uint256 with PRECISION_DECIMAL_PLACES decimal places."""
    Imb: uint256[N] = LIST_OF_ZEROES
    B: uint256 = 0
    L: uint256 = 0
    B,L = self.compute_B_and_L(balances, lp_tokens_issued, prices)
    for j in range(N):
        if lp_tokens_issued[j] != 0:
            Imb[j]=self.div(self.mul(balances[j] * FACTOR,L), self.mul(B, lp_tokens_issued[j] * FACTOR))
        else:
            Imb[j]=0
    return Imb


@internal
@view
def check_imbalance_ratios(
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N],
    i: uint8,
    o: uint8,
    ai: uint256,
    ao: uint256,
    pr_fee: uint256
    ) -> bool:
    """ Checks if the imbalance ratios after a trade belong to the corresponding range (or if they are closer to the range than before the trade)."""
    balances_before: uint256[N] = balances # check that the list is copied and that the original list is not modified
    balances_after: uint256[N] = balances  # check that the list is copied and that the original list is not modified
    balances_after[i] = balances[i] + ai - pr_fee
    balances_after[o] = balances[o] - ao
    imb_ratios_before_trade: uint256[N] = self.imbalance_ratios(balances_before, lp_tokens_issued, prices)
    imb_ratios_after_trade: uint256[N] = self.imbalance_ratios(balances_after, lp_tokens_issued, prices)

    condition1: bool = (
        imb_ratios_after_trade[o] < ONE - DELTA
        and imb_ratios_after_trade[o] < imb_ratios_before_trade[o]
        )
    condition2: bool = (
        ONE + DELTA < imb_ratios_after_trade[i]
        and imb_ratios_before_trade[i] < imb_ratios_after_trade[i]
        )

    if condition1 or condition2:
        return False
    return True


@internal
@view
def check_imbalance_ratios_message(execute: bool) -> String[100]:
    """Returns a message according to the trade being executed or not."""
    if execute == True:
        return "Trade executed."
    else:
        return "The trade was not executed because of pool imbalance."


@internal
@view
def funct_adjust(x: uint256) -> uint256:
    """Base function that adjusts the leverage parameter and the base fee."""
    return self.mul3(x, x, x)


@internal
@view
def scaled_fee_and_leverage(
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N],
    i: uint8,
    o: uint8
    ) -> (uint256,uint256):
    """Returns the scaled base fee and leverage parameter for a trade where token i goes into the pool and
    token o goes out of the pool."""
    imbalance: uint256[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
    adjust_i: uint256 = self.funct_adjust(imbalance[i])
    adjust_o: uint256 = self.funct_adjust(imbalance[o])
    scaled_base_fee: uint256 = self.div(self.mul(adjust_i, BASE_FEE), adjust_o)
    scaled_leverage: uint256 = self.div(self.mul(adjust_o, BASE_LEVERAGE), adjust_i)
    return (scaled_base_fee,scaled_leverage)


@internal
@view
def trade_i(
    i: uint8,
    o: uint8,
    ai: uint256,
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N]
    ) -> TradeOutput :
    """
    Computes the paramters of a trade where an amount ai of token i goes into the pool
    and token o goes out of the pool. Returns the amount ao of token o that goes
    out of the pool, the base fee that is charged, a boolean that indicates if the trade has to be executed or not,
    and a message that explains why the the trade will not be executed, if that is the case.
    """

    # First we compute the weights.
    W: uint256[N] = self.weights(balances, prices)
    # We divide into different cases.
    if balances[i] == 0:
        #ao = (1.0-BASE_FEE)*ai*prices[i]/prices[o]
        num: uint256 = self.mul3(ONE - BASE_FEE, ai * FACTOR, prices[i] * FACTOR_PRICES)
        ao: uint256 = self.div(num, prices[o] * FACTOR_PRICES) / FACTOR
        pr_fee: uint256 = self.mul3(PROTOCOL_FEE, BASE_FEE, ai * FACTOR) / FACTOR
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices, i, o, ai, ao, pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ao, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    if lp_tokens_issued[o] == 0 and balances[i] != 0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        leverage: uint256 = BASE_LEVERAGE
        trading_fee: uint256 = BASE_FEE
        bi: uint256 = self.mul(balances[i] * FACTOR, leverage)
        wi: uint256 = W[i]
        bo: uint256 = self.mul(balances[o] * FACTOR, leverage)
        wo: uint256 = W[o]
        #ao = bo*(1.0-self.power(bi/(bi+(1.0-trading_fee)*ai),wi/wo))
        base_denom: uint256 = bi + self.mul(ONE - trading_fee, ai * FACTOR)
        power: uint256 = self.power(self.div(bi, base_denom), self.div(wi, wo))
        ao: uint256 = self.mul(bo, ONE - power) / FACTOR
        pr_fee: uint256 = self.mul3(PROTOCOL_FEE, trading_fee, ai * FACTOR) / FACTOR
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices, i, o, ai, ao, pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ao, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    if lp_tokens_issued[o] != 0 and balances[i] != 0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        # We check imbalance ratio of token o.
        imb_ratios_initial_o: uint256 = self.imbalance_ratios(balances, lp_tokens_issued, prices)[o]
        if imb_ratios_initial_o < ONE-DELTA:
            # In this case the trade is not performed because the imbalance ratio of token o is too low.
            return TradeOutput({amount: 0, protocol_fee:0, execute_trade: False, message: "The trade was not executed because the imbalance ratio of the out-token is too low."})
        # Now we update the fee and the leverage parameter.
        trading_fee: uint256 = 0
        leverage: uint256 = BASE_LEVERAGE
        trading_fee,leverage = self.scaled_fee_and_leverage(balances, lp_tokens_issued, prices, i, o)
        ## Now we compute the amounts of the trade.
        bi: uint256 = self.mul(balances[i] * FACTOR, leverage)
        wi: uint256 = W[i]
        bo: uint256 = self.mul(balances[o] * FACTOR, leverage)
        wo: uint256 = W[o]
        #ao = bo*(1.0-self.power(bi/(bi+(1.0-trading_fee)*ai),wi/wo))
        base_denom: uint256 = bi + self.mul(ONE - trading_fee, ai * FACTOR)
        power: uint256 = self.power(self.div(bi, base_denom), self.div(wi, wo))
        ao: uint256 = self.mul(bo, ONE - power) / FACTOR
        pr_fee: uint256 = self.mul3(PROTOCOL_FEE, trading_fee, ai * FACTOR) / FACTOR
        # Now we check if there is enough balance of token o.
        if ao > balances[o] or (ao == balances[o] and lp_tokens_issued[o] != 0):
            # In this case the trade is not executed because there is not enough balance of token o.
            return TradeOutput({amount: 0, protocol_fee:0, execute_trade: False, message: "The trade was not executed because there is not enough balance of the out-token."})
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices, i, o, ai, ao, pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ao, protocol_fee:pr_fee, execute_trade: execute, message: _message})
    return TradeOutput({amount: 0, protocol_fee:0, execute_trade: False, message: "The trade was not executed."})

@internal
@view
def trade_o(
    i: uint8,
    o: uint8,
    ao: uint256,
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N]
    ) -> TradeOutput :
    """
    Computes the parameters of a trade where an amount ao of token o goes out of the pool
    and token i goes into the pool. Returns the amount ai of token i that goes
    into the pool, the base fee that is charged, a boolean that indicates if the trade has to be executed or not,
    and a message that explains why the the trade will not be executed, if that is the case.
    """

    # First we compute the weights.
    W: uint256[N] = self.weights(balances, prices)
    # Now we divide into different cases.
    if balances[i] == 0:
        #ai: decimal = ao*prices[o]/prices[i]/(1.0-BASE_FEE)
        num: uint256 = self.mul(ao * FACTOR,prices[o] * FACTOR_PRICES)
        denom: uint256 = self.mul(prices[i] * FACTOR_PRICES, ONE-BASE_FEE)
        ai: uint256 = self.div(num, denom) / FACTOR
        pr_fee: uint256 = self.mul3(PROTOCOL_FEE, BASE_FEE, ai * FACTOR) / FACTOR
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices, i, o, ai, ao, pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    if lp_tokens_issued[o] == 0 and balances[i] != 0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        leverage: uint256 = BASE_LEVERAGE
        bi: uint256 = self.mul(balances[i] * FACTOR, leverage)
        wi: uint256 = W[i]
        bo: uint256 = self.mul(balances[o] * FACTOR, leverage)
        wo: uint256 = W[o]
        #ai: decimal = bi/(1.0-BASE_FEE)*(self.power(bo/(bo-ao),wo/wi)-1.0)

        power: uint256 = self.power(self.div(bo, bo - ao * FACTOR), self.div(wo, wi))
        ai: uint256 = self.div(self.mul(bi, power - ONE), ONE - BASE_FEE) / FACTOR
        pr_fee: uint256 = self.mul3(PROTOCOL_FEE, BASE_FEE, ai * FACTOR) / FACTOR
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices, i, o, ai, ao, pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute, message: _message})

    if lp_tokens_issued[o] != 0 and balances[i] != 0: # Self.balances[i]!=0 is not needed here, but added anyway just in case
        # We check the imbalance ratio of token o.
        imb_ratios_initial: uint256[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
        if imb_ratios_initial[o] < ONE - DELTA:
            # In this case we do not execute the trade because the imbalance ratio of token o is too low.')
            return TradeOutput({amount: 0, protocol_fee:0, execute_trade: False, message: "The trade was not executed because the imbalance ratio of the out-token is too low."})

        # Now we update the fee and the leverage parameter.
        trading_fee: uint256 = 0
        leverage: uint256 = BASE_LEVERAGE
        trading_fee,leverage = self.scaled_fee_and_leverage(balances, lp_tokens_issued, prices, i, o)
        # Now we perform the trade
        bi: uint256 = self.mul(balances[i] * FACTOR, leverage)
        wi: uint256 = W[i]
        bo: uint256 = self.mul(balances[o] * FACTOR, leverage)
        wo: uint256 = W[o]
        #ai: decimal = bi/(1.0-trading_fee)*(self.power(bo/(bo-ao),wo/wi)-1.0)
        power: uint256 = self.power(self.div(bo, bo - ao * FACTOR), self.div(wo, wi))
        ai: uint256 = self.div(self.mul(bi, power - ONE), ONE - trading_fee) / FACTOR
        pr_fee: uint256 = self.mul3(PROTOCOL_FEE, trading_fee, ai * FACTOR) / FACTOR
        # We check the imbalance ratios
        execute: bool = self.check_imbalance_ratios(balances, lp_tokens_issued, prices, i, o, ai, ao, pr_fee)
        _message: String[100] = self.check_imbalance_ratios_message(execute)
        return TradeOutput({amount: ai, protocol_fee: pr_fee, execute_trade: execute, message: _message})
    return TradeOutput({amount: 0, protocol_fee:0, execute_trade: False, message: "The trade was not executed."})

@internal
@view
def single_asset_deposit(
    i: uint8,
    ai: uint256,
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N]
    )-> uint256:
    """
    Computes the parameters of a single asset deposit of amount i of token i.
    Returns the amount of LP tokens that must be given to the liquidity provider.
    """
    # we divide into cases
    if lp_tokens_issued[i] == 0 or (lp_tokens_issued[i] != 0 and balances[i] == 0):
        B: uint256 = 0
        L: uint256 = 0
        B,L = self.compute_B_and_L(balances, lp_tokens_issued, prices)
        if B == 0:
            lpt: uint256 = ai
            return lpt
        if B != 0:
            #lpt: decimal = ai*L/B
            lpt: uint256 = self.div(self.mul(ai * FACTOR,L),B) / FACTOR
            return lpt

    if lp_tokens_issued[i] != 0 and balances[i] != 0:
        imb_ratios: uint256[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
        bi: uint256 = balances[i] * FACTOR
        ri: uint256 = imb_ratios[i]
        #lpt = (ai/bi)*ri*lp_tokens_issued[i]
        lpt: uint256 = self.div(self.mul3(ai * FACTOR, ri, lp_tokens_issued[i] * FACTOR), bi) / FACTOR
        return lpt

    return 0


@internal
@view
def single_asset_withdrawal(
    o: uint8,
    lpt: uint256,
    balances: uint256[N],
    lp_tokens_issued: uint256[N],
    prices: uint256[N]
    ) -> WithdrawalOutput:
    """
    Given an amount of LP tokens and its type o,
    returns the amounts of each token to be given to the LP,
    the value given to the LP in terms of token o, and the remaining
    amount of token o to be given to the LP (if any) in case the
    process could not be completed.
    """

    amounts_out: uint256[N] = LIST_OF_ZEROES
    a_remaining: uint256 = 0
    bo: uint256 = balances[o] * FACTOR
    imb_ratios: uint256[N] = self.imbalance_ratios(balances, lp_tokens_issued, prices)
    ao: uint256 = 0


    if balances[o] == 0:
        B: uint256 = 0
        L: uint256 = 0
        B,L = self.compute_B_and_L(balances, lp_tokens_issued, prices)
        # ao = lpt*B/L
        ao = self.div(self.mul(lpt * FACTOR, B), L) / FACTOR
        a_remaining = ao
        # The liquidity provider receives 0 token o.
        # We continue the withdrawal with another token.

    if balances[o] != 0:
        ro: uint256 = imb_ratios[o]
        Lo: uint256 = lp_tokens_issued[o] * FACTOR
        # ao = lpt*bo/(Lo*ro)
        if lpt < lp_tokens_issued[o]:
            ao = self.div(self.mul(lpt * FACTOR, bo), self.mul(Lo, ro)) / FACTOR
            max_token_o: uint256 = 0

            if ONE-DELTA < ro:
                B: uint256 = 0
                L: uint256 = 0
                B,L = self.compute_B_and_L(balances, lp_tokens_issued, prices)
                # M1=bo-(1.0-DELTA)*(Lo-lpt)*B/L
                min_token_o: uint256 = self.div(self.mul3(B, (lp_tokens_issued[o] - lpt) * FACTOR, ONE - DELTA), L) / FACTOR
                max_token_o = balances[o] - min_token_o
            else:
                # M1 = lpt*bo/Lo
                max_token_o = self.div(self.mul(lpt * FACTOR,bo),Lo) / FACTOR

            if ao <= max_token_o:
                amounts_out[o] += ao
                # The liquidity provider receives ao token o.
                return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: 0})
            if ao > max_token_o:
                amounts_out[o] += max_token_o
                # The liquidity provider receives max_token_o token o
                a_remaining = ao - max_token_o
                imb_ratios[o] = 0 # to avoid choosing token o again in the next steps
                # We continue the withdrawal with another token.

        else:
            # ao=bo/ro
            ao = self.div(bo, ro) / FACTOR
            if ao <= balances[o]:
                amounts_out[o] += ao
                # The liquidity provider receives ao token o.
                return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: 0})
            if ao > balances[o]:
                amounts_out[o] += balances[o]
                # The liquidity provider receives balances[o] token o
                a_remaining = ao - balances[o]
                imb_ratios[o] = 0 # to avoid choosing token o again in the next steps
                # We continue the withdrawal with another token

    # Now the withdrawal continues with another token
    # and employs the remaining amount.

    Loop: bool = True
    prev_index: uint8 = o
    max_imb_ratio: uint256 = 0
    index: uint8 = o

    for j in range(N):
        if a_remaining != 0 and Loop:
            # We compute the maximum among the remaining imbalance ratios.
            # We would like to do:
            # k=imb_ratios.index(max([x for x in imb_ratios if x >= 0.0]))
            # but list comprehensions are not implemented in Vyper.
            max_imb_ratio = 0
            for l in range(N):
                if max_imb_ratio < imb_ratios[l]:
                    index = l
                    max_imb_ratio = imb_ratios[l]
            k: uint8 = index

            if k == prev_index:
                Loop = False

            if k != prev_index:
                # ak = a_remaining*price_o/price_k
                ak: uint256 = self.div(self.mul(a_remaining * FACTOR, prices[o] * FACTOR_PRICES), prices[k] * FACTOR_PRICES) / FACTOR
                bk: uint256 = balances[k] * FACTOR
                Lk: uint256 = lp_tokens_issued[k] * FACTOR
                B: uint256 = 0
                L: uint256 = 0
                B,L = self.compute_B_and_L(balances, lp_tokens_issued, prices)
                # Mk = bk-(1.0-DELTA)*Lk*B/L
                min_token_k: uint256 = self.div(self.mul3(B, Lk, ONE - DELTA), L) / FACTOR
                max_token_k: uint256 = balances[k] - min_token_k
                if ak <= max_token_k:
                    amounts_out[k] += ak
                    # The liquidity provider receives ak token k.
                    a_remaining=0
                if ak > max_token_k:
                    amounts_out[k] += max_token_k
                    # The liquidity provider receives max_token_k token k.
                    # The value of max_token_k in terms of token o is max_token_k*prices[k]/prices[o]
                    value_max_token_k: uint256 = self.div(self.mul(max_token_k * FACTOR, prices[k] * FACTOR_PRICES), prices[o] * FACTOR_PRICES) / FACTOR
                    a_remaining -= value_max_token_k
                prev_index=k

    return WithdrawalOutput({amounts: amounts_out, value: ao, remaining: a_remaining})


######################## OAMM ########################

@external
def pool_state(prices: uint256[N]):
    """
    @notice Logs the pool balances, the LP tokens in circulation and imbalance ratios with respect to the given prices.
    @dev The prices are given manually to avoid paying fees for calling the oracle.
    @param prices A list with the market prices of each asset.
    """
    Imb: uint256[N] = self.imbalance_ratios(self.balances, self.lp_tokens_issued, prices)
    log Log_pool_state(self.balances, self.lp_tokens_issued, Imb, prices)

@external
def get_pool_state() -> (uint256[N], uint256[N]):
    """
    @notice Returns the pool balances and the LP tokens in circulation.
    """
    return self.balances, self.lp_tokens_issued

@external
def trade_amount_in(i: uint8, o: uint8, ai: uint256):
    """
    @notice Performs a trade given the amount of the asset that goes into the pool.
    @param i Index of the asset that goes into the pool.
    @param o Index of the asset that goes out of the pool.
    @param ai Amount of the asset that goes into the pool.
    """
    #assert ai >= 0, "The trading amount must be non-negative."
    assert ai >= self.minimum_trade_amounts[i], "The trading amount is too small."
    assert self.lp_tokens_issued[i] > 0, "The trade is not allowed because there are no LP tokens of the in-token type in circulation."
    assert self.balances[o] > 0, "The trade is not possible because there is currently no out-token left in the pool."
    # We take the market prices from the oracle
    prices: uint256[N] = LIST_OF_ZEROES
    for j in range(N):
        prices[j] = convert(self.get_latest_price(j),uint256)
    # Now we compute the parameters of the trade
    trade: TradeOutput = self.trade_i(i, o, ai, self.balances, self.lp_tokens_issued, prices)
    if trade.execute_trade:
        # The following lines are not needed because this check is already performed in the self.trade_i function.
        #ao = trade.amount
        #assert ao<=self.balances[o], "The trade was not executed because there is not enough balance of the out-token."
        #if ao == self.balances[o]:
            #assert self.lp_tokens_issued[o] = 0, "The trade was not executed because there is not enough balance of the out-token."
        input_asset: address = self.assets[i]
        amount_in: uint256 = ai
        amount_fee: uint256 = trade.protocol_fee
        Token(input_asset).transferFrom(msg.sender, self, amount_in)
        Token(input_asset).transfer(self.fee_address, amount_fee)
        # For the final version we will need to call ERC20 perhaps instead of Token, as in the line below, which serves as an example.
        # Check this.
        #ERC20(input_asset).transferFrom(msg.sender,self,amount_in)
        output_asset: address = self.assets[o]
        amount_out: uint256 = trade.amount
        #ERC20(output_asset).transferFrom(self,msg.sender,amount_out)
        Token(output_asset).transfer(msg.sender, amount_out)
        self.balances[i] += ai - trade.protocol_fee
        self.balances[o] -= trade.amount
        self.trading_volume += self.mul(ai * FACTOR, prices[i] * FACTOR_PRICES)
        log Log_trade_output(i, o, ai, trade.amount, trade.protocol_fee, trade.execute_trade, 'trade', self, msg.sender)
    else:
        log Log_msg(trade.message)


@external
def trade_amount_out(i: uint8, o: uint8, ao: uint256):
    """
    @notice Performs a trade given the amount of the asset that goes out of the pool.
    @param i Index of the asset that goes into the pool.
    @param o Index of the asset that goes out of the pool.
    @param ao Amount of the asset that goes out of the pool.
    """
    # First we perform some simple checks.
    assert ao >= self.minimum_trade_amounts[o], "The trading amount is too small."
    assert self.lp_tokens_issued[i] > 0, "The trade is not allowed because there are no LP tokens of the in-token type in circulation."
    assert ao<=self.balances[o], "The trade was not executed because there is not enough balance of the out-token."
    if ao == self.balances[o]:
        assert self.lp_tokens_issued[o] == 0, "The trade was not executed because there is not enough balance of the out-token."
    # We take the market prices from the oracle
    prices:uint256[N] = LIST_OF_ZEROES
    for j in range(N):
        prices[j] = convert(self.get_latest_price(j), uint256)
    # Now we compute the parameters of the trade
    trade: TradeOutput = self.trade_o(i, o, ao, self.balances, self.lp_tokens_issued, prices)
    if trade.execute_trade:
        ai: uint256 = trade.amount - trade.protocol_fee
        input_asset: address = self.assets[i]
        amount_in: uint256 = trade.amount
        amount_fee: uint256 = trade.protocol_fee
        # For the final version we will need to call ERC20 perhaps instead of Token, as in the line below, which serves as an example.
        # Check this.
        #ERC20(input_asset).transferFrom(msg.sender,self,amount_in)
        Token(input_asset).transferFrom(msg.sender, self, amount_in)
        Token(input_asset).transfer(self.fee_address, amount_fee)
        output_asset: address = self.assets[o]
        amount_out: uint256 = ao
        #ERC20(output_asset).transferFrom(self,msg.sender,amount_out)
        Token(output_asset).transfer(msg.sender, amount_out)
        self.balances[i] += ai
        self.balances[o] -= ao
        #self.trading_volume+=trade.amount*prices[i]
        self.trading_volume += self.mul(ai * FACTOR, prices[i] * FACTOR_PRICES)
        log Log_trade_output(i, o, trade.amount, ao, trade.protocol_fee, trade.execute_trade, 'trade', self, msg.sender)
    else:
        log Log_msg(trade.message)

@external
def liquidity_deposit(i: uint8, ai: uint256):
    """
    @notice Performs a liquidity deposit into the pool.
    @param i Index of the asset that will be deposited.
    @param ai Amount of asset i that will be deposited.
    """
    input_asset: address = self.assets[i]
    assert self.deposits_enabled[i] == True, "Deposits of this asset are temporarily disabled."
    assert ai > 0, "The amount to deposit must be a positive number."
    assert Token(input_asset).balanceOf(msg.sender) >= ai , "You do not have enough tokens to deposit."
    # In the following lines we check that no LP tokens have been minted previously, to protect users.
    # Otherwise, the contract can be initialized, some LP tokens minted, and after that the minting authority passed to the pool, exposing LPs to losses of their funds.
    #if self.lp_tokens_issued[i] == 0:
        #assert self.lptokens[i].totalSupply() == 0, "LP token address is compromised."
    prices: uint256[N] = LIST_OF_ZEROES
    for j in range(N):
        prices[j] = convert(self.get_latest_price(j), uint256)

    lpt: uint256 = self.single_asset_deposit(i, ai, self.balances, self.lp_tokens_issued, prices)
    if lpt == 0:
        log Log_msg("Deposit not executed.")
    else:
        # transfer amount of token i
        amount_in: uint256 = ai
        # For the final version we will need to call ERC20 instead of Token, as in the line below, which serves as an example.
        # Check this.
        Token(input_asset).transferFrom(msg.sender, self, amount_in)
        #ERC20(input_asset).transferFrom(msg.sender,self,amount_in)
        self.balances[i] += ai
        # mint corresponding LP token
        lptok: LPToken = self.lptokens[i]
        mint_amount: uint256 = lpt
        lptok.mint(msg.sender, mint_amount)
        self.lp_tokens_issued[i] += lpt
        log Log_deposit(i, ai, lpt, 'deposit', self, msg.sender)

@external
def liquidity_withdrawal(o: uint8, lpt: uint256):
    """
    @notice Performs a liquidity withdrawal.
    @param o Index of the asset that corresponds to the LP tokens the user has.
    @param lpt Amount of LP tokens that will be redeemed.
    """
    lptok: LPToken = self.lptokens[o]
    assert lptok.balanceOf(msg.sender) >= lpt , "You do not have enough LP tokens."
    prices: uint256[N] = LIST_OF_ZEROES
    for j in range(N):
        prices[j] = convert(self.get_latest_price(j),uint256)
    out: WithdrawalOutput = self.single_asset_withdrawal(o, lpt, self.balances, self.lp_tokens_issued, prices)
    # burn corresponding amount of lp tokens
    lpt_amount: uint256 = lpt
    if out.remaining > 0:
        # lpt_amount = lpt*(out.value-out.remaining)/out.value
        lpt_amount = self.div(self.mul(lpt * FACTOR, (out.value-out.remaining) * FACTOR), out.value * FACTOR) / FACTOR
    burn_amount: uint256 = lpt_amount
    lptok.burnFrom(msg.sender, burn_amount)
    self.lp_tokens_issued[o] -= lpt_amount
    # deposit corresponding amount of each token
    for j in range(N):
        if out.amounts[j] != 0:
            # transfer to liquidity provider
            output_asset: address = self.assets[j]
            amount_out: uint256 = out.amounts[j]
            # For the final version perhaps we will need to call ERC20 instead of Token, as in the line below, which serves as an example.
            # Check this.
            #ERC20(output_asset).transfer(msg.sender,amount_out)
            Token(output_asset).transfer(msg.sender, amount_out)
            self.balances[j] -= out.amounts[j]
    log Log_withdrawal(o, lpt, out.amounts, 'withdrawal', self, msg.sender)




