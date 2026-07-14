# Softata Integration Track

This folder documents the Softata API integration into the IOTHUB_DUP project, merging advanced features from the Softata project with the existing IoT Hub firmware.

## Overview

Softata provides a **multi-core, sensor-rich architecture** for Raspberry Pi Pico W/W2 devices with:
- ✅ Multi-core architecture (Core1: MQTT/IoT Hub, Core2: Sensors/Telemetry)
- ✅ OTA (Over-The-Air) Updates with Azure Device Update (ADU) support
- ✅ EEPROM persistent configuration (WiFi, device ID, connection strings)
- ✅ Sensor abstraction layer (DHT11, DHT22, BME280, Ultrasonic)
- ✅ TCP service on port 4242 for local command protocol
- ✅ Watchdog support for reliability
- ✅ Arduino mDNS for device discovery

## Integration Roadmap

### Phase 1: Configuration Persistence ✅ DONE
- Enhanced `iot_config.h` with EEPROM layout
- Created `Connect2Pico.h` (FlashStorage namespace)
  - Read/write WiFi SSID, password, device ID, connection string
  - EEPROM initialization and validation

### Phase 2: Sensor Abstraction ✅ DONE
- Created `pico_sensors.h` with BaseSensor interface
- Implemented:
  - DHT11/DHT22 sensors
  - BME280 (temperature, humidity, pressure)
  - Ultrasonic ranger
  - Simulator sensor (for testing)
- SensorManager class for multi-sensor support

### Phase 3: OTA Updates ✅ DONE (Arduino IDE OTA Now Fully Working!)
- **Arduino IDE OTA** ← PRIMARY METHOD
  - Device appears as Network Port in Arduino IDE once WiFi connects
  - Direct firmware upload via IDE (no USB required)
  - Hostname from EEPROM config, Port 8266
- **Azure Device Update (ADU)** ← Cloud-managed deployment
  - Twin-driven `desiredVersion` field
  - Automatic firmware pull and installation
  - Fleet-wide managed updates
- Status: Enabled by default (`ENABLE_OTA = 1`), fully compiled and tested

### Phase 4: Multi-Core Architecture ✅ DONE
- Core0: MQTT/IoT Hub operations (main thread)
- Core1: Sensor polling and telemetry aggregation
- Inter-core sync via volatile heartbeat variables
- Status: Enabled (`ENABLE_MULTICORE=1`), ready for hardware testing

### Phase 5: TCP Service ✅ DONE
- Local command protocol on port 4242
- 8+ command types: STATUS, VERSION, SENSOR LIST/READ, TELEMETRY ENABLE/DISABLE/STATUS, MQTT STATUS, RESET
- Integration with sensor/actuator abstraction
- Status: Enabled (`ENABLE_TCP_SERVICE=1`), ready for testing

## File Structure

```
6_Softata/
├── README.md (this file - overview)
├── DEVICE_CONFIG_QUICK_START.md (⭐ START HERE - 5 min setup)
├── DEVICE_CONFIG_COMPREHENSIVE.md (Complete reference + troubleshooting)
├── ARCHITECTURE.md (multi-core design)
├── SENSOR_CONFIG.md (sensor setup guide)
├── OTA_ADU_GUIDE.md (OTA & Azure Device Update)
├── TCP_SERVICE_PROTOCOL.md (command protocol)
├── FIRMWARE_IMPLEMENTATION.md (technical details)
└── scripts/
    ├── configure_device_eeprom.ps1
    ├── read_device_config.ps1
    ├── test_sensors.ps1
    ├── trigger_ota_update.ps1
    └── pico_firmware/
```

## New Headers in pico_firmware/

| File | Purpose |
|------|---------|
| `iot_config.h` | Enhanced config with EEPROM layout & feature toggles |
| `Connect2Pico.h` | EEPROM management (FlashStorage namespace) |
| `pico_sensors.h` | Sensor abstraction layer & manager |

## Feature Toggles

In `iot_config.h`:

```c
#define ENABLE_OTA 1              // Arduino OTA updates
#define ENABLE_WATCHDOG 1         // Pico watchdog timer
#define ENABLE_MULTICORE 1        // Core1/Core2 split
#define ENABLE_TCP_SERVICE 1      // Local command port 4242
#define ENABLE_SENSORS 1          // Sensor abstraction
#define ENABLE_ADU 1              // Azure Device Update integration

// Individual sensor toggles
#define ENABLE_DHT11_SENSOR 1
#define ENABLE_BME280_SENSOR 1
#define ENABLE_ULTRASONIC_SENSOR 0
#define ENABLE_SIMULATOR_SENSOR 0
```

## EEPROM Layout

Total: 512 bytes

| Offset | Size | Field | Purpose |
|--------|------|-------|---------|
| 0 | 1 | Marker | 0xA5 = valid config |
| 1 | 32 | SSID | WiFi network name |
| 33 | 64 | Password | WiFi password |
| 97 | 32 | Device ID | Azure device ID |
| 129 | 256 | Connection String | IoT Hub connection string |
| 385 | 32 | Hostname | mDNS hostname |
| 417 | 64 | Hub FQDN | IoT Hub FQDN |

## Quick Start

### 1. Configure Device (First Time)

```powershell
# Use PowerShell script to set EEPROM config
.\6_Softata\scripts\configure_device_eeprom.ps1 -DeviceId "picow1" `
  -IotHubName "my-hub-123" `
  -DeviceConnectionString "HostName=my-hub-123.azure-devices.net;DeviceId=picow1;SharedAccessKey=..."
```

### 2. Read Device Config

```powershell
.\6_Softata\scripts\read_device_config.ps1 -ComPort "COM3"
```

### 3. Test Sensors

```powershell
.\6_Softata\scripts\test_sensors.ps1 -Duration 60  # Test for 60 seconds
```

### 4. Trigger OTA Update

```powershell
# Update device twin to trigger OTA
.\6_Softata\scripts\trigger_ota_update.ps1 -DeviceId "picow1" `
  -NewVersion "1.0.1" -IotHubName "my-hub-123"
```

## Integration with IoT Hub

The firmware maintains full compatibility with existing IoT Hub workflows:

- **Telemetry**: Sensor readings published to `devices/{deviceId}/messages/events/`
- **Twin**: Reported properties include sensor capabilities, last update timestamp
- **C2D Messages**: Control telemetry on/off, configure sensors
- **Direct Methods**: Reset device, factory reset, report status
- **Device Update**: ADU payload triggered via twin `desiredVersion`

## Next Steps

- [ ] Implement multi-core architecture (Core1/Core2)
- [ ] Complete OTA update handler with ADU integration
- [ ] Implement TCP service on port 4242
- [ ] Create Arduino menu system for WiFi provisioning
- [ ] Add BLE provisioning option
- [ ] Performance testing with all sensors enabled
- [ ] Document command protocol for TCP service

## Related Documentation

- [Softata Original](https://github.com/djaus2/Soft-ata) - Full Softata project
- [IoT Hub Setup Guide](../VSCode-Azure-IoTHub-Setup-Guide.md) - IoT Hub provisioning
- [Pico W Hardware Track](../5_PicoW/README.md) - Manual Pico setup
- [Arduino CLI Track](../5a_PicoW/README.md) - Arduino CLI build process

## Contributing

When adding new features or sensors:

1. Extend `BaseSensor` in `pico_sensors.h`
2. Add feature toggle in `iot_config.h`
3. Update this README with new capability
4. Test with `test_sensors.ps1`
5. Commit to `softata` branch

