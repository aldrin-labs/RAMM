# Oracle-based AMM

The oracle-based AMM (OAMM) is an AMM that takes prices from an oracle in order to avoid impermanent loss. This code was written for the Solana network using [Seahorse](https://seahorse-lang.org/) 0.2.5.

The particular code of this repository is designed for a SOL/USDC/USDT pool, but with a few tweaks in can be easily adapted to any pool with any number of tokens. 

One of the features of the OAMM is that liquidity providers can provide liquidity of just one asset, and the pool will mint a certain type of LP tokens according to the asset the liquidity provider is depositing. In consequence, this particular pool will mint three types of LP tokens: `LPSOL`, `LPUSDC` and `LPUSDT`.

## Code walthrough

Each OAMM pool consists of a single account that belongs to the `oamm` class and contains the data described below.

`balance_sol`: `f64` The current balance of SOL in the pool.

`balance_usdc`: `f64` The current balance of USDC in the pool.

`balance_usdt`: `f64` The current balance of USDT in the pool.

`lp_sol_tokens`: `f64` The current amount of LPSOL tokens in circulation.

`lp_usdc_tokens`: `f64` The current amount of LPUSDT tokens in circulation.

`lp_usdt_tokens`: `f64` The current amount of LPUSDC tokens in circulation.

`base_fee`: `f64` The base fee that the pool charges. The suggested value for the Solana network is `0.0008`, which amounts to 0.08%.

`protocol_fee`: `f64` The share of the fees that the protocol charges for itself. The suggested value is `0.5`, which means that half of the collected fees will be kept as revenue for the protocol, while the other half will be deposited into the pool and shared among the liquidity providers.

`base_leverage`: `f64` The base leverage parameter that the pool will use. This serves to concentrate liquidity around the current market price. The suggested value for this parameter is `100`.

`delta`: `f64` The maximum deviation in the imbalances ratios permitted. The suggested value for this parameter is `0.25`, which means that the imbalance ratios that are allowed are those between `0.75` and `1.25`. Trades that push imbalance ratios outside this range will not be allowed. This parameter is designed to prevent the pool from being heavy unbalanced.

`bump`: `u8` The value of the `bump` parameter of the pool account.

### Accounts

Before describing what our program does, we will describe all the Solana accounts that are involved in the different instructions.

**Pool accounts**

`pool`: The Solana account of the pool. Belongs to the `oamm` class as described above. Holds the SOL deposited into the pool.

`pool_usdc_tkn_acc`: The `TokenAccount` that will hold the USDC deposited into the pool. The owner of this account is the `pool`'s account.

`pool_usdc_tkn_acc`: The `TokenAccount` that will hold the USDT deposited into the pool. The owner of this account is the `pool`'s account.

`mint_lpsol`: The `TokenMint` account that will `mint` and `burn` the LPSOL tokens.

`mint_lpusdc`: The `TokenMint` account that will `mint` and `burn` the LPUSDC tokens.

`mint_lpusdt`: The `TokenMint` account that will `mint` and `burn` the LPUSDT tokens.

**User accounts**

`user`: `Signer` account. The account of the user that interacts with the OAMM.

`user_usdc_tkn_acc`: User's `TokenAccount` that holds USDC. Its owner is the `user` account.

`user_usdt_tkn_acc`: User's `TokenAccount` that holds USDT. Its owner is the `user` account.

`user_lp_sol_tkn_acc`: User's `TokenAccount` that holds LPSOL. Its owner is the `user` account.

`user_lp_usdc_tkn_acc`: User's `TokenAccount` that holds LPUSDC. Its owner is the `user` account.

`user_lp_usdt_tkn_acc`: User's `TokenAccount` that holds LPUSDT. Its owner is the `user` account.

**Price accounts**

`price_account_sol`: The [Pyth network](https://pyth.network/) Solana account that tracks the price of the pair [SOL/USD](https://pyth.network/price-feeds/crypto-sol-usd?cluster=mainnet-beta).

`price_account_usdc`: The [Pyth network](https://pyth.network/) Solana account that tracks the price of the pair [USDC/USD](https://pyth.network/price-feeds/crypto-usdc-usd?cluster=mainnet-beta).

`price_account_usdt`: The [Pyth network](https://pyth.network/) Solana account that tracks the price of the pair [USDT/USD](https://pyth.network/price-feeds/crypto-usdt-usd?cluster=mainnet-beta).

**Fee accounts**

`fee_acc_sol`: Solana account that holds the fees collected in SOL.

`fee_acc_usdc`: `TokenAccount` that holds the fees collected in USDC.

`fee_acc_usdt`: `TokenAccount` that holds the fees collected in USDT.

*Remark*: When a parameter given to an instruction is denoted by `*_usd_tkn_acc` instead of `*_usdc_tkn_acc` or `*_usdt_tkn_acc` it means that the instruction will be used for both cases and the account that is passed in as a parameter should be the one that corresponds to the token that will be traded. A similar reasoning applies when we use `fee_acc_usd` instead of `fee_acc_usdc` or `fee_acc_usdt`.


### Instructions

Now, we describe our program's instructions.

- `init`

Initializes the pool account and the three `TokenMint` accounts that correspond to the three types of LP tokens to be minted. Takes as parameters `basefee`, `protocolfee`, `baseleverage` and `delta`, which are set and fixed with this instruction and can not be changed later.

- `deposit_sol`

Performs a liquidity deposit of a certain amount of SOL. Its parameters are `amount_sol` (the amount of SOL to be provided as liquidity), the corresponding Solana accounts, `TokenAccount`s and `TokenMint` accounts needed, and the price accounts.



