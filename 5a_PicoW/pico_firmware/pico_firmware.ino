#include <Arduino.h>
#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <base64.h>
#include <bearssl/bearssl_hash.h>
#include <bearssl/bearssl_hmac.h>
#include <time.h>

#include "iot_config.h"

static const char* APP_NAME = "pico-firmware";
static const char* APP_VERSION = "0.1.0";

struct SimState {
  double intervalSeconds = 5.0;
  int randomEvery = 10;
  double tempMin = 15.0;
  double tempMax = 40.0;
  double baseTemp = 23.0;
  bool telemetryEnabled = true;
  uint32_t sendCount = 0;
  String storedText = "";
  int storedNumber = 0;
  String targetVersion = APP_VERSION;
  bool restartRequested = false;
  String lastState = "boot";
  String lastUpdateUtc = "";
};

WiFiClientSecure wifiClient;
PubSubClient mqttClient(wifiClient);
SimState state;
unsigned long lastTelemetryMs = 0;
unsigned long lastTwinRequestMs = 0;
bool twinRequested = false;

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
  String resourceUri = String(IOT_CONFIG_IOTHUB_FQDN) + "/devices/" + IOT_CONFIG_DEVICE_ID;
  String encodedUri = urlEncode(resourceUri);
  String toSign = encodedUri + "\n" + String(expiry);

  uint8_t keyBytes[64] = {0};
  size_t keyLen = 0;
  if (!base64Decode(IOT_CONFIG_DEVICE_KEY, keyBytes, sizeof(keyBytes), &keyLen)) {
    return "";
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
  return String("devices/") + IOT_CONFIG_DEVICE_ID + "/messages/events/";
}

static String deviceTopicC2D() {
  return String("devices/") + IOT_CONFIG_DEVICE_ID + "/messages/devicebound/#";
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
  if (!mqttClient.connected()) return;

  JsonDocument doc;
  JsonObject reported = doc.to<JsonObject>();
  JsonObject sim = reported["sim"].to<JsonObject>();
  sim["intervalSeconds"] = state.intervalSeconds;
  sim["randomEvery"] = state.randomEvery;
  sim["tempMin"] = state.tempMin;
  sim["tempMax"] = state.tempMax;
  sim["baseTemp"] = state.baseTemp;
  sim["sendCount"] = state.sendCount;
  sim["storedText"] = state.storedText;
  sim["storedNumber"] = state.storedNumber;
  sim["telemetryEnabled"] = state.telemetryEnabled;
  sim["lastState"] = reason;
  sim["lastUpdateUtc"] = getUtcTimeString();

  JsonObject app = reported["app"].to<JsonObject>();
  app["name"] = APP_NAME;
  app["version"] = APP_VERSION;

  JsonObject du = reported["du"].to<JsonObject>();
  du["targetVersion"] = state.targetVersion;
  du["restartRequested"] = state.restartRequested;
  du["note"] = "Device Update package installation is external to this app.";

  String payload;
  serializeJson(reported, payload);
  mqttClient.publish(deviceTopicTwinPatchReported("reported_state").c_str(), payload.c_str());
}

static void requestTwin() {
  if (!mqttClient.connected()) return;
  mqttClient.publish(deviceTopicTwinGet("get_twin").c_str(), "");
  twinRequested = true;
  lastTwinRequestMs = millis();
}

static void publishTelemetry() {
  if (!mqttClient.connected() || !state.telemetryEnabled) return;

  state.sendCount++;
  const bool randomCycle = (state.sendCount % (uint32_t)state.randomEvery) == 0;
  const double temp = randomCycle
    ? state.tempMin + (double)random(0, 1000) / 1000.0 * (state.tempMax - state.tempMin)
    : state.baseTemp + ((double)random(-50, 50) / 100.0);

  JsonDocument doc;
  doc["deviceId"] = IOT_CONFIG_DEVICE_ID;
  doc["messageNumber"] = state.sendCount;
  doc["temperature"] = round(temp * 100.0) / 100.0;
  doc["temperatureUnit"] = "C";
  doc["isRandomCycle"] = randomCycle;
  doc["textValue"] = state.storedText;
  doc["numberValue"] = state.storedNumber;
  doc["timestampUtc"] = getUtcTimeString();

  String payload;
  serializeJson(doc, payload);
  mqttClient.publish(deviceTopicTelemetry().c_str(), payload.c_str());
}

