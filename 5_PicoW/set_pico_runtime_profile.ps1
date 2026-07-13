param(
  [string]$HubName,
  [string]$Prefix = "picow",
  [int]$Start = 1,
  [int]$End = 2,
  [double]$IntervalSeconds = 5,
  [int]$RandomEvery = 10,
  [double]$TempMin = 15,
  [double]$TempMax = 40,
  [double]$BaseTemp = 23,
  [string]$Platform = "pico-w"
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
  Write-Host "Applying desired runtime profile to $deviceId"

  $desiredJson = @{
    sim = @{
      intervalSeconds = $IntervalSeconds
      randomEvery = $RandomEvery
      tempMin = $TempMin
      tempMax = $TempMax
      baseTemp = $BaseTemp
    }
    deviceProfile = @{
      platform = $Platform
    }
  } | ConvertTo-Json -Compress

  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    Set-Content -Path $tmp -Value $desiredJson -Encoding UTF8
    az iot hub device-twin update -n $HubName -d $deviceId --desired $tmp | Out-Null
  }
  finally {
    Remove-Item -Path $tmp -ErrorAction SilentlyContinue
  }
}

Write-Host "Done. Desired runtime profile applied to selected Pico devices."
