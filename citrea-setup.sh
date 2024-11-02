#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default configuration
node_name="citrea_node"
rpc_port=8545
citrea_port=8546

# Variables for diagnostics
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAX_RETRIES=5
RETRY_DELAY=5

# Logging functions
log_info() { echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }

# Progress indicators
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

# Show logo function
show_logo() {
    # Definisi warna-warna
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    # Logo dengan gradasi warna
    echo -e "${PURPLE}      ___      __    __       ___       __    __  "
    echo -e "${CYAN}       /   \    |  |  |  |     /   \     |  |  |  | "
    echo -e "${YELLOW}    /  ^  \   |  |  |  |    /  ^  \    |  |__|  | "
    echo -e "${RED}      /  /_\  \  |  |  |  |   /  /_\  \   |   __   | "
    echo -e "${BLUE}    /  _____  \ | \`--'  |  /  _____  \  |  |  |  | "
    echo -e "${PURPLE} /__/     \__\ \______/  /__/     \__\ |__|  |__| "
    echo -e "${CYAN}            Community ahh.. ahh.. ahh..${NC}"
    sleep 2
}

# Check system requirements
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        show_error "Minimum 2 CPU cores required. Found: $cpu_cores"
        return 1
    fi
    
    # Check RAM
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 4096 ]; then
        show_error "Minimum 4GB RAM required. Found: $total_ram MB"
        return 1
    }
    
    # Check disk space
    local free_space=$(df -m . | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 20480 ]; then
        show_error "Minimum 20GB free space required. Found: $free_space MB"
        return 1
    }
    
    log_info "System requirements met"
    return 0
}

# Install missing dependencies
install_missing_deps() {
    log_info "Installing required dependencies..."
    
    local packages=(
        curl
        wget
        tar
        ufw
        netcat
        jq
    )
    
    if command -v apt-get >/dev/null; then
        sudo apt-get update
        sudo apt-get install -y "${packages[@]}"
    elif command -v yum >/dev/null; then
        sudo yum install -y "${packages[@]}"
    else
        show_error "Unsupported package manager"
        return 1
    fi
    
    log_info "Dependencies installed successfully"
    return 0
}

