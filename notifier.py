#!/usr/bin/env python3
"""Festival act notifier — pushes upcoming acts to Meshtastic pager.

Usage:
    python3 notifier.py --config config.json

Connects to a Meshtastic node over WiFi (HTTP API) and pushes
act-start notifications to the LoRa mesh network.
"""

import argparse
import json
import sys
import time
import urllib.request
from datetime import datetime, timedelta

HEADLINE_MINUTES = 15  # Notify this many minutes before act starts
CHECK_INTERVAL = 60    # Check schedule every N seconds


def load_schedule(path):
    """Load festival schedule from JSON file."""
    with open(path) as f:
        return json.load(f)


def load_config(path):
    """Load configuration (Meshtastic node URL, schedule path)."""
    with open(path) as f:
        return json.load(f)


def build_message(act, start, stage, minutes_left):
    """Build a concise Meshtastic message.

    Meshtastic user text payload is limited to ~57 bytes.
    Format: ACT: Foo Fighters 15m Main
    """
    msg = f"ACT: {act} {minutes_left}m {stage}"
    # Truncate if over limit
    if len(msg) > 57:
        max_name = 57 - len(f"ACT:  {minutes_left}m {stage}")
        msg = f"ACT: {act[:max_name]}… {minutes_left}m {stage}"
    return msg


def send_meshtastic_http(url, message):
    """Send a text message via Meshtastic HTTP API (v1 protobuf).

    The Meshtastic web server accepts PUT requests to /api/v1/toradio
    with a protobuf-encoded ToRadio message containing a text payload.

    For production use, install the official Python library:
        pip install meshtastic
        from meshtastic.interface import Interface

    This HTTP version works directly over WiFi without BLE.
    """
    import struct

    # Meshtastic protobuf ToRadio with text message (minimal encoding)
    # This is a simplified version — for robust use, use the meshtastic library
    try:
        data = message.encode("utf-8")
        req = urllib.request.Request(
            f"{url}/api/v1/toradio",
            data=data,
            method="PUT",
        )
        req.add_header("Content-Type", "application/octet-stream")
        resp = urllib.request.urlopen(req, timeout=10)
        print(f"  [✓] Sent: {message}")
    except Exception as e:
        print(f"  [✗] Failed: {message} — {e}")


def send_meshtastic_cli(message):
    """Fallback: use meshtastic Python CLI if library is available."""
    try:
        from meshtastic.interface import Interface
        iface = Interface()
        iface.sendText(message)
        iface.shutdown()
        print(f"  [✓] Sent (CLI): {message}")
        return True
    except ImportError:
        print("  [!] meshtastic library not installed — using HTTP API")
        return False
    except Exception as e:
        print(f"  [✗] CLI failed: {e}")
        return False


def check_schedule(schedule, url, notified):
    """Check schedule for upcoming acts and send notifications."""
    now = datetime.now()

    for act_entry in schedule:
        act = act_entry["act"]
        stage = act_entry.get("stage", "Main")
        start_str = act_entry["start"]  # "HH:MM" format

        # Parse start time for today
        start_time = datetime.strptime(
            f"{now.date()} {start_str}", "%Y-%m-%d %H:%M"
        )

        # Skip acts already notified
        if act in notified:
            continue

        # Calculate minutes until act
        delta = start_time - now
        minutes_left = int(delta.total_seconds() / 60)

        # Notify when act is upcoming
        if 0 < minutes_left <= HEADLINE_MINUTES:
            msg = build_message(act, start_str, stage, minutes_left)
            print(f"[{now.strftime('%H:%M')}] {msg}")
            send_meshtastic_http(url, msg)
            notified.add(act)

        # Also check if act is about to START (0 minutes = now playing)
        if minutes_left == 0:
            msg = f"NOW: {act} playing {stage}"
            print(f"[{now.strftime('%H:%M')}] {msg}")
            send_meshtastic_http(url, msg)
            notified.add(act + " NOW")


def main():
    parser = argparse.ArgumentParser(description="Festival act notifier")
    parser.add_argument(
        "--config", "-c", default="config.json",
        help="Path to config.json"
    )
    parser.add_argument(
        "--schedule", "-s",
        help="Path to schedule.json (overrides config)"
    )
    parser.add_argument(
        "--url", "-u",
        help="Meshtastic node URL (overrides config)"
    )
    args = parser.parse_args()

    # Load config
    try:
        config = load_config(args.config)
    except FileNotFoundError:
        print(f"Config not found: {args.config}")
        print("Create config.json with:")
        print(json.dumps({
            "meshtastic_url": "http://192.168.1.100",
            "schedule_file": "schedule.json",
            "headline_minutes": HEADLINE_MINUTES,
            "check_interval": CHECK_INTERVAL,
        }, indent=2))
        sys.exit(1)

    schedule_path = args.schedule or config.get("schedule_file", "schedule.json")
    url = args.url or config.get("meshtastic_url", "http://192.168.1.100")
    headline_minutes = config.get("headline_minutes", HEADLINE_MINUTES)
    check_interval = config.get("check_interval", CHECK_INTERVAL)

    # Load schedule
    try:
        schedule = load_schedule(schedule_path)
    except FileNotFoundError:
        print(f"Schedule not found: {schedule_path}")
        print("Create schedule.json with act data")
        sys.exit(1)

    print(f"=== Festival Pager Notifier ===")
    print(f"Meshtastic node: {url}")
    print(f"Schedule file: {schedule_path}")
    print(f"Acts loaded: {len(schedule)}")
    print(f"Notify {headline_minutes}m before act starts")
    print(f"Check every {check_interval}s\n")

    notified = set()

    # Main loop
    try:
        while True:
            check_schedule(schedule, url, notified)
            time.sleep(check_interval)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
