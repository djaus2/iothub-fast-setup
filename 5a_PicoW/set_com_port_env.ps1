param(
  [string]$NameFilter = "USB Serial Device"
)

$ErrorActionPreference = 'Stop'

$ports = Get-CimInstance Win32_PnPEntity |
  Where-Object { $_.Name -like "*$NameFilter*" -and $_.Name -match '\(COM\d+\)' } |
  ForEach-Object {
    $com = [regex]::Match($_.Name, '\((COM\d+)\)').Groups[1].Value
    $comNumber = [int]([regex]::Match($com, 'COM(\d+)').Groups[1].Value)
    [pscustomobject]@{
      ComPort = $com
      ComNumber = $comNumber
      Name = $_.Name
    }
  } |
  Sort-Object ComNumber -Unique

if (-not $ports) {
  throw "No matching COM ports found for name filter '$NameFilter'."
}

Write-Host "Select a COM port (matching '$NameFilter'):"
for ($i = 0; $i -lt $ports.Count; $i++) {
  Write-Host ("  {0}. {1}  -  {2}" -f $ports[$i].ComNumber, $ports[$i].ComPort, $ports[$i].Name)
}

$selectionText = Read-Host "Enter COM number"
$selection = 0
if (-not [int]::TryParse($selectionText, [ref]$selection)) {
  $valid = ($ports.ComNumber | Sort-Object | ForEach-Object { $_.ToString() }) -join ', '
  throw "Invalid selection. Enter one of: $valid"
}

$chosen = $ports | Where-Object { $_.ComNumber -eq $selection } | Select-Object -First 1
if (-not $chosen) {
  $valid = ($ports.ComNumber | Sort-Object | ForEach-Object { $_.ToString() }) -join ', '
  throw "Selection out of range. Enter one of: $valid"
}

$env:IOT_COM_PORT = $chosen.ComPort

Write-Host "Environment variable set for this PowerShell session:"
Write-Host "  IOT_COM_PORT=$($env:IOT_COM_PORT)"
