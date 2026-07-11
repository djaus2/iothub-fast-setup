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

foreach ($id in $deviceIds) {
  Write-Host "Clearing ADU target version on $id..."
  az iot hub device-twin update -n $HubName -d $id --set properties.desired.du.targetVersion=null | Out-Null
}

Write-Host "Cleared ADU target version for $($deviceIds.Count) device(s)."
