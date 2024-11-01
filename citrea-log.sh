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

show_menu() {
    clear
    print_color "green" "=== Citrea Node Monitoring Tool ==="
    echo "1. Show live logs"
    echo "2. Show last 100 lines of logs"
    echo "3. Show today's logs"
    echo "4. Show node status"
    echo "5. Show node resource usage"
    echo "6. Restart node"
    echo "7. Custom log search"
    echo "8. Exit"
}

while true; do
    show_menu
    read -p "Choose an option (1-8): " choice

    case $choice in
        1)
            print_color "blue" "Showing live logs (Press Ctrl+C to stop)..."
            sleep 1
            journalctl -u citread -f
            ;;
        2)
            print_color "blue" "Showing last 100 lines..."
            journalctl -u citread -n 100
            read -p "Press Enter to continue..."
            ;;
        3)
            print_color "blue" "Showing today's logs..."
            journalctl -u citread --since today
            read -p "Press Enter to continue..."
            ;;
        4)
            print_color "blue" "Checking node status..."
            systemctl status citread
            read -p "Press Enter to continue..."
            ;;
        5)
            print_color "blue" "Checking resource usage..."
            print_color "yellow" "Installing htop if not present..."
            if ! command -v htop &> /dev/null; then
                sudo apt install htop -y
            fi
            htop -p $(pgrep citrea)
            ;;
        6)
            print_color "yellow" "Are you sure you want to restart the node? (y/n)"
            read -p "> " confirm
            if [ "$confirm" = "y" ]; then
                print_color "blue" "Restarting Citrea node..."
                sudo systemctl restart citread
                print_color "green" "Node restarted!"
            fi
            ;;
        7)
            print_color "yellow" "Enter search term:"
            read -p "> " search_term
            print_color "blue" "Searching logs for: $search_term"
            journalctl -u citread | grep -i "$search_term"
            read -p "Press Enter to continue..."
            ;;
        8)
            print_color "green" "Exiting..."
            exit 0
            ;;
        *)
            print_color "red" "Invalid option"
            sleep 1
            ;;
    esac
done
