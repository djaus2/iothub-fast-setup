param(
  [Parameter(Mandatory=$true)]
  [string]$HubName,

  [ValidateSet('Process','User','Machine')]
  [string]$Scope = 'User'
)

$ErrorActionPreference = 'Stop'
$rgName = "${HubName}_RG"

# Always set for current session so scripts work immediately.
$env:IOTHUB_NAME = $HubName
$env:IOT_RG = $rgName

switch ($Scope) {
  'Process' {
    Write-Host "Set IOTHUB_NAME for current process only: $HubName"
    Write-Host "Set IOT_RG for current process only: $rgName"
  }
  'User' {
    [Environment]::SetEnvironmentVariable('IOTHUB_NAME', $HubName, 'User')
    [Environment]::SetEnvironmentVariable('IOT_RG', $rgName, 'User')
    Write-Host "Set IOTHUB_NAME for current user: $HubName"
    Write-Host "Set IOT_RG for current user: $rgName"
    Write-Host "Open a new terminal to pick up persisted user environment variables."
  }
  'Machine' {
    try {
      [Environment]::SetEnvironmentVariable('IOTHUB_NAME', $HubName, 'Machine')
      [Environment]::SetEnvironmentVariable('IOT_RG', $rgName, 'Machine')
      Write-Host "Set IOTHUB_NAME at machine scope: $HubName"
      Write-Host "Set IOT_RG at machine scope: $rgName"
      Write-Host "Open a new terminal to pick up persisted machine environment variables."
    }
    catch {
      throw "Failed to set machine-scope variable. Re-run PowerShell as Administrator or use -Scope User."
    }
  }
}

Write-Host "Current session IOTHUB_NAME=$env:IOTHUB_NAME"
Write-Host "Current session IOT_RG=$env:IOT_RG"
