# ESP32 MicroPython camera server and HTTP stream client, adapted from
# geekscape/aiko_engine_mp examples/esp32_cam (commit 479cf95).
# Upstream licence (AGPL-3.0): licence/aiko_engine_mp-License

# import server
# hdr, con, cam = server.initialize()
# server.connect(hdr, con, cam)

import camera
import esp
import gc
import machine
import network
import socket
import time

LED_FLASH_PIN = 4
LED_STATUS_PIN = 33

_DEFAULT_UID = "username"
_DEFAULT_PWD = "password"
_DEFAULT_APS = {"ExampleSSID": "example-wifi-password"}

try:
    from config import UID, PWD, WIFI_APS as APS
    _USING_DEFAULTS = False
except ImportError:
    UID = _DEFAULT_UID
    PWD = _DEFAULT_PWD
    APS = _DEFAULT_APS
    _USING_DEFAULTS = True


def _warn_if_defaults():
    if _USING_DEFAULTS:
        print("WARNING: config.py missing on device — copy config.example.py to config.py and re-flash")
        return
    if UID == _DEFAULT_UID and PWD == _DEFAULT_PWD:
        print("WARNING: using default stream credentials — edit esp32cam/config.py and re-flash")
    if APS == _DEFAULT_APS:
        print("WARNING: using example Wi-Fi config — edit esp32cam/config.py and re-flash")


def initialize():
    print("#### server.initialize()")
    _warn_if_defaults()

    hdr = {
        "stream": """HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace; boundary=kaki5
Connection: keep-alive
Cache-Control: no-cache, no-store, max-age=0, must-revalidate
Expires: Thu, Jan 01 1970 00:00:00 GMT
Pragma: no-cache
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET
Access-Control-Allow-Headers: *""",
        "frame": """--kaki5
Content-Type: image/jpeg""",
    }

    try:
        camera.deinit()
    except OSError:
        pass

    cam = camera.init(
        0,
        d0=4, d1=5, d2=18, d3=19, d4=36, d5=39, d6=34, d7=35,
        format=camera.JPEG,
        framesize=camera.FRAME_QVGA,
        xclk_freq=camera.XCLK_20MHz,
        href=23, vsync=25, reset=-1, pwdn=-1,
        sioc=27, siod=26, xclk=21, pclk=22,
        fb_location=camera.PSRAM,
    )
    print("Camera ready?", cam)

    sta_if = network.WLAN(network.STA_IF)
    sta_if.active(True)

    ssid_found = False
    while not ssid_found:
        print("#### Wi-Fi scan()")
        aps = sta_if.scan()
        for ap in aps:
            ssid = ap[0].decode("utf-8")
            if ssid in APS:
                print("SSID:", ssid)
                ssid_found = True
                sta_if.connect(ssid, APS[ssid])
                break
        if not ssid_found:
            time.sleep(1.0)

    con = ()
    for _ in range(10):
        if sta_if.isconnected():
            con = sta_if.status()
            ip = sta_if.ifconfig()[0]
            print("Wi-Fi connected:", ip)
            print("Stream URL: http://%s/%s/%s" % (ip, UID, PWD))
            break
        print("Wi-Fi not ready. Wait...")
        time.sleep(2)
    else:
        print("Wi-Fi not ready")

    return hdr, con, cam


def connect(pin_led_status, hdr, con, cam):
    print("#### server.connect()")

    if con and cam:
        if cam:
            camera.framesize(camera.FRAME_QVGA)
            camera.quality(11)
            camera.contrast(2)
            camera.saturation(2)
            camera.brightness(2)
            camera.speffect(camera.EFFECT_NONE)
            camera.whitebalance(camera.WB_NONE)
            camera.flip(0)
            camera.mirror(0)

        if con:
            port = 80
            addr = socket.getaddrinfo("0.0.0.0", port)[0][-1]
            _socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            _socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            _socket.bind(addr)
            _socket.listen(1)

            while True:
                cs, ca = _socket.accept()
                print("Request from:", ca)
                w = cs.recv(200)
                try:
                    path = w.decode().split("\r\n")[0].split()[1]
                    _, uid, pwd = path.split("/")
                except (IndexError, ValueError):
                    print("Bad request (expected GET /%s/%s HTTP/1.1)" % (UID, PWD))
                    cs.close()
                    continue
                if uid != UID or pwd != PWD:
                    print("Not authenticated: %s/%s" % (uid, pwd))
                    cs.write(b"HTTP/1.1 401 Unauthorized\r\n\r\n")
                    cs.close()
                    continue

                cs.write(b"%s\r\n\r\n" % hdr["stream"])
                pic = camera.capture
                put = cs.write
                hr = hdr["frame"]
                while True:
                    pin_led_status.value(not pin_led_status.value())
                    time_start = time.ticks_ms()
                    try:
                        put(b"%s\r\n\r\n" % hr)
                        put(pic())
                        put(b"\r\n")
                    except Exception as e:
                        print("TCP send error", e)
                        cs.close()
                        break
                    gc.collect()
                    print("Frame: %d ms, mem: %d" % (time.ticks_ms() - time_start, gc.mem_free()))
    else:
        if not con:
            print("WiFi not connected.")
        if not cam:
            print("Camera not ready.")
        else:
            camera.deinit()
        print("System not ready. Please restart")

    print("System aborted")


def run():
    pin_flash_led = machine.Pin(LED_FLASH_PIN, machine.Pin.OUT)
    pin_flash_led.value(False)
    pin_status_led = machine.Pin(LED_STATUS_PIN, machine.Pin.OUT)
    pin_status_led.value(False)

    hdr, con, cam = initialize()
    pin_flash_led.value(True)
    time.sleep(0.25)
    pin_flash_led.value(False)
    connect(pin_status_led, hdr, con, cam)
