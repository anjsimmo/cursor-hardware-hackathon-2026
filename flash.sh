#!/usr/bin/env bash
#
# flash.sh — Deploy esp32cam/ to an ESP32 running MicroPython
#
# WHAT THIS SCRIPT DOES
# ---------------------
# Uploads every .py file from esp32cam/ to the ESP32 filesystem root,
# then soft-resets the board so main.py runs on boot.
#
#   esp32cam/boot.py            ->  /boot.py
#   esp32cam/main.py            ->  /main.py
#   esp32cam/server.py          ->  /server.py
#   esp32cam/config.py  ->  /config.py
#
# Copy esp32cam/config.example.py to esp32cam/config.py and edit before flashing.
# config.py is gitignored.
#
# TWO DEPLOY MODES
# ----------------
# 1. Upload only (default)
#    Use this when MicroPython is already on the board and you changed Python
#    code. Fast — takes a few seconds.
#
#      ./flash.sh
#
# 2. Full reflash (--with-firmware)
#    Erases the board, writes the MicroPython .bin firmware, then uploads all
#    esp32cam/ files. Use this the first time, or if the board is corrupted.
#
#      ./flash.sh --with-firmware
#
# PREREQUISITES
# -------------
# - ESP32 connected via USB (default port: /dev/ttyUSB0)
# - User in the dialout group (serial port access)
# - Conda env "thonny" with esptool (mpremote is auto-installed if missing)
# - Close Thonny or any other program using the serial port before running
#
# QUICK START
# -----------
#   cp esp32cam/config.example.py esp32cam/config.py   # edit UID, PWD, WIFI_APS
#   ./flash.sh                    # upload esp32cam/*.py (most common)
#   ./flash.sh --with-firmware    # firmware + upload (first-time setup)
#   ./flash.sh --help             # full option list
#
# OVERRIDES
# ---------
# Set env vars or pass flags — no args needed for normal use:
#
#   PORT=/dev/ttyUSB1 ./flash.sh
#   ./flash.sh --port /dev/ttyUSB1 --baud 921600
#
# After flashing, stream from your PC (see streaming_client_1.py):
#   ./streaming_client_1.py --url http://<esp32-ip>/username/password

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Defaults (override with environment variables)
PORT="${PORT:-/dev/ttyUSB0}"
BAUD="${BAUD:-460800}"
CHIP="${CHIP:-esp32}"
CONDA_ENV="${CONDA_ENV:-thonny}"
SRC_DIR="${SRC_DIR:-$REPO_ROOT/esp32cam}"
FIRMWARE="${FIRMWARE:-$REPO_ROOT/micropython_camera_feeeb5ea3_esp32_idf4_4.bin}"
FLASH_OFFSET="${FLASH_OFFSET:-0x1000}"
WITH_FIRMWARE="${WITH_FIRMWARE:-0}"
SKIP_RESET="${SKIP_RESET:-0}"

