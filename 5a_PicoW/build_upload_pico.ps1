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
  $candidateNames = @('IOT_COM_PORT', 'COM_PORT')
  $scopes = @('Process', 'User', 'Machine')

  foreach ($name in $candidateNames) {
    foreach ($scope in $scopes) {
      $value = [Environment]::GetEnvironmentVariable($name, $scope)
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value.Trim()
      }
    }
  }

  return $null
}

function Normalize-ComPort {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  $trimmed = $Value.Trim()
  if ($trimmed -match '^(?i)COM\d+$') {
    return $trimmed.ToUpperInvariant()
  }

  if ($trimmed -match '^(\d+)$') {
    return "COM$($matches[1])"
  }

  return $trimmed
}

function Escape-CppStringLiteral {
  param([string]$Value)

  if ($null -eq $Value) {
    return $null
  }

  return ($Value -replace '\\', '\\\\' -replace '"', '\\"')
}

function Append-BuildPropertyValue {
  param(
    [string[]]$Properties,
    [string]$Key,
    [string]$AppendValue
  )

  $updated = @($Properties)
  $index = -1
  for ($i = 0; $i -lt $updated.Count; $i++) {
    if ($updated[$i] -match ('^' + [regex]::Escape($Key) + '=')) {
      $index = $i
      break
    }
  }

  if ($index -ge 0) {
    $updated[$index] = "$($updated[$index]) $AppendValue"
  }
  else {
    $updated += "$Key=$AppendValue"
  }

  return ,$updated
}

