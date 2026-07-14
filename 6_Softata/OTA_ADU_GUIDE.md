# OTA Methods Guide

## Overview

The Softata firmware supports **multiple OTA update paths** (fully available for RP2040):

1. **Arduino IDE OTA** ← PRIMARY METHOD (Just Enabled!)
2. **Azure Device Update (ADU)** ← Cloud-managed updates
3. **Web Browser** ← Optional (HTTPUpdateServer not yet implemented)
4. **Custom HTTP Stream** ← Optional (Update.writeStream not yet implemented)

---

## Method 1: Arduino IDE OTA (PRIMARY - Recommended)

### What It Does
- Once firmware connects to WiFi, device appears as a Network Port in Arduino IDE
- Upload new firmware directly from IDE without USB cable
- Identical workflow to USB upload - just select Network Port and click Upload

### Prerequisites
- Pico W running current Softata firmware
- Connected to same WiFi network as development computer
- Arduino IDE with RP2040 board support (already configured)
- `ENABLE_OTA=1` in iot_config.h (currently enabled)

### Step-by-Step Upload

1. **Connect Pico to WiFi**
   - Flash current firmware via USB bootloader (if not already running)
   - Device connects to WiFi and obtains IP address
   - Check serial output for: `[OTA] Ready - upload new sketch via Arduino IDE (Network port)`

2. **Locate Network Port in Arduino IDE**
   - Open Arduino IDE
   - Go to `Tools > Port`
   - Look for entry like: `picow-XXXXXX (ArduinoOTA)` or `[hostname].local`
   - **Note**: If not visible, ensure device WiFi connection is stable (check serial monitor)

3. **Select Network Port**
   - Click to select the Network Port entry
   - Verify hostname matches device EEPROM config (default: `device_id`)

4. **Upload Firmware**
   - Edit your sketch in Arduino IDE
   - Click **Upload** button (or `Ctrl+U`)
   - Progress shows in status bar: "Uploading..." → "Verifying..." → "Upload successful"
   - Device restarts with new firmware

### Troubleshooting Arduino IDE OTA

| Issue | Solution |
|-------|----------|
| Network Port not visible | Check WiFi connection, power cycle device, restart IDE |
| Upload fails mid-way | Move closer to WiFi router, reduce interference |
| "Connection refused" | Device may have crashed - restart and reconnect |
| Progress hangs at 95% | WiFi signal too weak - move device closer to router |

### Configuration

Edit `iot_config.h` to customize OTA behavior:
```cpp
#define ENABLE_OTA 1              // Enable/disable OTA
#define OTA_HOSTNAME "pico"       // Part of device name in IDE port list
#define OTA_PORT 8266             // Standard ArduinoOTA port (don't change)
```

Or use EEPROM to set device hostname at runtime:
```powershell
# PowerShell - Connect via TCP service (port 4242)
$device_ip = "192.168.1.100"
$hostname = "device-pico-1"
# Use configure_device_eeprom.ps1 to set EEPROM hostname
```

---

## Method 2: Azure Device Update (ADU) - Cloud-Managed Updates

### What It Does
- Upload firmware once to Azure Storage
- Push updates to all devices via IoT Hub Twin
- Devices pull and install automatically
- Managed rollout and rollback at scale

### Prerequisites
- Azure Device Update account (linked to IoT Hub)
- Pico W with current firmware (running)
- `ENABLE_OTA=1` for ADU fallback OTA support
- Firmware compiled and ready to upload

### Setting Up Azure Device Update

1. **Create ADU Account** (one-time setup)
   ```powershell
   # Via Azure Portal
   # 1. Go to IoT Hub > Settings > Device Update
   # 2. Create new Device Update for IoT Hub account
   # 3. Link existing Storage account (or create new)
   ```

2. **Upload Firmware Binary**
   ```powershell
   # Convert .uf2 to .bin
   # Method 1: Extract from .uf2 using elf2uf2 reversal tool
   # Method 2: Use arduino-cli with --export-binaries flag
   
   arduino-cli compile --fqbn rp2040:rp2040:rpipico2 pico_firmware --export-binaries
   # Binary will be in: build/pico_firmware.ino.bin
   
   # Upload to Azure Storage
   # Via Azure Portal: Device Update > Imports > Upload new update
   ```

