# Start a device once set up

Use this quick runbook to bring one Pico device online after initial setup.

## 1. Set target device identity

Pick the device number (`N`) so firmware gets the right `deviceId` and key.

```powershell
.\5a_PicoW\set_picow_device_env.ps1
```

## 2. Set Wi-Fi and hub values in the same terminal

Use your preferred option. Example:

```powershell
.\5a_PicoW\set_iot_env.ps1 -WifiPassword "<your-wifi-password>" -IotHubName "my-iot-123"
```

Optional (if needed):

```powershell
.\5a_PicoW\set_com_port_env.ps1
```

## 3. Build and upload firmware

```powershell
.\5a_PicoW\build_upload_pico.ps1 -SketchPath .\5a_PicoW\pico_firmware\pico_firmware.ino -Action upload
```

Notes:
- The script prints the effective device id (for example `Using device id: picow1`).
- If upload says `No drive to deploy`, follow the BOOTSEL prompt, then press Enter to retry.

## 4. Check in Azure IoT Explorer

Assume Azure IoT Explorer is already installed.

Get the IoT Hub connection string:

```powershell
az iot hub connection-string show --hub-name my-iot-123 --policy-name iothubowner --query connectionString -o tsv
```

In Azure IoT Explorer:
- Add connection using the hub connection string.
- Open `picow1` or `picow2` under devices.
- Watch connection status and telemetry/messages etc while the device starts.

## 5. Watch serial logs

Use your detected COM port:

```powershell
arduino-cli --config-dir .\5a_PicoW\.arduino-cli monitor -p COM3 -c baudrate=115200
```

Healthy startup usually shows:
- Pico firmware starting
- Connecting to WIFI SSID ...
- Connected flow (without endless reconnect loop)

## 6. Confirm cloud connectivity

For `picow1`:

```powershell
az iot hub monitor-events --hub-name my-iot-123 --device-id picow1
```

You can also check state directly:

```powershell
az iot hub device-identity show --hub-name my-iot-123 --device-id picow1 --query "{connectionState:connectionState,lastActivityTime:lastActivityTime,status:status}" -o json
```

## Quick troubleshooting

- `Disconnected` with no activity:
  - Re-run steps 1 and 2 in the same terminal, then upload again.
- Upload fails with `No drive to deploy`:
  - Put board in BOOTSEL/UF2 mode and retry.
- No telemetry events:
  - Verify the selected device id matches the flashed board and IoT Hub device entry.
