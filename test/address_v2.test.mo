import Debug "mo:base/Debug";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Result "mo:base/Result";

import Address "../src/address";
import Errors "../src/errors";

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
            Debug.print("❌ FAIL: " # message # " (expected: " # toText(expected) # ", actual: " # toText(actual) # ")");
            false
        }
    };

    private func assertResult<T>(
        result: Result.Result<T, Errors.HoosatError>,
        expected_ok: Bool,
        message: Text
    ) : Bool {
        let is_ok = switch (result) {
            case (#ok(_)) { true };
            case (#err(error)) {
                if (not expected_ok) {
                    Debug.print("Expected error: " # Errors.errorToText(error));
                };
                false
            };
        };

        if (is_ok == expected_ok) {
            Debug.print("✅ PASS: " # message);
            true
        } else {
            Debug.print("❌ FAIL: " # message # " (expected: " # (if (expected_ok) "ok" else "error") # ")");
            false
        }
    };

    private func textEq(a: Text, b: Text) : Bool { a == b };
    private func textToText(t: Text) : Text { t };

    public func runTests() : async Text {
        Debug.print("🧪 Running AddressV2 Tests...");

        // Run all test functions
        test_hex_utilities();
        test_script_generation();
        test_address_operations();
        test_custom_prefixes();
        test_backward_compatibility();

        var passed : Nat = 0;
        var total : Nat = 0;

        // Simple hex test
        let bytes : [Nat8] = [0xDE, 0xAD, 0xBE, 0xEF];
        let hex = Address.hexFromArray(bytes);
        total += 1;
        if (assertEqual(
            hex,
            "deadbeef",
            "Hex encoding should work correctly",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        // Test hex decoding
        total += 1;
        switch (Address.arrayFromHex("deadbeef")) {
            case (#ok(decoded)) {
                let matches = Array.equal(decoded, bytes, func(a, b) { a == b });
                if (assertEqual(
                    matches,
                    true,
                    "Hex decoding should work correctly",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                )) {
                    passed += 1;
                };
            };
            case (#err(_)) {
                Debug.print("❌ FAIL: Hex decoding failed unexpectedly");
            };
        };

        // Test invalid hex
        total += 1;
        switch (Address.arrayFromHex("invalid")) {
            case (#ok(_)) {
                Debug.print("❌ FAIL: Invalid hex should fail");
            };
            case (#err(_)) {
                Debug.print("✅ PASS: Invalid hex correctly failed");
                passed += 1;
            };
        };

        // Test Schnorr script generation
        total += 1;
        let schnorr_pubkey = Array.freeze(Array.init<Nat8>(32, 0xAB));
        switch (Address.generateScriptPublicKey(schnorr_pubkey, Address.SCHNORR)) {
            case (#ok(script)) {
                let starts_correctly = Text.startsWith(script, #text("20")); // OP_DATA_32
                let ends_correctly = Text.endsWith(script, #text("ac")); // OP_CHECKSIG
                if (assertEqual(
                    starts_correctly and ends_correctly,
                    true,
                    "Schnorr script should have correct format",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                )) {
                    passed += 1;
                };
            };
            case (#err(_)) {
                Debug.print("❌ FAIL: Schnorr script generation failed");
            };
        };

        // Test ECDSA script generation
        total += 1;
        let ecdsa_pubkey = Array.tabulate<Nat8>(33, func(i) { if (i == 0) 0x02 else 0xAB });
        switch (Address.generateScriptPublicKey(ecdsa_pubkey, Address.ECDSA)) {
            case (#ok(script)) {
                let starts_correctly = Text.startsWith(script, #text("21")); // OP_DATA_33
                let ends_correctly = Text.endsWith(script, #text("ab")); // OP_CHECKSIG_ECDSA
                if (assertEqual(
                    starts_correctly and ends_correctly,
                    true,
                    "ECDSA script should have correct format",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                )) {
                    passed += 1;
                };
            };
            case (#err(_)) {
                Debug.print("❌ FAIL: ECDSA script generation failed");
            };
        };

        // Test backward compatibility
        total += 1;
        let test_bytes : [Nat8] = [0xDE, 0xAD, 0xBE, 0xEF];
        let compat_hex = Address.hex_from_array(test_bytes);
        if (assertEqual(
            compat_hex,
            "deadbeef",
            "Backward compatible hex_from_array should work",
            textEq,
            textToText
        )) {
            passed += 1;
        };

        let summary = "Test Summary: " # Nat.toText(passed) # "/" # Nat.toText(total) # " tests passed";
        Debug.print("🏁 " # summary);
        summary
    };

    private func test_hex_utilities() {
        Debug.print("\n🔢 Testing Hex Utilities");

        // Test hex encoding
        let bytes : [Nat8] = [0xDE, 0xAD, 0xBE, 0xEF];
        let hex = Address.hexFromArray(bytes);
        ignore assertEqual(
            hex,
            "deadbeef",
            "Hex encoding should work correctly",
            textEq,
            textToText
        );

        // Test hex decoding
        switch (Address.arrayFromHex("deadbeef")) {
            case (#ok(decoded)) {
                let matches = Array.equal(decoded, bytes, func(a, b) { a == b });
                ignore assertEqual(
                    matches,
                    true,
                    "Hex decoding should work correctly",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                );
            };
            case (#err(_)) {
                Debug.print("❌ FAIL: Hex decoding failed unexpectedly");
            };
        };

        // Test invalid hex
        ignore assertResult(
            Address.arrayFromHex("invalid"),
            false,
            "Invalid hex should fail"
        );

        ignore assertResult(
            Address.arrayFromHex("deadbee"), // Odd length
            false,
            "Odd length hex should fail"
        );
    };

    private func test_script_generation() {
        Debug.print("\n📜 Testing Script Generation");

        // Test Schnorr script generation
        let schnorr_pubkey = Array.freeze(Array.init<Nat8>(32, 0xAB));
        switch (Address.generateScriptPublicKey(schnorr_pubkey, Address.SCHNORR)) {
            case (#ok(script)) {
                // Should be: 20 (OP_DATA_32) + 32 bytes of pubkey + AC (OP_CHECKSIG)
                let expected_prefix = "20"; // OP_DATA_32
                let expected_suffix = "ac"; // OP_CHECKSIG
                let starts_correctly = Text.startsWith(script, #text(expected_prefix));
                let ends_correctly = Text.endsWith(script, #text(expected_suffix));

                ignore assertEqual(
                    starts_correctly and ends_correctly,
                    true,
                    "Schnorr script should have correct format",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                );
            };
            case (#err(_)) {
                Debug.print("❌ FAIL: Schnorr script generation failed");
            };
        };

        // Test ECDSA script generation
        let ecdsa_pubkey = Array.tabulate<Nat8>(33, func(i) { if (i == 0) 0x02 else 0xAB });
        switch (Address.generateScriptPublicKey(ecdsa_pubkey, Address.ECDSA)) {
            case (#ok(script)) {
                let expected_prefix = "21"; // OP_DATA_33
                let expected_suffix = "ab"; // OP_CHECKSIG_ECDSA
                let starts_correctly = Text.startsWith(script, #text(expected_prefix));
                let ends_correctly = Text.endsWith(script, #text(expected_suffix));

                ignore assertEqual(
                    starts_correctly and ends_correctly,
                    true,
                    "ECDSA script should have correct format",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                );
            };
            case (#err(_)) {
                Debug.print("❌ FAIL: ECDSA script generation failed");
            };
        };

        // Test invalid script generation
        ignore assertResult(
            Address.generateScriptPublicKey([], 999),
            false,
            "Invalid address type should fail"
        );

        ignore assertResult(
            Address.generateScriptPublicKey(Array.freeze(Array.init<Nat8>(31, 0)), Address.SCHNORR),
            false,
            "Wrong length pubkey should fail"
        );
    };

    private func test_address_operations() {
        Debug.print("\n📍 Testing Address Operations");

        // Test with a valid ECDSA public key
        let valid_ecdsa_pubkey = Array.thaw<Nat8>([
            0x02, 0x79, 0xbe, 0x66, 0x7e, 0xf9, 0xdc, 0xbb, 0xac, 0x55, 0xa0, 0x62, 0x95, 0xce, 0x87, 0x0b,
            0x07, 0x02, 0x9b, 0xfc, 0xdb, 0x2d, 0xce, 0x28, 0xd9, 0x59, 0xf2, 0x81, 0x5b, 0x16, 0xf8, 0x17, 0x98
        ]);
        let pubkey_blob = Blob.fromArray(Array.freeze(valid_ecdsa_pubkey));

        // Test address generation
        switch (Address.generateAddress(pubkey_blob, Address.ECDSA, null)) {
            case (#ok(addr_info)) {
                Debug.print("Generated address: " # addr_info.address);

                // Verify address starts with Hoosat:
                let has_prefix = Text.startsWith(addr_info.address, #text("Hoosat:"));
                ignore assertEqual(
                    has_prefix,
                    true,
                    "Generated address should have Hoosat: prefix",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                );

                // Test address decoding
                switch (Address.decodeAddress(addr_info.address, null)) {
                    case (#ok(decoded_info)) {
                        ignore assertEqual(
                            decoded_info.addr_type,
                            Address.ECDSA,
                            "Decoded address type should match",
                            func(a, b) { a == b },
                            func(n) { debug_show(n) }
                        );

                        let payload_matches = Array.equal(
                            decoded_info.payload,
                            addr_info.payload,
                            func(a, b) { a == b }
                        );
                        ignore assertEqual(
                            payload_matches,
                            true,
                            "Decoded payload should match original",
                            func(a, b) { a == b },
                            func(b) { if (b) "true" else "false" }
                        );
                    };
                    case (#err(_)) {
                        Debug.print("❌ FAIL: Address decoding failed");
                    };
                };
            };
            case (#err(error)) {
                Debug.print("❌ FAIL: Address generation failed: " # Errors.errorToText(error));
            };
        };

        // Test invalid public key
        let invalid_pubkey = Blob.fromArray([0x00]); // Wrong length
        ignore assertResult(
            Address.generateAddress(invalid_pubkey, Address.ECDSA, null),
            false,
            "Invalid public key should fail"
        );
    };

    private func test_custom_prefixes() {
        Debug.print("\n🌐 Testing Custom Prefixes");

        // Test with a valid ECDSA public key
        let valid_ecdsa_pubkey = Array.thaw<Nat8>([
            0x02, 0x79, 0xbe, 0x66, 0x7e, 0xf9, 0xdc, 0xbb, 0xac, 0x55, 0xa0, 0x62, 0x95, 0xce, 0x87, 0x0b,
            0x07, 0x02, 0x9b, 0xfc, 0xdb, 0x2d, 0xce, 0x28, 0xd9, 0x59, 0xf2, 0x81, 0x5b, 0x16, 0xf8, 0x17, 0x98
        ]);
        let pubkey_blob = Blob.fromArray(Array.freeze(valid_ecdsa_pubkey));

        // Test hoosat prefix
        switch (Address.generateAddress(pubkey_blob, Address.ECDSA, ?"hoosat")) {
            case (#ok(addr_info)) {
                Debug.print("Generated hoosat address: " # addr_info.address);

                // Verify address starts with hoosat:
                let has_prefix = Text.startsWith(addr_info.address, #text("hoosat:"));
                ignore assertEqual(
                    has_prefix,
                    true,
                    "Generated address should have hoosat: prefix",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                );

                // Test hoosat address decoding
                switch (Address.decodeAddress(addr_info.address, ?"hoosat")) {
                    case (#ok(decoded_info)) {
                        ignore assertEqual(
                            decoded_info.addr_type,
                            Address.ECDSA,
                            "Decoded hoosat address type should match",
                            func(a, b) { a == b },
                            func(n) { debug_show(n) }
                        );

                        let payload_matches = Array.equal(
                            decoded_info.payload,
                            addr_info.payload,
                            func(a, b) { a == b }
                        );
                        ignore assertEqual(
                            payload_matches,
                            true,
                            "Decoded hoosat payload should match original",
                            func(a, b) { a == b },
                            func(b) { if (b) "true" else "false" }
                        );
                    };
                    case (#err(error)) {
                        Debug.print("❌ FAIL: Hoosat address decoding failed: " # Errors.errorToText(error));
                    };
                };

                // Test that auto-detection works for lowercase hoosat prefix
                ignore assertResult(
                    Address.decodeAddress(addr_info.address, null),
                    true,
                    "Auto-detect should accept lowercase hoosat address"
                );
            };
            case (#err(error)) {
                Debug.print("❌ FAIL: Hoosat address generation failed: " # Errors.errorToText(error));
            };
        };

        // Test short prefix
        switch (Address.generateAddress(pubkey_blob, Address.ECDSA, ?"abc")) {
            case (#ok(addr_info)) {
                Debug.print("Generated abc address: " # addr_info.address);

                let has_prefix = Text.startsWith(addr_info.address, #text("abc:"));
                ignore assertEqual(
                    has_prefix,
                    true,
                    "Generated address should have abc: prefix",
                    func(a, b) { a == b },
                    func(b) { if (b) "true" else "false" }
                );

                // Test abc address decoding
                switch (Address.decodeAddress(addr_info.address, ?"abc")) {
                    case (#ok(_)) {
                        Debug.print("✅ PASS: ABC address decoding succeeded");
                    };
                    case (#err(error)) {
                        Debug.print("❌ FAIL: ABC address decoding failed: " # Errors.errorToText(error));
                    };
                };
            };
            case (#err(error)) {
                Debug.print("❌ FAIL: ABC address generation failed: " # Errors.errorToText(error));
            };
        };
    };

    private func test_backward_compatibility() {
        Debug.print("\n🔄 Testing Backward Compatibility");

        // Test backward compatibility functions exist and work
        let test_bytes : [Nat8] = [0xDE, 0xAD, 0xBE, 0xEF];
        let hex = Address.hex_from_array(test_bytes);
        ignore assertEqual(
            hex,
            "deadbeef",
            "Backward compatible hex_from_array should work",
            textEq,
            textToText
        );

        let decoded = Address.array_from_hex("deadbeef");
        let matches = Array.equal(decoded, test_bytes, func(a, b) { a == b });
        ignore assertEqual(
            matches,
            true,
            "Backward compatible array_from_hex should work",
            func(a, b) { a == b },
            func(b) { if (b) "true" else "false" }
        );

        // Test that backward compatible functions handle errors gracefully
        let empty_result = Address.array_from_hex("invalid");
        ignore assertEqual(
            empty_result.size(),
            0,
            "Invalid hex should return empty array in backward compatible function",
            func(a, b) { a == b },
            func(n) { debug_show(n) }
        );
    };
}