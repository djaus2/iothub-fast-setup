# Quick Start: Device Configuration

**Get a Pico W running with WiFi and Azure IoT Hub in 5 minutes.**

## Prerequisites

- Pico W/W2 with compiled Softata firmware
- USB cable connected to computer
- Azure IoT Hub with created device
- Device connection string handy

## Step 1: Upload Firmware

```powershell
cd c:\temp\IOTHUB_DUP\5a_PicoW
.\add_arduino_cli_to_path.ps1
arduino-cli upload --port COM3 --fqbn rp2040:rp2040:rpipico2 pico_firmware
```

Wait for: ✅ `Leaving...` message

## Step 2: Configure EEPROM (via Azure Twin)

```powershell
cd c:\temp\IOTHUB_DUP\6_Softata\scripts

.\configure_device_eeprom.ps1 `
  -DeviceId "picow1" `
  -IotHubName "my-hub-123" `
  -Ssid "YourNetworkName" `
  -Password "WiFiPassword" `
  -Hostname "pico-1"
```

**What this does:**
- Sends config to device twin
- Device firmware reads it
- Firmware writes to EEPROM
- Device restarts

**Time:** ~5-10 seconds

## Step 3: Verify Configuration

```powershell
.\read_device_config.ps1 -ComPort COM3
```

**Expected output:**
```
SSID: YourNetworkName
Hostname: pico-1
Device ID: picow1
Connected: Yes
```

## Step 4: Check Sensor Readings

```powershell
.\test_sensors.ps1 -ComPort COM3 -Duration 30
```

**Expected output:**
```
DHT11: Temp 22.5°C, Humidity 45%
BME280: Pressure 1013.25 hPa
```

---

## Done! 🎉

Your device is now:
- ✅ Connected to WiFi
- ✅ Configured with Azure IoT Hub
- ✅ Reading sensors
- ✅ Ready for OTA updates

**Next:** Monitor telemetry in Azure Portal or continue to Comprehensive Guide for advanced features.

---

## Troubleshooting (Quick)

| Issue | Fix |
|-------|-----|
| "Device not found" | Check device exists in IoT Hub: `az iot hub device-identity list -n my-hub-123` |
| Firmware won't upload | Check COM port: `.\set_com_port_env.ps1` |
| No sensor data | Verify sensors connected (DHT on GPIO 16, BME280 on I2C) |
| WiFi won't connect | Check SSID/password in EEPROM: `.\read_device_config.ps1 -ComPort COM3` |

