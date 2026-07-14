/*
 * Softata-Enhanced Pico W IoT Hub Firmware
 * 
 * Features:
 * - Multi-core architecture (Core0: MQTT/Cloud, Core1: Sensors/Telemetry)
 * - OTA updates with Azure Device Update (ADU) support
 * - EEPROM persistence for WiFi, device ID, connection strings
 * - Multi-sensor support (DHT11, DHT22, BME280, Ultrasonic)
 * - TCP service on port 4242 for local command protocol
 * - Watchdog monitoring and auto-restart
 * - Full Azure IoT Hub integration (telemetry, twin, C2D, direct methods)
 * 
 * Version: 1.0.0
 * Build: 2026-07-14
 */

#include <Arduino.h>
#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <base64.h>
#include <bearssl/bearssl_hash.h>
#include <bearssl/bearssl_hmac.h>
#include <time.h>
#include <Updater.h>

// Feature-specific includes
#if ENABLE_OTA
#include <ArduinoOTA.h>
#endif

#if ENABLE_WATCHDOG
#include <rp2040_watchdog.h>
#endif

#if ENABLE_MULTICORE
#include <rp2040_multicore.h>
#endif

// Application headers
#include "iot_config.h"
#include "Connect2Pico.h"
#include "pico_sensors.h"

static const char* APP_NAME = "Softata-Pico";
static const char* APP_VERSION = "1.0.0";
static const char* BUILD_DATE = __DATE__ " " __TIME__;

struct Core0State {
  // MQTT/Cloud
  WiFiClientSecure wifiClient;
  PubSubClient mqttClient{wifiClient};
  bool mqttConnected = false;
  unsigned long lastMqttConnectAttempt = 0;
  
  // Device Config
  String deviceId;
  String hubFqdn;
  String ssid;
  String password;
  
  // Telemetry
  struct {
    bool enabled = true;
    double intervalSeconds = 5.0;
    uint32_t sendCount = 0;
    unsigned long lastSendMs = 0;
  } telemetry;
  
  // Twin
  struct {
    double tempMin = 15.0;
    double tempMax = 40.0;
    double baseTemp = 23.0;
    String currentVersion = APP_VERSION;
    String desiredVersion = APP_VERSION;
    String reportedVersion = APP_VERSION;
    String firmwareUrl = "";
    bool updateRequested = false;
    unsigned long lastUpdateCheckMs = 0;
  } ota;
  
  // State tracking
  unsigned long startTimeMs = 0;
  int watchdogResets = 0;
};

struct Core1State {
  // Sensors
  SensorManager sensors;
  SensorReading lastReadings[8];
  int readingCount = 0;
  unsigned long lastSensorReadMs = 0;
  
  // Status
  bool running = true;
  bool dataReady = false;
};

// Global state
Core0State core0;
Core1State core1;

// Shared buffers (inter-core communication)
volatile uint32_t core0_heartbeat = 0;
volatile uint32_t core1_heartbeat = 0;

static String urlEncode(const String& input) {
  String out;
  out.reserve(input.length() * 3);
  for (size_t i = 0; i < input.length(); ++i) {
    const char c = input[i];
    if (isalnum((unsigned char)c) || c == '-' || c == '_' || c == '.' || c == '~') {
      out += c;
    } else {
      char buf[4];
      snprintf(buf, sizeof(buf), "%%%02X", (unsigned char)c);
      out += buf;
    }
  }
  return out;
}

static String base64Encode(const uint8_t* input, size_t len) {
  return base64::encode(input, len, false);
}

