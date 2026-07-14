# TCP Service Protocol (Port 4242)

## Overview

The Softata firmware runs a TCP service on **port 4242** that accepts command-based instructions for local control of sensors, actuators, and device state.

This mirrors the Softata project's command protocol and allows applications running on the same network to query sensor data, control outputs, and monitor device health without going through Azure IoT Hub.

## Connection

```
TCP://{device-hostname}:4242

Example:
tcp://picow1.local:4242
tcp://192.168.1.100:4242
```

### PowerShell Example

```powershell
$client = New-Object System.Net.Sockets.TcpClient
$client.Connect("picow1.local", 4242)

$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream)
$reader = New-Object System.IO.StreamReader($stream)

$writer.WriteLine("STATUS")
$response = $reader.ReadLine()
Write-Host $response

$writer.Close()
$stream.Close()
$client.Close()
```

---

## Command Format

### Request

```
COMMAND [arg1] [arg2] ...
```

- Commands are case-insensitive
- Arguments separated by space
- Newline (`\r\n`) terminates command
- Max 128 bytes per command

### Response

```
OK|[data]
ERROR|[error_code]|[message]
```

---

## Commands

### System Commands

#### STATUS

Get device status

**Request:**
```
STATUS
```

**Response:**
```
OK|picow1|1.0.0|192.168.1.100|0
  device_id | version | ip_addr | uptime_s
```

#### RESET

Restart the device

**Request:**
```
RESET
```

**Response:**
```
OK|Device restarting
```

#### VERSION

Get firmware version

**Request:**
```
VERSION
```

**Response:**
```
OK|1.0.0|2026-07-14T10:30:00Z
  version | build_date
```

#### HOSTNAME

Get or set mDNS hostname

**Request:**
```
HOSTNAME
HOSTNAME new-name
```

**Response:**
```
OK|picow1
OK|Hostname changed to new-name (restart required)
```

---

### WiFi Commands

#### WIFI STATUS

Get WiFi connection status

**Request:**
```
WIFI STATUS
```

**Response:**
```
OK|connected|my-ssid|192.168.1.100|signal:-50dBm
  | status | ssid | ip | rssi
```

#### WIFI SCAN

Scan for available networks

**Request:**
```
WIFI SCAN
```

**Response:**
```
OK|3
my-ssid|80|-50
other-net|WPA2|-75
guest|Open|-85
```

#### WIFI CONFIG

Set WiFi credentials (stored to EEPROM)

**Request:**
```
WIFI CONFIG ssid|password
```

**Response:**
```
OK|WiFi config updated (restart required)
```

---

### Sensor Commands

#### SENSOR LIST

List all available sensors

**Request:**
```
SENSOR LIST
```

**Response:**
```
OK|2
DHT11|temperature_humidity|16|enabled
BME280|environmental|i2c_0x76|enabled
```

#### SENSOR READ

Read sensor data

**Request:**
```
SENSOR READ
SENSOR READ DHT11
```

**Response (all sensors):**
```
OK|2|timestamp
DHT11|22.5|65.3
BME280|22.7|64.2|1013.25
```

**Response (single sensor):**
```
OK|DHT11|22.5|65.3|timestamp
  | name | temp | humidity | timestamp_ms
```

#### SENSOR ENABLE / DISABLE

Enable or disable sensor polling

**Request:**
```
SENSOR ENABLE DHT11
SENSOR DISABLE BME280
```

**Response:**
```
OK|DHT11 enabled
OK|BME280 disabled
```

#### SENSOR CONFIG

Configure sensor parameters

**Request:**
```
SENSOR CONFIG DHT11|READ_INTERVAL|3000
```

**Response:**
```
OK|DHT11 read interval set to 3000ms
```

---

### Telemetry Commands

#### TELEMETRY STATUS

Get telemetry state

**Request:**
```
TELEMETRY STATUS
```

**Response:**
```
OK|enabled|5000|45
  | enabled | interval_ms | messages_sent
```

#### TELEMETRY ENABLE / DISABLE

Control telemetry transmission

**Request:**
```
TELEMETRY ENABLE
TELEMETRY DISABLE
```

**Response:**
```
OK|Telemetry enabled
OK|Telemetry disabled
```

#### TELEMETRY INTERVAL

Set telemetry send interval

**Request:**
```
TELEMETRY INTERVAL 10000
```

**Response:**
```
OK|Telemetry interval set to 10000ms
```

---

### MQTT / Cloud Commands

#### MQTT STATUS

Get MQTT connection status

**Request:**
```
MQTT STATUS
```

**Response:**
```
OK|connected|my-iot-hub.azure-devices.net|25
  | status | broker | messages_published
```

#### MQTT RECONNECT

Force MQTT reconnection

**Request:**
```
MQTT RECONNECT
```

**Response:**
```
OK|Reconnecting to broker...
```

#### DEVICE ID

Get or set device ID (requires restart)

**Request:**
```
DEVICE ID
DEVICE ID new-device-id
```

**Response:**
```
OK|picow1
OK|Device ID set to new-device-id (restart required)
```

