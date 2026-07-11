param(
  [string]$HubName,

  [string]$DeviceId,

  [int]$Start = 1,
  [int]$End = 10
)

$ErrorActionPreference = 'Stop'

if (-not $HubName) {
  $HubName = $env:IOTHUB_NAME
}

if (-not $HubName) {
  throw "Hub name not provided. Set IOTHUB_NAME (run .\1_QuickSetup\set_iothub_env.ps1 -HubName <name>) or pass -HubName explicitly."
}

$deviceIds = @()
if ($DeviceId) {
  $deviceIds = @($DeviceId)
}
else {
  for ($i = $Start; $i -le $End; $i++) {
    $deviceIds += "device$i"
  }
}

$rows = @()
foreach ($id in $deviceIds) {
  $raw = az iot hub device-twin show -n $HubName -d $id -o json
  if (-not $raw) {
    Write-Warning "No twin returned for $id"
    continue
  }

  $twin = $raw | ConvertFrom-Json
  $rows += [pscustomobject]@{
    deviceId = $id
    desiredTargetVersion = $twin.properties.desired.du.targetVersion
    reportedTargetVersion = $twin.properties.reported.du.targetVersion
    restartRequested = $twin.properties.reported.du.restartRequested
    appVersion = $twin.properties.reported.app.version
    simState = $twin.properties.reported.sim.lastState
    lastUpdateUtc = $twin.properties.reported.sim.lastUpdateUtc
  }
}

$rows | Sort-Object deviceId | Format-Table -AutoSize
