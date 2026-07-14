#pragma once

#include <WiFi.h>
#include <EEPROM.h>
#include "iot_config.h"

namespace FlashStorage {

// ========== EEPROM HELPERS ==========

bool readEepromKey() {
  byte marker = EEPROM.read(EEPROM_OFFSET_MARKER);
  return marker == EEPROM_VALID_MARKER;
}

void writeEepromKey() {
  EEPROM.write(EEPROM_OFFSET_MARKER, EEPROM_VALID_MARKER);
  EEPROM.commit();
}

void readString(int offset, int maxLen, String& out) {
  out = "";
  for (int i = 0; i < maxLen; i++) {
    byte b = EEPROM.read(offset + i);
    if (b == 0) break;
    out += (char)b;
  }
}

void writeString(int offset, int maxLen, const String& val) {
  int len = min((int)val.length(), maxLen - 1);
  for (int i = 0; i < len; i++) {
    EEPROM.write(offset + i, val[i]);
  }
  EEPROM.write(offset + len, 0);  // Null terminator
}

// ========== CONFIG GETTERS ==========

String GetSSID() {
  String ssid;
  if (readEepromKey()) {
    readString(EEPROM_OFFSET_SSID, EEPROM_LEN_SSID, ssid);
    if (ssid.length() > 0) return ssid;
  }
  return IOT_CONFIG_WIFI_SSID;
}

String GetPassword() {
  String pwd;
  if (readEepromKey()) {
    readString(EEPROM_OFFSET_PASSWORD, EEPROM_LEN_PASSWORD, pwd);
    if (pwd.length() > 0) return pwd;
  }
  return IOT_CONFIG_WIFI_PASSWORD;
}

String GetDeviceName() {
  String deviceId;
  if (readEepromKey()) {
    readString(EEPROM_OFFSET_DEVICE_ID, EEPROM_LEN_DEVICE_ID, deviceId);
    if (deviceId.length() > 0) return deviceId;
  }
  return IOT_CONFIG_DEVICE_ID;
}

String GetDeviceConnectionString() {
  String connStr;
  if (readEepromKey()) {
    readString(EEPROM_OFFSET_CONNECTION_STR, EEPROM_LEN_CONNECTION_STR, connStr);
    if (connStr.length() > 0) return connStr;
  }
  return IOT_CONFIG_DEVICE_KEY;
}

String GetHostname() {
  String hostname;
  if (readEepromKey()) {
    readString(EEPROM_OFFSET_HOSTNAME, EEPROM_LEN_HOSTNAME, hostname);
    if (hostname.length() > 0) return hostname;
  }
  return GetDeviceName();
}

String GetHubFQDN() {
  String fqdn;
  if (readEepromKey()) {
    readString(EEPROM_OFFSET_HUB_FQDN, EEPROM_LEN_HUB_FQDN, fqdn);
    if (fqdn.length() > 0) return fqdn;
  }
  return IOT_CONFIG_IOTHUB_FQDN;
}

// ========== CONFIG SETTERS ==========

void SetSSID(const String& ssid) {
  writeEepromKey();
  writeString(EEPROM_OFFSET_SSID, EEPROM_LEN_SSID, ssid);
  EEPROM.commit();
}

void SetPassword(const String& pwd) {
  writeEepromKey();
  writeString(EEPROM_OFFSET_PASSWORD, EEPROM_LEN_PASSWORD, pwd);
  EEPROM.commit();
}

void SetDeviceName(const String& deviceId) {
  writeEepromKey();
  writeString(EEPROM_OFFSET_DEVICE_ID, EEPROM_LEN_DEVICE_ID, deviceId);
  EEPROM.commit();
}

void SetDeviceConnectionString(const String& connStr) {
  writeEepromKey();
  writeString(EEPROM_OFFSET_CONNECTION_STR, EEPROM_LEN_CONNECTION_STR, connStr);
  EEPROM.commit();
}

void SetHostname(const String& hostname) {
  writeEepromKey();
  writeString(EEPROM_OFFSET_HOSTNAME, EEPROM_LEN_HOSTNAME, hostname);
  EEPROM.commit();
}

void SetHubFQDN(const String& fqdn) {
  writeEepromKey();
  writeString(EEPROM_OFFSET_HUB_FQDN, EEPROM_LEN_HUB_FQDN, fqdn);
  EEPROM.commit();
}

void ClearAllConfig() {
  for (int i = 0; i < EEPROM_SIZE; i++) {
    EEPROM.write(i, 0);
  }
  EEPROM.commit();
}

// ========== INITIALIZATION ==========

void InitializeEEPROM() {
  EEPROM.begin(EEPROM_SIZE);
  if (!readEepromKey()) {
    Serial.println("EEPROM: First-time setup detected");
    ClearAllConfig();
    writeEepromKey();
  }
}

}  // namespace FlashStorage
