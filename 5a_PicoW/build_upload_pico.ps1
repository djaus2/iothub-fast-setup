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

if (-not (Test-Path $SketchPath)) {
  throw "Sketch not found: $SketchPath"
}

$sketchDir = Split-Path -Parent (Resolve-Path $SketchPath)

if ($Action -eq 'build') {
  $compileArgs = @('compile', '--fqbn', $resolvedFqbn, '--output-dir', "$sketchDir\build")
  foreach ($property in $BuildProperty) {
    $compileArgs += @('--build-property', $property)
  }
  $compileArgs += $SketchPath
  & $arduinoCli --config-dir $arduinoConfigDir @compileArgs
  return
}

if (-not $Port) {
  throw "Port is required for upload. Example: -Port COM6"
}

$compileArgs = @('compile', '--fqbn', $resolvedFqbn, '--output-dir', "$sketchDir\build")
foreach ($property in $BuildProperty) {
  $compileArgs += @('--build-property', $property)
}
$compileArgs += $SketchPath
& $arduinoCli --config-dir $arduinoConfigDir @compileArgs
& $arduinoCli --config-dir $arduinoConfigDir upload -p $Port --fqbn $resolvedFqbn $SketchPath