static void updateFromDesired(const JsonObject& desired) {
  JsonVariantConst desiredSim = desired["sim"];
  if (desiredSim.is<JsonObjectConst>()) {
    JsonObjectConst sim = desiredSim.as<JsonObjectConst>();
    if (!sim["intervalSeconds"].isNull()) state.intervalSeconds = sim["intervalSeconds"].as<double>();
    if (!sim["randomEvery"].isNull()) state.randomEvery = sim["randomEvery"].as<int>();
    if (!sim["tempMin"].isNull()) state.tempMin = sim["tempMin"].as<double>();
    if (!sim["tempMax"].isNull()) state.tempMax = sim["tempMax"].as<double>();
    if (!sim["baseTemp"].isNull()) state.baseTemp = sim["baseTemp"].as<double>();
  }

  if (state.tempMin > state.tempMax) {
    double swap = state.tempMin;
    state.tempMin = state.tempMax;
    state.tempMax = swap;
  }

  JsonVariantConst desiredDu = desired["du"];
  if (desiredDu.is<JsonObjectConst>()) {
    JsonObjectConst du = desiredDu.as<JsonObjectConst>();
    if (!du["targetVersion"].isNull()) {
      String target = du["targetVersion"].as<String>();
      if (target.length() > 0 && target != APP_VERSION) {
        state.targetVersion = target;
        state.restartRequested = true;
      }
    }
  }
}

static bool parseJsonPayload(const byte* payload, unsigned int length, JsonDocument& doc) {
  DeserializationError err = deserializeJson(doc, payload, length);
  return !err;
}

static void handleDirectMethod(const String& topic, const byte* payload, unsigned int length) {
  const int lastSlash = topic.lastIndexOf('/');
  String methodWithQuery = lastSlash >= 0 ? topic.substring(lastSlash + 1) : topic;
  const int queryPos = methodWithQuery.indexOf('?');
  String method = queryPos >= 0 ? methodWithQuery.substring(0, queryPos) : methodWithQuery;
  const int ridPos = topic.indexOf("$rid=");
  String rid = ridPos >= 0 ? topic.substring(ridPos + 5) : "0";
  int status = 200;
  String responseMethod = method;

  JsonDocument doc;
  if (length > 0) {
    deserializeJson(doc, payload, length);
  }

  if (method == "setText") {
    if (doc.is<JsonObject>() && !doc["value"].isNull()) state.storedText = doc["value"].as<String>();
    else if (doc.is<JsonVariant>()) state.storedText = String((const char*)payload).substring(0, length);
    publishReportedState("text-updated");
  } else if (method == "getText") {
    // read-only
  } else if (method == "setNumber") {
    if (doc.is<JsonObject>() && !doc["value"].isNull()) state.storedNumber = doc["value"].as<int>();
    else state.storedNumber = atoi((const char*)payload);
    publishReportedState("number-updated");
  } else if (method == "getNumber") {
    // read-only
  } else if (method == "startTelemetry") {
    state.telemetryEnabled = true;
    publishReportedState("telemetry-started");
  } else if (method == "stopTelemetry") {
    state.telemetryEnabled = false;
    publishReportedState("telemetry-stopped");
  } else {
    status = 404;
  }

  JsonDocument response;
  response["ok"] = (status == 200);
  response["method"] = responseMethod;
  response["deviceId"] = IOT_CONFIG_DEVICE_ID;
  response["appVersion"] = APP_VERSION;
  response["telemetryEnabled"] = state.telemetryEnabled;
  response["storedText"] = state.storedText;
  response["storedNumber"] = state.storedNumber;
  String responsePayload;
  serializeJson(response, responsePayload);
  mqttClient.publish(deviceTopicMethodResponse(status, rid).c_str(), responsePayload.c_str());
}

