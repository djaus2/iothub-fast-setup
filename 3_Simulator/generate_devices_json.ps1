param(
  [string]$HubName,

  [int]$Start = 1,
  [int]$End = 10
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = (Resolve-Path (Join-Path $scriptDir "..\csharp_simulator")).Path
$outputFile = Join-Path $projectDir "devices.json"

& (Join-Path $scriptDir "get_device_connections.ps1") -HubName $HubName -Start $Start -End $End -OutputFile $outputFile

Write-Host "Generated $outputFile"