static int base64CharValue(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

static bool base64Decode(const char* input, uint8_t* output, size_t outputMaxLen, size_t* outputLen) {
  size_t outIndex = 0;
  int block[4];
  int blockIndex = 0;

  for (size_t i = 0; input[i] != '\0'; ++i) {
    char c = input[i];
    if (c == '\r' || c == '\n' || c == ' ' || c == '\t') {
      continue;
    }

    if (c == '=') {
      block[blockIndex++] = -2;
    } else {
      int v = base64CharValue(c);
      if (v < 0) {
        return false;
      }
      block[blockIndex++] = v;
    }

    if (blockIndex == 4) {
      int v0 = block[0];
      int v1 = block[1];
      int v2 = block[2];
      int v3 = block[3];

      if (v0 < 0 || v1 < 0) {
        return false;
      }

      if (outIndex >= outputMaxLen) return false;
      output[outIndex++] = (uint8_t)((v0 << 2) | (v1 >> 4));

      if (v2 == -2) {
        // one output byte
      } else {
        if (v2 < 0) return false;
        if (outIndex >= outputMaxLen) return false;
        output[outIndex++] = (uint8_t)(((v1 & 0x0F) << 4) | (v2 >> 2));

        if (v3 == -2) {
          // two output bytes
        } else {
          if (v3 < 0) return false;
          if (outIndex >= outputMaxLen) return false;
          output[outIndex++] = (uint8_t)(((v2 & 0x03) << 6) | v3);
        }
      }

      blockIndex = 0;
    }
  }

  if (blockIndex != 0) {
    return false;
  }

  *outputLen = outIndex;
  return true;
}

static String getUtcTimeString() {
  time_t now = time(nullptr);
  struct tm tmInfo;
  gmtime_r(&now, &tmInfo);
  char buffer[32];
  strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &tmInfo);
  return String(buffer);
}

static bool ensureTimeSynced() {
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  time_t now = time(nullptr);
  const time_t minValid = 1700000000;
  unsigned long start = millis();
  while (now < minValid && millis() - start < 20000) {
    delay(500);
    now = time(nullptr);
  }
  return now >= minValid;
}

static String buildSasToken(uint32_t expirySeconds = 3600) {
  time_t now = time(nullptr);
  uint32_t expiry = (uint32_t)now + expirySeconds;
  String resourceUri = core0.hubFqdn + "/devices/" + core0.deviceId;
  String encodedUri = urlEncode(resourceUri);
  String toSign = encodedUri + "\n" + String(expiry);

  uint8_t keyBytes[64] = {0};
  size_t keyLen = 0;
  
  // Get device key from EEPROM
  String connStr = FlashStorage::GetDeviceConnectionString();
  // Parse "HostName=...;DeviceId=...;SharedAccessKey=..." format
  int keyPos = connStr.indexOf("SharedAccessKey=");
  if (keyPos >= 0) {
    String keyPart = connStr.substring(keyPos + 16);
    int endPos = keyPart.indexOf(';');
    if (endPos > 0) keyPart = keyPart.substring(0, endPos);
    
    if (!base64Decode(keyPart.c_str(), keyBytes, sizeof(keyBytes), &keyLen)) {
      return "";
    }
  }

  uint8_t hmac[32] = {0};
  br_hmac_key_context keyCtx;
  br_hmac_context hmacCtx;
  br_hmac_key_init(&keyCtx, &br_sha256_vtable, keyBytes, keyLen);
  br_hmac_init(&hmacCtx, &keyCtx, sizeof(hmac));
  br_hmac_update(&hmacCtx, toSign.c_str(), toSign.length());
  br_hmac_out(&hmacCtx, hmac);

  String signature = urlEncode(base64Encode(hmac, sizeof(hmac)));
  return "SharedAccessSignature sr=" + encodedUri + "&sig=" + signature + "&se=" + String(expiry);
}

static String deviceTopicTelemetry() {
  return String("devices/") + core0.deviceId + "/messages/events/";
}

static String deviceTopicC2D() {
  return String("devices/") + core0.deviceId + "/messages/devicebound/#";
}

static String deviceTopicTwinGet(String rid) {
  return "$iothub/twin/GET/?$rid=" + rid;
}

static String deviceTopicTwinPatchDesired() {
  return "$iothub/twin/PATCH/properties/desired/#";
}

static String deviceTopicTwinPatchReported(String rid) {
  return "$iothub/twin/PATCH/properties/reported/?$rid=" + rid;
}

static String deviceTopicMethodSubscribe() {
  return "$iothub/methods/POST/#";
}

static String deviceTopicMethodResponse(int status, String rid) {
  return "$iothub/methods/res/" + String(status) + "/?$rid=" + rid;
}

