# Employee Monitoring Agent (Rust)

A high-performance, cross-platform employee monitoring agent written in Rust. Tracks activity, captures screenshots, and reports to a central server.

## Features

- **Cross-platform**: Native support for Linux, macOS, and Windows
- **Efficient**: Low CPU and memory footprint (~2-5 MB binary)
- **Reliable**: Built-in retry logic, circuit breaker, and offline queue
- **Secure**: TLS support, secure token storage
- **Observable**: Structured logging with tracing
- **Production-ready**: Comprehensive error handling and graceful degradation

## Architecture

```
agent-rust/
├── crates/
│   ├── agent-core/    # Core library, config, models
│   ├── platform/      # Platform abstraction layer
│   ├── client/        # API client with retry & queue
│   ├── activity/      # Activity tracking
│   ├── screenshot/    # Screenshot capture
│   ├── idle/         # Idle detection
│   └── service/      # Service/daemon management
└── bin/agent/        # Main binary
```

## Performance

| Metric | Value |
|--------|-------|
| Binary Size | ~2-5 MB |
| Memory Usage | ~10-20 MB |
| CPU Usage | <1% idle |
| Screenshot Capture | <100ms |
| Activity Detection | <10ms |

## Quick Start

### Quick Install (Recommended)

#### Linux

```bash
# Build the agent
cd agent-rust
cargo build --release

# Install with one command
sudo ./scripts/install-simple.sh http://your-server:8080
```

The agent will:
- Install to `/usr/local/bin/agent`
- Create a systemd service
- Auto-register with the server
- Start monitoring immediately

#### Windows (PowerShell as Administrator)

```powershell
# Build the agent
cd agent-rust
cargo build --release

# Install with one command
.\scripts\install-simple.ps1 http://your-server:8080
```

#### Useful Commands

**Linux:**
```bash
# Check status
sudo systemctl status agent-rust

# View logs
sudo journalctl -u agent-rust -f

# Stop/Start
sudo systemctl stop agent-rust
sudo systemctl start agent-rust
```

**Windows:**
```powershell
# Check status
Get-Service AgentRust

# View logs
Get-EventLog -LogName Application -Source AgentRust -Newest 50
```

### Advanced Installation

For production environments with dedicated user, security hardening, and custom paths:

**Linux/macOS:**

```bash
# Download and extract
wget https://github.com/yourorg/employee-monitoring/releases/latest/download/agent-rust-linux-x86_64.tar.gz
tar xzf agent-rust-linux-x86_64.tar.gz

# Install
sudo install agent /usr/local/bin/

# Configure
sudo mkdir -p /etc/agent-rust
sudo cp config.example.toml /etc/agent-rust/config.toml
sudo nano /etc/agent-rust/config.toml

# Run (foreground)
sudo agent run

# Or as service
sudo agent install service
sudo systemctl start agent-rust
```

#### Windows

```powershell
# Download from releases
# Extract and run
agent.exe run
```

### Configuration

Edit `/etc/agent-rust/config.toml` (or `config.toml` in current directory):

```toml
[server]
url = "https://your-server.com"

[intervals]
heartbeat_secs = 30
activity_secs = 60
screenshot_secs = 300

[thresholds]
idle_secs = 300
```

### Environment Variables

Override configuration with environment variables:

```bash
export AGENT_SERVER_URL="https://your-server.com"
export AGENT_API_TOKEN="your-token-here"
export AGENT_LOG_LEVEL="debug"

agent run
```

## Usage

### Commands

```bash
# Run the agent
agent run

# Register with server
agent register --server-url https://your-server.com

# Show status
agent status

# Show version
agent version
```

### CLI Options

```
agent run [OPTIONS]

Options:
  -s, --server-url <URL>       Server URL [env: AGENT_SERVER_URL]
  -t, --api-token <TOKEN>      API token [env: AGENT_API_TOKEN]
  -l, --log-level <LEVEL>      Log level [env: AGENT_LOG_LEVEL] [default: info]
  -c, --config <PATH>          Config file [env: AGENT_CONFIG]
      --foreground             Run in foreground
  -h, --help                   Print help
```

