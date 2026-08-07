# Festival Pager — Product Plan

> Shared mesh notification service. Pi 1 B+ base station + T3S3 USB bridge.
> Users subscribe to specific acts via web UI. Notifications delivered as Meshtastic DMs.
> Users can still chat freely on the mesh — the base station only sends DMs.

## Architecture

```
Pi 1 B+ (inside tent)
  ├── USB-A ▸ AR9271 WiFi — WiFi hotspot + captive portal
  └── USB-A ▸ T3S3 (stock Meshtastic firmware, LoRa mesh node)
                      ↓
                 LoRa mesh (EU868)
                 ↙      ↓       ↘
            User A   User B   User C
          (any node) (app)   (any node)

Users chat freely on the mesh. Base station only sends DMs.
```

## Building Blocks

```ascii
                      notifier.py (main loop)
                     /        |          \
              listener.py  webui.py    models.py
              (DM parser)  (Flask UI)  (data + persistence)
                     \        |          /
                      ─── T3S3 serial ───
```

## Sessions

Each session is a self-contained slice. Do them in order — each builds on the
previous — but any session can be resumed without re-reading the whole plan.
Every session produces a working artifact that can be tested before moving on.

---

### Session 1: Data Model + Schedule Ingestion

**Goal:** Define the data structures and get a schedule loaded.

**What you'll have at the end:** `models.py` that loads/saves schedule JSON,
and a `schedule.json` file with example event data.

**Files touched:**
- `models.py` — Schedule, Event, Subscriber, Pin data classes
- `schedule.json` — Example festival schedule (Shambala 2026 acts)

**Test:**
```python
from models import Schedule
sched = Schedule.load("schedule.json")
assert len(sched.events) > 0
print(sched.next_events(n=3))  # next 3 acts
```

**Schema:**

```json
{
  "festival": "Shambala 2026",
  "dates": ["2026-08-27", "2026-08-28", "2026-08-29", "2026-08-30"],
  "timezone": "Europe/London",
  "events": [
    {
      "act": "Bob Vylan",
      "day": "2026-08-27",
      "start": "20:00",
      "end": "21:00",
      "stage": "Main",
      "type": "music"
    }
  ]
}
```

**Subscriber data model** (persisted to `subscribers.json`):

```python
@dataclass
class Subscriber:
    node_id: str          # "!a1b2c3d4"
    active: bool          # True = receiving DMs
    events: list[str]     # ["Bob Vylan", "BCUC"]
    stages: list[str]     # ["Main"] — subscribe to all acts on a stage
    created: str          # ISO timestamp
    last_seen: str        # ISO timestamp
```

**PIN data model** (ephemeral, persisted to `pins.json`, auto-expire after 5 min):

```python
@dataclass
class Pin:
    code: str            # "731294"
    session_id: str      # browser session
    created: float       # time.time()
    claimed_by: str      # node ID, once DM received
```

**Challenge data model** (ephemeral, in-memory + `challenges.json`, expire 5 min):

```python
@dataclass
class Challenge:
    id: str              # short id for polling
    node_id: str         # claimed node ID "!a1b2c3d4"
    code: str            # "GOAT42" — Shambala-themed word + digits, easy to read on e-ink
    created: float       # time.time()
    verified: bool       # True once DM received or code entered on web UI
    session_id: str      # browser session that initiated it
```

**Why this slice first:** Everything else depends on the data model. Getting this
right early means the other slices just import and use it.

---

### Session 2: Meshtastic Connection + DM Listener

**Goal:** Talk to the T3S3 over USB serial. Send and receive DMs.

**What you'll have at the end:** `listener.py` that connects to the T3S3,
listens for incoming DMs, and can send DMs.

**Files touched:**
- `listener.py` — Meshtastic serial connection, send/receive
- `config.json` — Serial port, node settings

**Test (requires T3S3 connected via USB):**
```python
from listener import MeshListener
m = MeshListener(port="/dev/ttyACM0")
m.send_dm("!test-node-id", "Hello from base station!")

# Incoming messages via callback:
@m.on_message
def handle(msg):
    print(f"{msg.from_id}: {msg.text}")
```

**DM API:**

