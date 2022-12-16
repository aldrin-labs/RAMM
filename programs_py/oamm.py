# oammv2
# Built with Seahorse v0.2.5

from lib.math import *
from seahorse.prelude import *
from seahorse.pyth import *

declare_id('4QtTJaWNGQBT1zoa3wuyewFXd1mCquGHL8hz69tuZ3Xu') # localhost



@instruction
def test(signer: Signer, balancesol: f64, balanceusdc: f64, balanceusdt: f64, pricesol: f64 , priceusdc: f64, priceusdt: f64, lptoksol: f64,lptokusdc: f64,lptokusdt: f64, basefee: f64, protocolfee: f64, baseleverage: f64, delta: f64, i: u8, o: u8, amount: f64,inout: str):
    balancearray=array(balancesol,balanceusdc,balanceusdt)
    balancearray2=array(balancesol,balanceusdc,balanceusdt)
    balancearray3=array(balancesol,balanceusdc,balanceusdt)
    pricearray=array(pricesol,priceusdc,priceusdt)
    pricearray2=array(pricesol,priceusdc,priceusdt)
    pricearray3=array(pricesol,priceusdc,priceusdt)
    lptokenarray=array(lptoksol,lptokusdc,lptokusdt)
    lptokenarray2=array(lptoksol,lptokusdc,lptokusdt)
    lptokenarray3=array(lptoksol,lptokusdc,lptokusdt)
    W=weights(balancearray,pricearray)
    I=imbalance_ratios(balancearray2,lptokenarray2,pricearray2)
    scaled_fee,scaled_leverage=scaled_fee_and_leverage(balancearray3,lptokenarray3,pricearray3,basefee,baseleverage,0,1)
    print(f'Weights: {W[0]}, {W[1]}, {W[2]}.')
    print(f'Imbalance ratios: {I[0]}, {I[1]}, {I[2]}.')
    print(f'Scaled fee: {scaled_fee} - Scaled leverage: {scaled_leverage}')
    # Trade
    if inout=='in':
        balancearray4=array(balancesol,balanceusdc,balanceusdt)
        lptokenarray4=array(lptoksol,lptokusdc,lptokusdt)
        pricearray4=array(pricesol,priceusdc,priceusdt)
        ao,pr_fee,execute_trade=trade_i(i,o,amount, balancearray4,lptokenarray4,pricearray4,basefee,protocolfee,baseleverage,delta)
        print(f'ao: {ao} - pr fee: {pr_fee} - Execute trade: {execute_trade}')
    if inout=='out':
        balancearray4=array(balancesol,balanceusdc,balanceusdt)
        lptokenarray4=array(lptoksol,lptokusdc,lptokusdt)
        pricearray4=array(pricesol,priceusdc,priceusdt)
        ai,pr_fee,execute_trade=trade_o(i,o,amount, balancearray4,lptokenarray4,pricearray4,basefee,protocolfee,baseleverage,delta)
        print(f'ai: {ai} - pr fee: {pr_fee} - Execute trade: {execute_trade}')
    if inout=='dep':
        balancearray4=array(balancesol,balanceusdc,balanceusdt)
        lptokenarray4=array(lptoksol,lptokusdc,lptokusdt)
        pricearray4=array(pricesol,priceusdc,priceusdt)
        lpt,i1=single_asset_deposit(i,amount, balancearray4,lptokenarray4,pricearray4)
        print(f'Deposit: amount: {amount} - token: {i1} - LP tokens: {lpt}')
    if inout=='with':
        balancearray4=array(balancesol,balanceusdc,balanceusdt)
        lptokenarray4=array(lptoksol,lptokusdc,lptokusdt)
        pricearray4=array(pricesol,priceusdc,priceusdt)
        single_asset_withdrawal(o, amount, balancearray4,lptokenarray4,pricearray4,delta)


class oamm(Account):
    balance_sol: f64
    balance_usdc: f64
    balance_usdt: f64
    lp_sol_tokens: f64
    lp_usdc_tokens: f64
    lp_usdt_tokens: f64
    base_fee: f64
    protocol_fee: f64
    base_leverage: f64
    delta: f64
    bump: u8


