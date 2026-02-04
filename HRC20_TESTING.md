# HRC20 Testing Guide

This guide covers testing the HRC20 example canister deployed on the Internet Computer.

## Prerequisites

- DFX installed and running
- HRC20 example canister deployed (`dfx deploy hrc20_example`)
- HTN tokens to fund operations (testnet or mainnet)

## Quick Start

```bash
# Make the test script executable
chmod +x test_hrc20.sh

# Run basic tests
./test_hrc20.sh test
```

## Test Script Commands

### 1. Check DFX Status
```bash
./test_hrc20.sh check
```

### 2. Get Canister Address
```bash
./test_hrc20.sh address
```
This caches the address to `/tmp/hrc20_canister_address.txt` for subsequent commands.

### 3. Check Balance
```bash
# Uses cached address
./test_hrc20.sh balance

# Or specify address
./test_hrc20.sh balance hoosat:qz...
```

### 4. Consolidate UTXOs
If you have many small UTXOs, consolidate them first:
```bash
./test_hrc20.sh consolidate
```

### 5. Deploy a Token
```bash
./test_hrc20.sh deploy MYTOK 21000000000000000 100000000000 8
```

Parameters:
- `MYTOK` - Token ticker (4-6 characters)
- `21000000000000000` - Max supply (in smallest units)
- `100000000000` - Mint limit per transaction
- `8` - Decimals (optional, default: 8)

**Note:** You need ~2100 HTN for deploy (1000 commit + 1000 reveal fees).

### 6. Mint Tokens
```bash
# Mint to canister's address
./test_hrc20.sh mint MYTOK

# Mint to specific address
./test_hrc20.sh mint MYTOK hoosat:qz...
```

### 7. Reveal Operation
After the commit transaction confirms (~10 seconds):
```bash
./test_hrc20.sh reveal <commit_tx_id>
```

### 8. Check Pending Reveals
```bash
./test_hrc20.sh pending
```

### 9. Get Redeem Script
```bash
./test_hrc20.sh redeem <commit_tx_id>
```

### 10. Estimate Fees
```bash
./test_hrc20.sh estimate '{"p":"hrc-20","op":"mint","tick":"TEST"}'
```

## Manual Testing (Without Script)

### Get Address
```bash
dfx canister call hrc20_example getAddress
```

### Get Balance
```bash
dfx canister call hrc20_example getBalance '("hoosat:qz...")'
```

### Deploy Token
```bash
dfx canister call hrc20_example deployTokenWithBroadcast '("MYTOK", "21000000000000000", "100000000000", opt 8, "hoosat:qz...")'
```

### Mint Token
```bash
dfx canister call hrc20_example mintTokenWithBroadcast '("MYTOK", null)'
```

### Reveal Operation
```bash
dfx canister call hrc20_example revealOperation '("commit_tx_id_here", "hoosat:qz...")'
```

## Testing Workflow

### Complete Deploy Flow

1. **Get the canister address:**
   ```bash
   ./test_hrc20.sh address
   ```

2. **Fund the address** with at least 2100 HTN

3. **Check balance:**
   ```bash
   ./test_hrc20.sh balance
   ```

4. **Deploy the token:**
   ```bash
   ./test_hrc20.sh deploy MYTOK 21000000000000000 100000000000 8
   ```
   
   Save the `commit_tx_id` from the output!

5. **Wait ~10 seconds** for the commit to confirm

6. **Reveal the operation:**
   ```bash
   ./test_hrc20.sh reveal <commit_tx_id>
   ```

### Complete Mint Flow

1. **Ensure you have HTN** for the mint fee (1 HTN)

2. **Mint tokens:**
   ```bash
   ./test_hrc20.sh mint MYTOK
   ```
   
   Save the `commit_tx_id` from the output!

3. **Wait ~10 seconds** for confirmation

4. **Reveal:**
   ```bash
   ./test_hrc20.sh reveal <commit_tx_id>
   ```

## Fee Structure

| Operation | Commit Fee | Reveal Fee | Total |
|-----------|-----------|-----------|-------|
| Deploy | 1000 HTN | 1000 HTN | 2000 HTN |
| Mint | 1 HTN | Network | ~1 HTN |
| Transfer | Network | Network | Minimal |
| Burn | Network | Network | Minimal |

## Troubleshooting

### "Insufficient Funds" Error
- Check balance: `./test_hrc20.sh balance`
- Consolidate UTXOs: `./test_hrc20.sh consolidate`
- Ensure you have enough for fees

### "No pending reveal found" Error
- Check pending reveals: `./test_hrc20.sh pending`
- Ensure you're using the correct commit_tx_id

### Transaction Not Found
- Wait longer for confirmation (can take 10-30 seconds)
- Check the Hoosat explorer for the commit transaction

### DFX Not Running
```bash
dfx start --background
dfx deploy hrc20_example
```

## Running Unit Tests

The project also has Motoko unit tests:

```bash
# Run all HRC20 tests
mops test hrc20_integration.test.mo
mops test hrc20_operations.test.mo
mops test hrc20_mint.test.mo

# Run all tests
mops test
```

## Test Checklist

- [ ] Canister address generated successfully
- [ ] Balance query returns correct amount
- [ ] UTXO consolidation works
- [ ] Token deploy commit succeeds
- [ ] Token deploy reveal succeeds
- [ ] Token mint commit succeeds
- [ ] Token mint reveal succeeds
- [ ] Pending reveals tracked correctly
- [ ] Fee estimates are reasonable