3. **Create Deployment**
   ```powershell
   # In Azure Portal
   # Device Update > Deployments > Create new deployment
   # Select firmware version
   # Target device group (e.g., all RP2040 devices)
   # Deployment type: Standard (phased) or Immediate
   ```

4. **Monitor Update Progress**
   ```powershell
   az iot hub query --hub-name {HUB_NAME} \
     -q "select deviceId, properties.reported.adu from devices"
   ```

### OTA Workflow (Automated)

1. ADU sends `desiredVersion` to device twin
2. Device Core0 detects change via MQTT handler
3. Device downloads firmware from Azure Storage URL
4. Verifies hash (MD5/SHA256)
5. Writes to flash memory
6. Reports `reportedVersion` when complete
7. Automatically restarts with new firmware

---

## Method 3: Web Browser OTA (Optional - Not Implemented Yet)

The Arduino-Pico BSP supports HTTPUpdateServer for web-based updates:

```cpp
#include <HTTPUpdateServer.h>

HTTPUpdateServer httpUpdater;

void setup() {
  // ... other setup ...
  httpUpdater.setup(&server);
  server.begin();
}

void loop() {
  server.handleClient();
}
```

Access via: `http://device-hostname:8080/update`

**Current Status**: Not yet integrated - can be added if needed.

---

## Method 4: Custom HTTP Stream (Optional)

For custom firmware hosting or advanced workflows:

```cpp
// Not shown - uses Update.writeStream() directly
// Reference: Arduino-Pico source code
```

**Current Status**: Removed in favor of ArduinoOTA (more reliable).

---

## Comparison Table

| Feature | Arduino IDE OTA | ADU | Web Upload | Custom Stream |
|---------|-----------------|-----|------------|---------------|
| Setup Complexity | ⭐ Very Easy | ⭐⭐⭐ Medium | ⭐⭐ Easy | ⭐⭐⭐ Complex |
| Single Device | ✅ Perfect | ✅ Works | ✅ Works | ✅ Works |
| Fleet Deployment | ❌ Manual | ✅ Automatic | ❌ Manual | ⚠️ Custom |
| Security | ✅ Strong | ✅ Very Strong | ✅ Can be Strong | ⚠️ Depends |
| Cloud Integration | ❌ No | ✅ Full | ❌ No | ❌ No |
| Network Requirement | ✅ WiFi | ✅ WiFi + Azure | ✅ WiFi | ✅ WiFi |

---

## Reference: Arduino-Pico OTA Documentation

Full documentation and security options available at:
[Arduino-Pico OTA Documentation](https://arduino-pico.readthedocs.io/en/latest/ota.html)

Includes:
- Password-protected OTA
- Signed firmware verification (RSA-2048 + SHA256)
- GZIP compression support
- Bootloader with fail-safe mechanisms

### Prerequisites

- IoT Hub **Standard tier** (S1 or higher)
- Device Update account linked to IoT Hub
- Firmware binary (.bin) hosted on Azure Storage or CDN

### Architecture

```
Azure Storage (Firmware Binary)
    ↓
Device Twin (desiredVersion field)
    ↓
Pico Firmware (monitors twin)
    ↓
Downloads & Installs
    ↓
Reports via reportedVersion
```

### Setup ADU

#### 1. Create Device Update Account

```powershell
az resource create `
  --resource-group "my-rg" `
  --resource-type "Microsoft.DeviceUpdate/accounts" `
  --name "my-adu-account" `
  --location "eastus"
```

#### 2. Link to IoT Hub

```powershell
az iot hub linked-backend create `
  --hub-name "my-iot-hub" `
  --resource-group "my-rg" `
  --linked-backend-name "my-adu-account"
```

#### 3. Upload Firmware Binary

```powershell
# Create a container in your storage account
az storage container create `
  --account-name "mystorageaccount" `
  --name "firmware"

# Upload firmware
az storage blob upload `
  --account-name "mystorageaccount" `
  --container-name "firmware" `
  --name "pico-v1.0.1.bin" `
  --file "./pico_firmware.ino.bin"

# Get public URL
az storage blob url `
  --account-name "mystorageaccount" `
  --container-name "firmware" `
  --name "pico-v1.0.1.bin"
```

### Trigger OTA Update

#### Method 1: PowerShell Script

```powershell
.\6_Softata\scripts\trigger_ota_update.ps1 `
  -DeviceId "picow1" `
  -IotHubName "my-iot-hub" `
  -NewVersion "1.0.1" `
  -FirmwareUrl "https://mystorageaccount.blob.core.windows.net/firmware/pico-v1.0.1.bin"
```

#### Method 2: Manual Twin Update

```powershell
az iot hub device-twin update `
  -n "my-iot-hub" `
  -d "picow1" `
  --desired '{
    "desiredVersion": "1.0.1",
    "firmwareUrl": "https://mystorageaccount.blob.core.windows.net/firmware/pico-v1.0.1.bin",
    "updateTime": "'$(Get-Date -Format O)'"
  }'
