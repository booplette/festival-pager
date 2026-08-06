# Festival Pager Implementation Plan

> **For Hermes:** Execute tasks sequentially. Hardware steps require user action.

**Goal:** Build a LoRa mesh notification system for music festivals — a phone at camp pushes act notifications that reach a wrist-worn e-paper pager via LoRa mesh relays.

**Architecture:** Phone (at camp) → WiFi → Heltec Wireless Paper (WiFi+LoRa node at camp edge) → LoRa mesh relays (LillyGo T3S3 nodes) → Heltec Wireless Paper (e-paper pager at festival). Meshtastic firmware on all LoRa nodes. Python script on phone watches a schedule JSON and pushes messages.

**Tech Stack:** Meshtastic firmware, ESP32-S3/SX1262 LoRa devices, Python notification script, JSON schedule data, e-paper display, 3D printed wrist case.

---

## Hardware Shopping List

- [ ] Heltec Wireless Paper HF (EU868) — from Amazon/AliExpress (~£25-35)
- [ ] LiPo battery 3.7V 500mAh with JST-PH connector (or use USB-C powered variant)
- [ ] 3D print wrist case (STL design — see Task 8)

## Existing Hardware

- [x] LillyGo T3S3 (ESP32-S3 + SX1262, 868 MHz) — acts as relay/boost node
- [x] LillyGo T-Display LoRa TFT (ESP32 + SX1276, 868 MHz) — optional relay node (battery limited)

---

### Task 1: Verify Meshtastic Flasher Support

**Objective:** Confirm the Heltec Wireless Paper can be flashed via the Meshtastic web flasher.

**Steps:**
1. Visit https://flasher.meshtastic.org/
2. Select device: look for "Heltec Wireless Paper" in the device dropdown
3. Confirm `heltec-wireless-paper` build variant appears
4. Note the exact firmware build name for reference

**Verification:** Screenshot of the flasher page showing Wireless Paper as a selectable device.

---

### Task 2: Flash Meshtastic onto Heltec Wireless Paper (Pager)

**Objective:** Install Meshtastic firmware on the e-paper display device.

**Files:**
- Device: Heltec Wireless Paper (USB-C connected to computer)

**Steps:**
1. Connect the Wireless Paper to your Mac via USB-C
2. Visit https://flasher.meshtastic.org/
3. Select device: "Heltec Wireless Paper" (or `heltec_wireless_paper` in dropdown)
4. Select region: **EU_868** (critical — matches your T3S3)
5. Click "Flash" and wait for completion (~2-3 minutes)
6. Verify the e-paper display boots and shows the Meshtastic boot screen

