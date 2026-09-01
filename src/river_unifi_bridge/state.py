"""Thread-safe shared state between the poll loop and the local API (§7A.3).

The poll loop (sync, main thread) writes; aiohttp handlers (worker thread)
read. Version counter lets SSE detect changes without busy diffing.
"""

from __future__ import annotations

import threading
import time
from collections import deque


class SharedState:
    def __init__(self, events_maxlen: int = 100) -> None:
        self._lock = threading.Lock()
        self._version = 0
        self._snapshot: dict | None = None
        self._events: deque[dict] = deque(maxlen=events_maxlen)
        self._comm_ok = False
        self._last_error: str | None = None
        self._protection: dict | None = None   # Fase 3'-EXP: last policy.status()

    def set_protection(self, status: dict | None) -> None:
        with self._lock:
            self._protection = status

    def update_snapshot(self, snapshot: dict) -> None:
        with self._lock:
            self._snapshot = snapshot
            self._comm_ok = True
            self._last_error = None
            self._version += 1

    def record_failure(self, reason: str) -> None:
        with self._lock:
            self._comm_ok = False
            self._last_error = reason
            self._version += 1

    def add_event(self, name: str, payload: dict | None = None) -> None:
        with self._lock:
            self._events.append(
                {
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                    "event": name,
                    **(payload or {}),
                }
            )
            self._version += 1

    def get(self) -> tuple[int, dict | None, bool, str | None]:
        with self._lock:
            return self._version, self._snapshot, self._comm_ok, self._last_error

    def events(self) -> list[dict]:
        with self._lock:
            return list(self._events)

    def health(self) -> dict:
        """Chain view (§7A.3): honest 'não observável' for links we can't see yet."""
        with self._lock:
            version = self._version
            snapshot = self._snapshot
            comm_ok = self._comm_ok
            last_error = self._last_error
            protection = dict(self._protection) if self._protection else None
        usb = "nao_observavel"  # only the NUT driver sees USB; Fase 1+ may refine
        return {
            "usb": usb,
            "nut": "ok" if comm_ok else ("falha" if last_error else "sem_dados"),
            "bridge": "ok",
            # Research verdict (docs/PESQUISA_UDR7_UPS_TERCEIROS_20260831.md): no documented
            # native path for a console to consume a third-party UPS — not "impossible".
            "unifi": "sem_caminho_nativo_documentado",
            # Fase 3'-EXP: closed enum from the protection policy; None until the first tick.
            "udr7": protection["state"] if protection else "desabilitado",
            "udr7_detail": protection,
            "ha": "nao_observavel",
            "last_error": last_error,
            "has_snapshot": snapshot is not None,
            "version": version,
        }
