param(
  [string]$PackageId = 'ArduinoSA.CLI'
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

if ($resolvedCli = Resolve-ArduinoCliExe) {
  Write-Host "arduino-cli is already installed:"
  & $resolvedCli version
  return
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget was not found on PATH. Install Arduino CLI from https://arduino.github.io/arduino-cli/latest/installation/ or use another package manager, then rerun the Pico setup."
}

Write-Host "Installing Arduino CLI with winget..."
winget install --id $PackageId -e --source winget --accept-source-agreements --accept-package-agreements

if (-not ($resolvedCli = Resolve-ArduinoCliExe)) {
  throw "Arduino CLI install finished, but arduino-cli could not be found. Open a new PowerShell session or add Arduino CLI to PATH manually, then rerun the Pico setup."
}

Write-Host "arduino-cli installed successfully:"
& $resolvedCli version