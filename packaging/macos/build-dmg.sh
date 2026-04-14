#!/bin/bash
# Build script for macOS DMG installer

set -e

# Configuration
APP_NAME="Agent"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="agent-rust"
VERSION="${VERSION:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/target"
PACKAGING_DIR="${SCRIPT_DIR}"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="aarch64-apple-darwin"
    DMG_ARCH="arm64"
else
    TARGET="x86_64-apple-darwin"
    DMG_ARCH="x86_64"
fi

DMG_FILE="${DMG_NAME}-${VERSION}-${DMG_ARCH}.dmg"

echo "============================================"
echo "  Building macOS DMG Installer"
echo "============================================"
echo "Version: ${VERSION}"
echo "Architecture: ${DMG_ARCH}"
echo ""

# Check if binary exists
BINARY="${BUILD_DIR}/${TARGET}/release/agent"
if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at ${BINARY}"
    echo "Please build the agent first with: cargo build --release --target ${TARGET}"
    exit 1
fi

# Create temporary directory for DMG contents
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "Creating app bundle..."
APP_PATH="${TEMP_DIR}/${APP_BUNDLE}"

# Create app bundle structure
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"
mkdir -p "${APP_PATH}/Contents/SharedSupport"

# Copy Info.plist
cp "${PACKAGING_DIR}/${APP_BUNDLE}/Contents/Info.plist" "${APP_PATH}/Contents/"

# Copy binary
cp "${BINARY}" "${APP_PATH}/Contents/MacOS/agent"
chmod +x "${APP_PATH}/Contents/MacOS/agent"

# Copy resources
cp "${PACKAGING_DIR}/${APP_BUNDLE}/Contents/Resources/uninstall.sh" "${APP_PATH}/Contents/Resources/"
cp "${PROJECT_ROOT}/scripts/com.ridwanajari.agent-rust.plist" "${APP_PATH}/Contents/Resources/"

# Copy config example
mkdir -p "${APP_PATH}/Contents/SharedSupport"
cp "${PROJECT_ROOT}/config.example.toml" "${APP_PATH}/Contents/SharedSupport/config.toml.example"
cp "${PROJECT_ROOT}/README.md" "${APP_PATH}/Contents/SharedSupport/"

# Create installation script
cat > "${APP_PATH}/Contents/SharedSupport/install.sh" << 'EOF'
#!/bin/bash
# Installation helper for Agent.app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "  Agent Installation"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This installation requires administrative privileges."
    echo "Please enter your password to continue."
    sudo "$0" "$@"
    exit $?
fi

# Stop existing service if running
if launchctl list | grep -q "com.ridwanajari.agent-rust"; then
    echo "Stopping existing agent service..."
    launchctl unload -w /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist 2>/dev/null || true
fi

# Install binary
echo "Installing binary..."
mkdir -p /usr/local/bin
cp "${APP}/Contents/MacOS/agent" /usr/local/bin/agent
chmod +x /usr/local/bin/agent

# Install LaunchDaemon
echo "Installing LaunchDaemon..."
cp "${APP}/Contents/Resources/com.ridwanajari.agent-rust.plist" /Library/LaunchDaemons/

# Create directories
echo "Creating data directories..."
mkdir -p "/Library/Application Support/agent-rust"
mkdir -p /var/lib/agent-rust
mkdir -p /var/log/agent-rust

# Install default config if not exists
if [ ! -f "/Library/Application Support/agent-rust/config.toml" ]; then
    echo "Installing default configuration..."
    cp "${APP}/Contents/SharedSupport/config.toml.example" "/Library/Application Support/agent-rust/config.toml"

    # Prompt for server URL
    echo ""
    read -p "Enter server URL (e.g., http://server:8080): " server_url
    if [ -n "$server_url" ]; then
        sed -i '' "s|url = \"http://localhost:8080\"|url = \"$server_url\"|" "/Library/Application Support/agent-rust/config.toml"
    fi
fi

# Set permissions
chown -R root:wheel /var/lib/agent-rust
chown -R root:wheel /var/log/agent-rust
chmod 755 /var/lib/agent-rust
chmod 755 /var/log/agent-rust

# Load and start service
echo "Starting agent service..."
launchctl load -w /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

echo ""
echo "============================================"
echo "  Installation Complete"
echo "============================================"
echo ""
echo "Agent is now running as a background service."
echo ""
echo "Configuration: /Library/Application Support/agent-rust/config.toml"
echo "Logs: /var/log/agent-rust/agent.log"
echo ""
echo "To uninstall, run: sudo /Applications/Agent.app/Contents/Resources/uninstall.sh"
EOF

chmod +x "${APP_PATH}/Contents/SharedSupport/install.sh"

# Calculate app size for DMG
APP_SIZE=$(du -sm "${APP_PATH}" | cut -f1)
DMG_SIZE=$((APP_SIZE + 10))

echo "Creating DMG..."
DMG_PATH="${BUILD_DIR}/${DMG_FILE}"

# Create DMG using hdiutil
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${TEMP_DIR}" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -size "${DMG_SIZE}m" \
    "${DMG_PATH}"

echo ""
echo "============================================"
echo "  Build Complete"
echo "============================================"
echo ""
echo "DMG created: ${DMG_PATH}"
echo "Size: $(du -h "${DMG_PATH}" | cut -f1)"
echo ""
echo "To install:"
echo "  1. Open the DMG"
echo "  2. Drag Agent.app to /Applications"
echo "  3. Run: open /Applications/Agent.app/Contents/SharedSupport/install.sh"
echo ""
