# Windows Service Installation Script for Employee Monitoring Agent
# Run as Administrator

param(
    [Parameter(Mandatory=$false)]
    [string]$BinaryPath = "C:\Program Files\AgentRust\agent.exe",

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "C:\ProgramData\AgentRust\config.toml",

    [Parameter(Mandatory=$false)]
    [switch]$Uninstall
)

$ServiceName = "AgentRust"
$DisplayName = "Employee Monitoring Agent"
$Description = "Cross-platform employee monitoring agent"

function Install-Service {
    Write-Host "Installing Employee Monitoring Agent service..." -ForegroundColor Green

    # Check if running as Administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run as Administrator"
        exit 1
    }

    # Check if binary exists
    if (-not (Test-Path $BinaryPath)) {
        Write-Error "Binary not found at: $BinaryPath"
        exit 1
    }

    # Create configuration directory if it doesn't exist
    $configDir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Create default config if it doesn't exist
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "Creating default configuration at $ConfigPath" -ForegroundColor Yellow

        $defaultConfig = @"
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
"@
        $defaultConfig | Out-File -FilePath $ConfigPath -Encoding UTF8
    }

    # Check if service already exists
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Write-Warning "Service '$ServiceName' already exists. Removing..."
        Remove-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }

    # Create the service using sc.exe
    $serviceArgs = @{
        Name = $ServiceName
        BinaryPathName = "`"$BinaryPath`" run --config `"$ConfigPath`""
        DisplayName = $DisplayName
        Description = $Description
        StartupType = "Automatic"
    }

    Write-Host "Creating service: $($serviceArgs.Name)" -ForegroundColor Cyan
    New-Service @serviceArgs

    # Configure service recovery
    Write-Host "Configuring service recovery..." -ForegroundColor Cyan
    & sc.exe failure $ServiceName reset= 300 reset= 600 reset= 900 actions= restart/60000/restart/120000/restart/300000

    # Configure service permissions
    Write-Host "Configuring service permissions..." -ForegroundColor Cyan
    & sc.exe sdset $ServiceName D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)(A;;CR;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)

    # Start the service
    Write-Host "Starting service..." -ForegroundColor Cyan
    Start-Service -Name $ServiceName

    Write-Host "Service installed and started successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Service Name: $ServiceName"
    Write-Host "Binary Path: $BinaryPath"
    Write-Host "Config Path: $ConfigPath"
    Write-Host ""
    Write-Host "Useful Commands:"
    Write-Host "  Start service:   Start-Service $ServiceName"
    Write-Host "  Stop service:    Stop-Service $ServiceName"
    Write-Host "  Restart service: Restart-Service $ServiceName"
    Write-Host "  Remove service:  sc.exe delete $ServiceName"
    Write-Host "  View logs:       Get-EventLog -LogName Application -Source $ServiceName -Newest 50"
}

function Uninstall-Service {
    Write-Host "Uninstalling Employee Monitoring Agent service..." -ForegroundColor Yellow

    # Check if service exists
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Warning "Service '$ServiceName' does not exist"
        return
    }

    # Stop service if running
    if ($service.Status -eq "Running") {
        Write-Host "Stopping service..." -ForegroundColor Cyan
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }

    # Remove service
    Write-Host "Removing service..." -ForegroundColor Cyan
    Remove-Service -Name $ServiceName -Force

    # Wait for service to be fully removed
    Start-Sleep -Seconds 2

    Write-Host "Service uninstalled successfully!" -ForegroundColor Green
}

# Main execution
if ($Uninstall) {
    Uninstall-Service
} else {
    Install-Service
}