```python
class MeshListener:
    def send_dm(self, node_id: str, text: str) -> bool
    # Callback registration:
    def on_message(self, callback: Callable[[MeshtasticMessage], None])
    def on_node_seen(self, callback: Callable[[str], None])
```

**MeshtasticMessage fields:**
```python
@dataclass
class MeshtasticMessage:
    from_id: str     # "!a1b2c3d4"
    text: str        # Message body
    channel: int     # 0 = primary
    rx_snr: float    # Signal quality
    rx_time: float   # Timestamp
```

**Why this slice second:** The DM listener is the only way users interact with
the system without WiFi. Must be solid before anything else.

---

### Session 3: DM Command Parser

**Goal:** Parse incoming DMs and execute subscription commands.

**What you'll have at the end:** A command handler that processes `sub XXXXXX`,
`unsub`, `list` DMs and updates the subscriber database.

**Files touched:**
- `listener.py` — Add command routing
- `models.py` — Add subscribe/unsubscribe/list methods

**DM commands:**

| DM | Effect | Reply DM |
|----|--------|----------|
| `sub XXXXXX` | Bind node to PIN + activate | ✅ Subscribed! Set your preferences at http://10.0.0.1 |
| `verify XXXXXX` | Confirm node ownership (challenge-response) | ✅ Verified! Set your preferences at http://10.0.0.1 |
| `unsub` | `active=false`, keep prefs | ✅ Unsubscribed. Send `sub` anytime to re-activate. |
| `list` | Next 3 acts as DM | 📋 Next: Bob Vylan 20:00 Main, Goat 21:30 Main, BCUC 19:00 Dance |

**PIN flow (standard — user has keyboard):**
```
User connects to WiFi hotspot (10.0.0.1)
  → Captive portal shows PIN "731294"
  → User DMs "sub 731294"
  → Server matches PIN to session
  → Binds browser session ↔ node ID
  → PIN consumed, subscriber created/activated
  → Reply DM: ✅ Subscribed! Open http://10.0.0.1 to pick your acts
```

**Challenge-response flow (no keyboard — e-ink / Wireless Paper users):**
```
User connects to WiFi hotspot (10.0.0.1)
  → Captive portal offers "No keyboard? Enter your node ID"
  → User types their node ID from their device screen (e.g. "!a1b2c3d4")
  → Server sends DM to that node: "Your code: GOAT42 — reply: verify GOAT42"
  → User reads DM on e-ink screen, types code "GOAT42" on web UI
  → Server verifies: DM sent to that node + code matches → binds session
  → OR user reads code and DMs "verify GOAT42" from their device instead
  → Subscriber created/activated, redirected to /schedule
```

The server generates a short memorable word code (e.g. `GOAT42`, `BEAN23`, `BASS19`)
so it's easy to read from a small e-ink screen. The code expires in 5 minutes.
The user can either:
  (a) Type the code on the web UI (if the page is still open)
  (b) DM `verify GOAT42` from their device (if they can send one message)

**Whimsical Shambala-themed word list** (code picks a word + appends 2 random digits):

```
GOAT    BEAN    BASS    BIRD    BUG
BUZZ    CHARM   CHIME   CLOUD   DANCE
DEER    DREAM   DRUM    DUNE    FAWN
FERN    FIELD   FIRE    FLOOD   FLUTE
FOG     FOX     FROG    GLADE   GLOW
GNOME   GONG    GROVE    HARE    HUMM
LEAF    LUCK    MAGIC   MOSS    MOTH
MYTH    OWL     PEACE   POND    RAVE
RUNE    SOUL    SPARK   STAR    SUN
SWIRL   TREE    VIBE    WILD    WISP
WYRD    YEW
```

Short words (3–6 chars), easy to read on small e-paper screens, no ambiguity
between similar letters. Combined with 2 random digits (e.g. `GOAT42`, `FROG07`,
`WISP83`) for 1M+ unique combinations — no collisions at festival scale.

**Test:**
```python
from listener import CommandHandler
handler = CommandHandler(subscribers_file="test_subs.json")

# Simulate receiving DMs
handler.handle("!a1b2c3d4", "sub 123456")  # → bound to session
handler.handle("!a1b2c3d4", "list")         # → reply with next acts
handler.handle("!a1b2c3d4", "unsub")        # → deactivated, prefs kept
```

