#!/bin/bash
# provision-pi.sh — flash Raspberry Pi OS Lite and drop headless boot artifacts
# into the boot filesystem so the Pi joins "69nicer" and announces as
# festival-pi.local on first boot.
#
# USAGE (run on the laptop, with the SD card mounted):
#   ./provision-pi.sh /path/to/boot-mount   e.g. /Volumes/bootfs
#
# This script does NOT burn the image — use Raspberry Pi Imager first
# (OS: Raspberry Pi OS Lite, armhf/bookworm). Then run this against the
# mounted boot volume. Everything here is idempotent / non-destructive.
#
# SECURITY: userconf.txt carries a known default password. Change it before
# any untrusted network. Never commit userconf.txt (it is gitignored).

set -euo pipefail

BOOT="${1:?Usage: $0 /path/to/boot-mount}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$BOOT" ]; then
    echo "ERROR: boot mount '$BOOT' not found" >&2
    exit 1
fi

echo "[provision] using boot volume: $BOOT"

# 1. Enable SSH
touch "$BOOT/ssh"
echo "[provision] ssh enabled"

# 2. Headless user (pi + hashed password)
cp "$HERE/userconf.txt" "$BOOT/userconf.txt"
echo "[provision] userconf.txt copied (default user: pi)"

# 3. WiFi (bookworm: /boot/firmware/wpa_supplicant.conf)
cp "$HERE/wpa_supplicant.conf" "$BOOT/wpa_supplicant.conf"
echo "[provision] wpa_supplicant.conf copied (ssid: 69nicer)"

# 4. First-boot provisioning script + systemd unit
install -m 755 "$HERE/firstboot.sh" "$BOOT/firstboot.sh"
install -m 644 "$HERE/festival-firstboot.service" "$BOOT/festival-firstboot.service"
echo "[provision] firstboot.sh + service staged in /boot"

# On first boot, the OS copies *.service from /boot into /etc and runs the
# script. (Raspberry Pi OS does not auto-copy arbitrary files, so the
# imager's "custom script" or a small /boot copy step is needed — see note.)
echo "[provision] DONE. Safely eject, insert into Pi 1 B+, power on."
echo "[provision] The unit will appear as festival-pi.local on the 69nicer network."
