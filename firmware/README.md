# ESP32 MicroPython camera firmware

Prebuilt binaries **included for convenience only**. They are third-party builds — not hackathon code and not covered by this repository’s MIT licence. Download from the sources below if you prefer.

## Camera-enabled build (required for `esp32cam/`)

| File | Description |
|------|-------------|
| `micropython_camera_feeeb5ea3_esp32_idf4_4.bin` | MicroPython v1.18 with `camera` module |

**Licence:** compiled from [lemariva/micropython-camera-driver](https://github.com/lemariva/micropython-camera-driver) (MIT) on top of [MicroPython](https://github.com/micropython/micropython) (MIT) and Espressif [esp32-camera](https://github.com/espressif/esp32-camera) (Apache-2.0). Redistribution of the binary is subject to those upstream licences.

**Sources:**

1. [Freenove FNK0046 kit](https://github.com/Freenove/Freenove_Super_Starter_Kit_for_ESP32) → `Python/Python_Codes/23.1_Camera_WebServer/firmware/micropython_camera_feeeb5ea3_esp32_idf4_4.bin`
2. [lemariva/micropython-camera-driver](https://github.com/lemariva/micropython-camera-driver)
3. [Freenove Chapter 23 Camera Web Server](https://docs.freenove.com/projects/fnk0046/en/latest/fnk0046/codes/Python/30_Camera_Web_Server.html)

Boot version string: `MicroPython v1.18-74-gfeeeb5ea3 on 2022-02-02; ESP32-cam module (i2s) with ESP32`

## Stock ESP32 build (no camera module)

| File | Description |
|------|-------------|
| `ESP32_GENERIC-SPIRAM-20220117-v1.18.bin` | Official MicroPython ESP32 SPIRAM image |

**Licence:** [MicroPython](https://github.com/micropython/micropython) — MIT licence.

**Source:** [micropython.org ESP32_GENERIC download](https://micropython.org/download/ESP32_GENERIC/) (2022-01-17 build). Does not include the `camera` module — not suitable for this project’s streaming server.