---

### Twin / Property Commands

#### TWIN STATUS

Get device twin sync status

**Request:**
```
TWIN STATUS
```

**Response:**
```
OK|synced|3500|1
  | status | last_sync_ms | update_count
```

#### TWIN DESIRED

Get desired properties

**Request:**
```
TWIN DESIRED
```

**Response:**
```
OK|desiredVersion:1.0.1|telemetryInterval:5000
```

#### TWIN REPORTED

Get reported properties

**Request:**
```
TWIN REPORTED
```

**Response:**
```
OK|reportedVersion:1.0.0|sensorCount:2|signal:-50dBm
```

---

### GPIO Commands (Simple Pin Control)

#### GPIO SET

Set pin as output and write value

**Request:**
```
GPIO SET 16 HIGH
GPIO SET 16 LOW
GPIO SET 16 1
GPIO SET 16 0
```

**Response:**
```
OK|GPIO 16 set to HIGH
OK|GPIO 16 set to LOW
```

#### GPIO READ

Read pin state

**Request:**
```
GPIO READ 16
```

**Response:**
```
OK|GPIO 16: HIGH
OK|GPIO 16: 1023  (if analog)
```

#### GPIO PWM

Set PWM on pin

**Request:**
```
GPIO PWM 15 256 1000
```

**Response:**
```
OK|GPIO 15: PWM duty=256/1023 frequency=1000Hz
```

---

### Configuration Commands

#### CONFIG SAVE

Save current config to EEPROM

**Request:**
```
CONFIG SAVE
```

**Response:**
```
OK|Config saved to EEPROM
```

#### CONFIG CLEAR

Clear EEPROM config (factory reset)

**Request:**
```
CONFIG CLEAR
```

**Response:**
```
OK|EEPROM cleared - restart required
```

#### CONFIG DUMP

Get full config dump

**Request:**
```
CONFIG DUMP
```

**Response:**
```
OK|ssid:my-wifi
password:****
device_id:picow1
hub_fqdn:my-iot-hub.azure-devices.net
hostname:picow1
```

---

### Diagnostic Commands

#### DEBUG ON / OFF

Enable verbose debug output to serial

**Request:**
```
DEBUG ON
DEBUG OFF
```

**Response:**
```
OK|Debug logging enabled
OK|Debug logging disabled
```

#### UPTIME

Get device uptime

**Request:**
```
UPTIME
```

**Response:**
```
OK|3600|1000  (seconds | milliseconds)
```

#### MEMORY

Get memory usage

**Request:**
```
MEMORY
```

**Response:**
```
OK|heap_free:45000|heap_size:50000|stack_free:8000
```

#### TEMP

Get internal die temperature

**Request:**
```
TEMP
```

**Response:**
```
OK|45.2  (°C)
```

---

## Error Codes

| Code | Meaning |
|------|---------|
| 1 | Unknown command |
| 2 | Invalid arguments |
| 3 | Sensor not found |
| 4 | MQTT not connected |
| 5 | EEPROM write failed |
| 6 | GPIO not available |
| 7 | Operation timeout |
| 8 | Permission denied |

### Error Response Format

```
ERROR|1|Unknown command: FOOBAR
ERROR|3|Sensor not found: DHT22
```

---

## Client Examples

### PowerShell

```powershell
function Invoke-SoftataCommand {
  param(
    [string]$Host,
    [int]$Port = 4242,
    [string]$Command
  )
  
  $client = New-Object System.Net.Sockets.TcpClient
  $client.Connect($Host, $Port)
  
  $stream = $client.GetStream()
  $writer = New-Object System.IO.StreamWriter($stream)
  $reader = New-Object System.IO.StreamReader($stream)
  
  $writer.WriteLine($Command)
  $writer.Flush()
  
  $response = $reader.ReadLine()
  
  $writer.Close()
  $stream.Close()
  $client.Close()
  
  return $response
}

# Usage
Invoke-SoftataCommand -Host "picow1.local" -Command "SENSOR READ"
Invoke-SoftataCommand -Host "picow1.local" -Command "STATUS"
```

### Python

```python
import socket

def softata_command(host, port, command):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((host, port))
        s.sendall(f"{command}\n".encode())
        response = s.recv(1024).decode()
        return response

# Usage
response = softata_command("picow1.local", 4242, "SENSOR READ")
print(response)
```

### Telnet

```bash
telnet picow1.local 4242
> SENSOR READ
< OK|2|timestamp
< DHT11|22.5|65.3
< BME280|22.7|64.2|1013.25
```

---

## Protocol Limitations

- Commands are synchronous (no async/streaming)
- Max response size: 512 bytes
- Command timeout: 5 seconds
- Max 4 concurrent connections
- No authentication (local network only)

---

## Future Enhancements

- [ ] Command pipelining (multiple commands in one request)
- [ ] Async notifications (unsolicited server messages)
- [ ] WebSocket support for browser clients
- [ ] Command scripting (batch operations)
- [ ] Performance metrics per command

