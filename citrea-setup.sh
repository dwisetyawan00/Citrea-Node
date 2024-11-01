#!/bin/bash

# Function to display colored text
print_color() {
    case $1 in
        "green") COLOR="\033[0;32m" ;;
        "red") COLOR="\033[0;31m" ;;
        "yellow") COLOR="\033[0;33m" ;;
        "blue") COLOR="\033[0;34m" ;;
        *) COLOR="\033[0m" ;;
    esac
    NC="\033[0m"  # No Color
    echo -e "${COLOR}$2${NC}"
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        print_color "green" "✓ $1 successful"
    else
        print_color "red" "✗ $1 failed"
        exit 1
    fi
}

# Clear screen and display header
clear
print_color "green" "=== Citrea Testnet Node Installation Script ==="
print_color "yellow" "This script will help you install and configure your Citrea testnet node."

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_color "red" "Please run as root (use sudo)"
    exit 1
fi

# Check OS compatibility
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$NAME" != *"Ubuntu"* ]] && [[ "$NAME" != *"Debian"* ]]; then
        print_color "red" "This script requires Ubuntu/Debian. Your OS: $NAME"
        exit 1
    fi
    if [ "${VERSION_ID%.*}" -lt 20 ]; then
        print_color "red" "This script requires Ubuntu 20.04 or higher"
        exit 1
    fi
else
    print_color "red" "Cannot detect OS version"
    exit 1
fi

# Update system packages
print_color "blue" "\nUpdating system packages..."
apt update && apt upgrade -y
check_status "System update"

# Install dependencies
print_color "blue" "\nInstalling dependencies..."
apt install -y curl build-essential git screen jq pkg-config libssl-dev \
    libclang-dev ca-certificates gnupg lsb-release wget
check_status "Dependencies installation"

# Create and navigate to Citrea directory
print_color "blue" "\nSetting up Citrea directory..."
mkdir -p "$HOME/citrea"
cd "$HOME/citrea" || exit 1
check_status "Directory setup"

# Download Citrea executable
print_color "blue" "\nDownloading Citrea executable..."
wget -O citrea https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64
chmod +x citrea
check_status "Executable download"

# Create configuration files
print_color "blue" "\nCreating configuration files..."

# Create genesis.json
cat > genesis.json << 'EOL'
{
    "chain_id": "11822",
    "initial_timestamp": "2024-01-01T00:00:00Z",
    "initial_state_root": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
EOL

# Create rollup_config.toml
cat > rollup_config.toml << 'EOL'
network = "testnet"
chain_id = 11822
rollup_id = "testnet-rollup"
da_layer = "mock"

[layer1]
rpc_url = "https://testnet-1.citrea.io"
start_block = 0

[da]
rpc_url = "https://testnet-1.citrea.io"
EOL

print_color "blue" "\nTesting node configuration..."
./citrea --help
check_status "Configuration test"

print_color "yellow" "\nNode installation completed! To start your node, use one of these commands:"
print_color "blue" "\nFor full node mode:"
print_color "blue" "  ./citrea --genesis-paths genesis.json --rollup-config-path rollup_config.toml"
print_color "blue" "\nFor testing with mock DA layer:"
print_color "blue" "  ./citrea --genesis-paths genesis.json --da-layer mock --rollup-config-path rollup_config.toml"

print_color "yellow" "\nIMPORTANT NOTES:"
print_color "yellow" "1. This is a testnet installation and configurations may need updates"
print_color "yellow" "2. Monitor the official Citrea documentation for updates: https://github.com/chainwayxyz/citrea"
print_color "yellow" "3. If you encounter errors, check the GitHub issues for solutions"

# Save node information
NODE_INFO="$HOME/citrea/node_info.txt"
cat > "$NODE_INFO" << EOL
Node Information:
Directory: $HOME/citrea
Version: v0.5.4
Date Installed: $(date)
OS: $NAME $VERSION_ID

Configuration files:
- genesis.json
- rollup_config.toml
EOL

print_color "green" "\n=== Installation Complete ==="
print_color "yellow" "Node information saved to: $NODE_INFO"

exit 0
