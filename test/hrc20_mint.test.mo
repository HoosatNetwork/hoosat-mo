/// Test file for HRC20 mint operations
///
/// Run with: mops test hrc20_mint.test.mo
///
/// These tests verify:
/// - Mint JSON formatting
/// - Mint parameter validation
/// - Commit transaction structure
/// - Fee calculations

import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Char "mo:base/Char";

import HRC20Types "../src/hrc20/types";
import HRC20Operations "../src/hrc20/operations";
import HRC20Builder "../src/hrc20/builder";

// Simple test helpers
func assertEqual<T>(actual: T, expected: T, toString: (T) -> Text, testName: Text) {
    let actualStr = toString(actual);
    let expectedStr = toString(expected);
    if (actualStr == expectedStr) {
        Debug.print("✅ " # testName);
    } else {
        Debug.print("❌ " # testName);
        Debug.print("   Expected: " # expectedStr);
        Debug.print("   Got: " # actualStr);
    };
};

func assertTextEqual(actual: Text, expected: Text, testName: Text) {
    assertEqual<Text>(actual, expected, func(t) { t }, testName);
};

func assertContains(text: Text, substring: Text, testName: Text) {
    if (Text.contains(text, #text(substring))) {
        Debug.print("✅ " # testName);
    } else {
        Debug.print("❌ " # testName);
        Debug.print("   Expected to contain: " # substring);
        Debug.print("   In text: " # text);
    };
};

// Test 1: Format mint operation with recipient
Debug.print("\n🧪 Test: Format mint operation with recipient");
let mint_params_1 : HRC20Types.MintParams = {
    tick = "HOOS";
    to = ?"hoosattest:qzk3xkr8mhgf7kd5x9p2ycv8w4h6n5j7m8l9k0p1q2r3s4t5u6v7w8x9y0z1a2b3";
};
let mint_json_1 = HRC20Operations.formatMint(mint_params_1);
assertContains(mint_json_1, "\"p\":\"hrc-20\"", "Contains protocol");
assertContains(mint_json_1, "\"op\":\"mint\"", "Contains operation");
assertContains(mint_json_1, "\"tick\":\"HOOS\"", "Contains tick (case preserved)");
assertContains(mint_json_1, "\"to\":\"hoosattest:", "Contains recipient address");
Debug.print("   JSON: " # mint_json_1);

// Test 2: Format mint operation without recipient (to deployer)
Debug.print("\n🧪 Test: Format mint operation without recipient");
let mint_params_2 : HRC20Types.MintParams = {
    tick = "TEST";
    to = null;
};
let mint_json_2 = HRC20Operations.formatMint(mint_params_2);
assertContains(mint_json_2, "\"op\":\"mint\"", "Contains operation");
assertContains(mint_json_2, "\"tick\":\"TEST\"", "Contains tick (case preserved)");
// When 'to' is null, it should not be in the JSON (mints to deployer)
if (not Text.contains(mint_json_2, #text("\"to\":"))) {
    Debug.print("✅ No 'to' field when recipient is null");
} else {
    Debug.print("❌ Should not have 'to' field when recipient is null");
    Debug.print("   JSON: " # mint_json_2);
};
Debug.print("   JSON: " # mint_json_2);

// Test 3: Verify mint fee estimation
Debug.print("\n🧪 Test: Estimate mint fees");
let (commit_fee, reveal_fee) = HRC20Builder.estimateFees(mint_json_1);
Debug.print("   Commit fee: " # debug_show(commit_fee) # " sompi");
Debug.print("   Reveal fee: " # debug_show(reveal_fee) # " sompi");
// Mint should be 1 HTN (100,000,000 sompi)
if (commit_fee == 100_000_000 or commit_fee == 0) {
    Debug.print("✅ Mint commit fee is reasonable (1 HTN or estimated)");
} else {
    Debug.print("⚠️  Unexpected commit fee: " # debug_show(commit_fee));
};

// Test 4: Format different tickers
Debug.print("\n🧪 Test: Format mint with various tickers");
let tickers = ["ABCD", "ABCDE", "ABCDEF", "HOOSA"];
for (tick in tickers.vals()) {
    let params : HRC20Types.MintParams = {
        tick = tick;
        to = null;
    };
    let json = HRC20Operations.formatMint(params);
    // Mint operations preserve case (only list/send operations lowercase)
    assertContains(json, "\"tick\":\"" # tick # "\"", "Ticker " # tick # " formatted correctly");
};

// Test 5: Verify minimum commit amount
Debug.print("\n🧪 Test: Minimum commit amount constant");
let min_commit = HRC20Builder.MIN_COMMIT_AMOUNT;
Debug.print("   MIN_COMMIT_AMOUNT: " # debug_show(min_commit) # " sompi");
if (min_commit >= 1000) {  // Should be at least dust threshold
    Debug.print("✅ MIN_COMMIT_AMOUNT is above dust threshold");
} else {
    Debug.print("❌ MIN_COMMIT_AMOUNT is too low: " # debug_show(min_commit));
};

// Test 6: Verify recommended commit amount
Debug.print("\n🧪 Test: Recommended commit amount constant");
let rec_commit = HRC20Builder.RECOMMENDED_COMMIT_AMOUNT;
Debug.print("   RECOMMENDED_COMMIT_AMOUNT: " # debug_show(rec_commit) # " sompi");
if (rec_commit >= min_commit) {
    Debug.print("✅ RECOMMENDED_COMMIT_AMOUNT >= MIN_COMMIT_AMOUNT");
} else {
    Debug.print("❌ RECOMMENDED_COMMIT_AMOUNT is less than MIN_COMMIT_AMOUNT");
};

Debug.print("\n✨ Mint operation tests complete!\n");
Debug.print("📝 Note: To test actual commit/reveal transactions, use:");
Debug.print("   dfx canister call hrc20_example mintTokenWithBroadcast '(\"TICKER\", null)'");
Debug.print("   dfx canister call hrc20_example revealOperation '(\"commit_tx_id\", \"address\")'");
Debug.print("\n📝 Note: API helper functions:");
Debug.print("   - getHRC20TokenBalance() for token balances");
Debug.print("   - getHRC20TokenList() for all tokens");
Debug.print("\n📝 To test balances:");
Debug.print("   dfx canister call hrc20_example getHRC20TokenBalance '(\"ADDRESS\", \"HOOS\")'");
Debug.print("   dfx canister call hrc20_example getHRC20TokenList '(\"ADDRESS\")'");
