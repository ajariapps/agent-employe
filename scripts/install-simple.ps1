# Simple One-Line Installer for Employee Monitoring Agent (Rust)
# Usage (PowerShell as Administrator): .\install-simple.ps1 <server-url>
# Example: .\install-simple.ps1 http://192.168.1.100:8080

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerUrl
)

$ErrorActionPreference = "Stop"
$BinaryPath = "C:\Program Files\AgentRust\agent.exe"
$ServiceName = "AgentRust"
$DisplayName = "Employee Monitoring Agent"

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

# Find the binary
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $scriptDir "..\target\release\agent.exe"

if (-not (Test-Path $source)) {
    $source = Join-Path $scriptDir "..\target\debug\agent.exe"
}

if (-not (Test-Path $source)) {
    Write-Host "Error: Binary not found at target\release\agent.exe or target\debug\agent.exe" -ForegroundColor Red
    Write-Host "Please build the agent first:" -ForegroundColor Yellow
    Write-Host "  cd .. && cargo build --release"
    exit 1
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
    exit 1
}
