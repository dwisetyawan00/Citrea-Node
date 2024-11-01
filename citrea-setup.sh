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

# Function to display logo (modified to handle failure gracefully)
display_logo() {
    if ! curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash; then
        print_color "yellow" "Logo display failed, continuing with installation..."
    fi
}

# Clear screen and display header
clear
display_logo
sleep 2

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

# Function to download executable with multiple fallback methods
download_executable() {
    local url="$1"
    local output="$2"
    local methods=(
        "wget --header='Accept: application/octet-stream' -q"
        "curl -L -f"
        "wget --no-check-certificate --header='User-Agent: Mozilla/5.0'"
    )
    
    for method in "${methods[@]}"; do
        print_color "blue" "Trying download method: ${method% *}..."
        if eval "$method \"$url\" -O \"$output\""; then
            chmod +x "$output"
            return 0
        fi
    done
    
    print_color "red" "All download methods failed"
    print_color "yellow" "Please download manually from:"
    print_color "yellow" "https://github.com/chainwayxyz/citrea/releases/tag/v0.5.4"
    return 1
}

# Download Citrea executable
EXECUTABLE_URL="https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64"
OUTPUT_FILE="$HOME/citrea/citrea-binary"  # Changed filename to avoid directory conflict

print_color "blue" "\nDownloading Citrea executable..."
download_executable "$EXECUTABLE_URL" "$OUTPUT_FILE"
check_status "Executable download"

# Verify executable
if [ ! -x "$OUTPUT_FILE" ]; then
    print_color "red" "Executable verification failed"
    exit 1
fi

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

# Get node name with validation
while true; do
    print_color "yellow" "\nEnter your node name (alphanumeric characters only):"
    read -r NODE_NAME
    if [[ "$NODE_NAME" =~ ^[a-zA-Z0-9]+$ ]]; then
        break
    else
        print_color "red" "Invalid node name. Use only letters and numbers."
    fi
done

# Wallet setup with validation
while true; do
    print_color "yellow" "\nDo you want to create a new wallet or import existing one? (new/import)"
    read -r WALLET_CHOICE
    case "$WALLET_CHOICE" in
        new)
            print_color "blue" "\nCreating new wallet..."
            "$OUTPUT_FILE" wallet new
            break
            ;;
        import)
            print_color "yellow" "\nEnter your wallet recovery phrase:"
            read -r RECOVERY_PHRASE
            echo "$RECOVERY_PHRASE" | "$OUTPUT_FILE" wallet import
            break
            ;;
        *)
            print_color "red" "Invalid choice. Please enter 'new' or 'import'"
            ;;
    esac
done

# Create systemd service with proper permissions
print_color "blue" "\nCreating systemd service..."
cat > /etc/systemd/system/citread.service << EOL
[Unit]
Description=Citrea Node
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
ExecStart=$OUTPUT_FILE node start --name $NODE_NAME --genesis-paths $HOME/citrea/genesis.json --rollup-config-path $HOME/citrea/rollup_config.toml
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOL

# Start the service
print_color "blue" "\nStarting Citrea node service..."
systemctl daemon-reload
systemctl enable citread
systemctl start citread
check_status "Service startup"

# Save node information
NODE_INFO="$HOME/citrea/node_info.txt"
cat > "$NODE_INFO" << EOL
Node Information:
Node Name: $NODE_NAME
Service Name: citread
Directory: $HOME/citrea
Executable Path: $OUTPUT_FILE
Version: v0.5.4
Date Installed: $(date)
OS: $NAME $VERSION_ID

Configuration files:
- genesis.json
- rollup_config.toml
EOL

# Final output
print_color "green" "\n=== Installation Complete ==="
print_color "yellow" "Your Citrea node has been installed and started!"
print_color "yellow" "Node information saved to: $NODE_INFO"
print_color "yellow" "\nUseful commands:"
print_color "blue" "Check node status: systemctl status citread"
print_color "blue" "View logs: journalctl -u citread -f"
print_color "blue" "Stop node: systemctl stop citread"
print_color "blue" "Start node: systemctl start citread"
print_color "blue" "Manual node start: $OUTPUT_FILE --genesis-paths $HOME/citrea/genesis.json --rollup-config-path $HOME/citrea/rollup_config.toml"

exit 0
