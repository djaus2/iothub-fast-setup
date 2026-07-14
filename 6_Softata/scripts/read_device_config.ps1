#!/usr/bin/env pwsh
<#
.SYNOPSIS
Read Softata device configuration from EEPROM via serial connection.

.DESCRIPTION
Connects to Pico W device via USB serial port and reads the EEPROM configuration
including WiFi SSID, device ID, connection string, and hub FQDN.

.PARAMETER ComPort
Serial COM port (e.g., COM3). Default: COM3

.PARAMETER Timeout
Read timeout in seconds. Default: 5

.EXAMPLE
.\read_device_config.ps1 -ComPort COM3
.\read_device_config.ps1 -ComPort COM5 -Timeout 10
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ComPort = "COM3",
    
    [Parameter(Mandatory = $false)]
    [int]$Timeout = 5
)

function Read-SerialConfig {
    param(
        [string]$Port,
        [int]$TimeoutSec
    )
    
    try {
        $serialPort = New-Object System.IO.Ports.SerialPort($Port, 115200, 'None', 8, 'One')
        $serialPort.ReadTimeout = $TimeoutSec * 1000
        $serialPort.Open()
        
        Write-Host "Opened $Port at 115200 baud"
        Start-Sleep -Milliseconds 500
        
        # Send command to read config (implementation-specific)
        $serialPort.WriteLine("CONFIG READ")
        
        $output = ""
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSec) {
            try {
                $line = $serialPort.ReadLine()
                $output += $line + "`n"
                
                if ($line -match "END_CONFIG" -or $line -match "Config complete") {
                    break
                }
            }
            catch [System.TimeoutException] {
                break
            }
        }
        
        $serialPort.Close()
        return $output
    }
    catch {
        Write-Error "Failed to read serial: $_"
        return $null
    }
}

Write-Host "=== Softata Device Configuration Reader ===" -ForegroundColor Cyan
Write-Host "COM Port: $ComPort"
Write-Host "Timeout: ${Timeout}s"
Write-Host ""

$config = Read-SerialConfig -Port $ComPort -TimeoutSec $Timeout

if ($config) {
    Write-Host "Configuration read:" -ForegroundColor Green
    Write-Host $config
} else {
    Write-Host "Failed to read configuration" -ForegroundColor Red
    Write-Host "Make sure:"
    Write-Host "  - Device is connected to $ComPort"
    Write-Host "  - Device firmware is running"
    Write-Host "  - Serial monitor is not open"
}
