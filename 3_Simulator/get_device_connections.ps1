param(
  [string]$HubName,

  [int]$Start = 1,
  [int]$End = 10,

  [string]$OutputFile = "devices.json"
)

if (-not $HubName) {
  $HubName = $env:IOTHUB_NAME
}

if (-not $HubName) {
  throw "Hub name not provided. Set IOTHUB_NAME environment variable (run .\1_QuickSetup\set_iothub_env.ps1 -HubName <name>) or pass -HubName explicitly."
}

$devices = @()

for ($i = $Start; $i -le $End; $i++) {
  $deviceId = "device$i"
  $conn = az iot hub device-identity connection-string show -n $HubName -d $deviceId --query connectionString -o tsv

  if (-not $conn) {
    Write-Error "Failed to get connection string for $deviceId"
    exit 1
  }

  $devices += [pscustomobject]@{
    deviceId = $deviceId
    connectionString = $conn
  }
}

$devices | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "Wrote $OutputFile with $($devices.Count) device connection strings."
