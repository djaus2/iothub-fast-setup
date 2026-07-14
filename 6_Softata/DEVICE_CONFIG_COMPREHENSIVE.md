# Comprehensive Device Configuration Guide

Complete reference for configuring Softata devices with EEPROM persistence, Azure IoT Hub integration, and troubleshooting.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [EEPROM Layout & Memory](#eeprom-layout--memory)
3. [Configuration Methods](#configuration-methods)
4. [Step-by-Step Workflows](#step-by-step-workflows)
5. [Advanced Configuration](#advanced-configuration)
6. [Troubleshooting](#troubleshooting)
7. [Reference](#reference)

---

## Architecture Overview

### How Configuration Works

```
Device Startup:
┌─────────────────────────────────────────────────────────────┐
│ Power On / Reset                                            │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
        ┌────────────────────┐
        │ Check EEPROM Valid?│
        └────────┬───────────┘
                 │
         ┌───────┴────────┐
         │ Yes            │ No (First Boot)
         │                │
         ▼                ▼
    ┌─────────┐      ┌─────────────┐
    │Use EEPROM│      │Use Defaults │
    │Config    │      │from .ino    │
    └────┬────┘      └────┬────────┘
         │                │
         └────────┬───────┘
                  ▼
        ┌─────────────────────┐
        │ Connect to WiFi     │
        │ (SSID/Password)     │
        └────┬────────────────┘
             │
             ▼
        ┌──────────────────┐
        │ Connect to Azure │
        │ IoT Hub (via SAS)│
        └────┬─────────────┘
             │
             ▼
        ┌──────────────────┐
        │ Read Twin Config │
        │ (desiredVersion) │
        └────┬─────────────┘
             │
             ▼
        ┌──────────────────┐
        │ Write to EEPROM  │
        │ If Changed       │
        └────┬─────────────┘
             │
             ▼
        ┌──────────────────┐
        │ Main Loop        │
        │ (Telemetry)      │
        └──────────────────┘
```

### Key Concepts

**EEPROM (Electrically Erasable Programmable ROM)**
- Persistent storage survives power loss and resets
- 512 bytes total on Pico W
- Byte offsets define where each config field starts
- Marker byte (0xA5) indicates valid config

**Device Twins (Azure IoT Hub)**
- Twin = JSON document representing device state
- **Desired** properties: Cloud → Device (configuration)
- **Reported** properties: Device → Cloud (status)
- Device firmware listens for twin changes and applies them

**Configuration Flow**
1. User updates twin desired properties via Azure CLI or Portal
2. Device receives twin update via MQTT
3. Firmware validates and writes to EEPROM
4. Firmware reports success via reported properties
5. Device persists config across power cycles

---

## EEPROM Layout & Memory

### Physical Layout (512 bytes total)

```
Offset  Size  Field               Purpose                    Example
──────  ────  ─────────────────   ──────────────────────     ──────────────
0       1     Marker              0xA5 = valid              0xA5
1-32    32    SSID                WiFi network name         "HomeNetwork"
33-96   64    Password            WiFi password             "SecurePass123"
97-128  32    Device ID           Azure device name         "pico-sensor-1"
129-384 256   Connection String   Full IoT Hub string       "HostName=..."
385-416 32    Hostname            mDNS hostname             "pico-1"
417-480 64    Hub FQDN            IoT Hub domain            "hub-123.azure-devices.net"
481-512 32    Reserved            Future use                (unused)
```

### Memory Usage

```
EEPROM: 512 bytes / 512 bytes (100%) - Config storage
RAM: 72 KB / 264 KB (27%) - Runtime state + sensor buffer
Flash: 278 KB / 4 MB (6%) - Firmware binary
```

---

## Configuration Methods

### Method 1: Azure Twin (RECOMMENDED for Fleet)

**Best for:** Managing multiple devices, cloud-controlled config, automated rollouts

**Workflow:**
```
User → Azure Portal/CLI
        ↓
        Update Twin Desired Properties
        ↓
        MQTT Broker
        ↓
        Device Firmware
        ↓
        Write to EEPROM
        ↓
        Report to Twin (success)
```

**When to use:**
- First-time setup from cloud
- Updating WiFi across fleet
- Changing device names/hostnames
- Rolling out new hub configuration

**Tools:**
- [DEVICE_CONFIG_QUICK_START.md](DEVICE_CONFIG_QUICK_START.md) - 5-minute setup
- `configure_device_eeprom.ps1` - Scripted twin update
- Azure Portal - Manual twin editing
- Azure CLI - `az iot hub device-twin update`

---

### Method 2: Serial Port (MANUAL)

**Best for:** Local setup, single device, no cloud access

**Workflow:**
```
USB Serial (COM3)
        ↓
Device Firmware
        ↓
Parse Config Command
        ↓
Write to EEPROM
        ↓
Report via Serial
```

**When to use:**
- Device not yet connected to WiFi
- Testing configuration locally
- Recovery/troubleshooting
- No Azure hub available yet

**Tools:**
- `read_device_config.ps1` - Read EEPROM
- PowerShell with SerialPort API - Direct commands
- Arduino IDE Serial Monitor - Manual entry

**Example Serial Command:**
```
CONFIG SET SSID MyNetwork
CONFIG SET PASSWORD SecurePass
CONFIG SET DEVICE_ID pico-1
CONFIG SAVE
```

---

### Method 3: Compile-Time Defaults

**Best for:** Prototype/development, single device with fixed config

**Workflow:**
```
Edit iot_config.h
        ↓
#define IOT_CONFIG_WIFI_SSID "MyNetwork"
#define IOT_CONFIG_DEVICE_ID "pico-1"
        ↓
Compile & Upload
        ↓
Device uses defaults
        ↓
EEPROM stays empty (until twin update)
```

**When to use:**
- Quick prototyping
- Lab testing
- One-off devices
- Offline operation

---

## Step-by-Step Workflows

### Workflow A: First-Time Setup (Recommended Path)

Goal: Device shipped blank → fully configured and connected

#### Phase 1: Firmware Upload (5 min)

```powershell
# 1. Connect Pico W via USB with BOOTSEL held
# 2. Wait for RPI-RP2 drive to appear
# 3. Upload firmware

cd c:\temp\IOTHUB_DUP\5a_PicoW
.\add_arduino_cli_to_path.ps1

# Identify COM port
.\set_com_port_env.ps1
# Select COM3 or COM4

# Upload
arduino-cli upload --port COM3 --fqbn rp2040:rp2040:rpipico2 pico_firmware

# Expected: "Leaving..." message = success
```

**Verify:**
```powershell
# Should see device on serial at 115200 baud
# Watch for: "[Setup] Arduino OTA enabled"
```

#### Phase 2: Create Azure Device (2 min)

```powershell
# If device doesn't exist in hub yet
$deviceId = "pico-sensor-1"
$hubName = "my-hub-123"

az iot hub device-identity create `
  --hub-name $hubName `
  --device-id $deviceId `
  --auth-method shared_private_key

# Get connection string
$connStr = az iot hub device-identity connection-string show `
  --hub-name $hubName `
  --device-id $deviceId `
  --query "connectionString" `
  -o tsv

Write-Host "Connection String: $connStr"
```

#### Phase 3: Push Configuration to Device (3 min)

```powershell
cd c:\temp\IOTHUB_DUP\6_Softata\scripts

.\configure_device_eeprom.ps1 `
  -DeviceId "pico-sensor-1" `
  -IotHubName "my-hub-123" `
  -Ssid "YourNetworkName" `
  -Password "WiFiPassword123" `
  -Hostname "pico-1"

# Script will:
# 1. Verify device exists
# 2. Update twin desired properties
# 3. Device reads update
# 4. Device writes to EEPROM
# 5. Device reports success
```

**Monitor Progress:**
```powershell
# Watch device twin
az iot hub device-twin show `
  --hub-name my-hub-123 `
  --device-id pico-sensor-1 `
  --query properties.reported
```

#### Phase 4: Verification (2 min)

```powershell
# Read what was written to EEPROM
.\read_device_config.ps1 -ComPort COM3

# Expected:
# SSID: YourNetworkName
# Hostname: pico-1
# Connected: Yes
```

**Total Time:** ~15 minutes for 10 devices

---

### Workflow B: Update Single Device Config

Goal: Change WiFi or hostname on running device

```powershell
# 1. Update twin
.\configure_device_eeprom.ps1 `
  -DeviceId "pico-sensor-1" `
  -IotHubName "my-hub-123" `
  -Ssid "NewNetworkName" `
  -Password "NewPassword"

# 2. Device automatically:
#    - Detects twin change
#    - Writes new SSID to EEPROM
#    - Reconnects to new WiFi
#    - Reports success

# 3. Verify
.\read_device_config.ps1 -ComPort COM3
```

---

### Workflow C: Recovery (Device Won't Connect)

Goal: Device stuck, need to reconfigure EEPROM

```powershell
# 1. Clear EEPROM
cd c:\temp\IOTHUB_DUP\6_Softata\scripts

# Send reset command via serial
# (if firmware implements CONFIG RESET)
# OR manually erase via Arduino sketch

# 2. Restart with defaults
# Device boots with compile-time defaults from iot_config.h

# 3. Reconfigure
.\configure_device_eeprom.ps1 ...
```

---

## Advanced Configuration

### Update Only One Field

Instead of reconfiguring everything, update just one field:

```powershell
# Azure CLI - update just SSID
az iot hub device-twin update `
  -n my-hub-123 `
  -d pico-sensor-1 `
  --desired '{
    "config": {
      "ssid": "NewNetwork",
      "applyAt": "'$(Get-Date -Format 'O')'"
    }
  }'

# Device reads and applies only the SSID change
# Other settings (password, device ID, etc.) unchanged
```

### Batch Configuration (Multiple Devices)

```powershell
# PowerShell script for 10 devices
$devices = @(
  @{id="pico-1"; ssid="MainOffice"; password="pwd1"},
  @{id="pico-2"; ssid="MainOffice"; password="pwd1"},
  # ... more devices
)

foreach ($device in $devices) {
  .\configure_device_eeprom.ps1 `
    -DeviceId $device.id `
    -IotHubName "my-hub-123" `
    -Ssid $device.ssid `
    -Password $device.password `
    -Hostname ($device.id)
  
  Write-Host "Configured $($device.id)" -ForegroundColor Green
  Start-Sleep -Seconds 5  # Rate limit
}
```

### Secure Connection String Handling

Instead of passing plaintext connection string:

```powershell
# Option 1: Store in Azure Key Vault
$connStr = az keyvault secret show `
  --vault-name my-vault `
  --name device-conn-string `
  --query value -o tsv

.\configure_device_eeprom.ps1 `
  -DeviceId "pico-1" `
  -DeviceConnectionString $connStr `
  -IotHubName "my-hub-123"

# Option 2: Use environment variable
$connStr = $env:IOT_DEVICE_CONN_STR
```

### Fallback Configuration Chain

If EEPROM fails, device tries:

1. EEPROM (if valid marker 0xA5) ← Persistent
2. Twin desired properties (if connected) ← Cloud-managed
3. Compile-time defaults in iot_config.h ← Fallback

This ensures device always has some working config.

---

## Troubleshooting

### Issue: "Device not found in hub"

**Symptoms:**
```
Error: Device pico-1 not found in hub my-hub-123
```

**Solutions:**
```powershell
# 1. Verify device exists
az iot hub device-identity list -n my-hub-123 | grep pico-1

# 2. If missing, create it
az iot hub device-identity create -n my-hub-123 -d pico-1

# 3. Verify you're using correct hub name
az iot hub list
```

---

### Issue: Configuration Written to EEPROM but Not Applied

**Symptoms:**
- read_device_config.ps1 shows correct values
- Device won't connect to WiFi
- Serial output shows "using EEPROM"

**Root Causes & Solutions:**

```powershell
# 1. Check EEPROM marker is valid
# In serial monitor:
# [Config] EEPROM valid (0xA5)  ← Good
# [Config] EEPROM invalid        ← Bad

# If invalid, run firmware erase:
# arduino-cli run --port COM3 --fqbn rp2040:rp2040:rpipico2

# 2. Verify SSID/Password are correct
.\read_device_config.ps1 -ComPort COM3

# 3. Check WiFi signal strength
# Look at serial for: "WiFi signal strength: XX dBm"
# Should be > -70 dBm

# 4. Verify connected device can reach internet
# Use ping or curl from device (if implemented)
```

---

### Issue: Twin Update Not Reaching Device

**Symptoms:**
- `configure_device_eeprom.ps1` succeeds
- Device doesn't receive update
- Serial monitor shows "waiting for twin..."

**Diagnosis:**

```powershell
# 1. Verify device is connected to MQTT
az iot hub monitor-events -n my-hub-123 -d pico-1

# If no events coming through, device offline

# 2. Check device twin was actually updated
az iot hub device-twin show -n my-hub-123 -d pico-1

# Look for properties.desired section with "config"

# 3. Force device to sync twin
# Send command via serial: "TWIN SYNC" or
# Power cycle device (will re-read twin on startup)
```

---

### Issue: EEPROM Corruption

**Symptoms:**
- Garbage characters in read_device_config output
- Device reboots repeatedly
- EEPROM marker wrong

**Recovery:**

```powershell
# 1. Use device fallback to compile-time defaults
# Edit iot_config.h with known-good values
# Recompile and re-upload

# 2. Erase EEPROM flash sector via programmer
# (Requires Picoprobe or OpenOCD debugger)

# 3. Format EEPROM programmatically
# Modify firmware to call:
# Connect2Pico.ClearAllConfig();
# Connect2Pico.InitializeEEPROM();
```

---

### Issue: Cannot Upload Firmware (Serial Errors)

**Symptoms:**
```
Error: Failed to open COM3
Error: Serial port timeout
```

**Solutions:**

```powershell
# 1. Verify port is free
$port = "COM3"
[System.IO.Ports.SerialPort]::GetPortNames()

# 2. Check no other process using port
Get-Process | Where-Object {$_.Handles -gt 500} | Select-Object ProcessName, Id

# Kill PuTTY, Arduino IDE, etc. if open on same port

# 3. Try alternate COM port
.\set_com_port_env.ps1  # Select COM4

# 4. Verify bootloader is responding
# Hold BOOTSEL during upload
# Should see "Picotool" in output

# 5. Try USB Hub (if connecting directly to laptop)
# Some hubs have power issues
```

---

## Reference

### Configuration Limits

| Field | Max Size | Notes |
|-------|----------|-------|
| SSID | 32 bytes | WiFi SSID length limited to ~32 chars |
| Password | 64 bytes | WiFi password (8-63 chars typical) |
| Device ID | 32 bytes | Azure device name |
| Connection String | 256 bytes | Full IoT Hub connection string usually ~100-120 bytes |
| Hostname | 32 bytes | mDNS hostname (must be DNS-valid) |
| Hub FQDN | 64 bytes | IoT Hub domain (hub-name.azure-devices.net) |

### Serial Port Baud Rate

All Pico W serial communication: **115200 baud**

```powershell
# Example: Connect via PowerShell
$port = New-Object System.IO.Ports.SerialPort("COM3", 115200)
$port.Open()
$port.WriteLine("CONFIG READ")  # Send command
$output = $port.ReadLine()
$port.Close()
```

### Azure CLI Quick Reference

```powershell
# List all devices
az iot hub device-identity list -n my-hub-123

# Show device details
az iot hub device-identity show -n my-hub-123 -d pico-1

# Create device
az iot hub device-identity create -n my-hub-123 -d pico-1

# Show twin (desired + reported)
az iot hub device-twin show -n my-hub-123 -d pico-1

# Update twin desired properties
az iot hub device-twin update -n my-hub-123 -d pico-1 --desired '{"config": {"ssid": "NewNetwork"}}'

# Monitor telemetry
az iot hub monitor-events -n my-hub-123 -d pico-1
```

### Firmware Configuration Headers

**iot_config.h** - Compile-time defaults
```cpp
#define IOT_CONFIG_WIFI_SSID "DefaultSSID"
#define IOT_CONFIG_WIFI_PASSWORD "DefaultPassword"
#define IOT_CONFIG_DEVICE_ID "pico-default"
#define IOT_CONFIG_IOTHUB_FQDN "hub.azure-devices.net"
```

These are used when EEPROM is invalid or empty.

### Twin Update Format

Device listens for this JSON in twin.desired.config:

```json
{
  "config": {
    "ssid": "WiFiNetworkName",
    "password": "WiFiPassword123",
    "deviceId": "pico-1",
    "hostname": "pico-sensor-1",
    "hubFqdn": "my-hub-123.azure-devices.net",
    "applyAt": "2026-07-14T15:30:00Z"
  }
}
```

---

## See Also

- [DEVICE_CONFIG_QUICK_START.md](DEVICE_CONFIG_QUICK_START.md) - 5-minute setup
- [FIRMWARE_IMPLEMENTATION.md](FIRMWARE_IMPLEMENTATION.md) - Technical details
- [OTA_ADU_GUIDE.md](OTA_ADU_GUIDE.md) - Over-the-air updates
- [TCP_SERVICE_PROTOCOL.md](TCP_SERVICE_PROTOCOL.md) - Local command interface

