# Service Installation Guide

This guide explains how to install the Employee Monitoring Agent as a system service on different operating systems.

## Prerequisites

- **Linux**: systemd-based distribution
- **macOS**: macOS 10.15 (Catalina) or later
- **Windows**: Windows 10 or later with Administrator privileges

## Linux Installation (systemd)

### Automated Installation

```bash
# Build the agent first
cargo build --release

# Install as service (requires sudo)
sudo ./scripts/install-service.sh
```

### Manual Installation

1. **Copy the binary**
   ```bash
   sudo cp target/release/agent /usr/local/bin/
   sudo chmod +x /usr/local/bin/agent
   ```

2. **Create service user**
   ```bash
   sudo useradd -r -s /bin/false -d /var/lib/agent-rust agent
   ```

3. **Create directories**
   ```bash
   sudo mkdir -p /etc/agent-rust
   sudo mkdir -p /var/lib/agent-rust
   sudo mkdir -p /var/log/agent-rust
   sudo chown -R agent:agent /var/lib/agent-rust /var/log/agent-rust
   ```

4. **Install systemd service file**
   ```bash
   sudo cp scripts/agent-rust.service /etc/systemd/system/
   sudo systemctl daemon-reload
   ```

5. **Create configuration**
   ```bash
   sudo cp config.example.toml /etc/agent-rust/config.toml
   sudo nano /etc/agent-rust/config.toml  # Edit as needed
   sudo chown agent:agent /etc/agent-rust/config.toml
   ```

6. **Enable and start service**
   ```bash
   sudo systemctl enable agent-rust
   sudo systemctl start agent-rust
   ```

7. **Verify service status**
   ```bash
   sudo systemctl status agent-rust
   ```

### Service Management Commands

```bash
# Start service
sudo systemctl start agent-rust

# Stop service
sudo systemctl stop agent-rust

# Restart service
sudo systemctl restart agent-rust

# View logs
sudo journalctl -u agent-rust -f

# View service status
sudo systemctl status agent-rust

# Enable at boot
sudo systemctl enable agent-rust

# Disable at boot
sudo systemctl disable agent-rust
```

## macOS Installation (launchd)

### Automated Installation

```bash
# Build the agent first
cargo build --release

# Install as service (requires sudo)
sudo ./scripts/install-service-macos.sh
```

### Manual Installation

1. **Copy the binary**
   ```bash
   sudo cp target/release/agent /usr/local/bin/
   sudo chmod +x /usr/local/bin/agent
   ```

2. **Create directories**
   ```bash
   sudo mkdir -p "/Library/Application Support/agent-rust"
   sudo mkdir -p /var/log/agent-rust
   ```

3. **Install launchd plist**
   ```bash
   sudo cp scripts/com.ridwanajari.agent-rust.plist /Library/LaunchDaemons/
   sudo chown root:wheel /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
   ```

4. **Create configuration**
   ```bash
   sudo cp config.example.toml "/Library/Application Support/agent-rust/config.toml"
   sudo nano "/Library/Application Support/agent-rust/config.toml"
   ```

5. **Load service**
   ```bash
   sudo launchctl load /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
   ```

### Service Management Commands

```bash
# Start service
sudo launchctl start com.ridwanajari.agent-rust

# Stop service
sudo launchctl stop com.ridwanajari.agent-rust

# Restart service
sudo launchctl kickstart -k gui/$(id -u)/com.ridwanajari.agent-rust

# Unload service
sudo launchctl unload /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# View logs
log show --predicate 'process == "agent"' --style syslog --last 1h
```

## Windows Installation (Windows Service)

### Automated Installation

```powershell
# Build the agent first
cargo build --release --target x86_64-pc-windows-gnu

# Run PowerShell as Administrator and execute:
.\scripts\install-service.ps1
```

### Manual Installation

1. **Copy the binary**
   ```powershell
   New-Item -ItemType Directory -Path "C:\Program Files\AgentRust" -Force
   Copy-Item target\release\agent.exe "C:\Program Files\AgentRust\agent.exe"
   ```

