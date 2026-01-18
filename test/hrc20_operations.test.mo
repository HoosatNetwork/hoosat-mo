import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";

import HRC20Operations "../src/hrc20/operations";
import HRC20Types "../src/hrc20/types";

persistent actor {

    private func assertEqual<T>(
        actual: T,
        expected: T,
        message: Text,
        eq: (T, T) -> Bool,
        toText: T -> Text
    ) : Bool {
        if (eq(actual, expected)) {
            Debug.print("✅ PASS: " # message);
            true
        } else {
            Debug.print("❌ FAIL: " # message);
            Debug.print("  Expected: " # toText(expected));
            Debug.print("  Actual:   " # toText(actual));
            false
        }
    };

    private func textEq(a: Text, b: Text) : Bool { a == b };
    private func textToText(t: Text) : Text { t };

    public func runTests() : async Text {
        Debug.print("🧪 Running HRC20 Operations Tests...");

        var passed : Nat = 0;
        var total : Nat = 0;

        // Test 1: formatDeployMint - basic fields
        total += 1;
        let deploy_params : HRC20Types.DeployMintParams = {
            tick = "HOOS";
            max = "2100000000000000";
            lim = "100000000000";
            to = null;
            dec = null;
            pre = null;
        };
        let deploy_json = HRC20Operations.formatDeployMint(deploy_params);
        let expected_deploy = "{\"p\":\"hrc-20\",\"op\":\"deploy\",\"tick\":\"HOOS\",\"max\":\"2100000000000000\",\"lim\":\"100000000000\"}";

        if (assertEqual(
            deploy_json,
            expected_deploy,
            "formatDeployMint basic fields",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 2: formatDeployMint - with optional fields
        total += 1;
        let deploy_params_full : HRC20Types.DeployMintParams = {
            tick = "TEST";
            max = "1000000";
            lim = "1000";
            to = ?"hoosat:qz0000000000000000000000000000000000000000000000000000000000000000";
            dec = ?8;
            pre = ?"500000";
        };
        let deploy_json_full = HRC20Operations.formatDeployMint(deploy_params_full);

        // Check it includes all fields
        let includes_to = Text.contains(deploy_json_full, #text "\"to\":\"hoosat:");
        let includes_dec = Text.contains(deploy_json_full, #text "\"dec\":\"8\"");  // dec is a string
        let includes_pre = Text.contains(deploy_json_full, #text "\"pre\":\"500000\"");
        let all_optional_fields = includes_to and includes_dec and includes_pre;

        if (all_optional_fields) {
            Debug.print("✅ PASS: formatDeployMint includes all optional fields");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: formatDeployMint should include all optional fields");
        };

        // Test 3: formatMint
        total += 1;
        let mint_params : HRC20Types.MintParams = {
            tick = "HOOS";
            to = null;
        };
        let mint_json = HRC20Operations.formatMint(mint_params);
        let expected_mint = "{\"p\":\"hrc-20\",\"op\":\"mint\",\"tick\":\"HOOS\"}";

        if (assertEqual(
            mint_json,
            expected_mint,
            "formatMint basic",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 4: formatMint with recipient
        total += 1;
        let mint_params_to : HRC20Types.MintParams = {
            tick = "HOOS";
            to = ?"hoosat:qz0000000000000000000000000000000000000000000000000000000000000000";
        };
        let mint_json_to = HRC20Operations.formatMint(mint_params_to);

        let mint_includes_to = Text.contains(mint_json_to, #text "\"to\":\"hoosat:");
        if (mint_includes_to) {
            Debug.print("✅ PASS: formatMint includes recipient");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: formatMint should include recipient");
        };

        // Test 5: formatTransferMint
        total += 1;
        let transfer_params : HRC20Types.TransferMintParams = {
            tick = "HOOS";
            amt = "100000000";
            to = "hoosat:qz0000000000000000000000000000000000000000000000000000000000000000";
        };
        let transfer_json = HRC20Operations.formatTransferMint(transfer_params);
        let expected_transfer = "{\"p\":\"hrc-20\",\"op\":\"transfer\",\"tick\":\"HOOS\",\"amt\":\"100000000\",\"to\":\"hoosat:qz0000000000000000000000000000000000000000000000000000000000000000\"}";

        if (assertEqual(
            transfer_json,
            expected_transfer,
            "formatTransferMint",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 6: formatBurnMint
        total += 1;
        let burn_params : HRC20Types.BurnMintParams = {
            tick = "HOOS";
            amt = "6600000000";
        };
        let burn_json = HRC20Operations.formatBurnMint(burn_params);
        let expected_burn = "{\"p\":\"hrc-20\",\"op\":\"burn\",\"tick\":\"HOOS\",\"amt\":\"6600000000\"}";

        if (assertEqual(
            burn_json,
            expected_burn,
            "formatBurnMint",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 7: formatList
        total += 1;
        let list_params : HRC20Types.ListParams = {
            tick = "TEST";  // Mixed case
            amt = "292960000000";
        };
        let list_json = HRC20Operations.formatList(list_params);
        let expected_list = "{\"p\":\"hrc-20\",\"op\":\"list\",\"tick\":\"test\",\"amt\":\"292960000000\"}";

        if (assertEqual(
            list_json,
            expected_list,
            "formatList converts tick to lowercase",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 8: formatSend
        total += 1;
        let send_params : HRC20Types.SendParams = {
            tick = "TEST";  // Mixed case
        };
        let send_json = HRC20Operations.formatSend(send_params);
        let expected_send = "{\"p\":\"hrc-20\",\"op\":\"send\",\"tick\":\"test\"}";

        if (assertEqual(
            send_json,
            expected_send,
            "formatSend converts tick to lowercase",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test 9: No spaces in JSON
        total += 1;
        let deploy_no_spaces = not Text.contains(deploy_json, #text " ");
        let mint_no_spaces = not Text.contains(mint_json, #text " ");
        let transfer_no_spaces = not Text.contains(transfer_json, #text " ");

        if (deploy_no_spaces and mint_no_spaces and transfer_no_spaces) {
            Debug.print("✅ PASS: JSON outputs contain no spaces");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: JSON outputs should not contain spaces");
        };

        // Test 10: formatDeployIssue
        total += 1;
        let deploy_issue_params : HRC20Types.DeployIssueParams = {
            name = "MYTOKEN";
            max = "1000000000";
            mod = "issue";
            to = null;
            dec = null;
            pre = null;
        };
        let deploy_issue_json = HRC20Operations.formatDeployIssue(deploy_issue_params);

        let includes_mod = Text.contains(deploy_issue_json, #text "\"mod\":\"issue\"");
        let includes_name = Text.contains(deploy_issue_json, #text "\"name\":\"MYTOKEN\"");

        if (includes_mod and includes_name) {
            Debug.print("✅ PASS: formatDeployIssue includes mod and name");
            passed += 1;
        } else {
            Debug.print("❌ FAIL: formatDeployIssue should include mod and name fields");
        };

        // Print summary
        Debug.print("\n📊 Test Summary:");
        Debug.print("Passed: " # Nat.toText(passed) # "/" # Nat.toText(total));

        if (passed == total) {
            Debug.print("🎉 All tests passed!");
            "All tests passed ✅"
        } else {
            Debug.print("⚠️  Some tests failed");
            "Some tests failed ❌"
        }
    };
};
