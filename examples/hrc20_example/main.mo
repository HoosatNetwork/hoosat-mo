/// HRC20 Token Example - Deploy HRC20 tokens on Hoosat from ICP
///
/// This canister demonstrates deploying HRC20 tokens using the commit-reveal pattern.
///
/// ## Quick Start
///
/// 1. Start local replica and deploy:
///    ```
///    dfx start --background
///    dfx deploy hrc20_example
///    ```
///
/// 2. Get your canister's Hoosat address:
///    ```
///    dfx canister call hrc20_example getAddress
///    ```
///
/// 3. Fund the address with HTN (need ~2100+ HTN for deploy)
///
/// 4. Deploy a token (commit transaction):
///    ```
///    dfx canister call hrc20_example deployTokenWithBroadcast '("MYTOKEN", "21000000000000000", "100000000000", opt 8, "YOUR_HOOSAT_ADDRESS")'
///    ```
///
/// 5. Wait ~10 seconds for commit to confirm, then reveal:
///    ```
///    dfx canister call hrc20_example revealOperation '("COMMIT_TX_ID", "YOUR_HOOSAT_ADDRESS")'
///    ```
///
/// ## Fee Structure
/// - Deploy: 1000 HTN commit fee + 1000 HTN reveal fee = 2000 HTN total
/// - Mint: 1 HTN fee
/// - Transfer: Network fees only
///
/// ## Key Concepts
/// - Commit-Reveal: Each HRC20 operation requires 2 transactions
/// - P2SH Scripts: Data is embedded using OP_FALSE OP_IF...OP_ENDIF envelope
/// - Threshold ECDSA: Uses IC's threshold ECDSA for signing (no private keys stored)

import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Array "mo:base/Array";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";

import Wallet "../../src/wallet";
import Errors "../../src/errors";
import Types "../../src/types";
import Address "../../src/address";
import ScriptBuilder "../../src/script_builder";
import Sighash "../../src/sighash";
import Transaction "../../src/transaction";
import IC "mo:ic";

import HRC20Types "../../src/hrc20/types";
import HRC20Operations "../../src/hrc20/operations";
import HRC20Builder "../../src/hrc20/builder";

import Config "./config";

