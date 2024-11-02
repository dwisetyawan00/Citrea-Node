#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables for diagnostics
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAX_RETRIES=5
RETRY_DELAY=5

# Logging functions
log_info() { echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }

# Show logo
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Progress indicators
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

# Check system requirements
check_system_requirements() {
    log_info "Checking system resources..."
    
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        log_error "Minimum 2 CPU cores required. Found: $cpu_cores"
        return 1
    fi
    
    local ram_mb=$(free -m | awk '/Mem:/ {print $2}')
    if [ "$ram_mb" -lt 4096 ]; then
        log_error "Minimum 4GB RAM required. Found: $((ram_mb/1024))GB"
        return 1
    fi
    
    local disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$disk_gb" -lt 50 ]; then
        log_error "Minimum 50GB free disk space required. Found: ${disk_gb}GB"
        return 1
    fi
    
    log_info "System resources check passed"
    return 0
}

# Check dependencies
check_dependencies() {
    show_progress "Checking basic dependencies..."
    local deps=(curl wget jq gpg tar netcat)
    
    for pkg in "${deps[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            show_warning "$pkg not found. Installing $pkg..."
            if ! sudo apt-get update && sudo apt-get install -y $pkg; then
                show_error "Failed to install $pkg"
                return 1
            fi
        fi
    done
    return 0
}

# Verify RPC connection
verify_rpc_connection() {
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        local response=$(curl -s --user citrea:citrea \
            --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getnetworkinfo", "params": []}' \
            -H 'content-type: text/plain;' \
            http://0.0.0.0:${rpc_port})
        
        if [ $? -eq 0 ] && [[ $response == *"version"* ]]; then
            log_info "RPC connection successful"
            return 0
        fi
        
        log_warn "RPC connection attempt $attempt failed. Waiting ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
        attempt=$((attempt + 1))
    done
    
    log_error "Failed to establish RPC connection after $MAX_RETRIES attempts"
    return 1
}

# Setup Citrea
setup_citrea() {
    show_progress "Setting up Citrea..."
    
    if ! mkdir -p "${node_name}" || ! cd "${node_name}"; then
        show_error "Failed to setup Citrea directory"
        return 1
    fi
    
    local files=(
        "https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64"
        "https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml"
        "https://static.testnet.citrea.xyz/genesis.tar.gz"
    )
    
    for file in "${files[@]}"; do
        if ! wget -q --tries=3 --timeout=15 "$file"; then
            show_error "Failed to download: $(basename "$file")"
            return 1
        fi
    done
    
    if ! tar xf genesis.tar.gz || ! chmod +x ./citrea-v0.5.4-linux-amd64; then
        show_error "Failed to setup Citrea files"
        return 1
    fi
    
    if ! sed -i "s/rpc_user = .*/rpc_user = \"citrea\"/" rollup_config.toml || \
       ! sed -i "s/rpc_password = .*/rpc_password = \"citrea\"/" rollup_config.toml || \
       ! sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" rollup_config.toml; then
        show_error "Failed to update rollup config"
        return 1
    fi
    
    return 0
}

get_manual_config() {
    echo "=== Node Configuration ==="
    read -p "Node Name (default: citrea-node): " node_name
    node_name=${node_name:-citrea-node}
    
    read -p "RPC Port (default: 18443): " rpc_port
    rpc_port=${rpc_port:-18443}
    
    read -p "Citrea Port (default: 8080): " citrea_port
    citrea_port=${citrea_port:-8080}
}

show_node_info() {
    echo -e "\n=== Node Information ==="
    echo "Node Name: ${node_name}"
    echo "Bitcoin RPC: http://0.0.0.0:${rpc_port}"
    echo "Citrea API: http://0.0.0.0:${citrea_port}"
    echo -e "\nTo check sync status:"
    echo "curl -X POST --header \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"citrea_syncStatus\",\"params\":[], \"id\":31}' http://0.0.0.0:${citrea_port}"
}

main() {
    clear
    show_logo
    
    log_info "Starting Citrea Node Installation"
    
    if ! check_system_requirements; then
        log_error "Insufficient system resources"
        exit 1
    fi
    
    # Get configuration
    echo "=================================="
    echo "   Citrea Node Installation       "
    echo "=================================="
    echo "1. Default Configuration"
    echo "2. Manual Configuration"
    echo "=================================="
    read -p "Choose option (1/2): " config_choice
    
    case $config_choice in
        1)
            node_name="citrea-node"
            rpc_port="18443"
            citrea_port="8080"
            ;;
        2)
            get_manual_config
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Setup steps
    local setup_steps=(
        "check_dependencies"
        "setup_citrea"
        "verify_rpc_connection"
    )
    
    for step in "${setup_steps[@]}"; do
        log_info "Executing step: $step"
        if ! $step; then
            log_error "Failed at step: $step"
            exit 1
        fi
    done
    
    show_node_info
    log_info "Installation completed successfully!"
    log_warn "Important: Node requires time for full synchronization"
    log_warn "Use the status check command above to monitor progress"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM
    main "$@"
fi
