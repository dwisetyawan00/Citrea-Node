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

# Diagnostic Functions
check_citrea_process() {
    log_info "Checking Citrea process..."
    if pgrep -f "citrea-v0.5.4-linux-amd64" > /dev/null; then
        log_info "Citrea process is running"
        return 0
    else
        log_error "Citrea process is not running"
        return 1
    fi
}

check_port_availability() {
    local port=$1
    log_info "Checking port $port availability..."
    
    if netstat -tuln | grep ":$port " > /dev/null; then
        log_warn "Port $port is already in use"
        log_info "Process using port $port:"
        lsof -i ":$port"
        return 1
    else
        log_info "Port $port is available"
        return 0
    fi
}

verify_config_files() {
    log_info "Verifying configuration files..."
    local config_file="rollup_config.toml"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file $config_file not found"
        return 1
    fi
    
    log_info "Contents of $config_file:"
    echo "----------------------------------------"
    grep -E "rpc_user|rpc_password|rpc_port" "$config_file"
    echo "----------------------------------------"
    
    return 0
}

check_network_connectivity() {
    local rpc_port=$1
    log_info "Testing network connectivity..."
    
    if nc -zv localhost $rpc_port 2>/dev/null; then
        log_info "Port $rpc_port is open locally"
    else
        log_warn "Port $rpc_port is not accessible locally"
    fi
    
    if command -v ufw >/dev/null; then
        log_info "UFW Firewall status:"
        sudo ufw status | grep $rpc_port
    fi
}

check_system_logs() {
    log_info "Checking system logs for Citrea-related errors..."
    
    journalctl -u citrea --since "5 minutes ago" 2>/dev/null || \
    log_warn "No Citrea service logs found in journald"
    
    tail -n 20 /var/log/syslog 2>/dev/null | grep -i "citrea" || \
    log_warn "No Citrea-related messages found in syslog"
}

run_diagnostics() {
    log_info "Running Citrea diagnostics..."
    check_citrea_process
    check_port_availability $rpc_port
    check_port_availability $citrea_port
    verify_config_files
    check_network_connectivity $rpc_port
    check_system_logs
}

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
    local deps=(curl wget jq gpg tar netcat lsof)
    
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

install_missing_deps() {
    show_progress "Installing required system packages..."
    sudo apt-get update
    sudo apt-get install -y net-tools netcat curl wget jq gpg tar lsof
}

start_citrea_node() {
    show_progress "Starting Citrea node..."
    
    # Verify genesis paths
    if [ ! -f "genesis/genesis.json" ]; then
        show_error "Genesis file not found in expected location"
        return 1
    fi
    
    # Start the node with correct arguments
    ./citrea-v0.5.4-linux-amd64 --genesis-paths genesis/genesis.json \
        --config rollup_config.toml > citrea.log 2>&1 &
    local pid=$!
    
    # Wait for node to start
    sleep 10
    
    if ! ps -p $pid > /dev/null; then
        show_error "Failed to start Citrea node"
        log_error "Node startup failed. Check citrea.log for details:"
        tail -n 20 citrea.log
        return 1
    fi
    
    log_info "Citrea node started with PID: $pid"
    verify_node_status
    return 0
}

verify_node_status() {
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Checking node status (attempt $attempt/$max_attempts)..."
        
        if curl -s -X POST \
            --header "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[], "id":31}' \
            http://0.0.0.0:${citrea_port} | grep -q "result"; then
            
            log_info "Node is responding to API calls"
            return 0
        fi
        
        log_warn "Node not responding yet, waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    log_error "Node failed to respond after $max_attempts attempts"
    return 1
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
    run_diagnostics  # Run diagnostics if RPC connection fails
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
    echo "3. Run Diagnostics Only"
    echo "=================================="
    read -p "Choose option (1/2/3): " config_choice
    
    case $config_choice in
        1)
            node_name="citrea-node"
            rpc_port="18443"
            citrea_port="8080"
            
            log_info "Running pre-installation diagnostics for default configuration..."
            run_diagnostics
            read -p "Continue with installation? (y/n): " continue_install
            if [[ $continue_install != "y" ]]; then
                log_info "Installation cancelled by user"
                exit 0
            fi
            ;;
        2)
            get_manual_config
            
            log_info "Running pre-installation diagnostics for manual configuration..."
            run_diagnostics
            read -p "Continue with installation? (y/n): " continue_install
            if [[ $continue_install != "y" ]]; then
                log_info "Installation cancelled by user"
                exit 0
            fi
            ;;
        3)
            node_name="citrea-node"
            rpc_port="18443"
            citrea_port="8080"
            log_info "Running standalone diagnostics..."
            run_diagnostics
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Setup steps
   local setup_steps=(
    "install_missing_deps"  
    "check_dependencies"
    "setup_citrea"
    "start_citrea_node"
    "verify_rpc_connection"
)
    
    for step in "${setup_steps[@]}"; do
        log_info "Executing step: $step"
        if ! $step; then
            log_error "Failed at step: $step"
            log_info "Running post-failure diagnostics..."
            run_diagnostics
            exit 1
        fi
        
        # Run intermediate diagnostics after critical steps
        if [[ "$step" == "start_citrea_node" ]]; then
            log_info "Running post-startup diagnostics..."
            run_diagnostics
        fi
    done
    
    show_node_info
    log_info "Installation completed successfully!"
    
    # Run final diagnostics
    log_info "Running final health check..."
    run_diagnostics
    
    log_warn "Important: Node requires time for full synchronization"
    log_warn "Use the status check command above to monitor progress"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM
    main "$@"
fi
