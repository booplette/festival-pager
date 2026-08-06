# AGENTS.md — festival-pager

**Auto-loaded when working in this directory.** Follow strictly.

## Project Identity

- **Project:** festival-pager
- **Path:** `~/Projects/festival-pager`
- **GitHub:** https://github.com/booplette/festival-pager
- **Deploy target:** Local/festival — not deployed to VPS
- **Test command:** N/A (no tests yet — hardware project)

## Project-Specific Rules

- **Hardware-first.** This project involves physical LoRa devices (Heltec Wireless Paper, LillyGo T3S3). Always verify device connectivity, region settings (EU868), and battery state before testing.
- **Meshtastic firmware.** All LoRa nodes run Meshtastic firmware. Use the web flasher (https://flasher.meshtastic.org/) — do not build firmware locally unless the web flasher doesn't support the device.
- **EU868 region.** ALL devices must be configured for EU_868 region. Transmitting on wrong frequencies is illegal.
- **notifier.py is placeholder.** The `send_meshtastic_message()` function is a stub. Before running: install `meshtastic` Python library or implement the HTTP API properly.
- **57-byte limit.** Meshtastic user text payload is ~57 bytes. Keep messages concise. Truncate act names when needed.
- **No VPS deploy.** This project runs locally on a phone/laptop at festival camp. No rsync, no systemd.
- **BOM in docs/hardware/.** Track component purchases in a BOM table.

## Safety Rules (from ~/Projects/AGENTS.md)

1. No destructive ops without backup + dry-run + two approvals.
2. TDD + Gherkin before any code change.
3. Feature branch → PR → CI → merge. Never commit to main.
4. Deploy: clean status → tests pass → dry-run → approve → deploy → smoke test (N/A — no VPS).
5. No secrets in git.

## See Also

- `safe-operation-governor` skill — full enforcement rules
- `PLAN.md` — implementation plan (10 tasks)
- `STATUS.md` — current project state
- `docs/hardware/` — BOM and component docs
- `case/` — 3D printed case designs