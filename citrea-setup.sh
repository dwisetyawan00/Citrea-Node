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

# Fungsi untuk menampilkan logo (existing)
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Fungsi existing untuk progress/error/warning
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

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
    
    # Generate wallet menggunakan bitcoin-cli dalam container
    show_progress "Generating Bitcoin wallet: $BTC_WALLET_NAME"
    docker exec bitcoin-testnet4 bitcoin-cli -testnet4 createwallet "$BTC_WALLET_NAME"
    
    # Generate new address
    BTC_ADDRESS=$(docker exec bitcoin-testnet4 bitcoin-cli -testnet4 -rpcwallet="$BTC_WALLET_NAME" getnewaddress)
    BTC_PRIVKEY=$(docker exec bitcoin-testnet4 bitcoin-cli -testnet4 -rpcwallet="$BTC_WALLET_NAME" dumpprivkey "$BTC_ADDRESS")
    
    # Save wallet info
    echo "Bitcoin Testnet4 Wallet" > "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Wallet Name: $BTC_WALLET_NAME" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Address: $BTC_ADDRESS" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Private Key: $BTC_PRIVKEY" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    echo "Created: $(date)" >> "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    
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
    
    # Install ethereum-keygen jika belum ada
    if ! command -v ethereum-keygen &> /dev/null; then
        show_progress "Installing ethereum-keygen..."
        npm install -g ethereum-keygen
    fi
    
    # Generate EVM wallet
    show_progress "Generating EVM wallet: $EVM_WALLET_NAME"
    EVM_KEYS=$(ethereum-keygen)
    EVM_ADDRESS=$(echo "$EVM_KEYS" | grep "Address:" | cut -d' ' -f2)
    EVM_PRIVKEY=$(echo "$EVM_KEYS" | grep "Private key:" | cut -d' ' -f3)
    
    # Save wallet info
    echo "EVM Wallet" > "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    echo "Wallet Name: $EVM_WALLET_NAME" >> "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    echo "Address: $EVM_ADDRESS" >> "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    echo "Private Key: $EVM_PRIVKEY" >> "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    echo "Created: $(date)" >> "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    
    # Update rollup config dengan EVM private key
    sed -i "s/private_key = .*/private_key = \"$EVM_PRIVKEY\"/" rollup_config.toml
    
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

# Fungsi untuk menampilkan wallet info
show_wallet_info() {
    echo -e "\n=== Wallet Information ==="
    if [ -f "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt" ]; then
        echo "Bitcoin Wallet Name: $BTC_WALLET_NAME"
        grep "Address:" "$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    fi
    
    if [ -f "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt" ]; then
        echo -e "\nEVM Wallet Name: $EVM_WALLET_NAME"
        grep "Address:" "$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    fi
    
    echo -e "\nWallet files location: $WALLET_DIR"
    echo "Backup location: $BACKUP_DIR"
}

# Modifikasi fungsi get_manual_config yang existing
get_manual_config() {
    echo "=== Konfigurasi Node ==="
    read -p "Nama Node (default: citrea-node): " node_name
    node_name=${node_name:-citrea-node}
    
    read -p "RPC Port (default: 18443): " rpc_port
    rpc_port=${rpc_port:-18443}
    
    read -p "Citrea Port (default: 8080): " citrea_port
    citrea_port=${citrea_port:-8080}
    
    # Tambahan opsi untuk wallet
    read -p "Generate new wallets? (Y/n): " gen_wallets
    gen_wallets=${gen_wallets:-Y}
}

# Modifikasi main script
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

    # Proses instalasi
    check_dependencies
    install_docker
    setup_wallet_directories
    run_bitcoin_node
    
    if [[ "${gen_wallets,,}" == "y" ]]; then
        generate_bitcoin_wallet
        generate_evm_wallet
        backup_wallets
    fi
    
    setup_citrea
    show_node_info
    show_wallet_info

    show_progress "Instalasi selesai!"
    show_warning "Penting: Node memerlukan waktu untuk sinkronisasi penuh"
    show_warning "Gunakan perintah cek status di atas untuk memantau progress"
}

# Jalankan script
main
