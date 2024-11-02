#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
DEFAULT_NODE_NAME="citrea_node"
rpc_port=8545
citrea_port=8546
node_name=""

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

# Modified get_node_name function
get_node_name() {
    while true; do
        printf "${CYAN}Masukkan nama node: ${NC}"
        read -r input
        
        if [[ $input =~ ^[a-zA-Z0-9_]+$ ]]; then
            node_name="$input"
            break
        else
            echo -e "${RED}Nama node hanya boleh menggunakan huruf, angka, dan underscore${NC}"
        fi
    done
}

# Show logo function - now only in green
show_logo() {
    echo -e "${GREEN}     ___      __    __       ___       __    __  "
    echo -e "    /   \    |  |  |  |     /   \     |  |  |  | "
    echo -e "   /  ^  \   |  |  |  |    /  ^  \    |  |__|  | "
    echo -e "  /  /_\  \  |  |  |  |   /  /_\  \   |   __   | "
    echo -e " /  _____  \ |  \`--'  |  /  _____  \  |  |  |  | "
    echo -e "/__/     \__\ \______/  /__/     \__\ |__|  |__| "
    echo -e "            Community ahh.. ahh.. ahh..${NC}"
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
    fi
    
    # Check disk space
    local free_space=$(df -m . | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 20480 ]; then
        show_error "Minimum 20GB free space required. Found: $free_space MB"
        return 1
    fi
    
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
    
    # Ensure we're working with absolute paths
    local current_dir=$(pwd)
    local node_dir="${current_dir}/${node_name}"
    
    log_info "Setting up node in directory: ${node_dir}"
    
    # Remove existing directory if exists
    if [ -d "${node_dir}" ]; then
        log_warn "Existing node directory found. Removing..."
        rm -rf "${node_dir}"
    fi
    
    # Create fresh directory
    if ! mkdir -p "${node_dir}"; then
        show_error "Failed to create directory: ${node_dir}"
        return 1
    fi
    
    # Change to node directory
    if ! cd "${node_dir}"; then
        show_error "Failed to enter directory: ${node_dir}"
        return 1
    fi
    
    # Create logs directory
    if ! mkdir -p "${node_dir}/logs"; then
        show_error "Failed to create logs directory"
        return 1
    fi
    
    # Download required files
    show_progress "Downloading Citrea files..."
    
    local binary_url="https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64"
    local config_url="https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml"
    local genesis_url="https://static.testnet.citrea.xyz/genesis.tar.gz"
    
    log_info "Working directory: $(pwd)"
    
    # Download binary
    log_info "Downloading citrea binary..."
    if ! wget -q "$binary_url" -O "${node_dir}/citrea-v0.5.4-linux-amd64"; then
        show_error "Failed to download binary"
        return 1
    fi
    chmod +x "${node_dir}/citrea-v0.5.4-linux-amd64"
    
    # Download config
    log_info "Downloading rollup_config.toml..."
    if ! wget -q "$config_url" -O "${node_dir}/rollup_config.toml"; then
        show_error "Failed to download configuration file"
        return 1
    fi
    
    # Download genesis
    log_info "Downloading genesis.tar.gz..."
    if ! wget -q "$genesis_url" -O "${node_dir}/genesis.tar.gz"; then
        show_error "Failed to download genesis file"
        return 1
    fi
    
    # Extract genesis files
    log_info "Extracting genesis files..."
    if ! cd "${node_dir}" || ! tar xf genesis.tar.gz; then
        show_error "Failed to extract genesis files"
        return 1
    fi
    
    # Verify files exist
    if [ ! -f "${node_dir}/rollup_config.toml" ] || [ ! -f "${node_dir}/citrea-v0.5.4-linux-amd64" ]; then
        show_error "Required files missing after download"
        return 1
    fi
    
    # Configure rollup_config.toml
    log_info "Configuring rollup_config.toml..."
    sed -i "s/rpc_host = .*/rpc_host = \"0.0.0.0\"/" "${node_dir}/rollup_config.toml"
    sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" "${node_dir}/rollup_config.toml"
    sed -i "s/api_host = .*/api_host = \"0.0.0.0\"/" "${node_dir}/rollup_config.toml"
    sed -i "s/api_port = .*/api_port = ${citrea_port}/" "${node_dir}/rollup_config.toml"
    sed -i "s/network = .*/network = \"testnet\"/" "${node_dir}/rollup_config.toml"
    
    # Save node directory path for other functions
    echo "${node_dir}" > /tmp/citrea_node_path
    
    log_info "Configuration updated successfully"
    return 0
}