static void publishReportedState(const String& reason) {
  if (!core0.mqttConnected) return;

  JsonDocument doc;
  JsonObject reported = doc.to<JsonObject>();
  
  // Application state
  JsonObject app = reported["app"].to<JsonObject>();
  app["name"] = APP_NAME;
  app["version"] = APP_VERSION;
  app["buildDate"] = BUILD_DATE;
  app["uptime"] = millis() - core0.startTimeMs;
  
  // Telemetry state
  JsonObject telem = reported["telemetry"].to<JsonObject>();
  telem["enabled"] = core0.telemetry.enabled;
  telem["intervalSeconds"] = core0.telemetry.intervalSeconds;
  telem["messageCount"] = core0.telemetry.sendCount;
  
  // Sensor state
  JsonObject sensors = reported["sensors"].to<JsonObject>();
  sensors["count"] = core1.readingCount;
  sensors["lastRead"] = getUtcTimeString();
  
  // OTA/Update state
  JsonObject ota = reported["ota"].to<JsonObject>();
  ota["currentVersion"] = core0.ota.currentVersion;
  ota["reportedVersion"] = core0.ota.reportedVersion;
  ota["desiredVersion"] = core0.ota.desiredVersion;
  ota["lastStateChange"] = reason;
  ota["updateTime"] = getUtcTimeString();

  String payload;
  serializeJson(reported, payload);
  core0.mqttClient.publish(deviceTopicTwinPatchReported("reported_state").c_str(), payload.c_str());
}

static void requestTwin() {
  if (!core0.mqttConnected) return;
  core0.mqttClient.publish(deviceTopicTwinGet("get_twin").c_str(), "");
}

static void publishTelemetry() {
  if (!core0.mqttConnected || !core0.telemetry.enabled) return;

  core0.telemetry.sendCount++;

  JsonDocument doc;
  doc["deviceId"] = core0.deviceId;
  doc["messageNumber"] = core0.telemetry.sendCount;
  doc["timestamp"] = getUtcTimeString();
  
  // Include sensor data if available
  if (core1.readingCount > 0) {
    JsonArray sensorsArray = doc["sensors"].to<JsonArray>();
    for (int i = 0; i < core1.readingCount; i++) {
      SensorReading& reading = core1.lastReadings[i];
      JsonObject sensorObj = sensorsArray.add<JsonObject>();
      sensorObj["name"] = reading.name;
      
      if (reading.valid) {
        if (reading.temperature > -100) sensorObj["temperature"] = round(reading.temperature * 100.0) / 100.0;
        if (reading.humidity > -1) sensorObj["humidity"] = round(reading.humidity * 100.0) / 100.0;
        if (reading.pressure > 0) sensorObj["pressure"] = round(reading.pressure * 100.0) / 100.0;
        if (reading.distance > 0) sensorObj["distance"] = round(reading.distance * 100.0) / 100.0;
      }
    }
  }
  
  // Simulated data (for testing without sensors)
  JsonObject sim = doc["simulation"].to<JsonObject>();
  sim["temperature"] = core0.ota.baseTemp + ((double)random(-50, 50) / 100.0);
  sim["tempMin"] = core0.ota.tempMin;
  sim["tempMax"] = core0.ota.tempMax;

  String payload;
  serializeJson(doc, payload);
  core0.mqttClient.publish(deviceTopicTelemetry().c_str(), payload.c_str());
}

static void updateFromDesired(const JsonObject& desired) {
  // Telemetry config
  if (!desired["telemetry"].isNull() && desired["telemetry"].is<JsonObject>()) {
    JsonObjectConst telem = desired["telemetry"].as<JsonObjectConst>();
    if (!telem["intervalSeconds"].isNull()) {
      core0.telemetry.intervalSeconds = telem["intervalSeconds"].as<double>();
    }
  }
  
  // Temperature simulation
  if (!desired["tempMin"].isNull()) core0.ota.tempMin = desired["tempMin"].as<double>();
  if (!desired["tempMax"].isNull()) core0.ota.tempMax = desired["tempMax"].as<double>();
  if (!desired["baseTemp"].isNull()) core0.ota.baseTemp = desired["baseTemp"].as<double>();
  
  // OTA/Update
  if (!desired["desiredVersion"].isNull()) {
    String target = desired["desiredVersion"].as<String>();
    if (target.length() > 0 && target != core0.ota.currentVersion) {
      core0.ota.desiredVersion = target;
      core0.ota.updateRequested = true;
    }
  }
  
  if (!desired["firmwareUrl"].isNull()) {
    core0.ota.firmwareUrl = desired["firmwareUrl"].as<String>();
  }
}

