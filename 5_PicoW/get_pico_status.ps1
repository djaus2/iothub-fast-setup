param(
  [string]$HubName,
  [string]$Prefix = "picow",
  [int]$Start = 1,
  [int]$End = 2,
  [string]$DeviceId
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
    $deviceIds += "$Prefix$i"
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
    desiredPlatform = $twin.properties.desired.deviceProfile.platform
    desiredIntervalSeconds = $twin.properties.desired.sim.intervalSeconds
    desiredRandomEvery = $twin.properties.desired.sim.randomEvery
    reportedPlatform = $twin.properties.reported.deviceProfile.platform
    reportedIntervalSeconds = $twin.properties.reported.sim.intervalSeconds
    reportedRandomEvery = $twin.properties.reported.sim.randomEvery
    reportedLastState = $twin.properties.reported.sim.lastState
    reportedLastUpdateUtc = $twin.properties.reported.sim.lastUpdateUtc
  }
}

$rows | Sort-Object deviceId | Format-Table -AutoSize