# Check if all required dependencies are installed
check_dependencies() {
    log_info "Checking dependencies..."
    
    local required_commands=(
        curl
        wget
        tar
        nc
        jq
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null; then
            show_error "Required command not found: $cmd"
            return 1
        fi
    done
    
    log_info "All dependencies are installed"
    return 0
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall rules..."
    
    if command -v ufw >/dev/null; then
        sudo ufw allow ssh
        sudo ufw allow ${rpc_port}/tcp
        sudo ufw allow ${citrea_port}/tcp
        sudo ufw --force enable
        log_info "Firewall rules added for ports ${rpc_port} and ${citrea_port}"
    else
        log_warn "UFW not installed, skipping firewall configuration"
    fi
    
    return 0
}

# Setup Citrea
setup_citrea() {
    show_progress "Setting up Citrea..."
    
    # Clean up existing installation if present
    if [ -d "${node_name}" ]; then
        log_warn "Existing installation found. Cleaning up..."
        rm -rf "${node_name}"
    fi
    
    # Create and enter installation directory
    if ! mkdir -p "${node_name}"; then
        show_error "Failed to create directory: ${node_name}"
        return 1
    fi
    
    if ! cd "${node_name}"; then
        show_error "Failed to enter directory: ${node_name}"
        return 1
    fi
    
    # Create logs directory
    mkdir -p logs
    
    # Download required files
    show_progress "Downloading Citrea files..."
    
    local files=(
        "https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64"
        "https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml"
        "https://static.testnet.citrea.xyz/genesis.tar.gz"
    )
    
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        log_info "Downloading ${filename}..."
        if ! wget -q "$file"; then
            show_error "Failed to download ${filename}"
            return 1
        fi
        log_info "${filename} downloaded successfully"
    done
    
    # Extract genesis files
    log_info "Extracting genesis files..."
    if ! tar xzf genesis.tar.gz; then
        show_error "Failed to extract genesis files"
        return 1
    fi
    
    # Set correct permissions
    chmod +x ./citrea-v0.5.4-linux-amd64
    
    # Configure rollup_config.toml
    log_info "Configuring rollup_config.toml..."
    if [ ! -f rollup_config.toml ]; then
        show_error "rollup_config.toml not found after download"
        return 1
    fi
    
    # Backup original config
    cp rollup_config.toml rollup_config.toml.backup
    
    # Update configuration
    sed -i "s/rpc_user = .*/rpc_user = \"citrea\"/" rollup_config.toml
    sed -i "s/rpc_password = .*/rpc_password = \"citrea\"/" rollup_config.toml
    sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" rollup_config.toml
    sed -i "s/api_port = .*/api_port = ${citrea_port}/" rollup_config.toml
    
    log_info "Configuration updated successfully"
    return 0
}

# Start Citrea node
start_citrea_node() {
    log_info "Starting Citrea node..."
    
    # Create startup script
    cat > start.sh << EOF
#!/bin/bash
./citrea-v0.5.4-linux-amd64 --config rollup_config.toml > logs/citrea.log 2>&1 &
echo \$! > citrea.pid
EOF
    
    chmod +x start.sh
    
    # Start the node
    ./start.sh
    
    # Check if process started
    sleep 5
    if [ -f citrea.pid ] && kill -0 $(cat citrea.pid) 2>/dev/null; then
        log_info "Citrea node started successfully"
        return 0
    else
        show_error "Failed to start Citrea node"
        return 1
    fi
}

# Verify RPC connection
verify_rpc_connection() {
    log_info "Verifying RPC connection..."
    
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[],"id":1}' \
            http://localhost:${citrea_port} > /dev/null; then
            log_info "RPC connection verified"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_warn "RPC connection attempt $retry_count failed. Retrying in ${RETRY_DELAY} seconds..."
        sleep $RETRY_DELAY
    done
    
    show_error "Failed to verify RPC connection after $MAX_RETRIES attempts"
    return 1
}

# Run diagnostics
run_diagnostics() {
    log_info "Running diagnostics..."
    
    # Check process status
    if [ -f "${node_name}/citrea.pid" ]; then
        local pid=$(cat "${node_name}/citrea.pid")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Citrea process is running (PID: $pid)"
        else
            log_error "Citrea process is not running"
        fi
    fi
    
    # Check logs for errors
    if [ -f "${node_name}/logs/citrea.log" ]; then
        log_info "Last 10 lines of citrea.log:"
        tail -n 10 "${node_name}/logs/citrea.log"
    fi
    
    # Check port status
    log_info "Checking port status..."
    if nc -z localhost ${rpc_port}; then
        log_info "RPC port ${rpc_port} is open"
    else
        log_error "RPC port ${rpc_port} is not accessible"
    fi
    
    if nc -z localhost ${citrea_port}; then
        log_info "Citrea port ${citrea_port} is open"
    else
        log_error "Citrea port ${citrea_port} is not accessible"
    fi
}

# Show node information
show_node_info() {
    cat << EOF

=== Citrea Node Information ===
Node Name: ${node_name}
RPC Endpoint: http://localhost:${rpc_port}
API Endpoint: http://localhost:${citrea_port}
Log Location: ${node_name}/logs/
Config File: ${node_name}/rollup_config.toml

To check node status:
curl -X POST --header "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[],"id":1}' \
    http://localhost:${citrea_port}
EOF
}

# Main function
main() {
    clear
    show_logo
    
    log_info "Starting Citrea Node Installation"
    
    local setup_steps=(
        "check_system_requirements"
        "install_missing_deps"
        "check_dependencies"
        "configure_firewall"
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
        sleep 2
    done
    
    show_node_info
    log_info "Installation completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
