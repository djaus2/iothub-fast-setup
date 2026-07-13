param(
  [string]$HubName,
  [string]$Prefix = "picow",
  [int]$Start = 1,
  [int]$End = 2
)

$ErrorActionPreference = "Stop"

if (-not $HubName) {
  $HubName = $env:IOTHUB_NAME
}

if (-not $HubName) {
  throw "Hub name not provided. Set IOTHUB_NAME (run .\1_QuickSetup\set_iothub_env.ps1 -HubName <name>) or pass -HubName explicitly."
}

if ($End -lt $Start) {
  throw "End must be greater than or equal to Start."
}

for ($i = $Start; $i -le $End; $i++) {
  $deviceId = "$Prefix$i"
  az iot hub device-identity show -n $HubName -d $deviceId --query deviceId -o tsv 1>$null 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Device already exists: $deviceId"
    continue
  }

  Write-Host "Creating device identity: $deviceId"
  az iot hub device-identity create -n $HubName -d $deviceId | Out-Null
}

Write-Host "Done. Pico device identity provisioning complete."
