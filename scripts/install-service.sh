#!/bin/bash
# Linux Service Installation Script for Employee Monitoring Agent
# Run as root or with sudo

set -e

# Configuration
BINARY_PATH="${BINARY_PATH:-/usr/local/bin/agent}"
CONFIG_PATH="${CONFIG_PATH:-/etc/agent-rust/config.toml}"
SERVICE_USER="${SERVICE_USER:-agent}"
SERVICE_GROUP="${SERVICE_GROUP:-agent}"
SERVICE_NAME="agent-rust"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install binary
install_binary() {
    log_step "Installing binary to $BINARY_PATH"

    # Find the binary in current directory or use provided path
    if [[ -z "$SOURCE_BINARY" ]]; then
        SOURCE_BINARY="$(dirname "$0")/target/release/agent"
        if [[ ! -f "$SOURCE_BINARY" ]]; then
            SOURCE_BINARY="$(dirname "$0")/target/debug/agent"
        fi
    fi

    if [[ ! -f "$SOURCE_BINARY" ]]; then
        log_error "Binary not found. Please build the agent first with 'cargo build --release'"
        exit 1
    fi

    cp "$SOURCE_BINARY" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    log_info "Binary installed: $BINARY_PATH"
}

# Create user and group
create_user() {
    log_step "Creating service user"

    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d /var/lib/agent-rust "$SERVICE_USER"
        log_info "User created: $SERVICE_USER"
    else
        log_info "User already exists: $SERVICE_USER"
    fi
}

# Create directories
create_directories() {
    log_step "Creating directories"

    # Config directory
    mkdir -p "$(dirname "$CONFIG_PATH")"

    # Data directory
    mkdir -p /var/lib/agent-rust
    chown -R "$SERVICE_USER:$SERVICE_GROUP" /var/lib/agent-rust

    # Log directory
    mkdir -p /var/log/agent-rust
    chown -R "$SERVICE_USER:$SERVICE_GROUP" /var/log/agent-rust

    # Run directory
    mkdir -p /run/agent-rust
    chown -R "$SERVICE_USER:$SERVICE_GROUP" /run/agent-rust

    log_info "Directories created"
}

# Create default configuration
create_config() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_step "Creating default configuration"

        cat > "$CONFIG_PATH" << 'EOF'
# Employee Monitoring Agent Configuration

[server]
url = "http://localhost:8080"
timeout_secs = 30
connect_timeout_secs = 10
max_retries = 3

[intervals]
heartbeat_secs = 30
activity_secs = 60
screenshot_secs = 300
update_check_secs = 3600

[thresholds]
idle_secs = 300
queue_max_bytes = 104857600
queue_max_items = 10000

[logging]
level = "info"
format = "json"
console = true
file = true
EOF

        chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG_PATH"
        chmod 640 "$CONFIG_PATH"
        log_info "Configuration created: $CONFIG_PATH"
    else
        log_info "Configuration already exists: $CONFIG_PATH"
    fi
}

# Install systemd service
install_service() {
    log_step "Installing systemd service"

    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Employee Monitoring Agent
Documentation=https://gitlab.ajari.app/ridwanajari/agent-emp
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
# Run as a regular user
User=$SERVICE_USER
Group=$SERVICE_GROUP

# Service configuration
Type=simple
ExecStart=$BINARY_PATH run --config $CONFIG_PATH
Restart=on-failure
RestartSec=30s

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/agent-rust
ReadWritePaths=/var/log/agent-rust
ReadWritePaths=/run/agent-rust

# Resource limits
MemoryMax=512M
CPUQuota=50%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_info "Systemd service installed"
}

# Enable and start service
start_service() {
    log_step "Enabling and starting service"

    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    log_info "Service enabled and started"
}

# Show status
show_status() {
    log_step "Service status"
    systemctl status "$SERVICE_NAME" --no-pager
    echo ""

    log_info "Useful commands:"
    echo "  Start service:   systemctl start $SERVICE_NAME"
    echo "  Stop service:    systemctl stop $SERVICE_NAME"
    echo "  Restart service: systemctl restart $SERVICE_NAME"
    echo "  View logs:       journalctl -u $SERVICE_NAME -f"
    echo "  View status:     systemctl status $SERVICE_NAME"
}

# Uninstall function
uninstall() {
    log_step "Uninstalling service"

    # Stop and disable service
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        systemctl disable "$SERVICE_NAME"
    fi

    # Remove service file
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload

    # Optionally remove user and directories
    read -p "Remove service user '$SERVICE_USER'? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        userdel "$SERVICE_USER" 2>/dev/null || true
        groupdel "$SERVICE_GROUP" 2>/dev/null || true
        rm -rf /var/lib/agent-rust
        rm -rf /var/log/agent-rust
        log_info "User and directories removed"
    fi

    log_info "Service uninstalled"
}

# Main installation flow
main() {
    if [[ "$1" == "uninstall" ]]; then
        uninstall
        exit 0
    fi

    check_root
    install_binary
    create_user
    create_directories
    create_config
    install_service
    start_service
    show_status

    log_info "Installation complete!"
}

# Run main function
main "$@"
