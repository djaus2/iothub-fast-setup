# OTA & Azure Device Update (ADU) Guide

## Overview

The Softata firmware supports **two OTA update paths**:

1. **Arduino OTA** — Direct upload via Arduino IDE or web interface
2. **Azure Device Update (ADU)** — Managed updates via IoT Hub twin

## Arduino OTA

### Enabling Arduino OTA

In `iot_config.h`:
```cpp
#define ENABLE_OTA 1
```

### Upload via Arduino IDE

1. Open `Tools > Port` and select the COM port
2. Go to `Tools > Network Ports` and find `picow1.local` (or your device hostname)
3. Click the upload button
4. Firmware uploads via WiFi (no USB required after first upload)

### Upload via Web Browser

The device exposes an OTA update page:

```
http://picow1.local:8080
```

Upload `.bin` file directly.

### Command-Line OTA (Linux/macOS)

```bash
curl -X POST \
  -F "update=@pico_firmware.ino.uf2" \
  http://picow1.local:8080/update
```

---

## Azure Device Update (ADU)

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