**Alternative (if web flasher doesn't list it):**
```bash
# Clone firmware
git clone --depth 1 https://github.com/meshtastic/firmware.git
cd firmware
# Build for Wireless Paper
pio run -e heltec-wireless-paper
# Flash (find USB port first)
ls /dev/cu.usbmodem*  # find the port
pio run -e heltec-wireless-paper -t upload --upload-port /dev/cu.usbmodemXXXX
```

**Verification:** E-paper display shows "Meshtastic" boot logo and node ID.

---

### Task 3: Flash Meshtastic onto LillyGo T3S3 (Relay Node)

**Objective:** Install Meshtastic firmware on your existing T3S3 for mesh relaying.

**Steps:**
1. Connect T3S3 to computer via USB-C
2. Visit https://flasher.meshtastic.org/
3. Select device: look for "LilyGo T3S3" or "LilyGo LoRa T3S3" in dropdown
4. Select region: **EU_868**
5. Flash and wait for completion

**Verification:** TFT display shows Meshtastic boot screen with node ID.

---

### Task 4: Configure LoRa Mesh Settings

**Objective:** Set up both devices for EU868 mesh operation with proper channel and routing.

**Config (apply to both devices via Meshtastic app or web admin):**

```yaml
# LoRa config (both devices)
lora_region: EU_868
lora_spreading_factor: 7   # faster, shorter range (good for festival)
lora_tx_enabled: true
lora_has_msg_propagation: true

# Mesh config
channel: primary
channel_name: festalf
channel_frequency: 868.1   # EU default
channel_privacy: false     # simpler for demo

# WiFi config (camp node only — the Wireless Paper near phone)
wifi_ssid: <your_hotspot_or_venue_wifi>
wifi_password: <password>
wifi_enabled: true         # ONLY on the camp node

# Node identity
owner: camp               # camp node
owner: pager              # wrist pager node
```

**Steps:**
1. Install Meshtastic mobile app (iOS or Android)
2. Connect to each device via BLE
3. Navigate to Config → LoRa → set region to EU_868
4. Navigate to Config → WiFi → enable ONLY on the camp node
5. Set owner names to identify nodes
6. Note each device's 8-character user hash (e.g. `!a1b2c3d4`)

**Verification:** Both devices show the same channel hash on their displays.

---

### Task 5: Test LoRa Mesh Communication

**Objective:** Verify that text messages relay between devices over LoRa.

**Steps:**
1. Take the T3S3 relay node ~50m from the Wireless Paper pager node
2. On the camp node (Wireless Paper with WiFi), use Meshtastic app to send a text message
3. Verify the message appears on the pager's e-paper display
4. Increase distance gradually — test at 100m, 200m, 500m
5. Position the T3S3 relay between them — verify relay extends range

**Verification:** Message displayed on e-paper pager with source node hash.

---

### Task 6: Build the Notification Script

**Objective:** Python script on the phone/laptop that watches a festival schedule and pushes messages to the camp node via Meshtastic HTTP API.

**Files:**
- Create: `festival-pager/notifier.py`
- Create: `festival-pager/schedule.json`

**Step 1: Create schedule.json**

```json
[
  {"act": "Foo Fighters", "start": "20:00", "stage": "Main"},
  {"act": "Arctic Monkeys", "start": "19:15", "stage": "Main"},
  {"act": "Gorillaz", "start": "21:30", "stage": "Main"},
  {"act": "Bicep", "start": "18:00", "stage": "Dance"},
  {"act": "Four Tet", "start": "19:30", "stage": "Dance"}
]
```

**Step 2: Create notifier.py**

```python
#!/usr/bin/env python3
"""Festival act notifier — pushes upcoming acts to Meshtastic pager."""

import json
import time
import urllib.request
from datetime import datetime, timedelta

SCHEDULE_FILE = "schedule.json"
MESHTASTIC_URL = "http://192.168.1.100/api/v1/toradio"  # camp node IP
HEADLINE_MINUTES = 15  # notify X minutes before act starts
CHECK_INTERVAL = 60    # check every N seconds
NOTIFIED = set()       # track acts we've already notified about


def load_schedule():
    """Load festival schedule from JSON."""
    with open(SCHEDULE_FILE) as f:
        return json.load(f)


def build_message(act, start, stage, minutes):
    """Build a concise Meshtastic message (max 57 bytes user payload)."""
    # Meshtastic user text limit is ~57 bytes with headers
    # Be economical: "ACT: Foo Fighters 15m Main"
    msg = f"ACT: {act} {minutes}m {stage}"
    if len(msg) > 57:
        # Truncate act name if needed
        max_name = 57 - len(f"ACT:  {minutes}m {stage}")
        msg = f"ACT: {act[:max_name]}… {minutes}m {stage}"
    return msg


def send_meshtastic_message(text):
    """Send a text message via Meshtastic HTTP API (protobuf).

    Note: The Meshtastic HTTP API uses protobuf encoding.
    For production, use the meshtastic Python library:
      pip install meshtastic
      from meshtastic import mesh_interface
    """
    # Simplified — actual implementation uses protobuf ToRadio message
    # See: meshtastic Python library sendText() method
    print(f"[SEND] {text}")  # TODO: replace with actual HTTP PUT


def main():
    """Main loop — check schedule, notify when acts are upcoming."""
    schedule = load_schedule()

    while True:
        now = datetime.now()
        for act_entry in schedule:
            act = act_entry["act"]
            start_time = datetime.strptime(f"{now.date()} {act_entry['start']}", "%Y-%m-%d %H:%M")
            stage = act_entry.get("stage", "")

            if act in NOTIFIED:
                continue

            delta = start_time - now
            minutes = int(delta.total_seconds() / 60)

            if 0 < minutes <= HEADLINE_MINUTES:
                msg = build_message(act, act_entry["start"], stage, minutes)
                send_meshtastic_message(msg)
                NOTIFIED.add(act)
                print(f"[NOTIFIED] {act} — {msg}")

        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
```

**Step 3: Install meshtastic Python library**

```bash
pip3 install meshtastic  # note: may need workaround for pyobjc on macOS
# Alternative: run the script in a Docker container or Linux VM
```

**Step 4: Replace the placeholder send_meshtastic_message() with actual Meshtastic API**

```python
from meshtastic.interface import Interface as MeshtasticInterface

def send_meshtastic_message(text):
    iface = MeshtasticInterface()
    iface.sendText(text)
    iface.shutdown()
```

**Verification:** Script runs, checks schedule, prints notification messages.

---

### Task 7: Test End-to-End Pipeline

**Objective:** Verify the full pipeline from schedule → script → camp node → mesh relay → pager display.

**Steps:**
1. Set a test act 2 minutes from now in schedule.json
2. Run `python3 notifier.py`
3. Verify the script detects the upcoming act and prints [SEND]
4. Verify the message appears on the pager's e-paper display
5. Verify the T3S3 relay forwards the message (check its display)

**Verification:** Message appears on pager within 30 seconds of script running.

---

### Task 8: Design 3D Printed Wrist Case

**Objective:** Create a wearable case for the Heltec Wireless Paper (72 × 30 × ~8mm).

**Files:**
- Create: `festival-pager/case/` directory
- Create: `festival-pager/case/wireless-paper-wrist.stl`

**Design constraints:**
- Device: 72 × 30 × 8mm (Heltec Wireless Paper with case)
- Battery compartment: 3.7V LiPo 500mAh (~35 × 20 × 5mm)
- USB-C port accessible (for charging)
- Wrist strap attachment points
- 3D print in PLA, ~0.2mm layer height

**Steps:**
1. Model case in Fusion 360 or Onshape (free tiers available)
2. Or use an existing Meshtastic e-paper case design from Thingiverse/Printables and adapt
3. Search: "Heltec Wireless Paper case" or "Meshtastic e-paper case"
4. Export as STL

**Verification:** STL file created, dimensions verified.

---

### Task 9: Print and Assemble

**Objective:** 3D print the case and assemble the wrist pager.

**Steps:**
1. Print case (2 walls, 2 top/bottom layers, 15% infill)
2. Insert LiPo battery with JST-PH connector
3. Install Heltec Wireless Paper
4. Snap case together
5. Attach wrist strap (use existing elastic cord or 3D print loop)

**Verification:** Pager assembled, powers on, display works.

---

### Task 10: Festival Deployment Plan

**Objective:** Document the deployment workflow for festival day.

**Pre-festival (camp):**
1. Flash both devices with latest Meshtastic firmware
2. Configure EU_868 region on both
3. Connect camp node to phone's WiFi hotspot
4. Load festival schedule into schedule.json
5. Run notifier.py on phone/laptop at camp

**Festival setup:**
1. Position camp node (Wireless Paper) at edge of camp → festival boundary
2. Position T3S3 relay node ~200m into festival (within LoRa range of camp node)
3. Wear the wrist pager
4. Test: send a message from camp app, verify pager receives

**Message format convention:**
- `ACT: Foo Fighters 15m Main` — 15 minutes until act on Main stage
- `MEET: Gates 2pm` — meeting point reminder
- `DRINKS: Bar open` — custom notification

**Limitations:**
- Meshtastic user text payload: ~57 bytes
- Message arrives asynchronously (10-30 second delay typical)
- Mesh relay depends on node placement

---

## Decision Log

### Why Meshtastic over LRMesh?
- Heltec Wireless Paper is **officially supported** in Meshtastic (found `heltec_wireless_paper` build variant in firmware repo)
- Massive community, active Discord, pre-built firmware binaries available via web flasher
- Python library (`meshtastic`) available for programmatic message sending
- WiFi HTTP API built into every node for camp-to-phone comms

### Why the Wireless Paper over the TFT T-Display?
- E-paper display: weeks of battery life on a small LiPo
- 5μA deep sleep current vs TFT's constant backlight drain
- Properly suited for "strap and forget" festival use
- The TFT T-Display stays as an optional relay node (power bank at camp)

### EU868 Region
- Both devices confirmed as 868 MHz (EU) — T3S3 and Wireless Paper HF
- Meshtastic EU_868 region preset matches this exactly
- Legal transmit power limits applied automatically by firmware
