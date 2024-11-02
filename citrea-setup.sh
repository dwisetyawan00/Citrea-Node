#!/bin/bash

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Tambahan variabel untuk wallet
WALLET_DIR="$HOME/.citrea/wallets"
BACKUP_DIR="$HOME/.citrea/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WALLET_DATA_DIR="$HOME/.bitcoin/testnet4/wallets"

# Fungsi untuk menampilkan logo
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Fungsi untuk menampilkan progress/error/warning
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

derive_bitcoin_key() {
    local evm_privkey=$1
    # Convert EVM private key to a format suitable for Bitcoin
    # Note: Using SHA256 to derive Bitcoin key from EVM key for deterministic generation
    local btc_privkey=$(echo -n "$evm_privkey" | sha256sum | cut -d' ' -f1)
    echo "$btc_privkey"
}

# Fungsi untuk memeriksa dan install dependensi dasar
check_dependencies() {
    show_progress "Memeriksa dependensi dasar..."
    for pkg in curl wget jq gpg tar; do
        if ! command -v $pkg &> /dev/null; then
            show_warning "$pkg tidak ditemukan. Menginstall $pkg..."
            sudo apt update && sudo apt install -y $pkg
        fi
    done
}

# Fungsi untuk instalasi Docker
install_docker() {
    show_progress "Memeriksa Docker..."
    if ! command -v docker &> /dev/null; then
        show_progress "Menginstall Docker..."
        sudo apt update
        sudo apt install -y docker.io docker-compose
        sudo systemctl enable --now docker
        sudo usermod -aG docker $USER
        show_warning "Docker berhasil diinstall. Anda perlu logout dan login kembali."
        show_warning "Jalankan script ini kembali setelah login ulang."
        exit 0
    fi
}

# Fungsi untuk setup direktori wallet
setup_wallet_directories() {
    show_progress "Setting up wallet directories..."
    mkdir -p "$WALLET_DIR"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$WALLET_DIR" "$BACKUP_DIR"
}

