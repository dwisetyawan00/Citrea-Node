#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables for wallet management
WALLET_DIR="$HOME/.citrea/wallets"
BACKUP_DIR="$HOME/.citrea/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Logging functions
log_info() { echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }

# Setup wallet directories
setup_wallet_directories() {
    if ! mkdir -p "$WALLET_DIR" "$BACKUP_DIR/bitcoin" "$BACKUP_DIR/evm"; then
        log_error "Failed to create wallet directories"
        return 1
    fi
    chmod 700 "$WALLET_DIR" "$BACKUP_DIR"
    return 0
}

# Generate EVM wallet
generate_evm_wallet() {
    log_info "Generating EVM wallet..."
    
    read -p "Enter name for EVM wallet (default: citrea_evm_wallet): " EVM_WALLET_NAME
    EVM_WALLET_NAME=${EVM_WALLET_NAME:-citrea_evm_wallet}
    
    EVM_PRIVKEY=$(openssl rand -hex 32)
    if [[ ! $EVM_PRIVKEY =~ ^[a-f0-9]{64}$ ]]; then
        log_error "Failed to generate valid EVM private key"
        return 1
    fi
    
    local wallet_info_file="$WALLET_DIR/${EVM_WALLET_NAME}_info.txt"
    {
        echo "EVM Wallet"
        echo "Wallet Name: $EVM_WALLET_NAME"
        echo "Private Key: $EVM_PRIVKEY"
        echo "Created: $(date)"
    } > "$wallet_info_file"
    chmod 600 "$wallet_info_file"
    
    log_info "EVM wallet generated successfully"
    echo "$EVM_PRIVKEY"
}

# Generate Bitcoin wallet
generate_bitcoin_wallet() {
    log_info "Generating Bitcoin testnet4 wallet..."
    
    read -p "Enter name for Bitcoin wallet (default: citrea_btc_wallet): " BTC_WALLET_NAME
    BTC_WALLET_NAME=${BTC_WALLET_NAME:-citrea_btc_wallet}
    
    # Generate Bitcoin private key
    local btc_privkey=$(openssl rand -hex 32)
    
    local wallet_info_file="$WALLET_DIR/${BTC_WALLET_NAME}_info.txt"
    {
        echo "Bitcoin Testnet4 Wallet"
        echo "Wallet Name: $BTC_WALLET_NAME"
        echo "Private Key: $btc_privkey"
        echo "Created: $(date)"
    } > "$wallet_info_file"
    chmod 600 "$wallet_info_file"
    
    log_info "Bitcoin wallet generated successfully"
    return 0
}

# Backup wallets
backup_wallets() {
    log_info "Creating wallet backups..."
    
    # Create backup archives
    if [ -d "$WALLET_DIR" ]; then
        tar -czf "$BACKUP_DIR/wallets_backup_${TIMESTAMP}.tar.gz" -C "$WALLET_DIR" .
        
        # Encrypt backup
        read -s -p "Enter password for backup encryption: " BACKUP_PASSWORD
        echo
        read -s -p "Confirm backup password: " BACKUP_PASSWORD_CONFIRM
        echo
        
        if [ "$BACKUP_PASSWORD" = "$BACKUP_PASSWORD_CONFIRM" ]; then
            gpg --batch --yes --passphrase "$BACKUP_PASSWORD" -c "$BACKUP_DIR/wallets_backup_${TIMESTAMP}.tar.gz"
            rm "$BACKUP_DIR/wallets_backup_${TIMESTAMP}.tar.gz"
            log_info "Wallets backed up and encrypted successfully"
        else
            log_error "Passwords do not match"
            return 1
        fi
    else
        log_error "No wallets found to backup"
        return 1
    fi
}

# Main function
main() {
    clear
    echo "=================================="
    echo "    Citrea Wallet Manager         "
    echo "=================================="
    echo "1. Generate EVM Wallet"
    echo "2. Generate Bitcoin Wallet"
    echo "3. Backup All Wallets"
    echo "4. Exit"
    echo "=================================="
    
    read -p "Choose option (1-4): " choice
    
    case $choice in
        1)
            setup_wallet_directories && generate_evm_wallet
            ;;
        2)
            setup_wallet_directories && generate_bitcoin_wallet
            ;;
        3)
            backup_wallets
            ;;
        4)
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM
    main "$@"
fi
