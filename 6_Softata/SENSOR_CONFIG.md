# Softata Sensor Configuration Guide

## Supported Sensors

### 1. DHT11 / DHT22 (Temperature & Humidity)

**Features**
- Temperature: -40°C to +80°C (±2°C accuracy)
- Humidity: 20-90% (±5% accuracy)
- Digital output via single wire
- Read interval: 2 seconds minimum

**Wiring (Grove)**
```
DHT11/DHT22 (Grove)
├─ VCC → 3.3V
├─ GND → GND
└─ DATA → GPIO 16 (default, configurable)
```

**Configuration**
```cpp
// In iot_config.h
#define ENABLE_DHT11_SENSOR 1    // Enable DHT11
#define DHT11_PIN 16              // GPIO pin

// Or for DHT22
#define ENABLE_DHT22_SENSOR 1
#define DHT22_PIN 16
```

**Code Example**
```cpp
#include "pico_sensors.h"

SensorManager sensors;

void setup() {
  // Add DHT11 sensor
  DHTSensor* dht = new DHTSensor("DHT11", DHT11_PIN, DHT11);
  sensors.addSensor(dht);
}

void loop() {
  SensorReading reading;
  if (dht->read(reading)) {
    Serial.printf("Temp: %.1f°C, Humidity: %.1f%%\n", 
      reading.temperature, reading.humidity);
  }
}
```

**Troubleshooting**
- Reading NaN: Sensor not responding (check pin, power)
- Slow reads: Normal; DHT needs 2+ second interval
- Disconnections: Use pull-up resistor on data line

---

### 2. BME280 (Temperature, Humidity, Pressure)

**Features**
- Temperature: -40°C to +85°C
- Humidity: 0-100%
- Pressure: 300-1100 hPa (altitude calculation)
- I2C interface (address 0x76 or 0x77)
- High accuracy environmental sensing

**Wiring (Grove I2C)**
```
BME280 (Grove I2C)
├─ VCC → 3.3V
├─ GND → GND
├─ SCL → GPIO 9 (I2C0 SCL, default)
└─ SDA → GPIO 8 (I2C0 SDA, default)
```

**Configuration**
```cpp
// In iot_config.h
#define ENABLE_BME280_SENSOR 1

// I2C pins (Pico default)
#define I2C0_SDA 8
#define I2C0_SCL 9
```

**Code Example**
```cpp
BME280Sensor* bme = new BME280Sensor("BME280");
sensors.addSensor(bme);

SensorReading reading;
if (bme->read(reading)) {
  Serial.printf("Temp: %.1f°C, Humidity: %.1f%%, "
    "Pressure: %.2f hPa\n",
    reading.temperature, reading.humidity, reading.pressure);
}
```

**Altitude Calculation**
```cpp
// From sea-level pressure (hPa)
float seaLevelPressure = 1013.25;
float pressure = reading.pressure;
float altitude = 44330 * (1 - pow(pressure / seaLevelPressure, 1/5.255));
```

**Troubleshooting**
- I2C not responding: Check SCL/SDA pins, verify address with `i2c_scan`
- Erratic readings: Add 10kΩ pull-up resistors to I2C lines
- Slow updates: BME280 has internal averaging; patience!

---

### 3. Ultrasonic Ranger (HC-SR04 Distance)

**Features**
- Measurement range: 2cm to 400cm
- Accuracy: ±3%
- Trigger pulse + echo timing
- Non-contact distance measurement

**Wiring (Grove)**
```
HC-SR04 (Grove Ultrasonic)
├─ VCC → 5V (needs 5V for reliable operation)
├─ GND → GND
├─ TRIG → GPIO 12 (configurable)
└─ ECHO → GPIO 13 (configurable)
```

**Configuration**
```cpp
// In iot_config.h
#define ENABLE_ULTRASONIC_SENSOR 1
#define ULTRASONIC_TRIG_PIN 12
#define ULTRASONIC_ECHO_PIN 13
```

**Code Example**
```cpp
UltrasonicSensor* ultrasonic = new UltrasonicSensor(
  "Ultrasonic", ULTRASONIC_TRIG_PIN, ULTRASONIC_ECHO_PIN);
sensors.addSensor(ultrasonic);

SensorReading reading;
if (ultrasonic->read(reading)) {
  Serial.printf("Distance: %.2f cm\n", reading.distance);
}
```

**Troubleshooting**
- Reading 0: Check pins, verify 5V power
- Erratic readings: Add 100nF capacitor across trigger pin
- Out of range (0 cm): Object out of range or too close
- Slow reads: Normal; ultrasonic is inherently slower

---

### 4. Simulator Sensor (Testing)

**Features**
- Generates synthetic sensor data
- No hardware required
- Useful for testing without physical sensors
- Configurable base/min/max values

**Configuration**
```cpp
// In iot_config.h
#define ENABLE_SIMULATOR_SENSOR 1
```

**Code Example**
```cpp
SimulatorSensor* sim = new SimulatorSensor("Simulator");
sensors.addSensor(sim);

SensorReading reading;
sim->read(reading);  // Always succeeds
// Simulates temp 23°C ± variation, humidity 45% ± variation
```

---

## Multi-Sensor Setup

