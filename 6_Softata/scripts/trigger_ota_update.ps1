#!/usr/bin/env pwsh
<#
.SYNOPSIS
Trigger OTA update on Softata device via Azure Device Update (ADU).

.DESCRIPTION
Updates the device twin `desiredVersion` field to trigger OTA firmware update.
The device firmware monitors this field and initiates download/update when it changes.

.PARAMETER DeviceId
Device ID (e.g., picow1). Required.

.PARAMETER IotHubName
IoT Hub name without suffix (e.g., my-hub-123). Required.

.PARAMETER NewVersion
Target firmware version (e.g., 1.0.1). Required.

.PARAMETER FirmwareUrl
URL to firmware binary. Optional (uses default if not specified).

.EXAMPLE
.\trigger_ota_update.ps1 -DeviceId "picow1" -IotHubName "my-hub-123" `
  -NewVersion "1.0.1"

.\trigger_ota_update.ps1 -DeviceId "picow1" -IotHubName "my-hub-123" `
  -NewVersion "1.0.2" -FirmwareUrl "https://my-storage.blob.core.windows.net/firmware/pico.bin"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    
    [Parameter(Mandatory = $true)]
    [string]$IotHubName,
    
    [Parameter(Mandatory = $true)]
    [string]$NewVersion,
    
    [Parameter(Mandatory = $false)]
    [string]$FirmwareUrl
)

function Update-TwinVersion {
    param(
        [string]$HubName,
        [string]$Device,
        [string]$Version,
        [string]$Url
    )
    
    Write-Host "Updating device twin desiredVersion..." -ForegroundColor Cyan
    
    $desiredJson = @{
        properties = @{
            desired = @{
                desiredVersion = $Version
                updateTime     = (Get-Date -Format 'O')
            }
        }
    }
    
    if ($Url) {
        $desiredJson.properties.desired["firmwareUrl"] = $Url
    }
    
    try {
        $json = $desiredJson | ConvertTo-Json -Depth 5
        
        # Update twin using Azure CLI
        $result = az iot hub device-twin update -n $HubName -d $Device `
            --desired $json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Twin updated successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to update twin: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Error "Exception updating twin: $_"
        return $false
    }
}

function Get-DeviceTwin {
    param(
        [string]$HubName,
        [string]$Device
    )
    
    try {
        $twin = az iot hub device-twin show -n $HubName -d $Device 2>&1 | ConvertFrom-Json
        return $twin
    }
    catch {
        return $null
    }
}

Write-Host "=== Softata OTA Update Trigger ===" -ForegroundColor Cyan
Write-Host "Device: $DeviceId"
Write-Host "IoT Hub: $IotHubName"
Write-Host "Target Version: $NewVersion"
if ($FirmwareUrl) {
    Write-Host "Firmware URL: $FirmwareUrl"
}
Write-Host ""

# Verify device exists
Write-Host "Verifying device exists..." -ForegroundColor Yellow
$device = az iot hub device-identity show -n $IotHubName -d $DeviceId 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Device $DeviceId not found in hub $IotHubName"
    exit 1
}

Write-Host "Device found" -ForegroundColor Green
Write-Host ""

# Get current twin
Write-Host "Reading current twin state..." -ForegroundColor Yellow
$twin = Get-DeviceTwin -HubName $IotHubName -Device $DeviceId

if ($twin) {
    $currentVersion = $twin.properties.desired.desiredVersion
    Write-Host "Current desiredVersion: $currentVersion"
}

Write-Host ""

# Update twin
if (Update-TwinVersion -HubName $IotHubName -Device $DeviceId `
    -Version $NewVersion -Url $FirmwareUrl) {
    
    Write-Host ""
    Write-Host "OTA update triggered successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Device will now:"
    Write-Host "  1. Detect desiredVersion change"
    Write-Host "  2. Download new firmware"
    Write-Host "  3. Verify firmware integrity"
    Write-Host "  4. Install and restart"
    Write-Host "  5. Update reportedVersion in twin"
    Write-Host ""
    Write-Host "Monitor update progress with:"
    Write-Host "  az iot hub device-twin show -n $IotHubName -d $DeviceId"
    Write-Host ""
    
} else {
    exit 1
}