---

### Session 4: Notifier Loop — Schedule Watcher

**Goal:** The core loop that watches the clock and sends notifications.

**What you'll have at the end:** `notifier.py` that loads the schedule, watches
the clock, and sends DMs to subscribers when acts are upcoming.

**Files touched:**
- `notifier.py` — Main loop
- `notified.json` — Persisted set of already-sent notifications

**Loop logic:**

```python
while True:
    now = datetime.now()
    for event in schedule.events:
        if event in notified:
            continue
        delta = event.start_time - now
        if 0 < delta.total_seconds() <= LEAD_TIME * 60:
            for sub in subscribers.active():
                if sub.wants(event):
                    mesh.send_dm(sub.node_id, format_msg(event))
            notified.add(event.id)
    time.sleep(CHECK_INTERVAL)
```

**DM message format (max 57 bytes):**

```
ACT: Bob Vylan 15m Main     (27 chars)
ACT: Goat 30m Dance         (22 chars)
MEET: Gates 2pm             (15 chars)
```

If act name is too long, truncate:
```
ACT: The Closing Ceremony… 15m Main  (41 chars — fits)
```

**Config (`config.json`):**
```json
{
  "lead_time_minutes": 15,
  "check_interval_seconds": 30,
  "serial_port": "/dev/ttyACM0"
}
```

**Test (no hardware needed — mock MeshListener):**
```python
from notifier import Notifier
from unittest.mock import MagicMock

mesh = MagicMock()
n = Notifier(schedule="schedule.json", mesh=mesh)
n.tick()  # Manually trigger one check
# Assert mesh.send_dm was called with correct messages
```

---

### Session 5: Web UI — Captive Portal + Schedule Picker

**Goal:** The web interface users see when they connect to the Pi's WiFi hotspot.

**What you'll have at the end:** A Flask web app serving:
- `/` — Captive portal showing PIN, waiting for DM binding
- `/schedule` — Full schedule with checkboxes per act
- `/dashboard` — System status overview
- `/subscribers` — Subscriber list with preferences
- `/send` — Manual push form

**Files touched:**
- `webui.py` — Flask app
- `templates/` — HTML templates (inline or files)
- `static/` — CSS

**Route design:**

```
GET  /                    Captive portal — shows PIN + "no keyboard" option
GET  /api/pin             Generate + return new PIN (JSON)
GET  /api/pin/status      Check if PIN claimed (JSON)
POST /api/challenge       Initiate challenge-response (body: node_id)
GET  /api/challenge/:id   Check if challenge verified (JSON)
POST /api/verify          Submit challenge code from web UI (body: code)
GET  /schedule            Full schedule with checkboxes (requires session)
POST /schedule            Save preferences
GET  /dashboard           Sub count, next acts, recent sends
GET  /subscribers         List with edit/remove
POST /subscribers         Add subscriber manually
GET  /send                Manual push form
POST /send                Execute manual push
GET  /status              System health
```

**Captive portal page (`/`):**

```html
<h1>🎪 Festival Pager</h1>

<!-- Path A: standard PIN auth -->
<div id="pin-auth">
  <h2>Have a keyboard on your Meshtastic device?</h2>
  <p>Your PIN: <strong>731294</strong></p>
  <p>Send a DM from your device: <code>sub 731294</code></p>
  <div id="status">⏳ Waiting for DM...</div>
</div>

<hr>

<!-- Path B: no-keyboard challenge-response -->
<div id="nokb-auth">
  <h2>No keyboard? No problem.</h2>
  <p>Enter your Meshtastic node ID (shown on your device screen):</p>
  <input type="text" id="node-id" placeholder="!a1b2c3d4">
  <button onclick="startChallenge()">Verify</button>
  <div id="challenge-status"></div>
</div>

<script>
  // Path A: poll /api/pin/status every 2s
  // On claim: redirect to /schedule

  // Path B: challenge-response
  function startChallenge() {
    fetch("/api/challenge", {method: "POST", body: JSON.stringify({node_id: document.getElementById("node-id").value})})
      .then(r => r.json())
      .then(data => {
        document.getElementById("challenge-status").innerText =
          "📡 DM sent to your device. Reply: verify " + data.code;
        // Poll for verification
        const interval = setInterval(() => {
          fetch("/api/challenge/" + data.id)
            .then(r => r.json())
            .then(d => { if (d.verified) { clearInterval(interval); window.location = "/schedule"; } });
        }, 2000);
      });
  }
</script>
```