### Example: DHT11 + BME280 + Ultrasonic

```cpp
#include "pico_sensors.h"

SensorManager sensors;

void setup() {
  Serial.begin(115200);
  
  // Initialize DHT11
  #if ENABLE_DHT11_SENSOR
  DHTSensor* dht = new DHTSensor("DHT11", DHT11_PIN, DHT11);
  sensors.addSensor(dht);
  #endif
  
  // Initialize BME280
  #if ENABLE_BME280_SENSOR
  BME280Sensor* bme = new BME280Sensor("BME280");
  sensors.addSensor(bme);
  #endif
  
  // Initialize Ultrasonic
  #if ENABLE_ULTRASONIC_SENSOR
  UltrasonicSensor* us = new UltrasonicSensor(
    "Ultrasonic", ULTRASONIC_TRIG_PIN, ULTRASONIC_ECHO_PIN);
  sensors.addSensor(us);
  #endif
  
  Serial.printf("Initialized %d sensors\n", sensors.getSensorCount());
}

void loop() {
  for (int i = 0; i < sensors.getSensorCount(); i++) {
    BaseSensor* sensor = sensors.getSensor(i);
    SensorReading reading;
    
    if (sensor->read(reading)) {
      Serial.printf("[%s] ", reading.name);
      
      if (reading.temperature > -100) {  // Valid temp
        Serial.printf("T=%.1f°C ", reading.temperature);
      }
      if (reading.humidity > -1) {  // Valid humidity
        Serial.printf("H=%.1f%% ", reading.humidity);
      }
      if (reading.pressure > 0) {  // Valid pressure
        Serial.printf("P=%.0f hPa ", reading.pressure);
      }
      if (reading.distance > 0) {  // Valid distance
        Serial.printf("D=%.1f cm ", reading.distance);
      }
      
      Serial.println();
    }
  }
  
  delay(2000);  // 2 second read interval
}
```

---

## Twin Reporting Sensor Capabilities

The device reports sensor capabilities in the twin `reportedProperties`:

```json
{
  "properties": {
    "reported": {
      "sensors": {
        "count": 2,
        "list": [
          {
            "name": "DHT11",
            "type": "temperature_humidity",
            "enabled": true,
            "pin": 16
          },
          {
            "name": "BME280",
            "type": "environmental",
            "enabled": true,
            "i2c_address": "0x76"
          }
        ]
      }
    }
  }
}
```

---

## Telemetry Format

Sensor data published to `devices/{deviceId}/messages/events/`:

```json
{
  "timestamp": "2026-07-14T10:30:45.123Z",
  "sensors": [
    {
      "name": "DHT11",
      "temperature": 22.5,
      "humidity": 65.3,
      "unit": "celsius"
    },
    {
      "name": "BME280",
      "temperature": 22.7,
      "humidity": 64.2,
      "pressure": 1013.25,
      "unit": "hPa"
    },
    {
      "name": "Ultrasonic",
      "distance": 45.2,
      "unit": "cm"
    }
  ]
}
```

---

## Adding Custom Sensors

To add a new sensor:

1. **Extend BaseSensor** in `pico_sensors.h`:

```cpp
class MyCustomSensor : public BaseSensor {
private:
  int pin;
  
public:
  MyCustomSensor(const char* n, int p) 
    : BaseSensor(n), pin(p) {}
  
  bool initialize() override {
    pinMode(pin, INPUT);
    return true;
  }
  
  bool read(SensorReading& reading) override {
    reading.name = name;
    reading.timestamp = millis();
    
    // Custom read logic
    int rawValue = analogRead(pin);
    reading.temperature = (rawValue / 1023.0) * 100.0;  // Example
    
    reading.valid = (rawValue >= 0);
    return reading.valid;
  }
};
```

2. **Add configuration toggle** in `iot_config.h`:

```cpp
#define ENABLE_CUSTOM_SENSOR 1
#define CUSTOM_SENSOR_PIN 26
```

3. **Instantiate in firmware**:

```cpp
#if ENABLE_CUSTOM_SENSOR
MyCustomSensor* custom = new MyCustomSensor("MyCustom", CUSTOM_SENSOR_PIN);
sensors.addSensor(custom);
#endif
```

---

## Performance & Limitations

| Sensor | Read Time | Max Frequency | Power (mA) |
|--------|-----------|---------------|-----------|
| DHT11 | 2-3s | 1 read/2s | 2.5 |
| DHT22 | 2-3s | 1 read/2s | 2.5 |
| BME280 | 100ms | 10 Hz | 0.5-5 |
| HC-SR04 | 50-150ms | 20 Hz | 15 |
| Simulator | <1ms | 1000 Hz | 0 |

---

## Testing Sensors

Use the provided script:

```powershell
.\6_Softata\scripts\test_sensors.ps1 -ComPort COM3 -Duration 120
```

Or test individually via Arduino IDE Serial Monitor:

```
Enter command: SENSOR DHT11
Response: Temp=22.5°C Humidity=65.3%

Enter command: SENSOR BME280
Response: Temp=22.7°C Humidity=64.2% Pressure=1013.25hPa

Enter command: SENSOR DISTANCE
Response: Distance=45.2cm
```

