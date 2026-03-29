# Universal Windows CLI Installer for Employee Monitoring Agent (Rust)
# Supported: Windows 10/11 (x64)
#
# Usage:
#   Method 1 (Parameter):    irm https://.../install.ps1 | iex; Install-Agent -ServerUrl http://server:8080
#   Method 2 (Environment):  $env:AGENT_SERVER_URL="http://server:8080"; irm https://.../install.ps1 | iex
#   Method 3 (Interactive):  irm https://.../install.ps1 | iex
#
# Environment Variables:
#   AGENT_SERVER_URL    - Server URL (overrides prompt)
#   AGENT_INSTALL_DIR   - Installation directory (default: C:\Program Files\AgentRust)
#   GITHUB_TOKEN        - GitHub token for private repos (optional)

param(
    [string]$ServerUrl = ""
)

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

#######################################
# Configuration
#######################################
$GITHUB_REPO = "ajariapps/agent-employe"
$INSTALL_DIR = if ($env:AGENT_INSTALL_DIR) { $env:AGENT_INSTALL_DIR } else { "C:\Program Files\AgentRust" }
$BINARY_NAME = "agent.exe"
$SERVICE_NAME = "AgentRust"
$SERVICE_DISPLAY_NAME = "Employee Monitoring Agent"

#######################################
# Helper Functions
#######################################
function Write-Header {
    param([string]$Message)
    $line = "━━" * 40
    Write-Host $line -ForegroundColor Blue
    Write-Host $Message -ForegroundColor Blue
    Write-Host $line -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[⚠] $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "[ℹ] $Message" -ForegroundColor Cyan
}

#######################################
# System Detection
#######################################
function Get-OSArchitecture {
    $arch = [System.Environment]::GetEnvironmentVariable("PROCESSOR_ARCHITECTURE")
    if ($arch -eq "AMD64") {
        return "x64"
    } elseif ($arch -eq "ARM64") {
        return "arm64"
    } else {
        return "unknown"
    }
}

function Get-PlatformFilename {
    param([string]$Arch)

    if ($Arch -eq "x64") {
        return "agent-rust-windows-x64.tar.gz"
    } elseif ($Arch -eq "arm64") {
        return "agent-rust-windows-arm64.tar.gz"
    } else {
        return ""
    }
}

#######################################
# Download Functions
#######################################
function Get-LatestVersion {
    $url = "https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

    try {
        $headers = @{}
        if ($env:GITHUB_TOKEN) {
            $headers["Authorization"] = "token $($env:GITHUB_TOKEN)"
        }

        $response = Invoke-RestMethod -Uri $url -Headers $headers
        return $response.tag_name
    } catch {
        Write-Error "Failed to fetch latest version from GitHub"
        return $null
    }
}

function Download-Binary {
    param(
        [string]$Version,
        [string]$Filename
    )

    $url = "https://github.com/${GITHUB_REPO}/releases/download/${Version}/${Filename}"
    $outputPath = Join-Path $env:TEMP $Filename

    Write-Info "Downloading ${Filename}..."

    try {
        Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
        Write-Success "Downloaded successfully"
        return $outputPath
    } catch {
        Write-Error "Failed to download from ${url}"
        Write-Info "Please check:"
        Write-Host "  1. Your internet connection"
        Write-Host "  2. The release exists at: https://github.com/${GITHUB_REPO}/releases"
        return $null
    }
}

function Download-Checksums {
    param([string]$Version)

    $url = "https://github.com/${GITHUB_REPO}/releases/download/${Version}/checksums.txt"
    $outputPath = Join-Path $env:TEMP "checksums.txt"

    try {
        Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
        return $outputPath
    } catch {
        Write-Warning "Could not download checksums.txt"
        return $null
    }
}

function Test-Checksum {
    param(
        [string]$Archive,
        [string]$ChecksumsFile
    )

    if ([string]::IsNullOrEmpty($ChecksumsFile) -or !(Test-Path $ChecksumsFile)) {
        Write-Warning "Checksum verification skipped (no checksums file)"
        return $true
    }

    $filename = Split-Path $Archive -Leaf
    $expectedChecksum = (Get-Content $ChecksumsFile | Select-String $filename).Line.Split()[0]

    if ([string]::IsNullOrEmpty($expectedChecksum)) {
        Write-Warning "Checksum not found for ${filename}"
        return $true
    }

    Write-Info "Verifying checksum..."

    # Calculate SHA256
    $actualChecksum = (Get-FileHash -Path $Archive -Algorithm SHA256).Hash.ToLower()

    if ($actualChecksum -eq $expectedChecksum.ToLower()) {
        Write-Success "Checksum verified"
        return $true
    } else {
        Write-Error "Checksum mismatch!"
        Write-Host "  Expected: ${expectedChecksum}"
        Write-Host "  Actual:   ${actualChecksum}"
        return $false
    }
}

