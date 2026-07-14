# Softata Documentation Index

**Complete navigation guide for Softata firmware, configuration, and deployment.**

---

## Quick Navigation

**Just getting started?** → Start with [Quick Start](#quick-start)  
**Need detailed answers?** → Use [Complete Reference](#complete-reference)  
**Building or deploying?** → See [Implementation](#implementation)

---

## Quick Start ⭐

**Get a working device in 5 minutes**

- [DEVICE_CONFIG_QUICK_START.md](6_Softata/DEVICE_CONFIG_QUICK_START.md)
  - Upload firmware
  - Configure EEPROM
  - Verify setup
  - Quick troubleshooting

---

## Complete Reference 📚

### Device Configuration & Setup

- [DEVICE_CONFIG_COMPREHENSIVE.md](6_Softata/DEVICE_CONFIG_COMPREHENSIVE.md) - **START HERE for details**
  - Architecture overview with diagrams
  - EEPROM layout (all 512 bytes explained)
  - Configuration methods (Twin, Serial, Compile-time)
  - Step-by-step workflows
  - Advanced scenarios (batch setup, secure handling)
  - Extensive troubleshooting (6+ common issues)
  - Reference (limits, CLI commands, JSON formats)

### Hardware & Sensors

- [SENSOR_CONFIG.md](6_Softata/SENSOR_CONFIG.md)
  - DHT11/DHT22 temperature/humidity
  - BME280 temperature/humidity/pressure
  - Ultrasonic distance sensors
  - Wiring diagrams
  - Code examples
  - Calibration & troubleshooting

### Multi-Core Architecture

- [ARCHITECTURE.md](6_Softata/ARCHITECTURE.md)
  - Dual-core design (Core0: MQTT, Core1: Sensors)
  - Inter-core communication
  - Memory layout
  - Startup sequence
  - Watchdog strategy

### Over-The-Air Updates

- [OTA_ADU_GUIDE.md](6_Softata/OTA_ADU_GUIDE.md)
  - **Arduino IDE OTA** (primary method)
  - Azure Device Update (cloud-managed)
  - Web browser updates
  - Custom HTTP streaming
  - Security & integrity verification
  - Troubleshooting OTA failures

### Local Control & Commands

- [TCP_SERVICE_PROTOCOL.md](6_Softata/TCP_SERVICE_PROTOCOL.md)
  - TCP service on port 4242
  - Command format & examples
  - 15+ commands (STATUS, SENSOR, TELEMETRY, MQTT, etc.)
  - Error codes
  - PowerShell & Python clients

---

## Implementation 🔧

### Technical Details

- [FIRMWARE_IMPLEMENTATION.md](6_Softata/FIRMWARE_IMPLEMENTATION.md)
  - Compilation results (278KB, 72KB RAM)
  - Feature checklist
  - Hardware testing steps
  - Azure integration verification
  - Verification checklist

### Overview & Roadmap

- [README.md](6_Softata/README.md)
  - Integration roadmap (Phases 1-5, all complete)
  - Feature toggles
  - EEPROM layout summary
  - Quick start commands

---

## PowerShell Scripts 🚀

Located in `6_Softata/scripts/`:

### Configuration Management

- **configure_device_eeprom.ps1**
  - Push config to device via Azure Twin
  - Set WiFi SSID, password, hostname
  - Works with running devices
  - Usage: See [DEVICE_CONFIG_COMPREHENSIVE.md](6_Softata/DEVICE_CONFIG_COMPREHENSIVE.md#step-2-configure-eeprom-via-azure-twin)

- **read_device_config.ps1**
  - Read EEPROM values from device via serial
  - Verify configuration was saved
  - Usage: `.\read_device_config.ps1 -ComPort COM3`

### Testing & Monitoring

- **test_sensors.ps1**
  - Monitor sensor readings over serial
  - Real-time temperature, humidity, pressure
  - Usage: `.\test_sensors.ps1 -ComPort COM3 -Duration 60`

### OTA Updates

- **trigger_ota_update.ps1**
  - Trigger firmware update via device twin
  - Azure Device Update integration
  - Usage: See [OTA_ADU_GUIDE.md](6_Softata/OTA_ADU_GUIDE.md)

### Setup Helpers

- **set_com_port_env.ps1** (in `5a_PicoW/`)
  - Detect and set Arduino COM port
  - Interactive selection
  - Used before uploads

- **add_arduino_cli_to_path.ps1** (in `5a_PicoW/`)
  - Add Arduino CLI to system PATH
  - Run once per terminal session

---

## Firmware Source Code 💻

Located in `5a_PicoW/pico_firmware/`:

### Main Application

- **pico_firmware.ino** (1100+ lines)
  - Multi-core MQTT + sensors
  - OTA update handler
  - TCP service (port 4242)
  - Device twin integration
  - Telemetry publisher

### Configuration Headers

- **iot_config.h**
  - EEPROM layout definitions (512 bytes)
  - Feature toggles (OTA, watchdog, multi-core, sensors)
  - Compile-time defaults
  - Pin definitions

- **Connect2Pico.h**
  - EEPROM read/write interface
  - Config getters/setters
  - Initialization & validation
  - Fallback logic

- **pico_sensors.h**
  - Sensor abstraction layer
  - BaseSensor interface
  - Implementations:
    - DHTSensor (DHT11/DHT22)
    - BME280Sensor (pressure, altitude)
    - UltrasonicSensor (distance)
    - SimulatorSensor (testing)
  - SensorManager (multi-sensor support)

### Compiled Output

- **build/pico_firmware.ino.uf2**
  - Ready to upload to Pico W
  - 278 KB binary (6% of 4MB flash)
  - All features enabled

---

## Hardware Specifications 🔌

### Pico W / Pico W2 (RP2040)

| Component | Capacity | Current Usage |
|-----------|----------|---------------|
| **Flash** | 4 MB | 278 KB (6%) |
| **RAM** | 264 KB | 72 KB (27%) |
| **EEPROM** | 512 bytes | Full (100%) |
| **CPU** | Dual-core Cortex-M0+ @ 125 MHz | Both cores active |
| **GPIO** | 28 pins | 6+ used (SDA, SCL, DHT, etc.) |
| **WiFi** | 802.11b/g/n | Active (WPA2) |
| **USB** | Micro-B | Programming & serial |

### Pin Assignments

- **I2C0**: SDA=GPIO8, SCL=GPIO9 (BME280)
- **DHT11**: GPIO16 (configurable)
- **Ultrasonic**: Trigger=GPIO12, Echo=GPIO13
- **UART0**: TX=GPIO0, RX=GPIO1 (Serial)

---

## Azure Integration 🌐

### IoT Hub Connectivity

- **MQTT Port**: 8883 (TLS)
- **Topics**:
  - Telemetry: `devices/{deviceId}/messages/events/`
  - Device Twin: `$iothub/twin/GET/?$rid={requestId}`
  - C2D Messages: `devices/{deviceId}/messages/devicebound/#`

### Device Twin Properties

**Desired (Cloud → Device):**
```json
{
  "config": {
    "ssid": "WiFiNetwork",
    "password": "WiFiPassword",
    "hostname": "pico-1",
    "applyAt": "2026-07-14T15:30:00Z"
  }
}
```

**Reported (Device → Cloud):**
```json
{
  "version": "1.0.0",
  "sensors": ["DHT11", "BME280"],
  "connected": true,
  "signalStrength": -65
}
```

---

## Feature Status ✅

All core features **fully implemented and tested**:

- ✅ Multi-core architecture (Core0: MQTT, Core1: Sensors)
- ✅ EEPROM persistence (512 bytes, all fields)
- ✅ ArduinoOTA (Arduino IDE + Network port)
- ✅ Azure Device Update framework (ADU-ready)
- ✅ Sensor abstraction (4 implementations)
- ✅ TCP service (port 4242, 8+ commands)
- ✅ Telemetry aggregation
- ⚠️ Watchdog (framework present, pending full testing)
- ⚠️ Bluetooth (framework present, disabled)

---

## Common Tasks

### I want to...

**Upload firmware to a Pico W**
→ [DEVICE_CONFIG_QUICK_START.md](6_Softata/DEVICE_CONFIG_QUICK_START.md#step-1-upload-firmware)

**Configure WiFi and device ID**
→ [DEVICE_CONFIG_QUICK_START.md](6_Softata/DEVICE_CONFIG_QUICK_START.md#step-2-configure-eeprom-via-azure-twin)

**Understand the architecture**
→ [ARCHITECTURE.md](6_Softata/ARCHITECTURE.md)

**Set up sensors**
→ [SENSOR_CONFIG.md](6_Softata/SENSOR_CONFIG.md)

**Deploy OTA updates**
→ [OTA_ADU_GUIDE.md](6_Softata/OTA_ADU_GUIDE.md)

**Control device locally**
→ [TCP_SERVICE_PROTOCOL.md](6_Softata/TCP_SERVICE_PROTOCOL.md)

**Troubleshoot configuration issues**
→ [DEVICE_CONFIG_COMPREHENSIVE.md#troubleshooting](6_Softata/DEVICE_CONFIG_COMPREHENSIVE.md#troubleshooting)

**Deploy 10+ devices at once**
→ [DEVICE_CONFIG_COMPREHENSIVE.md#batch-configuration-multiple-devices](6_Softata/DEVICE_CONFIG_COMPREHENSIVE.md#batch-configuration-multiple-devices)

---

## File Structure

```
c:\temp\IOTHUB_DUP\
├── 5a_PicoW/                          # Pico W firmware & scripts
│   ├── pico_firmware/
│   │   ├── pico_firmware.ino          # Main application (1100+ lines)
│   │   ├── iot_config.h               # EEPROM layout & toggles
│   │   ├── Connect2Pico.h             # EEPROM management
│   │   ├── pico_sensors.h             # Sensor abstraction
│   │   └── build/pico_firmware.ino.uf2 # Compiled binary (ready to flash)
│   ├── add_arduino_cli_to_path.ps1    # Setup helper
│   ├── set_com_port_env.ps1           # Port detection
│   └── install_arduino_cli.ps1        # Arduino CLI installer
│
├── 6_Softata/                         # Softata integration docs
│   ├── 📍 INDEX.md                     # THIS FILE
│   ├── ⭐ DEVICE_CONFIG_QUICK_START.md (5-minute setup)
│   ├── 📚 DEVICE_CONFIG_COMPREHENSIVE.md (complete reference)
│   ├── FIRMWARE_IMPLEMENTATION.md      # Technical specs
│   ├── ARCHITECTURE.md                 # Multi-core design
│   ├── SENSOR_CONFIG.md               # Sensor setup
│   ├── OTA_ADU_GUIDE.md               # Over-the-air updates
│   ├── TCP_SERVICE_PROTOCOL.md        # Local commands
│   ├── README.md                      # Overview
│   └── scripts/
│       ├── configure_device_eeprom.ps1  # Twin config
│       ├── read_device_config.ps1       # Serial read
│       ├── test_sensors.ps1             # Sensor monitor
│       └── trigger_ota_update.ps1       # OTA trigger
│
├── 1_QuickSetup/                      # Azure setup scripts
├── 3_Simulator/                       # Device simulator
├── 4_ADU/                            # Device Update scripts
├── 5_PicoW/                          # Original Pico W setup
└── csharp_simulator/                 # C# simulator app
```

---

## Getting Help

**Quick question?** → Check [DEVICE_CONFIG_COMPREHENSIVE.md](6_Softata/DEVICE_CONFIG_COMPREHENSIVE.md#reference)

**Device won't connect?** → See [Troubleshooting](6_Softata/DEVICE_CONFIG_COMPREHENSIVE.md#troubleshooting)

**Want to learn the architecture?** → Read [ARCHITECTURE.md](6_Softata/ARCHITECTURE.md)

**Need code examples?** → Check [SENSOR_CONFIG.md](6_Softata/SENSOR_CONFIG.md) or [TCP_SERVICE_PROTOCOL.md](6_Softata/TCP_SERVICE_PROTOCOL.md)

**Missing something?** → All documentation is in `6_Softata/` folder

---

## Version Info

- **Firmware**: v1.0.0
- **Arduino-Pico BSP**: 5.6.1
- **Documentation**: 2026-07-14
- **Repository**: softata branch
- **Status**: ✅ Production-ready

---

**Last Updated**: 2026-07-14  
**Documentation Scope**: Softata integration for Pico W/W2 with Azure IoT Hub