function Resolve-DeviceIdFromBuildProperties {
  param([string[]]$Properties)

  if (-not $Properties) {
    return $null
  }

  $property = $Properties | Where-Object { $_ -match 'IOT_CONFIG_DEVICE_ID' } | Select-Object -First 1
  if (-not $property) {
    return $null
  }

  $match = [regex]::Match($property, 'IOT_CONFIG_DEVICE_ID=(?:`"|"|)?([^`"\s]+)(?:`"|"|)?')
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return $null
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
    Write-Host "Detected board on port ${TargetPort}: $($portLine.Line.Trim())"
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

function Resolve-ComPortFromBoardList {
  param([string]$ResolvedFqbn)

  $boardList = & $arduinoCli --config-dir $arduinoConfigDir board list 2>$null
  if ([string]::IsNullOrWhiteSpace($boardList)) {
    return $null
  }

  $preferredPattern = if ($ResolvedFqbn -match 'rpipico2w') {
    '(?i)(Pico\s*2\s*W|rpipico2w|RP2350)'
  }
  elseif ($ResolvedFqbn -match 'rpipicow') {
    '(?i)(Pico\s*W|rpipicow|RP2040)'
  }
  else {
    '(?i)(Pico\s*W|Pico\s*2\s*W|rpipicow|rpipico2w|RP2040|RP2350)'
  }

  $lines = $boardList -split "`r?`n"
  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $portMatch = [regex]::Match($line, '^\s*(COM\d+)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $portMatch.Success) { continue }
    if (-not [regex]::IsMatch($line, $preferredPattern)) { continue }
    return $portMatch.Groups[1].Value.ToUpperInvariant()
  }

  foreach ($line in $lines) {
    $portMatch = [regex]::Match($line, '^\s*(COM\d+)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($portMatch.Success) {
      return $portMatch.Groups[1].Value.ToUpperInvariant()
    }
  }

  return $null
}

function Ensure-PicoNetworkStackOption {
  param([string]$ResolvedFqbn)

  if ([string]::IsNullOrWhiteSpace($ResolvedFqbn)) {
    return $ResolvedFqbn
  }

  $isPicoWifiBoard = $ResolvedFqbn -match '^rp2040:rp2040:rpipicow' -or $ResolvedFqbn -match '^rp2040:rp2040:rpipico2w'
  if (-not $isPicoWifiBoard) {
    return $ResolvedFqbn
  }

  if ($ResolvedFqbn -match '(^|[,:])ipbtstack=') {
    $fqbnWithStack = $ResolvedFqbn
  }
  else {
    $fqbnWithStack = "${ResolvedFqbn}:ipbtstack=ipv4only"
  }

  if ($fqbnWithStack -match '^rp2040:rp2040:rpipico2w' -and $fqbnWithStack -notmatch '(^|[,:])arch=') {
    return "${fqbnWithStack},arch=arm"
  }

  return $fqbnWithStack
}

$resolvedFqbn = Resolve-PicoFqbn -ExplicitFqbn $Fqbn -TargetPort $Port
$resolvedFqbn = Ensure-PicoNetworkStackOption -ResolvedFqbn $resolvedFqbn

Write-Host "Using FQBN: $resolvedFqbn"

$effectiveBuildProperties = @()
if ($BuildProperty) {
  $effectiveBuildProperties = @($BuildProperty)
}

$effectiveDeviceId = $null
$extraFlags = @()

$hasHubOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_IOTHUB_FQDN' } | Select-Object -First 1
if (-not $hasHubOverride) {
  $iotHubFqdn = Resolve-IotHubFqdnFromEnv
  if (-not [string]::IsNullOrWhiteSpace($iotHubFqdn)) {
    $escapedHubFqdn = Escape-CppStringLiteral $iotHubFqdn
    $extraFlags += "-DIOT_CONFIG_IOTHUB_FQDN=`"$escapedHubFqdn`""
    Write-Host "Using IoT Hub FQDN from environment: $iotHubFqdn"
  }
}

$hasWifiSsidOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_WIFI_SSID' } | Select-Object -First 1
if (-not $hasWifiSsidOverride) {
  $wifiSsid = Resolve-WifiSsidFromEnv
  if (-not [string]::IsNullOrWhiteSpace($wifiSsid)) {
    $escapedWifiSsid = Escape-CppStringLiteral $wifiSsid
    $extraFlags += "-DIOT_CONFIG_WIFI_SSID=`"$escapedWifiSsid`""
    Write-Host "Using Wi-Fi SSID from environment."
  }
}

$hasWifiPasswordOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_WIFI_PASSWORD' } | Select-Object -First 1
if (-not $hasWifiPasswordOverride) {
  $wifiPassword = Resolve-WifiPasswordFromEnv
  if (-not [string]::IsNullOrWhiteSpace($wifiPassword)) {
    $escapedWifiPassword = Escape-CppStringLiteral $wifiPassword
    $extraFlags += "-DIOT_CONFIG_WIFI_PASSWORD=`"$escapedWifiPassword`""
    Write-Host "Using Wi-Fi password from environment."
  }
}

$hasDeviceIdOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_DEVICE_ID' } | Select-Object -First 1
if (-not $hasDeviceIdOverride) {
  $deviceId = Resolve-DeviceIdFromEnv
  if (-not [string]::IsNullOrWhiteSpace($deviceId)) {
    $effectiveDeviceId = $deviceId
    $escapedDeviceId = Escape-CppStringLiteral $deviceId
    $extraFlags += "-DIOT_CONFIG_DEVICE_ID=`"$escapedDeviceId`""
    Write-Host "Using device id from environment: $deviceId"
  }
}
else {
  $effectiveDeviceId = Resolve-DeviceIdFromBuildProperties -Properties $effectiveBuildProperties
}

$hasDeviceKeyOverride = $effectiveBuildProperties | Where-Object { $_ -match 'IOT_CONFIG_DEVICE_KEY' } | Select-Object -First 1
if (-not $hasDeviceKeyOverride) {
  $deviceKey = Resolve-DeviceKeyFromEnv
  if (-not [string]::IsNullOrWhiteSpace($deviceKey)) {
    $escapedDeviceKey = Escape-CppStringLiteral $deviceKey
    $extraFlags += "-DIOT_CONFIG_DEVICE_KEY=`"$escapedDeviceKey`""
    Write-Host "Using device primary key from environment."
  }
}

if ($extraFlags.Count -gt 0) {
  $extraFlagsValue = $extraFlags -join ' '
  $effectiveBuildProperties = Append-BuildPropertyValue -Properties $effectiveBuildProperties -Key 'compiler.cpp.extra_flags' -AppendValue $extraFlagsValue
}

if (-not [string]::IsNullOrWhiteSpace($effectiveDeviceId)) {
  Write-Host "Using device id: $effectiveDeviceId"
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
$effectivePort = Normalize-ComPort -Value $effectivePort

if ([string]::IsNullOrWhiteSpace($effectivePort)) {
  $effectivePort = Resolve-ComPortFromBoardList -ResolvedFqbn $resolvedFqbn
  if (-not [string]::IsNullOrWhiteSpace($effectivePort)) {
    Write-Host "Auto-detected upload port from connected board: $effectivePort"
  }
}

if ([string]::IsNullOrWhiteSpace($effectivePort)) {
  throw "Port is required for upload. Pass -Port COM6, set env:IOT_COM_PORT/env:COM_PORT in this terminal, or connect the board so the script can auto-detect a COM port from arduino-cli board list."
}

Write-Host "Using upload port: $effectivePort"

$compileArgs = @('compile', '--fqbn', $resolvedFqbn, '--output-dir', "$sketchDir\build")
foreach ($property in $effectiveBuildProperties) {
  $compileArgs += @('--build-property', $property)
}
$compileArgs += $SketchPath
& $arduinoCli --config-dir $arduinoConfigDir @compileArgs

$uploadArgs = @('--config-dir', $arduinoConfigDir, 'upload', '-p', $effectivePort, '--fqbn', $resolvedFqbn, $SketchPath)
$uploadOutput = & $arduinoCli @uploadArgs 2>&1
$uploadExitCode = $LASTEXITCODE
$uploadOutput | ForEach-Object { Write-Host $_ }

if ($uploadExitCode -ne 0) {
  $uploadText = $uploadOutput | Out-String
  if ($uploadText -match '(?i)No drive to deploy') {
    Write-Warning 'UF2 drive was not found. This usually means the board is not in BOOTSEL mode.'
    Write-Host 'Please press and hold BOOTSEL, tap RESET (or reconnect USB), then release BOOTSEL once RPI-RP2 appears.'
    Read-Host 'Press Enter to retry upload after the board is in UF2 mode' | Out-Null

    $uploadOutput = & $arduinoCli @uploadArgs 2>&1
    $uploadExitCode = $LASTEXITCODE
    $uploadOutput | ForEach-Object { Write-Host $_ }
  }
}

if ($uploadExitCode -ne 0) {
  throw 'Upload failed. If you saw "No drive to deploy", retry in BOOTSEL/UF2 mode.'
}
