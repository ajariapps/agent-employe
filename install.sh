#!/bin/bash
# Universal One-Line Installer for Employee Monitoring Agent (Rust)
# Supported platforms: Linux, macOS (x86_64, ARM64)
#
# Usage:
#   Method 1 (Argument):    curl -sSL https://.../install.sh | sudo bash -s http://server:8080
#   Method 2 (Environment): AGENT_SERVER_URL=http://server:8080 curl -sSL https://.../install.sh | sudo bash
#   Method 3 (Interactive): curl -sSL https://.../install.sh | sudo bash
#
# Environment Variables:
#   AGENT_SERVER_URL    - Server URL (overrides prompt)
#   AGENT_INSTALL_DIR   - Installation directory (default: /usr/local/bin)
#   GITHUB_TOKEN        - GitHub token for private repos (optional)

set -e

#######################################
# Configuration
#######################################
GITHUB_REPO="ajariapps/agent-employe"
INSTALL_DIR="${AGENT_INSTALL_DIR:-/usr/local/bin}"
BINARY_NAME="agent"
SERVICE_NAME="agent-rust"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Helper Functions
#######################################
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

#######################################
# System Detection
#######################################
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        i386|i686)
            echo "i386"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

get_platform_filename() {
    local os=$1
    local arch=$2

    if [[ "$os" == "linux" ]]; then
        echo "agent-rust-linux-${arch}.tar.gz"
    elif [[ "$os" == "macos" ]]; then
        echo "agent-rust-macos-${arch}.tar.gz"
    else
        echo ""
    fi
}

