# Autostart Configuration Guide

Panduan lengkap untuk membuat Employee Monitoring Agent berjalan otomatis saat sistem boot.

## Ringkasan

Agent akan dikonfigurasi untuk:
- ✅ **Start otomatis** saat sistem boot
- ✅ **Auto-restart** jika crash
- ✅ **Restart otomatis** setelah update
- ✅ **Tetap running** meskipun network down sementara

---

## Linux (systemd)

### Cara 1: Installer Otomatis (Recommended)

```bash
# Build agent
cargo build --release

# Install dengan satu perintah
sudo ./scripts/install-simple.sh http://your-server:8080
```

Installer akan:
- Menginstall binary ke `/usr/local/bin/agent`
- Membuat systemd service
- **Mengaktifkan autostart** (enable)
- Memulai agent segera

### Cara 2: Manual Installation

```bash
# Install binary
sudo cp target/release/agent /usr/local/bin/
sudo chmod +x /usr/local/bin/agent

# Install service file
sudo cp scripts/agent-rust.service /etc/systemd/system/
sudo systemctl daemon-reload

# ENABLE autostart (penting!)
sudo systemctl enable agent-rust

# Start service sekarang
sudo systemctl start agent-rust
```

### Verifikasi Autostart

```bash
# Cek apakah service enabled (akan start on boot)
sudo systemctl is-enabled agent-rust
# Output: enabled

# Cek status service
sudo systemctl status agent-rust

# Test reboot (optional)
sudo reboot
# Setelah reboot, cek:
sudo systemctl status agent-rust
```

### Konfigurasi Autostart yang Digunakan

File `/etc/systemd/system/agent-rust.service`:

```ini
[Unit]
Description=Employee Monitoring Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/agent run --config /etc/agent-rust/config.toml

# Auto-restart configuration
Restart=always        # Selalu restart jika crash
RestartSec=10s       # Tunggu 10 detik sebelum restart

[Install]
WantedBy=multi-user.target  # Start on boot (multi-user mode)
```

**Penting:**
- `Restart=always` - Agent akan restart jika crash, killed, atau exit dengan status apapun
- `WantedBy=multi-user.target` - Systemd akan start service saat boot
- `systemctl enable` - Perintah ini mengaktifkan autostart

### Troubleshooting

```bash
# Jika service tidak start on boot
sudo systemctl enable agent-rust

# Jika service crash terus menerus
sudo journalctl -u agent-rust -n 50 --no-pager

# Reset failure count
sudo systemctl reset-failed agent-rust
sudo systemctl restart agent-rust

# Disable autostart (jika tidak ingin autostart)
sudo systemctl disable agent-rust
```

---

## macOS (launchd)

### Cara 1: Installer Otomatis

```bash
# Build agent
cargo build --release

# Install
sudo ./scripts/install-simple.sh http://your-server:8080
```

### Cara 2: Manual Installation

```bash
# Install binary
sudo cp target/release/agent /usr/local/bin/
sudo chmod +x /usr/local/bin/agent

# Install launchd plist
sudo cp scripts/com.ridwanajari.agent-rust.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# Load service (akan auto-start on boot)
sudo launchctl load /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# Start service sekarang
sudo launchctl start com.ridwanajari.agent-rust
```

### Verifikasi Autostart

```bash
# Cek apakah service loaded
sudo launchctl list | grep agent-rust

# Cek status
sudo launchctl print com.ridwanajari.agent-rust

# Test reboot
sudo reboot
# Setelah reboot, cek:
sudo launchctl list | grep agent-rust
```

### Konfigurasi Autostart yang Digunakan

File `/Library/LaunchDaemons/com.ridwanajari.agent-rust.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ridwanajari.agent-rust</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/agent</string>
        <string>run</string>
        <string>--config</string>
        <string>/Library/Application Support/agent-rust/config.toml</string>
    </array>

    <!-- Start at boot -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Keep alive - auto restart if crashes -->
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>

    <!-- Restart if binary changes -->
    <key>WatchPaths</key>
    <array>
        <string>/usr/local/bin/agent</string>
    </array>
</dict>
</plist>
```

**Penting:**
- `RunAtLoad=true` - Start saat boot/load
- `KeepAlive` dengan `Crashed=true` - Auto-restart jika crash
- Lokasi `/Library/LaunchDaemons/` - System-wide service (start on boot)

### Troubleshooting

```bash
# View logs
log show --predicate 'process == "agent"' --last 1h

# Unload service
sudo launchctl unload /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# Load ulang
sudo launchctl load /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# Force restart
sudo launchctl kickstart -k gui/$(id -u)/com.ridwanajari.agent-rust
```

---

## Windows (Windows Service)

### Cara 1: PowerShell Script

```powershell
# Run PowerShell as Administrator

# Build agent
cargo build --release

# Install
.\scripts\install-simple.ps1 http://your-server:8080
```

### Cara 2: Manual Installation

```powershell
# Copy binary ke Program Files
New-Item -ItemType Directory -Path "C:\Program Files\AgentRust" -Force
Copy-Item target\release\agent.exe "C:\Program Files\AgentRust\"

# Create service using sc.exe
sc.exe create AgentRust `
    binPath= "C:\Program Files\AgentRust\agent.exe run --server-url http://your-server:8080" `
    DisplayName= "Employee Monitoring Agent" `
    start= auto

# Set service description
sc.exe description AgentRust "Cross-platform employee monitoring agent"

# Configure recovery actions (auto-restart)
sc.exe failure AgentRust reset= 300 actions= restart/60000/restart/120000/quit/300000

# Start service
sc.exe start AgentRust
```

### Verifikasi Autostart

```powershell
# Cek status
Get-Service AgentRust

