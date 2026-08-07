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
| 7 | Systemd Service + WiFi Hotspot | Not started |
| 8 | Festival Prep Checklist | Not started |

## Key Paths

| Resource | Path |
|----------|------|
| Repo | `~/Projects/festival-pager/` (branch `feat/architecture-v2`) |
| Plan | `PLAN.md` |
| Assembly | `docs/hardware/pi-assembly.md` |
| Data model | `models.py` |
| Provision scripts | `provision/` |

## Pi Access
- **SSH:** `pi@festival-pager.local` / `pi@192.168.1.150` (password: festival-pager)
- **Kernel:** 6.18.39+rpt-rpi-v6 (ARMv6)
- **T3S3:** `/dev/ttyACM0`

## Commands to Continue (Next: Session 7)
```bash
# On the Pi:
ssh pi@festival-pager.local

# Create systemd service + hostapd hotspot config
# See PLAN.md Session 7 for details
```