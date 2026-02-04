#!/bin/bash

# HRC20 Example Canister Test Script
# Usage: ./test_hrc20.sh [command]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Canister name
CANISTER="hrc20_example"

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check if dfx is running
check_dfx() {
    if ! dfx ping 2>/dev/null; then
        print_error "DFX is not running. Please start it with: dfx start --background"
        exit 1
    fi
    print_success "DFX is running"
}

# Get canister address
get_address() {
    print_header "Getting Canister Address"
    local result=$(dfx canister call $CANISTER getAddress 2>&1)
    echo "$result"
    
    # Extract address from result
    local address=$(echo "$result" | grep -o 'hoosat[^"]*' | head -1)
    if [ -n "$address" ]; then
        print_success "Canister address: $address"
        echo "$address" > /tmp/hrc20_canister_address.txt
    else
        print_error "Failed to get address"
    fi
}

# Get balance
get_balance() {
    local address=$1
    if [ -z "$address" ]; then
        if [ -f /tmp/hrc20_canister_address.txt ]; then
            address=$(cat /tmp/hrc20_canister_address.txt)
        else
            print_error "No address provided and no cached address found"
            return 1
        fi
    fi
    
    print_header "Getting Balance for $address"
    dfx canister call $CANISTER getBalance "(\"$address\")"
}

# Consolidate UTXOs - can run multiple times
consolidate_utxos() {
    local address=$1
    local count=$2
    
    if [ -z "$address" ]; then
        if [ -f /tmp/hrc20_canister_address.txt ]; then
            address=$(cat /tmp/hrc20_canister_address.txt)
        else
            print_error "No address provided and no cached address found"
            return 1
        fi
    fi
    
    # Default to 1 if no count provided
    count=${count:-1}
    
    print_header "Consolidating UTXOs for $address"
    print_info "Running $count consolidation(s)..."
    
    local success_count=0
    local fail_count=0
    
    for i in $(seq 1 $count); do
        print_info "Consolidation $i of $count..."
        
        if dfx canister call $CANISTER consolidateUTXOs "(\"$address\")" 2>&1 | grep -q "ok"; then
            print_success "Consolidation $i successful"
            success_count=$((success_count + 1))
            
            # Wait between consolidations (except for the last one)
            if [ $i -lt $count ]; then
                print_info "Waiting 5 seconds before next consolidation..."
                sleep 5
            fi
        else
            print_error "Consolidation $i failed"
            fail_count=$((fail_count + 1))
        fi
    done
    
    print_header "Consolidation Summary"
    print_success "Successful: $success_count"
    if [ $fail_count -gt 0 ]; then
        print_error "Failed: $fail_count"
    fi
}

# Deploy token
deploy_token() {
    local tick=$1
    local max_supply=$2
    local mint_limit=$3
    local decimals=$4
    local from_address=$5
    
    if [ -z "$tick" ] || [ -z "$max_supply" ] || [ -z "$mint_limit" ]; then
        print_error "Usage: deploy_token <tick> <max_supply> <mint_limit> [decimals] [from_address]"
        print_info "Example: ./test_hrc20.sh deploy_token MYTOK 21000000000000000 100000000000 8"
        return 1
    fi
    
    # Set defaults
    decimals=${decimals:-8}
    if [ -z "$from_address" ] && [ -f /tmp/hrc20_canister_address.txt ]; then
        from_address=$(cat /tmp/hrc20_canister_address.txt)
    fi
    
    if [ -z "$from_address" ]; then
        print_error "No from_address provided and no cached address found"
        return 1
    fi
    
    print_header "Deploying HRC20 Token"
    print_info "Ticker: $tick"
    print_info "Max Supply: $max_supply"
    print_info "Mint Limit: $mint_limit"
    print_info "Decimals: $decimals"
    print_info "From Address: $from_address"
    
    dfx canister call $CANISTER deployTokenWithBroadcast "(\"$tick\", \"$max_supply\", \"$mint_limit\", opt $decimals, \"$from_address\")"
}

# Mint tokens
mint_token() {
    local tick=$1
    local recipient=$2
    
    if [ -z "$tick" ]; then
        print_error "Usage: mint_token <tick> [recipient]"
        print_info "Example: ./test_hrc20.sh mint_token MYTOK"
        return 1
    fi
    
    print_header "Minting HRC20 Token"
    print_info "Ticker: $tick"
    
    if [ -n "$recipient" ]; then
        print_info "Recipient: $recipient"
        dfx canister call $CANISTER mintTokenWithBroadcast "(\"$tick\", opt \"$recipient\")"
    else
        print_info "Recipient: canister's address (null)"
        dfx canister call $CANISTER mintTokenWithBroadcast "(\"$tick\", null)"
    fi
}

