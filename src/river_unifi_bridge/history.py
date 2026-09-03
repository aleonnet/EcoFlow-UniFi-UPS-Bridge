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
    detail TEXT,
    device TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_ts ON events (ts);
"""

# Bases criadas antes de 2026-09-03 não têm a coluna `device` (o dono do evento:
# o id da instância do dispositivo protegido). ALTER TABLE ADD COLUMN é a única
# migração de esquema e é idempotente por construção: só roda quando PRAGMA
# table_info não lista a coluna. Linhas antigas ficam com device NULL — o app
# resolve o dono pelo tipo do evento quando só há uma instância do tipo.
_EVENTS_DEVICE_MIGRATION = "ALTER TABLE events ADD COLUMN device TEXT"


def _event_row(r: tuple) -> dict:
    return {"ts": r[0], "type": r[1], "detail": r[2], "device": r[3]}


class HistoryStore:
    def __init__(self, path: str, retention_days: int = 7) -> None:
        self.path = path
        self.retention_days = retention_days
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with self._connect() as conn:
            conn.executescript(_SCHEMA)
            columns = {row[1] for row in conn.execute("PRAGMA table_info(events)")}
            if "device" not in columns:
                conn.execute(_EVENTS_DEVICE_MIGRATION)

    def _connect(self) -> sqlite3.Connection:
        # One fresh connection per operation (thread-safe by construction:
        # poll loop and API thread never share a handle). Each `with conn:`
        # block is ONE atomic transaction (sqlite3 context manager commits or
        # rolls back). WAL + synchronous=NORMAL is the documented combo for
        # this environment: "The synchronous=NORMAL setting is a good choice
        # for most applications running in WAL mode."
        # (https://www.sqlite.org/pragma.html#pragma_synchronous)
        conn = sqlite3.connect(self.path, timeout=5)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
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
                     ts: int | None = None, device: str | None = None) -> None:
        """`device` = id da instância do dispositivo protegido dona do evento;
        None para eventos do bridge (queda, restauração, comunicação)."""
        ts = int(ts if ts is not None else time.time())
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO events (ts, type, detail, device) VALUES (?, ?, ?, ?)",
                (ts, event_type, detail, device),
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
                "SELECT ts, type, detail, device FROM events ORDER BY ts DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [_event_row(r) for r in rows]

    def query_events(self, ts_from: int, ts_to: int,
                     types: list[str] | None = None,
                     limit: int = 200, device: str | None = None) -> list[dict]:
        """Period/type/device query over the persisted log (newest first)."""
        if ts_from > ts_to:
            raise ValueError("intervalo inválido: from maior que to")
        if not 1 <= limit <= 1000:
            raise ValueError("limit fora da faixa (1..1000)")
        sql = "SELECT ts, type, detail, device FROM events WHERE ts >= ? AND ts <= ?"
        args: list[object] = [ts_from, ts_to]
        if types:
            sql += f" AND type IN ({','.join('?' * len(types))})"
            args.extend(types)
        if device:
            sql += " AND device = ?"
            args.append(device)
        sql += " ORDER BY ts DESC LIMIT ?"
        args.append(limit)
        with self._connect() as conn:
            rows = conn.execute(sql, args).fetchall()
        return [_event_row(r) for r in rows]

    def delete_events(self, ts_from: int, ts_to: int) -> int:
        """Delete events inside [from, to]; returns rows removed."""
        if ts_from > ts_to:
            raise ValueError("intervalo inválido: from maior que to")
        with self._connect() as conn:
            return conn.execute(
                "DELETE FROM events WHERE ts >= ? AND ts <= ?",
                (ts_from, ts_to),
            ).rowcount

    def prune(self, now: int | None = None) -> int:
        """Delete data older than the retention window. Returns rows removed."""
        now = int(now if now is not None else time.time())
        cutoff = now - self.retention_days * 86400
        with self._connect() as conn:
            a = conn.execute("DELETE FROM samples WHERE ts < ?", (cutoff,)).rowcount
            b = conn.execute("DELETE FROM events WHERE ts < ?", (cutoff,)).rowcount
        return a + b