# Cek startup type
Get-WmiObject -Class Win32_Service -Filter "Name='AgentRust'" | Select-Object Name, StartMode

# Output: Auto (berarti autostart enabled)
```

### Konfigurasi Autostart yang Digunakan

- `start= auto` - Service start otomatis saat boot
- `sc.exe failure` dengan `restart/60000` - Restart 60 detik setelah crash
- Service diinstall sebagai system service

### Troubleshooting

```powershell
# Cek service status
Get-Service AgentRust | Format-List *

# View logs in Event Viewer
eventvwr.msc
# Navigate to: Windows Logs → Application → Filter by "AgentRust"

# Manual restart
Restart-Service AgentRust

# Remove service
Remove-Service -Name AgentRust
```

---

## Testing Autostart

### Linux

```bash
# 1. Pastikan service enabled
sudo systemctl is-enabled agent-rust

# 2. Cek status sekarang
sudo systemctl status agent-rust

# 3. Reboot sistem
sudo reboot

# 4. Setelah boot, cek lagi
sudo systemctl status agent-rust
# Harus aktif dan running
```

### macOS

```bash
# 1. Cek service loaded
sudo launchctl list | grep agent-rust

# 2. Reboot
sudo reboot

# 3. Setelah boot, cek lagi
sudo launchctl list | grep agent-rust
# Harus ada di list
```

### Windows

```powershell
# 1. Cek startup type
Get-WmiObject -Class Win32_Service -Filter "Name='AgentRust'" | Select-Object StartMode

# 2. Reboot sistem

# 3. Setelah boot, cek status
Get-Service AgentRust
# Status harus Running
```

---

## Monitoring & Maintenance

### Cek Agent Running

**Linux:**
```bash
# Cek status
sudo systemctl status agent-rust

# Cek process
ps aux | grep agent

# View live logs
sudo journalctl -u agent-rust -f
```

**macOS:**
```bash
# Cek process
ps aux | grep agent

# View logs
log show --predicate 'process == "agent"' --last 1h
```

**Windows:**
```powershell
# Cek status
Get-Service AgentRust

# Cek process
Get-Process agent

# View logs
Get-EventLog -LogName Application -Source AgentRust -Newest 50
```

### Auto-Restart Behavior

Agent akan otomatis restart jika:
- ✅ Crash atau segfault
- ✅ Killed oleh OOM killer
- ✅ Binary di-update (dengan watch path)
- ✅ Network error sementara
- ✅ Configuration error (setelah fix)

Agent TIDAK akan restart jika:
- ❌ Service di-stop manual (`systemctl stop`, `Stop-Service`)
- ❌ Service di-disable (`systemctl disable`)
- ❌ Binary dihapus

---

## Troubleshooting Umum

### Agent tidak start on boot

**Linux:**
```bash
# Cek apakah enabled
sudo systemctl is-enabled agent-rust
# Jika "disabled" atau "masked":
sudo systemctl enable agent-rust

# Cek apakah ada error di boot
sudo journalctl -b -u agent-rust
```

**macOS:**
```bash
# Cek apakah file plist ada
ls -la /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# Load ulang
sudo launchctl unload /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
sudo launchctl load /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
```

**Windows:**
```powershell
# Cek startup type
sc.exe config AgentRust start= auto

# Start manual dulu
sc.exe start AgentRust
```

### Agent restart terus menerus (crash loop)

```bash
# Linux: Cek error logs
sudo journalctl -u agent-rust -n 100 --no-pager

# macOS: Cek crash logs
log show --predicate 'process == "agent"' --last 1h | grep -i error

# Windows: Cek Event Viewer
eventvwr.msc
```

Solusi umum:
- Cek configuration file
- Cek network connectivity ke server
- Cek permissions
- Cek memory/disk space

---

## Security Considerations

### Linux

- Service running sebagai user `agent` (non-root)
- `NoNewPrivileges=true` - Tidak bisa elevate privileges
- `ProtectSystem=strict` - Tidak bisa modify system files
- `PrivateTmp=true` - Isolated /tmp

### macOS

- Service running sebagai root (required untuk screenshot)
- Consider menggunakan non-root user jika tidak perlu screenshot

### Windows

- Service running sebagai Local System
- Consider menggunakan dedicated service account dengan limited permissions

---

## Summary Command Reference

| Task | Linux | macOS | Windows |
|------|-------|-------|---------|
| **Enable autostart** | `sudo systemctl enable agent-rust` | (Auto dengan load) | `sc.exe config AgentRust start= auto` |
| **Disable autostart** | `sudo systemctl disable agent-rust` | `sudo launchctl unload ...` | `sc.exe config AgentRust start= demand` |
| **Start now** | `sudo systemctl start agent-rust` | `sudo launchctl start ...` | `Start-Service AgentRust` |
| **Stop now** | `sudo systemctl stop agent-rust` | `sudo launchctl stop ...` | `Stop-Service AgentRust` |
| **Check status** | `sudo systemctl status agent-rust` | `sudo launchctl list \| grep agent` | `Get-Service AgentRust` |
| **View logs** | `sudo journalctl -u agent-rust -f` | `log show --predicate 'process == "agent"'` | `Get-EventLog -LogName Application` |

---

## Additional Resources

- **Linux systemd documentation**: `man systemd.service`
- **macOS launchd documentation**: `man launchd.plist`
- **Windows Service documentation: https://docs.microsoft.com/en-us/windows/win32/services/about-services

---

## Support

Jika ada masalah dengan autostart:
1. Cek logs untuk error messages
2. Pastikan service enabled/loaded
3. Test manual start dulu
4. Cek file permissions
5. Verify network connectivity

For more help: https://gitlab.ajari.app/ridwanajari/agent-emp/-/issues
