#pragma once

#include <EEPROM.h>

// ========== DEVICE CONFIGURATION ==========
// Replace these placeholders with values for your device.
// Keep secrets out of source control.

#ifndef IOT_CONFIG_WIFI_SSID
#define IOT_CONFIG_WIFI_SSID "SSID"
#endif

#ifndef IOT_CONFIG_WIFI_PASSWORD
#define IOT_CONFIG_WIFI_PASSWORD "PWD"
#endif

#ifndef IOT_CONFIG_IOTHUB_FQDN
#define IOT_CONFIG_IOTHUB_FQDN "YOUR_HUB.azure-devices.net"
#endif

#ifndef IOT_CONFIG_DEVICE_ID
#define IOT_CONFIG_DEVICE_ID "picow1"
#endif

#ifndef IOT_CONFIG_DEVICE_KEY
#define IOT_CONFIG_DEVICE_KEY "YOUR_DEVICE_PRIMARY_KEY"
#endif

// Azure IoT Hub MQTT defaults
#define IOT_CONFIG_MQTT_PORT 8883

// ========== EEPROM CONFIGURATION ==========
// Persistent storage for WiFi, device ID, connection string, etc.

#define EEPROM_SIZE 512
#define EEPROM_VALID_MARKER 0xA5  // Marker to detect first-time setup

// EEPROM layout (byte offsets)
#define EEPROM_OFFSET_MARKER 0           // 1 byte: 0xA5 if valid
#define EEPROM_OFFSET_SSID 1             // 32 bytes: WiFi SSID
#define EEPROM_OFFSET_PASSWORD 33        // 64 bytes: WiFi password
#define EEPROM_OFFSET_DEVICE_ID 97       // 32 bytes: Device ID
#define EEPROM_OFFSET_CONNECTION_STR 129 // 256 bytes: Connection string
#define EEPROM_OFFSET_HOSTNAME 385       // 32 bytes: Hostname for mDNS
#define EEPROM_OFFSET_HUB_FQDN 417       // 64 bytes: Hub FQDN

// Derived lengths
#define EEPROM_LEN_SSID 32
#define EEPROM_LEN_PASSWORD 64
#define EEPROM_LEN_DEVICE_ID 32
#define EEPROM_LEN_CONNECTION_STR 256
#define EEPROM_LEN_HOSTNAME 32
#define EEPROM_LEN_HUB_FQDN 64

// Configuration menu timeouts
#define MENU_TIMEOUT_SEC 15
#define WIFI_CONNECT_TIMEOUT_SEC 20

// ========== FEATURE TOGGLES ==========
#define ENABLE_OTA 0              // Arduino OTA not available for RP2040; use PicoOTA or ADU instead
#define ENABLE_WATCHDOG 0         // Watchdog via rp2040_multicore
#define ENABLE_MULTICORE 1        // Dual-core architecture
#define ENABLE_TCP_SERVICE 1      // TCP service on port 4242
#define ENABLE_SENSORS 1          // Sensor support
#define ENABLE_BLUETOOTH 0        // Bluetooth hardware support

// TCP Service port
#define TCP_SERVICE_PORT 4242

// ========== SENSOR CONFIGURATION ==========
// Available sensors: DHT11, DHT22, BME280, UltrasonicRanger, Simulator
#define ENABLE_DHT11_SENSOR 1
#define ENABLE_BME280_SENSOR 1
#define ENABLE_ULTRASONIC_SENSOR 0
#define ENABLE_SIMULATOR_SENSOR 0

#define DHT11_PIN 16  // Grove pin for DHT11
#define ULTRASONIC_TRIG_PIN 12
#define ULTRASONIC_ECHO_PIN 13

// ========== MULTI-CORE CONFIGURATION ==========
#define CORE1_PRIORITY_MQTT 1    // Core1: MQTT/IoT Hub
#define CORE2_PRIORITY_SENSORS 2 // Core2: Sensors/Telemetry

// Synced command multiplier for inter-core communication
#define CORE_SYNC_MULTIPLIER 1000

// ========== ADU (Azure Device Update) CONFIGURATION ==========
#define ENABLE_ADU 1
#define ADU_UPDATE_TIMEOUT_SEC 300  // 5 minutes
