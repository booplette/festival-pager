"""Festival Pager — Data Models

Schedule, Event, Subscriber, Pin, Challenge, and MeshtasticMessage
dataclasses with JSON persistence. All data stored as flat JSON files
in the project directory.
"""

from __future__ import annotations

import json
import os
import random
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta
from typing import Callable, Optional


# ─── Constants ───────────────────────────────────────────────────────────────

DATA_DIR = os.path.dirname(os.path.abspath(__file__))
LEAD_TIME_MINUTES = 15
CHECK_INTERVAL_SECONDS = 30
PIN_EXPIRE_SECONDS = 300  # 5 minutes
CHALLENGE_EXPIRE_SECONDS = 300

# Whimsical Shambala-themed words for challenge codes
CHALLENGE_WORDS = [
    "GOAT", "BEAN", "BASS", "BIRD", "BUG", "BUZZ", "CHARM", "CHIME",
    "CLOUD", "DANCE", "DEER", "DREAM", "DRUM", "DUNE", "FAWN", "FERN",
    "FIELD", "FIRE", "FLOOD", "FLUTE", "FOG", "FOX", "FROG", "GLADE",
    "GLOW", "GNOME", "GONG", "GROVE", "HARE", "HUMM", "LEAF", "LUCK",
    "MAGIC", "MOSS", "MOTH", "MYTH", "OWL", "PEACE", "POND", "RAVE",
    "RUNE", "SOUL", "SPARK", "STAR", "SUN", "SWIRL", "TREE", "VIBE",
    "WILD", "WISP", "WYRD", "YEW",
]


# ─── Data Models ─────────────────────────────────────────────────────────────

@dataclass
class Event:
    """A single festival act / event on the schedule."""
    act: str
    day: str          # "2026-08-27"
    start: str        # "20:00"
    end: str          # "21:00"
    stage: str        # "Main", "Dance", etc.
    type: str = "music"

    @property
    def id(self) -> str:
        return f"{self.day}_{self.start}_{self.act}"

    @property
    def start_dt(self) -> datetime:
        return datetime.strptime(f"{self.day} {self.start}", "%Y-%m-%d %H:%M")


@dataclass
class Schedule:
    """Full festival schedule with persistence."""
    festival: str
    dates: list[str]
    timezone: str = "Europe/London"
    events: list[Event] = field(default_factory=list)

    @classmethod
    def load(cls, path: str) -> Schedule:
        with open(path) as f:
            data = json.load(f)
        events = [Event(**e) for e in data.pop("events", [])]
        return cls(events=events, **data)

    def save(self, path: str) -> None:
        data = asdict(self)
        data["events"] = [asdict(e) for e in self.events]
        with open(path, "w") as f:
            json.dump(data, f, indent=2)

    def next_events(self, n: int = 3) -> list[Event]:
        now = datetime.now()
        upcoming = [e for e in sorted(self.events, key=lambda x: x.start_dt)
                    if e.start_dt > now]
        return upcoming[:n]


@dataclass
class Subscriber:
    """A Meshtastic node subscribed to notifications."""
    node_id: str
    active: bool = True
    events: list[str] = field(default_factory=list)    # act names
    stages: list[str] = field(default_factory=list)     # stage names
    created: str = field(default_factory=lambda: datetime.now().isoformat())
    last_seen: str = field(default_factory=lambda: datetime.now().isoformat())

    def wants(self, event: Event) -> bool:
        if not self.active:
            return False
        if event.act in self.events:
            return True
        if event.stage in self.stages:
            return True
        return False


@dataclass
class Pin:
    """One-time PIN for binding a browser session to a node ID."""
    code: str
    session_id: str
    created: float = field(default_factory=time.time)
    claimed_by: Optional[str] = None

    @property
    def expired(self) -> bool:
        return time.time() - self.created > PIN_EXPIRE_SECONDS


@dataclass
class Challenge:
    """Challenge-response verification for no-keyboard auth path."""
    id: str
    node_id: str
    code: str
    created: float = field(default_factory=time.time)
    verified: bool = False
    session_id: str = ""

    @property
    def expired(self) -> bool:
        return time.time() - self.created > CHALLENGE_EXPIRE_SECONDS

    @classmethod
    def generate_code(cls) -> str:
        word = random.choice(CHALLENGE_WORDS)
        digits = random.randint(10, 99)
        return f"{word}{digits}"


