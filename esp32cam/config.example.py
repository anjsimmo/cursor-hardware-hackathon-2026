# Copy to config.py and edit. config.py is gitignored — do not commit secrets.
#
#   cp esp32cam/config.example.py esp32cam/config.py

# Stream URL: http://<esp32-ip>/<UID>/<PWD>
UID = "username"
PWD = "password"

# Wi-Fi networks to scan for (SSID -> password). First match in range wins.
WIFI_APS = {
    "MyHomeWiFi": "home-wifi-secret",
    "GuestNetwork": "guest-password",
}
