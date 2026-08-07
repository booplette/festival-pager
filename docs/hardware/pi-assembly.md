# Pi 1 B+ Base Station Assembly

**Board:** Raspberry Pi 1 Model B+ Rev 1.2 (BCM2835 ARMv6)
**Hostname:** `festival-pager`
**OS:** Raspberry Pi OS Lite (Bullseye armhf)

## Port Map

```
Pi 1 B+
   │
   ├── USB port 1 ──→ Atheros AR9271 WiFi dongle (wlan0)
   ├── USB port 2 ──→ LillyGo T3S3 (Meshtastic serial bridge, /dev/ttyACM0)
   ├── USB port 3   (spare)
   ├── USB port 4   (spare)
   ├── Ethernet     (debug/backhaul — connected during setup)
   └── microUSB     (5V 2A power input)
```

## Assembly Steps

1. Plug AR9271 WiFi dongle into USB port 1.
2. Connect T3S3 to USB port 2 via USB-C to USB-A cable.
3. Connect Ethernet cable for initial SSH access (optional — WiFi on 69nicer also works).
4. Apply 5V 2A power via microUSB port.

## Software Stack

| Component | Location |
|-----------|----------|
| Project code | `/home/pi/festival-pager/` |
| Python venv | `/home/pi/festival-pager/venv/` |
| Schedule data | `/home/pi/festival-pager/schedule.json` |
| Subscriber DB | `/home/pi/festival-pager/subscribers.json` |
| Notification log | `/home/pi/festival-pager/notified.json` |

## Connectivity

- **SSH:** `pi@festival-pager.local` or `pi@192.168.1.150` (password: festival-pager)
- **WiFi hotspot:** SSID `Festival Pager`, captive portal at `10.0.0.1` (configured in Session 7)
- **Mesh serial:** `/dev/ttyACM0` → T3S3 running stock Meshtastic firmware (EU868)
- **Ethernet:** DHCP on LAN (for setup/debug only)

## Notes

- The AR9271 uses the in-kernel `ath9k_htc` driver — no proprietary firmware needed.
- On Bullseye armhf, ensure `firmware-atheros` is installed for the AR9271.
- T3S3 appears as `/dev/ttyACM0` (CDC ACM serial). If it shows as `/dev/ttyUSB0` instead, check if `brltty` is interfering.