```

#### Method 3: Azure Portal

1. Open **Device Update** in Azure Portal
2. Select device: `picow1`
3. Go to **Deployments**
4. **Create new deployment**
5. Select `.bin` file
6. Target devices
7. **Create**

### Firmware: Monitor & Handle Updates

In `pico_firmware.ino`:

```cpp
#include "Connect2Pico.h"
#include <Update.h>

String currentVersion = APP_VERSION;
String desiredVersion;
String reportedVersion;
String firmwareUrl;

void handleTwinUpdate() {
  // Check if desiredVersion changed
  if (desiredVersion != reportedVersion) {
    Serial.printf("Update available: %s -> %s\n", reportedVersion.c_str(), desiredVersion.c_str());
    
    // Download and install
    if (downloadAndInstallFirmware(firmwareUrl)) {
      reportedVersion = desiredVersion;
      updateTwinReportedVersion();
    }
  }
}

bool downloadAndInstallFirmware(const String& url) {
  Serial.printf("Downloading firmware from: %s\n", url.c_str());
  
  WiFiClientSecure client;
  client.setInsecure();  // For testing only
  
  if (!client.connect(url.c_str(), 443)) {
    Serial.println("Connection failed");
    return false;
  }
  
  // Send HTTP GET request
  client.print("GET /path/to/firmware.bin HTTP/1.1\r\n");
  client.print("Host: " + String(url) + "\r\n");
  client.print("Connection: close\r\n\r\n");
  
  // Parse HTTP response
  bool inBody = false;
  int contentLength = 0;
  
  while (client.connected()) {
    String line = client.readStringUntil('\n');
    
    if (!inBody) {
      if (line.startsWith("Content-Length:")) {
        contentLength = line.substring(15).toInt();
      }
      if (line == "\r") {
        inBody = true;
      }
    }
  }
  
  // Start firmware update
  if (!Update.begin(contentLength)) {
    Serial.println("OTA begin failed");
    return false;
  }
  
  // Stream firmware to flash
  while (client.available()) {
    uint8_t buffer[512];
    int len = client.read(buffer, sizeof(buffer));
    
    if (len > 0) {
      Update.write(buffer, len);
    }
  }
  
  // Finalize and verify
  if (!Update.end(true)) {
    Serial.println("OTA failed");
    return false;
  }
  
  Serial.println("OTA successful - restarting");
  delay(1000);
  
  // Restart to load new firmware
  rp2040_watchdog.reboot();
  
  return true;
}

void updateTwinReportedVersion() {
  // Update twin reported properties
  String json = "{\"properties\": {\"reported\": {\"reportedVersion\": \"" 
    + reportedVersion + "\"}}}";
  
  // Publish via MQTT
  String topic = "$aws/things/" + deviceId + "/shadow/update";
  mqttClient.publish(topic.c_str(), json.c_str());
}
```

### Monitor Update Progress

```powershell
# Watch device twin for update status
while ($true) {
  $twin = az iot hub device-twin show `
    -n "my-iot-hub" `
    -d "picow1" | ConvertFrom-Json
  
  $desired = $twin.properties.desired.desiredVersion
  $reported = $twin.properties.reported.reportedVersion
  
  Write-Host "Desired: $desired | Reported: $reported"
  
  if ($reported -eq $desired) {
    Write-Host "✓ Update complete!"
    break
  }
  
  Start-Sleep -Seconds 5
}
```

### Safety Considerations

#### 1. Signature Verification

Add firmware signature verification:

```cpp
#include <Ed25519.h>

