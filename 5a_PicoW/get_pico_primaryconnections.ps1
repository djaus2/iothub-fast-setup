param(
  [string]$HubName,
  [string]$Prefix = "picow",
  [int]$Start = 1,
  [int]$End = 2,
  [string]$OutputFile = ".\5a_PicoW\picow-primaryconnections.json"
)

$ErrorActionPreference = 'Stop'

if (-not $HubName) {
  $HubName = $env:IOTHUB_NAME
}

if (-not $HubName) {
  throw "Hub name not provided. Set IOTHUB_NAME or pass -HubName explicitly."
}

if ($End -lt $Start) {
  throw "End must be greater than or equal to Start."
}

$rows = @()
for ($i = $Start; $i -le $End; $i++) {
  $deviceId = "$Prefix$i"
  Write-Host "Reading credentials: $deviceId"

  $primaryKey = az iot hub device-identity show -n $HubName -d $deviceId --query authentication.symmetricKey.primaryKey -o tsv
  $connectionString = az iot hub device-identity connection-string show -n $HubName -d $deviceId --query connectionString -o tsv

  if (-not $primaryKey -or -not $connectionString) {
    Write-Warning "Skipping $deviceId because key or connection string was not returned."
    continue
  }

  $rows += [pscustomobject]@{
    deviceId = $deviceId
    primaryKey = $primaryKey
    connectionString = $connectionString
  }
}

if (-not $rows) {
  throw "No device credentials were retrieved."
}

$rows | Format-Table -AutoSize

$parentDir = Split-Path -Parent $OutputFile
if ($parentDir -and -not (Test-Path $parentDir)) {
  New-Item -ItemType Directory -Path $parentDir | Out-Null
}

$rows | ConvertTo-Json -Depth 4 | Set-Content -Path $OutputFile -Encoding UTF8
Write-Host "Saved JSON: $OutputFile"
