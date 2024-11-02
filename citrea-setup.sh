#!/bin/bash

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Tambahan variabel untuk wallet dan diagnostik
WALLET_DIR="$HOME/.citrea/wallets"
BACKUP_DIR="$HOME/.citrea/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WALLET_DATA_DIR="$HOME/.bitcoin/testnet4/wallets"
MAX_RETRIES=5
RETRY_DELAY=5

# Fungsi logging yang ditingkatkan
log_info() { echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }
log_debug() { 
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Fungsi untuk menampilkan logo
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Fungsi untuk menampilkan progress/error/warning
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

# Fungsi untuk diagnosa sistem
diagnose_system() {
    log_info "Running system diagnostics..."
    
    # Check system resources
    local mem_total=$(free -m | awk '/Mem:/ {print $2}')
    local mem_available=$(free -m | awk '/Mem:/ {print $7}')
    local disk_space=$(df -h / | awk 'NR==2 {print $4}')
    
    log_info "Memory Total: ${mem_total}MB"
    log_info "Memory Available: ${mem_available}MB"
    log_info "Disk Space Available: ${disk_space}"
    
    # Check required ports
    local ports_to_check=("${rpc_port}" "$((rpc_port + 1))" "${citrea_port}")
    for port in "${ports_to_check[@]}"; do
        if lsof -i :"$port" >/dev/null 2>&1; then
            log_warn "Port $port is already in use"
            if ! kill $(lsof -t -i:"$port") 2>/dev/null; then
                log_error "Failed to free port $port"
                return 1
            fi
            log_info "Freed port $port"
        else
            log_info "Port $port is available"
        fi
    done
    
    # Check Docker system
    if command -v docker &> /dev/null; then
        if ! docker info &>/dev/null; then
            log_error "Docker system issues detected"
            if ! systemctl restart docker; then
                log_error "Failed to restart Docker"
                return 1
            fi
            sleep 5
            if ! docker info &>/dev/null; then
                log_error "Docker system still not healthy after restart"
                return 1
            fi
        fi
        log_info "Docker system is healthy"
    fi
    
    return 0
}

# Fungsi untuk memeriksa dan install dependensi dasar
check_dependencies() {
    show_progress "Memeriksa dependensi dasar..."
    local deps=(curl wget jq gpg tar netcat)
    
    for pkg in "${deps[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            show_warning "$pkg tidak ditemukan. Menginstall $pkg..."
            if ! sudo apt-get update && sudo apt-get install -y $pkg; then
                show_error "Gagal menginstall $pkg"
                return 1
            fi
        fi
    done
    return 0
}

check_system_requirements() {
    log_info "Checking system resources..."
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 2 ]; then
        log_error "Minimum 2 CPU cores required. Found: $cpu_cores"
        return 1
    fi
    
    # Check RAM
    local ram_mb=$(free -m | awk '/Mem:/ {print $2}')
    if [ "$ram_mb" -lt 4096 ]; then
        log_error "Minimum 4GB RAM required. Found: $((ram_mb/1024))GB"
        return 1
    fi
    
    # Check disk space
    local disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$disk_gb" -lt 50 ]; then
        log_error "Minimum 50GB free disk space required. Found: ${disk_gb}GB"
        return 1
    fi
    
    log_info "System resources check passed"
    return 0
}

# Fungsi untuk instalasi Docker
install_docker() {
    show_progress "Memeriksa Docker..."
    if ! command -v docker &> /dev/null; then
        show_progress "Menginstall Docker..."
        if ! sudo apt update && sudo apt install -y docker.io docker-compose; then
            show_error "Gagal menginstall Docker"
            return 1
        fi
        
        if ! sudo systemctl enable --now docker; then
            show_error "Gagal mengaktifkan Docker service"
            return 1
        fi
        
        if ! sudo usermod -aG docker $USER; then
            show_error "Gagal menambahkan user ke grup docker"
            return 1
        fi
        
        show_warning "Docker berhasil diinstall. Anda perlu logout dan login kembali."
        show_warning "Jalankan script ini kembali setelah login ulang."
        exit 0
    fi
    return 0
}

