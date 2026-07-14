# Softata Multi-Core Architecture

## Overview

The Softata firmware uses a **dual-core architecture** on the Raspberry Pi Pico W/W2 to separate concerns:

```
┌─────────────────────────────────────────────────────────────┐
│  Raspberry Pi Pico W / Pico W2 (RP2040 Dual-Core)          │
├──────────────────────────┬──────────────────────────────────┤
│  Core0 (Primary)         │  Core1 (Secondary)               │
│  ================         │  ==================               │
│  • Main Thread           │  • Sensor Polling                │
│  • MQTT/IoT Hub          │  • Telemetry Aggregation         │
│  • Twin Updates          │  • Data Buffering                │
│  • C2D Messages          │  • OTA Status                    │
│  • Direct Methods        │  • Watchdog Monitoring           │
│  • Serial/TCP Service    │  • Local Control (TCP)           │
└──────────────────────────┴──────────────────────────────────┘
        ↓                           ↓
    WiFi/MQTT              Sensors/Peripherals
    Azure Cloud             (DHT, BME280, etc.)
```

## Core Responsibilities

### Core0 (Primary - Main Thread)

**Connectivity & Cloud**
- WiFi initialization and management
- MQTT/PubSubClient connection to IoT Hub
- Twin desired/reported property sync
- Telemetry publish loop
- C2D message handlers
- Direct method invocation

**Local Services**
- TCP server on port 4242 (command protocol)
- Serial REPL for debugging
- Arduino OTA listening

**Inter-Core Communication**
- Receives sensor readings from Core1
- Sends control commands to Core1
- Synced shutdown on errors

### Core1 (Secondary - Sensor Core)

**Hardware Monitoring**
- DHT11/DHT22 temperature/humidity reads
- BME280 pressure/altitude reads
- Ultrasonic distance measurement
- Any custom sensor polling

**Data Aggregation**
- Buffer sensor readings
- Calculate statistics (min/max/average)
- Timestamp all measurements

**Watchdog & Safety**
- Monitor Core0 health
- Trigger restart if Core0 hangs
- Report watchdog triggers via twin

**OTA Preparation**
- Calculate firmware checksums
- Prepare flash regions during update

## Inter-Core Synchronization

Using `rp2040_multicore` library:

```cpp
#include <rp2040_multicore.h>

// Synced command types
enum SyncedCommand : uint32_t {
  PAUSE_TELEMETRY = 1,
  RESUME_TELEMETRY = 2,
  STOP_CORE1 = 200,
  SENSORS_READY = 10,
  CORE0_CONNECTED = 11
};

// Send command from Core0 to Core1
rp2040_multicore::fifo_push_value_blocking(PAUSE_TELEMETRY);

// Wait for response
uint32_t response = rp2040_multicore::fifo_pop_blocking();
```

## Startup Sequence

```
1. Core0: Initialize Serial/GPIO/WiFi/OTA
2. Core0: Initialize EEPROM config
3. Core0: Launch Core1 with setup_prio_high_and_launch_core1()
4. Core1: Initialize sensors (DHT, BME280, etc.)
5. Core1: Signal SENSORS_READY to Core0
6. Core0: Wait for SENSORS_READY signal
7. Core0: Connect to WiFi
8. Core0: Start MQTT/IoT Hub
9. Both: Begin normal operation loops
```

## Watchdog Strategy

**Timeout**: 8 seconds (RPi Pico standard)

- Core0 must pet watchdog every 5 seconds
- Core1 monitoring loop checks Core0 heartbeat
- If Core0 doesn't update heartbeat within 7 seconds:
  - Core1 triggers reset
  - Logs event to twin `reportedWatchdogReset`
  - Firmware restarts

## Context Switching & Performance

- **Core0 Loop**: ~100ms cycle (MQTT polling, cloud sync)
- **Core1 Loop**: ~2-5s cycle (sensor reads + aggregation)
- **FIFO overhead**: ~1ms per message (minimal)
- **RAM split**: 64KB per core (typical)

## Memory Layout

```
RP2040 = 264KB total SRAM

Core0 Stack:   4KB
Core0 Heap:    50KB
─────────────────────  (mid-point barrier)
Core1 Stack:   4KB
Core1 Heap:    50KB
────────────────────
Shared Buffers: ~156KB
```

## Debugging Multi-Core Issues

### Core0 Serial Output
```
Serial.println("Core0: Starting MQTT loop");
```

### Core1 Serial Output
```
// Not directly available; use dual USB cables or log to shared buffer
// Or compile test in single-core mode
```

### Check Multicore Status
```cpp
#include <rp2040_multicore.h>

void setup() {
  // Check if Core1 is running
  if (multicore_is_core1_running()) {
    Serial.println("Core1: Running");
  }
}
```

### Force Single-Core Mode
```cpp
#define ENABLE_MULTICORE 0  // In iot_config.h
// All operations run on Core0
```

## Tuning & Optimization

### Sensor Read Frequency
Adjust in `iot_config.h`:
```cpp
#define SENSOR_READ_INTERVAL_MS 2000  // 2 seconds
```

### Telemetry Send Frequency
```cpp
#define TELEMETRY_SEND_INTERVAL_MS 5000  // 5 seconds
```

### Twin Update Frequency
```cpp
#define TWIN_UPDATE_INTERVAL_MS 30000  // 30 seconds
```

## Limitations & Edge Cases

1. **Core1 Crash**: Device restarts (watchdog fires)
2. **MQTT Disconnect**: Core0 retries, Core1 continues sampling
3. **WiFi Outage**: Twin sync paused; local telemetry buffered
4. **OTA During Sensor Read**: Deferred until next read cycle
5. **High Sensor Frequency**: May cause Core1 stack overflow

## Related Files

- `pico_firmware.ino` — Core setup and main loops
- `Connect2Pico.h` — EEPROM + Core0/Core1 init
- `pico_sensors.h` — Core1 sensor abstraction
- `iot_config.h` — Feature toggles and timing