persistent actor HRC20Example {

    // Initialize a testnet wallet with configuration from config.mo
    // To use a custom API endpoint, update TESTNET_API_HOST in config.mo
    transient let wallet = Wallet.createTestnetWallet(
        Config.DEFAULT_KEY_NAME,  // key_name
        ?Config.TESTNET_PREFIX,   // prefix
        ?Config.TESTNET_API_HOST  // api_host
    );

    // Store pending reveals (survives upgrades)
    private stable var pendingReveals : [(Text, [Nat8])] = [];  // (commit_tx_id, redeem_script)

    /// Get the canister's Hoosat address
    public func getAddress() : async Result.Result<Wallet.AddressInfo, Errors.HoosatError> {
        await wallet.generateAddress(null, null)
    };

    /// Consolidate UTXOs by sending all funds to self
    /// This is necessary when you have multiple small UTXOs and need one large one
    public func consolidateUTXOs(from_address: Text) : async Result.Result<Text, Errors.HoosatError> {
        // Get UTXOs to count inputs and calculate proper fee
        let utxos = switch (await wallet.getUTXOs(from_address)) {
            case (#ok(u)) { u };
            case (#err(e)) { return #err(e) };
        };

        if (utxos.size() == 0) {
            return #err(#InsufficientFunds({ required = 1000; available = 0 }));
        };

        // Sort UTXOs by amount (largest first) to match selectCoinsForTransaction logic
        // This ensures we calculate fees and amounts from the same UTXOs that will be spent
        let sorted_utxos = Array.sort<Types.UTXO>(
            utxos,
            func(a, b) { Nat64.compare(b.amount, a.amount) }
        );

        // Cap at max_utxos (10) to match selectCoinsForTransaction limit
        let max_utxos = 10;
        let input_count = Nat.min(sorted_utxos.size(), max_utxos);

        // Calculate fee based on transaction size: inputs * 150 + outputs * 35 + 10 bytes
        // With 10 input limit, max fee = (10 * 150 + 2 * 35 + 10) * 1000 = 1,570,000 sompi
        // Add 20% margin for safety
        let estimated_size = input_count * 150 + 2 * 35 + 10;
        let fee_rate: Nat64 = 1000; // sompi per byte
        let calculated_fee = Nat64.fromNat(estimated_size) * fee_rate;
        let fee_buffer = calculated_fee + (calculated_fee / 5); // Add 20% margin

        // Calculate total from LARGEST UTXOs (matching selectCoinsForTransaction)
        var selected_total: Nat64 = 0;
        for (i in Iter.range(0, input_count - 1)) {
            selected_total += sorted_utxos[i].amount;
        };

        if (selected_total == 0) {
            return #err(#InsufficientFunds({ required = fee_buffer; available = 0 }));
        };

        let amount_to_send = if (selected_total > fee_buffer) { 
            selected_total - fee_buffer 
        } else { 
            return #err(#InsufficientFunds({ required = fee_buffer; available = selected_total })) 
        };

        // Use explicit fee to ensure it doesn't exceed max_fee
        let explicit_fee = calculated_fee;

        Debug.print("🔄 Consolidating " # debug_show(input_count) # " UTXOs with total: " # debug_show(selected_total));

        switch (await wallet.sendTransaction(
            from_address,
            from_address,  // Send to self
            amount_to_send,
            ?explicit_fee,  // Use calculated fee
            null   // Use default derivation path
        )) {
            case (#ok(result)) { 
                Debug.print("✅ Consolidation complete. New UTXO amount: " # debug_show(amount_to_send));
                #ok(result.transaction_id) 
            };
            case (#err(e)) { 
                Debug.print("❌ Consolidation failed: " # debug_show(e));
                #err(e) 
            };
        }
    };

    /// Get balance of an address (HTN balance in sompi)
    public func getBalance(address: Text) : async Result.Result<Wallet.Balance, Errors.HoosatError> {
        await wallet.getBalance(address)
    };

    /// Example 1: Build a HRC20 deploy operation
    ///
    /// This creates the commit transaction for deploying a token.
    /// After broadcasting, you must call revealOperation() to complete it.
    ///
    /// @param tick - Token ticker (4-6 letters)
    /// @param max_supply - Maximum supply as string
    /// @param mint_limit - Amount per mint as string
    /// @param decimals - Number of decimals (default: 8)
    /// @param from_address - Address to use for funding
    /// @return Commit transaction details and instructions
    public func buildDeployCommit(
        tick: Text,
        max_supply: Text,
        mint_limit: Text,
        decimals: ?Nat8,
        from_address: Text
    ) : async Result.Result<{
        operation_json: Text;
        commit_tx: Types.HoosatTransaction;
        redeem_script_hex: Text;
        instructions: Text;
    }, Errors.HoosatError> {

        Debug.print("🚀 Building deploy commit for: " # tick);

        // 1. Create deployment parameters
        let deploy_params : HRC20Types.DeployMintParams = {
            tick = tick;
            max = max_supply;
            lim = mint_limit;
            to = ?from_address;
            dec = decimals;
            pre = null;
        };

        // 2. Format the HRC20 operation JSON
        let operation_json = HRC20Operations.formatDeployMint(deploy_params);

        // 3. Get address info for public key
        let addressInfo = switch (await wallet.generateAddress(null, null)) {
            case (#ok(info)) { info };
            case (#err(e)) { return #err(e) };
        };

        // 4. Get UTXO to fund the transaction
        let utxos = switch (await wallet.getUTXOs(from_address)) {
            case (#ok(utxos)) {
                if (utxos.size() == 0) {
                    return #err(#InsufficientFunds({
                        required = 100000000000;  // 1000 HTN
                        available = 0;
                    }));
                };
                utxos
            };
            case (#err(e)) { return #err(e) };
        };

        let utxo = utxos[0];

        // 5. Build commit transaction
        let commit_result = HRC20Builder.buildCommit(
            addressInfo.public_key,
            operation_json,
            utxo,
            HRC20Builder.RECOMMENDED_COMMIT_AMOUNT,
            100000000000,  // 1000 HTN deploy fee
            from_address,
            true  // Use ECDSA
        );

        let commit_pair = switch (commit_result) {
            case (#ok(pair)) { pair };
            case (#err(e)) { return #err(e) };
        };

        Debug.print("✅ Commit transaction built");
        Debug.print("📝 Operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            commit_tx = commit_pair.commitTx;
            redeem_script_hex = Address.hexFromArray(commit_pair.redeemScript);
            instructions = "1. Sign and broadcast the commit_tx\n2. Wait for confirmation\n3. Call revealOperation() with the commit TX ID";
        })
    };

    /// Example 2: Build a mint operation
    ///
    /// @param tick - Token ticker
    /// @param recipient - Optional recipient address
    /// @param from_address - Address to fund the mint
    public func buildMintCommit(
        tick: Text,
        recipient: ?Text,
        from_address: Text
    ) : async Result.Result<{
        operation_json: Text;
        instructions: Text;
    }, Errors.HoosatError> {

        let mint_params : HRC20Types.MintParams = {
            tick = tick;
            to = recipient;
        };

        let operation_json = HRC20Operations.formatMint(mint_params);

        Debug.print("💰 Mint operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            instructions = "Follow same commit-reveal pattern as deploy. Fee: 1 HTN";
        })
    };

    /// Example 3: Build a transfer operation
    ///
    /// @param tick - Token ticker
    /// @param amount - Amount to transfer (with decimals)
    /// @param to_address - Recipient address
    public func buildTransferCommit(
        tick: Text,
        amount: Text,
        to_address: Text
    ) : async Result.Result<{
        operation_json: Text;
        instructions: Text;
    }, Errors.HoosatError> {

        let transfer_params : HRC20Types.TransferMintParams = {
            tick = tick;
            amt = amount;
            to = to_address;
        };

        let operation_json = HRC20Operations.formatTransferMint(transfer_params);

        Debug.print("📤 Transfer operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            instructions = "Follow commit-reveal pattern. Fee: Network fees only";
        })
    };

    /// Example 4: Build a burn operation
    ///
    /// @param tick - Token ticker
    /// @param amount - Amount to burn (with decimals)
    public func buildBurnCommit(
        tick: Text,
        amount: Text
    ) : async Result.Result<{
        operation_json: Text;
        instructions: Text;
    }, Errors.HoosatError> {

        let burn_params : HRC20Types.BurnMintParams = {
            tick = tick;
            amt = amount;
        };

        let operation_json = HRC20Operations.formatBurnMint(burn_params);

        Debug.print("🔥 Burn operation: " # operation_json);

        #ok({
            operation_json = operation_json;
            instructions = "Follow commit-reveal pattern. Fee: Network fees only";
        })
    };

    /// Example 5: Format a list (sell) operation
    ///
    /// @param tick - Token ticker (will be converted to lowercase)
    /// @param amount - Amount to list
    public func formatListOperation(
        tick: Text,
        amount: Text
    ) : async Text {
        let list_params : HRC20Types.ListParams = {
            tick = tick;
            amt = amount;
        };

        HRC20Operations.formatList(list_params)
    };

    /// Example 6: Format a send (buy) operation
    ///
    /// @param tick - Token ticker (will be converted to lowercase)
    public func formatSendOperation(tick: Text) : async Text {
        let send_params : HRC20Types.SendParams = {
            tick = tick;
        };

        HRC20Operations.formatSend(send_params)
    };

    /// Get P2SH address from script hash
    ///
    /// Useful for constructing reveal transactions
    /// @param scriptHash - The redeem script hash
    /// @param prefix - Optional network prefix (defaults to "hoosat" for mainnet, use "hoosattest" for testnet)
    public func getP2SHAddress(scriptHash: [Nat8], prefix: ?Text) : async Result.Result<Text, Errors.HoosatError> {
        let network_prefix = switch (prefix) {
            case (?p) { p };
            case (null) { "hoosat" };
        };
        HRC20Builder.getP2SHAddress(2, scriptHash, network_prefix)
    };

    /// Estimate fees for a HRC20 operation
    ///
    /// @param operation_json - The HRC20 operation JSON
    /// @return (commit_fee, reveal_fee) in sompi
    public func estimateFees(operation_json: Text) : async (Nat64, Nat64) {
        HRC20Builder.estimateFees(operation_json)
    };

    /// Store a pending reveal for later
    ///
    /// Call this after successfully broadcasting a commit transaction
    public func storePendingReveal(commit_tx_id: Text, redeem_script_hex: Text) : async () {
        let redeem_script = switch (Address.arrayFromHex(redeem_script_hex)) {
            case (#ok(bytes)) { bytes };
            case (#err(_)) { return };
        };

        pendingReveals := Array.append(
            pendingReveals,
            [(commit_tx_id, redeem_script)]
        );

        Debug.print("💾 Stored pending reveal for: " # commit_tx_id);
    };

    /// Get list of pending reveals
    public query func getPendingReveals() : async [(Text, Nat)] {
        Array.map<(Text, [Nat8]), (Text, Nat)>(
            pendingReveals,
            func(pair) { (pair.0, pair.1.size()) }
        )
    };

    /// Get a specific redeem script by commit TX ID
    public query func getRedeemScript(commit_tx_id: Text) : async ?Text {
        switch (Array.find<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 == commit_tx_id }
        )) {
            case (?pair) { ?Address.hexFromArray(pair.1) };
            case null { null };
        }
    };

    /// Clear a pending reveal after it's been broadcast
    public func clearPendingReveal(commit_tx_id: Text) : async () {
        pendingReveals := Array.filter<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 != commit_tx_id }
        );

        Debug.print("🗑️  Cleared pending reveal: " # commit_tx_id);
    };

    /// Build reveal transaction outputs
    ///
    /// Helper for constructing the reveal transaction
    public func buildRevealOutputs(
        recipient_address: Text,
        amount: Nat64
    ) : async Result.Result<[Types.TransactionOutput], Errors.HoosatError> {
        HRC20Builder.buildRevealOutputs(recipient_address, amount)
    };

    /// FULL BROADCAST: Deploy token with automatic commit transaction broadcast
    ///
    /// This builds the commit transaction, signs it, and broadcasts it to the network.
    /// You must manually call revealOperation() after the commit confirms.
    ///
    /// @param tick - Token ticker (4-6 letters)
    /// @param max_supply - Maximum supply as string
    /// @param mint_limit - Amount per mint as string
    /// @param decimals - Number of decimals (default: 8)
    /// @param from_address - Address to use for funding
    /// @return Commit transaction ID and redeem script
    public func deployTokenWithBroadcast(
        tick: Text,
        max_supply: Text,
        mint_limit: Text,
        decimals: ?Nat8,
        from_address: Text
    ) : async Result.Result<{
        commit_tx_id: Text;
        redeem_script_hex: Text;
        p2sh_address: Text;
        instructions: Text;
    }, Errors.HoosatError> {

        Debug.print("🚀 Deploying token with broadcast: " # tick);

        // 1. Create deployment parameters
        let deploy_params : HRC20Types.DeployMintParams = {
            tick = tick;
            max = max_supply;
            lim = mint_limit;
            to = ?from_address;
            dec = decimals;
            pre = null;
        };

        // 2. Format the HRC20 operation JSON
        let operation_json = HRC20Operations.formatDeployMint(deploy_params);
        Debug.print("📝 Operation: " # operation_json);

        // 3. Get address info for public key (use canister's address, not user's)
        let addressInfo = switch (await wallet.generateAddress(null, null)) {
            case (#ok(info)) { info };
            case (#err(e)) { return #err(e) };
        };

        // 4. Get UTXOs to fund the transaction (fetch from canister's address)
        let utxos = switch (await wallet.getUTXOs(addressInfo.address)) {
            case (#ok(utxos)) {
                if (utxos.size() == 0) {
                    return #err(#InsufficientFunds({
                        required = 100000000000;  // 1000 HTN
                        available = 0;
                    }));
                };
                utxos
            };
            case (#err(e)) { return #err(e) };
        };

        // 5. Calculate total available
        let total_available = Array.foldLeft<Types.UTXO, Nat64>(
            utxos, 0, func(acc, utxo) { acc + utxo.amount }
        );

        let deploy_fee: Nat64 = 100000000000;  // 1000 HTN
        let commit_amount = HRC20Builder.MIN_COMMIT_AMOUNT;
        let required = deploy_fee + commit_amount;

        if (total_available < required) {
            return #err(#InsufficientFunds({
                required = required;
                available = total_available;
            }));
        };

        // 6. Check if we have a large enough UTXO for deploy (need 2,100 HTN minimum)
        let min_deploy_amount: Nat64 = 210_000_000_000; // 2,100 HTN
        var largest_utxo = utxos[0];
        
        // Find the largest UTXO
        for (utxo in utxos.vals()) {
            if (utxo.amount > largest_utxo.amount) {
                largest_utxo := utxo;
            };
        };

        Debug.print("📊 Largest UTXO amount: " # debug_show(largest_utxo.amount));
        Debug.print("💰 Minimum required: " # debug_show(min_deploy_amount));
        Debug.print("📦 Total UTXOs available: " # debug_show(utxos.size()));

        // If largest UTXO is insufficient, consolidate first
        if (largest_utxo.amount < min_deploy_amount) {
            Debug.print("⚠️  Largest UTXO insufficient. Auto-consolidating UTXOs first...");
            
            // Attempt to consolidate UTXOs
            switch (await consolidateUTXOs(addressInfo.address)) {
                case (#ok(consolidation_tx_id)) {
                    Debug.print("✅ Consolidation broadcast! TX ID: " # consolidation_tx_id);
                    // Return a special result indicating consolidation happened
                    return #ok({
                        commit_tx_id = "PENDING_CONSOLIDATION:" # consolidation_tx_id;
                        redeem_script_hex = "";
                        p2sh_address = "";
                        instructions = "⏳ Consolidation transaction broadcast: " # consolidation_tx_id # ".\n\nPlease wait ~10 seconds for confirmation, then run deploy again.";
                    });
                };
                case (#err(e)) {
                    Debug.print("❌ Consolidation failed: " # debug_show(e));
                    return #err(e);
                };
            };
        };

        // Use the largest UTXO for deploy
        let selected_utxo = largest_utxo;
        let total_needed = deploy_fee + commit_amount;

        Debug.print("✅ Using UTXO with amount: " # debug_show(selected_utxo.amount));

        let commit_result = HRC20Builder.buildCommit(
            addressInfo.public_key,
            operation_json,
            selected_utxo,
            commit_amount,
            deploy_fee,
            addressInfo.address,
            true  // Use ECDSA
        );

        let commit_pair = switch (commit_result) {
            case (#ok(pair)) {
                Debug.print("🔧 Commit TX inputs: " # debug_show(pair.commitTx.inputs.size()));
                Debug.print("🔧 Commit TX outputs: " # debug_show(pair.commitTx.outputs.size()));
                pair
            };
            case (#err(e)) { return #err(e) };
        };

        // 7. Get P2SH address from script hash
        let prefix = if (Text.startsWith(addressInfo.address, #text("hoosattest:"))) {
            "hoosattest"
        } else {
            "hoosat"
        };

        let p2sh_address = switch (HRC20Builder.getP2SHAddress(2, commit_pair.p2shScriptHash, prefix)) {
            case (#ok(addr)) { addr };
            case (#err(e)) { return #err(e) };
        };

        Debug.print("🔐 P2SH Address: " # p2sh_address);

        // 8. Sign and broadcast the commit transaction
        let commit_tx_id = switch (await wallet.signAndBroadcastTransaction(
            commit_pair.commitTx,
            [selected_utxo],
            null
        )) {
            case (#ok(tx_id)) { tx_id };
            case (#err(e)) { return #err(e) };
        };

        let redeem_script_hex = Address.hexFromArray(commit_pair.redeemScript);

        // 9. Store pending reveal
        pendingReveals := Array.append(
            pendingReveals,
            [(commit_tx_id, commit_pair.redeemScript)]
        );

        Debug.print("✅ Commit broadcast! TX ID: " # commit_tx_id);
        Debug.print("💾 Stored redeem script for reveal");

        #ok({
            commit_tx_id = commit_tx_id;
            redeem_script_hex = redeem_script_hex;
            p2sh_address = p2sh_address;
            instructions = "Commit TX broadcast! Wait for confirmation, then call revealOperation(\"" # commit_tx_id # "\")";
        })
    };

    /// FULL BROADCAST: Mint tokens with automatic commit transaction broadcast
    ///
    /// This builds the commit transaction for minting, signs it, and broadcasts it.
    /// You must call revealOperation() after the commit confirms to complete the mint.
    ///
    /// @param tick - Token ticker to mint
    /// @param recipient - Optional recipient address (defaults to canister's address)
    /// @return Commit transaction ID and redeem script
    public func mintTokenWithBroadcast(
        tick: Text,
        recipient: ?Text
    ) : async Result.Result<{
        commit_tx_id: Text;
        redeem_script_hex: Text;
        p2sh_address: Text;
        instructions: Text;
    }, Errors.HoosatError> {

        Debug.print("💰 Minting token: " # tick);

        // 1. Get address info for public key
        let addressInfo = switch (await wallet.generateAddress(null, null)) {
            case (#ok(info)) { info };
            case (#err(e)) { return #err(e) };
        };

        // 2. Determine recipient (use canister's address if not specified)
        let mint_recipient = switch (recipient) {
            case (?addr) { addr };
            case null { addressInfo.address };
        };

        // 3. Create mint parameters
        let mint_params : HRC20Types.MintParams = {
            tick = tick;
            to = ?mint_recipient;
        };

        // 4. Format the HRC20 operation JSON
        let operation_json = HRC20Operations.formatMint(mint_params);
        Debug.print("📝 Operation: " # operation_json);

        // 5. Get UTXOs to fund the transaction
        let utxos = switch (await wallet.getUTXOs(addressInfo.address)) {
            case (#ok(utxos)) {
                if (utxos.size() == 0) {
                    return #err(#InsufficientFunds({
                        required = 100_000_000;  // 1 HTN
                        available = 0;
                    }));
                };
                utxos
            };
            case (#err(e)) { return #err(e) };
        };

        // 6. Calculate total available
        let total_available = Array.foldLeft<Types.UTXO, Nat64>(
            utxos, 0, func(acc, utxo) { acc + utxo.amount }
        );

        let mint_fee: Nat64 = 100_000_000;  // 1 HTN
        let commit_amount = HRC20Builder.MIN_COMMIT_AMOUNT;
        let required = mint_fee + commit_amount;

        if (total_available < required) {
            return #err(#InsufficientFunds({
                required = required;
                available = total_available;
            }));
        };

        // 7. Select UTXO with enough funds
        var selected_utxo = utxos[0];
        let total_needed = mint_fee + commit_amount;

        label utxo_loop for (utxo in utxos.vals()) {
            if (utxo.amount >= total_needed) {
                selected_utxo := utxo;
                break utxo_loop;
            };
            if (utxo.amount > selected_utxo.amount) {
                selected_utxo := utxo;
            };
        };

        Debug.print("📊 Selected UTXO amount: " # debug_show(selected_utxo.amount));
        Debug.print("💰 Commit amount: " # debug_show(commit_amount));
        Debug.print("💸 Mint fee: " # debug_show(mint_fee));

        // Check if we need to consolidate UTXOs first
        if (selected_utxo.amount < total_needed) {
            Debug.print("⚠️  Single UTXO insufficient. Please consolidate UTXOs first.");
            return #err(#InsufficientFunds({
                required = total_needed;
                available = selected_utxo.amount;
            }));
        };

        // 8. Build commit transaction
        let commit_result = HRC20Builder.buildCommit(
            addressInfo.public_key,
            operation_json,
            selected_utxo,
            commit_amount,
            mint_fee,
            addressInfo.address,
            true  // Use ECDSA
        );

        let commit_pair = switch (commit_result) {
            case (#ok(pair)) {
                Debug.print("🔧 Commit TX inputs: " # debug_show(pair.commitTx.inputs.size()));
                Debug.print("🔧 Commit TX outputs: " # debug_show(pair.commitTx.outputs.size()));
                pair
            };
            case (#err(e)) { return #err(e) };
        };

        // 9. Get P2SH address
        let prefix = if (Text.startsWith(addressInfo.address, #text("hoosattest:"))) {
            "hoosattest"
        } else {
            "hoosat"
        };

        let p2sh_address = switch (HRC20Builder.getP2SHAddress(2, commit_pair.p2shScriptHash, prefix)) {
            case (#ok(addr)) { addr };
            case (#err(e)) { return #err(e) };
        };

        Debug.print("🔐 P2SH Address: " # p2sh_address);

        // 10. Sign and broadcast the commit transaction
        let commit_tx_id = switch (await wallet.signAndBroadcastTransaction(
            commit_pair.commitTx,
            [selected_utxo],
            null
        )) {
            case (#ok(tx_id)) { tx_id };
            case (#err(e)) { return #err(e) };
        };

        let redeem_script_hex = Address.hexFromArray(commit_pair.redeemScript);

        // 11. Store pending reveal
        pendingReveals := Array.append(
            pendingReveals,
            [(commit_tx_id, commit_pair.redeemScript)]
        );

        Debug.print("✅ Commit broadcast! TX ID: " # commit_tx_id);
        Debug.print("💾 Stored redeem script for reveal");

        #ok({
            commit_tx_id = commit_tx_id;
            redeem_script_hex = redeem_script_hex;
            p2sh_address = p2sh_address;
            instructions = "Commit TX broadcast! Wait ~10 seconds for confirmation, then call revealOperation(\"" # commit_tx_id # "\", \"" # mint_recipient # "\")";
        })
    };

    /// FULL BROADCAST: Reveal operation after commit confirms
    ///
    /// This builds the reveal transaction, signs it, and broadcasts it.
    /// Call this after the commit transaction has confirmed.
    /// Works for ALL HRC20 operations (deploy, mint, transfer, burn).
    ///
    /// @param commit_tx_id - Transaction ID of the commit
    /// @param recipient_address - Where to send the remaining funds
    /// @return Reveal transaction ID
    public func revealOperation(
        commit_tx_id: Text,
        recipient_address: Text
    ) : async Result.Result<{
        reveal_tx_id: Text;
        message: Text;
    }, Errors.HoosatError> {

        Debug.print("🔓 Revealing operation for commit: " # commit_tx_id);

        // 1. Get stored redeem script
        let redeem_script = switch (Array.find<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 == commit_tx_id }
        )) {
            case (?pair) { pair.1 };
            case null {
                return #err(#InvalidTransaction({
                    message = "No pending reveal found for commit TX: " # commit_tx_id;
                }));
            };
        };

        Debug.print("📜 Found redeem script, length: " # debug_show(redeem_script.size()));
        Debug.print("📜 Redeem script (hex): " # Address.hexFromArray(redeem_script));

        // 2. Get P2SH address from the redeem script hash
        // Detect network prefix from recipient address
        let prefix = if (Text.startsWith(recipient_address, #text("hoosattest:"))) {
            "hoosattest"
        } else {
            "hoosat"
        };
        Debug.print("🌐 Using network prefix: " # prefix);

        let scriptHash = ScriptBuilder.hashRedeemScript(redeem_script);
        let p2sh_address = switch (HRC20Builder.getP2SHAddress(2, scriptHash, prefix)) {
            case (#ok(addr)) { addr };
            case (#err(e)) { return #err(e) };
        };

        Debug.print("🏠 P2SH Address: " # p2sh_address);

        // 3. Get UTXO from P2SH address
        let p2sh_utxos = switch (await wallet.getUTXOs(p2sh_address)) {
            case (#ok(utxos)) {
                if (utxos.size() == 0) {
                    return #err(#InsufficientFunds({
                        required = 1;
                        available = 0;
                    }));
                };
                utxos
            };
            case (#err(e)) { return #err(e) };
        };

        let p2sh_utxo = p2sh_utxos[0];
        Debug.print("💰 P2SH UTXO amount: " # debug_show(p2sh_utxo.amount));
        Debug.print("📍 P2SH UTXO txid: " # p2sh_utxo.transactionId);
        Debug.print("📍 P2SH UTXO index: " # debug_show(p2sh_utxo.index));

        // 4. Calculate reveal amount (P2SH amount minus fee)
        let reveal_fee: Nat64 = 100_000_000_000;  // 1000 HTN deploy fee
        if (p2sh_utxo.amount <= reveal_fee) {
            return #err(#InsufficientFunds({
                required = reveal_fee + 1;
                available = p2sh_utxo.amount;
            }));
        };
        let reveal_amount = p2sh_utxo.amount - reveal_fee;

        // 5. Build reveal outputs
        let recipient_info = switch (Address.decodeAddress(recipient_address, null)) {
            case (#ok(info)) { info };
            case (#err(e)) { return #err(e) };
        };

        let outputs: [Types.TransactionOutput] = [{
            amount = reveal_amount;
            scriptPublicKey = {
                version = 0 : Nat16;
                scriptPublicKey = recipient_info.script_public_key;
            };
        }];

        // 6. Build the reveal transaction
        let reveal_tx: Types.HoosatTransaction = {
            version = 0;
            inputs = [{
                previousOutpoint = {
                    transactionId = p2sh_utxo.transactionId;
                    index = p2sh_utxo.index;
                };
                signatureScript = "";
                sequence = 0;
                sigOpCount = 1;
            }];
            outputs = outputs;
            lockTime = 0;
            subnetworkId = "0000000000000000000000000000000000000000";
            gas = 0;
            payload = "";
        };

        // 7. Sign the reveal transaction (P2SH spending)
        let signed_reveal = switch (await signP2SHReveal(reveal_tx, p2sh_utxo, redeem_script)) {
            case (#ok(signed)) { signed };
            case (#err(e)) { return #err(e) };
        };

        // 8. Broadcast the reveal transaction
        let serialized = Transaction.serialize_transaction(signed_reveal);
        Debug.print("📡 Broadcasting reveal: " # serialized);

        let reveal_tx_id = switch (await wallet.broadcastSerializedTransaction(serialized)) {
            case (#ok(tx_id)) { tx_id };
            case (#err(e)) { return #err(e) };
        };

        // 9. Clear the pending reveal
        pendingReveals := Array.filter<(Text, [Nat8])>(
            pendingReveals,
            func(pair) { pair.0 != commit_tx_id }
        );

        Debug.print("✅ Reveal broadcast! TX ID: " # reveal_tx_id);

        #ok({
            reveal_tx_id = reveal_tx_id;
            message = "Token operation revealed! Check HRC20 explorer.";
        })
    };

    // Helper function to sign P2SH reveal transaction
    private func signP2SHReveal(
        tx: Types.HoosatTransaction,
        utxo: Types.UTXO,
        redeem_script: [Nat8]
    ) : async Result.Result<Types.HoosatTransaction, Errors.HoosatError> {

        // Calculate sighash for the P2SH input
        let reused_values: Sighash.SighashReusedValues = {
            var previousOutputsHash = null;
            var sequencesHash = null;
            var sigOpCountsHash = null;
            var outputsHash = null;
            var payloadHash = null;
        };

        Debug.print("🔧 Using P2SH scriptPubKey for sighash: " # utxo.scriptPublicKey);

        let p2sh_utxo_for_sighash: Types.UTXO = {
            transactionId = utxo.transactionId;
            index = utxo.index;
            amount = utxo.amount;
            scriptPublicKey = utxo.scriptPublicKey;
            scriptVersion = utxo.scriptVersion;
            address = utxo.address;
        };

        let sighash = switch (Sighash.calculate_sighash_ecdsa(tx, 0, p2sh_utxo_for_sighash, Sighash.SigHashAll, reused_values)) {
            case (null) {
                return #err(#CryptographicError({ message = "Failed to calculate P2SH sighash" }));
            };
            case (?hash) {
                Debug.print("🔏 Sighash (hex): " # Address.hexFromArray(hash));
                hash
            };
        };

        // Sign with IC ECDSA
        try {
            let signature_result = await (with cycles = 30_000_000_000) IC.ic.sign_with_ecdsa({
                message_hash = Blob.fromArray(sighash);
                derivation_path = [];
                key_id = { name = "dfx_test_key"; curve = #secp256k1 };
            });

            let signature_bytes = Blob.toArray(signature_result.signature);
            Debug.print("✍️ Raw signature length: " # debug_show(signature_bytes.size()));

            let sighash_type: Nat8 = 0x01;  // SigHashAll

            // Signature with hashtype appended
            let sig_with_hashtype = Array.append(signature_bytes, [sighash_type]);

            // Build P2SH signature script
            let script_bytes = ScriptBuilder.buildP2SHSignatureScript(
                sig_with_hashtype,
                redeem_script
            );

            Debug.print("🔏 Signature script length: " # debug_show(script_bytes.size()));

            let signature_script = Address.hexFromArray(script_bytes);

            // Update transaction with signature script
            let signed_input: Types.TransactionInput = {
                previousOutpoint = tx.inputs[0].previousOutpoint;
                signatureScript = signature_script;
                sequence = tx.inputs[0].sequence;
                sigOpCount = tx.inputs[0].sigOpCount;
            };

            #ok({
                version = tx.version;
                inputs = [signed_input];
                outputs = tx.outputs;
                lockTime = tx.lockTime;
                subnetworkId = tx.subnetworkId;
                gas = tx.gas;
                payload = tx.payload;
            })
        } catch (e) {
            #err(#CryptographicError({ message = "Failed to sign P2SH reveal: " # Error.message(e) }))
        }
    };

    // System functions
    system func preupgrade() {
        Debug.print("💾 Saving " # debug_show(pendingReveals.size()) # " pending reveals");
    };

    system func postupgrade() {
        Debug.print("♻️ Restored " # debug_show(pendingReveals.size()) # " pending reveals");
    };
};