@instruction
def init(owner: Signer, pool: Empty[oamm], basefee: f64, protocolfee: f64, baseleverage: f64, delta: f64, mint_lpsol: Empty[TokenMint], mint_lpusdc: Empty[TokenMint], mint_lpusdt: Empty[TokenMint]):

  bump = pool.bump()
  pool = pool.init(
    payer=owner,
    seeds=['oamm']
  )
  pool.bump=bump

  pool.balance_sol=0.0
  pool.balance_usdc=0.0
  pool.balance_usdt=0.0
  pool.lp_sol_tokens=0.0
  pool.lp_usdc_tokens=0.0
  pool.lp_usdt_tokens=0.0
  pool.base_fee=basefee
  pool.protocol_fee=protocolfee
  pool.base_leverage=baseleverage
  pool.delta=delta


  mint_lpsol.init(
    payer = owner,
    seeds = ['lp_sol-token-mint'],
    decimals = 9,
    authority = pool
  )

  mint_lpusdc.init(
    payer = owner,
    seeds = ['lp_usdc-token-mint'],
    decimals = 9,
    authority = pool
  )

  mint_lpusdt.init(
    payer = owner,
    seeds = ['lp_usdt-token-mint'],
    decimals = 9,
    authority = pool
  )




@instruction
def deposit_sol(user: Signer, user_lp_sol_tkn_acc: TokenAccount, pool: oamm, mint_lpsol: TokenMint, amount_sol: f64, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  n = f64_to_u64_9_decimal_places(amount_sol)
  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  amount_lp_sol,i = single_asset_deposit(0, amount_sol, balances, LP_tokens_issued, prices)
  m = f64_to_u64_9_decimal_places(amount_lp_sol)
  bump = pool.bump

  user.transfer_lamports(
    to = pool,
    amount = n
  )

  mint_lpsol.mint(
    authority = pool,
    to = user_lp_sol_tkn_acc,
    amount = m,
    signer = ['oamm', bump]
  )

  pool.balance_sol+=amount_sol
  pool.lp_sol_tokens+=amount_lp_sol

  print(f'User {user.key()} deposited {amount_sol} SOL and received {amount_lp_sol} LPSOL tokens.')


@instruction
def withdraw_sol(user: Signer, user_lp_sol_tkn_acc: TokenAccount, user_usdc_tkn_acc: TokenAccount, user_usdt_tkn_acc: TokenAccount, pool: oamm, pool_usdc_tkn_acc: TokenAccount, pool_usdt_tkn_acc: TokenAccount, mint_lpsol: TokenMint, amount_lp_sol: f64, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)
  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  delta=pool.delta
  amount_sol_out,amount_usdc_out,amount_usdt_out,ao,remaining = single_asset_withdrawal(0, amount_lp_sol, balances, LP_tokens_issued, prices,delta)

  amount_lp_sol_to_burn=amount_lp_sol*(ao-remaining)/ao
  n_lp_sol = f64_to_u64_9_decimal_places(amount_lp_sol_to_burn)

  bump = pool.bump

  mint_lpsol.burn(
    authority = user,
    holder = user_lp_sol_tkn_acc,
    amount = n_lp_sol
  )
  pool.lp_sol_tokens-=amount_lp_sol_to_burn
  print(f'{amount_lp_sol_to_burn} LPSOL burned from user {user.key()}.')

  if amount_usdc_out != 0.0:
    n_usdc = f64_to_u64_9_decimal_places(amount_usdc_out)
    pool_usdc_tkn_acc.transfer(
      authority = pool,
      to = user_usdc_tkn_acc,
      amount = n_usdc,
      signer = ['oamm', bump]
    )
    pool.balance_usdc-=amount_usdc_out
    print(f'User {user.key()} withdrew {amount_usdc_out} USDC.')

  if amount_usdt_out != 0.0:
    n_usdt = f64_to_u64_9_decimal_places(amount_usdt_out)
    pool_usdt_tkn_acc.transfer(
      authority = pool,
      to = user_usdt_tkn_acc,
      amount = n_usdt,
      signer = ['oamm', bump]
    )
    pool.balance_usdt-=amount_usdt_out
    print(f'User {user.key()} withdrew {amount_usdt_out} USDT.')

  if amount_sol_out != 0.0:
    n_sol = f64_to_u64_9_decimal_places(amount_sol_out)
    pool.transfer_lamports(
      to = user,
      amount = n_sol
    )
    pool.balance_sol-=amount_sol_out
    print(f'User {user.key()} withdrew {amount_sol_out} SOL.')

@instruction
def deposit_usdc(user: Signer, user_usdc_tkn_acc: TokenAccount, user_lp_usdc_tkn_acc: TokenAccount, pool: oamm, pool_usdc_tkn_acc: TokenAccount, mint_lpusdc: TokenMint, amount_usdc: f64, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  n = f64_to_u64_9_decimal_places(amount_usdc)
  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  amount_lp_usdc,i = single_asset_deposit(1, amount_usdc, balances, LP_tokens_issued, prices)
  m = f64_to_u64_9_decimal_places(amount_lp_usdc)
  bump = pool.bump

  user_usdc_tkn_acc.transfer(
    authority = user,
    to = pool_usdc_tkn_acc,
    amount = n
  )

  mint_lpusdc.mint(
    authority = pool,
    to = user_lp_usdc_tkn_acc,
    amount = m,
    signer = ['oamm', bump]
  )

  pool.balance_usdc+=amount_usdc
  pool.lp_usdc_tokens+=amount_lp_usdc

  print(f'User {user.key()} deposited {amount_usdc} USDC.')


@instruction
def withdraw_usdc(user: Signer, user_lp_usdc_tkn_acc: TokenAccount, user_usdc_tkn_acc: TokenAccount, user_usdt_tkn_acc: TokenAccount, pool: oamm, pool_usdc_tkn_acc: TokenAccount, pool_usdt_tkn_acc: TokenAccount, mint_lpusdc: TokenMint, amount_lp_usdc: f64, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)
  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  delta=pool.delta
  amount_sol_out,amount_usdc_out,amount_usdt_out,ao,remaining = single_asset_withdrawal(1, amount_lp_usdc, balances, LP_tokens_issued, prices,delta)

  amount_lp_usdc_to_burn=amount_lp_usdc*(ao-remaining)/ao
  n_lp_usdc = f64_to_u64_9_decimal_places(amount_lp_usdc_to_burn)

  bump = pool.bump

  mint_lpusdc.burn(
    authority = user,
    holder = user_lp_usdc_tkn_acc,
    amount = n_lp_usdc
  )
  pool.lp_usdc_tokens-=amount_lp_usdc_to_burn
  print(f'{amount_lp_usdc_to_burn} LPUSDC burned from user {user.key()}.')

  if amount_usdc_out != 0.0:
    n_usdc = f64_to_u64_9_decimal_places(amount_usdc_out)
    pool_usdc_tkn_acc.transfer(
      authority = pool,
      to = user_usdc_tkn_acc,
      amount = n_usdc,
      signer = ['oamm', bump]
    )
    pool.balance_usdc-=amount_usdc_out
    print(f'User {user.key()} withdrew {amount_usdc_out} USDC.')

  if amount_usdt_out != 0.0:
    n_usdt = f64_to_u64_9_decimal_places(amount_usdt_out)
    pool_usdt_tkn_acc.transfer(
      authority = pool,
      to = user_usdt_tkn_acc,
      amount = n_usdt,
      signer = ['oamm', bump]
    )
    pool.balance_usdt-=amount_usdt_out
    print(f'User {user.key()} withdrew {amount_usdt_out} USDT.')

  if amount_sol_out != 0.0:
    n_sol = f64_to_u64_9_decimal_places(amount_sol_out)
    pool.transfer_lamports(
      to = user,
      amount = n_sol
    )
    pool.balance_sol-=amount_sol_out
    print(f'User {user.key()} withdrew {amount_sol_out} SOL.')



@instruction
def deposit_usdt(user: Signer, user_usdt_tkn_acc: TokenAccount, user_lp_usdt_tkn_acc: TokenAccount, pool: oamm, pool_usdt_tkn_acc: TokenAccount, mint_lpusdt: TokenMint, amount_usdt: f64, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  n = f64_to_u64_9_decimal_places(amount_usdt)
  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  amount_lp_usdt,i = single_asset_deposit(2, amount_usdt, balances, LP_tokens_issued, prices)
  m = f64_to_u64_9_decimal_places(amount_lp_usdt)
  bump = pool.bump

  user_usdt_tkn_acc.transfer(
    authority = user,
    to = pool_usdt_tkn_acc,
    amount = n
  )

  mint_lpusdt.mint(
    authority = pool,
    to = user_lp_usdt_tkn_acc,
    amount = m,
    signer = ['oamm', bump]
  )

  pool.balance_usdt+=amount_usdt
  pool.lp_usdt_tokens+=amount_lp_usdt

  print(f'User {user.key()} deposited {amount_usdt} USDT.')


@instruction
def withdraw_usdt(user: Signer, user_lp_usdt_tkn_acc: TokenAccount, user_usdc_tkn_acc: TokenAccount, user_usdt_tkn_acc: TokenAccount, pool: oamm, pool_usdc_tkn_acc: TokenAccount, pool_usdt_tkn_acc: TokenAccount, mint_lpusdt: TokenMint, amount_lp_usdt: f64, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  delta=pool.delta
  amount_sol_out,amount_usdc_out,amount_usdt_out,ao,remaining = single_asset_withdrawal(2, amount_lp_usdt, balances, LP_tokens_issued, prices,delta)

  amount_lp_usdt_to_burn=amount_lp_usdt*(ao-remaining)/ao
  n_lp_usdt = f64_to_u64_9_decimal_places(amount_lp_usdt_to_burn)

  bump = pool.bump

  mint_lpusdt.burn(
    authority = user,
    holder = user_lp_usdt_tkn_acc,
    amount = n_lp_usdt
  )
  pool.lp_usdt_tokens-=amount_lp_usdt_to_burn
  print(f'{amount_lp_usdt_to_burn} LPUSDC burned from user {user.key()}.')

  if amount_usdc_out != 0.0:
    n_usdc = f64_to_u64_9_decimal_places(amount_usdc_out)
    pool_usdc_tkn_acc.transfer(
      authority = pool,
      to = user_usdc_tkn_acc,
      amount = n_usdc,
      signer = ['oamm', bump]
    )
    pool.balance_usdc-=amount_usdc_out
    print(f'User {user.key()} withdrew {amount_usdc_out} USDC.')

  if amount_usdt_out != 0.0:
    n_usdt = f64_to_u64_9_decimal_places(amount_usdt_out)
    pool_usdt_tkn_acc.transfer(
      authority = pool,
      to = user_usdt_tkn_acc,
      amount = n_usdt,
      signer = ['oamm', bump]
    )
    pool.balance_usdt-=amount_usdt_out
    print(f'User {user.key()} withdrew {amount_usdt_out} USDT.')

  if amount_sol_out != 0.0:
    n_sol = f64_to_u64_9_decimal_places(amount_sol_out)
    pool.transfer_lamports(
      to = user,
      amount = n_sol
    )
    pool.balance_sol-=amount_sol_out
    print(f'User {user.key()} withdrew {amount_sol_out} SOL.')


@instruction
def trade_sol_in(user: Signer, user_usd_tkn_acc: TokenAccount, pool: oamm, pool_usd_tkn_acc: TokenAccount, amount_sol_in: f64, amount_usd_out: f64, token_out: str, fee_acc_sol: UncheckedAccount, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  delta=pool.delta
  fee=pool.base_fee
  protocol_fee=pool.protocol_fee
  delta=pool.delta
  leverage=pool.base_leverage

  out=[0]

  if token_out == 'USDC':
    out[0]=1
  elif token_out == 'USDT':
    out[0]=2
  else:
    return None

  o=out[0]

  if amount_sol_in != 0.0:

    balances_copy_1=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_1=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_1=array(prices[0],prices[1],prices[2])

    ao,pr_fee,execute_trade=trade_i(0,o,amount_sol_in, balances_copy_1, LP_tokens_issued_copy_1, prices_copy_1,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None

    amount_in = f64_to_u64_9_decimal_places(amount_sol_in)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(ao)

    bump = pool.bump

    pool_usd_tkn_acc.transfer(
      authority = pool,
      to = user_usd_tkn_acc,
      amount = amount_out,
      signer = ['oamm', bump]
    )
    if token_out == 'USDC':
      pool.balance_usdc-=ao
    elif token_out == 'USDT':
      pool.balance_usdt-=ao

    user.transfer_lamports(
      to = pool,
      amount = amount_in
    )
    pool.transfer_lamports(
      to = fee_acc_sol,
      amount = n_pr_fee
    )
    pool.balance_sol+=amount_sol_in-pr_fee

  if amount_sol_in == 0.0:

    balances_copy_2=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_2=array(prices[0],prices[1],prices[2])

    ai,pr_fee,execute_trade=trade_o(0,o,amount_usd_out, balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None


    amount_in = f64_to_u64_9_decimal_places(ai)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(amount_usd_out)


    bump = pool.bump

    pool_usd_tkn_acc.transfer(
      authority = pool,
      to = user_usd_tkn_acc,
      amount = amount_out,
      signer = ['oamm', bump]
    )
    if token_out == 'USDC':
      pool.balance_usdc-=amount_usd_out
    elif token_out == 'USDT':
      pool.balance_usdt-=amount_usd_out

    user.transfer_lamports(
      to = pool,
      amount = amount_in
    )
    pool.transfer_lamports(
      to = fee_acc_sol,
      amount = n_pr_fee
    )
    pool.balance_sol+=ai-pr_fee

@instruction
def trade_sol_out(user: Signer, user_usd_tkn_acc: TokenAccount, pool: oamm, pool_usd_tkn_acc: TokenAccount, amount_usd_in: f64, amount_sol_out: f64, token_in: str, fee_acc_usd: TokenAccount, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  delta=pool.delta
  fee=pool.base_fee
  protocol_fee=pool.protocol_fee
  delta=pool.delta
  leverage=pool.base_leverage

  tok_in=[0]

  if token_in == 'USDC':
    tok_in[0]=1
  elif token_in == 'USDT':
    tok_in[0]=2
  else:
    return None

  i=tok_in[0]

  if amount_usd_in != 0.0:

    balances_copy_1=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_1=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_1=array(prices[0],prices[1],prices[2])

    ao,pr_fee,execute_trade=trade_i(i,0,amount_usd_in, balances_copy_1, LP_tokens_issued_copy_1, prices_copy_1,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None


    amount_in = f64_to_u64_9_decimal_places(amount_usd_in)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(ao)
    bump = pool.bump

    user_usd_tkn_acc.transfer(
      authority = user,
      to = pool_usd_tkn_acc,
      amount = amount_in
    )
    pool_usd_tkn_acc.transfer(
      authority = pool,
      to = fee_acc_usd,
      amount = n_pr_fee,
      signer = ['oamm', bump]
    )
    if token_in == 'USDC':
      pool.balance_usdc+=amount_usd_in-pr_fee
    elif token_in == 'USDT':
      pool.balance_usdt+=amount_usd_in-pr_fee

    pool.transfer_lamports(
      to = user,
      amount = amount_out
    )
    pool.balance_sol-=ao

  if amount_usd_in == 0.0:

    balances_copy_2=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_2=array(prices[0],prices[1],prices[2])

    ai,pr_fee,execute_trade=trade_o(i,0,amount_sol_out, balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None


    amount_in = f64_to_u64_9_decimal_places(ai)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(amount_sol_out)
    bump = pool.bump

    user_usd_tkn_acc.transfer(
      authority = user,
      to = pool_usd_tkn_acc,
      amount = amount_in
    )
    pool_usd_tkn_acc.transfer(
      authority = pool,
      to = fee_acc_usd,
      amount = n_pr_fee,
      signer = ['oamm', bump]
    )
    if token_in == 'USDC':
      pool.balance_usdc+=ai-pr_fee
    elif token_in == 'USDT':
      pool.balance_usdt+=ai-pr_fee

    pool.transfer_lamports(
      to = user,
      amount = amount_out
    )
    pool.balance_sol-=amount_sol_out


@instruction
def trade_usdc_in_usdt_out(user: Signer, user_usdc_tkn_acc: TokenAccount, user_usdt_tkn_acc: TokenAccount, pool: oamm, pool_usdc_tkn_acc: TokenAccount, pool_usdt_tkn_acc: TokenAccount, amount_usdc_in: f64, amount_usdt_out: f64, fee_acc_usdc: TokenAccount, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  delta=pool.delta
  fee=pool.base_fee
  protocol_fee=pool.protocol_fee
  delta=pool.delta
  leverage=pool.base_leverage

  if amount_usdc_in != 0.0:

    balances_copy_1=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_1=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_1=array(prices[0],prices[1],prices[2])

    ao,pr_fee,execute_trade=trade_i(1,2,amount_usdc_in, balances_copy_1, LP_tokens_issued_copy_1, prices_copy_1,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None


    amount_in = f64_to_u64_9_decimal_places(amount_usdc_in)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(ao)
    bump = pool.bump

    user_usdc_tkn_acc.transfer(
      authority = user,
      to = pool_usdc_tkn_acc,
      amount = amount_in
    )
    pool_usdc_tkn_acc.transfer(
      authority = pool,
      to = fee_acc_usdc,
      amount = n_pr_fee,
      signer = ['oamm', bump]
    )

    pool.balance_usdc+=amount_usdc_in-pr_fee

    pool_usdt_tkn_acc.transfer(
      authority = pool,
      to = user_usdt_tkn_acc,
      amount = amount_out,
      signer = ['oamm', bump]
    )

    pool.balance_usdt-=ao


  if amount_usdc_in == 0.0:

    balances_copy_2=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_2=array(prices[0],prices[1],prices[2])

    ai,pr_fee,execute_trade=trade_o(1,2,amount_usdt_out, balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None


    amount_in = f64_to_u64_9_decimal_places(ai)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(amount_usdt_out)
    bump = pool.bump

    user_usdc_tkn_acc.transfer(
      authority = user,
      to = pool_usdc_tkn_acc,
      amount = amount_in
    )
    pool_usdc_tkn_acc.transfer(
      authority = pool,
      to = fee_acc_usdc,
      amount = n_pr_fee,
      signer = ['oamm', bump]
    )

    pool.balance_usdc+=ai-pr_fee

    pool_usdt_tkn_acc.transfer(
      authority = pool,
      to = user_usdt_tkn_acc,
      amount = amount_out,
      signer = ['oamm', bump]
    )
    pool.balance_usdt-=amount_usdt_out



@instruction
def trade_usdt_in_usdc_out(user: Signer, user_usdc_tkn_acc: TokenAccount, user_usdt_tkn_acc: TokenAccount, pool: oamm, pool_usdc_tkn_acc: TokenAccount, pool_usdt_tkn_acc: TokenAccount, amount_usdt_in: f64, amount_usdc_out: f64, fee_acc_usdt: TokenAccount, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):

  balances = array(pool.balance_sol,pool.balance_usdc,pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  delta=pool.delta
  fee=pool.base_fee
  protocol_fee=pool.protocol_fee
  delta=pool.delta
  leverage=pool.base_leverage

  if amount_usdt_in != 0.0:

    balances_copy_1=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_1=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_1=array(prices[0],prices[1],prices[2])

    ao,pr_fee,execute_trade=trade_i(2,1,amount_usdt_in, balances_copy_1, LP_tokens_issued_copy_1, prices_copy_1,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None


    amount_in = f64_to_u64_9_decimal_places(amount_usdt_in)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(ao)
    bump = pool.bump

    user_usdt_tkn_acc.transfer(
      authority = user,
      to = pool_usdt_tkn_acc,
      amount = amount_in
    )
    pool_usdt_tkn_acc.transfer(
      authority = pool,
      to = fee_acc_usdt,
      amount = n_pr_fee,
      signer = ['oamm', bump]
    )

    pool.balance_usdt+=amount_usdt_in-pr_fee

    pool_usdc_tkn_acc.transfer(
      authority = pool,
      to = user_usdc_tkn_acc,
      amount = amount_out,
      signer = ['oamm', bump]
    )
    pool.balance_usdc-=ao



  if amount_usdt_in == 0.0:

    balances_copy_2=array(balances[0],balances[1],balances[2])
    LP_tokens_issued_copy_2=array(LP_tokens_issued[0],LP_tokens_issued[1],LP_tokens_issued[2])
    prices_copy_2=array(prices[0],prices[1],prices[2])

    ai,pr_fee,execute_trade=trade_o(2,1,amount_usdc_out, balances_copy_2, LP_tokens_issued_copy_2, prices_copy_2,fee,protocol_fee,leverage,delta)

    if not execute_trade:
      print('Trade not performed.')
      return None


    amount_in = f64_to_u64_9_decimal_places(ai)
    n_pr_fee = f64_to_u64_9_decimal_places(pr_fee)
    amount_out = f64_to_u64_9_decimal_places(amount_usdc_out)
    bump = pool.bump

    user_usdt_tkn_acc.transfer(
      authority = user,
      to = pool_usdt_tkn_acc,
      amount = amount_in
    )
    pool_usdt_tkn_acc.transfer(
      authority = pool,
      to = fee_acc_usdt,
      amount = n_pr_fee,
      signer = ['oamm', bump]
    )

    pool.balance_usdt+=ai-pr_fee

    pool_usdc_tkn_acc.transfer(
      authority = pool,
      to = user_usdc_tkn_acc,
      amount = amount_out,
      signer = ['oamm', bump]
    )

    pool.balance_usdc-=amount_usdc_out



@instruction
def test_convert_to_u64(user: Signer, x: f64):
    a=f64_to_u64_9_decimal_places(x)
    print(f'Return: {a}')



@instruction
def pool_state(user: Signer, pool: oamm, price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):
  print(f'Balances: {pool.balance_sol} SOL - {pool.balance_usdc} USDC - {pool.balance_usdt} USDT.')
  print(f'LP tokens issued: {pool.lp_sol_tokens} LPSOL - {pool.lp_usdc_tokens} LPUSDC - {pool.lp_usdt_tokens} LPUSDT.')

  balances = array(pool.balance_sol, pool.balance_usdc, pool.balance_usdt)
  LP_tokens_issued = array(pool.lp_sol_tokens,pool.lp_usdc_tokens,pool.lp_usdt_tokens)

  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  prices = array(x,y,z)
  #prices = array(20.0,1.0,1.0) # take from oracle
  imb_ratios = imbalance_ratios(balances, LP_tokens_issued, prices)

  print(f'Imbalance ratios: {imb_ratios[0]}, {imb_ratios[1]}, {imb_ratios[2]}.')


@instruction
def update_pool_state(user: Signer, pool: oamm, sol_update: f64, usdc_update: f64, usdt_update: f64, lp_sol_update: f64, lp_usdc_update: f64, lp_usdt_update: f64):
    pool.balance_sol+=sol_update
    pool.balance_usdc+=usdc_update
    pool.balance_usdt+=usdt_update
    pool.lp_sol_tokens+=lp_sol_update
    pool.lp_usdc_tokens+=lp_usdc_update
    pool.lp_usdt_tokens+=lp_usdt_update

def retrieve_prices(price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount) -> Tuple[f64,f64,f64]:
  price_feed = price_account_sol.validate_price_feed('devnet-SOL/USD')
  price = price_feed.get_price()
  x: f64 = price.num()
  #price_feed = price_account_usdc.validate_price_feed('devnet-USDC/USD')
  #price = price_feed.get_price()
  #y: f64 = price.num()
  y=1.0
  price_feed = price_account_usdt.validate_price_feed('devnet-USDT/USD')
  price = price_feed.get_price()
  z: f64 = price.num()
  print(f'The current prices are: {x}, {y}, {z}.')
  return x,y,z

@instruction
def test_prices(price_account_sol: PriceAccount, price_account_usdc: PriceAccount, price_account_usdt: PriceAccount):
  price_feed = price_account_sol.validate_price_feed('devnet-SOL/USD')
  price = price_feed.get_price()
  x: f64 = price.num()
  print(x)
  #price_feed = price_account_usdc.validate_price_feed('devnet-USDC/USD')
  #price = price_feed.get_price()
  #y: f64 = price.num()
  #print(y)
  price_feed = price_account_usdt.validate_price_feed('devnet-USDT/USD')
  price = price_feed.get_price()
  z: f64 = price.num()
  print(z)
  x,y,z = retrieve_prices(price_account_sol, price_account_usdc, price_account_usdt)
  print(f'The current prices are: {x}, {y}, {z}.')

@instruction
def test_USDC_price(price_account_usdc: PriceAccount):
  print('0')
  price_feed = price_account_usdc.validate_price_feed('devnet-USDC/USD')
  print('1')
  price = price_feed.get_price()
  print('2')
  x: f64 = price.num()
  print(x)