**Schedule page (`/schedule`):**

```html
<h2>Pick your acts (!a1b2c3d4)</h2>
<form method="POST">
  <h3>Thursday 27th</h3>
  <label><input type="checkbox" name="events" value="Bob Vylan"> 20:00 Bob Vylan (Main)</label>
  <label><input type="checkbox" name="events" value="Goat"> 21:30 Goat (Main)</label>
  ...
  <button>Save</button>
</form>
```

**How captive portal + DNS works:**
- Pi runs dnsmasq + hostapd (or similar)
- DHCP gives IPs on 10.0.0.0/24
- All DNS resolves to 10.0.0.1
- HTTP on port 80 serves the captive portal
- On claim: browser redirects to /schedule

**For development/testing:** The web UI works without WiFi setup — just
`flask run --host=0.0.0.0 --port=8080` and hit it from any browser.

---

### Session 6: Pi Base Station Provisioning

**Goal:** Turn a Raspberry Pi 1 B+ into a ready base-station host — OS
flashed, headless SSH access, hardware assembled, Python deps installed, and a
verified serial link to the T3S3 Meshtastic node.

**Why this slice before Session 7:** Session 7 (systemd + hotspot) and the Web UI
deployment assume a running, reachable Pi with the serial bridge wired up.
Provisioning first means Session 7 is just "install the service files," not
"also hope the OS boots."

**What you'll have at the end:**
- Bootable Raspberry Pi OS Lite SD card with headless SSH enabled
- Pi 1 B+ with AR9271 WiFi dongle and T3S3 plugged into USB ports
- Python venv with `meshtastic` + `flask` installed
- Confirmed `/dev/ttyACM0` link to the T3S3 returning node info

**Files touched:**
- `docs/hardware/pi-assembly.md` — physical build + port map

**Steps:**
1. ✅ OS flashed — Raspberry Pi OS Lite (Bullseye armhf) on SD card, booted.
2. ✅ Headless SSH — `pi` user with known password, `festival-pager` hostname.
3. Run `sudo apt update && sudo apt full-upgrade -y` (fresh flash, needs updates).
4. Plug T3S3 into USB port, confirm `/dev/ttyACM0` appears. `pi` already in `dialout` group.
5. `sudo apt install python3-pip -y`, create venv `/home/pi/festival-pager/venv`, `pip install meshtastic flask`.
6. Document hardware: Pi 1 B+ → USB ports → AR9271 (wlan0) + T3S3 (ttyACM0). Write `docs/hardware/pi-assembly.md`.
7. Verify: `meshtastic --port /dev/ttyACM0 --info` returns node info (EU868 + working serial bridge).

**Test:**
```bash
ssh pi@festival-pager
ls -l /dev/ttyACM0            # should exist with T3S3 plugged in
/home/pi/festival-pager/venv/bin/python -c "import meshtastic, flask; print('deps ok')"
meshtastic --port /dev/ttyACM0 --info | grep -i "firmware\|region"
```

**Handoff to Session 7:** Pi is reachable over SSH, deps present, T3S3 on
`ttyACM0`. Session 7 adds the systemd unit + hotspot so it auto-runs headless
at the festival.

---

### Session 7: Systemd Service + WiFi Hotspot

**Goal:** Everything runs as a single systemd service, auto-starts on boot,
WiFi hotspot is configured.

**What you'll have at the end:** The Pi 1 B+ boots into hotspot mode, the
notification service starts automatically, and the system is "deployable"
for a festival.

**Files touched:**
- `/etc/systemd/system/festival-pager.service`
- `/etc/hostapd/hostapd.conf` — AR9271 on wlan0
- `/etc/dnsmasq.conf`
- `/etc/network/interfaces.d/wlan0` — static IP for hotspot
- `setup.sh` — One-shot setup script