@dataclass
class MeshtasticMessage:
    """A parsed inbound DM from the mesh."""
    from_id: str      # "!a1b2c3d4"
    text: str         # Message body
    channel: int = 0  # 0 = primary
    rx_snr: float = 0.0
    rx_time: float = field(default_factory=time.time)


# ─── Persistence Helpers ─────────────────────────────────────────────────────

def _data_path(filename: str) -> str:
    return os.path.join(DATA_DIR, filename)


class SubscriberStore:
    """Persistent subscriber database as JSON."""

    def __init__(self, path: Optional[str] = None):
        self.path = path or _data_path("subscribers.json")
        self._subs: dict[str, Subscriber] = {}
        self._load()

    def _load(self) -> None:
        if not os.path.exists(self.path):
            return
        with open(self.path) as f:
            raw = json.load(f)
        self._subs = {k: Subscriber(**v) for k, v in raw.items()}

    def _save(self) -> None:
        raw = {k: asdict(v) for k, v in self._subs.items()}
        with open(self.path, "w") as f:
            json.dump(raw, f, indent=2)

    def get(self, node_id: str) -> Optional[Subscriber]:
        return self._subs.get(node_id)

    def all(self) -> list[Subscriber]:
        return list(self._subs.values())

    def active(self) -> list[Subscriber]:
        return [s for s in self._subs.values() if s.active]

    def upsert(self, sub: Subscriber) -> None:
        self._subs[sub.node_id] = sub
        self._save()

    def remove(self, node_id: str) -> bool:
        if node_id in self._subs:
            del self._subs[node_id]
            self._save()
            return True
        return False


class PinStore:
    """Ephemeral PIN store (auto-expire after 5 min)."""

    def __init__(self, path: Optional[str] = None):
        self.path = path or _data_path("pins.json")
        self._pins: dict[str, Pin] = {}
        self._load()

    def _load(self) -> None:
        if not os.path.exists(self.path):
            return
        with open(self.path) as f:
            raw = json.load(f)
        self._pins = {k: Pin(**v) for k, v in raw.items()}

    def _save(self) -> None:
        # Expunge expired before saving
        self._pins = {k: v for k, v in self._pins.items() if not v.expired}
        raw = {k: asdict(v) for k, v in self._pins.items()}
        with open(self.path, "w") as f:
            json.dump(raw, f, indent=2)

    def create(self, session_id: str) -> Pin:
        code = f"{random.randint(100000, 999999)}"
        pin = Pin(code=code, session_id=session_id)
        self._pins[code] = pin
        self._save()
        return pin

    def claim(self, code: str, node_id: str) -> Optional[Pin]:
        pin = self._pins.get(code)
        if pin is None or pin.expired or pin.claimed_by is not None:
            return None
        pin.claimed_by = node_id
        self._save()
        return pin


class ChallengeStore:
    """Ephemeral challenge store (auto-expire after 5 min)."""

    def __init__(self, path: Optional[str] = None):
        self.path = path or _data_path("challenges.json")
        self._challenges: dict[str, Challenge] = {}
        self._load()

    def _load(self) -> None:
        if not os.path.exists(self.path):
            return
        with open(self.path) as f:
            raw = json.load(f)
        self._challenges = {k: Challenge(**v) for k, v in raw.items()}

    def _save(self) -> None:
        self._challenges = {k: v for k, v in self._challenges.items()
                            if not v.expired}
        raw = {k: asdict(v) for k, v in self._challenges.items()}
        with open(self.path, "w") as f:
            json.dump(raw, f, indent=2)

    def create(self, node_id: str, session_id: str = "") -> Challenge:
        import uuid
        cid = uuid.uuid4().hex[:8]
        code = Challenge.generate_code()
        challenge = Challenge(id=cid, node_id=node_id, code=code,
                              session_id=session_id)
        self._challenges[cid] = challenge
        self._save()
        return challenge

    def verify(self, code: str) -> Optional[Challenge]:
        for c in self._challenges.values():
            if c.code == code and not c.verified and not c.expired:
                c.verified = True
                self._save()
                return c
        return None