usage() {
    cat <<EOF
Deploy esp32cam/ MicroPython files to an ESP32.

WHAT GETS COPIED
  All .py files in: $SRC_DIR
  Uploaded to the ESP32 root (e.g. boot.py, main.py, server.py)
  config.py is uploaded as /config.py on the device (if present)

DEFAULT BEHAVIOUR (no arguments)
  1. Activate conda env: $CONDA_ENV
  2. Upload esp32cam/*.py via mpremote
  3. Soft-reset the board

FULL REFLASH (--with-firmware)
  1. Erase flash and write MicroPython firmware
  2. Upload esp32cam/*.py
  3. Soft-reset the board

CURRENT DEFAULTS
  PORT=$PORT
  BAUD=$BAUD
  CHIP=$CHIP
  CONDA_ENV=$CONDA_ENV
  SRC_DIR=$SRC_DIR
  FIRMWARE=$FIRMWARE

OPTIONS
  -p, --port PORT           Serial port (env: PORT)
  -b, --baud BAUD           esptool baud rate (env: BAUD)
  -s, --src-dir DIR         Python source folder (env: SRC_DIR)
  -f, --firmware PATH       MicroPython .bin file (env: FIRMWARE)
      --with-firmware       Erase flash and install firmware before upload
      --skip-reset          Upload only; do not reset the board afterward
  -h, --help                Show this help

ENVIRONMENT VARIABLES
  PORT, BAUD, CHIP, CONDA_ENV, SRC_DIR, FIRMWARE, WITH_FIRMWARE, SKIP_RESET

EXAMPLES
  ./flash.sh
  ./flash.sh --with-firmware
  PORT=/dev/ttyUSB1 ./flash.sh
  ./flash.sh --port /dev/ttyUSB1

TROUBLESHOOTING
  "serial port busy"       Close Thonny or other apps using $PORT
  "serial port not found"  Check USB cable; try: ls /dev/ttyUSB*
  Board won't connect      Hold BOOT, plug in USB, release BOOT; retry
  Wi-Fi fails after boot   Edit esp32cam/config.py WIFI_APS and re-flash
  Default credential warn  cp config.example.py config.py, edit, and re-flash
EOF
}

log() {
    printf '==> %s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

activate_conda_env() {
    if [[ -n "${CONDA_PREFIX:-}" && "${CONDA_DEFAULT_ENV:-}" == "$CONDA_ENV" ]]; then
        return 0
    fi

    local conda_base=""
    if command -v conda >/dev/null 2>&1; then
        conda_base="$(conda info --base 2>/dev/null || true)"
    fi
    if [[ -z "$conda_base" && -n "${CONDA_EXE:-}" ]]; then
        conda_base="$(cd "$(dirname "$CONDA_EXE")/.." && pwd)"
    fi
    if [[ -z "$conda_base" || ! -f "$conda_base/etc/profile.d/conda.sh" ]]; then
        die "conda not found; install Miniconda/Anaconda or activate env '$CONDA_ENV' yourself"
    fi

    # shellcheck disable=SC1091
    source "$conda_base/etc/profile.d/conda.sh"
    conda activate "$CONDA_ENV"
}

ensure_tools() {
    command -v python >/dev/null 2>&1 || die "python not found in conda env '$CONDA_ENV'"
    python -m esptool version >/dev/null 2>&1 || die "esptool not found in '$CONDA_ENV' (conda activate $CONDA_ENV && pip install esptool)"

    if ! python -m mpremote version >/dev/null 2>&1; then
        log "Installing mpremote into conda env '$CONDA_ENV'"
        python -m pip install -q mpremote
    fi
}

check_port() {
    [[ -e "$PORT" ]] || die "serial port not found: $PORT (is the ESP32 plugged in? try: ls /dev/ttyUSB*)"
    if command -v lsof >/dev/null 2>&1; then
        local holders
        holders="$(lsof -t "$PORT" 2>/dev/null || true)"
        if [[ -n "$holders" ]]; then
            die "serial port busy: $PORT (close Thonny/other programs using it)"
        fi
    fi
}

collect_source_files() {
    mapfile -t SOURCE_FILES < <(find "$SRC_DIR" -maxdepth 1 -type f -name '*.py' ! -name 'config.example.py' ! -name 'config.py' | sort)
    [[ ${#SOURCE_FILES[@]} -gt 0 ]] || die "no .py files found in $SRC_DIR"
    CONFIG_FILE="$SRC_DIR/config.py"
}

flash_firmware() {
    [[ -f "$FIRMWARE" ]] || die "firmware not found: $FIRMWARE"
    log "Erasing flash on $PORT"
    python -m esptool --chip "$CHIP" --port "$PORT" erase-flash
    log "Writing firmware: $FIRMWARE"
    python -m esptool --chip "$CHIP" --port "$PORT" --baud "$BAUD" \
        write-flash -z "$FLASH_OFFSET" "$FIRMWARE"
    log "Waiting for board to boot"
    sleep 3
}

upload_files() {
    local -a mpremote_cmd=(python -m mpremote connect "$PORT")
    local file base

    for file in "${SOURCE_FILES[@]}"; do
        base="$(basename "$file")"
        mpremote_cmd+=(+ fs cp "$file" ":$base")
    done
    if [[ -f "$CONFIG_FILE" ]]; then
        mpremote_cmd+=(+ fs cp "$CONFIG_FILE" ":config.py")
    else
        log "warning: $CONFIG_FILE not found — device will use defaults (cp config.example.py config.py)"
    fi

    if [[ "$SKIP_RESET" != "1" ]]; then
        mpremote_cmd+=(+ soft-reset)
    fi

    log "Uploading ${#SOURCE_FILES[@]} file(s) from $SRC_DIR to $PORT"
    for file in "${SOURCE_FILES[@]}"; do
        printf '    %s  ->  /%s\n' "$(basename "$file")" "$(basename "$file")"
    done
    if [[ -f "$CONFIG_FILE" ]]; then
        printf '    config.py  ->  /config.py\n'
    fi

    "${mpremote_cmd[@]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -b|--baud)
            BAUD="$2"
            shift 2
            ;;
        -s|--src-dir)
            SRC_DIR="$2"
            shift 2
            ;;
        -f|--firmware)
            FIRMWARE="$2"
            shift 2
            ;;
        --with-firmware)
            WITH_FIRMWARE=1
            shift
            ;;
        --skip-reset)
            SKIP_RESET=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1 (try --help)"
            ;;
    esac
done

log "Deploy mode: $([ "$WITH_FIRMWARE" = "1" ] && echo 'firmware + upload' || echo 'upload only')"
activate_conda_env
ensure_tools
check_port
collect_source_files

if [[ "$WITH_FIRMWARE" == "1" ]]; then
    flash_firmware
fi

upload_files
log "Done — board reset; main.py should start the camera server"
