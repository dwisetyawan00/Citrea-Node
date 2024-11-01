#!/bin/bash

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fungsi untuk menampilkan logo
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Fungsi untuk menampilkan progress
show_progress() {
    echo -e "${GREEN}[+] $1${NC}"
}

# Fungsi untuk menampilkan error
show_error() {
    echo -e "${RED}[-] Error: $1${NC}"
}

# Fungsi untuk menampilkan warning
show_warning() {
    echo -e "${YELLOW}[!] Warning: $1${NC}"
}

# Fungsi untuk input manual konfigurasi
get_manual_config() {
    echo "=== Konfigurasi Manual ==="
    read -p "Nama Node (default: citrea-node): " node_name
    node_name=${node_name:-citrea-node}
    
    read -p "RPC User (default: citrea): " rpc_user
    rpc_user=${rpc_user:-citrea}
    
    read -p "RPC Password (default: citrea): " rpc_password
    rpc_password=${rpc_password:-citrea}
    
    read -p "RPC Port (default: 18443): " rpc_port
    rpc_port=${rpc_port:-18443}
    
    read -p "Citrea Port (default: 8080): " citrea_port
    citrea_port=${citrea_port:-8080}
}

# Fungsi untuk memeriksa dependensi
check_dependencies() {
    show_progress "Memeriksa dependensi..."
    
    # Install curl jika belum ada
    if ! command -v curl &> /dev/null; then
        show_warning "curl tidak ditemukan. Menginstall curl..."
        sudo apt update
        sudo apt install -y curl
    fi

    # Install wget jika belum ada
    if ! command -v wget &> /dev/null; then
        show_warning "wget tidak ditemukan. Menginstall wget..."
        sudo apt update
        sudo apt install -y wget
    fi
}

# Fungsi untuk instalasi Docker
install_docker() {
    show_progress "Memeriksa instalasi Docker..."
    
    if ! command -v docker &> /dev/null; then
        show_progress "Menginstall Docker..."
        sudo apt update
        sudo apt install -y docker.io docker-compose
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        show_warning "Docker berhasil diinstall. Anda perlu logout dan login kembali."
        show_warning "Script akan keluar. Jalankan kembali setelah login ulang."
        exit 0
    fi
}

# Fungsi untuk menjalankan Bitcoin node
run_bitcoin_node() {
    show_progress "Menjalankan Bitcoin Testnet4 Node..."
    
    # Hentikan container yang sudah ada jika ada
    docker stop bitcoin-testnet4 2>/dev/null
    docker rm bitcoin-testnet4 2>/dev/null
    
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
    -rpcuser=${rpc_user} \
    -rpcpassword=${rpc_password} \
    -server \
    -txindex=1
    
    # Tunggu node startup
    show_progress "Menunggu Bitcoin node startup..."
    sleep 10
    
    # Verifikasi node
    show_progress "Verifikasi Bitcoin node..."
    if curl --silent --user ${rpc_user}:${rpc_password} --data-binary '{"jsonrpc": "1.0", "id": "curltest", "method": "getblockcount", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port} > /dev/null; then
        show_progress "Bitcoin node berhasil dijalankan"
    else
        show_error "Bitcoin node gagal dijalankan"
        exit 1
    fi
}

# Fungsi untuk setup dan menjalankan Citrea
setup_citrea() {
    show_progress "Setting up Citrea..."
    
    # Buat direktori
    mkdir -p ${node_name} && cd ${node_name}
    
    # Download binary
    show_progress "Downloading Citrea binary..."
    wget https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64
    
    # Download config
    show_progress "Downloading config files..."
    curl https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml --output rollup_config.toml
    
    # Download & extract genesis
    show_progress "Downloading dan extracting genesis files..."
    curl https://static.testnet.citrea.xyz/genesis.tar.gz --output genesis.tar.gz
    tar -xzvf genesis.tar.gz
    
    # Set permission
    chmod u+x ./citrea-v0.5.4-linux-amd64
    
    # Backup config file
    cp rollup_config.toml rollup_config.toml.backup
    
    # Update config dengan nilai-nilai custom
    sed -i "s/rpc_user = .*/rpc_user = \"${rpc_user}\"/" rollup_config.toml
    sed -i "s/rpc_password = .*/rpc_password = \"${rpc_password}\"/" rollup_config.toml
    sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" rollup_config.toml
    
    show_progress "Menjalankan Citrea node..."
    ./citrea-v0.5.4-linux-amd64 --da-layer bitcoin --rollup-config-path ./rollup_config.toml --genesis-paths ./genesis &
    
    # Tunggu node startup
    sleep 10
    
    # Verifikasi Citrea node
    show_progress "Verifikasi Citrea node..."
    if curl -s -X POST --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[], "id":31}' http://0.0.0.0:${citrea_port} > /dev/null; then
        show_progress "Citrea node berhasil dijalankan"
    else
        show_error "Citrea node gagal dijalankan"
        exit 1
    fi
}

# Fungsi untuk menampilkan informasi node
show_node_info() {
    echo ""
    echo "=== Informasi Node ==="
    echo "Nama Node: ${node_name}"
    echo "Bitcoin RPC: http://0.0.0.0:${rpc_port}"
    echo "Citrea API: http://0.0.0.0:${citrea_port}"
    echo ""
    echo "Untuk cek status Bitcoin node:"
    echo "curl --user ${rpc_user}:${rpc_password} --data-binary '{\"jsonrpc\": \"1.0\", \"id\": \"curltest\", \"method\": \"getblockcount\", \"params\": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port}"
    echo ""
    echo "Untuk cek status Citrea sync:"
    echo "curl -X POST --header \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"citrea_syncStatus\",\"params\":[], \"id\":31}' http://0.0.0.0:${citrea_port}"
}

# Main script
clear
show_logo

echo "=================================="
echo "   Citrea Complete Installation   "
echo "=================================="
echo "Pilih konfigurasi:"
echo "1. Konfigurasi Default (Recommended)"
echo "2. Konfigurasi Manual"
echo "=================================="
read -p "Pilihan Anda (1/2): " config_choice

case $config_choice in
    1)
        node_name="citrea-node"
        rpc_user="citrea"
        rpc_password="citrea"
        rpc_port="18443"
        citrea_port="8080"
        ;;
    2)
        get_manual_config
        ;;
    *)
        show_error "Pilihan tidak valid"
        exit 1
        ;;
esac

# Mulai instalasi
check_dependencies
install_docker
run_bitcoin_node
setup_citrea
show_node_info

show_progress "Instalasi selesai!"
