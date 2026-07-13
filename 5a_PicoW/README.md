# Pico W / Pico W2 Arduino CLI Track

This folder is the Arduino CLI-based companion to the optional Pico hardware path.

Goal:
- use Earle Philhower's Arduino BSP for Raspberry Pi Pico W / Pico W2
- keep the same IoT Hub twin contract where possible
- reuse the same desired/reported shape as the simulator

## What this track does

1. Installs the Pico board package for Arduino CLI.
2. Installs the common libraries used by the sketch.
3. Builds the firmware from the command line.
4. Uploads the firmware to a connected Pico W / Pico W2.
5. Leaves IoT Hub twin orchestration in the same shape as the simulator.

## Firmware folder

The starter firmware lives in [5a_PicoW/pico_firmware](5a_PicoW/pico_firmware).

It includes:
- `pico_firmware.ino` - starter sketch with telemetry, twin, C2D, and direct-method handlers
- `iot_config.h` - local device and hub configuration placeholders

## Prerequisites

- Windows with PowerShell
- USB-connected Pico W or Pico W2
- The board in BOOTSEL mode if you are flashing manually
- Azure IoT Hub S1 or higher if you want to use twin operations
- `IOTHUB_NAME` set for twin checks and device onboarding scripts

## Step 1: Install Arduino CLI

If `arduino-cli` is not already on PATH, run:

```powershell
.\5a_PicoW\install_arduino_cli.ps1
```

That script uses Winget to install the `ArduinoSA.CLI` package and then checks that `arduino-cli` is available.

## Step 2: Add Arduino CLI to PATH

Run this after installation if the current terminal still does not see `arduino-cli`:

```powershell
.\5a_PicoW\add_arduino_cli_to_path.ps1
```

This updates the current session and the user PATH so the next scripts can find `arduino-cli` without extra manual steps.

## Step 3: Install board support and libraries

```powershell
.\5a_PicoW\setup_arduino_cli_pico.ps1
```

This script uses a repo-local `.arduino-cli` config folder so it does not inherit a broken global `additional_urls` setting.

## Step 4: Build firmware

```powershell
.\5a_PicoW\build_upload_pico.ps1 -SketchPath .\5a_PicoW\pico_firmware\pico_firmware.ino -Action build
```

If a Pico board is connected, the script tries to detect whether it is a Pico W or Pico W2 from `arduino-cli board list` and picks the matching FQBN automatically. You can still override it with `-Fqbn` if needed.

## Step 5: Upload firmware

```powershell
.\5a_PicoW\build_upload_pico.ps1 -SketchPath .\5a_PicoW\pico_firmware\pico_firmware.ino -Action upload -Port COM6
```

## Notes

- `Fqbn` is configurable in the script so you can choose the board definition that matches your hardware and BSP version.
- Pico W2 BSP note: there is no separate BSP install step. Pico W and Pico W2 are both provided by the same Earle RP2040 core (`rp2040:rp2040`) installed in Step 3.
- To verify Pico W2 support is available, run: `arduino-cli --config-dir .\5a_PicoW\.arduino-cli board listall | Select-String "Pico 2 W|rpipico2w"`
- If you are targeting Pico W2 and the board package uses a different name, inspect `arduino-cli board listall` first.
- Device twin and telemetry contract should stay aligned with the simulator to keep the existing monitoring scripts useful.
- Caveat (optional): if other tools that use the global Arduino CLI config fail with an invalid `additional_urls` value, run `./5a_PicoW/cleanup_arduino_cli_global_config.ps1` once to clean malformed `[] ,` prefixes from `arduino-cli.yaml`.
