# Build Script for Windows .exe Installer
# Requires NSIS to be installed (https://nsis.sourceforge.io/Download)

param(
    [string]$AgentExePath = "",
    [string]$OutputDir = ".\output"
)

$ErrorActionPreference = "Stop"

# Colors
$Green = @{
    ForegroundColor = "Green"
}
$Red = @{
    ForegroundColor = "Red"
}
$Yellow = @{
    ForegroundColor = "Yellow"
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n[Step] $Message" @Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[Info] $Message" @Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[Error] $Message" @Red
}

function Test-Command {
    param([string]$Command)
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Main script
Clear-Host
Write-Host "======================================"
Write-Host "Agent Windows Installer Build Script"
Write-Host "======================================"

# Check if NSIS is installed
Write-Step "Checking NSIS installation..."

$nsisPath = "C:\Program Files (x86)\NSIS\makensis.exe"
if (!(Test-Path $nsisPath)) {
    $nsisPath = "C:\Program Files\NSIS\makensis.exe"
}

if (!(Test-Path $nsisPath)) {
    Write-Error "NSIS not found!"
    Write-Info "Please install NSIS from: https://nsis.sourceforge.io/Download"
    exit 1
}

Write-Info "NSIS found at: $nsisPath"

# Check agent.exe
Write-Step "Locating agent.exe..."

if ([string]::IsNullOrEmpty($AgentExePath)) {
    # Try to find agent.exe in common locations
    $possiblePaths = @(
        ".\target\release\agent.exe",
        ".\target\debug\agent.exe",
        "..\target\release\agent.exe",
        "..\target\debug\agent.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $AgentExePath = Resolve-Path $path
            break
        }
    }
}

if ([string]::IsNullOrEmpty($AgentExePath) -or !(Test-Path $AgentExePath)) {
    Write-Error "agent.exe not found!"
    Write-Info "Please build the agent first: cargo build --release"
    Write-Info "Or specify path: .\build-installer.ps1 -AgentExePath path\to\agent.exe"
    exit 1
}

Write-Info "Found agent.exe at: $AgentExePath"

# Copy agent.exe to installer directory
Write-Step "Preparing installer files..."

$installerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Copy-Item -Path $AgentExePath -Destination "$installerDir\agent.exe" -Force
Write-Info "Copied agent.exe to installer directory"

# Create output directory
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Build installer
Write-Step "Building installer with NSIS..."

$nsiScript = Join-Path $installerDir "agent-setup.nsi"
$outputExe = Join-Path (Resolve-Path $OutputDir) "Agent-Setup.exe"

try {
    $process = Start-Process -FilePath $nsisPath -ArgumentList "`"$nsiScript`" /DOUTPUT_FILE=`"$outputExe`"" -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -eq 0) {
        Write-Host "`n======================================" @Green
        Write-Host "Build Successful!" @Green
        Write-Host "======================================" @Green
        Write-Host "`nOutput: $outputExe"
        Write-Host "Size: $((Get-Item $outputExe).Length / 1MB) MB`n"
    } else {
        throw "NSIS build failed with exit code: $($process.ExitCode)"
    }
} catch {
    Write-Error "Build failed: $_"
    exit 1
} finally {
    # Cleanup
    Write-Step "Cleaning up..."
    $agentCopy = Join-Path $installerDir "agent.exe"
    if (Test-Path $agentCopy) {
        Remove-Item -Path $agentCopy -Force
        Write-Info "Removed temporary agent.exe copy"
    }
}

Write-Host "`nTo test the installer, run: $outputExe"