# Start Citrea node
start_citrea_node() {
    log_info "Starting Citrea node..."
    
    # Get node directory path from temp file
    local node_dir=$(cat /tmp/citrea_node_path)
    
    if [ ! -d "$node_dir" ]; then
        show_error "Node directory not found: ${node_dir}"
        return 1
    fi
    
    log_info "Using node directory: ${node_dir}"
    
    if ! cd "${node_dir}"; then
        show_error "Failed to enter node directory: ${node_dir}"
        return 1
    fi
    
    # Verify required files exist
    if [ ! -f "${node_dir}/citrea-v0.5.4-linux-amd64" ] || [ ! -f "${node_dir}/rollup_config.toml" ]; then
        show_error "Required files missing. Please check installation."
        ls -la "${node_dir}"  # Debug output
        return 1
    fi
    
    # Create startup script
    cat > "${node_dir}/start.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "${SCRIPT_DIR}"

exec 1> >(tee -a logs/citrea.log)
exec 2>&1

if [ -f citrea.pid ]; then
    old_pid=$(cat citrea.pid)
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "Stopping old process..."
        kill "$old_pid"
        sleep 5
    fi
    rm citrea.pid
fi

echo "Starting Citrea node at $(date)"
./citrea-v0.5.4-linux-amd64 start --config rollup_config.toml &
echo $! > citrea.pid

# Wait for process to start
sleep 5
if ! kill -0 $(cat citrea.pid) 2>/dev/null; then
    echo "Process failed to start"
    exit 1
fi

echo "Node started successfully"
EOF
    
    chmod +x "${node_dir}/start.sh"
    
    # Start the node
    if ! "${node_dir}/start.sh"; then
        show_error "Failed to start node process"
        cat "${node_dir}/logs/citrea.log"
        return 1
    fi
    
    log_info "Citrea node started successfully"
    return 0
}

# Tambahkan fungsi cleanup
cleanup() {
    if [ -f /tmp/citrea_node_path ]; then
        rm /tmp/citrea_node_path
    fi
}

# Tambahkan trap untuk cleanup
trap cleanup EXIT

# Verify RPC connection
verify_rpc_connection() {
    log_info "Verifying RPC connection..."
    
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # First check if process is still running
        if [ -f "${node_name}/citrea.pid" ]; then
            local pid=$(cat "${node_name}/citrea.pid")
            if ! kill -0 "$pid" 2>/dev/null; then
                show_error "Node process is not running"
                return 1
            fi
        else
            show_error "PID file not found"
            return 1
        fi
        
        # Try RPC connection
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
    if [ -f "${node_name}/logs/citrea.log" ]; then
        log_error "Last 20 lines of node log:"
        tail -n 20 "${node_name}/logs/citrea.log"
    fi
    return 1
}

# Run diagnostics
run_diagnostics() {
    log_info "Running diagnostics..."
    
    # Check system resources
    log_info "System Resources:"
    echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    echo "Memory Usage: $(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')"
    echo "Disk Usage: $(df -h . | awk 'NR==2{print $5}')"
    
    # Check process status
    if [ -f "${node_name}/citrea.pid" ]; then
        local pid=$(cat "${node_name}/citrea.pid")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Citrea process is running (PID: $pid)"
            ps -p "$pid" -o %cpu,%mem,cmd
        else
            log_error "Citrea process is not running"
        fi
    fi
    
    # Check port status
    log_info "Checking port status..."
    echo "Network connections:"
    netstat -tuln | grep -E "${rpc_port}|${citrea_port}" || echo "No ports listening"
    
    # Check firewall status
    log_info "Firewall status:"
    sudo ufw status | grep -E "${rpc_port}|${citrea_port}"
    
    # Check configuration
    log_info "Configuration check:"
    if [ -f "${node_name}/rollup_config.toml" ]; then
        echo "Config file exists and contains:"
        grep -E "rpc_port|api_port" "${node_name}/rollup_config.toml"
    else
        log_error "Configuration file missing"
    fi
    
    # Check logs
    if [ -f "${node_name}/logs/citrea.log" ]; then
        log_info "Last 20 lines of citrea.log:"
        tail -n 20 "${node_name}/logs/citrea.log"
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
    get_node_name
    
    log_info "Starting installation for node: $node_name"
    
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
