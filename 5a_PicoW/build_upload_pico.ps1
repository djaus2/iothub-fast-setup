param(
  [Parameter(Mandatory=$true)]
  [string]$SketchPath,

  [ValidateSet('build','upload')]
  [string]$Action = 'build',

  [string]$Port,
  [string]$Fqbn,
  [string[]]$BuildProperty
)

$ErrorActionPreference = 'Stop'

function Resolve-ArduinoCliExe {
  $command = Get-Command arduino-cli -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $fallback = 'C:\Program Files\Arduino CLI\arduino-cli.exe'
  if (Test-Path $fallback) {
    return $fallback
  }

  return $null
}

function Get-ArduinoCliConfigDir {
  $configDir = Join-Path $PSScriptRoot '.arduino-cli'
  if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir | Out-Null
  }
  return $configDir
}

function Resolve-IotHubFqdnFromEnv {
  if (-not [string]::IsNullOrWhiteSpace($env:IOTHUB_FQDN)) {
    return $env:IOTHUB_FQDN.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:IOTHUB_NAME)) {
    return "$(($env:IOTHUB_NAME).Trim()).azure-devices.net"
  }

  return $null
}

function Resolve-DeviceIdFromEnv {
  if (-not [string]::IsNullOrWhiteSpace($env:IOT_DEVICE_ID)) {
    return $env:IOT_DEVICE_ID.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:IOT_CONFIG_DEVICE_ID)) {
    return $env:IOT_CONFIG_DEVICE_ID.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:PICOW_N)) {
    return "picow$($env:PICOW_N.Trim())"
  }

  return $null
}

function Resolve-DeviceKeyFromEnv {
  if (-not [string]::IsNullOrWhiteSpace($env:IOT_DEVICE_KEY)) {
    return $env:IOT_DEVICE_KEY
  }

  if (-not [string]::IsNullOrWhiteSpace($env:IOT_CONFIG_DEVICE_KEY)) {
    return $env:IOT_CONFIG_DEVICE_KEY
  }

  return $null
}

function Resolve-WifiSsidFromEnv {
  if (-not [string]::IsNullOrWhiteSpace($env:IOT_WIFI_SSID)) {
    return $env:IOT_WIFI_SSID.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:WIFI_SSID)) {
    return $env:WIFI_SSID.Trim()
  }

  return $null
}

function Resolve-WifiPasswordFromEnv {
  if (-not [string]::IsNullOrWhiteSpace($env:IOT_WIFI_PASSWORD)) {
    return $env:IOT_WIFI_PASSWORD
  }

  if (-not [string]::IsNullOrWhiteSpace($env:WIFI_PASSWORD)) {
    return $env:WIFI_PASSWORD
  }

  return $null
}

function Resolve-ComPortFromEnv {
  if (-not [string]::IsNullOrWhiteSpace($env:IOT_COM_PORT)) {
    return $env:IOT_COM_PORT.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:COM_PORT)) {
    return $env:COM_PORT.Trim()
  }

  return $null
}

function Escape-CppStringLiteral {
  param([string]$Value)

  if ($null -eq $Value) {
    return $null
  }

  return ($Value -replace '\\', '\\\\' -replace '"', '\\"')
}

if (-not ($arduinoCli = Resolve-ArduinoCliExe)) {
  throw "arduino-cli was not found. Run .\5a_PicoW\install_arduino_cli.ps1 first, then rerun this script."
}

$arduinoConfigDir = Get-ArduinoCliConfigDir

function Resolve-PicoFqbn {
  param(
    [string]$ExplicitFqbn,
    [string]$TargetPort
  )

  if (-not [string]::IsNullOrWhiteSpace($ExplicitFqbn)) {
    Write-Host "Using explicit FQBN: $ExplicitFqbn"
    return $ExplicitFqbn
  }

  $boardList = & $arduinoCli --config-dir $arduinoConfigDir board list 2>$null
  if ([string]::IsNullOrWhiteSpace($boardList)) {
    return 'rp2040:rp2040:rpipicow'
  }

  $portLine = $null
  if (-not [string]::IsNullOrWhiteSpace($TargetPort)) {
    $portLine = $boardList | Select-String -Pattern ("^" + [regex]::Escape($TargetPort) + "\b") | Select-Object -First 1
  }

  $lineText = if ($portLine) { $portLine.Line } else { $boardList }

  if (-not [string]::IsNullOrWhiteSpace($TargetPort) -and $portLine) {
    Write-Host "Detected board on port $TargetPort: $($portLine.Line.Trim())"
  }

  if ($lineText -match '(?i)Pico\s*2\s*W' -or $lineText -match '(?i)rpipico2w' -or $lineText -match '(?i)RP2350') {
    Write-Host "Auto-selected Pico W2 FQBN."
    return 'rp2040:rp2040:rpipico2w'
  }

  if ($lineText -match '(?i)Pico\s*W' -or $lineText -match '(?i)rpipicow' -or $lineText -match '(?i)RP2040') {
    Write-Host "Auto-selected Pico W FQBN."
    return 'rp2040:rp2040:rpipicow'
  }

  Write-Host "Could not distinguish the board family from arduino-cli output; defaulting to Pico W FQBN."
  return 'rp2040:rp2040:rpipicow'
}

