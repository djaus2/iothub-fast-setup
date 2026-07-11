param(
  [Parameter(Mandatory=$true)]
  [string]$TargetVersion,

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
  Write-Host "Setting ADU target version '$TargetVersion' on $id..."
  az iot hub device-twin update -n $HubName -d $id --set properties.desired.du.targetVersion=$TargetVersion | Out-Null
}

Write-Host "Completed ADU target version update for $($deviceIds.Count) device(s)."
