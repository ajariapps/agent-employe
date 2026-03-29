# Simple One-Line Installer for Employee Monitoring Agent (Rust)
# Usage (PowerShell as Administrator): .\install-simple.ps1 <server-url>
# Example: .\install-simple.ps1 http://192.168.1.100:8080

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerUrl
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BinaryPath = "C:\Program Files\AgentRust\agent.exe"
$ServiceName = "AgentRust"
$DisplayName = "Employee Monitoring Agent"
$GITHUB_REPO = "ajariapps/agent-employe"

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

#######################################
# Helper Functions
#######################################
function Get-Architecture {
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

function Download-FromGitHub {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host "Binary not found locally. Downloading from GitHub..." -ForegroundColor Blue
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host ""

    # Detect architecture
    $arch = Get-Architecture
    if ($arch -eq "unknown") {
        Write-Host "Error: Unsupported architecture" -ForegroundColor Red
        return $null
    }

    Write-Host "Detected: Windows ($arch)"

    # Get filename
    $filename = Get-PlatformFilename -Arch $arch
    if ([string]::IsNullOrEmpty($filename)) {
        Write-Host "Error: Could not determine download filename" -ForegroundColor Red
        return $null
    }

    # Get latest version
    Write-Host "Fetching latest version..."
    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
        $version = $response.tag_name
        Write-Host "Latest version: $version"
    } catch {
        Write-Host "Error: Could not fetch latest version" -ForegroundColor Red
        return $null
    }

    # Download
    $downloadUrl = "https://github.com/${GITHUB_REPO}/releases/download/${version}/${filename}"
    Write-Host "Downloading from: $downloadUrl"

    $tempDir = Join-Path $env:TEMP "agent-download-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $archivePath = Join-Path $tempDir $filename

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing
        Write-Host "Download successful" -ForegroundColor Green
    } catch {
        Write-Host "Error: Download failed" -ForegroundColor Red
        return $null
    }

    # Extract
    Write-Host "Extracting..."
    try {
        $extractDir = Join-Path $tempDir "extracted"
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

        Push-Location $extractDir
        tar -xzf $archivePath
        Pop-Location

        $binaryPath = Join-Path $extractDir "agent.exe"

        if (Test-Path $binaryPath) {
            # Register cleanup
            Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            } -ErrorAction SilentlyContinue | Out-Null

            return $binaryPath
        } else {
            Write-Host "Error: Binary not found in archive" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "Error: Failed to extract archive" -ForegroundColor Red
        return $null
    }
}

# Find the binary (try release first, then debug, then download)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $scriptDir "..\target\release\agent.exe"

if (-not (Test-Path $source)) {
    $source = Join-Path $scriptDir "..\target\debug\agent.exe"
}

if (-not (Test-Path $source)) {
    $source = Download-FromGitHub
    if ([string]::IsNullOrEmpty($source) -or -not (Test-Path $source)) {
        Write-Host ""
        Write-Host "Error: Could not find or download binary" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please do one of the following:" -ForegroundColor Yellow
        Write-Host "  1. Build the agent: cd .. ; cargo build --release"
        Write-Host "  2. Check your internet connection"
        Write-Host "  3. Download manually from: https://github.com/${GITHUB_REPO}/releases"
        exit 1
    }
    $downloaded = $true
} else {
    $downloaded = $false
}

Write-Host "Installing Employee Monitoring Agent (Rust)..." -ForegroundColor Green
Write-Host ""

# Create directory
Write-Host "Installing binary to $BinaryPath"
$installDir = Split-Path -Parent $BinaryPath
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}
Copy-Item $source $BinaryPath -Force
Write-Host "Binary installed" -ForegroundColor Green

# Remove existing service if it exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Removing existing service..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

# Create service
Write-Host "Creating Windows service"
$binaryPathEscaped = $BinaryPath -replace '\\', '\\'
$serviceCommand = "`"$binaryPathEscaped`" run --server-url `"$ServerUrl`""

sc.exe create $ServiceName binPath= $serviceCommand DisplayName= "$DisplayName" start= auto | Out-Null
sc.exe description $ServiceName "Cross-platform employee monitoring agent" | Out-Null
sc.exe config $ServiceName obj= LocalSystem | Out-Null

# Set environment variable for server URL
sc.exe config $ServiceName Env= "AGENT_SERVER_URL=$ServerUrl" | Out-Null

Write-Host "Service created" -ForegroundColor Green

# Start service
Write-Host "Starting service"
Start-Service -Name $ServiceName

# Wait a bit and check status
Start-Sleep -Seconds 2

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq 'Running') {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "Agent installed and started successfully!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "Server URL: $ServerUrl"
    Write-Host ""
    Write-Host "Useful commands:"
    Write-Host "  Check status:  Get-Service $ServiceName"
    Write-Host "  View logs:     Get-EventLog -LogName Application -Source $ServiceName -Newest 50"
    Write-Host "  Stop agent:    Stop-Service $ServiceName"
    Write-Host "  Start agent:   Start-Service $ServiceName"
    Write-Host ""
    Write-Host "Uninstall:"
    Write-Host "  Stop-Service $ServiceName -Force"
    Write-Host "  sc.exe delete $ServiceName"
    Write-Host "  Remove-Item '$BinaryPath' -Force"
    Write-Host "  Remove-Item 'C:\ProgramData\AgentRust' -Recurse -Force -ErrorAction SilentlyContinue"
} else {
    Write-Host ""
    Write-Host "Warning: Service may not have started successfully" -ForegroundColor Red
    Write-Host "Check status with: Get-Service $ServiceName"
    Write-Host "Check Event Logs for errors"

    # Cleanup if downloaded
    if ($downloaded) {
        if ($source -and (Test-Path (Split-Path $source -Parent))) {
            Remove-Item -Path (Split-Path $source -Parent) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    exit 1
}
