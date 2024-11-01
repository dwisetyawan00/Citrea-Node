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

# Fungsi untuk menampilkan progress/error/warning
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

# Fungsi untuk input manual (hanya yang penting)
get_manual_config() {
    echo "=== Konfigurasi Node ==="
    read -p "Nama Node (default: citrea-node): " node_name
    node_name=${node_name:-citrea-node}
    
    read -p "RPC Port (default: 18443): " rpc_port
    rpc_port=${rpc_port:-18443}
    
    read -p "Citrea Port (default: 8080): " citrea_port
    citrea_port=${citrea_port:-8080}
}

# Fungsi untuk memeriksa dan install dependensi dasar
check_dependencies() {
    show_progress "Memeriksa dependensi dasar..."
    for pkg in curl wget; do
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

    # Verifikasi node
    sleep 10
    show_progress "Verifikasi Bitcoin node..."
    if curl --silent --user citrea:citrea --data-binary '{"jsonrpc": "1.0", "id": "curltest", "method": "getblockcount", "params": []}' -H 'content-type: text/plain;' http://0.0.0.0:${rpc_port} > /dev/null; then
        show_progress "Bitcoin node berhasil dijalankan"
    else
        show_error "Bitcoin node gagal dijalankan"
        docker logs bitcoin-testnet4
        exit 1
    fi
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
    
    show_progress "Menjalankan Citrea node..."
    ./citrea-v0.5.4-linux-amd64 --da-layer bitcoin --rollup-config-path ./rollup_config.toml --genesis-paths ./genesis &
    
    # Verifikasi node
    sleep 10
    if curl -s -X POST --header "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[], "id":31}' http://0.0.0.0:${citrea_port} > /dev/null; then
        show_progress "Citrea node berhasil dijalankan"
    else
        show_error "Citrea node gagal dijalankan. Cek log untuk detail"
        exit 1
    fi
}

# Fungsi untuk menampilkan informasi node
show_node_info() {
    echo -e "\n=== Informasi Node ==="
    echo "Nama Node: ${node_name}"
    echo "Bitcoin RPC: http://0.0.0.0:${rpc_port}"
    echo "Citrea API: http://0.0.0.0:${citrea_port}"
    echo -e "\nUntuk cek sync status:"
    echo "curl -X POST --header \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"citrea_syncStatus\",\"params\":[], \"id\":31}' http://0.0.0.0:${citrea_port}"
}

# Main script
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
run_bitcoin_node
setup_citrea
show_node_info

show_progress "Instalasi selesai!"
show_warning "Penting: Node memerlukan waktu untuk sinkronisasi penuh"
show_warning "Gunakan perintah cek status di atas untuk memantau progress"