ensure_bitcoin_wallet() {
    local wallet_name=$1
    show_progress "Checking Bitcoin wallet: $wallet_name"
    
    # Check if wallet exists in list
    local wallet_list=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listwallets", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    local wallet_exists=$(echo "$wallet_list" | jq -r '.result' | grep -w "$wallet_name" || echo "")
    
    if [ -z "$wallet_exists" ]; then
        show_warning "Wallet $wallet_name tidak ditemukan. Membuat wallet baru..."
        
        # Create new wallet
        local create_response=$(curl -s --user citrea:citrea --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"createwallet\", \"params\": [\"$wallet_name\"]}" -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
        
        if echo "$create_response" | jq -e '.error' > /dev/null; then
            show_error "Gagal membuat wallet: $(echo "$create_response" | jq -r '.error.message')"
            return 1
        fi
    fi
    
    # Load wallet
    local load_response=$(curl -s --user citrea:citrea --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"loadwallet\", \"params\": [\"$wallet_name\"]}" -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    # Check if wallet needs a new address
    local address_list=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getaddressesbylabel", "params": [""]}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    if [ "$(echo "$address_list" | jq '.result | length')" -eq 0 ]; then
        show_progress "Generating new address for wallet $wallet_name"
        local new_address_response=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getnewaddress", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
        
        if echo "$new_address_response" | jq -e '.error' > /dev/null; then
            show_error "Gagal generate address: $(echo "$new_address_response" | jq -r '.error.message')"
            return 1
        fi
        
        local new_address=$(echo "$new_address_response" | jq -r '.result')
        show_progress "New address generated: $new_address"
    fi
    
    return 0
}

# Fungsi untuk validasi nama wallet
validate_wallet_name() {
    local name=$1
    if [[ ! $name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        show_error "Nama wallet hanya boleh mengandung huruf, angka, underscore, dan dash"
        return 1
    fi
    return 0
}

# Fungsi untuk menjalankan Bitcoin node
run_bitcoin_node() {
    show_progress "Menjalankan Bitcoin Testnet4 Node..."
    
    # Hentikan container yang sudah ada
    docker stop bitcoin-testnet4 2>/dev/null
    docker rm bitcoin-testnet4 2>/dev/null
    
    # Jalankan container baru
    docker run -d \
    --name bitcoin-testnet4 \
    --restart unless-stopped \
    -p ${rpc_port}:${rpc_port} \
    -p $((rpc_port + 1)):$((rpc_port + 1)) \
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
    -txindex=1
}

# Fungsi untuk verify Bitcoin node
verify_bitcoin_node() {
    show_progress "Verifying Bitcoin node..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getblockcount", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port} > /dev/null; then
            show_progress "Bitcoin node is running"
            return 0
        fi
        
        show_warning "Waiting for Bitcoin node to start (attempt $attempt/$max_attempts)..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    show_error "Bitcoin node failed to start after $max_attempts attempts"
    return 1
}

# Fungsi untuk setup Citrea
setup_citrea() {
    show_progress "Setting up Citrea..."
    
    # Buat dan masuk ke direktori
    mkdir -p ${node_name} && cd ${node_name}
    
    # Download binary dan file pendukung
    show_progress "Downloading files..."
    wget -q https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64
    curl -s https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml -o rollup_config.toml
    curl -s https://static.testnet.citrea.xyz/genesis.tar.gz -o genesis.tar.gz
    
    # Extract genesis dan set permission
    tar xf genesis.tar.gz
    chmod +x ./citrea-v0.5.4-linux-amd64
    
    # Update config
    sed -i "s/rpc_user = .*/rpc_user = \"citrea\"/" rollup_config.toml
    sed -i "s/rpc_password = .*/rpc_password = \"citrea\"/" rollup_config.toml
    sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" rollup_config.toml
}

# Fungsi untuk generate Bitcoin testnet4 wallet
generate_bitcoin_wallet() {
    local evm_privkey=$1
    show_progress "Setup Bitcoin testnet4 wallet..."
    
    # Input nama wallet
    while true; do
        read -p "Masukkan nama untuk Bitcoin wallet (default: citrea_btc_wallet): " BTC_WALLET_NAME
        BTC_WALLET_NAME=${BTC_WALLET_NAME:-citrea_btc_wallet}
        
        if validate_wallet_name "$BTC_WALLET_NAME"; then
            break
        fi
    done
    
    # Derive Bitcoin private key from EVM private key
    local btc_privkey=$(derive_bitcoin_key "$evm_privkey")
    
    # Import the private key to Bitcoin wallet
    local import_response=$(curl -s --user citrea:citrea --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"importprivkey\", \"params\": [\"$btc_privkey\", \"citrea_derived\", false]}" -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    if echo "$import_response" | jq -e '.error' > /dev/null; then
        show_error "Failed to import Bitcoin private key: $(echo "$import_response" | jq -r '.error.message')"
        return 1
    fi
    
    # Get new address for the imported key
    local address_response=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getnewaddress", "params": ["citrea_derived"]}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    local btc_address=$(echo "$address_response" | jq -r '.result')
    
    if [ -n "$btc_address" ]; then
        # Save wallet info
        echo "Bitcoin Testnet4 Wallet (Derived from EVM)" > "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
        echo "Wallet Name: $BTC_WALLET_NAME" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
        echo "Address: $btc_address" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
        echo "Private Key: $btc_privkey" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
        echo "Derived from EVM Key: $evm_privkey" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
        echo "Created: $(date)" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
        
        show_progress "Bitcoin wallet generated and saved"
        show_warning "Please fund this address with testnet4 BTC: $btc_address"
    else
        show_error "Failed to generate Bitcoin address"
        return 1
    fi
}



# Fungsi untuk generate EVM wallet
generate_evm_wallet() {
    show_progress "Setup EVM wallet..."
    
    # Input nama wallet
    while true; do
        read -p "Masukkan nama untuk EVM wallet (default: citrea_evm_wallet): " EVM_WALLET_NAME
        EVM_WALLET_NAME=${EVM_WALLET_NAME:-citrea_evm_wallet}
        
        if validate_wallet_name "$EVM_WALLET_NAME"; then
            break
        fi
    done
    
    # Generate EVM wallet
    show_progress "Generating EVM wallet: $EVM_WALLET_NAME"
    EVM_PRIVKEY=$(openssl rand -hex 32)
    
    # Save wallet info
    echo "EVM Wallet" > "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    echo "Wallet Name: $EVM_WALLET_NAME" >> "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    echo "Private Key: $EVM_PRIVKEY" >> "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    echo "Created: $(date)" >> "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    
    # Update rollup config dengan EVM private key
    if [ -f "rollup_config.toml" ]; then
        sed -i "s/private_key = .*/private_key = \"$EVM_PRIVKEY\"/" rollup_config.toml
        show_progress "EVM private key updated in rollup config"
    else
        show_warning "rollup_config.toml not found, private key not updated"
    fi
    
    show_progress "EVM wallet generated and saved"
    
    # Return the private key for Bitcoin wallet generation
    echo "$EVM_PRIVKEY"
}

# Fungsi untuk backup wallet Bitcoin
backup_bitcoin_wallet() {
    local wallet_name=$1
    show_progress "Starting Bitcoin wallet backup process..."
    
    # Debug info
    show_progress "Wallet name: $wallet_name"
    show_progress "RPC port: $rpc_port"
    show_progress "Backup directory: $BACKUP_DIR"
    
    # Verifikasi wallet name
    if [ -z "$wallet_name" ]; then
        show_error "Nama wallet kosong"
        return 1
    fi
    
    # Verifikasi node Bitcoin
    show_progress "Verifying Bitcoin node..."
    local node_check=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getblockcount", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    if [ -z "$node_check" ] || echo "$node_check" | jq -e '.error' > /dev/null; then
        show_error "Bitcoin node tidak merespon atau error"
        show_error "Response: $node_check"
        return 1
    fi
    
    # Verifikasi wallet loaded
    show_progress "Verifying wallet is loaded..."
    local wallet_list=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listwallets", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    if ! echo "$wallet_list" | grep -q "$wallet_name"; then
        show_warning "Wallet $wallet_name tidak terdeteksi, mencoba load..."
        curl -s --user citrea:citrea --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"loadwallet\", \"params\": [\"$wallet_name\"]}" -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port}
    fi
    
    # Create backup directory
    show_progress "Creating backup directory..."
    mkdir -p "$BACKUP_DIR/bitcoin/${wallet_name}"
    
    # Dump wallet
    show_progress "Dumping wallet..."
    local dump_file="$BACKUP_DIR/bitcoin/${wallet_name}/wallet_dump_${TIMESTAMP}.txt"
    local dump_response=$(curl -s --user citrea:citrea --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"dumpwallet\", \"params\": [\"$dump_file\"]}" -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    if echo "$dump_response" | jq -e '.error' > /dev/null; then
        show_error "Gagal dump wallet: $(echo "$dump_response" | jq -r '.error.message')"
        show_error "Full response: $dump_response"
        return 1
    fi
    
    # Backup wallet data files
    show_progress "Backing up wallet data files..."
    if [ -d "$WALLET_DATA_DIR/$wallet_name" ]; then
        tar -czf "$BACKUP_DIR/bitcoin/${wallet_name}/wallet_data_${TIMESTAMP}.tar.gz" -C "$WALLET_DATA_DIR" "$wallet_name"
        show_progress "Wallet data files backed up successfully"
    else
        show_warning "Wallet data directory tidak ditemukan: $WALLET_DATA_DIR/$wallet_name"
        show_warning "Mencoba cari di lokasi alternatif..."
        # Coba cari di lokasi lain
        for dir in "$HOME/.bitcoin" "$HOME/.bitcoin/testnet4" "$HOME/.bitcoin/wallets"; do
            if [ -d "$dir/$wallet_name" ]; then
                show_progress "Wallet ditemukan di: $dir/$wallet_name"
                tar -czf "$BACKUP_DIR/bitcoin/${wallet_name}/wallet_data_${TIMESTAMP}.tar.gz" -C "$dir" "$wallet_name"
                show_progress "Wallet data files backed up from alternative location"
                break
            fi
        done
    fi
    
    # Get and save current wallet info
    show_progress "Saving wallet info..."
    local wallet_info=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getwalletinfo", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    echo "$wallet_info" > "$BACKUP_DIR/bitcoin/${wallet_name}/wallet_info_${TIMESTAMP}.json"
    
    # Final verification
    if [ -f "$dump_file" ] || [ -f "$BACKUP_DIR/bitcoin/${wallet_name}/wallet_data_${TIMESTAMP}.tar.gz" ]; then
        show_progress "Bitcoin wallet backup completed successfully"
        return 0
    else
        show_error "Backup files tidak ditemukan setelah proses backup"
        return 1
    fi
}

# Fungsi untuk backup wallet
backup_wallets() {
    show_progress "Creating wallet backup..."
    
    # Create backup directory structure
    mkdir -p "$BACKUP_DIR/bitcoin"
    mkdir -p "$BACKUP_DIR/evm"
    
    # Backup Bitcoin wallet with proper checks
    if [ -n "$BTC_WALLET_NAME" ]; then
        if backup_bitcoin_wallet "$BTC_WALLET_NAME"; then
            show_progress "Bitcoin wallet backup selesai"
        else
            show_error "Gagal backup Bitcoin wallet"
        fi
    fi
    
    # Backup EVM wallet dan info files
    if [ -d "$WALLET_DIR" ]; then
        tar -czf "$BACKUP_DIR/evm/evm_backup_${TIMESTAMP}.tar.gz" -C "$WALLET_DIR" .
        show_progress "EVM wallet backup selesai"
    fi
    
    # Encrypt backups
    read -s -p "Enter password for backup encryption: " BACKUP_PASSWORD
    echo
    read -s -p "Confirm backup password: " BACKUP_PASSWORD_CONFIRM
    echo
    
    if [ "$BACKUP_PASSWORD" != "$BACKUP_PASSWORD_CONFIRM" ]; then
        show_error "Password tidak cocok"
        backup_wallets
        return
    fi
    
    # Encrypt all backup files
    find "$BACKUP_DIR" -type f ! -name "*.gpg" ! -name "backup_info.txt" -exec bash -c '
        gpg --batch --yes --passphrase "$0" -c "{}"
        rm "{}"  # Remove unencrypted file after encryption
    ' "$BACKUP_PASSWORD" \;
    
    # Save backup info
    echo "Backup created at: $TIMESTAMP" > "$BACKUP_DIR/backup_info.txt"
    echo -e "\nBitcoin wallet backup files:" >> "$BACKUP_DIR/backup_info.txt"
    ls -1 "$BACKUP_DIR/bitcoin" 2>/dev/null >> "$BACKUP_DIR/backup_info.txt" || echo "No Bitcoin backups found" >> "$BACKUP_DIR/backup_info.txt"
    echo -e "\nEVM wallet backup files:" >> "$BACKUP_DIR/backup_info.txt"
    ls -1 "$BACKUP_DIR/evm" 2>/dev/null >> "$BACKUP_DIR/backup_info.txt" || echo "No EVM backups found" >> "$BACKUP_DIR/backup_info.txt"
    
    show_progress "All backups created and encrypted in $BACKUP_DIR"
    show_warning "Please store your backup password safely!"
}

# Fungsi untuk menampilkan info node
show_node_info() {
    echo -e "\n=== Informasi Node ==="
    echo "Nama Node: ${node_name}"
    echo "Bitcoin RPC: http://0.0.0.0:${rpc_port}"
    echo "Citrea API: http://0.0.0.0:${citrea_port}"
    echo -e "\nUntuk cek sync status:"
    echo "curl -X POST --header \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"citrea_syncStatus\",\"params\":[], \"id\":31}' http://0.0.0.0:${citrea_port}"
}

# Fungsi untuk menampilkan wallet info
show_wallet_info() {
    echo -e "\n=== Wallet Information ==="
    if [ -f "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt" ]; then
        echo "Bitcoin Wallet Name: $BTC_WALLET_NAME"
        grep "Address:" "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    fi
    
    if [ -f "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt" ]; then
        echo -e "\nEVM Wallet Name: $EVM_WALLET_NAME"
        # Tidak menampilkan private key untuk keamanan
        echo "Private key tersimpan di: $WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    fi
    
    echo -e "\nWallet files location: $WALLET_DIR"
    echo "Backup location: $BACKUP_DIR"
}

# Fungsi untuk input manual
get_manual_config() {
    echo "=== Konfigurasi Node ==="
    read -p "Nama Node (default: citrea-node): " node_name
    node_name=${node_name:-citrea-node}
    
    read -p "RPC Port (default: 18443): " rpc_port
    rpc_port=${rpc_port:-18443}
    
    read -p "Citrea Port (default: 8080): " citrea_port
    citrea_port=${citrea_port:-8080}
    
    read -p "Generate new wallets? (Y/n): " gen_wallets
    gen_wallets=${gen_wallets:-Y}
}

setup_wallets() {
    show_progress "Setting up wallets..."
    
    # 1. Generate EVM wallet terlebih dahulu
    if [[ "${gen_wallets,,}" == "y" ]]; then
        # Generate EVM wallet dan dapatkan private key
        local evm_privkey=$(generate_evm_wallet)
        if [ $? -ne 0 ]; then
            show_error "Gagal generate EVM wallet"
            return 1
        fi
        
        # Gunakan EVM private key untuk generate Bitcoin wallet
        generate_bitcoin_wallet "$evm_privkey"
        if [ $? -ne 0 ]; then
            show_error "Gagal generate Bitcoin wallet"
            return 1
        fi
        
        # Tampilkan report wallet
        show_wallet_report "$evm_privkey"
        
        # Backup wallets
        backup_wallets
    fi
}

# Fungsi untuk menampilkan report wallet yang lebih terstruktur
show_wallet_report() {
    local evm_privkey=$1
    
    echo -e "\n=== Wallet Generation Report ==="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # EVM Wallet Info
    echo -e "\n1. EVM Wallet Details:"
    echo "-------------------------"
    if [ -f "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt" ]; then
        echo "Wallet Name: $EVM_WALLET_NAME"
        echo "Private Key: ${evm_privkey}"
        # Tambahkan informasi address EVM jika tersedia
    fi
    
    # Bitcoin Wallet Info (derived from EVM)
    echo -e "\n2. Bitcoin Wallet Details (Derived from EVM):"
    echo "----------------------------------------"
    if [ -f "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt" ]; then
        echo "Wallet Name: $BTC_WALLET_NAME"
        grep "Address:" "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
        echo "Derived from EVM Private Key: ${evm_privkey}"
    fi
    
    # Storage Information
    echo -e "\n3. Storage Information:"
    echo "----------------------"
    echo "Wallet Directory: $WALLET_DIR"
    echo "Backup Directory: $BACKUP_DIR"
    
    # Important Notes
    echo -e "\n4. Important Notes:"
    echo "-----------------"
    echo "- Keep your EVM private key safe as it's used to derive your Bitcoin wallet"
    echo "- Backup your wallet information regularly"
    echo "- Store backup encryption password in a secure location"
    
    # Save report to file
    local report_file="$WALLET_DIR/wallet_generation_report_${TIMESTAMP}.txt"
    echo "Report saved to: $report_file"
}


# Main script
main() {
    clear
    show_logo

    echo "=================================="
    echo "   Citrea Node Installation       "
    echo "=================================="
    echo "1. Konfigurasi Default"
    echo "2. Konfigurasi Manual"
    echo "=================================="
    read -p "Pilihan (1/2): " config_choice

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
            show_error "Pilihan tidak valid"
            exit 1
            ;;
    esac

    # 1. Install dependencies first
    check_dependencies
    install_docker
    
    # 2. Setup directories
    setup_wallet_directories
    
    # 3. Run Bitcoin node
    run_bitcoin_node
    
    # 4. Verify Bitcoin node is running
    if ! verify_bitcoin_node; then
        show_error "Bitcoin node verification failed. Please check logs and try again."
        exit 1
    fi
    
    # 5. Setup Citrea
setup_citrea

# Generate dan setup wallets (urutan yang benar)
setup_wallets

# Show final information
show_node_info
show_progress "Instalasi selesai!"
show_warning "Penting: Node memerlukan waktu untuk sinkronisasi penuh"
show_warning "Gunakan perintah cek status di atas untuk memantau progress"
}

# Jalankan script
main
