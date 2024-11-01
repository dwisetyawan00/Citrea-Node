#!/bin/bash

# Function to display the logo
display_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
}

# Function to display colored text
print_color() {
    case $1 in
        "green") COLOR="\033[0;32m" ;;
        "red") COLOR="\033[0;31m" ;;
        "yellow") COLOR="\033[0;33m" ;;
        "blue") COLOR="\033[0;34m" ;;
        "nc") COLOR="\033[0m" ;;
    esac
    echo -e "${COLOR}$2${NC}"
}

# Clear screen and display logo
clear
display_logo
sleep 2

print_color "green" "=== Citrea Testnet Node Installation Script ==="
print_color "yellow" "This script will help you install and configure your Citrea testnet node."

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    print_color "red" "Cannot detect OS version"
    exit 1
fi

# Check if running on Ubuntu/Debian
if [[ "$OS" != *"Ubuntu"* ]] && [[ "$OS" != *"Debian"* ]]; then
    print_color "red" "This script is designed for Ubuntu/Debian systems."
    print_color "red" "Your OS: $OS"
    print_color "red" "Please use Ubuntu 20.04 or higher"
    exit 1
fi

# Update system
print_color "blue" "\nUpdating system packages..."
apt update && apt upgrade -y

# Install dependencies
print_color "blue" "\nInstalling dependencies..."
apt install -y curl build-essential git screen jq pkg-config libssl-dev libclang-dev ca-certificates gnupg lsb-release wget

# Create directory for Citrea
print_color "blue" "\nCreating Citrea directory..."
mkdir -p $HOME/citrea
cd $HOME/citrea

# Download and set up the executable
print_color "blue" "\nDownloading Citrea testnet executable v0.5.4..."
EXECUTABLE_URL="https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-x86_64-linux"

if ! wget -O citrea $EXECUTABLE_URL; then
    print_color "red" "Error downloading executable from $EXECUTABLE_URL"
    print_color "yellow" "Please check the URL or download manually from:"
    print_color "yellow" "https://github.com/chainwayxyz/citrea/releases/tag/v0.5.4"
    exit 1
fi

chmod +x citrea

# Verify executable
if [ -f citrea ] && [ -x citrea ]; then
    print_color "green" "Executable downloaded and set up successfully!"
else
    print_color "red" "Failed to set up executable properly"
    exit 1
fi

# Get user input for node name
print_color "yellow" "\nPlease enter your node name:"
read -p "> " NODE_NAME

# Create or import wallet
print_color "yellow" "\nDo you want to create a new wallet or import existing one? (new/import)"
read -p "> " WALLET_CHOICE

if [ "$WALLET_CHOICE" = "new" ]; then
    print_color "blue" "\nCreating new wallet..."
    ./citrea wallet new
elif [ "$WALLET_CHOICE" = "import" ]; then
    print_color "yellow" "\nPlease enter your wallet recovery phrase:"
    read -p "> " RECOVERY_PHRASE
    echo "$RECOVERY_PHRASE" | ./citrea wallet import
fi

# Create systemd service
print_color "blue" "\nCreating systemd service..."
cat > /etc/systemd/system/citread.service << EOL
[Unit]
Description=Citrea Node
After=network-online.target

[Service]
User=$USER
ExecStart=$HOME/citrea/citrea node start --name $NODE_NAME
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOL

# Start the service
print_color "blue" "\nStarting Citrea node service..."
systemctl daemon-reload
systemctl enable citread
systemctl start citread

# Final instructions
print_color "green" "\n=== Installation Complete ==="
print_color "yellow" "Your Citrea node has been installed and started!"
print_color "yellow" "You can check the node status with: systemctl status citread"
print_color "yellow" "View logs with: journalctl -u citread -f"

# Display node information
print_color "blue" "\nNode Information:"
print_color "green" "Node Name: $NODE_NAME"
print_color "green" "Service Name: citread"
print_color "green" "Directory: $HOME/citrea"
print_color "green" "Version: v0.5.4"

# Save node info to a file
cat > $HOME/citrea/node_info.txt << EOL
Node Information:
Node Name: $NODE_NAME
Service Name: citread
Directory: $HOME/citrea
Version: v0.5.4
Date Installed: $(date)
OS: $OS $VER
EOL

print_color "yellow" "\nNode information has been saved to: $HOME/citrea/node_info.txt"

exit 0
