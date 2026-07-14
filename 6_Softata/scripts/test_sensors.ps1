#!/usr/bin/env pwsh
<#
.SYNOPSIS
Test Softata device sensors via serial connection.

.DESCRIPTION
Connects to Pico W device and collects sensor readings for a specified duration.
Displays temperature, humidity, pressure, and distance readings in real-time.

.PARAMETER ComPort
Serial COM port (e.g., COM3). Default: COM3

.PARAMETER Duration
Test duration in seconds. Default: 60

.PARAMETER Interval
Reading interval in milliseconds. Default: 2000 (2 seconds)

.EXAMPLE
.\test_sensors.ps1 -ComPort COM3 -Duration 60
.\test_sensors.ps1 -Duration 120 -Interval 1000
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ComPort = "COM3",
    
    [Parameter(Mandatory = $false)]
    [int]$Duration = 60,
    
    [Parameter(Mandatory = $false)]
    [int]$Interval = 2000
)

function Read-SensorData {
    param(
        [string]$Port,
        [int]$DurationSec,
        [int]$IntervalMs
    )
    
    try {
        $serialPort = New-Object System.IO.Ports.SerialPort($Port, 115200, 'None', 8, 'One')
        $serialPort.ReadTimeout = 5000
        $serialPort.Open()
        
        Write-Host "Opened $Port at 115200 baud"
        Start-Sleep -Milliseconds 500
        
        # Send sensor read command
        $serialPort.WriteLine("SENSOR READ")
        
        Write-Host ""
        Write-Host "Collecting sensor data for $DurationSec seconds..." -ForegroundColor Green
        Write-Host "Interval: ${IntervalMs}ms"
        Write-Host ""
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $readingCount = 0
        
        while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSec) {
            try {
                $line = $serialPort.ReadLine()
                
                if ($line -match "SENSOR|TEMP|HUM|PRESS|DIST") {
                    Write-Host "[$([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s] $line"
                    $readingCount++
                }
                
                if ($line -match "ERROR|FAIL") {
                    Write-Host $line -ForegroundColor Red
                }
            }
            catch [System.TimeoutException] {
                # Timeout is normal
            }
        }
        
        $serialPort.Close()
        return $readingCount
    }
    catch {
        Write-Error "Failed to read sensors: $_"
        return 0
    }
}

Write-Host "=== Softata Sensor Test ===" -ForegroundColor Cyan
Write-Host "COM Port: $ComPort"
Write-Host "Duration: ${Duration}s"
Write-Host ""

$count = Read-SensorData -Port $ComPort -DurationSec $Duration -IntervalMs $Interval

Write-Host ""
Write-Host "Test complete. Readings collected: $count" -ForegroundColor Green
Write-Host ""
Write-Host "If no data appears:"
Write-Host "  - Check COM port is correct"
Write-Host "  - Verify firmware is running"
Write-Host "  - Check sensor hardware connections"
Write-Host "  - Monitor firmware serial output separately"
