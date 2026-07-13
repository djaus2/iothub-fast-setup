param(
  [string]$HubName,
  [string]$Prefix = "picow",
  [int]$Start = 1,
  [int]$End = 2,
  [string]$OutputFile = ""
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

$rows = @()
for ($i = $Start; $i -le $End; $i++) {
  $deviceId = "$Prefix$i"
  Write-Host "Reading connection string: $deviceId"

  $cs = az iot hub device-identity connection-string show -n $HubName -d $deviceId --query connectionString -o tsv
  if (-not $cs) {
    Write-Warning "No connection string returned for $deviceId"
    continue
  }

  $rows += [pscustomobject]@{
    deviceId = $deviceId
    connectionString = $cs
  }
}

if (-not $rows) {
  Write-Warning "No connection strings were retrieved."
  return
}

$rows | Format-Table -AutoSize

if ($OutputFile) {
  $json = $rows | ConvertTo-Json -Depth 3
  Set-Content -Path $OutputFile -Value $json -Encoding UTF8
  Write-Host "Saved output JSON: $OutputFile"
}
