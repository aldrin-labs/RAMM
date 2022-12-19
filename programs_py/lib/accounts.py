# oamm
# Built with Seahorse v0.2.5
#
# This file contains the public keys related to the SOL/USDC/USDT OAMM and is used for permission checks.

def get_public_keys() -> Tuple[str,str,str,str,str,str,str,str,str,str,str,str]:
    owner_pubkey='DzgBxedPKCuWbK4a4P9Bj4nNdayVzZEqc7n6YZ1A4sLa'
    mint_usdc_pubkey='3AdmphpXt2Cnum2WZPB5mwqHHoSg8943YgYe5Z4Phk8u'
    mint_usdt_pubkey='2fXzsHWhhcNqTbigYDKEYwv6k5aYNqSXHjLNv1RJdXy9'
    pool_pubkey='GkTxPhwRzb8xocBJMew7iVUwq2dzeTm5dZ3GkWYqMHA'
    pool_usdc_token_account_pubkey='4QTUMW3sScb8jmKAYbcbiWoCYi9nRyXAyub9cHAXNfUb'
    pool_usdt_token_account_pubkey='D4d2Zcw6JeShSNSBVFPYWtUQ9HXG9cApsTvcrPiDxzUY'
    pool_mint_lp_sol_pubkey='6hFQSgkGFkZiRC9joDybk9U6L2X1CJgvp6eKoxGdrbTz'
    pool_mint_lp_usdc_pubkey='5oQPPFRw4LECv8VnMp5gm5Bep5wpbUy2iZ8JcQLRZ4gk'
    pool_mint_lp_usdt_pubkey='51pkDvEgjRhZMb9VYihtJnjQLKj2uj3YJvLBb2ReJ6rQ'
    fee_account_sol_pubkey = 'D6U9ms9icRKY1oFrN57v5cui5Y89cNUzCutw1keUH8CM'
    fee_account_usdc_pubkey = '3v5mLWxqReiegzaLDm1TizpaTyaiEtvY4WPHAabvUNR4'
    fee_account_usdt_pubkey = '2Bcashf4mF4m3ex7YtjiAYoniGpgAC5a1cnGYVwxqeNo'
    return str(owner_pubkey), str(mint_usdc_pubkey), str(mint_usdt_pubkey), str(pool_pubkey), str(pool_usdc_token_account_pubkey), str(pool_usdt_token_account_pubkey), str(pool_mint_lp_sol_pubkey), str(pool_mint_lp_usdc_pubkey), str(pool_mint_lp_usdt_pubkey), str(fee_account_sol_pubkey), str(fee_account_usdc_pubkey), str(fee_account_usdt_pubkey)

# call this function as:
# owner_pub_key, mint_usdc_pubkey, mint_usdt_pubkey, pool_pubkey, pool_usdc_token_account_pubkey, pool_usdt_token_account_pubkey, pool_mint_lp_sol, pool_mint_lp_usdc, pool_mint_lp_usdt, fee_account_sol, fee_account_usdc, fee_account_usdt = get_public_keys()