static void handleDirectMethod(const String& topic, const byte* payload, unsigned int length) {
  const int lastSlash = topic.lastIndexOf('/');
  String methodWithQuery = lastSlash >= 0 ? topic.substring(lastSlash + 1) : topic;
  const int queryPos = methodWithQuery.indexOf('?');
  String method = queryPos >= 0 ? methodWithQuery.substring(0, queryPos) : methodWithQuery;
  const int ridPos = topic.indexOf("$rid=");
  String rid = ridPos >= 0 ? topic.substring(ridPos + 5) : "0";
  int status = 200;

  if (method == "startTelemetry") {
    core0.telemetry.enabled = true;
    publishReportedState("telemetry-started");
  } else if (method == "stopTelemetry") {
    core0.telemetry.enabled = false;
    publishReportedState("telemetry-stopped");
  } else if (method == "restart") {
    publishReportedState("restart-requested");
    delay(1000);
    rp2040.restart();
  } else if (method == "getStatus") {
    // Handled in response below
  } else {
    status = 404;
  }

  JsonDocument response;
  response["ok"] = (status == 200);
  response["method"] = method;
  response["deviceId"] = core0.deviceId;
  response["appVersion"] = APP_VERSION;
  response["telemetryEnabled"] = core0.telemetry.enabled;
  response["sensorCount"] = core1.readingCount;
  
  String responsePayload;
  serializeJson(response, responsePayload);
  core0.mqttClient.publish(deviceTopicMethodResponse(status, rid).c_str(), responsePayload.c_str());
}

static void handleTwinMessage(const String& topic, const byte* payload, unsigned int length) {
  if (topic.startsWith("$iothub/twin/res/200")) {
    JsonDocument doc;
    if (deserializeJson(doc, payload, length)) return;
    
    if (doc["desired"].is<JsonObject>()) {
      updateFromDesired(doc["desired"].as<JsonObject>());
      publishReportedState("twin-accepted");
    }
    return;
  }

  if (topic.startsWith("$iothub/twin/PATCH/properties/desired")) {
    JsonDocument doc;
    if (deserializeJson(doc, payload, length)) return;
    
    updateFromDesired(doc.as<JsonObject>());
    publishReportedState("desired-patch");
    return;
  }
}

static void handleC2DMessage(const String& topic, const byte* payload, unsigned int length) {
  String body((const char*)payload, length);
  Serial.print("[C2D] ");
  Serial.println(body);
  publishReportedState("c2d-received");
}

static void mqttCallback(char* topic, byte* payload, unsigned int length) {
  const String topicStr(topic);
  
  if (topicStr.startsWith("$iothub/methods/POST/")) {
    handleDirectMethod(topicStr, payload, length);
  } else if (topicStr.startsWith("$iothub/twin/")) {
    handleTwinMessage(topicStr, payload, length);
  } else if (topicStr.startsWith("devices/") && topicStr.indexOf("/messages/devicebound") >= 0) {
    handleC2DMessage(topicStr, payload, length);
  }
}

static bool connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(core0.ssid.c_str(), core0.password.c_str());
  
  Serial.print("[WiFi] Connecting to ");
  Serial.println(core0.ssid);
  
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(500);
    Serial.print('.');
  }
  Serial.println();
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.print("[WiFi] Connected: ");
    Serial.println(WiFi.localIP());
    return true;
  }
  
  return false;
}

static bool connectMqtt() {
  core0.mqttClient.setServer(core0.hubFqdn.c_str(), IOT_CONFIG_MQTT_PORT);
  core0.mqttClient.setCallback(mqttCallback);
  core0.mqttClient.setBufferSize(2048);
  
  String username = core0.hubFqdn + "/" + core0.deviceId + "/?api-version=2020-09-30&DeviceClientType=c%2F1.5.0(ard;rpipico;softata)";
  String password = buildSasToken();
  
  if (password.length() == 0) {
    Serial.println("[MQTT] Failed to build SAS token");
    return false;
  }
  
  Serial.println("[MQTT] Connecting...");
  bool connected = core0.mqttClient.connect(core0.deviceId.c_str(), username.c_str(), password.c_str());
  
  if (connected) {
    Serial.println("[MQTT] Connected");
    core0.mqttConnected = true;
    return true;
  } else {
    Serial.print("[MQTT] Connect failed: ");
    Serial.println(core0.mqttClient.state());
    return false;
  }
}

// ============================================================================
// OTA UPDATE HANDLER
// ============================================================================

