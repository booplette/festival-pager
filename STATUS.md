# STATUS.md — Festival Pager

**Last updated:** 2026-08-07

## Overview
LoRa mesh notification system for music festivals. Pi 1 B+ base station with
AR9271 WiFi hotspot + T3S3 serial bridge sends Meshtastic DMs to subscribers
when their selected acts are about to start.

## Architecture
```
Pi 1 B+ (inside tent)
  ├── USB-A ▸ AR9271 WiFi — hotspot + captive portal (10.0.0.1)
  └── USB-A ▸ T3S3 — Meshtastic serial bridge (LoRa mesh, EU868)
                  ↓
            LoRa mesh DMs to subscribers
```

## Sessions Completed

### Session 6 ✅ Pi Base Station Provisioning
- Pi 1 B+ flashed, booted, SSH accessible at `festival-pager.local`
- OS updated, kernel 6.18.39 running
- Python venv at `/home/pi/festival-pager/venv/` with Flask 3.1.3 + Meshtastic 2.7.11
- T3S3 confirmed at `/dev/ttyACM0`, pi in dialout group
- Assembly docs at `docs/hardware/pi-assembly.md`

## Session Status

| # | Session | Status |
|---|---------|--------|
| 1 | Data Model + Schedule | models.py written, needs schedule.json + commit |
| 2 | Meshtastic Connection + DM Listener | Not started |
| 3 | DM Command Parser | Not started |
| 4 | Notifier Loop | Not started |
| 5 | Web UI (Captive Portal + Schedule Picker) | Not started |
| 6 | Pi Base Station Provisioning | ✅ Complete |
| 7 | Systemd Service + WiFi Hotspot | ✅ Complete |
| 8 | Festival Prep Checklist | Not started |

## Key Paths

| Resource | Path |
|----------|------|
| Repo | `~/Projects/festival-pager/` (branch `feat/architecture-v2`) |
| Plan | `PLAN.md` |
| Assembly | `docs/hardware/pi-assembly.md` |
| Data model | `models.py` |
| Provision scripts | `provision/` |
| Deploy configs | `deploy/` |
| Setup script | `setup.sh` |

## Session 7 — Files Created

| File | Purpose |
|------|---------|
| `deploy/festival-pager.service` | systemd unit → runs run.sh, depends on hostapd + dnsmasq |
| `deploy/hostapd.conf` | AR9271 open hotspot, SSID 'Festival Pager', GB channel 6 |
| `deploy/dnsmasq.conf` | DHCP 10.0.0.10-100, DNS captive (# → 10.0.0.1) |
| `deploy/wlan0.network` | Static IP 10.0.0.1/24 for wlan0 |
| `deploy/run.sh` | Service wrapper: starts notifier (bg) + web UI (fg), cleanup on exit |
| `setup.sh` | One-shot Pi setup: apt deps, venv, copy configs, enable services, data dir |

## Session 7 — Deploy Plan (Ethernet Required)

**CRITICAL:** `setup.sh` reconfigures wlan0 from WiFi client (station) to AP
mode (hotspot). This kills the current WiFi SSH session at 192.168.1.150.

**Before deploying, plug an Ethernet cable into the Pi's RJ45 port.** The Pi
will get a new IP via DHCP on eth0 — use that IP for SSH during/after deploy.

### Step-by-step (tomorrow)

1. **Boot Pi with Ethernet plugged in** → check router DHCP table for new IP
   (or scan: `nmap -sn 192.168.1.0/24` / `arp -a | grep -i b8:27:eb`)

2. **SSH in via Ethernet:**
   ```bash
   ssh pi@<new-eth-ip>  # or pi@festival-pager.local if mDNS works on eth0
   ```

3. **Clone the repo on the Pi (if not already):**
   ```bash
   cd /home/pi
   git clone https://github.com/booplette/festival-pager.git
   cd festival-pager
   ```

4. **Run setup.sh:**
   ```bash
   chmod +x setup.sh
   sudo ./setup.sh
   ```

5. **Before rebooting — test the hotspot incrementally** (WiFi client stays alive
   until reboot):
   ```bash
   sudo systemctl start hostapd
   sudo systemctl start dnsmasq
   ```
   Connect phone to 'Festival Pager' WiFi → http://10.0.0.1

6. **Reboot:**
   ```bash
   sudo reboot
   ```

7. **After reboot** — SSH via Ethernet IP (or connect to 'Festival Pager' hotspot
   and SSH to 10.0.0.1):
   ```bash
   ssh pi@<eth-ip>
   sudo systemctl status festival-pager
   ```

### Post-deploy access options

| Method | Address | Works? |
|--------|---------|--------|
| Ethernet (eth0) | DHCP from router (check DHCP table) | ✅ Always |
| WiFi hotspot (wlan0 AP) | 10.0.0.1 | ✅ Connect to 'Festival Pager' first |
| WiFi client (wlan0 STA) | 192.168.1.150 | ❌ Killed by setup.sh |
| `festival-pager.local` | mDNS | ⚠️ Only on the network eth0 gets a DHCP lease from |

## Pi Access (Current — WiFi client, will change)
- **SSH:** `pi@festival-pager.local` / `pi@192.168.1.150` — **will stop working after setup.sh reboot**
- **Post-deploy SSH:** via Ethernet DHCP IP, or connect to hotspot → 10.0.0.1
- **Kernel:** 6.18.39+rpt-rpi-v6 (ARMv6)
- **T3S3:** `/dev/ttyACM0`