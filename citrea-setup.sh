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

# Fungsi untuk menampilkan logo
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Fungsi untuk menampilkan progress/error/warning
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

# Fungsi untuk memeriksa dan install dependensi dasar
check_dependencies() {
    show_progress "Memeriksa dependensi dasar..."
    for pkg in curl wget jq; do
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
    show_progress "Setup Bitcoin testnet4 wallet..."
    
    # Input nama wallet
    while true; do
        read -p "Masukkan nama untuk Bitcoin wallet (default: citrea_btc_wallet): " BTC_WALLET_NAME
        BTC_WALLET_NAME=${BTC_WALLET_NAME:-citrea_btc_wallet}
        
        if validate_wallet_name "$BTC_WALLET_NAME"; then
            break
        fi
    done
    
    # Create wallet using curl
    show_progress "Generating Bitcoin wallet: $BTC_WALLET_NAME"
    CREATE_WALLET_RESPONSE=$(curl -s --user citrea:citrea --data-binary "{\"jsonrpc\": \"1.0\", \"id\":\"curltest\", \"method\": \"createwallet\", \"params\": [\"$BTC_WALLET_NAME\"]}" -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    # Verify wallet is loaded
    WALLET_LIST=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listwallets", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    # Get new address
    BTC_ADDRESS_RESPONSE=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getnewaddress", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    BTC_ADDRESS=$(echo $BTC_ADDRESS_RESPONSE | jq -r '.result')
    
    # Get wallet info
    WALLET_INFO=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "getwalletinfo", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    # Get descriptors (including private keys)
    DESCRIPTORS=$(curl -s --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id":"curltest", "method": "listdescriptors", "params": [true]}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port})
    
    # Save wallet info
    echo "Bitcoin Testnet4 Wallet" > "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Wallet Name: $BTC_WALLET_NAME" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Address: $BTC_ADDRESS" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Created: $(date)" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Wallet Info: $WALLET_INFO" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Descriptors: $DESCRIPTORS" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    
    show_progress "Bitcoin wallet generated and saved"
    show_warning "Please fund this address with testnet4 BTC: $BTC_ADDRESS"
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
    
    # Generate EVM wallet (menggunakan openssl untuk generate private key)
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
}

# Fungsi untuk backup wallet
backup_wallets() {
    show_progress "Creating wallet backup..."
    
    # Create backup archive
    BACKUP_FILE="$BACKUP_DIR/wallet_backup_$TIMESTAMP.tar.gz"
    tar -czf "$BACKUP_FILE" -C "$WALLET_DIR" .
    
    # Encrypt backup
    read -s -p "Enter password for backup encryption: " BACKUP_PASSWORD
    echo
    read -s -p "Confirm backup password: " BACKUP_PASSWORD_CONFIRM
    echo
    
    if [ "$BACKUP_PASSWORD" != "$BACKUP_PASSWORD_CONFIRM" ]; then
        show_error "Password tidak cocok"
        backup_wallets
        return
    fi
    
    gpg --batch --yes --passphrase "$BACKUP_PASSWORD" -c "$BACKUP_FILE"
    rm "$BACKUP_FILE"  # Remove unencrypted backup
    
    # Save backup info (tanpa password)
    echo "Backup created: ${BACKUP_FILE}.gpg" > "$BACKUP_DIR/backup_info.txt"
    echo "Timestamp: $TIMESTAMP" >> "$BACKUP_DIR/backup_info.txt"
    echo "Wallets included:" >> "$BACKUP_DIR/backup_info.txt"
    ls -1 "$WALLET_DIR" >> "$BACKUP_DIR/backup_info.txt"
    
    show_progress "Backup created at: ${BACKUP_FILE}.gpg"
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
    
    # 6. Generate wallets after everything is running
    if [[ "${gen_wallets,,}" == "y" ]]; then
        generate_bitcoin_wallet
        generate_evm_wallet
        backup_wallets
    fi
    
    # 7. Show final information
    show_node_info
    show_wallet_info

    show_progress "Instalasi selesai!"
    show_warning "Penting: Node memerlukan waktu untuk sinkronisasi penuh"
    show_warning "Gunakan perintah cek status di atas untuk memantau progress"
}

# Jalankan script
main
