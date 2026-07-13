param(
  [string]$WifiSsid,

  [Parameter(Mandatory=$true)]
  [string]$WifiPassword,

  [string]$IotHubName,

  [string]$ComPort
)

$ErrorActionPreference = 'Stop'

function Resolve-WifiSsid {
  param([string]$RequestedWifiSsid)

  if (-not [string]::IsNullOrWhiteSpace($RequestedWifiSsid)) {
    return $RequestedWifiSsid.Trim()
  }

  if (-not [string]::IsNullOrWhiteSpace($env:IOT_WIFI_SSID)) {
    return $env:IOT_WIFI_SSID.Trim()
  }

  $netshOutput = netsh wlan show interfaces 2>$null
  if (-not $netshOutput) {
    return $null
  }

  $ssidLine = $netshOutput |
    Where-Object { $_ -match '^\s*SSID\s*:\s*' -and $_ -notmatch '^\s*BSSID\s*:' } |
    Select-Object -First 1

  if (-not $ssidLine) {
    return $null
  }

  $resolvedSsid = (($ssidLine -split ':', 2)[1]).Trim()
  if ([string]::IsNullOrWhiteSpace($resolvedSsid) -or $resolvedSsid -eq 'N/A') {
    return $null
  }

  return $resolvedSsid
}

function Test-WifiConnectedToSsid {
  param([string]$ExpectedSsid)

  $netshOutput = netsh wlan show interfaces 2>$null
  if (-not $netshOutput) {
    return $false
  }

  $stateLine = $netshOutput |
    Where-Object { $_ -match '^\s*State\s*:\s*' } |
    Select-Object -First 1
  if (-not $stateLine) {
    return $false
  }

  $stateValue = (($stateLine -split ':', 2)[1]).Trim()
  if ($stateValue -notmatch '^(?i)connected$') {
    return $false
  }

  $ssidLine = $netshOutput |
    Where-Object { $_ -match '^\s*SSID\s*:\s*' -and $_ -notmatch '^\s*BSSID\s*:' } |
    Select-Object -First 1
  if (-not $ssidLine) {
    return $false
  }

  $connectedSsid = (($ssidLine -split ':', 2)[1]).Trim()
  if ([string]::IsNullOrWhiteSpace($connectedSsid)) {
    return $false
  }

  return $connectedSsid -eq $ExpectedSsid
}

if ([string]::IsNullOrWhiteSpace($WifiPassword)) {
  throw "Required parameter must be non-empty: -WifiPassword"
}

$effectiveWifiSsid = Resolve-WifiSsid -RequestedWifiSsid $WifiSsid
if ([string]::IsNullOrWhiteSpace($effectiveWifiSsid)) {
  throw "WifiSsid could not be resolved. Pass -WifiSsid explicitly or connect to Wi-Fi first."
}

$effectiveIotHubName = if (-not [string]::IsNullOrWhiteSpace($IotHubName)) { $IotHubName } else { $env:IOTHUB_NAME }
if ([string]::IsNullOrWhiteSpace($effectiveIotHubName)) {
  throw "IotHubName is required when IOTHUB_NAME is not already set. Pass -IotHubName or set env:IOTHUB_NAME first."
}

$env:IOT_WIFI_SSID = $effectiveWifiSsid
$env:IOT_WIFI_PASSWORD = $WifiPassword

if (-not [string]::IsNullOrWhiteSpace($IotHubName)) {
  $env:IOTHUB_NAME = $IotHubName
}

if (-not [string]::IsNullOrWhiteSpace($ComPort)) {
  $env:IOT_COM_PORT = $ComPort.Trim()
}

Write-Host "Environment variables set for this PowerShell session:"
Write-Host "  IOT_WIFI_SSID=$($env:IOT_WIFI_SSID)"
Write-Host "  IOT_WIFI_PASSWORD=(hidden)"
Write-Host "  IOTHUB_NAME=$effectiveIotHubName"
if (-not [string]::IsNullOrWhiteSpace($env:IOT_COM_PORT)) {
  Write-Host "  IOT_COM_PORT=$($env:IOT_COM_PORT)"
}

if (-not (Test-WifiConnectedToSsid -ExpectedSsid $effectiveWifiSsid)) {
  throw "Wi-Fi connectivity check failed. This machine is not currently connected to SSID '$effectiveWifiSsid'."
}

Write-Host "Wi-Fi connectivity check passed for SSID '$effectiveWifiSsid'."
