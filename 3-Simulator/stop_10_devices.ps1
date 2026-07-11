param(
  [string]$HubName,

  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$scriptDir = (Resolve-Path (Split-Path -Parent $MyInvocation.MyCommand.Path)).Path
$projectDir = (Resolve-Path (Join-Path $scriptDir "..\csharp-simulator")).Path

if (-not $HubName) {
  $HubName = $env:IOTHUB_NAME
}

if (-not $HubName) {
  $HubName = "<unknown-hub>"
}

# Match simulator processes started from this workspace project.
$targets = Get-CimInstance Win32_Process | Where-Object {
  ($_.Name -ieq "csharp-simulator.exe" -and $_.ExecutablePath -like "$projectDir*") -or
  ($_.Name -ieq "dotnet.exe" -and $_.CommandLine -like "*csharp-simulator*" -and $_.CommandLine -like "*$projectDir*")
}

if (-not $targets) {
  Write-Host "No running C# simulator processes found for hub '$HubName'."
  return
}

Write-Host "Found $($targets.Count) simulator process(es) for hub '$HubName':"
$targets | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize

if ($WhatIf) {
  Write-Host "WhatIf enabled. No processes were stopped."
  return
}

foreach ($p in $targets) {
  try {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
    Write-Host "Stopped PID $($p.ProcessId) ($($p.Name))"
  }
  catch {
    Write-Warning "Failed to stop PID $($p.ProcessId): $($_.Exception.Message)"
  }
}

Write-Host "Simulator stop operation completed."