# Reveal operation
reveal() {
    local commit_tx_id=$1
    local recipient=$2
    
    if [ -z "$commit_tx_id" ]; then
        print_error "Usage: reveal <commit_tx_id> [recipient]"
        print_info "Example: ./test_hrc20.sh reveal abc123... hoosat:qz..."
        return 1
    fi
    
    if [ -z "$recipient" ] && [ -f /tmp/hrc20_canister_address.txt ]; then
        recipient=$(cat /tmp/hrc20_canister_address.txt)
    fi
    
    if [ -z "$recipient" ]; then
        print_error "No recipient provided and no cached address found"
        return 1
    fi
    
    print_header "Revealing Operation"
    print_info "Commit TX ID: $commit_tx_id"
    print_info "Recipient: $recipient"
    
    dfx canister call $CANISTER revealOperation "(\"$commit_tx_id\", \"$recipient\")"
}

# Get pending reveals
get_pending() {
    print_header "Getting Pending Reveals"
    dfx canister call $CANISTER getPendingReveals
}

# Get redeem script
get_redeem_script() {
    local commit_tx_id=$1
    
    if [ -z "$commit_tx_id" ]; then
        print_error "Usage: get_redeem_script <commit_tx_id>"
        return 1
    fi
    
    print_header "Getting Redeem Script"
    dfx canister call $CANISTER getRedeemScript "(\"$commit_tx_id\")"
}

# Estimate fees
estimate_fees() {
    local operation=$1
    
    if [ -z "$operation" ]; then
        print_error "Usage: estimate_fees <operation_json>"
        print_info "Example: ./test_hrc20.sh estimate_fees '{\"p\":\"hrc-20\",\"op\":\"mint\",\"tick\":\"TEST\"}'"
        return 1
    fi
    
    print_header "Estimating Fees"
    dfx canister call $CANISTER estimateFees "(\"$operation\")"
}

# Run all basic tests
test_all() {
    print_header "Running All HRC20 Tests"
    
    check_dfx
    get_address
    
    local address=$(cat /tmp/hrc20_canister_address.txt 2>/dev/null)
    if [ -n "$address" ]; then
        get_balance "$address"
        get_pending
    fi
    
    print_success "Basic tests completed!"
    print_info "To deploy a token, run:"
    print_info "  ./test_hrc20.sh deploy_token MYTOK 21000000000000000 100000000000 8"
}

# Show help
show_help() {
    echo "HRC20 Example Canister Test Script"
    echo ""
    echo "Usage: ./test_hrc20.sh [command] [args...]"
    echo ""
    echo "Commands:"
    echo "  check              - Check if DFX is running"
    echo "  address            - Get canister's Hoosat address"
    echo "  balance [address]  - Get HTN balance (uses cached address if none provided)"
    echo "  consolidate [n]    - Consolidate UTXOs n times (default: 1)"
    echo "  deploy <args>      - Deploy a new HRC20 token"
    echo "  mint <args>        - Mint tokens"
    echo "  reveal <args>      - Reveal operation after commit"
    echo "  pending            - List pending reveals"
    echo "  redeem <txid>      - Get redeem script for commit TX"
    echo "  estimate <json>    - Estimate fees for operation"
    echo "  test               - Run all basic tests"
    echo "  help               - Show this help"
    echo ""
    echo "Examples:"
    echo "  ./test_hrc20.sh address"
    echo "  ./test_hrc20.sh balance"
    echo "  ./test_hrc20.sh consolidate 5       # Run consolidation 5 times"
    echo "  ./test_hrc20.sh deploy MYTOK 21000000000000000 100000000000 8"
    echo "  ./test_hrc20.sh mint MYTOK"
    echo "  ./test_hrc20.sh reveal <commit_tx_id>"
    echo ""
    echo "Workflow:"
    echo "  1. Get address: ./test_hrc20.sh address"
    echo "  2. Fund the address with HTN (need ~2100+ HTN for deploy)"
    echo "  3. Consolidate UTXOs: ./test_hrc20.sh consolidate 10"
    echo "  4. Deploy token: ./test_hrc20.sh deploy MYTOK 21000000000000000 100000000000 8"
    echo "  5. Wait ~10 seconds for commit to confirm"
    echo "  6. Reveal: ./test_hrc20.sh reveal <commit_tx_id>"
    echo ""
    echo "Fees:"
    echo "  - Deploy: 1000 HTN commit + 1000 HTN reveal = 2000 HTN total"
    echo "  - Mint: 1 HTN fee"
    echo "  - Transfer: Network fees only"
}

# Main command handler
case "${1:-test}" in
    check)
        check_dfx
        ;;
    address|addr)
        get_address
        ;;
    balance|bal)
        get_balance "$2"
        ;;
    consolidate|consol)
        # Check if second argument is a number (count) or address
        if [ -n "$2" ] && echo "$2" | grep -qE '^[0-9]+$'; then
            # Second arg is a number - use as count with cached/default address
            consolidate_utxos "" "$2"
        else
            # Second arg is address (or empty), third arg is count
            consolidate_utxos "$2" "$3"
        fi
        ;;
    deploy|deploy_token)
        shift
        deploy_token "$@"
        ;;
    mint|mint_token)
        shift
        mint_token "$@"
        ;;
    reveal)
        shift
        reveal "$@"
        ;;
    pending|reveals)
        get_pending
        ;;
    redeem|script)
        get_redeem_script "$2"
        ;;
    estimate|fees)
        estimate_fees "$2"
        ;;
    test|all)
        test_all
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