2. **Create configuration directory**
   ```powershell
   New-Item -ItemType Directory -Path "C:\ProgramData\AgentRust" -Force
   Copy-Item config.example.toml "C:\ProgramData\AgentRust\config.toml"
   ```

3. **Install service using PowerShell**
   ```powershell
   # Run as Administrator
   .\scripts\install-service.ps1
   ```

Or using sc.exe:

```cmd
sc.exe create AgentRust binPath= "C:\Program Files\AgentRust\agent.exe run --config C:\ProgramData\AgentRust\config.toml" DisplayName= "Employee Monitoring Agent" start= auto
sc.exe description AgentRust "Cross-platform employee monitoring agent"
sc.exe failure AgentRust reset= 300 actions= restart/60000/restart/120000
sc.exe start AgentRust
```

### Service Management Commands

```powershell
# Start service
Start-Service AgentRust

# Stop service
Stop-Service AgentRust

# Restart service
Restart-Service AgentRust

# View service status
Get-Service AgentRust

# View logs
Get-EventLog -LogName Application -Source AgentRust -Newest 50

# Remove service
Remove-Service -Name AgentRust
```

## Configuration

After installation, edit the configuration file for your environment:

### Linux/macOS
```bash
sudo nano /etc/agent-rust/config.toml
# or
sudo nano "/Library/Application Support/agent-rust/config.toml"
```

### Windows
```powershell
notepad "C:\ProgramData\AgentRust\config.toml"
```

### Key Configuration Options

```toml
[server]
url = "https://your-server.com"  # Change to your server URL
timeout_secs = 30

[intervals]
heartbeat_secs = 30              # How often to send heartbeat
activity_secs = 60               # How often to check window activity
screenshot_secs = 300           # How often to capture screenshots

[thresholds]
idle_secs = 300                  # Idle threshold before stopping monitoring
```

## Troubleshooting

### Service fails to start

**Linux:**
```bash
sudo journalctl -xe
sudo journalctl -u agent-rust -n 50
```

**macOS:**
```bash
log show --predicate 'eventMessage contains "agent"' --info --last 1h
```

**Windows:**
- Check Windows Event Viewer → Windows Logs → Application
- Look for entries with source "AgentRust"

### Permission denied errors

**Linux/macOS:**
```bash
# Check file permissions
ls -la /etc/agent-rust/
ls -la /var/lib/agent-rust/

# Fix ownership
sudo chown -R agent:agent /var/lib/agent-rust /var/log/agent-rust
```

### Service not connecting to server

1. Verify server URL in config file
2. Check network connectivity
3. Review logs for error messages
4. Ensure firewall allows outbound connections

### High CPU or memory usage

1. Check monitoring intervals (increase if too frequent)
2. Verify screenshot settings (capture interval, compression)
3. Review logs for errors
4. Consider adjusting resource limits in service file

## Uninstallation

### Linux
```bash
sudo ./scripts/install-service.sh uninstall
# or manually:
sudo systemctl stop agent-rust
sudo systemctl disable agent-rust
sudo rm /etc/systemd/system/agent-rust.service
sudo systemctl daemon-reload
sudo userdel agent  # optional
```

### macOS
```bash
sudo launchctl unload /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
sudo rm /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
sudo rm -rf "/Library/Application Support/agent-rust"
```

### Windows
```powershell
# Run as Administrator
.\scripts\install-service.ps1 -Uninstall
# or manually:
Stop-Service AgentRust
Remove-Service -Name AgentRust
Remove-Item -Recurse -Force "C:\Program Files\AgentRust"
Remove-Item -Recurse -Force "C:\ProgramData\AgentRust"
```

## Security Considerations

- Run the agent as a non-privileged user when possible
- Use HTTPS/TLS for server communication
- Restrict file permissions on configuration files (chmod 640 or 600)
- Regularly update the agent to the latest version
- Monitor and review logs regularly
- Ensure compliance with privacy regulations in your jurisdiction
