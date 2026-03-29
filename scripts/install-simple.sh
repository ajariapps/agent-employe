#!/bin/bash
# Simple One-Line Installer for Employee Monitoring Agent (Rust)
# Usage: sudo ./install-simple.sh <server-url>
# Example: sudo ./install-simple.sh http://192.168.1.100:8080

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_REPO="ajariapps/agent-employe"
BINARY_PATH="/usr/local/bin/agent"
SERVICE_FILE="/etc/systemd/system/agent-rust.service"

# Get server URL from argument
SERVER_URL="$1"

# Check if server URL is provided
if [[ -z "$SERVER_URL" ]]; then
    echo -e "${RED}Error: Server URL is required${NC}"
    echo ""
    echo "Usage: $0 <server-url>"
    echo "Example: $0 http://192.168.1.100:8080"
    echo "         $0 https://monitoring.company.com"
    exit 1
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

#######################################
# Platform Detection
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
# Download Functions
#######################################
download_from_github() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Binary not found locally. Downloading from GitHub...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    # Detect platform
    OS=$(detect_os)
    ARCH=$(detect_arch)

    if [[ "$OS" == "unknown" ]] || [[ "$ARCH" == "unknown" ]]; then
        echo -e "${RED}Error: Unsupported platform${NC}"
        return 1
    fi

    echo "Detected: ${OS} (${ARCH})"

    # Get filename
    FILENAME=$(get_platform_filename "$OS" "$ARCH")

    if [[ -z "$FILENAME" ]]; then
        echo -e "${RED}Error: Could not determine download filename${NC}"
        return 1
    fi

    # Get latest version
    echo "Fetching latest version..."
    VERSION=$(curl -sSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$VERSION" ]]; then
        echo -e "${RED}Error: Could not fetch latest version${NC}"
        return 1
    fi

    echo "Latest version: ${VERSION}"

    # Download
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${FILENAME}"
    echo "Downloading from: ${DOWNLOAD_URL}"

    TEMP_DIR=$(mktemp -d)
    ARCHIVE_PATH="${TEMP_DIR}/${FILENAME}"

    if curl -fsSL "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"; then
        echo -e "${GREEN}Download successful${NC}"
    else
        echo -e "${RED}Error: Download failed${NC}"
        return 1
    fi

    # Extract
    echo "Extracting..."
    tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"

    SOURCE="${TEMP_DIR}/agent"

    if [[ ! -f "$SOURCE" ]]; then
        echo -e "${RED}Error: Binary not found in archive${NC}"
        return 1
    fi

    # Cleanup function
    cleanup_download() {
        if [[ -d "$TEMP_DIR" ]]; then
            rm -rf "$TEMP_DIR"
        fi
    }

    trap cleanup_download EXIT

    return 0
}

# Find the binary (try release first, then debug, then download)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/../target/release/agent"

if [[ ! -f "$SOURCE" ]]; then
    SOURCE="$SCRIPT_DIR/../target/debug/agent"
fi

if [[ ! -f "$SOURCE" ]]; then
    if ! download_from_github; then
        echo -e "${RED}Error: Could not find or download binary${NC}"
        echo ""
        echo "Please do one of the following:"
        echo "  1. Build the agent: cd .. && cargo build --release"
        echo "  2. Check your internet connection"
        echo "  3. Download manually from: https://github.com/${GITHUB_REPO}/releases"
        exit 1
    fi
fi

echo -e "${GREEN}Installing Employee Monitoring Agent (Rust)...${NC}"
echo ""

# Detect OS for service type
OS=$(detect_os)

# Install binary
echo "Installing binary to $BINARY_PATH"
cp "$SOURCE" "$BINARY_PATH"
chmod +x "$BINARY_PATH"
echo -e "${GREEN}✓ Binary installed${NC}"

# Create service file
echo "Creating service..."

if [[ "$OS" == "linux" ]]; then
    # Create systemd service file
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Employee Monitoring Agent
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=simple
ExecStart=$BINARY_PATH run --server-url $SERVER_URL
Restart=always
RestartSec=10s
Environment="AGENT_SERVER_URL=$SERVER_URL"

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=agent-rust

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    echo "Enabling and starting service"
    systemctl daemon-reload
    systemctl enable agent-rust
    systemctl restart agent-rust
    echo -e "${GREEN}✓ Service started${NC}"

    # Show status
    sleep 2
    if systemctl is-active --quiet agent-rust; then
        SUCCESS=true
    else
        SUCCESS=false
    fi

elif [[ "$OS" == "macos" ]]; then
    # Create launchd service file
    LAUNCHD_PLIST="/Library/LaunchDaemons/com.ridwanajari.agent-rust.plist"

    cat > "$LAUNCHD_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ridwanajari.agent-rust</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY_PATH</string>
        <string>run</string>
        <string>--server-url</string>
        <string>$SERVER_URL</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>/tmp</string>
    <key>StandardOutPath</key>
    <string>/var/log/agent-rust.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/agent-rust.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AGENT_SERVER_URL</key>
        <string>$SERVER_URL</string>
    </dict>
</dict>
</plist>
EOF

    chmod 644 "$LAUNCHD_PLIST"

    # Load service
    echo "Loading service"
    launchctl load "$LAUNCHD_PLIST"
    echo -e "${GREEN}✓ Service loaded${NC}"

    # Note about permissions
    echo ""
    echo -e "${YELLOW}Note: macOS requires screen recording permission for screenshots${NC}"
    echo "  Go to: System Preferences > Security & Privacy > Privacy > Screen Recording"
    echo "  Add and allow 'agent'"

    SUCCESS=true
fi

# Show final message
if [[ "$SUCCESS" == true ]]; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Agent installed and started successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Server URL: $SERVER_URL"
    echo ""

    if [[ "$OS" == "linux" ]]; then
        echo "Useful commands:"
        echo "  Check status:  sudo systemctl status agent-rust"
        echo "  View logs:     sudo journalctl -u agent-rust -f"
        echo "  Stop agent:    sudo systemctl stop agent-rust"
        echo "  Start agent:   sudo systemctl start agent-rust"
        echo ""
        echo "Uninstall:"
        echo "  sudo systemctl stop agent-rust"
        echo "  sudo systemctl disable agent-rust"
        echo "  sudo rm $SERVICE_FILE"
        echo "  sudo rm $BINARY_PATH"
        echo "  sudo systemctl daemon-reload"
    elif [[ "$OS" == "macos" ]]; then
        echo "Useful commands:"
        echo "  View logs:     sudo log show --predicate 'process == \"agent\"' --last 1h"
        echo "  Stop agent:    sudo launchctl stop com.ridwanajari.agent-rust"
        echo "  Start agent:   sudo launchctl start com.ridwanajari.agent-rust"
        echo ""
        echo "Uninstall:"
        echo "  sudo launchctl unload $LAUNCHD_PLIST"
        echo "  sudo rm $LAUNCHD_PLIST"
        echo "  sudo rm $BINARY_PATH"
    fi
else
    echo -e "${RED}Warning: Service may not have started successfully${NC}"
    echo "Check status with: sudo systemctl status agent-rust"
    exit 1
fi
