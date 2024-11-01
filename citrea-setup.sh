#!/bin/bash

# Fungsi untuk menampilkan logo
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Fungsi untuk input manual konfigurasi
get_manual_config() {
    echo "=== Konfigurasi Manual ==="
    read -p "RPC User (default: citrea): " rpc_user
    rpc_user=${rpc_user:-citrea}
    
    read -p "RPC Password (default: citrea): " rpc_password
    rpc_password=${rpc_password:-citrea}
    
    read -p "RPC Port (default: 18443): " rpc_port
    rpc_port=${rpc_port:-18443}
    
    read -p "Bitcoin Image Version (default: 28.0rc1): " btc_version
    btc_version=${btc_version:-28.0rc1}
}

# Fungsi untuk instalasi Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        sudo apt update
        sudo apt install -y docker.io docker-compose
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        echo "Docker berhasil diinstall. Mohon logout dan login kembali untuk menggunakan Docker tanpa sudo."
        need_relogin=true
    fi
}

# Fungsi untuk instalasi dengan Docker - Executable
install_docker_executable() {
    echo "Memulai instalasi Docker dengan executable..."
    
    # Install Docker
    install_docker
    
    if [ "$need_relogin" = true ]; then
        echo "Mohon login ulang terlebih dahulu sebelum melanjutkan instalasi"
        exit 0
    fi

    # Setup direktori
    mkdir -p citrea-docker && cd citrea-docker
    
    # Download executable dan config
    wget https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64
    curl https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml --output rollup_config.toml
    
    # Jalankan Bitcoin node
    docker run -d \
    --name bitcoin-testnet4 \
    -p ${rpc_port}:${rpc_port} \
    -p $((rpc_port + 1)):$((rpc_port + 1)) \
    bitcoin/bitcoin:${btc_version} \
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
}

# Fungsi untuk instalasi dengan Docker - Source
install_docker_source() {
    echo "Memulai instalasi Docker dari source..."
    
    # Install Docker
    install_docker
    
    if [ "$need_relogin" = true ]; then
        echo "Mohon login ulang terlebih dahulu sebelum melanjutkan instalasi"
        exit 0
    fi

    # Clone repository
    git clone https://github.com/chainwayxyz/citrea
    cd citrea
    git fetch --tags
    git checkout $(git describe --tags `git rev-list --tags --max-count=1`)
    
    # Build image
    docker build -t citrea .
    
    # Jalankan container
    docker run -d \
    --name citrea \
    -p 8080:8080 \
    citrea
}

# Fungsi untuk instalasi Rust - Executable
install_rust_executable() {
    echo "Memulai instalasi Rust dengan executable..."
    
    # Install Rust
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Setup direktori
    mkdir -p citrea-rust && cd citrea-rust
    
    # Download executable dan config
    wget https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64
    chmod +x citrea-v0.5.4-linux-amd64
    
    # Download config
    curl https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml --output rollup_config.toml
}

# Fungsi untuk instalasi Rust - Source
install_rust_source() {
    echo "Memulai instalasi Rust dari source..."
    
    # Install Rust
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
    fi
    
    # Install dependencies
    sudo apt update
    sudo apt install -y build-essential git curl
    
    # Clone repository
    git clone https://github.com/chainwayxyz/citrea
    cd citrea
    git fetch --tags
    git checkout $(git describe --tags `git rev-list --tags --max-count=1`)
    
    # Build
    make install-dev-tools
    
    echo "Pilih metode build:"
    echo "1. Build tanpa ZK-Proofs"
    echo "2. Build dengan ZK-Proofs (membutuhkan Docker)"
    read -p "Pilihan Anda (1/2): " build_choice
    
    case $build_choice in
        1)
            SKIP_GUEST_BUILD=1 cargo build --release
            ;;
        2)
            REPR_GUEST_BUILD=1 cargo build --release
            ;;
        *)
            echo "Pilihan tidak valid"
            exit 1
            ;;
    esac
}

# Menu utama
clear
show_logo

echo "=================================="
echo "   Citrea Advanced Installation   "
echo "=================================="
echo "Pilih metode instalasi:"
echo "1. Docker"
echo "2. Rust"
echo "3. Keluar"
echo "=================================="
read -p "Pilihan Anda (1/2/3): " install_method

case $install_method in
    1|2)
        echo "Pilih tipe instalasi:"
        echo "1. Dari Executable (Recommended)"
        echo "2. Dari Source Code"
        read -p "Pilihan Anda (1/2): " install_type
        
        echo "Pilih konfigurasi:"
        echo "1. Konfigurasi Default (Recommended)"
        echo "2. Konfigurasi Manual"
        read -p "Pilihan Anda (1/2): " config_type
        
        if [ "$config_type" = "2" ]; then
            get_manual_config
        else
            rpc_user="citrea"
            rpc_password="citrea"
            rpc_port="18443"
            btc_version="28.0rc1"
        fi
        
        if [ "$install_method" = "1" ]; then
            if [ "$install_type" = "1" ]; then
                install_docker_executable
            else
                install_docker_source
            fi
        else
            if [ "$install_type" = "1" ]; then
                install_rust_executable
            else
                install_rust_source
            fi
        fi
        ;;
    3)
        echo "Keluar dari installer"
        exit 0
        ;;
    *)
        echo "Pilihan tidak valid"
        exit 1
        ;;
esac

echo "Instalasi selesai!"
echo "Untuk verifikasi status sync:"
echo "curl -X POST --header \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"citrea_syncStatus\",\"params\":[], \"id\":31}' http://0.0.0.0:8080"
