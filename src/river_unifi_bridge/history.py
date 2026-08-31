"""Telemetry history for the UI charts (§7A.4).

The daemon owns history (it runs 24/7; the UI is intermittent). SQLite from
the stdlib, WAL mode, one short-lived connection per call — safe across the
poll thread and the API thread without shared connections.
"""

from __future__ import annotations

import os
import sqlite3
import time

METRICS = ("charge", "runtime", "load", "power_w")

_SCHEMA = """
CREATE TABLE IF NOT EXISTS samples (
    ts INTEGER NOT NULL,
    state TEXT,
    charge REAL,
    runtime REAL,
    load REAL,
    power_w REAL
);
CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples (ts);
CREATE TABLE IF NOT EXISTS events (
    ts INTEGER NOT NULL,
    type TEXT NOT NULL,
    detail TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_ts ON events (ts);
"""


class HistoryStore:
    def __init__(self, path: str, retention_days: int = 7) -> None:
        self.path = path
        self.retention_days = retention_days
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with self._connect() as conn:
            conn.executescript(_SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, timeout=5)
        conn.execute("PRAGMA journal_mode=WAL")
        return conn

    def record_sample(self, snapshot: dict, ts: int | None = None) -> None:
        ts = int(ts if ts is not None else time.time())
        battery = snapshot.get("battery", {})
        power = snapshot.get("power", {})
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO samples (ts, state, charge, runtime, load, power_w)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                (
                    ts,
                    power.get("state"),
                    battery.get("charge_percent"),
                    battery.get("runtime_seconds"),
                    power.get("load_percent"),
                    power.get("output_power_w"),
                ),
            )

    def record_event(self, event_type: str, detail: str | None = None,
                     ts: int | None = None) -> None:
        ts = int(ts if ts is not None else time.time())
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO events (ts, type, detail) VALUES (?, ?, ?)",
                (ts, event_type, detail),
            )

    def query(self, metric: str, ts_from: int, ts_to: int,
              bucket_seconds: int = 60) -> list[dict]:
        """Bucketed aggregation; only known metrics, only real data."""
        if metric not in METRICS:
            raise ValueError(f"métrica desconhecida: {metric} (válidas: {', '.join(METRICS)})")
        if bucket_seconds < 1:
            raise ValueError("bucket_seconds deve ser >= 1")
        with self._connect() as conn:
            rows = conn.execute(
                f"SELECT (ts / ?) * ? AS bucket, AVG({metric}), MIN({metric}),"
                f" MAX({metric}), COUNT({metric})"
                " FROM samples WHERE ts >= ? AND ts <= ? AND"
                f" {metric} IS NOT NULL GROUP BY bucket ORDER BY bucket",
                (bucket_seconds, bucket_seconds, ts_from, ts_to),
            ).fetchall()
        return [
            {"ts": r[0], "avg": r[1], "min": r[2], "max": r[3], "n": r[4]}
            for r in rows
        ]

    def recent_events(self, limit: int = 50) -> list[dict]:
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT ts, type, detail FROM events ORDER BY ts DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [{"ts": r[0], "type": r[1], "detail": r[2]} for r in rows]

    def prune(self, now: int | None = None) -> int:
        """Delete data older than the retention window. Returns rows removed."""
        now = int(now if now is not None else time.time())
        cutoff = now - self.retention_days * 86400
        with self._connect() as conn:
            a = conn.execute("DELETE FROM samples WHERE ts < ?", (cutoff,)).rowcount
            b = conn.execute("DELETE FROM events WHERE ts < ?", (cutoff,)).rowcount
        return a + b
