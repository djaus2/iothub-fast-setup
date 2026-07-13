param(
  [string]$BoardManagerUrl = "https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json",
  [string]$BoardPackage = "rp2040:rp2040",
  [string]$SketchFolder = "pico_firmware",
  [string[]]$Libraries = @("ArduinoJson", "PubSubClient", "Time")
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

if (-not ($arduinoCli = Resolve-ArduinoCliExe)) {
  throw "arduino-cli was not found. Run .\5a_PicoW\install_arduino_cli.ps1 first, then rerun this script."
}

$arduinoConfigDir = Get-ArduinoCliConfigDir

Write-Host "Adding board manager URL (if missing)..."
Write-Host "Using board manager URL for this run only: $BoardManagerUrl"

Write-Host "Updating board indexes..."
& $arduinoCli --config-dir $arduinoConfigDir --additional-urls $BoardManagerUrl core update-index | Out-Null

Write-Host "Installing board package: $BoardPackage"
& $arduinoCli --config-dir $arduinoConfigDir --additional-urls $BoardManagerUrl core install $BoardPackage | Out-Null

foreach ($lib in $Libraries) {
  Write-Host "Installing library: $lib"
  & $arduinoCli --config-dir $arduinoConfigDir lib install $lib | Out-Null
}

$resolvedSketchFolder = if ([System.IO.Path]::IsPathRooted($SketchFolder)) {
  $SketchFolder
} else {
  Join-Path $PSScriptRoot $SketchFolder
}

if (-not (Test-Path $resolvedSketchFolder)) {
  Write-Warning "Sketch folder not found: $resolvedSketchFolder"
}

Write-Host "Arduino CLI Pico setup completed."