$resolvedFqbn = Resolve-PicoFqbn -ExplicitFqbn $Fqbn -TargetPort $Port

Write-Host "Using FQBN: $resolvedFqbn"

$effectiveBuildProperties = @()
if ($BuildProperty) {
  $effectiveBuildProperties = @($BuildProperty)
}

$extraFlags = @()

$hasHubOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_IOTHUB_FQDN' } | Select-Object -First 1
if (-not $hasHubOverride) {
  $iotHubFqdn = Resolve-IotHubFqdnFromEnv
  if (-not [string]::IsNullOrWhiteSpace($iotHubFqdn)) {
    $escapedHubFqdn = Escape-CppStringLiteral $iotHubFqdn
    $extraFlags += "-DIOT_CONFIG_IOTHUB_FQDN=\"$escapedHubFqdn\""
    Write-Host "Using IoT Hub FQDN from environment: $iotHubFqdn"
  }
}

$hasWifiSsidOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_WIFI_SSID' } | Select-Object -First 1
if (-not $hasWifiSsidOverride) {
  $wifiSsid = Resolve-WifiSsidFromEnv
  if (-not [string]::IsNullOrWhiteSpace($wifiSsid)) {
    $escapedWifiSsid = Escape-CppStringLiteral $wifiSsid
    $extraFlags += "-DIOT_CONFIG_WIFI_SSID=\"$escapedWifiSsid\""
    Write-Host "Using Wi-Fi SSID from environment."
  }
}

$hasWifiPasswordOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_WIFI_PASSWORD' } | Select-Object -First 1
if (-not $hasWifiPasswordOverride) {
  $wifiPassword = Resolve-WifiPasswordFromEnv
  if (-not [string]::IsNullOrWhiteSpace($wifiPassword)) {
    $escapedWifiPassword = Escape-CppStringLiteral $wifiPassword
    $extraFlags += "-DIOT_CONFIG_WIFI_PASSWORD=\"$escapedWifiPassword\""
    Write-Host "Using Wi-Fi password from environment."
  }
}

$hasDeviceIdOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_DEVICE_ID' } | Select-Object -First 1
if (-not $hasDeviceIdOverride) {
  $deviceId = Resolve-DeviceIdFromEnv
  if (-not [string]::IsNullOrWhiteSpace($deviceId)) {
    $escapedDeviceId = Escape-CppStringLiteral $deviceId
    $extraFlags += "-DIOT_CONFIG_DEVICE_ID=\"$escapedDeviceId\""
    Write-Host "Using device id from environment: $deviceId"
  }
}

$hasDeviceKeyOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_DEVICE_KEY' } | Select-Object -First 1
if (-not $hasDeviceKeyOverride) {
  $deviceKey = Resolve-DeviceKeyFromEnv
  if (-not [string]::IsNullOrWhiteSpace($deviceKey)) {
    $escapedDeviceKey = Escape-CppStringLiteral $deviceKey
    $extraFlags += "-DIOT_CONFIG_DEVICE_KEY=\"$escapedDeviceKey\""
    Write-Host "Using device primary key from environment."
  }
}

if ($extraFlags.Count -gt 0) {
  $extraFlagsValue = $extraFlags -join ' '
  $extraFlagsIndex = -1
  for ($i = 0; $i -lt $effectiveBuildProperties.Count; $i++) {
    if ($effectiveBuildProperties[$i] -match '^build\.extra_flags=') {
      $extraFlagsIndex = $i
      break
    }
  }

  if ($extraFlagsIndex -ge 0) {
    $effectiveBuildProperties[$extraFlagsIndex] = "$($effectiveBuildProperties[$extraFlagsIndex]) $extraFlagsValue"
  }
  else {
    $effectiveBuildProperties += "build.extra_flags=$extraFlagsValue"
  }
}

if (-not (Test-Path $SketchPath)) {
  throw "Sketch not found: $SketchPath"
}

$sketchDir = Split-Path -Parent (Resolve-Path $SketchPath)

if ($Action -eq 'build') {
  $compileArgs = @('compile', '--fqbn', $resolvedFqbn, '--output-dir', "$sketchDir\build")
  foreach ($property in $effectiveBuildProperties) {
    $compileArgs += @('--build-property', $property)
  }
  $compileArgs += $SketchPath
  & $arduinoCli --config-dir $arduinoConfigDir @compileArgs
  return
}

$effectivePort = if (-not [string]::IsNullOrWhiteSpace($Port)) { $Port } else { Resolve-ComPortFromEnv }
if ([string]::IsNullOrWhiteSpace($effectivePort)) {
  throw "Port is required for upload. Pass -Port COM6 or set env:IOT_COM_PORT (or env:COM_PORT)."
}

Write-Host "Using upload port: $effectivePort"

$compileArgs = @('compile', '--fqbn', $resolvedFqbn, '--output-dir', "$sketchDir\build")
foreach ($property in $effectiveBuildProperties) {
  $compileArgs += @('--build-property', $property)
}
$compileArgs += $SketchPath
& $arduinoCli --config-dir $arduinoConfigDir @compileArgs
& $arduinoCli --config-dir $arduinoConfigDir upload -p $effectivePort --fqbn $resolvedFqbn $SketchPath
