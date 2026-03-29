# Panduan Instalasi Agent Employee Monitoring

Panduan lengkap untuk menginstal Employee Monitoring Agent di Linux, macOS, dan Windows.

## Daftar Isi

- [Persyaratan Sistem](#persyaratan-sistem)
- [Instalasi di Linux](#instalasi-di-linux)
- [Instalasi di macOS](#instalasi-di-macos)
- [Instalasi di Windows](#instalasi-di-windows)
- [Konfigurasi](#konfigurasi)
- [Manajemen Service](#manajemen-service)
- [Troubleshooting](#troubleshooting)

---

## Persyaratan Sistem

### Umum
- RAM: Minimal 512 MB
- Disk Space: Minimal 100 MB
- Koneksi internet aktif

### Linux
- Distribusi: Ubuntu 20.04+, Debian 11+, CentOS 8+, atau distro lainnya
- Display Server: X11 atau Wayland
- Init System: systemd (untuk mode service)
- Dependencies: libx11, libxrandr, libxext

### macOS
- Versi: macOS 10.15 (Catalina) atau lebih baru
- Architecture: x86_64 atau arm64 (Apple Silicon)

### Windows
- Versi: Windows 10 atau lebih baru
- Architecture: x64
- PowerShell 5.1 atau lebih baru

---

## Instalasi di Linux

### Metode 1: Instalasi Cepat (Recommended)

Cara termudah untuk menginstal agent dengan satu perintah:

```bash
# 1. Download dan extract release
wget https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-linux-x86_64.tar.gz
tar xzf agent-rust-linux-x86_64.tar.gz

# 2. Jalankan installer
sudo ./scripts/install-simple.sh http://your-server:8080
```

Installer akan:
- Menginstal binary ke `/usr/local/bin/agent`
- Membuat systemd service
- **Mengaktifkan autostart** (agent akan otomatis start saat boot)
- Mendaftarkan agent ke server secara otomatis
- Memulai monitoring

### Metode 2: Build dari Source

```bash
# 1. Install Rust dan dependencies
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
sudo apt-get update
sudo apt-get install -y build-essential libx11-dev libxrandr-dev libxext-dev

# 2. Clone repository dan build
git clone https://github.com/ajariapps/agent-employe.git
cd agent-employe
cargo build --release

# 3. Jalankan installer
sudo ./scripts/install-simple.sh http://your-server:8080
```

### Metode 3: Manual Installation

```bash
# 1. Copy binary
sudo cp target/release/agent /usr/local/bin/
sudo chmod +x /usr/local/bin/agent

# 2. Buat directory konfigurasi
sudo mkdir -p /etc/agent-rust
sudo cp config.example.toml /etc/agent-rust/config.toml

# 3. Edit konfigurasi
sudo nano /etc/agent-rust/config.toml
```

Isi konfigurasi:
```toml
[server]
url = "http://your-server:8080"

[agent]
hostname = "nama-komputer"

[intervals]
heartbeat_secs = 30
activity_secs = 60
screenshot_secs = 300
```

```bash
# 4. Install sebagai service
sudo ./scripts/install-service.sh

# 5. Start service
sudo systemctl enable agent-rust
sudo systemctl start agent-rust
```

---

## Instalasi di macOS

### Metode 1: Instalasi Cepat (Recommended)

```bash
# 1. Download dan extract release
curl -L https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-macos-x86_64.tar.gz -o agent-rust.tar.gz
tar xzf agent-rust.tar.gz

# 2. Jalankan installer
sudo ./scripts/install-simple.sh http://your-server:8080
```

### Metode 2: Build dari Source

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. Install Xcode Command Line Tools
xcode-select --install

# 3. Clone dan build
git clone https://github.com/ajariapps/agent-employe.git
cd agent-employe
cargo build --release

# 4. Install
sudo cp target/release/agent /usr/local/bin/
sudo chmod +x /usr/local/bin/agent

# 5. Setup launchd service
sudo cp scripts/com.ridwanajari.agent-rust.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
```

### Metode 3: Manual Installation

```bash
# 1. Copy binary
sudo cp target/release/agent /usr/local/bin/
sudo chmod +x /usr/local/bin/agent

# 2. Buat directory konfigurasi
sudo mkdir -p /etc/agent-rust
sudo cp config.example.toml /etc/agent-rust/config.toml

# 3. Edit konfigurasi
sudo nano /etc/agent-rust/config.toml

# 4. Grant permissions (penting untuk macOS)
# System Preferences > Security & Privacy > Privacy > Screen Recording
# Add dan allow "agent" application

# 5. Test run
agent run --server-url http://your-server:8080 --foreground
```

---

## Instalasi di Windows

### Metode 1: Instalasi Cepat (Recommended)

Buka PowerShell sebagai Administrator:

```powershell
# 1. Download dan extract
Invoke-WebRequest -Uri "https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-windows-x64.tar.gz" -OutFile "agent-rust.tar.gz"
tar -xzf agent-rust.tar.gz

# 2. Jalankan installer
.\scripts\install-simple.ps1 http://your-server:8080
```

### Metode 2: Build dari Source

```powershell
# 1. Install Rustup
# Download dari https://rustup.rs/

# 2. Install Visual Studio Build Tools
# Download dari https://visualstudio.microsoft.com/downloads/

# 3. Clone dan build
git clone https://github.com/ajariapps/agent-employe.git
cd agent-employe
cargo build --release

# 4. Copy ke Program Files
copy target\release\agent.exe "C:\Program Files\Agent\"

# 5. Install sebagai Windows Service
.\scripts\install-service.ps1
```

### Metode 3: Manual Installation

```powershell
# 1. Buat directory
New-Item -ItemType Directory -Path "C:\Program Files\Agent" -Force
New-Item -ItemType Directory -Path "C:\ProgramData\Agent" -Force

# 2. Copy binary dan config
copy target\release\agent.exe "C:\Program Files\Agent\"
copy config.example.toml "C:\ProgramData\Agent\config.toml"

# 3. Edit konfigurasi
notepad "C:\ProgramData\Agent\config.toml"
```

Isi konfigurasi:
```toml
[server]
url = "http://your-server:8080"

[agent]
hostname = "nama-komputer"

[logging]
dir = "C:\ProgramData\Agent\logs"
console = true
file = true
```

```powershell
# 4. Test run
& "C:\Program Files\Agent\agent.exe" run --server-url http://your-server:8080 --foreground

# 5. Install sebagai service
.\scripts\install-service.ps1
```

---

## Konfigurasi

### File Konfigurasi

Agent menggunakan file konfigurasi TOML. Lokasi default:

- **Linux/macOS**: `/etc/agent-rust/config.toml`
- **Windows**: `C:\ProgramData\Agent\config.toml`

### Environment Variables

Anda juga bisa menggunakan environment variables:

```bash
# Linux/macOS
export AGENT_SERVER_URL="http://your-server:8080"
export AGENT_LOG_LEVEL="debug"
export AGENT_API_TOKEN="your-token"

# Windows (PowerShell)
$env:AGENT_SERVER_URL="http://your-server:8080"
$env:AGENT_LOG_LEVEL="debug"
$env:AGENT_API_TOKEN="your-token"
```

### Opsi Konfigurasi Utama

```toml
[server]
url = "http://your-server:8080"        # Server URL
timeout_secs = 30                        # Request timeout
max_retries = 3                          # Jumlah retry

[intervals]
heartbeat_secs = 30                      # Heartbeat interval (min: 10)
activity_secs = 60                       # Activity tracking (min: 5)
screenshot_secs = 300                    # Screenshot interval (min: 30)

[thresholds]
idle_secs = 300                          # Idle threshold (detik)

[logging]
level = "info"                           # trace, debug, info, warn, error
format = "json"                          # json, pretty, compact
console = true                           # Log ke console
file = true                              # Log ke file

[screenshot]
format = "png"                           # png atau jpeg
capture_all_monitors = false             # Capture semua monitor
compress = true                          # Compress sebelum upload
```

---

## Manajemen Service

### Linux (systemd)

```bash
# Cek status
sudo systemctl status agent-rust

# Start service
sudo systemctl start agent-rust

# Stop service
sudo systemctl stop agent-rust

# Restart service
sudo systemctl restart agent-rust

# Enable autostart
sudo systemctl enable agent-rust

# Disable autostart
sudo systemctl disable agent-rust

# View logs
sudo journalctl -u agent-rust -f

# View 100 log terakhir
sudo journalctl -u agent-rust -n 100
```

### macOS (launchd)

```bash
# Start service
sudo launchctl start com.ridwanajari.agent-rust

# Stop service
sudo launchctl stop com.ridwanajari.agent-rust

# Restart service
sudo launchctl kickstart -k gui/$(id -u)/com.ridwanajari.agent-rust

# View logs
log show --predicate 'process == "agent"' --last 1h
```

### Windows (Service)

```powershell
# Cek status
Get-Service AgentRust

# Start service
Start-Service AgentRust

# Stop service
Stop-Service AgentRust

# Restart service
Restart-Service AgentRust

# View logs
Get-EventLog -LogName Application -Source AgentRust -Newest 50

# Service manager
services.msc
```

---

## Troubleshooting

### Agent tidak bisa start

**Linux:**
```bash
# Cek logs
sudo journalctl -u agent-rust -n 50

# Cek service status
sudo systemctl status agent-rust -l
```

**macOS:**
```bash
# Cek logs
log show --predicate 'process == "agent"' --last 1h

# Cek launchd status
sudo launchctl list | grep agent
```

**Windows:**
```powershell
# Cek Event Viewer
eventvwr.msc

# Cek service
Get-Service AgentRust | Format-List *
```

### Permission denied

**Linux/macOS:**
```bash
# Jalankan dengan sudo
sudo agent run

# Atau set permission yang benar
sudo chown -R $USER /var/lib/agent-rust
sudo chown -R $USER /var/log/agent-rust
```

**Windows:**
```powershell
# Run PowerShell as Administrator
# Right-click > Run as Administrator
```

### Screenshot gagal

**Linux:**
```bash
# Pastikan DISPLAY variable set
echo $DISPLAY
# Export jika perlu
export DISPLAY=:0

# Cek X11 permission
xhost +
```

**macOS:**
- Buka **System Preferences > Security & Privacy > Privacy > Screen Recording**
- Tambahkan dan allow aplikasi **agent**

**Windows:**
- Jalankan agent sebagai Administrator
- Pastikan session user aktif (tidak di RDP session yang inactive)

### Connection refused

```bash
# Cek koneksi ke server
curl http://your-server:8080/api/health

# Cek firewall
sudo ufw status  # Linux
# Windows Firewall settings

# Ping server
ping your-server.com
```

### Agent tidak register ke server

1. Pastikan server URL benar di config
2. Cek apakah server online
3. Cek network connectivity
4. Lihat logs untuk detail error

### Update agent

**Linux:**
```bash
# Stop service
sudo systemctl stop agent-rust

# Download version baru
wget https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-linux-x86_64.tar.gz
tar xzf agent-rust-linux-x86_64.tar.gz

# Replace binary
sudo cp agent /usr/local/bin/

# Start service
sudo systemctl start agent-rust
```

**macOS:**
```bash
# Stop service
sudo launchctl stop com.ridwanajari.agent-rust

# Download dan install
curl -L https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-macos-x86_64.tar.gz -o agent-rust.tar.gz
tar xzf agent-rust.tar.gz
sudo cp agent /usr/local/bin/

# Start service
sudo launchctl start com.ridwanajari.agent-rust
```

**Windows:**
```powershell
# Stop service
Stop-Service AgentRust

# Download dan install
Invoke-WebRequest -Uri "https://github.com/ajariapps/agent-employe/releases/latest/download/agent-rust-windows-x64.tar.gz" -OutFile "agent-rust.tar.gz"
tar -xzf agent-rust.tar.gz
copy agent.exe "C:\Program Files\Agent\"

# Start service
Start-Service AgentRust
```

### Uninstall agent

**Linux:**
```bash
# Stop dan disable service
sudo systemctl stop agent-rust
sudo systemctl disable agent-rust

# Remove service
sudo rm /etc/systemd/system/agent-rust.service
sudo systemctl daemon-reload

# Remove binary
sudo rm /usr/local/bin/agent

# Remove config dan data (optional)
sudo rm -rf /etc/agent-rust
sudo rm -rf /var/lib/agent-rust
sudo rm -rf /var/log/agent-rust
```

**macOS:**
```bash
# Stop dan unload service
sudo launchctl stop com.ridwanajari.agent-rust
sudo launchctl unload /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist

# Remove files
sudo rm /Library/LaunchDaemons/com.ridwanajari.agent-rust.plist
sudo rm /usr/local/bin/agent
sudo rm -rf /etc/agent-rust
```

**Windows:**
```powershell
# Stop dan remove service
Stop-Service AgentRust
Remove-Service AgentRust

# Remove files
Remove-Item "C:\Program Files\Agent" -Recurse -Force
Remove-Item "C:\ProgramData\Agent" -Recurse -Force
```

---

## Support

Jika Anda mengalami masalah:

1. Cek logs untuk detail error
2. Pastikan semua persyaratan sistem terpenuhi
3. Verify konfigurasi sudah benar
4. Cek koneksi ke server

Untuk bantuan lebih lanjut:
- Documentation: [README.md](../README.md)
- Autostart Configuration: [AUTOSTART_CONFIGURATION.md](AUTOSTART_CONFIGURATION.md)
- Service Installation: [SERVICE_INSTALLATION.md](SERVICE_INSTALLATION.md)
- Issues: [GitHub Issues](https://github.com/ajariapps/agent-employe/issues)
- Email: support@yourcompany.com