**Hardware setup:**
```
Pi 1 B+
  ├── USB-A ▸ AR9271 WiFi dongle (hotspot, captive portal)
  └── USB-A ▸ T3S3 (Meshtastic serial bridge, /dev/ttyACM0)
```

**Setup script (`setup.sh`):**
```bash
#!/bin/bash
# One-time setup for Pi 1 B+ festival-pager base station

# (deps already installed in venv during Session 6 provisioning)

# Copy service file
sudo cp festival-pager.service /etc/systemd/system/
sudo systemctl enable festival-pager
sudo systemctl start festival-pager

# Configure hotspot
sudo cp hostapd.conf /etc/hostapd/
sudo cp dnsmasq.conf /etc/dnsmasq.d/
sudo systemctl enable hostapd dnsmasq
```

**Persistence note:** `subscribers.json` and `notified.json` live in
`/home/pi/festival-pager/data/` — survive reboots. `pins.json` is ephemeral,
auto-cleaned.

---

### Session 8: Festival Prep Checklist

**Goal:** A document to run through before deploying to a festival.

**Files touched:**
- `docs/festival-prep.md`

**Checklist:**
- [ ] Flash T3S3 with stock Meshtastic firmware (EU868)
- [ ] Configure T3S3: region EU868, no WiFi (serial only)
- [ ] Verify Pi provisioned (Session 6): SSH in, venv + deps present, `ttyACM0` link to T3S3 confirmed
- [ ] Run `setup.sh` on Pi (installs service + hotspot — deps already in venv)
- [ ] Copy `schedule.json` to Pi
- [ ] Test: connect phone to Pi hotspot, DM `sub PIN`, pick acts, verify DM arrives
- [ ] Test: no-keyboard path — enter node ID, verify challenge DM received, confirm code
- [ ] Power test: run on battery for 4+ hours
- [ ] Pack: Pi 1 B+ + case, AR9271 dongle, T3S3, Ethernet cable, USB cables, power supply
- [ ] Pack: spare relay nodes (if extending range)

---

### Future / Stretch

- **APK schedule extraction** (T2.1) — user will provide the festival app APK
- **Multiple festival profiles** — swap `schedule.json` + `config.json` per festival
- **Delivery confirmation** — track which DMs were acknowledged
- **Rate limiting** — prevent notification spam from overwhelming the mesh
- **Emergency broadcast** — push to all subscribers regardless of preferences

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base station HW | Pi 1 B+ + AR9271 WiFi dongle | Owned, ARMv6, 4x USB ports for WiFi + T3S3 |
| Mesh bridge | T3S3 via USB serial | Owned, serial control, no WiFi dependency |
| Notification delivery | DM per subscriber | Doesn't pollute primary channel, users chat freely |
| Subscription | Web UI (PIN-bound) | No typing hex node IDs, works on any phone browser |
| Auth (keyboard) | PIN shown on captive portal, DM `sub PIN` | Short code sent via DM binds device to session |
| Auth (no keyboard) | Challenge-response: enter node ID → server DMs code → user replies | Proves ownership without typing on the device itself |
| `unsub` | Deactivates, keeps prefs | Easy to come back |
| User hardware | Agnostic | No custom firmware needed |
| Schedule format | Generic JSON | One format, any festival |
| Subscriber persistence | JSON on disk | Simple, no DB |
| WiFi mode | Pi hotspot + captive portal | No external WiFi dependency |
| PIN expiry | 5 minutes | Balances security with usability |

## Hardware BOM

| Item | Qty | Status | Notes |
|------|-----|--------|-------|
| Raspberry Pi 1 B+ | 1 | ✅ Owned | ARMv6, 4x USB ports, runs notification service + web UI + hotspot |
| USB WiFi dongle (Atheros AR9271) | 1 | ✅ Owned | WiFi hotspot + captive portal, in-kernel ath9k_htc driver |
| LillyGo T3S3 | 1 | ✅ Owned | USB serial bridge to LoRa mesh |
| MicroSD card (8GB+) | 1 | ✅ Have | For Pi OS + data |
| Power supply (5V 2A, microUSB) | 1 | ⬜ Need | For the Pi 1 B+ |
| Ethernet cable | 1 | ⬜ Need | Handy for initial setup/troubleshooting |
| Relay nodes | N | ⬜ As needed | Range extension |