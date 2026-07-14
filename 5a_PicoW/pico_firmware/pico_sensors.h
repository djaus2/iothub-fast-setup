#pragma once

#include <Arduino.h>
#include "iot_config.h"

// ========== SENSOR ABSTRACTION ==========

struct SensorReading {
  String name;
  double temperature = 0.0;
  double humidity = 0.0;
  double pressure = 0.0;
  double distance = 0.0;
  bool valid = false;
  unsigned long timestamp = 0;
};

class BaseSensor {
public:
  BaseSensor(const char* n) : name(n) {}
  virtual ~BaseSensor() {}
  
  virtual bool initialize() { return true; }
  virtual bool read(SensorReading& reading) = 0;
  
  const char* getName() const { return name; }

protected:
  const char* name;
};

// ========== DHT SENSORS ==========

#if ENABLE_DHT11_SENSOR || ENABLE_DHT22_SENSOR
#include <DHT.h>

class DHTSensor : public BaseSensor {
private:
  DHT dht;
  
public:
  DHTSensor(const char* n, int pin, int type) 
    : BaseSensor(n), dht(pin, type), pin(pin), type(type) {}
  
  bool initialize() override {
    dht.begin();
    delay(1000);  // DHT needs time to stabilize
    return true;
  }
  
  bool read(SensorReading& reading) override {
    reading.temperature = dht.readTemperature();
    reading.humidity = dht.readHumidity();
    reading.name = name;
    reading.timestamp = millis();
    
    if (isnan(reading.temperature) || isnan(reading.humidity)) {
      reading.valid = false;
      return false;
    }
    
    reading.valid = true;
    return true;
  }

private:
  int pin;
  int type;  // DHT11, DHT22, etc.
};
#endif

// ========== BME280 SENSOR ==========

#if ENABLE_BME280_SENSOR
#include <Adafruit_BME280.h>

class BME280Sensor : public BaseSensor {
private:
  Adafruit_BME280 bme;
  bool initialized = false;
  
public:
  BME280Sensor(const char* n) : BaseSensor(n) {}
  
  bool initialize() override {
    initialized = bme.begin(0x76);  // I2C address
    if (!initialized) {
      Serial.println("BME280: Failed to initialize");
    }
    return initialized;
  }
  
  bool read(SensorReading& reading) override {
    if (!initialized) return false;
    
    reading.temperature = bme.readTemperature();
    reading.humidity = bme.readHumidity();
    reading.pressure = bme.readPressure() / 100.0F;  // hPa
    reading.name = name;
    reading.timestamp = millis();
    reading.valid = true;
    return true;
  }
};
#endif

// ========== ULTRASONIC SENSOR ==========

#if ENABLE_ULTRASONIC_SENSOR
class UltrasonicSensor : public BaseSensor {
private:
  int trigPin;
  int echoPin;
  
public:
  UltrasonicSensor(const char* n, int trig, int echo) 
    : BaseSensor(n), trigPin(trig), echoPin(echo) {}
  
  bool initialize() override {
    pinMode(trigPin, OUTPUT);
    pinMode(echoPin, INPUT);
    return true;
  }
  
  bool read(SensorReading& reading) override {
    digitalWrite(trigPin, LOW);
    delayMicroseconds(2);
    digitalWrite(trigPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(trigPin, LOW);
    
    long duration = pulseIn(echoPin, HIGH, 30000);
    if (duration == 0) {
      reading.valid = false;
      return false;
    }
    
    reading.distance = duration * 0.034 / 2;  // cm
    reading.name = name;
    reading.timestamp = millis();
    reading.valid = true;
    return true;
  }
};
#endif

// ========== SIMULATOR SENSOR ==========

#if ENABLE_SIMULATOR_SENSOR
class SimulatorSensor : public BaseSensor {
private:
  double baseTemp = 23.0;
  double minTemp = 15.0;
  double maxTemp = 40.0;
  int counter = 0;
  
public:
  SimulatorSensor(const char* n) : BaseSensor(n) {}
  
  bool initialize() override { return true; }
  
  bool read(SensorReading& reading) override {
    // Simulate temperature variation
    double variation = (random(-100, 100) / 100.0);  // ±1°C variation
    reading.temperature = baseTemp + variation;
    reading.humidity = 45.0 + random(-10, 10);
    reading.pressure = 1013.25 + (random(-5, 5) / 10.0);
    reading.name = name;
    reading.timestamp = millis();
    reading.valid = true;
    counter++;
    return true;
  }
};
#endif

// ========== SENSOR MANAGER ==========

class SensorManager {
private:
  static const int MAX_SENSORS = 8;
  BaseSensor* sensors[MAX_SENSORS];
  int sensorCount = 0;
  
public:
  SensorManager() {
    for (int i = 0; i < MAX_SENSORS; i++) {
      sensors[i] = nullptr;
    }
  }
  
  bool addSensor(BaseSensor* sensor) {
    if (sensorCount >= MAX_SENSORS) return false;
    sensors[sensorCount++] = sensor;
    return sensor->initialize();
  }
  
  int getSensorCount() const { return sensorCount; }
  
  BaseSensor* getSensor(int index) {
    if (index < 0 || index >= sensorCount) return nullptr;
    return sensors[index];
  }
  
  bool readAll() {
    bool allOk = true;
    for (int i = 0; i < sensorCount; i++) {
      SensorReading dummy;
      if (!sensors[i]->read(dummy)) {
        allOk = false;
      }
    }
    return allOk;
  }
};
