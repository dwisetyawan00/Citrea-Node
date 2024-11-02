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

# Add firewall configuration function
configure_firewall() {
    log_info "Configuring firewall rules..."
    
    if command -v ufw >/dev/null; then
        # Allow required ports
        sudo ufw allow ${rpc_port}/tcp
        sudo ufw allow ${citrea_port}/tcp
        sudo ufw --force enable
        log_info "Firewall rules added for ports ${rpc_port} and ${citrea_port}"
    else
        log_warn "UFW not installed, skipping firewall configuration"
    fi
}

# Enhanced setup_citrea function
setup_citrea() {
    show_progress "Setting up Citrea..."
    
    # Clean up existing installation if present
    if [ -d "${node_name}" ]; then
        log_warn "Existing installation found. Cleaning up..."
        rm -rf "${node_name}"
    fi
    
    # Create and enter installation directory
    if ! mkdir -p "${node_name}"; then
        show_error "Failed to create directory: ${node_name}"
        return 1
    fi
    
    if ! cd "${node_name}"; then
        show_error "Failed to enter directory: ${node_name}"
        return 1
    fi
    
    # Create logs directory
    mkdir -p logs
    
    # Download required files with verbose output
    show_progress "Downloading Citrea files..."
    
    local files=(
        "https://github.com/chainwayxyz/citrea/releases/download/v0.5.4/citrea-v0.5.4-linux-amd64"
        "https://raw.githubusercontent.com/chainwayxyz/citrea/nightly/resources/configs/testnet/rollup_config.toml"
        "https://static.testnet.citrea.xyz/genesis.tar.gz"
    )
    
    for file in "${files[@]}"; do
        local filename=$(basename "$file")
        log_info "Downloading ${filename}..."
        if ! wget --progress=bar:force:noscroll "$file" 2>&1 | grep --line-buffered -oP "...%" | sed -u 's/.*/Downloading: &/'; then
            show_error "Failed to download ${filename}"
            return 1
        fi
        log_info "${filename} downloaded successfully"
    done
    
    # Extract genesis files
    log_info "Extracting genesis files..."
    if ! tar xzf genesis.tar.gz; then
        show_error "Failed to extract genesis files"
        return 1
    fi
    
    # Set correct permissions
    chmod +x ./citrea-v0.5.4-linux-amd64
    
    # Configure rollup_config.toml
    log_info "Configuring rollup_config.toml..."
    if [ ! -f rollup_config.toml ]; then
        show_error "rollup_config.toml not found after download"
        return 1
    fi
    
    # Backup original config
    cp rollup_config.toml rollup_config.toml.backup
    
    # Update configuration
    sed -i "s/rpc_user = .*/rpc_user = \"citrea\"/" rollup_config.toml
    sed -i "s/rpc_password = .*/rpc_password = \"citrea\"/" rollup_config.toml
    sed -i "s/rpc_port = .*/rpc_port = ${rpc_port}/" rollup_config.toml
    sed -i "s/api_port = .*/api_port = ${citrea_port}/" rollup_config.toml
    
    # Verify configuration
    if ! grep -q "rpc_user = \"citrea\"" rollup_config.toml; then
        show_error "Configuration update failed"
        mv rollup_config.toml.backup rollup_config.toml
        return 1
    fi
    
    log_info "Configuration updated successfully"
    return 0
}

# Modified main function to include firewall setup
main() {
    clear
    show_logo
    
    log_info "Starting Citrea Node Installation"
    
    # ... (keep existing configuration options) ...
    
    # Add firewall configuration step
    local setup_steps=(
        "install_missing_deps"
        "check_dependencies"
        "configure_firewall"
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
        
        # Add delay between steps
        sleep 2
    done
    
    # Add post-installation verification
    verify_installation() {
        log_info "Verifying installation..."
        
        # Check if process is running
        if ! pgrep -f "citrea-v0.5.4-linux-amd64" > /dev/null; then
            show_error "Citrea process is not running"
            return 1
        fi
        
        # Check port accessibility
        if ! nc -z localhost ${rpc_port}; then
            show_error "RPC port ${rpc_port} is not accessible"
            return 1
        fi
        
        if ! nc -z localhost ${citrea_port}; then
            show_error "Citrea port ${citrea_port} is not accessible"
            return 1
        fi
        
        log_info "Installation verified successfully"
        return 0
    }
    
    # Run verification
    if ! verify_installation; then
        log_error "Installation verification failed"
        run_diagnostics
        exit 1
    fi
    
    show_node_info
    log_info "Installation completed and verified successfully!"
    
    # Show important information
    cat << EOF

=== Important Information ===
1. Node Name: ${node_name}
2. RPC Endpoint: http://localhost:${rpc_port}
3. API Endpoint: http://localhost:${citrea_port}
4. Log Location: ${node_name}/logs/
5. Config File: ${node_name}/rollup_config.toml

To monitor the node:
curl -X POST --header "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"citrea_syncStatus","params":[], "id":31}' \
    http://localhost:${citrea_port}

Configuration files are located in: $(pwd)/${node_name}
EOF

    log_warn "Important: Node requires time for full synchronization"
    log_warn "Use the status check command above to monitor progress"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'log_error "Script interrupted. Cleaning up..."; exit 1' INT TERM
    main "$@"
fi
