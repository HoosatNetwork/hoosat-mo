/// Configuration for HRC20 Example Canister
/// 
/// IMPORTANT: This file contains private configuration data.
/// Copy this file to config.mo and add your private API endpoint.
/// The config.mo file is in .gitignore and won't be committed.

module {
    /// API endpoint for Hoosat testnet
    /// Default: "https://proxy.hoosat.net/api/v1" (public testnet)
    /// For local testing with your own node, update this to your endpoint
    /// Example: "https://your-ngrok-url.ngrok-free.app"
    public let TESTNET_API_HOST : Text = "https://proxy.hoosat.net/api/v1";
    
    /// Default key name for IC ECDSA
    public let DEFAULT_KEY_NAME : Text = "dfx_test_key";
    
    /// Network prefix for testnet addresses
    public let TESTNET_PREFIX : Text = "hoosattest";
    
    /// Network prefix for mainnet addresses  
    public let MAINNET_PREFIX : Text = "hoosat";
}
