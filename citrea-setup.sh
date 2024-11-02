#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
node_name=""
BITCOIN_RPC_PORT=18443
BITCOIN_P2P_PORT=18444

# Logging functions
log_info() { echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }

# Show logo function
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

# Get node name function
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

# Check Docker installation
check_docker() {
    log_info "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        log_info "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        sudo systemctl enable docker
        sudo systemctl start docker
        rm get-docker.sh
        log_info "Docker installed successfully"
        log_warn "Please log out and log back in for docker group changes to take effect"
        read -p "Press Enter to continue..."
    else
        log_info "Docker is already installed"
    fi
}

# Start Bitcoin Testnet4 node
setup_bitcoin_testnet() {
    log_info "Setting up Bitcoin Testnet4 node..."
    
    if docker ps -a | grep -q "bitcoin-testnet4"; then
        log_info "Bitcoin testnet4 container already exists. Stopping and removing..."
        docker stop bitcoin-testnet4
        docker rm bitcoin-testnet4
    fi
    
    docker run -d \
        --name bitcoin-testnet4 \
        -p ${BITCOIN_RPC_PORT}:18443 \
        -p ${BITCOIN_P2P_PORT}:18444 \
        bitcoin/bitcoin:28.0rc1 \
        -printtoconsole \
        -testnet4=1 \
        -rest \
        -rpcbind=0.0.0.0 \
        -rpcallowip=0.0.0.0/0 \
        -rpcport=18443 \
        -rpcuser=citrea \
        -rpcpassword=citrea \
        -server \
        -txindex=1
        
    log_info "Waiting for Bitcoin node to start..."
    sleep 10
    
    # Verify Bitcoin node
    if ! curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id": "curltest", "method": "getblockcount", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${BITCOIN_RPC_PORT} &> /dev/null; then
        log_error "Failed to connect to Bitcoin node"
        return 1
    fi
    
    log_info "Bitcoin Testnet4 node started successfully"
    return 0
}

# Setup Citrea
setup_citrea() {
    show_progress "Setting up Citrea node..."
    
    # Create directory structure
    mkdir -p "$node_name"
    cd "$node_name" || exit 1
    
    log_info "Downloading Citrea binary..."
    wget -q "https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64" -O citrea
    chmod +x citrea
    
    log_info "Downloading configuration files..."
    wget -q "https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml" -O rollup_config.toml
    
    log_info "Downloading and extracting genesis files..."
    wget -q "https://static.testnet.citrea.xyz/genesis.tar.gz" -O genesis.tar.gz
    tar xf genesis.tar.gz
    rm genesis.tar.gz
    
    # Save node directory path
    pwd > /tmp/citrea_node_path
    
    log_info "Citrea setup completed successfully"
    return 0
}

# Start Citrea node
start_citrea_node() {
    log_info "Starting Citrea node..."
    
    local node_dir=$(cat /tmp/citrea_node_path)
    cd "$node_dir" || exit 1
    
    # Create startup script
    cat > start.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "${SCRIPT_DIR}"

exec 1> >(tee -a citrea.log)
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
./citrea --da-layer bitcoin --rollup-config-path ./rollup_config.toml --genesis-paths ./genesis &
echo $! > citrea.pid

sleep 5
if ! kill -0 $(cat citrea.pid) 2>/dev/null; then
    echo "Process failed to start"
    exit 1
fi

echo "Node started successfully"
EOF
    
    chmod +x start.sh
    
    if ! ./start.sh; then
        log_error "Failed to start node process"
        cat citrea.log
        return 1
    fi
    
    log_info "Citrea node started successfully"
    return 0
}

# Verify node status
verify_node_status() {
    log_info "Verifying node status..."
    
    # Check Bitcoin node
    local bitcoin_status=$(curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id": "curltest", "method": "getblockcount", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${BITCOIN_RPC_PORT} 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "Bitcoin node is not responding"
        return 1
    fi
    
    # Check Citrea node
    local citrea_status=$(curl -s -X POST --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[],"id":31}' http://0.0.0.0:8080 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "Citrea node is not responding"
        return 1
    fi
    
    log_info "Both nodes are running"
    return 0
}

# Show node information
show_node_info() {
    cat << EOF

=== Node Information ===
Bitcoin Testnet4 Node:
  RPC Endpoint: http://localhost:${BITCOIN_RPC_PORT}
  Username: citrea
  Password: citrea

Citrea Node:
  Node Name: ${node_name}
  Directory: $(cat /tmp/citrea_node_path)
  Log File: citrea.log

To check Bitcoin node status:
curl --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id": "curltest", "method": "getblockcount", "params": []}' -H 'content-type: text/plain;' http://localhost:${BITCOIN_RPC_PORT}

To check Citrea node status:
curl -X POST --header "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[],"id":31}' \
    http://localhost:8080
EOF
}

# Cleanup function
cleanup() {
    if [ -f /tmp/citrea_node_path ]; then
        rm /tmp/citrea_node_path
    fi
}

# Main function
main() {
    clear
    show_logo
    get_node_name
    
    log_info "Starting installation for node: $node_name"
    
    local setup_steps=(
        "check_docker"
        "setup_bitcoin_testnet"
        "setup_citrea"
        "start_citrea_node"
        "verify_node_status"
    )
    
    for step in "${setup_steps[@]}"; do
        log_info "Executing step: $step"
        if ! $step; then
            log_error "Failed at step: $step"
            cleanup
            exit 1
        fi
    done
    
    show_node_info
    log_info "Installation completed successfully!"
}

# Handle cleanup on script exit
trap cleanup EXIT

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
