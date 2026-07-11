param(
  [string]$HubName
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = (Resolve-Path (Join-Path $scriptDir "..\csharp_simulator")).Path
Push-Location $projectDir

try {
  if (-not $HubName) {
    $HubName = $env:IOTHUB_NAME
  }

  if (-not $HubName) {
    throw "Hub name not provided. Set IOTHUB_NAME environment variable (run .\1_QuickSetup\set_iothub_env.ps1 -HubName <name>) or pass -HubName explicitly."
  }

  if (-not (Test-Path ".\devices.json")) {
    Write-Host "devices.json not found. Generating from IoT Hub identities..."
    & (Join-Path $scriptDir "get_device_connections.ps1") -HubName $HubName -Start 1 -End 10 -OutputFile "devices.json"
  }

  dotnet run -- --devices-file .\devices.json
}
finally {
  Pop-Location
}
