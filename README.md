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
