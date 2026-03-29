#!/bin/bash
# Simple One-Line Installer for Employee Monitoring Agent (Rust)
# Usage: sudo ./install-simple.sh <server-url>
# Example: sudo ./install-simple.sh http://192.168.1.100:8080

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

BINARY_PATH="/usr/local/bin/agent"
SERVICE_FILE="/etc/systemd/system/agent-rust.service"

# Find the binary (try release first, then debug)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/../target/release/agent"

if [[ ! -f "$SOURCE" ]]; then
    SOURCE="$SCRIPT_DIR/../target/debug/agent"
fi

if [[ ! -f "$SOURCE" ]]; then
    echo -e "${RED}Error: Binary not found at target/release/agent or target/debug/agent${NC}"
    echo "Please build the agent first:"
    echo "  cd .. && cargo build --release"
    exit 1
fi

echo -e "${GREEN}Installing Employee Monitoring Agent (Rust)...${NC}"
echo ""

# Install binary
echo "Installing binary to $BINARY_PATH"
cp "$SOURCE" "$BINARY_PATH"
chmod +x "$BINARY_PATH"
echo -e "${GREEN}✓ Binary installed${NC}"

# Create systemd service file
echo "Creating systemd service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Employee Monitoring Agent
Documentation=https://gitlab.ajari.app/ridwanajari/agent-emp
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
echo -e "${GREEN}✓ Service file created${NC}"

# Enable and start service
echo "Enabling and starting service"
systemctl daemon-reload
systemctl enable agent-rust
systemctl restart agent-rust
echo -e "${GREEN}✓ Service started${NC}"

# Show status
sleep 2
if systemctl is-active --quiet agent-rust; then
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Agent installed and started successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Server URL: $SERVER_URL"
    echo ""
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
else
    echo -e "${RED}Warning: Service may not have started successfully${NC}"
    echo "Check status with: sudo systemctl status agent-rust"
    exit 1
fi