static void handleTwinMessage(const String& topic, const byte* payload, unsigned int length) {
  if (topic.startsWith("$iothub/twin/res/200")) {
    JsonDocument doc;
    if (!parseJsonPayload(payload, length, doc)) return;
    if (doc["desired"].is<JsonObject>()) {
      updateFromDesired(doc["desired"].as<JsonObject>());
      publishReportedState("twin-accepted");
    }
    return;
  }

  if (topic.startsWith("$iothub/twin/PATCH/properties/desired")) {
    JsonDocument doc;
    if (!parseJsonPayload(payload, length, doc)) return;
    updateFromDesired(doc.as<JsonObject>());
    publishReportedState("desired-patch");
    return;
  }
}

static void handleC2DMessage(const String& topic, const byte* payload, unsigned int length) {
  String body((const char*)payload, length);
  Serial.print("C2D received: ");
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
  WiFi.begin(IOT_CONFIG_WIFI_SSID, IOT_CONFIG_WIFI_PASSWORD);
  Serial.print("Connecting to WIFI SSID ");
  Serial.println(IOT_CONFIG_WIFI_SSID);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 30000) {
    delay(500);
    Serial.print('.');
  }
  Serial.println();
  return WiFi.status() == WL_CONNECTED;
}

static bool connectMqtt() {
  mqttClient.setServer(IOT_CONFIG_IOTHUB_FQDN, IOT_CONFIG_MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(2048);
  String username = String(IOT_CONFIG_IOTHUB_FQDN) + "/" + IOT_CONFIG_DEVICE_ID + "/?api-version=2020-09-30&DeviceClientType=c%2F1.5.0-beta.1(ard;rpipico)";
  String password = buildSasToken();
  return mqttClient.connect(IOT_CONFIG_DEVICE_ID, username.c_str(), password.c_str());
}

static void restartDevice() {
#if defined(ARDUINO_ARCH_RP2040)
  rp2040.restart();
#else
  ESP.restart();
#endif
}

static void subscribeTopics() {
  mqttClient.subscribe(deviceTopicC2D().c_str());
  mqttClient.subscribe(deviceTopicMethodSubscribe().c_str());
  mqttClient.subscribe(deviceTopicTwinPatchDesired().c_str());
  mqttClient.publish(deviceTopicTwinGet("get_twin").c_str(), "");
  twinRequested = true;
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  randomSeed(analogRead(A0));

  wifiClient.setInsecure();

  Serial.println();
  Serial.println("Pico firmware starting");
  Serial.print("Device ID: ");
  Serial.println(IOT_CONFIG_DEVICE_ID);
  Serial.print("Hub: ");
  Serial.println(IOT_CONFIG_IOTHUB_FQDN);

  if (!connectWifi()) {
    Serial.println("WiFi connect failed");
  }

  if (!ensureTimeSynced()) {
    Serial.println("SNTP sync failed");
  }
}

void loop() {
  if (!mqttClient.connected()) {
    if (connectWifi() && connectMqtt()) {
      subscribeTopics();
      publishReportedState("connected");
    } else {
      delay(2000);
      return;
    }
  }

  mqttClient.loop();

  if (millis() - lastTelemetryMs >= (unsigned long)(state.intervalSeconds * 1000.0)) {
    lastTelemetryMs = millis();
    publishTelemetry();
  }

  if (state.restartRequested) {
    publishReportedState("restart-requested");
    Serial.println("Restart requested by desired twin targetVersion mismatch.");
    delay(1000);
    restartDevice();
  }

  if (twinRequested && millis() - lastTwinRequestMs > 10000) {
    twinRequested = false;
  }
}
