# Quick Install Guide

One-line installation commands for Employee Monitoring Agent.

## 🚀 Quick Install (Recommended)

### Linux

```bash
curl -sSL https://raw.githubusercontent.com/ajariapps/agent-employe/main/install.sh | sudo bash -s http://your-server:8080
```

### macOS

```bash
curl -sSL https://raw.githubusercontent.com/ajariapps/agent-employe/main/install.sh | sudo bash -s http://your-server:8080
```

### Windows (.exe Installer - Recommended)

1. Download `Agent-Setup.exe` from [Releases](https://github.com/ajariapps/agent-employe/releases/latest)
2. Double-click `Agent-Setup.exe`
3. Enter server URL when prompted
4. Click Install

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/ajariapps/agent-employe/main/install.ps1 | iex
```

---

## 📦 Manual Install

### Step 1: Download

| Platform | Download Link |
|----------|---------------|
| Linux x64 | [agent-rust-linux-x86_64.tar.gz](https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-linux-x86_64.tar.gz) |
| macOS Intel | [agent-rust-macos-x86_64.tar.gz](https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-macos-x86_64.tar.gz) |
| macOS Apple Silicon | [agent-rust-macos-arm64.tar.gz](https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-macos-arm64.tar.gz) |
| Windows | [Agent-Setup.exe](https://github.com/ajariapps/agent-employe/releases/latest/download/Agent-Setup.exe) |

### Step 2: Extract & Install

**Linux/macOS:**
```bash
# Extract
tar xzf agent-rust-*.tar.gz

# Install
sudo ./scripts/install-simple.sh http://your-server:8080
```

**Windows:**
- Extract and run `Agent-Setup.exe`
- Or use PowerShell:
  ```powershell
  Expand-Archive -Path agent-rust-windows-x64.tar.gz -DestinationPath .
  .\scripts\install-simple.ps1 http://your-server:8080
  ```

---

## 🔧 Configuration

Replace `http://your-server:8080` with your actual server URL, for example:
- `http://192.168.1.100:8080` (local server)
- `https://monitoring.company.com` (remote server with HTTPS)

---

## ✅ Verify Installation

**Linux:**
```bash
sudo systemctl status agent-rust
sudo journalctl -u agent-rust -f
```

**macOS:**
```bash
sudo log show --predicate 'process == "agent"' --last 1h
```

**Windows:**
```powershell
Get-Service AgentRust
Get-EventLog -LogName Application -Source AgentRust -Newest 50
```

---

## 🛠️ Management Commands

### Start/Stop/Restart

**Linux:**
```bash
sudo systemctl start agent-rust
sudo systemctl stop agent-rust
sudo systemctl restart agent-rust
```

**macOS:**
```bash
sudo launchctl start com.ridwanajari.agent-rust
sudo launchctl stop com.ridwanajari.agent-rust
```

**Windows:**
```powershell
Start-Service AgentRust
Stop-Service AgentRust
Restart-Service AgentRust
```

### Uninstall

**Linux:**
```bash
sudo systemctl stop agent-rust
sudo systemctl disable agent-rust
sudo rm /etc/systemd/system/agent-rust.service
sudo rm /usr/local/bin/agent
sudo systemctl daemon-reload
```

**macOS:**
```bash
sudo launchctl unload /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
sudo rm /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
sudo rm /usr/local/bin/agent
```

**Windows:**
```powershell
Stop-Service AgentRust -Force
Remove-Service AgentRust
Remove-Item "C:\Program Files\AgentRust" -Recurse -Force
```

---

## 🔑 macOS Permissions

After installation on macOS, grant screen recording permission:

1. Open **System Preferences**
2. Go to **Security & Privacy** > **Privacy** > **Screen Recording**
3. Click **+** and add `/usr/local/bin/agent`
4. Check the box to allow

---

## ❓ Troubleshooting

### Connection refused
```bash
# Test server connectivity
curl http://your-server:8080/api/health
```

### Screenshot failed
- **Linux**: Ensure `DISPLAY` variable is set: `echo $DISPLAY`
- **macOS**: Grant screen recording permission (see above)
- **Windows**: Run as Administrator

### Service won't start
```bash
# Linux/macOS
sudo journalctl -u agent-rust -n 50

# Windows
Get-EventLog -LogName Application -Source AgentRust -Newest 50
```

---

## 📖 Full Documentation

- [Installation Guide](INSTALLATION.md) - Detailed installation instructions
- [Service Configuration](SERVICE_INSTALLATION.md) - Configure as system service
- [Autostart Configuration](AUTOSTART_CONFIGURATION.md) - Auto-start on boot
- [README](../README.md) - Project overview

---

## 🔒 Security Notice

This agent captures screenshots and tracks window activity for employee monitoring purposes. Ensure:

- Employees are informed about monitoring
- Data collection complies with local privacy laws
- Access to monitoring data is restricted
- Data is encrypted in transit and at rest

---

## 💡 Tips

1. **Use HTTPS** for production servers to encrypt data in transit
2. **Test connection** before installing: `curl http://your-server:8080/api/health`
3. **Check logs** if something doesn't work
4. **Verify checksums** after download: `sha256sum -c checksums.txt`

---

Need help? [Open an issue](https://github.com/ajariapps/agent-employe/issues)
