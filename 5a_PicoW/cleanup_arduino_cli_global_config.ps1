param(
  [string]$KnownBadPrefix = '[] ,'
)

$ErrorActionPreference = 'Stop'

$candidateConfigFiles = @(
  (Join-Path $env:USERPROFILE '.arduinoIDE\arduino-cli.yaml'),
  (Join-Path $env:LOCALAPPDATA 'Arduino15\arduino-cli.yaml'),
  (Join-Path $env:APPDATA 'arduino-cli.yaml')
)

$configFile = $candidateConfigFiles | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $configFile) {
  throw "Could not find a global arduino-cli.yaml config file in common locations."
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFile = "$configFile.bak.$timestamp"
Copy-Item -LiteralPath $configFile -Destination $backupFile -Force

$content = Get-Content -LiteralPath $configFile -Raw
$updated = $content -replace '\[\]\s*,\s*', ''

if ($updated -eq $content) {
  Write-Host "No malformed additional URL prefix found in: $configFile"
  Write-Host "Backup created at: $backupFile"
  return
}

Set-Content -LiteralPath $configFile -Value $updated -Encoding UTF8

Write-Host "Cleaned malformed additional URL entries in: $configFile"
Write-Host "Backup saved at: $backupFile"
Write-Host "Open a new terminal before running arduino-cli commands that use global config."
