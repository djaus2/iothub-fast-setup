# Pico W / Pico W2 Optional Hardware Track

This folder adds an optional physical device path (Raspberry Pi Pico W / Pico W2) alongside the C# simulator.

Goal: keep the same IoT Hub twin contract where possible so existing ADU/twin monitoring scripts remain useful.

## Prerequisites

- IoT Hub Standard tier (S1 or higher) for twin updates and status queries
- Azure CLI with azure-iot extension
- Environment variable IOTHUB_NAME set (or pass -HubName)
- Pico W/Pico W2 firmware built separately (Earle Philhower Arduino BSP path)

## Current Verified Flow

This optional track is meant to mirror the simulator contract as closely as possible.

Verified with the current repo state:

1. Create the resource group and IoT Hub with the quick setup script.
2. Provision Pico device identities.
3. Retrieve device connection strings for firmware configuration.
4. Apply desired twin runtime settings.
5. Validate twin values with existing IoT Hub commands.

## Phase 1: Provision Device Identities

Create one or more Pico device identities.

```powershell
.\5_PicoW\create_pico_devices.ps1 -Prefix picow -Start 1 -End 2
```

Get connection strings for firmware config.

```powershell
.\5_PicoW\get_pico_device_connections.ps1 -Prefix picow -Start 1 -End 2
```

Check desired vs reported twin values.

```powershell
.\5_PicoW\get_pico_status.ps1 -Prefix picow -Start 1 -End 2
```

## Phase 2: Set Runtime Profile in Desired Twin

Apply desired twin profile values that hardware firmware should consume.

```powershell
.\5_PicoW\set_pico_runtime_profile.ps1 -Prefix picow -Start 1 -End 2 -IntervalSeconds 5 -RandomEvery 10
```

This writes:

- properties.desired.sim.*
- properties.desired.deviceProfile.platform = pico-w

Note: the runtime profile step only works on Standard tier hubs.

## Phase 3: Validate Device Reports

Use existing status flow and IoT tools to verify:

- reported platform and runtime values
- reported sim values actually applied
- telemetry timestamps advancing

Existing script useful for ADU/twin checks:

```powershell
.\4_ADU\adu_get_status.ps1 -DeviceId picow1
```

## Notes

- ADU scripts in this repository set desired twin intent only. They do not install MCU firmware packages.
- For Pico W/W2, firmware update is handled by your board-specific upload/OTA pipeline.
- Keep desired/reported property names aligned with simulator to preserve script compatibility.