bool verifyFirmwareSignature(const uint8_t* firmware, size_t size, const uint8_t* signature) {
  // Verify signature before installing
  return Ed25519::verify(signature, firmware, size, PUBLIC_KEY);
}
```

#### 2. Rollback on Failure

Store previous firmware and rollback if new one fails:

```cpp
#define FIRMWARE_A_OFFSET 0x00010000
#define FIRMWARE_B_OFFSET 0x00100000

void installFirmwareWithRollback(const uint8_t* newFirmware, size_t size) {
  // Backup current to slot B
  copyFlash(FIRMWARE_A_OFFSET, FIRMWARE_B_OFFSET, size);
  
  // Install new to slot A
  if (!writeFlashAndVerify(FIRMWARE_A_OFFSET, newFirmware, size)) {
    // Restore from backup
    copyFlash(FIRMWARE_B_OFFSET, FIRMWARE_A_OFFSET, size);
    Serial.println("Rollback completed");
    return;
  }
  
  Serial.println("Update successful");
}
```

#### 3. Staged Rollout

Update one device at a time:

```powershell
# Update devices in sequence
$devices = "picow1", "picow2", "picow3"

foreach ($device in $devices) {
  .\6_Softata\scripts\trigger_ota_update.ps1 `
    -DeviceId $device `
    -NewVersion "1.0.1"
  
  # Wait for completion
  Start-Sleep -Seconds 120
  
  # Check status
  $twin = az iot hub device-twin show -n "my-iot-hub" -d $device | ConvertFrom-Json
  $reported = $twin.properties.reported.reportedVersion
  
  if ($reported -ne "1.0.1") {
    Write-Error "Update failed for $device"
    break
  }
}
```

---

## Version Management

### Version Numbering

Follow semantic versioning:

```
MAJOR.MINOR.PATCH
1.0.1
│ │ └─ Patch: Bug fixes, no new features
│ └─── Minor: New features, backward compatible
└───── Major: Breaking changes
```

### Track Versions in Twin

```json
{
  "properties": {
    "desired": {
      "desiredVersion": "1.0.1"
    },
    "reported": {
      "reportedVersion": "1.0.1",
      "buildDate": "2026-07-14T10:30:00Z",
      "updateHistory": [
        {
          "version": "1.0.0",
          "timestamp": "2026-07-10T08:00:00Z",
          "status": "success"
        },
        {
          "version": "1.0.1",
          "timestamp": "2026-07-14T10:30:00Z",
          "status": "success"
        }
      ]
    }
  }
}
```

---

## Troubleshooting

### Update Stuck / Not Starting

```powershell
# Reset twin version to current
az iot hub device-twin update `
  -n "my-iot-hub" `
  -d "picow1" `
  --desired '{"desiredVersion": "'$currentVersion'"}'
```

### Download Failure (Network)

```cpp
// Add retry logic in firmware
const int MAX_RETRIES = 3;

for (int i = 0; i < MAX_RETRIES; i++) {
  if (downloadAndInstallFirmware(firmwareUrl)) {
    return true;
  }
  delay(5000 * (i + 1));  // Exponential backoff
}

// Give up and revert
reportedVersion = "failed";
return false;
```

### Signature Verification Failed

```powershell
# Check firmware hash
Get-FileHash -Path "pico_firmware.ino.bin" -Algorithm SHA256
```

---

## Related Files

- `pico_firmware.ino` — Main update handler
- `iot_config.h` — Feature toggles
- `Connect2Pico.h` — Version tracking in EEPROM
- Scripts in `6_Softata/scripts/` — Update management

