#!/bin/bash

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_color "red" "Please run as root (use sudo)"
    exit 1
fi

print_color "yellow" "WARNING: This will completely remove Citrea node and all associated data."
print_color "yellow" "Are you sure you want to proceed? (y/n)"
read -p "> " confirm

if [ "$confirm" != "y" ]; then
    print_color "blue" "Uninstall cancelled."
    exit 0
fi

# Stop and disable service
print_color "blue" "Stopping Citrea service..."
systemctl stop citread
systemctl disable citread

# Remove service file
print_color "blue" "Removing service file..."
rm -f /etc/systemd/system/citread.service
systemctl daemon-reload
systemctl reset-failed

# Remove Citrea directory
print_color "blue" "Removing Citrea directory..."
rm -rf $HOME/citrea

# Clean systemd files
print_color "blue" "Cleaning systemd files..."
rm -rf /etc/systemd/system/citread.service.d
rm -rf /etc/systemd/system/citread.service.requires
rm -rf /etc/systemd/system/citread.service.wants

# Optional: Remove logs
print_color "yellow" "Do you want to remove all Citrea logs? (y/n)"
read -p "> " remove_logs
if [ "$remove_logs" = "y" ]; then
    print_color "blue" "Removing logs..."
    journalctl --vacuum-time=1s -u citread
fi

print_color "green" "Citrea node has been completely removed!"
print_color "yellow" "If you want to reinstall, you can use the installation script again."

exit 0
