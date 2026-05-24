#!/usr/bin/env bash
#
# monitor.sh — Thonny-like serial monitor for ESP32 MicroPython
#
# Shows boot output, print(), tracebacks, and ESP log lines in real time.
# Forwards keyboard input to the MicroPython REPL.
#
# QUICK START
# -----------
#   ./monitor.sh
#   ./monitor.sh --reset          # reset board on connect (see boot + main.py)
#   PORT=/dev/ttyUSB1 ./monitor.sh
#
# Close Thonny or any other program using the serial port first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

PORT="${PORT:-/dev/ttyUSB0}"
BAUD="${BAUD:-115200}"
CONDA_ENV="${CONDA_ENV:-thonny}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [monitor.py options]

Connect to ESP32 MicroPython serial output (Thonny-like).

CURRENT DEFAULTS
  PORT=$PORT
  BAUD=$BAUD
  CONDA_ENV=$CONDA_ENV

OPTIONS (passed to monitor.py)
  -p, --port PORT     Serial port (default: $PORT)
  -b, --baud BAUD     Baud rate (default: $BAUD)
      --reset         Hardware-reset board on connect
      --no-color      Disable ANSI highlighting
  -h, --help          Show monitor.py help

EXAMPLES
  ./monitor.sh
  ./monitor.sh --reset
  PORT=/dev/ttyUSB1 ./monitor.sh

KEYS (while connected)
  Ctrl+C   interrupt board / break into REPL
  Ctrl+D   soft reset
  Ctrl+]   quit
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

ensure_pyserial() {
    python -c "import serial" >/dev/null 2>&1 || {
        log "Installing pyserial into conda env '$CONDA_ENV'"
        python -m pip install -q pyserial
    }
}

check_port() {
    [[ -e "$PORT" ]] || die "serial port not found: $PORT (try: ls /dev/ttyUSB*)"
    if command -v lsof >/dev/null 2>&1; then
        local holders
        holders="$(lsof -t "$PORT" 2>/dev/null || true)"
        if [[ -n "$holders" ]]; then
            die "serial port busy: $PORT (close Thonny/other programs using it)"
        fi
    fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

activate_conda_env
ensure_pyserial
check_port

exec python "$REPO_ROOT/monitor.py" --port "$PORT" --baud "$BAUD" "$@"
