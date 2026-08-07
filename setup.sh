#!/bin/bash
# Festival Pager — One-shot setup for Pi 1 B+ base station
#
# Run this ON the Pi after flashing Raspberry Pi OS Lite (Bullseye armhf)
# and connecting the AR9271 WiFi dongle + T3S3 to the USB ports.
#
# Prerequisites:
#   - Pi 1 B+ booted and SSH-accessible
#   - SD card flashed with Raspberry Pi OS Lite (armhf / 32-bit)
#   - python3-venv already installed (from Session 6 provisioning)
#   - AR9271 plugged into USB + T3S3 plugged into USB
#
# Usage:
#   git clone https://github.com/booplette/festival-pager /home/pi/festival-pager
#   cd /home/pi/festival-pager
#   chmod +x setup.sh
#   sudo ./setup.sh

set -euo pipefail

PAGER_DIR="/home/pi/festival-pager"
DEPLOY_DIR="$PAGER_DIR/deploy"
DATA_DIR="$PAGER_DIR/data"

echo "=== Festival Pager Setup — Pi 1 B+ ==="

# -- 1. System packages --
echo "[1/7] Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    hostapd \
    dnsmasq \
    python3 \
    python3-pip \
    git

# Stop services while we configure them (may be auto-started on install)
sudo systemctl stop hostapd dnsmasq 2>/dev/null || true

# -- 2. Python environment --
echo "[2/7] Setting up Python virtual environment..."
cd "$PAGER_DIR"
if [ ! -d venv ]; then
    python3 -m venv venv --system-site-packages
fi
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet meshtastic flask

# -- 3. Systemd service --
echo "[3/7] Installing systemd service..."
sudo cp "$DEPLOY_DIR/festival-pager.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable festival-pager

# -- 4. hostapd (WiFi hotspot) --
echo "[4/7] Configuring hostapd (WiFi hotspot)..."
sudo cp "$DEPLOY_DIR/hostapd.conf" /etc/hostapd/hostapd.conf

# Point hostapd defaults to our config
if [ -f /etc/default/hostapd ]; then
    sudo sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    sudo sed -i 's|^DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
fi
sudo systemctl unmask hostapd 2>/dev/null || true
sudo systemctl enable hostapd

# -- 5. dnsmasq (DNS + DHCP) --
echo "[5/7] Configuring dnsmasq (DNS + DHCP)..."
sudo cp "$DEPLOY_DIR/dnsmasq.conf" /etc/dnsmasq.d/festival-pager.conf
sudo systemctl enable dnsmasq

# -- 6. Static IP for wlan0 --
echo "[6/7] Setting static IP for wlan0..."
if command -v dhcpcd &>/dev/null; then
    # Raspberry Pi OS Lite uses dhcpcd by default
    echo "  Using dhcpcd method..."
    if ! grep -q "^interface wlan0" /etc/dhcpcd.conf 2>/dev/null; then
        cat <<EOF | sudo tee -a /etc/dhcpcd.conf

# Festival Pager hotspot (added by setup.sh)
interface wlan0
    static ip_address=10.0.0.1/24
    static routers=10.0.0.1
    nohook wpa_supplicant
EOF
    fi
elif [ -d /etc/systemd/network ]; then
    # systemd-networkd fallback
    echo "  Using systemd-networkd method..."
    sudo cp "$DEPLOY_DIR/wlan0.network" /etc/systemd/network/12-wlan0.network
elif [ -f /etc/network/interfaces ]; then
    # Legacy ifupdown fallback
    echo "  Using ifupdown method..."
    sudo cp "$DEPLOY_DIR/wlan0.network" /etc/network/interfaces.d/wlan0
fi

# -- 7. Data directory --
echo "[7/7] Creating data directory..."
mkdir -p "$DATA_DIR"

# Symlink data files into the project root so the app finds them
ln -sf "$DATA_DIR/subscribers.json" "$PAGER_DIR/subscribers.json" 2>/dev/null || true
ln -sf "$DATA_DIR/notified.json" "$PAGER_DIR/notified.json" 2>/dev/null || true

# -- Done --
echo ""
echo "=== Setup complete! ==="
echo ""
echo "What to do next:"
echo ""
echo "  1. Edit /home/pi/festival-pager/config.json if needed"
echo "  2. Edit /home/pi/festival-pager/schedule.json with the festival acts"
echo "  3. Reboot: sudo reboot"
echo ""
echo "After reboot the Pi will:"
echo "  - Start 'Festival Pager' WiFi hotspot (10.0.0.1)"
echo "  - Run the notification service"
echo "  - Serve the web UI at http://10.0.0.1"
echo ""
echo "To check status:"
echo "  sudo systemctl status festival-pager"
echo "  sudo journalctl -u festival-pager -f"
echo ""
echo "To test the hotspot:"
echo "  Connect to 'Festival Pager' WiFi from your phone"
echo "  Visit http://10.0.0.1 — should show the captive portal"