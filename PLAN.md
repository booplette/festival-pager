# Festival Pager — Product Plan

> Shared mesh notification service. Pi Nano base station + T3S3 USB bridge.
> Users subscribe to specific acts via web UI. Notifications delivered as Meshtastic DMs.
> Users can still chat freely on the mesh — the base station only sends DMs.

## Architecture

```
Pi Nano (inside tent, on WiFi hotspot)
  └─ USB serial ─→ T3S3 (stock Meshtastic firmware, LoRa mesh node)
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
| `unsub` | `active=false`, keep prefs | ✅ Unsubscribed. Send `sub` anytime to re-activate. |
| `list` | Next 3 acts as DM | 📋 Next: Bob Vylan 20:00 Main, Goat 21:30 Main, BCUC 19:00 Dance |

**PIN flow:**
```
User connects to WiFi hotspot (10.0.0.1)
  → Captive portal shows PIN "731294"
  → User DMs "sub 731294"
  → Server matches PIN to session
  → Binds browser session ↔ node ID
  → PIN consumed, subscriber created/activated
  → Reply DM: ✅ Subscribed! Open http://10.0.0.1 to pick your acts
```

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
GET  /               → Captive portal (shows PIN, polls for claim)
GET  /schedule       → Schedule with checkboxes (requires node_id in session)
POST /schedule       → Save preferences
GET  /dashboard      → Sub count, next acts, recent sends
GET  /subscribers    → List of subscribers with edit/remove
POST /subscribers    → Add subscriber manually
GET  /send           → Manual push form
POST /send           → Execute manual push
GET  /status         → System health
GET  /api/pin        → Generate + return new PIN (JSON)
GET  /api/pin/status → Check if PIN claimed (JSON)
```

**Captive portal page (`/`):**

```html
<h1>🎪 Festival Pager</h1>
<p>Your PIN: <strong>731294</strong></p>
<p>Send a DM from Meshtastic: <code>sub 731294</code></p>
<div id="status">⏳ Waiting...</div>
<script>
  // Poll /api/pin/status every 2s
  // On claim: redirect to /schedule
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

### Session 6: Systemd Service + WiFi Hotspot

**Goal:** Everything runs as a single systemd service, auto-starts on boot,
WiFi hotspot is configured.

**What you'll have at the end:** The Pi Nano boots into hotspot mode, the
notification service starts automatically, and the system is "deployable"
for a festival.

**Files touched:**
- `/etc/systemd/system/festival-pager.service`
- `/etc/hostapd/hostapd.conf`
- `/etc/dnsmasq.conf`
- `setup.sh` — One-shot setup script

**Setup script (`setup.sh`):**
```bash
#!/bin/bash
# One-time setup for Pi Nano festival-pager base station

# Install deps
pip install meshtastic flask

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

### Session 7: Festival Prep Checklist

**Goal:** A document to run through before deploying to a festival.

**Files touched:**
- `docs/festival-prep.md`

**Checklist:**
- [ ] Flash T3S3 with stock Meshtastic firmware (EU868)
- [ ] Configure T3S3: region EU868, no WiFi (serial only)
- [ ] Flash SD card with Raspberry Pi OS Lite
- [ ] Run `setup.sh` on Pi
- [ ] Copy `schedule.json` to Pi
- [ ] Test: connect phone to Pi hotspot, DM `sub PIN`, pick acts, verify DM arrives
- [ ] Power test: run on battery for 4+ hours
- [ ] Pack: Pi Nano + case, T3S3, USB cable, power bank
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
| Base station HW | Pi Nano | Owned, low power, full OS |
| Mesh bridge | T3S3 via USB serial | Owned, serial control, no WiFi dependency |
| Notification delivery | DM per subscriber | Doesn't pollute primary channel, users chat freely |
| Subscription | Web UI (PIN-bound) | No typing hex node IDs, works on any phone browser |
| Auth | PIN shown on captive portal | Short code sent via DM binds device to session |
| `unsub` | Deactivates, keeps prefs | Easy to come back |
| User hardware | Agnostic | No custom firmware needed |
| Schedule format | Generic JSON | One format, any festival |
| Subscriber persistence | JSON on disk | Simple, no DB |
| WiFi mode | Pi hotspot + captive portal | No external WiFi dependency |
| PIN expiry | 5 minutes | Balances security with usability |

## Hardware BOM

| Item | Qty | Status | Notes |
|------|-----|--------|-------|
| Raspberry Pi Nano | 1 | ✅ Owned | Runs notification service + web UI + hotspot |
| LillyGo T3S3 | 1 | ✅ Owned | USB serial bridge to LoRa mesh |
| USB-C cable (data) | 1 | ⬜ Need | Connects T3S3 to Pi Nano |
| MicroSD card (32GB+) | 1 | ⬜ Assume | For Pi OS + data |
| Power bank (5V 3A) | 1 | ⬜ Need | Weekend runtime |
| Relay nodes | N | ⬜ As needed | Range extension |