# Fungsi untuk verifikasi RPC yang ditingkatkan
verify_rpc_connection() {
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log_debug "RPC connection attempt $attempt of $MAX_RETRIES"
        
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

# Fungsi untuk setup direktori wallet
setup_wallet_directories() {
    show_progress "Setting up wallet directories..."
    if ! mkdir -p "$WALLET_DIR" "$BACKUP_DIR"; then
        show_error "Failed to create wallet directories"
        return 1
    fi
    chmod 700 "$WALLET_DIR" "$BACKUP_DIR"
    return 0
}

# Fungsi untuk menjalankan Bitcoin node dengan health check
run_bitcoin_node() {
    log_info "Starting Bitcoin Testnet4 Node..."
    
    # Stop existing container if running
    docker stop bitcoin-testnet4 2>/dev/null
    docker rm bitcoin-testnet4 2>/dev/null
    
    # Create docker network if it doesn't exist
    if ! docker network inspect citrea-network >/dev/null 2>&1; then
        if ! docker network create citrea-network; then
            log_error "Failed to create Docker network"
            return 1
        fi
    fi
    
    # Run container with health check
    if ! docker run -d \
        --name bitcoin-testnet4 \
        --network citrea-network \
        --restart unless-stopped \
        -p ${rpc_port}:${rpc_port} \
        -p $((rpc_port + 1)):$((rpc_port + 1)) \
        -v $HOME/.bitcoin:/root/.bitcoin \
        --health-cmd='curl -s --user citrea:citrea --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"health\", \"method\": \"getblockcount\", \"params\": []}" -H "content-type: text/plain;" http://localhost:'${rpc_port} \
        --health-interval=10s \
        --health-timeout=5s \
        --health-retries=5 \
        --health-start-period=30s \
        bitcoin/bitcoin:28.0rc1 \
        -printtoconsole \
        -testnet4=1 \
        -rest \
        -rpcbind=0.0.0.0 \
        -rpcallowip=0.0.0.0/0 \
        -rpcport=${rpc_port} \
        -rpcuser=citrea \
        -rpcpassword=citrea \
        -server \
        -txindex=1; then
        log_error "Failed to start Bitcoin container"
        return 1
    fi
    
    # Wait for container to be healthy with extended timeout
    local max_wait=180  # Increased from 60 to 180 seconds
    local wait_time=0
    while [ $wait_time -lt $max_wait ]; do
        local container_status=$(docker inspect -f '{{.State.Status}}' bitcoin-testnet4 2>/dev/null)
        local health_status=$(docker inspect -f '{{.State.Health.Status}}' bitcoin-testnet4 2>/dev/null)
        
        if [ "$container_status" = "running" ]; then
            if [ "$health_status" = "healthy" ]; then
                log_info "Bitcoin node is healthy"
                return 0
            elif [ "$health_status" = "starting" ]; then
                log_info "Bitcoin node is starting..."
            else
                log_warn "Health status: $health_status"
            fi
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        log_debug "Waiting for Bitcoin node to be healthy... ${wait_time}s/${max_wait}s"
        
        # Show logs if taking too long
        if [ $((wait_time % 30)) -eq 0 ]; then
            log_info "Recent container logs:"
            docker logs --tail 5 bitcoin-testnet4
        fi
    done
    
    # If we get here, show the logs and return error
    log_error "Bitcoin node failed to become healthy within ${max_wait} seconds"
    log_error "Container logs:"
    docker logs --tail 20 bitcoin-testnet4
    return 1
}

# Fungsi untuk setup Citrea
setup_citrea() {
    show_progress "Setting up Citrea..."
    
    # Create and enter directory
    if ! mkdir -p "${node_name}" || ! cd "${node_name}"; then
        show_error "Failed to setup Citrea directory"
        return 1
    fi
    
    # Download and verify files
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
    
    # Extract and setup files
    if ! tar xf genesis.tar.gz || ! chmod +x ./citrea-v0.5.4-linux-amd64; then
        show_error "Failed to setup Citrea files"
        return 1
    fi
    
    # Update config
    if ! sed -i "s/rpc_user = .*/rpc_user = \"citrea\"/" rollup_config.toml || \
       ! sed -i "s/rpc_password = .*/rpc_password = \"citrea\"/" rollup_config.toml || \
       ! sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" rollup_config.toml; then
        show_error "Failed to update rollup config"
        return 1
    fi
    
    return 0
}

derive_bitcoin_key() {
    local evm_privkey=$1
    local btc_privkey=$(echo -n "$evm_privkey" | sha256sum | cut -d' ' -f1)
    echo "$btc_privkey"
}

# Generate Bitcoin wallet dengan error handling yang ditingkatkan
generate_bitcoin_wallet() {
    local evm_privkey=$1
    show_progress "Setup Bitcoin testnet4 wallet..."
    
    # Input validation for wallet name
    while true; do
        read -p "Masukkan nama untuk Bitcoin wallet (default: citrea_btc_wallet): " BTC_WALLET_NAME
        BTC_WALLET_NAME=${BTC_WALLET_NAME:-citrea_btc_wallet}
        
        if [[ $BTC_WALLET_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            show_error "Invalid wallet name. Use only letters, numbers, underscore, and dash."
        fi
    done
    
    # Wait for Bitcoin node to be ready
    local retry=0
    while ! verify_rpc_connection && [ $retry -lt $MAX_RETRIES ]; do
        log_warn "Waiting for Bitcoin node to be ready (attempt $((retry + 1))/$MAX_RETRIES)..."
        sleep $RETRY_DELAY
        retry=$((retry + 1))
    done
    
    if [ $retry -eq $MAX_RETRIES ]; then
        show_error "Bitcoin node not ready after $MAX_RETRIES attempts"
        return 1
    fi
    
    # Unload wallet if already loaded
    local wallet_list=$(curl -s --user citrea:citrea \
        --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listwallets", "params": []}' \
        -H 'content-type: text/plain;' \
        http://0.0.0.0:${rpc_port})
    
    if echo "$wallet_list" | grep -q "\"$BTC_WALLET_NAME\""; then
        curl -s --user citrea:citrea \
            --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"unloadwallet\", \"params\": [\"$BTC_WALLET_NAME\"]}" \
            -H 'content-type: text/plain;' \
            http://0.0.0.0:${rpc_port}
        sleep 2
    fi
    
    # Create and load wallet
    local create_response=$(curl -s --user citrea:citrea \
        --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"createwallet\", \"params\": [\"$BTC_WALLET_NAME\"]}" \
        -H 'content-type: text/plain;' \
        http://0.0.0.0:${rpc_port})
    
    if [[ $(echo "$create_response" | jq -r '.error // empty') != "" ]]; then
        if ! echo "$create_response" | grep -q "Database already exists"; then
            show_error "Failed to create Bitcoin wallet: $(echo "$create_response" | jq -r '.error.message')"
            return 1
        fi
    fi
    
    # Load wallet
    local load_response=$(curl -s --user citrea:citrea \
        --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"loadwallet\", \"params\": [\"$BTC_WALLET_NAME\"]}" \
        -H 'content-type: text/plain;' \
        http://0.0.0.0:${rpc_port})
    
    if [[ $(echo "$load_response" | jq -r '.error // empty') != "" ]]; then
        show_error "Failed to load Bitcoin wallet: $(echo "$load_response" | jq -r '.error.message')"
        return 1
    fi
    
    # Generate new address with retries
    local address_response=""
    local retry=0
    while [ $retry -lt $MAX_RETRIES ]; do
        address_response=$(curl -s --user citrea:citrea \
            --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getnewaddress", "params": ["citrea_derived"]}' \
            -H 'content-type: text/plain;' \
            http://0.0.0.0:${rpc_port})
        
        local btc_address=$(echo "$address_response" | jq -r '.result')
        if [ -n "$btc_address" ] && [ "$btc_address" != "null" ]; then
            break
        fi
        
        log_warn "Failed to generate address, retrying..."
        sleep $RETRY_DELAY
        retry=$((retry + 1))
    done
    
    if [ $retry -eq $MAX_RETRIES ]; then
        show_error "Failed to generate Bitcoin address after $MAX_RETRIES attempts"
        return 1
    fi
    
    local btc_address=$(echo "$address_response" | jq -r '.result')
    
    # Create wallet info file with proper permissions
    local wallet_info_file="$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    {
        echo "Bitcoin Testnet4 Wallet"
        echo "Wallet Name: $BTC_WALLET_NAME"
        echo "Address: $btc_address"
        echo "Created: $(date)"
        echo "Derived from EVM Private Key: $evm_privkey"
        echo -e "\nBackup Locations:"
        echo "Wallet Backups: $BACKUP_DIR/bitcoin/${BTC_WALLET_NAME}"
        echo "Encrypted Backups: $BACKUP_DIR/bitcoin/${BTC_WALLET_NAME}/*.gpg"
    } > "$wallet_info_file"
    
    chmod 600 "$wallet_info_file"
    
    show_progress "Bitcoin wallet setup completed successfully"
    show_warning "Please fund this address with testnet4 BTC: $btc_address"
    show_warning "Wallet information saved to: $wallet_info_file"
    
    return 0
}

# Generate EVM wallet dengan error handling yang ditingkatkan
generate_evm_wallet() {
    show_progress "Setup EVM wallet..."
    
    while true; do
        read -p "Masukkan nama untuk EVM wallet (default: citrea_evm_wallet): " EVM_WALLET_NAME
        EVM_WALLET_NAME=${EVM_WALLET_NAME:-citrea_evm_wallet}
        
        if [[ $EVM_WALLET_NAME =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            show_error "Invalid wallet name. Use only letters, numbers, underscore, and dash."
        fi
    done
    
    # Generate EVM private key with verification
    local attempts=0
    while [ $attempts -lt 3 ]; do
        EVM_PRIVKEY=$(openssl rand -hex 32)
        if [[ $EVM_PRIVKEY =~ ^[a-f0-9]{64}$ ]]; then
            break
        fi
        attempts=$((attempts + 1))
    done
    
    if [[ ! $EVM_PRIVKEY =~ ^[a-f0-9]{64}$ ]]; then
        show_error "Failed to generate valid EVM private key"
        return 1
    fi
    
    # Save wallet info with proper permissions
    local wallet_info_file="$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    {
        echo "EVM Wallet"
        echo "Wallet Name: $EVM_WALLET_NAME"
        echo "Private Key: $EVM_PRIVKEY"
        echo "Created: $(date)"
    } > "$wallet_info_file"
    
    chmod 600 "$wallet_info_file"
    
    # Update rollup config
    if [ -f "rollup_config.toml" ]; then
        if ! sed -i "s/private_key = .*/private_key = \"$EVM_PRIVKEY\"/" rollup_config.toml; then
            show_warning "Failed to update rollup config with EVM private key"
        else
            log_info "Updated rollup config with EVM private key"
        fi
    fi
    
    show_progress "EVM wallet generated successfully"
    echo "$EVM_PRIVKEY"
}

backup_bitcoin_wallet() {
    local wallet_name=$1
    show_progress "Starting Bitcoin wallet backup process..."
    
    # Verify Bitcoin daemon connection
    if ! verify_rpc_connection; then
        show_error "Cannot connect to Bitcoin daemon"
        return 1
    fi
    
    # Create backup directories
    local wallet_backup_dir="$BACKUP_DIR/bitcoin/${wallet_name}"
    mkdir -p "$wallet_backup_dir"
    
    # Verify wallet exists and is loaded
    local wallet_list=$(curl -s --user citrea:citrea \
        --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listwallets", "params": []}' \
        -H 'content-type: text/plain;' \
        http://0.0.0.0:${rpc_port})
    
    if ! echo "$wallet_list" | grep -q "\"$wallet_name\""; then
        show_warning "Attempting to load wallet..."
        curl -s --user citrea:citrea \
            --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"loadwallet\", \"params\": [\"$wallet_name\"]}" \
            -H 'content-type: text/plain;' \
            http://0.0.0.0:${rpc_port}
        sleep 2
    fi
    
    # Backup wallet info
    local wallet_info=$(curl -s --user citrea:citrea \
        --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getwalletinfo", "params": []}' \
        -H 'content-type: text/plain;' \
        http://0.0.0.0:${rpc_port})
    
    if [ -n "$wallet_info" ]; then
        echo "$wallet_info" > "$wallet_backup_dir/wallet_info_${TIMESTAMP}.json"
    else
        show_error "Failed to get wallet info"
        return 1
    fi
    
    # Backup addresses
    local address_info=$(curl -s --user citrea:citrea \
        --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listaddressgroupings", "params": []}' \
        -H 'content-type: text/plain;' \
        http://0.0.0.0:${rpc_port})
    
    if [ -n "$address_info" ]; then
        echo "$address_info" > "$wallet_backup_dir/addresses_${TIMESTAMP}.json"
    else
        show_error "Failed to get address info"
        return 1
    fi
    
    # Backup wallet files
    if [ -d "$WALLET_DATA_DIR/$wallet_name" ]; then
        if ! tar -czf "$wallet_backup_dir/wallet_data_${TIMESTAMP}.tar.gz" -C "$WALLET_DATA_DIR" "$wallet_name"; then
            show_error "Failed to backup wallet data files"
            return 1
        fi
    else
        show_warning "Wallet data directory not found at $WALLET_DATA_DIR/$wallet_name"
    fi
    
    # Verify backup files exist
    if [ ! -f "$wallet_backup_dir/wallet_info_${TIMESTAMP}.json" ] || \
       [ ! -f "$wallet_backup_dir/addresses_${TIMESTAMP}.json" ]; then
        show_error "Backup verification failed"
        return 1
    fi
    
    show_progress "Bitcoin wallet backup completed successfully"
    show_progress "Backup location: $wallet_backup_dir"
    return 0
}

# Function to backup wallets dengan error handling yang ditingkatkan
backup_wallets() {
    show_progress "Creating wallet backup..."
    
    # Create backup directory structure
    mkdir -p "$BACKUP_DIR/bitcoin" "$BACKUP_DIR/evm"
    
    # Verify Bitcoin node is running before backup
    if ! verify_rpc_connection; then
        show_error "Bitcoin node not accessible for backup"
        return 1
    fi
    
    # Backup Bitcoin wallet if exists
    if [ -n "$BTC_WALLET_NAME" ]; then
        if backup_bitcoin_wallet "$BTC_WALLET_NAME"; then
            show_progress "Bitcoin wallet backup completed"
        else
            show_error "Failed to backup Bitcoin wallet"
            return 1
        fi
    fi
    
    # Backup EVM wallet and info files
    if [ -d "$WALLET_DIR" ]; then
        if ! tar -czf "$BACKUP_DIR/evm/evm_backup_${TIMESTAMP}.tar.gz" -C "$WALLET_DIR" .; then
            show_error "Failed to backup EVM wallet"
            return 1
        fi
        show_progress "EVM wallet backup completed"
    fi
    
    # Encrypt backups with password verification
    local password_verified=false
    while [ "$password_verified" = false ]; do
        read -s -p "Enter password for backup encryption: " BACKUP_PASSWORD
        echo
        read -s -p "Confirm backup password: " BACKUP_PASSWORD_CONFIRM
        echo
        
        if [ "$BACKUP_PASSWORD" = "$BACKUP_PASSWORD_CONFIRM" ]; then
            password_verified=true
        else
            show_error "Passwords do not match. Please try again."
        fi
    done
    
    # Encrypt all backup files with error checking
    find "$BACKUP_DIR" -type f ! -name "*.gpg" ! -name "backup_info.txt" -print0 | while IFS= read -r -d '' file; do
        if ! gpg --batch --yes --passphrase "$BACKUP_PASSWORD" -c "$file"; then
            show_error "Failed to encrypt backup file: $file"
            continue
        fi
        rm "$file"
    done
    
    # Create backup info file
    {
        echo "Backup created at: $TIMESTAMP"
        echo -e "\nBitcoin wallet backup files:"
        ls -1 "$BACKUP_DIR/bitcoin" 2>/dev/null || echo "No Bitcoin backups found"
        echo -e "\nEVM wallet backup files:"
        ls -1 "$BACKUP_DIR/evm" 2>/dev/null || echo "No EVM backups found"
    } > "$BACKUP_DIR/backup_info.txt"
    
    show_progress "All backups created and encrypted in $BACKUP_DIR"
    show_warning "Please store your backup password safely!"
    return 0
}

# Setup wallets function with improved error handling
setup_wallets() {
    show_progress "Setting up wallets..."
    
    if [[ "${gen_wallets,,}" == "y" ]]; then
        # Generate EVM wallet first
        local evm_privkey=$(generate_evm_wallet)
        if [ $? -ne 0 ] || [ -z "$evm_privkey" ]; then
            show_error "Failed to generate EVM wallet"
            return 1
        fi
        
        # Generate Bitcoin wallet using EVM private key
        if ! generate_bitcoin_wallet "$evm_privkey"; then
            show_error "Failed to generate Bitcoin wallet"
            return 1
        fi
        
        # Create backup with retries
        local backup_attempts=0
        while [ $backup_attempts -lt 3 ]; do
            if backup_wallets; then
                break
            fi
            backup_attempts=$((backup_attempts + 1))
            if [ $backup_attempts -lt 3 ]; then
                show_warning "Backup attempt $backup_attempts failed, retrying..."
                sleep 5
            fi
        done
        
        if [ $backup_attempts -eq 3 ]; then
            show_error "Failed to create wallet backups after 3 attempts"
            return 1
        fi
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
    
    read -p "Generate new wallets? (Y/n): " gen_wallets
    gen_wallets=${gen_wallets:-Y}
}

show_node_info() {
    echo -e "\n=== Node Information ==="
    echo "Node Name: ${node_name}"
    echo "Bitcoin RPC: http://0.0.0.0:${rpc_port}"
    echo "Citrea API: http://0.0.0.0:${citrea_port}"
    echo -e "\nTo check sync status:"
    echo "curl -X POST --header \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"citrea_syncStatus\",\"params\":[], \"id\":31}' http://0.0.0.0:${citrea_port}"
}

# Main script with enhanced error handling
main() {
    clear
    show_logo
    
    log_info "Starting Citrea Node Installation"
    
    # Taruh disini - setelah show_logo dan sebelum menu konfigurasi
    if ! diagnose_system; then
        log_error "System diagnostics failed. Please resolve issues before continuing."
        exit 1
    fi

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
            gen_wallets="Y"
            ;;
        2)
            get_manual_config
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Setup with comprehensive error handling
    local setup_steps=(
        "check_dependencies"
        "install_docker"
        "setup_wallet_directories"
        "run_bitcoin_node"
        "verify_rpc_connection"
        "setup_citrea"
        "setup_wallets"
    )
    
    for step in "${setup_steps[@]}"; do
        log_info "Executing step: $step"
        if ! $step; then
            log_error "Failed at step: $step"
            exit 1
        fi
    done
    
    # Show final information
    show_node_info
    log_info "Installation completed successfully!"
    log_warn "Important: Node requires time for full synchronization"
    log_warn "Use the status check command above to monitor progress"
}

# Run script with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM
    main "$@"
fi