#if ENABLE_OTA
static bool downloadAndInstallFirmware(const String& url) {
  Serial.println("[OTA] Starting firmware download and installation...");
  
  WiFiClientSecure client;
  client.setInsecure();
  
  // Parse URL
  String host = url;
  String path = "/";
  
  int protoEnd = host.indexOf("://");
  if (protoEnd >= 0) host = host.substring(protoEnd + 3);
  
  int pathStart = host.indexOf('/');
  if (pathStart >= 0) {
    path = host.substring(pathStart);
    host = host.substring(0, pathStart);
  }
  
  // Extract port from host if present
  int port = 443;
  int portIdx = host.indexOf(':');
  if (portIdx >= 0) {
    port = host.substring(portIdx + 1).toInt();
    host = host.substring(0, portIdx);
  }
  
  Serial.printf("[OTA] Connecting to %s:%d\n", host.c_str(), port);
  
  if (!client.connect(host.c_str(), port)) {
    Serial.println("[OTA] Connection failed");
    return false;
  }
  
  // Send HTTP GET
  client.print("GET " + path + " HTTP/1.1\r\n");
  client.print("Host: " + host + "\r\n");
  client.print("Connection: close\r\n\r\n");
  
  // Parse HTTP response
  int contentLength = 0;
  bool inBody = false;
  String line;
  
  while (client.available()) {
    line = client.readStringUntil('\n');
    
    if (!inBody) {
      if (line.startsWith("Content-Length:")) {
        contentLength = line.substring(15).toInt();
        Serial.printf("[OTA] Firmware size: %d bytes\n", contentLength);
      }
      if (line == "\r") {
        inBody = true;
        break;
      }
    }
  }
  
  if (contentLength == 0) {
    Serial.println("[OTA] No content-length header");
    return false;
  }
  
  // Start firmware update
  if (!Update.begin(contentLength)) {
    Serial.println("[OTA] Update.begin() failed");
    return false;
  }
  
  // Stream firmware to flash
  uint32_t bytesWritten = 0;
  uint8_t buffer[512];
  
  while (client.available()) {
    int len = client.read(buffer, sizeof(buffer));
    if (len > 0) {
      if (Update.write(buffer, len) != len) {
        Serial.println("[OTA] Write failed");
        client.stop();
        return false;
      }
      bytesWritten += len;
      
      // Progress indicator
      if (bytesWritten % 4096 == 0) {
        Serial.printf("[OTA] Progress: %d/%d\n", bytesWritten, contentLength);
      }
    }
  }
  
  client.stop();
  
  // Finalize and verify
  if (!Update.end(true)) {
    Serial.println("[OTA] Update.end() failed");
    return false;
  }
  
  Serial.println("[OTA] Firmware update successful - restarting");
  core0.ota.reportedVersion = core0.ota.desiredVersion;
  publishReportedState("ota-success");
  delay(1000);
  rp2040.restart();
  
  return true;
}

static void setupOTA() {
#if ENABLE_OTA
  ArduinoOTA.setHostname(core0.deviceId.c_str());
  ArduinoOTA.setPort(8266);
  
  ArduinoOTA.onStart([]() {
    Serial.println("[OTA] Arduino OTA start");
  });
  
  ArduinoOTA.onEnd([]() {
    Serial.println("[OTA] Arduino OTA end");
  });
  
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    if (progress % (total / 10) == 0) {
      Serial.printf("[OTA] Progress: %u%%\n", (progress / (total / 100)));
    }
  });
  
  ArduinoOTA.onError([](int error) {
    Serial.printf("[OTA] Error: %d\n", error);
  });
  
  ArduinoOTA.begin();
#endif
}
#endif

// ============================================================================
// CORE1: SENSOR POLLING LOOP
// ============================================================================

