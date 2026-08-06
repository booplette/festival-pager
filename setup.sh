#!/bin/bash
# Festival Pager — One-shot setup for Pi Zero base station
#
# Run this ON the Pi Zero after flashing Raspberry Pi OS Lite
# and connecting the AR9271 WiFi dongle + T3S3.
#
# Usage:
#   cd festival-pager
#   chmod +x setup.sh
#   sudo ./setup.sh

set -euo pipefail

PAGER_DIR="/home/pi/festival-pager"
DEPLOY_DIR="$PAGER_DIR/deploy"
DATA_DIR="$PAGER_DIR/data"

echo "=== Festival Pager Setup ==="

# -- 1. System packages --
echo "[1/7] Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    hostapd \
    dnsmasq \
    python3 \
    python3-pip \
    python3-venv \
    git

# Stop services while we configure them (may be auto-started)
sudo systemctl stop hostapd dnsmasq 2>/dev/null || true

# -- 2. Python environment --
echo "[2/7] Setting up Python virtual environment..."
cd "$PAGER_DIR"
python3 -m venv venv --system-site-packages
source venv/bin/activate
pip install --quiet meshtastic flask

# -- 3. Copy config files to system locations --
echo "[3/7] Installing systemd service..."
sudo cp "$DEPLOY_DIR/festival-pager.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable festival-pager

echo "[4/7] Configuring hostapd (WiFi hotspot)..."
sudo cp "$DEPLOY_DIR/hostapd.conf" /etc/hostapd/hostapd.conf

# Point hostapd defaults to our config
if [ -f /etc/default/hostapd ]; then
    sudo sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    sudo sed -i 's|^DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
fi
sudo systemctl unmask hostapd 2>/dev/null || true
sudo systemctl enable hostapd

# -- 4. dnsmasq --
echo "[5/7] Configuring dnsmasq (DNS + DHCP)..."
sudo cp "$DEPLOY_DIR/dnsmasq.conf" /etc/dnsmasq.d/festival-pager.conf
sudo systemctl enable dnsmasq

# -- 5. Static IP for wlan0 --
echo "[6/7] Setting static IP for wlan0..."
if command -v dhcpcd &>/dev/null; then
    # Raspberry Pi OS Bookworm+ uses dhcpcd
    echo "  Using dhcpcd method..."
    if ! grep -q "^interface wlan0" /etc/dhcpcd.conf 2>/dev/null; then
        cat <<EOF | sudo tee -a /etc/dhcpcd.conf

# Festival Pager hotspot
interface wlan0
    static ip_address=10.0.0.1/24
    static routers=10.0.0.1
    nohook wpa_supplicant
EOF
    fi
elif [ -d /etc/systemd/network ]; then
    # systemd-networkd
    echo "  Using systemd-networkd method..."
    sudo cp "$DEPLOY_DIR/wlan0.network" /etc/systemd/network/12-wlan0.network
elif [ -f /etc/network/interfaces ]; then
    # Legacy ifupdown
    echo "  Using ifupdown method..."
    sudo cp "$DEPLOY_DIR/wlan0.network" /etc/network/interfaces.d/wlan0
fi

# -- 6. Data directory --
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