function Expand-AgentArchive {
    param([string]$Archive)

    Write-Info "Extracting binary..."

    $extractDir = Join-Path $env:TEMP "agent-extract"
    if (Test-Path $extractDir) {
        Remove-Item -Path $extractDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    try {
        # Use tar (Windows 10+ has built-in tar support)
        tar -xzf $Archive -C $extractDir
        Write-Success "Extracted successfully"

        $binaryPath = Join-Path $extractDir $BINARY_NAME
        if (Test-Path $binaryPath) {
            return $binaryPath
        } else {
            Write-Error "Binary not found in archive"
            return $null
        }
    } catch {
        Write-Error "Failed to extract archive: $_"
        return $null
    }
}

#######################################
# Installation Functions
#######################################
function Install-Binary {
    param([string]$Source)

    Write-Info "Installing binary to ${INSTALL_DIR}..."

    try {
        # Create install directory
        if (!(Test-Path $INSTALL_DIR)) {
            New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
        }

        # Copy binary
        Copy-Item -Path $Source -Destination (Join-Path $INSTALL_DIR $BINARY_NAME) -Force
        Write-Success "Binary installed to ${INSTALL_DIR}\${BINARY_NAME}"

        return $true
    } catch {
        Write-Error "Failed to install binary: $_"
        return $false
    }
}

function Install-Service {
    param([string]$ServerUrl)

    Write-Info "Creating Windows service..."

    try {
        # Remove existing service if it exists
        $existingService = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
        if ($existingService) {
            Write-Warning "Removing existing service..."
            Stop-Service -Name $SERVICE_NAME -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            sc.exe delete $SERVICE_NAME | Out-Null
            Start-Sleep -Seconds 2
        }

        # Create service
        $binaryPath = (Join-Path $INSTALL_DIR $BINARY_NAME).Replace('\', '\\')
        $serviceCommand = "`"${binaryPath}`" run --server-url `"$ServerUrl`""

        sc.exe create $SERVICE_NAME binPath= $serviceCommand DisplayName= "$SERVICE_DISPLAY_NAME" start= auto | Out-Null
        sc.exe description $SERVICE_NAME "Cross-platform employee monitoring agent" | Out-Null
        sc.exe config $SERVICE_NAME obj= LocalSystem | Out-Null

        # Set environment variable
        sc.exe config $SERVICE_NAME Env= "AGENT_SERVER_URL=$ServerUrl" | Out-Null

        Write-Success "Service created"
        return $true
    } catch {
        Write-Error "Failed to create service: $_"
        return $false
    }
}

function Start-AgentService {
    Write-Info "Starting service..."

    try {
        Start-Service -Name $SERVICE_NAME
        Start-Sleep -Seconds 2

        $service = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Success "Service started successfully"
            return $true
        } else {
            Write-Warning "Service may not have started. Check with: Get-Service $SERVICE_NAME"
            return $false
        }
    } catch {
        Write-Error "Failed to start service: $_"
        return $false
    }
}

#######################################
# Server URL Prompt
#######################################
function Get-ServerUrl {
    param([string]$ProvidedUrl)

    # Check parameter first
    if (![string]::IsNullOrEmpty($ProvidedUrl)) {
        return $ProvidedUrl
    }

    # Check environment variable
    if (![string]::IsNullOrEmpty($env:AGENT_SERVER_URL)) {
        return $env:AGENT_SERVER_URL
    }

    # Interactive prompt
    while ($true) {
        $url = Read-Host "Enter server URL (e.g., http://192.168.1.100:8080)"

        if (![string]::IsNullOrEmpty($url)) {
            return $url
        } else {
            Write-Error "Server URL cannot be empty"
        }
    }
}

#######################################
# Main Installation Flow
#######################################
function Install-Agent {
    param([string]$ServerUrl = "")

    Clear-Host
    Write-Header "Employee Monitoring Agent Installer"

    # Check administrator privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!$isAdmin) {
        Write-Error "This script must be run as Administrator"
        Write-Info "Right-click PowerShell and select 'Run as Administrator'"
        return
    }

    # Detect architecture
    $arch = Get-OSArchitecture
    if ($arch -eq "unknown") {
        Write-Error "Unsupported architecture"
        return
    }
    Write-Success "Detected: Windows (${arch})"

    # Get platform filename
    $filename = Get-PlatformFilename -Arch $arch
    if ([string]::IsNullOrEmpty($filename)) {
        Write-Error "Could not determine download filename"
        return
    }

    # Get server URL
    Write-Host
    $serverUrl = Get-ServerUrl -ProvidedUrl $ServerUrl
    Write-Success "Server URL: ${serverUrl}"

    # Get latest version
    Write-Host
    Write-Info "Fetching latest release version..."
    $version = Get-LatestVersion

    if ([string]::IsNullOrEmpty($version)) {
        Write-Error "Failed to fetch latest version"
        return
    }
    Write-Success "Latest version: ${version}"

    # Download binary
    Write-Host
    $archivePath = Download-Binary -Version $version -Filename $filename
    if ([string]::IsNullOrEmpty($archivePath)) {
        return
    }

    # Download checksums
    $checksumsPath = Download-Checksums -Version $version

    # Verify checksum
    Write-Host
    if (!(Test-Checksum -Archive $archivePath -ChecksumsFile $checksumsPath)) {
        return
    }

    # Extract binary
    $binaryPath = Expand-AgentArchive -Archive $archivePath
    if ([string]::IsNullOrEmpty($binaryPath)) {
        return
    }

    # Install binary
    Write-Host
    if (!(Install-Binary -Source $binaryPath)) {
        return
    }

    # Create service
    Write-Host
    if (!(Install-Service -ServerUrl $serverUrl)) {
        return
    }

    # Start service
    Write-Host
    Start-AgentService | Out-Null

    # Cleanup
    Write-Host
    Write-Info "Cleaning up temporary files..."
    $extractDir = Join-Path $env:TEMP "agent-extract"
    if (Test-Path $extractDir) {
        Remove-Item -Path $extractDir -Recurse -Force
    }
    if (Test-Path $archivePath) {
        Remove-Item -Path $archivePath -Force
    }
    if ($checksumsPath -and (Test-Path $checksumsPath)) {
        Remove-Item -Path $checksumsPath -Force
    }
    Write-Success "Cleanup complete"

    # Success message
    Write-Host
    Write-Header "Installation Complete!"
    Write-Host
    Write-Host "Server URL:      " -NoNewline
    Write-Host "${serverUrl}" -ForegroundColor Green
    Write-Host "Version:         " -NoNewline
    Write-Host "${version}" -ForegroundColor Green
    Write-Host "Binary:          " -NoNewline
    Write-Host "${INSTALL_DIR}\${BINARY_NAME}" -ForegroundColor Green
    Write-Host
    Write-Host "Useful commands:"
    Write-Host "  Check status:  Get-Service ${SERVICE_NAME}"
    Write-Host "  View logs:     Get-EventLog -LogName Application -Source ${SERVICE_NAME} -Newest 50"
    Write-Host "  Stop agent:    Stop-Service ${SERVICE_NAME}"
    Write-Host "  Start agent:   Start-Service ${SERVICE_NAME}"
    Write-Host
    Write-Host "Uninstall:"
    Write-Host "  Stop-Service ${SERVICE_NAME} -Force"
    Write-Host "  Remove-Service ${SERVICE_NAME}"
    Write-Host "  Remove-Item '${INSTALL_DIR}' -Recurse -Force"
    Write-Host
    Write-Host "━━" * 40 -ForegroundColor Blue
}

# Export function for use after script execution
Export-ModuleMember -Function Install-Agent

# Auto-run if server URL is provided as parameter
if (![string]::IsNullOrEmpty($ServerUrl)) {
    Install-Agent -ServerUrl $ServerUrl
} elseif (![string]::IsNullOrEmpty($env:AGENT_SERVER_URL)) {
    Install-Agent -ServerUrl $env:AGENT_SERVER_URL
} else {
    # Make function available for interactive use
    Write-Info "To install, run: Install-Agent"
    Write-Info "Example: Install-Agent -ServerUrl http://server:8080"
}
