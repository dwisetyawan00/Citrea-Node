#!/bin/bash

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Fungsi untuk konfirmasi
confirm() {
    read -p "Apakah Anda yakin ingin menghapus semua data Citrea? (y/n): " choice
    case "$choice" in 
        y|Y ) return 0;;
        * ) return 1;;
    esac
}

# Fungsi untuk membersihkan Citrea
cleanup_citrea() {
    show_progress "Memulai proses pembersihan Citrea..."

    # Menghentikan proses Citrea yang sedang berjalan
    show_progress "Menghentikan proses Citrea..."
    pkill -f citrea-v0.5.4-linux-amd64 || true

    # Menghapus direktori Citrea
    if [ -d "citrea-node" ]; then
        show_progress "Menghapus direktori citrea-node..."
        rm -rf citrea-node
    fi

    # Menghentikan dan menghapus container Bitcoin
    show_progress "Membersihkan container Docker..."
    if docker ps -a | grep -q "bitcoin-testnet4"; then
        docker stop bitcoin-testnet4
        docker rm bitcoin-testnet4
    fi

    # Menghapus image Bitcoin jika ada
    show_progress "Membersihkan Docker images..."
    if docker images | grep -q "bitcoin/bitcoin"; then
        docker rmi bitcoin/bitcoin:28.0rc1
    fi

    # Hapus data Docker volume jika ada
    show_progress "Membersihkan Docker volumes..."
    docker volume prune -f

    show_progress "Pembersihan selesai!"
}

# Main script
clear
echo "=================================="
echo "     Citrea Cleanup Utility       "
echo "=================================="
echo "Script ini akan menghapus:"
echo "1. Citrea node dan semua filenya"
echo "2. Bitcoin testnet4 container"
echo "3. Bitcoin Docker image"
echo "4. Docker volumes yang tidak terpakai"
echo "=================================="

if confirm; then
    cleanup_citrea
else
    show_warning "Pembersihan dibatalkan"
    exit 0
fi
