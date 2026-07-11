param(
  [Parameter(Mandatory=$true)]
  [string]$HubName,

  [ValidateSet('Process','User','Machine')]
  [string]$Scope = 'User'
)

$ErrorActionPreference = 'Stop'

# Always set for current session so scripts work immediately.
$env:IOTHUB_NAME = $HubName

switch ($Scope) {
  'Process' {
    Write-Host "Set IOTHUB_NAME for current process only: $HubName"
  }
  'User' {
    [Environment]::SetEnvironmentVariable('IOTHUB_NAME', $HubName, 'User')
    Write-Host "Set IOTHUB_NAME for current user: $HubName"
    Write-Host "Open a new terminal to pick up persisted user environment variables."
  }
  'Machine' {
    try {
      [Environment]::SetEnvironmentVariable('IOTHUB_NAME', $HubName, 'Machine')
      Write-Host "Set IOTHUB_NAME at machine scope: $HubName"
      Write-Host "Open a new terminal to pick up persisted machine environment variables."
    }
    catch {
      throw "Failed to set machine-scope variable. Re-run PowerShell as Administrator or use -Scope User."
    }
  }
}

Write-Host "Current session IOTHUB_NAME=$env:IOTHUB_NAME"