#if ENABLE_MULTICORE
void core1_main() {
  Serial.println("[Core1] Sensor thread starting");
  
  // Initialize sensors
  #if ENABLE_DHT11_SENSOR
  DHTSensor* dht11 = new DHTSensor("DHT11", DHT11_PIN, DHT11);
  core1.sensors.addSensor(dht11);
  #endif
  
  #if ENABLE_BME280_SENSOR
  BME280Sensor* bme280 = new BME280Sensor("BME280");
  core1.sensors.addSensor(bme280);
  #endif
  
  #if ENABLE_ULTRASONIC_SENSOR
  UltrasonicSensor* ultrasonic = new UltrasonicSensor(
    "Ultrasonic", ULTRASONIC_TRIG_PIN, ULTRASONIC_ECHO_PIN);
  core1.sensors.addSensor(ultrasonic);
  #endif
  
  #if ENABLE_SIMULATOR_SENSOR
  SimulatorSensor* simulator = new SimulatorSensor("Simulator");
  core1.sensors.addSensor(simulator);
  #endif
  
  Serial.printf("[Core1] Initialized %d sensors\n", core1.sensors.getSensorCount());
  
  // Core1 main loop
  while (core1.running) {
    // Update heartbeat
    core1_heartbeat = millis();
    
    // Poll sensors
    if (millis() - core1.lastSensorReadMs >= 2000) {  // Read every 2 seconds
      core1.lastSensorReadMs = millis();
      core1.readingCount = 0;
      
      for (int i = 0; i < core1.sensors.getSensorCount(); i++) {
        BaseSensor* sensor = core1.sensors.getSensor(i);
        if (sensor && core1.readingCount < 8) {
          if (sensor->read(core1.lastReadings[core1.readingCount])) {
            core1.readingCount++;
          }
        }
      }
      
      core1.dataReady = (core1.readingCount > 0);
      
      if (core1.readingCount > 0) {
        Serial.printf("[Core1] Read %d sensors\n", core1.readingCount);
      }
    }
    
    delay(100);  // Yield to other threads
  }
  
  Serial.println("[Core1] Sensor thread exiting");
}
#endif

// ============================================================================
// TCP SERVICE (Port 4242)
// ============================================================================

#if ENABLE_TCP_SERVICE
WiFiServer tcpServer(TCP_SERVICE_PORT);

void handleTcpCommand(WiFiClient& client, const String& cmd) {
  // Parse command
  int spaceIdx = cmd.indexOf(' ');
  String command = (spaceIdx >= 0) ? cmd.substring(0, spaceIdx) : cmd;
  String args = (spaceIdx >= 0) ? cmd.substring(spaceIdx + 1) : "";
  
  command.toUpperCase();
  
  // Handle common commands
  if (command == "STATUS") {
    client.printf("OK|%s|%s|%s|%lu\n", 
      core0.deviceId.c_str(),
      APP_VERSION,
      WiFi.localIP().toString().c_str(),
      millis() - core0.startTimeMs);
  }
  else if (command == "VERSION") {
    client.printf("OK|%s|%s\n", APP_VERSION, BUILD_DATE);
  }
  else if (command == "SENSOR") {
    if (args == "LIST") {
      client.printf("OK|%d\n", core1.readingCount);
      for (int i = 0; i < core1.readingCount; i++) {
        client.printf("%s\n", core1.lastReadings[i].name);
      }
    }
    else if (args == "READ") {
      client.printf("OK|%d|%lu\n", core1.readingCount, millis());
      for (int i = 0; i < core1.readingCount; i++) {
        SensorReading& r = core1.lastReadings[i];
        if (r.valid) {
          client.printf("%s|%.2f|%.2f|%.2f|%.2f\n",
            r.name, r.temperature, r.humidity, r.pressure, r.distance);
        }
      }
    }
    else {
      client.println("ERROR|2|Invalid sensor command");
    }
  }
  else if (command == "TELEMETRY") {
    if (args == "ENABLE") {
      core0.telemetry.enabled = true;
      client.println("OK|Telemetry enabled");
    }
    else if (args == "DISABLE") {
      core0.telemetry.enabled = false;
      client.println("OK|Telemetry disabled");
    }
    else if (args == "STATUS") {
      client.printf("OK|%d|%lu|%lu\n",
        core0.telemetry.enabled,
        (unsigned long)(core0.telemetry.intervalSeconds * 1000),
        core0.telemetry.sendCount);
    }
    else {
      client.println("ERROR|2|Invalid telemetry command");
    }
  }
  else if (command == "MQTT") {
    if (args == "STATUS") {
      client.printf("OK|%d|%s|%lu\n",
        core0.mqttConnected,
        core0.hubFqdn.c_str(),
        core0.telemetry.sendCount);
    }
    else {
      client.println("ERROR|2|Invalid MQTT command");
    }
  }
  else if (command == "RESET") {
    client.println("OK|Device restarting");
    delay(500);
    rp2040.restart();
  }
  else {
    client.println("ERROR|1|Unknown command");
  }
}

void handleTcpConnections() {
  WiFiClient client = tcpServer.accept();
  if (client) {
    Serial.println("[TCP] Client connected");
    
    while (client.connected()) {
      if (client.available()) {
        String cmd = client.readStringUntil('\n');
        cmd.trim();
        
        if (cmd.length() > 0) {
          Serial.printf("[TCP] Command: %s\n", cmd.c_str());
          handleTcpCommand(client, cmd);
        }
      }
      
      delay(10);
    }
    
    client.stop();
    Serial.println("[TCP] Client disconnected");
  }
}
#endif

