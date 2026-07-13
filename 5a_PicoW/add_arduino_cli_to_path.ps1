param(
  [string]$InstallPath = 'C:\Program Files\Arduino CLI'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InstallPath)) {
  throw "Arduino CLI install folder was not found: $InstallPath"
}

$currentProcessPath = $env:Path
if ($currentProcessPath -notmatch [regex]::Escape($InstallPath)) {
  $env:Path = "$InstallPath;$currentProcessPath"
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrWhiteSpace($userPath)) {
  [Environment]::SetEnvironmentVariable('Path', $InstallPath, 'User')
}
elseif ($userPath -notmatch [regex]::Escape($InstallPath)) {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$InstallPath", 'User')
}

Write-Host "Added Arduino CLI to the current session PATH and the user PATH: $InstallPath"
Write-Host "Open a new terminal after this step if you want the change to apply everywhere immediately."