## Platform Support

### Linux

**Requirements:**
- X11 or Wayland display server
- systemd (for service mode)

**Dependencies:**
- libx11, libxrandr, libxext (for X11)

### macOS

**Requirements:**
- macOS 10.15 (Catalina) or later

**Features:**
- Core Graphics for screenshots
- Cocoa/AppKit for window detection

### Windows

**Requirements:**
- Windows 10 or later

**Features:**
- Win32 API for window detection
- GDI+ for screenshots
- Windows Service support

## Development

### Prerequisites

- Rust 1.75 or later
- Platform-specific development tools

#### Linux

```bash
sudo apt-get install build-essential libx11-dev libxrandr-dev libxext-dev
```

#### macOS

```bash
# Xcode command line tools
xcode-select --install
```

#### Windows

- Install [MSVC](https://visualstudio.microsoft.com/)
- Install [Rust](https://rustup.rs/)

### Building

```bash
# Build for current platform
cargo build --release

# Build for all targets
./scripts/build-release.sh

# Build with debug info
cargo build
```

### Testing

```bash
# Run all tests
cargo test

# Run with logging
RUST_LOG=debug cargo test

# Run integration tests
cargo test --test integration
```

### Development

```bash
# Run with auto-reload
cargo install cargo-watch
cargo watch -x run

# Format code
cargo fmt

# Lint
cargo clippy -- -D warnings
```

## Configuration Options

### Server Settings

```toml
[server]
url = "https://your-server.com"    # Server URL
timeout_secs = 30                  # Request timeout
connect_timeout_secs = 10          # Connection timeout
max_retries = 3                    # Retry attempts
```

### Intervals

```toml
[intervals]
heartbeat_secs = 30                # Heartbeat interval (min: 10)
activity_secs = 60                 # Activity tracking (min: 5)
screenshot_secs = 300              # Screenshot interval (min: 30)
update_check_secs = 3600           # Update check interval
```

### Thresholds

```toml
[thresholds]
idle_secs = 300                    # Idle threshold (5 minutes)
queue_max_bytes = 104857600        # Max queue size (100 MB)
queue_max_items = 10000            # Max queue items
```

### Screenshot Settings

```toml
[screenshot]
format = "png"                     # Image format (png, jpeg)
jpeg_quality = 85                  # JPEG quality (1-100)
capture_all_monitors = false       # Multi-monitor support
compress = true                    # Compress before upload
```

## Logging

### Log Levels

- `trace`: Most verbose
- `debug`: Debug information
- `info`: General information (default)
- `warn`: Warnings
- `error`: Errors only

### Log Formats

- `json`: Structured JSON logs
- `pretty`: Human-readable
- `compact`: Single-line format

## Troubleshooting

### Permission Denied

**Problem:** Cannot create directories or files

**Solution:** Run with appropriate permissions or change data directory:
```bash
sudo agent run
# or
export AGENT_DATA_DIR=$HOME/.agent-rust
agent run
```

### Connection Refused

**Problem:** Cannot connect to server

**Solution:** Check server URL and network connectivity:
```bash
curl https://your-server.com/api/health
```

### Screenshot Failed

**Problem:** Screenshot capture fails

**Solution:**
- Linux: Check X11 display (`echo $DISPLAY`)
- macOS: Grant screen recording permission in System Preferences
- Windows: Run as administrator if needed

## License

MIT License - see LICENSE file for details.

## Security

This agent captures screenshots and tracks window activity. Ensure compliance with local privacy laws and regulations.

- Employees should be informed about monitoring
- Data should be encrypted in transit and at rest
- Access to monitoring data should be restricted

## Support

- Documentation: [docs/](docs/)
- Issues: [GitHub Issues](https://github.com/yourorg/employee-monitoring/issues)
- Email: support@yourcompany.com
