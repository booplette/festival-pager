#!/bin/bash
# firstrun.sh — runs ONCE on first boot via Raspberry Pi OS's built-in
# firstrun.service (bookworm). That service executes /boot/firstrun.sh and
# then renames it to firstrun.sh.done, so this never runs again.
#
# What it does:
#   1. Joins WiFi "69nicer"
#   2. Installs + enables avahi so the unit is reachable as festival-pi.local
#   3. Starts a LAN beacon (UDP broadcast on 4242 + mDNS) so you can see it
#      appear on the network without knowing the IP.

set -euo pipefail

LOG=/var/log/festival-firstrun.log
exec >"$LOG" 2>&1
echo "[firstrun] $(date -Iseconds) starting"

# --- WiFi ---
WPA_SRC=/boot/firstrun.sh.wifi 2>/dev/null || true   # placeholder, not used
# We ship wpa_supplicant.conf at /boot/firmware via the imager copy step.
# But Raspberry Pi OS also honours /boot/wpa_supplicant.conf on first boot:
WPA_SRC=/boot/wpa_supplicant.conf
WPA_DST=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
if [ -f "$WPA_SRC" ]; then
    install -m 600 -o root -g root "$WPA_SRC" "$WPA_DST"
    echo "[firstrun] installed wpa_supplicant.conf -> $WPA_DST"
fi

systemctl restart wpa_supplicant.service 2>/dev/null || true
systemctl restart dhcpcd.service 2>/dev/null || true

# Wait for an IP on wlan0 (max ~90s)
IP=""
for i in $(seq 1 90); do
    IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2; exit}')
    [ -n "$IP" ] && break
    sleep 1
done
echo "[firstrun] wlan0 IP: ${IP:-none}"

# --- mDNS / avahi: reachable as festival-pi.local ---
if ! command -v avahi-daemon >/dev/null 2>&1; then
    apt-get update
    apt-get install -y avahi-daemon libnss-mdns
fi
hostnamectl set-hostname festival-pi 2>/dev/null || true
sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4/' /etc/nsswitch.conf 2>/dev/null || true
systemctl enable --now avahi-daemon

# --- LAN beacon: announce presence without knowing the IP ---
# Pure-Python (stdlib only) so it needs no netcat on the base image.
cat >/usr/local/bin/festival-announce.py <<'ANN'
#!/usr/bin/env python3
"""Announce festival-pi on the LAN: UDP broadcast every 30s + mDNS hostname.

No external deps (stdlib only). The mDNS name (festival-pi.local) is handled
by avahi; this just adds a UDP broadcast beacon on port 4242 so any listener
on the subnet can see the unit appear without knowing its IP.
"""
import socket
import time
from datetime import datetime

PORT = 4242
BROADCAST = "255.255.255.255"


def get_ip() -> str:
    out = ""
    try:
        import subprocess
        out = subprocess.run(
            ["ip", "-4", "addr", "show", "wlan0"],
            capture_output=True, text=True,
        ).stdout
    except Exception:
        return ""
    for line in out.splitlines():
        if "inet " in line:
            return line.split("inet ")[1].split("/")[0].strip()
    return ""


def main() -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    while True:
        ip = get_ip()
        if not ip:
            time.sleep(10)
            continue
        msg = f"festival-pi UP {ip} {datetime.now().isoformat(timespec='seconds')}"
        try:
            sock.sendto(msg.encode(), (BROADCAST, PORT))
        except OSError:
            pass
        try:
            import syslog
            syslog.syslog(syslog.LOG_INFO, msg)
        except Exception:
            pass
        time.sleep(30)


if __name__ == "__main__":
    main()
ANN
chmod +x /usr/local/bin/festival-announce.py

cat >/etc/systemd/system/festival-announce.service <<'SVC'
[Unit]
Description=Festival Pi LAN announcement beacon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/festival-announce.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC
systemctl enable --now festival-announce.service

# Immediate one-shot beacon so it shows up right away
IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2; exit}')
if [ -n "$IP" ]; then
    python3 - <<PY
import socket
from datetime import datetime
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.sendto(f"festival-pi UP ${IP} {datetime.now().isoformat(timespec='seconds')}".encode(),
         ("255.255.255.255", 4242))
PY
    logger -t festival-pi "festival-pi UP ${IP}"
fi

echo "[firstrun] done — unit live as festival-pi.local"
# NOTE: do NOT disable anything here. The OS's firstrun.service renames this
# script to firstrun.sh.done after exit, guaranteeing one-shot behaviour.
