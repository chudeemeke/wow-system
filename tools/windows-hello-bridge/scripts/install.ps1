# WoW Windows Hello Bridge - Installation Script
# Run this from PowerShell after building the bridge
#
# Usage:
#   .\install.ps1              Install to default location
#   .\install.ps1 -Uninstall   Remove installation

param(
    [switch]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Configuration
$InstallDir = "$env:LOCALAPPDATA\Programs\WoW"
$ExeName = "WoWHelloBridge.exe"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path (Split-Path -Parent $ScriptDir) "build"
$SourceExe = Join-Path $BuildDir $ExeName

function Show-Help {
    Write-Host @"

WoW Windows Hello Bridge - Installer

USAGE:
    .\install.ps1              Install bridge to $InstallDir
    .\install.ps1 -Uninstall   Remove installation
    .\install.ps1 -Help        Show this help

PREREQUISITES:
    1. Build the bridge first:
       dotnet publish src/WoWHelloBridge.csproj -c Release -r win-x64 --self-contained -o build/

    2. Run this script

WHAT IT DOES:
    - Creates installation directory: $InstallDir
    - Copies WoWHelloBridge.exe to installation directory
    - Verifies the executable works

"@
}

function Install-Bridge {
    Write-Host ""
    Write-Host "WoW Windows Hello Bridge - Installation" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check if build exists
    if (-not (Test-Path $SourceExe)) {
        Write-Host "ERROR: Build not found at: $SourceExe" -ForegroundColor Red
        Write-Host ""
        Write-Host "Build the bridge first:" -ForegroundColor Yellow
        Write-Host "  cd $(Split-Path -Parent $ScriptDir)"
        Write-Host "  dotnet publish src/WoWHelloBridge.csproj -c Release -r win-x64 --self-contained -o build/"
        Write-Host ""
        exit 1
    }

    Write-Host "[1/4] Found build: $SourceExe" -ForegroundColor Green

    # Create installation directory
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Write-Host "[2/4] Created directory: $InstallDir" -ForegroundColor Green
    } else {
        Write-Host "[2/4] Directory exists: $InstallDir" -ForegroundColor Green
    }

    # Copy executable
    Copy-Item -Path $SourceExe -Destination $InstallDir -Force
    $InstalledExe = Join-Path $InstallDir $ExeName
    Write-Host "[3/4] Installed: $InstalledExe" -ForegroundColor Green

    # Verify
    try {
        $version = & $InstalledExe --version 2>&1
        Write-Host "[4/4] Verified: $version" -ForegroundColor Green
    } catch {
        Write-Host "[4/4] WARNING: Could not verify executable" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Installation complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. In WSL, run: wow superadmin setup --hello"
    Write-Host "  2. Complete Windows Hello enrollment when prompted"
    Write-Host "  3. Use: wow superadmin unlock"
    Write-Host ""

    # Show WSL path
    $WslPath = $InstalledExe -replace "C:", "/mnt/c" -replace "\\", "/"
    Write-Host "WSL path: $WslPath" -ForegroundColor DarkGray
    Write-Host ""
}

function Uninstall-Bridge {
    Write-Host ""
    Write-Host "WoW Windows Hello Bridge - Uninstallation" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    $InstalledExe = Join-Path $InstallDir $ExeName

    if (Test-Path $InstalledExe) {
        Remove-Item -Path $InstalledExe -Force
        Write-Host "Removed: $InstalledExe" -ForegroundColor Green
    } else {
        Write-Host "Not installed: $InstalledExe" -ForegroundColor Yellow
    }

    # Remove directory if empty
    if ((Test-Path $InstallDir) -and ((Get-ChildItem $InstallDir | Measure-Object).Count -eq 0)) {
        Remove-Item -Path $InstallDir -Force
        Write-Host "Removed empty directory: $InstallDir" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Uninstallation complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Note: Windows Hello key credential remains in Windows." -ForegroundColor DarkGray
    Write-Host "To remove it, use Windows Settings > Accounts > Sign-in options." -ForegroundColor DarkGray
    Write-Host ""
}

# Main
if ($Help) {
    Show-Help
} elseif ($Uninstall) {
    Uninstall-Bridge
} else {
    Install-Bridge
}
