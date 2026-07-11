# ADU Workflow (Simulator)

This workflow uses IoT Hub twins to signal Device Update intent for simulator devices.

## Prerequisites

- IoT Hub Standard tier (S1 or higher)
- Azure CLI with `azure-iot` extension
- `IOTHUB_NAME` environment variable set, or pass `-HubName`
- Simulator running from `csharp_simulator`

> Note: The simulator does not install packages by itself. It only signals update intent and restart handoff through twin properties.

## Scripts

- [adu_get_status.ps1](adu_get_status.ps1) — get current ADU status for all or single device
- [adu_set_target_version.ps1](adu_set_target_version.ps1) — set desired target version for all or single device
- [adu_clear_target_version.ps1](adu_clear_target_version.ps1) — clear/rollback desired target version for all or single device 
- [adu_restart_simulator.ps1](adu_restart_simulator.ps1) — restart simulator after external update workflow has completed
- 
## 1. Generate devices.json (if needed)

```powershell
.\3_Simulator\generate_devices_json.ps1
```

## 2. Start simulator

```powershell
.\3_Simulator\run_10_devices.ps1
```

## 3. Set ADU target version intent

All devices (device1..device10):

```powershell
.\4_ADU\adu_set_target_version.ps1 -TargetVersion 1.1.0
```

Single device:

```powershell
.\4_ADU\adu_set_target_version.ps1 -TargetVersion 1.1.0 -DeviceId device1
```

## 4. Check ADU status

```powershell
.\4_ADU\adu_get_status.ps1
```

Expected behavior:
- `desiredTargetVersion` set to target release
- `restartRequested` becomes `True` for affected devices
- simulator reports state then exits to allow external update workflow

## 5. Clear/rollback ADU intent

All devices:

```powershell
.\4_ADU\adu_clear_target_version.ps1
```

Single device:

```powershell
.\4_ADU\adu_clear_target_version.ps1 -DeviceId device1
```

## 6. Restart simulator after external update workflow

```powershell
.\3_Simulator\run_10_devices.ps1
```

## Notes

- This simulator does not install packages by itself.
- It only signals update intent and restart handoff through twin properties.
