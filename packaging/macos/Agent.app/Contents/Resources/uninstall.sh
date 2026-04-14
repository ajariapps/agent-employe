#!/bin/bash
# Uninstall script for Employee Monitoring Agent (macOS)

set -e

echo "============================================"
echo "  Agent Uninstaller"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (sudo)."
    echo "Please run: sudo ./uninstall.sh"
    exit 1
fi

# Stop and unload LaunchDaemon
echo "Stopping agent service..."
if [ -f /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist ]; then
    launchctl unload -w /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist 2>/dev/null || true
fi

# Kill any running agent processes
echo "Stopping agent processes..."
pkill -9 agent 2>/dev/null || true

# Remove LaunchDaemon
echo "Removing LaunchDaemon..."
rm -f /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# Remove binary
echo "Removing binary..."
rm -f /usr/local/bin/agent

# Remove app bundle
echo "Removing app bundle..."
rm -rf /Applications/Agent.app

# Remove configuration and data (ask user)
echo ""
read -p "Remove configuration and data files? (y/N): " remove_data
if [ "$remove_data" = "y" ] || [ "$remove_data" = "Y" ]; then
    echo "Removing data directories..."
    rm -rf "/Library/Application Support/agent-rust"
    rm -rf /var/lib/agent-rust
    rm -rf /var/log/agent-rust
else
    echo "Configuration and data files preserved:"
    echo "  - /Library/Application Support/agent-rust/"
    echo "  - /var/lib/agent-rust/"
    echo "  - /var/log/agent-rust/"
fi

echo ""
echo "Agent uninstalled successfully."
