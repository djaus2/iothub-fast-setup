# Azure IoT Hub Fast Setup

This repository provides a practical, script-first setup for an Azure IoT Hub lab, including  quick setup scripts:
- Creating one IoT Hub,
- a C# simulator for devices
- an optional Raspberry Pi Pico W / Pico W2 hardware track
- Telemetry with off/on capability
- Twinning, D2C and C2D messages
- Device Update (under development)
- Quick tear down

## Optional Hardware Track (Pico W / Pico W2)

An optional hardware path is available in [5_PicoW/README.md](5_PicoW/README.md).

The Pico track is designed to reuse the same twin contract as the simulator, with an S1 hub required for twin update operations.

This keeps the simulator flow intact while adding scripts to:
- provision Pico device identities,
- retrieve connection strings for firmware configuration,
- apply desired twin runtime profile values for hardware devices.

Current verified steps:
1. Create the resource group and IoT Hub with the quick setup script.
2. Provision Pico device identities.
3. Retrieve device connection strings.
4. Apply the desired twin runtime profile.
5. Verify desired twin values with the existing IoT Hub commands.

## Arduino CLI Track

The Arduino CLI-based Pico flow is in [5a_PicoW/README.md](5a_PicoW/README.md).

Use this when you want a host-side build/upload workflow for Pico W / Pico W2 with Earle Philhower's BSP.

## Blog posts

For more information see the blog posts:

- [IoT Hub: Quick setup](https://davidjones2.sportronics.com.au/iot/IoT_Hub-C-_Device_Simulator_Deployment-iot.html)
- [IoT Hub Device Twin vs Device Update for IoT Hub Simulators](https://davidjones2.sportronics.com.au/iot/IoT_Hub-Device_Twin_vs_Device_Update_for_IoT_Hub_Simulators-iot.html)
- [IoT Hub C# Device Simulator Deployment](https://davidjones2.sportronics.com.au/iot/IoT_Hub-C-_Device_Simulator_Deployment-iot.html)
- [IoT Hub ADU Workflow for IoT Hub Simulators](https://davidjones2.sportronics.com.au/iot/IoT_Hub-ADU_Workflow_for_IoT_Hub_Simulators-iot.html)
- [IoT Hub Pico W / Pico W2 Optional Hardware Track](https://davidjones2.sportronics.com.au/iot/IoT_Hub-RPI_Pico_W-iot.html)
  - Have successfully provisioned 2 RPI Pico W 2 devices and uploaded firmware to them. Verified twin values and telemetry.  
  - Both viewable and able to be interrogated in Azure IoT Explorer :).