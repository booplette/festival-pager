# Festival Pager — Product Plan (v2)

> **Architecture switch:** From dedicated wrist-pager to shared mesh notification service.
> Pi Nano base station + T3S3 USB bridge. Users subscribe via DM. Schedule from generic JSON input.

## Architecture

```
Pi Nano (notification service + web UI, inside tent/campervan)
  └─ USB serial ─→ T3S3 (stock Meshtastic firmware, LoRa mesh node)
                      ↓
                 LoRa mesh (EU868)
                 ↙      ↓       ↘
            User A   User B   User C
          (any node) (app)   (any node)

          ↕ Users chat freely on the mesh (unaffected by notification service)
```

### Components

| Component | Role | Details |
|-----------|------|---------|
| **Pi Nano** | Runs notification service + web UI | Python, `meshtastic` library over serial, Flask/FastAPI web interface |
| **T3S3** | Meshtastic mesh node | Stock Meshtastic firmware, USB serial to Pi, all mesh routing done by firmware |
| **User devices** | Any Meshtastic node or phone app | Agnostic — no custom firmware needed |
| **Schedule** | Generic JSON input | `[{act, start, stage, day, ...}]` — one format, any festival |

### Data flow

```
1. Schedule JSON → Pi reads file, builds notification queue
2. Pi watches clock, when act is N minutes away:
   → meshtastic-python → T3S3 serial → LoRa DM to each subscriber
3. User receives DM on their device/app: "ACT: Bob Vylan 15m Main"
4. Users chat freely on primary channel — DMs are invisible to non-subscribers
```

## Tasks

### Phase 1: Core Service

- [x] T1.0: Project scaffold (AGENTS.md, hardware dirs, wiki entry)
- [ ] T1.1: Create generic schedule JSON spec and example file
- [ ] T1.2: Build notifier.py — schedule watcher that DMs subscribers via T3S3 serial
- [ ] T1.3: Subscriber management — DM listener (parse `sub`/`unsub` messages), persist to disk
- [ ] T1.4: Web UI — subscriber list, manual push, schedule preview, status
- [ ] T1.5: Pi setup — configure OS, auto-start service, USB T3S3 serial config

### Phase 2: Schedule Ingestion

- [ ] T2.1: APK extraction — unpack festival app, extract schedule data **← you said you'll get the APK**
- [ ] T2.2: Schedule parser — convert APK/internal format → generic JSON spec
- [ ] T2.3: Web scraper fallback (for festivals without an app)

### Phase 3: Festival Deployment

- [ ] T3.1: Test with real T3S3 + Pi Nano
- [ ] T3.2: Range test — relay node placement strategy
- [ ] T3.3: Deployment checklist
- [ ] T3.4: Battery/uptime test (weekend-long run)

### Phase 4: Polish

- [ ] T4.1: Multi-festival schedule support (switch config)
- [ ] T4.2: Rate limiting / spam protection
- [ ] T4.3: Delivery confirmation (optional)
- [ ] T4.4: Emergency broadcast (override schedule, push urgent message to all)

## Schedule JSON Spec (v1)

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

Subscriber events are a separate list for non-act pushes (meetups, announcements).

## Hardware BOM (v2 — no pagers)

| Item | Qty | Status | Notes |
|------|-----|--------|-------|
| Raspberry Pi Nano | 1 | ✅ Owned | Runs notification service + web UI |
| LillyGo T3S3 | 1 | ✅ Owned | USB serial bridge to LoRa mesh |
| USB-C cable (data) | 1 | ⬜ Need | Connects T3S3 to Pi Nano |
| MicroSD card (32GB+) | 1 | ⬜ Assume | For Pi OS + data |
| Power bank (5V 3A) | 1 | ⬜ Need | Weekend runtime for Pi + T3S3 |
| Relay nodes (optional) | N | ⬜ As needed | LillyGo T-Display etc. for range extension |

**No pagers to buy.** Users bring their own device or use the app. This v2 BOM is just the base station.

## Key Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base station HW | Pi Nano | Already owned, low power, full OS |
| Mesh bridge | T3S3 via USB serial | Already owned, direct serial control, no WiFi dependency |
| Notification delivery | DM to each subscriber | Doesn't pollute primary channel, no secondary channel needed, users chat freely |
| Subscription | DM `sub`/`unsub` to base station | Zero-friction for Meshtastic users, works on any device |
| User hardware | Agnostic | No custom firmware, no dedicated pagers to buy/manage |
| Schedule format | Generic JSON | Single spec, any festival. Parser per festival is separate |
| Subscriber persistence | JSON file on disk | Survives reboot, simple, no DB dependency |
| Schedule source | Festival app APK (later) | T2.1 — extract from APK when user provides it |