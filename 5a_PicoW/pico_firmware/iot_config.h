#pragma once

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
