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

get_node_name() {
    local input_node_name=""
    echo -ne "${CYAN}masukkan nama node: ${NC}"
    read -r input_node_name
        
    # Validate node name (alphanumeric and underscores only)
    while ! [[ $input_node_name =~ ^[a-zA-Z0-9_]+$ ]]; do
        echo -e "${RED}Invalid node name. Use only letters, numbers, and underscores.${NC}"
        echo -ne "${CYAN}masukkan nama node: ${NC}"
        read -r input_node_name
    done
    echo "$input_node_name"
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
    
    cd "${node_name}" || {
        show_error "Failed to enter directory: ${node_name}"
        return 1
    }
    
    # Create logs directory
    mkdir -p logs
    
    # Download required files with explicit error checking
    show_progress "Downloading Citrea files..."
    
    local binary_url="https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64"
    local config_url="https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml"
    local genesis_url="https://static.testnet.citrea.xyz/genesis.tar.gz"
    
    # Download binary with retries
    log_info "Downloading citrea-v0.5.4-linux-amd64..."
    for i in $(seq 1 3); do
        if wget -q "$binary_url"; then
            chmod +x citrea-v0.5.4-linux-amd64
            log_info "Binary downloaded and made executable"
            break
        fi
        if [ $i -eq 3 ]; then
            show_error "Failed to download Citrea binary after 3 attempts"
            return 1
        fi
        log_warn "Binary download attempt $i failed, retrying..."
        sleep 2
    done
    
    # Download config
    log_info "Downloading rollup_config.toml..."
    if ! wget -q "$config_url"; then
        show_error "Failed to download configuration file"
        return 1
    fi
    
    # Download genesis
    log_info "Downloading genesis.tar.gz..."
    if ! wget -q "$genesis_url"; then
        show_error "Failed to download genesis file"
        return 1
    fi
    
    # Extract genesis files with error checking
    log_info "Extracting genesis files..."
    if ! tar xzf genesis.tar.gz; then
        show_error "Failed to extract genesis files"
        return 1
    fi
    
    # Verify binary exists and is executable
    if [ ! -f "./citrea-v0.5.4-linux-amd64" ]; then
        show_error "Binary not found after download"
        return 1
    fi
    
    if [ ! -x "./citrea-v0.5.4-linux-amd64" ]; then
        chmod +x ./citrea-v0.5.4-linux-amd64
        if [ ! -x "./citrea-v0.5.4-linux-amd64" ]; then
            show_error "Failed to make binary executable"
            return 1
        fi
    fi
    
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
    
    # Create node directory if it doesn't exist
    if [ ! -d "$node_name" ]; then
        log_info "Creating node directory: $node_name"
        mkdir -p "$node_name" || {
            show_error "Failed to create node directory: $node_name"
            return 1
        }
    fi
    
    cd "$node_name" || {
        show_error "Failed to enter node directory"
        return 1
    }
    
    # Check if binary exists and is executable
    if [ ! -f "./citrea-v0.5.4-linux-amd64" ]; then
        show_error "Citrea binary not found"
        return 1
    fi
    
    if [ ! -x "./citrea-v0.5.4-linux-amd64" ]; then
        show_error "Citrea binary is not executable"
        chmod +x ./citrea-v0.5.4-linux-amd64
    fi
    
    # Verify config file
    if [ ! -f "./rollup_config.toml" ]; then
        show_error "Configuration file not found"
        return 1
    fi
    
    # Check if ports are already in use
    if netstat -tuln | grep -q ":${rpc_port}"; then
        show_error "RPC port ${rpc_port} is already in use"
        return 1
    fi
    
    if netstat -tuln | grep -q ":${citrea_port}"; then
        show_error "Citrea port ${citrea_port} is already in use"
        return 1
    fi
    
    # Ensure logs directory exists and is writable
    mkdir -p logs
    if [ ! -w "logs" ]; then
        show_error "Logs directory is not writable"
        return 1
    fi
    
    # Create startup script with proper error handling
    cat > start.sh << 'EOF'
#!/bin/bash
exec 1> >(tee -a logs/citrea.log)
exec 2>&1

# Kill existing process if PID file exists
if [ -f citrea.pid ]; then
    old_pid=$(cat citrea.pid)
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "Killing existing process: $old_pid"
        kill "$old_pid"
        sleep 2
    fi
fi

# Start the node with detailed logging
echo "Starting Citrea node at $(date)"
./citrea-v0.5.4-linux-amd64 --config rollup_config.toml &

# Store PID
echo $! > citrea.pid

# Wait briefly to check if process stays running
sleep 5
if ! kill -0 $(cat citrea.pid) 2>/dev/null; then
    echo "Process failed to start or died immediately"
    exit 1
fi
EOF
    
    chmod +x start.sh
    
    log_info "Starting node process..."
    if ! ./start.sh; then
        show_error "Failed to start node process"
        if [ -f logs/citrea.log ]; then
            log_error "Last 10 lines of log:"
            tail -n 10 logs/citrea.log
        fi
        return 1
    fi
    
    # Enhanced process verification
    local max_wait=30
    local counter=0
    local pid
    
    if [ -f citrea.pid ]; then
        pid=$(cat citrea.pid)
        
        while [ $counter -lt $max_wait ]; do
            if kill -0 "$pid" 2>/dev/null; then
                # Check if ports are listening
                sleep 2
                if netstat -tuln | grep -q ":${rpc_port}" && \
                   netstat -tuln | grep -q ":${citrea_port}"; then
                    log_info "Citrea node started successfully with PID: $pid"
                    return 0
                fi
            else
                show_error "Process died after starting. Check logs for details"
                if [ -f logs/citrea.log ]; then
                    tail -n 20 logs/citrea.log
                fi
                return 1
            fi
            
            counter=$((counter + 1))
            sleep 1
        done
        
        show_error "Node started but ports are not listening after ${max_wait} seconds"
        return 1
    else
        show_error "PID file not created"
        return 1
    fi
}

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
    # Get node name first
    node_name=$(get_node_name)
    # Then show logo
    show_logo
    
    log_info "Starting installation for node: $node_name"
    
    # Rest of the installation steps
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
            
            # Show logs if they exist
            if [ -f "${node_name}/logs/citrea.log" ]; then
                echo -e "\n${YELLOW}=== Last 20 lines of citrea.log ===${NC}"
                tail -n 20 "${node_name}/logs/citrea.log"
            fi
            
            exit 1
        fi
    done
    
    show_node_info
    log_info "Installation completed successfully!"
}

# Rest of the script functions remain the same...

# Handle script interruption
trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
