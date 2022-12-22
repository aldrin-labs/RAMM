use std::convert::TryInto;

fn weights(balances: Vec<f64>, prices: Vec<f64>) -> Vec<f64> {
    assert_eq!(balances.len(), prices.len(), "Balance list and price list do not have the same length.");
    let n = balances.len();
    let mut B = 0.0;
    let mut W = vec![0.0; n];
    for j in 0..n {
        let price = prices[j];
        let balance = balances[j];
        B += price * balance;
    }
    for j in 0..n {
        let price = prices[j];
        let balance = balances[j];
        W[j] = price * balance / B;
    }
    W
}

fn compute_B_and_L(balances: Vec<f64>, LP_tokens_issued: Vec<f64>, prices: Vec<f64>) -> (f64, f64) {
    assert_eq!(balances.len(), prices.len(), "Balance list and price list do not have the same length.");
    assert_eq!(balances.len(), LP_tokens_issued.len(), "Balance list and list of amount of LP tokens issued do not have the same length.");
    let n = balances.len();
    let mut B = 0.0;
    let mut L = 0.0;
    for j in 0..n {
        let price = prices[j];
        let balance = balances[j];
        let lptok = LP_tokens_issued[j];
        B += price * balance;
        L += price * lptok;
    }
    (B, L)
}

fn imbalance_ratios(balances: Vec<f64>, LP_tokens_issued: Vec<f64>, prices: Vec<f64>) -> Vec<f64> {
    assert_eq!(balances.len(), prices.len(), "Balance list and price list do not have the same length.");
    assert_eq!(balances.len(), LP_tokens_issued.len(), "Balance list and list of amount of LP tokens issued do not have the same length.");
    let n = balances.len();
    let mut W = vec![0.0; n];
    let LP_tokens_issued_copy = LP_tokens_issued.clone();
    let (B, L) = compute_B_and_L(balances.clone(), LP_tokens_issued_copy, prices.clone());
    for j in 0..n {
        let lptok = LP_tokens_issued[j];
        if lptok != 0.0 {
            let balance = balances[j];
            W[j] = (balance * L) / (B * lptok);
        } else {
            W[j] = -1.0;
        }
    }
    W
}

fn check_imbalance_ratios(
    balances: Vec<f64>,
    LP_tokens_issued: Vec<f64>,
    prices: Vec<f64>,
    i: u8,
    o: u8,
    ai: f64,
    ao: f64,
    pr_fee: f64,
    delta: f64,
) -> bool {
    let balances_list = balances.clone();
    let LP_tokens_list = LP_tokens_issued.clone();
    let prices_list = prices.clone();
    let balances_before = vec![balances_list[0], balances_list[1], balances_list[2]];
    let LP_tokens_issued_before = vec![LP_tokens_issued[0], LP_tokens_issued[1], LP_tokens_issued[2]];
    let prices_before = vec![prices[0], prices[1], prices[2]];
    let W_before = imbalance_ratios(balances_before, LP_tokens_issued_before, prices_before);
    balances_list[i as usize] += ai;
    LP_tokens_list[i as usize] += ai * pr_fee;
    balances_list[o as usize] -= ao;
    let balances_after = vec![balances_list[0], balances_list[1], balances_list[2]];
    let LP_tokens_issued_after = vec![LP_tokens_list[0], LP_tokens_list[1], LP_tokens_list[2]];
    let W_after = imbalance_ratios(balances_after, LP_tokens_issued_after, prices_before);
    for j in 0..3 {
        let W_j_before = W_before[j];
        let W_j_after = W_after[j];
        if (W_j_after - W_j_before).abs() > delta {
            return false;
        }
    }
    true
}

fn main() {
    let balances = vec![100.0, 100.0, 100.0];
    let LP_tokens_issued = vec![100.0, 100.0, 100.0];
    let prices = vec![1.0, 1.0, 1.0];
    let i: u8 = 0;
    let o: u8 = 1;
    let ai = 10.0;
    let ao = 10.0;
    let pr_fee = 0.1;
    let delta = 0.1;
    let result = check_imbalance_ratios(balances, LP_tokens_issued, prices, i, o, ai, ao, pr_fee, delta);
    println!("Result: {}", result);
}
