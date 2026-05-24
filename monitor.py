#!/usr/bin/env python3
"""ESP32 MicroPython serial monitor (Thonny-like).

Connects to the board UART, prints boot output / print() / tracebacks in real
time, and forwards the keyboard for REPL interaction.

Usage
~~~~~
  ./monitor.py
  ./monitor.py --port /dev/ttyUSB0 --baud 115200
  ./monitor.py --reset          # hardware-reset board on connect
  ./monitor.sh                  # wrapper: activates conda env "thonny"

Keys (while connected)
~~~~~~~~~~~~~~~~~~~~~~
  Ctrl+C   send interrupt to board (break into MicroPython REPL)
  Ctrl+D   soft reset (MicroPython)
  Ctrl+]   quit monitor
"""

from __future__ import annotations

import argparse
import select
import sys
import termios
import time
import tty

try:
    import serial
except ImportError as exc:
    raise SystemExit(
        "pyserial is required (pip install pyserial). "
        "Try: conda activate thonny && pip install pyserial"
    ) from exc

ERROR_MARKERS = (
    "Traceback",
    "Error:",
    "ERROR",
    "Exception",
    "AttributeError",
    "TypeError",
    "ValueError",
    "OSError",
    "E (",
    "W (",
    "failed",
    "Failed",
)

INFO_MARKERS = (
    "####",
    "Stream URL:",
    "Wi-Fi connected",
    "Camera ready",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Serial monitor for ESP32 MicroPython (Thonny-like)."
    )
    parser.add_argument(
        "-p",
        "--port",
        default="/dev/ttyUSB0",
        help="Serial port (default: /dev/ttyUSB0)",
    )
    parser.add_argument(
        "-b",
        "--baud",
        type=int,
        default=115200,
        help="Baud rate (default: 115200, MicroPython REPL)",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Hardware-reset the board after opening the port",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI color highlighting",
    )
    return parser.parse_args()


def colorize(line: str, use_color: bool) -> str:
    if not use_color:
        return line
    if any(marker in line for marker in ERROR_MARKERS):
        return f"\033[31m{line}\033[0m"
    if any(marker in line for marker in INFO_MARKERS):
        return f"\033[36m{line}\033[0m"
    if line.strip().startswith(">>>"):
        return f"\033[33m{line}\033[0m"
    return line


def hardware_reset(ser: serial.Serial) -> None:
    ser.setDTR(False)
    ser.setRTS(True)
    time.sleep(0.1)
    ser.setRTS(False)
    time.sleep(0.1)


def write_serial(ser: serial.Serial, data: bytes) -> None:
    ser.write(data)
    ser.flush()


def emit_text(text: str, line_buf: list[str], use_color: bool) -> list[str]:
    line_buf[0] += text
    while "\n" in line_buf[0]:
        line, line_buf[0] = line_buf[0].split("\n", 1)
        sys.stdout.write(colorize(line + "\n", use_color))
    sys.stdout.flush()
    return line_buf


def run_monitor(port: str, baud: int, reset: bool, use_color: bool) -> int:
    if not sys.stdin.isatty():
        print("warning: stdin is not a TTY; keyboard input disabled", file=sys.stderr)

    try:
        ser = serial.Serial(port, baud, timeout=0.05)
    except serial.SerialException as exc:
        print(f"error: cannot open {port}: {exc}", file=sys.stderr)
        print("Close Thonny or any other program using the port.", file=sys.stderr)
        return 1

    if reset:
        hardware_reset(ser)
        time.sleep(0.5)

    use_color = use_color and sys.stdout.isatty()
    line_buf = [""]

    banner = (
        f"Connected to {port} @ {baud} baud\n"
        "Keys: Ctrl+C interrupt | Ctrl+D soft reset | Ctrl+] quit\n"
        "─" * 60
    )
    sys.stdout.write(colorize(banner + "\n", use_color))
    sys.stdout.flush()

    old_term = termios.tcgetattr(sys.stdin)
    try:
        tty.setcbreak(sys.stdin.fileno())
        while True:
            if ser.in_waiting:
                chunk = ser.read(ser.in_waiting)
                text = chunk.decode("utf-8", errors="replace")
                line_buf = emit_text(text, line_buf, use_color)

            if sys.stdin in select.select([sys.stdin], [], [], 0)[0]:
                key = sys.stdin.read(1)
                if key == "\x1d":  # Ctrl+]
                    break
                if key == "\x03":  # Ctrl+C
                    write_serial(ser, b"\x03")
                    continue
                if key == "\x04":  # Ctrl+D
                    write_serial(ser, b"\x04")
                    continue
                write_serial(ser, key.encode("utf-8", errors="replace"))

    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term)
        if line_buf[0]:
            sys.stdout.write(colorize(line_buf[0], use_color))
            sys.stdout.flush()
        ser.close()
        print("\nDisconnected.")

    return 0


def main() -> int:
    args = parse_args()
    return run_monitor(args.port, args.baud, args.reset, args.no_color)


if __name__ == "__main__":
    raise SystemExit(main())
