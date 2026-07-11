param(
  [string]$HubName,

  [ValidateSet('start','stop')]
  [string]$Action = 'stop'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir

try {
  if (-not $HubName) {
    $HubName = $env:IOTHUB_NAME
  }

  if (-not $HubName) {
    throw "Hub name not provided. Set IOTHUB_NAME environment variable (run .\1-QuickSetup\set_iothub_env.ps1 -HubName <name>) or pass -HubName explicitly."
  }

  for ($i = 1; $i -le 10; $i++) {
    $deviceId = "device$i"
    $methodName = if ($Action -eq 'start') { 'startTelemetry' } else { 'stopTelemetry' }
    $payload = '{}'

    Write-Host "Invoking $methodName on $deviceId..."
    az iot hub invoke-device-method -n $HubName -d $deviceId --method-name $methodName --method-payload $payload | Out-Null
  }

  Write-Host "Completed telemetry $Action for device1..device10."
}
finally {
  Pop-Location
}