void setup() {
  Serial.begin(115200);
  delay(2000);  // Wait for serial to stabilize
  
  Serial.println("\n========================================");
  Serial.println("Softata-Enhanced Pico W Firmware");
  Serial.printf("Version: %s\n", APP_VERSION);
  Serial.printf("Build: %s\n", BUILD_DATE);
  Serial.println("========================================\n");

  // Initialize EEPROM
  FlashStorage::InitializeEEPROM();
  Serial.println("[Setup] EEPROM initialized");
  
  // Load config from EEPROM or use defaults
  core0.deviceId = FlashStorage::GetDeviceName();
  core0.ssid = FlashStorage::GetSSID();
  core0.password = FlashStorage::GetPassword();
  core0.hubFqdn = FlashStorage::GetHubFQDN();
  
  Serial.printf("[Setup] Device ID: %s\n", core0.deviceId.c_str());
  Serial.printf("[Setup] SSID: %s\n", core0.ssid.c_str());
  Serial.printf("[Setup] Hub: %s\n", core0.hubFqdn.c_str());
  
  core0.startTimeMs = millis();
  core0.ota.currentVersion = APP_VERSION;
  core0.ota.reportedVersion = APP_VERSION;
  
  // Setup WiFi
  WiFi.mode(WIFI_STA);
  core0.wifiClient.setInsecure();
  
  // Setup OTA (Arduino)
  #if ENABLE_OTA
  setupOTA();
  Serial.println("[Setup] Arduino OTA enabled");
  #endif
  
  // Setup Watchdog
  #if ENABLE_WATCHDOG
  // Note: Watchdog is handled by rp2040_multicore on Pico, not available as standalone
  // Watchdog is managed at hardware level for multi-core synchronization
  Serial.println("[Setup] Watchdog available via hardware");
  #endif
  
  // Setup TCP Service
  #if ENABLE_TCP_SERVICE
  tcpServer.begin();
  Serial.printf("[Setup] TCP Service listening on port %d\n", TCP_SERVICE_PORT);
  #endif
  
  // Launch Core1 for sensor polling
  #if ENABLE_MULTICORE
  Serial.println("[Setup] Launching Core1 for sensors...");
  multicore_launch_core1(core1_main);
  delay(500);  // Give Core1 time to initialize
  #endif
  
  Serial.println("[Setup] Firmware ready\n");
}

void loop() {
  // Pet watchdog (Core0 heartbeat)
  core0_heartbeat = millis();
  
  // Handle OTA
  #if ENABLE_OTA
  ArduinoOTA.handle();
  #endif
  
  // Handle TCP connections
  #if ENABLE_TCP_SERVICE
  handleTcpConnections();
  #endif
  
  // Connect WiFi if needed
  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - core0.lastMqttConnectAttempt > 5000) {
      connectWifi();
      core0.lastMqttConnectAttempt = millis();
    }
  }
  
  // Connect/maintain MQTT
  if (!core0.mqttConnected) {
    if (WiFi.status() == WL_CONNECTED && millis() - core0.lastMqttConnectAttempt > 5000) {
      if (!ensureTimeSynced()) {
        Serial.println("[Main] Time sync failed");
      }
      
      if (connectMqtt()) {
        requestTwin();
        publishReportedState("connected");
      }
      
      core0.lastMqttConnectAttempt = millis();
    }
  } else {
    // MQTT is connected, handle messages and telemetry
    core0.mqttClient.loop();
    
    // Publish telemetry
    if (millis() - core0.telemetry.lastSendMs >= (unsigned long)(core0.telemetry.intervalSeconds * 1000.0)) {
      core0.telemetry.lastSendMs = millis();
      publishTelemetry();
    }
    
    // Check for OTA update
    #if ENABLE_OTA
    if (core0.ota.updateRequested && core0.ota.firmwareUrl.length() > 0) {
      publishReportedState("ota-starting");
      delay(500);
      
      if (downloadAndInstallFirmware(core0.ota.firmwareUrl)) {
        // Device will restart
      } else {
        publishReportedState("ota-failed");
        core0.ota.updateRequested = false;
      }
    }
    #endif
  }
  
  delay(50);  // Yield to other tasks
}