#######################################
# Security Checks
#######################################
check_https() {
    if [[ "$SCRIPT_URL" != https://* ]]; then
        print_warning "Installer not loaded via HTTPS. For security, please use:"
        echo "  curl -sSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh | sudo bash"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

#######################################
# Download Functions
#######################################
get_latest_version() {
    # Get latest release version from GitHub API
    local url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl -sSL -H "Authorization: token ${GITHUB_TOKEN}" "$url" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        curl -sSL "$url" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    fi
}

download_binary() {
    local version=$1
    local filename=$2
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${filename}"

    print_info "Downloading ${filename}..."

    # Download to temp file
    if curl -fsSL "$download_url" -o "/tmp/${filename}"; then
        print_success "Downloaded successfully"
        echo "/tmp/${filename}"
    else
        print_error "Failed to download from ${download_url}"
        print_info "Please check:"
        echo "  1. Your internet connection"
        echo "  2. The release exists at: https://github.com/${GITHUB_REPO}/releases"
        exit 1
    fi
}

download_checksums() {
    local version=$1
    local url="https://github.com/${GITHUB_REPO}/releases/download/${version}/checksums.txt"

    if curl -fsSL "$url" -o "/tmp/checksums.txt"; then
        echo "/tmp/checksums.txt"
    else
        print_warning "Could not download checksums.txt"
        echo ""
    fi
}

verify_checksum() {
    local archive=$1
    local checksums_file=$2

    if [[ -z "$checksums_file" ]] || [[ ! -f "$checksums_file" ]]; then
        print_warning "Checksum verification skipped (no checksums file)"
        return 0
    fi

    local filename=$(basename "$archive")
    local expected_checksum=$(grep "$filename" "$checksums_file" | awk '{print $1}')

    if [[ -z "$expected_checksum" ]]; then
        print_warning "Checksum not found for ${filename}"
        return 0
    fi

    print_info "Verifying checksum..."

    # Calculate checksum
    local actual_checksum=$(sha256sum "$archive" | awk '{print $1}')

    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        print_success "Checksum verified"
        return 0
    else
        print_error "Checksum mismatch!"
        echo "  Expected: ${expected_checksum}"
        echo "  Actual:   ${actual_checksum}"
        exit 1
    fi
}

extract_binary() {
    local archive=$1
    local extract_dir=$2

    print_info "Extracting binary..."

    mkdir -p "$extract_dir"
    if tar -xzf "$archive" -C "$extract_dir"; then
        print_success "Extracted successfully"
        echo "${extract_dir}/${BINARY_NAME}"
    else
        print_error "Failed to extract archive"
        exit 1
    fi
}

#######################################
# Installation Functions
#######################################
install_binary() {
    local source=$1

    print_info "Installing binary to ${INSTALL_DIR}..."

    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"

    # Copy binary
    if cp "$source" "${INSTALL_DIR}/${BINARY_NAME}"; then
        chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
        print_success "Binary installed to ${INSTALL_DIR}/${BINARY_NAME}"
    else
        print_error "Failed to install binary"
        exit 1
    fi
}

create_systemd_service() {
    local server_url=$1

    print_info "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Employee Monitoring Agent
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${BINARY_NAME} run --server-url ${server_url}
Restart=always
RestartSec=10s
Environment="AGENT_SERVER_URL=${server_url}"

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    print_success "Service file created"
}

create_launchd_service() {
    local server_url=$1

    print_info "Creating launchd service..."

    cat > "/Library/LaunchDaemons/com.ridwanajari.${SERVICE_NAME}.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ridwanajari.${SERVICE_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/${BINARY_NAME}</string>
        <string>run</string>
        <string>--server-url</string>
        <string>${server_url}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>/tmp</string>
    <key>StandardOutPath</key>
    <string>/var/log/${SERVICE_NAME}.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/${SERVICE_NAME}.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AGENT_SERVER_URL</key>
        <string>${server_url}</string>
    </dict>
</dict>
</plist>
EOF

    chmod 644 "/Library/LaunchDaemons/com.ridwanajari.${SERVICE_NAME}.plist"
    print_success "Service file created"
}

start_service_linux() {
    print_info "Enabling and starting service..."

    systemctl enable "${SERVICE_NAME}"
    systemctl start "${SERVICE_NAME}"

    sleep 2

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        print_success "Service started successfully"
    else
        print_warning "Service may not have started. Check with: systemctl status ${SERVICE_NAME}"
    fi
}

start_service_macos() {
    print_info "Loading service..."

    launchctl load "/Library/LaunchDaemons/com.ridwanajari.${SERVICE_NAME}.plist"

    sleep 2

    print_success "Service loaded"
    print_info "Note: macOS requires screen recording permission for screenshots"
    echo "  Go to: System Preferences > Security & Privacy > Privacy > Screen Recording"
    echo "  Add and allow '${BINARY_NAME}'"
}

#######################################
# Server URL Prompt
#######################################
get_server_url() {
    local url="$1"

    # Check argument first
    if [[ -n "$url" ]]; then
        echo "$url"
        return
    fi

    # Check environment variable
    if [[ -n "$AGENT_SERVER_URL" ]]; then
        echo "$AGENT_SERVER_URL"
        return
    fi

    # Interactive prompt
    while true; do
        echo -n "Enter server URL (e.g., http://192.168.1.100:8080): "
        read -r SERVER_URL

        if [[ -n "$SERVER_URL" ]]; then
            echo "$SERVER_URL"
            return
        else
            print_error "Server URL cannot be empty"
        fi
    done
}

#######################################
# Main Installation Flow
#######################################
main() {
    # Capture server URL from argument
    SERVER_URL_ARG="$1"

    clear
    print_header "Employee Monitoring Agent Installer"

    # Security checks
    check_root
    check_https

    # Detect system
    OS=$(detect_os)
    if [[ "$OS" == "unknown" ]]; then
        print_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi

    ARCH=$(detect_arch)
    if [[ "$ARCH" == "unknown" ]]; then
        print_error "Unsupported architecture: $(uname -m)"
        exit 1
    fi

    print_success "Detected: ${OS} (${ARCH})"

    # Get platform-specific filename
    FILENAME=$(get_platform_filename "$OS" "$ARCH")
    if [[ -z "$FILENAME" ]]; then
        print_error "Could not determine download filename"
        exit 1
    fi

    # Get server URL
    echo
    SERVER_URL=$(get_server_url "$SERVER_URL_ARG")
    print_success "Server URL: ${SERVER_URL}"

    # Get latest version
    echo
    print_info "Fetching latest release version..."
    VERSION=$(get_latest_version)

    if [[ -z "$VERSION" ]]; then
        print_error "Failed to fetch latest version"
        print_info "You can specify version manually by editing this script"
        exit 1
    fi

    print_success "Latest version: ${VERSION}"

    # Download binary
    echo
    ARCHIVE_PATH=$(download_binary "$VERSION" "$FILENAME")

    # Download checksums
    CHECKSUMS_PATH=$(download_checksums "$VERSION")

    # Verify checksum
    echo
    verify_checksum "$ARCHIVE_PATH" "$CHECKSUMS_PATH"

    # Extract binary
    EXTRACT_DIR="/tmp/agent-extract"
    BINARY_PATH=$(extract_binary "$ARCHIVE_PATH" "$EXTRACT_DIR")

    # Install binary
    echo
    install_binary "$BINARY_PATH"

    # Create service
    echo
    if [[ "$OS" == "linux" ]]; then
        create_systemd_service "$SERVER_URL"
        start_service_linux
    elif [[ "$OS" == "macos" ]]; then
        create_launchd_service "$SERVER_URL"
        start_service_macos
    fi

    # Cleanup
    rm -rf "$EXTRACT_DIR"
    rm -f "$ARCHIVE_PATH"
    rm -f "$CHECKSUMS_PATH"

    # Success message
    echo
    print_header "Installation Complete!"
    echo
    echo -e "${GREEN}Server URL:${NC} ${SERVER_URL}"
    echo -e "${GREEN}Version:${NC}    ${VERSION}"
    echo -e "${GREEN}Binary:${NC}     ${INSTALL_DIR}/${BINARY_NAME}"
    echo
    echo "Useful commands:"
    if [[ "$OS" == "linux" ]]; then
        echo "  Check status:  sudo systemctl status ${SERVICE_NAME}"
        echo "  View logs:     sudo journalctl -u ${SERVICE_NAME} -f"
        echo "  Stop agent:    sudo systemctl stop ${SERVICE_NAME}"
        echo "  Start agent:   sudo systemctl start ${SERVICE_NAME}"
    elif [[ "$OS" == "macos" ]]; then
        echo "  View logs:     sudo log show --predicate 'process == \"${BINARY_NAME}\"' --last 1h"
        echo "  Stop agent:    sudo launchctl stop com.ridwanajari.${SERVICE_NAME}"
        echo "  Start agent:   sudo launchctl start com.ridwanajari.${SERVICE_NAME}"
    fi
    echo
    echo "Uninstall:"
    if [[ "$OS" == "linux" ]]; then
        echo "  sudo systemctl stop ${SERVICE_NAME}"
        echo "  sudo systemctl disable ${SERVICE_NAME}"
        echo "  sudo rm /etc/systemd/system/${SERVICE_NAME}.service"
        echo "  sudo rm ${INSTALL_DIR}/${BINARY_NAME}"
        echo "  sudo systemctl daemon-reload"
    elif [[ "$OS" == "macos" ]]; then
        echo "  sudo launchctl unload /Library/LaunchDaemons/com.ridwanajari.${SERVICE_NAME}.plist"
        echo "  sudo rm /Library/LaunchDaemons/com.ridwanajari.${SERVICE_NAME}.plist"
        echo "  sudo rm ${INSTALL_DIR}/${BINARY_NAME}"
    fi
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Run main function
main "$@"
