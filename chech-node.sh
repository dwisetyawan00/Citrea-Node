#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default configuration
BTC_RPC_PORT=18443
BTC_RPC_USER="citrea"
BTC_RPC_PASS="citrea"
CITREA_PORT=8080

# Logging functions
log_header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_detail() { echo -e "${CYAN}$1${NC}"; }

# Helper function for Bitcoin JSON-RPC calls
bitcoin_cli() {
    local method=$1
    shift
    local params=$@
    
    curl -s --user ${BTC_RPC_USER}:${BTC_RPC_PASS} \
        --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"script\", \"method\": \"$method\", \"params\": [$params]}" \
        -H 'content-type: text/plain;' \
        http://localhost:${BTC_RPC_PORT}
}

check_bitcoin_node() {
    log_header "Bitcoin Testnet4 Node Status"
    
    # Check if node is responding
    local blockcount_response=$(bitcoin_cli getblockcount)
    if [ $? -ne 0 ]; then
        log_error "Bitcoin node is not responding"
        return 1
    fi
    
    # Get node information
    log_info "Node Status: RUNNING"
    
    # Block height
    local block_height=$(echo $blockcount_response | grep -o '"result":[0-9]*' | cut -d':' -f2)
    log_detail "Block Height: $block_height"
    
    # Network info
    local network_info=$(bitcoin_cli getnetworkinfo)
    local version=$(echo $network_info | grep -o '"version":[0-9]*' | cut -d':' -f2)
    local connections=$(echo $network_info | grep -o '"connections":[0-9]*' | cut -d':' -f2)
    log_detail "Version: $version"
    log_detail "Connections: $connections"
    
    # Blockchain info
    local blockchain_info=$(bitcoin_cli getblockchaininfo)
    local chain=$(echo $blockchain_info | grep -o '"chain":"[^"]*' | cut -d'"' -f4)
    local headers=$(echo $blockchain_info | grep -o '"headers":[0-9]*' | cut -d':' -f2)
    local verification_progress=$(echo $blockchain_info | grep -o '"verificationprogress":[0-9.]*' | cut -d':' -f2)
    verification_progress=$(echo "$verification_progress * 100" | bc -l | xargs printf "%.2f")
    
    log_detail "Chain: $chain"
    log_detail "Headers: $headers"
    log_detail "Sync Progress: ${verification_progress}%"
    
    # Memory pool information
    local mempool_info=$(bitcoin_cli getmempoolinfo)
    local mempool_size=$(echo $mempool_info | grep -o '"size":[0-9]*' | cut -d':' -f2)
    local mempool_bytes=$(echo $mempool_info | grep -o '"bytes":[0-9]*' | cut -d':' -f2)
    
    log_detail "Mempool Transactions: $mempool_size"
    log_detail "Mempool Size: $(echo "$mempool_bytes/1024/1024" | bc -l | xargs printf "%.2f") MB"
    
    # Check if syncing
    if [ "$headers" -gt "$block_height" ]; then
        log_warn "Node is still syncing - $block_height/$headers blocks"
    else
        log_info "Node is fully synced"
    fi
}

check_citrea_node() {
    log_header "Citrea Node Status"
    
    # Check if node is responding
    local response=$(curl -s -X POST \
        --header "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[],"id":31}' \
        http://localhost:${CITREA_PORT})
    
    if [ $? -eq 0 ] && [ ! -z "$response" ]; then
        log_info "Node Status: RUNNING"
        log_detail "Sync Status: $response"
        
        # Check node directory and logs
        local node_dir=$(cat /tmp/citrea_node_path 2>/dev/null)
        if [ ! -z "$node_dir" ] && [ -f "$node_dir/citrea.log" ]; then
            log_header "Recent Citrea Logs"
            echo -e "${CYAN}"
            tail -n 5 "$node_dir/citrea.log"
            echo -e "${NC}"
        fi
    else
        log_error "Citrea node is not responding"
        return 1
    fi
}

check_docker_status() {
    if command -v docker &> /dev/null; then
        log_header "Docker Container Status"
        echo -e "${CYAN}"
        docker ps --filter "name=bitcoin-testnet4" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo -e "${NC}"
    fi
}

show_help() {
    echo "Citrea & Bitcoin Node Status Monitor"
    echo ""
    echo "Usage:"
    echo "  $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help          Show this help message"
    echo "  --btc-port     Bitcoin RPC port (default: 18443)"
    echo "  --btc-user     Bitcoin RPC username"
    echo "  --btc-pass     Bitcoin RPC password"
    echo "  --citrea-port  Citrea node port (default: 8080)"
    echo "  --monitor      Continuous monitoring (updates every 10 seconds)"
    echo ""
    echo "Example:"
    echo "  $0 --monitor"
    echo "  $0 --btc-port 18443 --btc-user custom --btc-pass secret"
}

# Parse command line arguments
MONITOR_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --btc-port)
            BTC_RPC_PORT="$2"
            shift 2
            ;;
        --btc-user)
            BTC_RPC_USER="$2"
            shift 2
            ;;
        --btc-pass)
            BTC_RPC_PASS="$2"
            shift 2
            ;;
        --citrea-port)
            CITREA_PORT="$2"
            shift 2
            ;;
        --monitor)
            MONITOR_MODE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

check_all_nodes() {
    clear
    echo "Last Update: $(date '+%Y-%m-%d %H:%M:%S')"
    check_bitcoin_node
    check_citrea_node
    check_docker_status
    
    log_header "Node Status Summary"
    local btc_status=$(bitcoin_cli getblockcount >/dev/null 2>&1 && echo "Running" || echo "Stopped")
    local citrea_status=$(curl -s localhost:${CITREA_PORT} >/dev/null 2>&1 && echo "Running" || echo "Stopped")
    
    log_detail "Bitcoin Node: $btc_status"
    log_detail "Citrea Node: $citrea_status"
    
    if [ "$btc_status" = "Running" ] && [ "$citrea_status" = "Running" ]; then
        log_info "All nodes are operational"
    else
        log_warn "Some nodes are not running"
    fi
}

if [ "$MONITOR_MODE" = true ]; then
    while true; do
        check_all_nodes
        sleep 10
    done
else
    check_all_nodes
fi
