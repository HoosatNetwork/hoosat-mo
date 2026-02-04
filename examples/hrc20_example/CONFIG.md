# HRC20 Example Configuration

## Setup

1. **Copy the template config file:**
   ```bash
   cd examples/hrc20_example
   cp config.template.mo config.mo
   ```

2. **Edit `config.mo`** to add your private API endpoint:
   ```motoko
   public let TESTNET_API_HOST : Text = "https://your-ngrok-url.ngrok-free.app";
   ```

3. **The `config.mo` file is in `.gitignore`** and won't be committed to git.

## Default Configuration

If you don't create a `config.mo` file, the canister will use:
- **API Endpoint:** `https://proxy.hoosat.net/api/v1` (public Hoosat testnet)
- **Key Name:** `dfx_test_key`
- **Network:** Testnet (`hoosattest` prefix)

## Switching to Mainnet

To use mainnet, update `config.mo`:
```motoko
public let TESTNET_API_HOST : Text = "https://api.hoosat.fi";
public let TESTNET_PREFIX : Text = "Hoosat";
```

And update `main.mo` to use `createMainnetWallet` instead of `createTestnetWallet`.

## Private Data Safety

- ✅ `config.template.mo` - Safe to commit (contains defaults only)
- ✅ `config.mo` - Ignored by git (contains your private URLs)
- ✅ Your private ngrok URLs stay local
