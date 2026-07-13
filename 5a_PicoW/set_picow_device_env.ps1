param(
  [int]$N = 1,
  [string]$Prefix = "picow",
  [string]$HubName
)

$ErrorActionPreference = 'Stop'

if (-not $HubName) {
  $HubName = $env:IOTHUB_NAME
}

if (-not $HubName) {
  throw "Hub name not provided. Set IOTHUB_NAME or pass -HubName explicitly."
}

if ($N -lt 1) {
  throw "N must be >= 1."
}

$deviceId = "$Prefix$N"
Write-Host "Resolving primary key for device: $deviceId"

$primaryKey = az iot hub device-identity show -n $HubName -d $deviceId --query authentication.symmetricKey.primaryKey -o tsv
if (-not $primaryKey) {
  throw "No primary key returned for $deviceId. Confirm the device exists in hub $HubName."
}

$env:PICOW_N = "$N"
$env:IOT_DEVICE_ID = $deviceId
$env:IOT_DEVICE_KEY = $primaryKey

Write-Host "Environment variables set for this PowerShell session:"
Write-Host "  PICOW_N=$($env:PICOW_N)"
Write-Host "  IOT_DEVICE_ID=$($env:IOT_DEVICE_ID)"
Write-Host "  IOT_DEVICE_KEY=(hidden)"
