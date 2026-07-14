#!/usr/bin/env pwsh
<#
.SYNOPSIS
Configure Softata device EEPROM via IoT Hub twin.

.DESCRIPTION
Sets EEPROM configuration (WiFi, device ID, connection string) by updating 
the Azure IoT Hub device twin. The device firmware reads desired properties 
and persists them to EEPROM.

.PARAMETER DeviceId
Device ID (e.g., picow1). Required.

.PARAMETER IotHubName
IoT Hub name without suffix (e.g., my-hub-123). Required.

.PARAMETER Ssid
WiFi SSID. Optional.

.PARAMETER Password
WiFi password. Optional.

.PARAMETER DeviceConnectionString
Full device connection string. Optional (falls back to device key).

.PARAMETER Hostname
mDNS hostname. Defaults to device ID.

.EXAMPLE
.\configure_device_eeprom.ps1 -DeviceId "picow1" -IotHubName "my-hub-123" `
  -Ssid "MyWiFi" -Password "password123"

.\configure_device_eeprom.ps1 -DeviceId "picow1" -IotHubName "my-hub-123" `
  -DeviceConnectionString "HostName=my-hub-123.azure-devices.net;DeviceId=picow1;SharedAccessKey=..."
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceId,
    
    [Parameter(Mandatory = $true)]
    [string]$IotHubName,
    
    [Parameter(Mandatory = $false)]
    [string]$Ssid,
    
    [Parameter(Mandatory = $false)]
    [string]$Password,
    
    [Parameter(Mandatory = $false)]
    [string]$DeviceConnectionString,
    
    [Parameter(Mandatory = $false)]
    [string]$Hostname = $DeviceId
)

function Set-TwinDesiredProperty {
    param(
        [string]$HubName,
        [string]$Device,
        [hashtable]$Properties
    )
    
    # Build the desired properties JSON
    $desiredJson = $Properties | ConvertTo-Json -Depth 10
    
    Write-Host "Updating twin desired properties..." -ForegroundColor Cyan
    
    try {
        # Use Azure CLI to update twin
        $twin = az iot hub device-twin update -n $HubName -d $Device --desired "{
            `"config`": {
                `"ssid`": `"$Ssid`",
                `"hostname`": `"$Hostname`",
                `"applyAt`": `"$(Get-Date -Format 'O')`"
            }
        }" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Twin updated successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to update twin: $twin" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Error "Exception updating twin: $_"
        return $false
    }
}

Write-Host "=== Softata Device EEPROM Configuration ===" -ForegroundColor Cyan
Write-Host "Device: $DeviceId"
Write-Host "IoT Hub: $IotHubName"
Write-Host "Hostname: $Hostname"
Write-Host ""

# Verify device exists
Write-Host "Verifying device exists..." -ForegroundColor Yellow
$device = az iot hub device-identity show -n $IotHubName -d $DeviceId 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Device $DeviceId not found in hub $IotHubName"
    exit 1
}

Write-Host "Device found: $($device | ConvertFrom-Json | Select-Object deviceId, type)" -ForegroundColor Green
Write-Host ""

# Prepare properties
$props = @{
    "deviceId"   = $DeviceId
    "hostname"   = $Hostname
    "hubName"    = $IotHubName
}

if ($Ssid) {
    $props["ssid"] = $Ssid
}

if ($Password) {
    $props["password"] = $Password
}

if ($DeviceConnectionString) {
    $props["connectionString"] = $DeviceConnectionString
}

# Update twin
if (Set-TwinDesiredProperty -HubName $IotHubName -Device $DeviceId -Properties $props) {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Green
    Write-Host "1. Device will read desired twin properties"
    Write-Host "2. Configuration will be written to EEPROM"
    Write-Host "3. Device will restart with new config"
    Write-Host ""
    Write-Host "Verify with: .\read_device_config.ps1 -ComPort COM3"
} else {
    exit 1
}
