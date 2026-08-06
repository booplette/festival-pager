# Festival Pager 🎪📡

LoRa mesh notification system for music festivals.

**Phone at camp → LoRa mesh relays → wrist-worn e-paper pager**

A Python script watches a festival schedule and pushes act-start notifications
via Meshtastic LoRa mesh to a Heltec Wireless Paper e-paper pager you wear.

## Hardware

| Device | Role | Protocol |
|--------|------|----------|
| Heltec Wireless Paper (HF/EU868) | Camp node + wrist pager | ESP32-S3 + SX1262, LoRa mesh |
| LillyGo T3S3 | Relay/boost node | ESP32-S3 + SX1262, LoRa mesh |
| LillyGo T-Display LoRa | Optional relay (battery limited) | ESP32 + SX1276, LoRa mesh |

## Architecture

```
Phone (at camp, WiFi)
  → notifier.py watches schedule.json
  → HTTP API → Heltec Wireless Paper (camp node)
    → LoRa mesh (EU868) → LillyGo T3S3 relay (~200m in)
      → LoRa mesh → Heltec Wireless Paper (wrist pager)
```

## See Also

- [PLAN.md](PLAN.md) — Full implementation plan (10 tasks)
- [STATUS.md](STATUS.md) — Current project state

## Stack

- **Meshtastic** firmware on all LoRa nodes (EU868 region)
- **Python** notification script with Meshtastic HTTP API
- **JSON** schedule data (scraped from festival websites)
- **E-paper** display (250×122px, weeks of battery)
