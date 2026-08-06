# STATUS.md — Festival Pager

## Overview
LoRa mesh notification system for music festivals. Phone at camp pushes act-start notifications to a wrist-worn e-paper pager via Meshtastic LoRa mesh relays.

## URLs
- Meshtastic flasher: https://flasher.meshtastic.org/
- Meshtastic docs: https://meshtastic.org/docs/
- Meshtastic firmware repo: https://github.com/meshtastic/firmware
- Heltec Wireless Paper manual: (PDF attached in chat)

## Architecture
- **Camp node:** Heltec Wireless Paper (ESP32-S3 + SX1262, EU868) — WiFi enabled, connects to phone's hotspot, receives HTTP API messages
- **Relay node(s):** LillyGo T3S3 (ESP32-S3 + SX1262, EU868) — LoRa mesh relay, extends range into festival
- **Pager:** Heltec Wireless Paper (ESP32-S3 + SX1262, EU868) — e-paper display, wrist-worn, LiPo powered
- **Phone:** Runs `notifier.py` script, watches `schedule.json`, pushes messages via Meshtastic HTTP API to camp node
- **Protocol:** Meshtastic LoRa mesh (EU868), protobuf messages, mesh routing automatic

## File Structure
```
festival-pager/
  PLAN.md          # Implementation plan (10 tasks)
  STATUS.md        # This file
  notifier.py      # Python notification script (to be created)
  schedule.json    # Festival schedule data (to be created)
  case/            # 3D printed case designs (STL files)
```

## Hardware State
- **LillyGo T3S3:** Owned, current firmware unknown, to be flashed with Meshtastic
- **LillyGo T-Display LoRa TFT:** Owned, current firmware unknown, optional relay (battery limited)
- **Heltec Wireless Paper HF:** Not yet purchased (~£25-35 on Amazon/AliExpress)
- **LiPo battery:** Not yet purchased (3.7V 500mAh, JST-PH connector)
- **3D printed case:** Not yet designed

## Deploy Workflow
1. Flash all devices with Meshtastic (EU868 region) via web flasher
2. Configure channels and WiFi on camp node via Meshtastic app
3. Run `notifier.py` on phone/laptop at camp (connects to camp node via WiFi)
4. Position relay nodes at strategic festival locations
5. Pager receives messages automatically via LoRa mesh

## Outstanding Items
- [ ] Purchase Heltec Wireless Paper HF (EU868)
- [ ] Purchase LiPo battery 3.7V 500mAh
- [ ] Flash Meshtastic onto Wireless Paper (pager node)
- [ ] Flash Meshtastic onto T3S3 (relay node)
- [ ] Test mesh communication between devices
- [ ] Write and test notifier.py with real Meshtastic HTTP API
- [ ] Get festival schedule data (JSON format)
- [ ] Design and 3D print wrist case
- [ ] Assemble and test end-to-end at a local event

## Gotchas
- Meshtastic user text payload limited to ~57 bytes — act names must be truncated
- Message delivery is asynchronous (10-30 second delay typical)
- The python-meshtastic library has macOS dependency issues (pyobjc) — may need Docker/venv workaround
- Both devices must be on the SAME Meshtastic channel (channel hash must match)
- EU868 region must be set on ALL devices (firmware flash time)
- The camp node needs WiFi; the pager runs LoRa-only (WiFi disabled)

## Commands to Continue Development
```bash
cd ~/festival-pager

# Write the notifier script
# (requires meshtastic library — install with: pip3 install meshtastic)
# Note: macOS may need --no-deps workaround for pyobjc

# Flash devices (use web flasher instead of CLI)
open "https://flasher.meshtastic.org/"

# Test after flashing
meshtastic scan  # list nearby nodes
meshtastic send "test"  # send a test message
```
