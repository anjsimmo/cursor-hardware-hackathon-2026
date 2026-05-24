# ESP32 MicroPython camera stream

Authenticated MJPEG camera server for the **Freenove ESP32-WROVER** board (and compatible ESP32 + camera modules), with host-side flash, monitor, and streaming tools.

Vibe coded by Angie Simmons and Nick Meinhold at the [Cursor Melbourne Hardware Hack](https://luma.com/qf7urg29) (24 May 2026, Stone & Chalk Melbourne).

**Inspired by:** Andy Gelme’s [`esp32_cam`](https://github.com/geekscape/aiko_engine_mp/tree/main/examples/esp32_cam) — [`server.py`](esp32cam/server.py) and [`streaming_client_1.py`](streaming_client_1.py) are adapted from that example ([AGPL-3.0](licence/aiko_engine_mp-License)). See [Inspired by and porting notes](#inspired-by-and-porting-notes) for Freenove firmware changes.

## Features

- MJPEG stream over HTTP with **URL-path authentication** (`http://<ip>/<uid>/<pwd>`)
- Wi-Fi scan and connect from a configurable list of networks
- Flash and monitor tooling (`flash.sh`, `monitor.sh`) — no Thonny required
- Laptop-side stream viewer (`streaming_client_1.py`)

## Hardware

- **Board:** Freenove ESP32-WROVER ([FNK0046 Super Starter Kit](https://docs.freenove.com/projects/fnk0046/en/latest/index.html))
- **Camera firmware:** lemariva camera-enabled MicroPython (see [Firmware](#firmware))
- **USB serial:** typically `/dev/ttyUSB0` (CH340)

## Quick start

### 1. Configure credentials

```bash
cp esp32cam/config.example.py esp32cam/config.py
# Edit esp32cam/config.py — set UID, PWD, and WIFI_APS
```

`config.py` is gitignored and will not be committed.

### 2. Flash firmware and upload code (first time)

```bash
conda activate thonny
./flash.sh --with-firmware
```

### 3. Watch serial output

```bash
./monitor.sh --reset
```

Look for `Stream URL: http://192.168.x.x/<uid>/<pwd>` in the log.

### 4. View the stream

```bash
./streaming_client_1.py --url http://<esp32-ip>/<uid>/<pwd>
```

Subsequent code-only updates (firmware already installed):

```bash
./flash.sh
```

## Configuration

Edit **`esp32cam/config.py`** (copy from [`config.example.py`](esp32cam/config.example.py)). `flash.sh` uploads it to the ESP32 as `/config.py`.

| Variable | Purpose |
|----------|---------|
| `UID` | Stream authentication username (URL path segment) |
| `PWD` | Stream authentication password (URL path segment) |
| `WIFI_APS` | Dict of `SSID -> password`; board scans and connects to the first match |

Example:

```python
UID = "myuser"
PWD = "mysecret"

WIFI_APS = {
    "MyHomeWiFi": "home-wifi-password",
    "PhoneHotspot": "hotspot-password",
}
```

**Wi-Fi tip:** A **phone hotspot** is recommended for demos and first-time setup. Venue, office, and guest Wi‑Fi networks often block or restrict IoT devices, use captive portals, or simply fail to connect reliably. Put your hotspot SSID first in `WIFI_APS` so the board finds it quickly.

**Security notes:**

- Never commit `config.py` — it is gitignored
- If config is missing on the device, the board uses placeholder defaults and prints **WARNING** on boot
- Wrong stream credentials receive `401 Unauthorized`

## Project layout

```
esp32cam/
  config.example.py Committed template — copy to config.py
  config.py         Your credentials (gitignored)
  server.py         Camera server (AGPL-3.0 — see licence/)
  main.py           Boot entry point
  boot.py           MicroPython boot hook
licence/
  aiko_engine_mp-License  AGPL-3.0 for server.py and streaming_client_1.py
  MIT-License             Hackathon code (same as root LICENSE)
firmware/           Firmware provenance docs
*.bin               Prebuilt firmware (third-party, convenience only)
flash.sh            Upload esp32cam/*.py (+ optional firmware flash)
monitor.sh          Thonny-like serial monitor
streaming_client_1.py  Laptop MJPEG viewer (AGPL-3.0)
```

## Firmware

This project requires a MicroPython build with the **`camera`** module. Stock [micropython.org](https://micropython.org/download/ESP32_GENERIC/) ESP32 builds do not include it.

| File | Use |
|------|-----|
| `micropython_camera_feeeb5ea3_esp32_idf4_4.bin` | **Required** — camera-enabled build for Freenove ESP32-WROVER |
| `ESP32_GENERIC-SPIRAM-20220117-v1.18.bin` | Stock MicroPython (no camera) — not suitable for this server |

Both binaries are **included for convenience only** (~1.4 MB each). They are third-party builds — not hackathon code and not covered by this repository’s MIT licence. Full provenance and download links: [`firmware/README.md`](firmware/README.md).

Boot version string for the camera firmware:

```
MicroPython v1.18-74-gfeeeb5ea3 on 2022-02-02; ESP32-cam module (i2s) with ESP32
```

**Sources:**

1. [Freenove FNK0046 kit download](https://github.com/Freenove/Freenove_Super_Starter_Kit_for_ESP32/archive/refs/heads/master.zip) → `Python/Python_Codes/23.1_Camera_WebServer/firmware/micropython_camera_feeeb5ea3_esp32_idf4_4.bin`
2. Built from [lemariva/micropython-camera-driver](https://github.com/lemariva/micropython-camera-driver)
3. Documented in [Freenove Chapter 23 Camera Web Server](https://docs.freenove.com/projects/fnk0046/en/latest/fnk0046/codes/Python/30_Camera_Web_Server.html)

Flash camera firmware + upload code:

```bash
conda activate thonny
./flash.sh --with-firmware --firmware micropython_camera_feeeb5ea3_esp32_idf4_4.bin
```

## Scripts

### `flash.sh`

Uploads `esp32cam/*.py` via `mpremote`. Uploads `config.py` as `/config.py` on the device (if present).

```bash
./flash.sh                 # upload code
./flash.sh --with-firmware # erase flash, write firmware, upload code
PORT=/dev/ttyUSB1 ./flash.sh
```

### `monitor.sh`

Serial monitor at 115200 baud with error highlighting. Keys: **Ctrl+C** interrupt, **Ctrl+D** soft reset, **Ctrl+]** quit.

```bash
./monitor.sh
./monitor.sh --reset
```

### `streaming_client_1.py`

OpenCV MJPEG viewer for the authenticated stream URL.

```bash
./streaming_client_1.py --url http://<esp32-ip>/<uid>/<pwd>
```

## Host environment

Use a Python environment with `esptool` and `mpremote`. This repo assumes a conda env named **`thonny`**:

```bash
conda activate thonny
```

| Tool | Purpose |
|------|---------|
| esptool | Flash `.bin` firmware |
| mpremote | Upload `.py` files to the board |
| pyserial | Serial monitor |

You must be in the **`dialout`** group (or otherwise have access to the serial device). Close Thonny before running `flash.sh` or `monitor.sh`.

## Inspired by and porting notes

[`esp32cam/server.py`](esp32cam/server.py) and [`streaming_client_1.py`](streaming_client_1.py) are adapted from Andy Gelme’s [`esp32_cam`](https://github.com/geekscape/aiko_engine_mp/tree/main/examples/esp32_cam) example in [aiko_engine_mp](https://github.com/geekscape/aiko_engine_mp) (commit [`479cf95`](https://github.com/geekscape/aiko_engine_mp/commit/479cf9533c967ccb0adad47072e7c15290463a71)). Those files remain under the upstream [**AGPL-3.0 licence**](licence/aiko_engine_mp-License) ([source](https://github.com/geekscape/aiko_engine_mp/blob/master/License)).

Everything else written during the [Cursor Melbourne Hardware Hack](https://luma.com/qf7urg29) — flash/monitor tooling, config layout, docs, etc. — is **MIT** and free to use as you wish (see [Licence](#licence)).

Andy Gelme’s example targets **KAKI5** camera firmware:

```
MicroPython v1.20.0-206-g33b403dfb-kaki5 on 2023-07-11; ESP32 CAMERA w/SSL (KAKI5)
```

This project targets the **Freenove ESP32-WROVER** with **lemariva** camera firmware (`v1.18-74-gfeeeb5ea3`). Changes needed to make that work:

| Area | KAKI5 example (aiko_engine_mp) | This project (Freenove / lemariva) |
|------|--------------------------------|-------------------------------------|
| `camera.init()` | `camera.init()` — no arguments | Full pin map for Freenove WROVER: `d0`–`d7`, `href`, `vsync`, `sioc`, `siod`, `xclk`, `pclk`, `fb_location=camera.PSRAM`, `format=camera.JPEG`, `framesize=camera.FRAME_QVGA`, `xclk_freq=camera.XCLK_20MHz` |
| Pixel format | `camera.pixformat(0)` in `connect()` | Set at init via `format=camera.JPEG`; `pixformat()` not available |
| Frame size | `camera.framesize(6)` (numeric) | `camera.framesize(camera.FRAME_QVGA)` |
| Special effects | `camera.speffect(0)` | `camera.speffect(camera.EFFECT_NONE)` |
| White balance | `camera.whitebalance(0)` | `camera.whitebalance(camera.WB_NONE)` |
| Flip / mirror | `camera.flip(False)` | `camera.flip(0)` / `camera.mirror(0)` |
| Exposure / gain | `aelevels`, `aecvalue`, `agcgain` | Removed — not in lemariva API |
| Auth credentials | `UID`/`PWD` as local `const()` inside `initialize()` | Module-level import from `config.py` |
| Stream URL | Not printed | Printed on Wi-Fi connect |
| Auth errors | Silent close | `401 Unauthorized` + clearer request parsing |
| Secrets | Hard-coded in `server.py` | `esp32cam/config.py` (gitignored) |

Reference implementation for Freenove camera init: [Freenove Chapter 23](https://docs.freenove.com/projects/fnk0046/en/latest/fnk0046/codes/Python/30_Camera_Web_Server.html) and [`picoweb_video.py`](https://github.com/Freenove/Freenove_Super_Starter_Kit_for_ESP32/blob/master/Python/Python_Codes/23.1_Camera_WebServer/picoweb_video.py) in the Freenove kit repo.

## Licence

Built at the [Cursor Melbourne Hardware Hack](https://luma.com/qf7urg29). This repository mixes licences:

| What | Licence | Full text |
|------|---------|-----------|
| **Hackathon code** — `flash.sh`, `monitor.sh`, `monitor.py`, `esp32cam/main.py`, `esp32cam/boot.py`, `esp32cam/config.example.py`, docs | **MIT** | [LICENSE](LICENSE) · [licence/MIT-License](licence/MIT-License) |
| **Adapted from Andy Gelme** — [`esp32cam/server.py`](esp32cam/server.py), [`streaming_client_1.py`](streaming_client_1.py) | **AGPL-3.0** | [licence/aiko_engine_mp-License](licence/aiko_engine_mp-License) |
| **`esp32cam/config.py`** | *(your file)* | Gitignored — never commit Wi-Fi passwords |
| **`*.bin` firmware** | **Third-party** | Included for convenience only — see [`firmware/README.md`](firmware/README.md) |

Copyright (c) 2026 Angie Simmons and Nick Meinhold (MIT hackathon portions).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `serial port busy` | Close Thonny or other apps using the port |
| `config missing` warning | `cp esp32cam/config.example.py esp32cam/config.py`, edit, and re-flash |
| `Camera deinit Failed` on boot | Harmless on cold boot — ignored |
| `AttributeError: pixformat` | Wrong firmware — flash `micropython_camera_feeeb5ea3_esp32_idf4_4.bin` |
| Wi-Fi never connects | Check `WIFI_APS` SSIDs match scan results (see monitor log) |
| `Not authenticated` | Match `--url` path to `UID`/`PWD` in `config.py` |
