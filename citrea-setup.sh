#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables for diagnostics
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MAX_RETRIES=5
RETRY_DELAY=5

# Logging functions
log_info() { echo -e "${GREEN}[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" >&2; }

# Show logo
show_logo() {
    curl -s https://raw.githubusercontent.com/dwisetyawan00/dwisetyawan00.github.io/main/logo.sh | bash
    sleep 2
}

# Progress indicators
show_progress() { echo -e "${GREEN}[+] $1${NC}"; }
show_error() { echo -e "${RED}[-] Error: $1${NC}"; }
show_warning() { echo -e "${YELLOW}[!] Warning: $1${NC}"; }

# Setup Citrea with improved error handling and verification
setup_citrea() {
    show_progress "Setting up Citrea..."
    
    # Create and enter directory with error checking
    if [ -d "${node_name}" ]; then
        log_warn "Directory ${node_name} already exists. Cleaning up..."
        rm -rf "${node_name}"
    fi
    
    if ! mkdir -p "${node_name}"; then
        show_error "Failed to create directory: ${node_name}"
        return 1
    fi
    
    if ! cd "${node_name}"; then
        show_error "Failed to enter directory: ${node_name}"
        return 1
    }
    
    # Download files with better error handling
    local files=(
        "https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64"
        "https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml"
        "https://static.testnet.citrea.xyz/genesis.tar.gz"
    )
    
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        show_progress "Downloading ${filename}..."
        
        if ! wget -q --show-progress --tries=3 --timeout=15 "$file"; then
            show_error "Failed to download: ${filename}"
            return 1
        fi
        
        # Verify file was downloaded
        if [ ! -f "$(basename $file)" ]; then
            show_error "File not found after download: ${filename}"
            return 1
        }
    done
    
    # Extract genesis files with verification
    show_progress "Extracting genesis files..."
    if [ ! -f "genesis.tar.gz" ]; then
        show_error "Genesis archive not found"
        return 1
    fi
    
    if ! tar xzf genesis.tar.gz; then
        show_error "Failed to extract genesis archive"
        return 1
    fi
    
    # Verify genesis directory and files
    if [ ! -d "genesis" ] || [ ! -f "genesis/genesis.json" ]; then
        show_error "Genesis directory or files missing after extraction"
        return 1
    }
    
    # Set executable permission
    if ! chmod +x ./citrea-v0.5.4-linux-amd64; then
        show_error "Failed to set executable permission"
        return 1
    }
    
    # Update configuration with verification
    show_progress "Updating configuration..."
    if [ ! -f "rollup_config.toml" ]; then
        show_error "Configuration file not found"
        return 1
    }
    
    # Create backup of original config
    cp rollup_config.toml rollup_config.toml.backup
    
    # Update configuration with error checking
    if ! sed -i "s/rpc_user = .*/rpc_user = \"citrea\"/" rollup_config.toml || \
       ! sed -i "s/rpc_password = .*/rpc_password = \"citrea\"/" rollup_config.toml || \
       ! sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" rollup_config.toml; then
        show_error "Failed to update configuration file"
        # Restore backup
        mv rollup_config.toml.backup rollup_config.toml
        return 1
    fi
    
    # Verify configuration was updated
    if ! grep -q "rpc_user = \"citrea\"" rollup_config.toml || \
       ! grep -q "rpc_password = \"citrea\"" rollup_config.toml || \
       ! grep -q "rpc_port = ${rpc_port}" rollup_config.toml; then
        show_error "Configuration verification failed"
        return 1
    fi
    
    # Remove backup if everything succeeded
    rm -f rollup_config.toml.backup
    
    log_info "Citrea setup completed successfully"
    return 0
}

# Modified start_citrea_node function with better verification
start_citrea_node() {
    show_progress "Starting Citrea node..."
    
    # Verify all required files exist
    local required_files=("citrea-v0.5.4-linux-amd64" "rollup_config.toml" "genesis/genesis.json")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            show_error "Required file not found: $file"
            return 1
        fi
    done
    
    # Verify executable permission
    if [ ! -x "./citrea-v0.5.4-linux-amd64" ]; then
        show_error "Citrea binary is not executable"
        chmod +x ./citrea-v0.5.4-linux-amd64
    fi
    
    # Create log directory if it doesn't exist
    mkdir -p logs
    
    # Start the node with logging
    ./citrea-v0.5.4-linux-amd64 --genesis-paths genesis/genesis.json \
        --config rollup_config.toml > logs/citrea_${TIMESTAMP}.log 2>&1 &
    
    local pid=$!
    log_info "Started Citrea node with PID: $pid"
    
    # Wait for node to initialize
    show_progress "Waiting for node to initialize..."
    sleep 15
    
    # Verify process is still running
    if ! ps -p $pid > /dev/null; then
        show_error "Citrea node failed to start. Check logs/citrea_${TIMESTAMP}.log for details"
        tail -n 20 logs/citrea_${TIMESTAMP}.log
        return 1
    fi
    
    # Save PID for future reference
    echo $pid > citrea.pid
    
    log_info "Citrea node started successfully"
    return 0
}

# Rest of the script remains the same...
# (Keep all other functions unchanged)

main() {
    clear
    show_logo
    
    log_info "Starting Citrea Node Installation"
    
    if ! check_system_requirements; then
        log_error "Insufficient system resources"
        exit 1
    fi
    
    # Get configuration
    echo "=================================="
    echo "   Citrea Node Installation       "
    echo "=================================="
    echo "1. Default Configuration"
    echo "2. Manual Configuration"
    echo "3. Run Diagnostics Only"
    echo "=================================="
    read -p "Choose option (1/2/3): " config_choice
    
    case $config_choice in
        1)
            node_name="citrea-node"
            rpc_port="18443"
            citrea_port="8080"
            ;;
        2)
            get_manual_config
            ;;
        3)
            node_name="citrea-node"
            rpc_port="18443"
            citrea_port="8080"
            run_diagnostics
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Run pre-installation diagnostics
    log_info "Running pre-installation diagnostics..."
    run_diagnostics
    
    read -p "Continue with installation? (y/n): " continue_install
    if [[ $continue_install != "y" ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
    
    # Setup steps with improved error handling
    local setup_steps=(
        "install_missing_deps"
        "check_dependencies"
        "setup_citrea"
        "start_citrea_node"
        "verify_rpc_connection"
    )
    
    for step in "${setup_steps[@]}"; do
        log_info "Executing step: $step"
        if ! $step; then
            log_error "Failed at step: $step"
            log_info "Running post-failure diagnostics..."
            run_diagnostics
            exit 1
        fi
    done
    
    show_node_info
    log_info "Installation completed successfully!"
    
    # Run final health check
    log_info "Running final health check..."
    run_diagnostics
    
    log_warn "Important: Node requires time for full synchronization"
    log_warn "Use the status check command above to monitor progress"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM
    main "$@"
fi
