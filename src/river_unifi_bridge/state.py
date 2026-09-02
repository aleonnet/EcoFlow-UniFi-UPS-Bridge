"""Thread-safe shared state between the poll loop and the local API (§7A.3).

The poll loop (sync, main thread) writes; aiohttp handlers (worker thread)
read. Version counter lets SSE detect changes without busy diffing.
"""

from __future__ import annotations

import threading
import time
from collections import deque


# O id cujo estado também sai no topo do health, por compatibilidade. Literal
# aqui de propósito: state.py é folha da árvore de imports e importar plugins/
# fecharia um ciclo.
UDR7_ALIAS_ID = "udr7"


class SharedState:
    def __init__(self, events_maxlen: int = 100) -> None:
        self._lock = threading.Lock()
        self._version = 0
        self._snapshot: dict | None = None
        self._events: deque[dict] = deque(maxlen=events_maxlen)
        self._comm_ok = False
        self._last_error: str | None = None
        self._plugins: list[dict] = []         # última leitura de plugin_statuses()

    def set_plugins(self, statuses: list[dict]) -> None:
        """Copia sob a trava: o chamador pode reusar a lista depois."""
        with self._lock:
            self._plugins = [dict(s) for s in statuses]

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
            plugins = [dict(p) for p in self._plugins]
        # O alias udr7/udr7_detail continua sendo a entrada deste id. É PERMANENTE
        # enquanto o instalador o ler com sed (river-bridge-install.sh): a regex
        # casa `"udr7": "..."` no topo e não casaria `"id": "udr7"` dentro da lista.
        alias = next((p for p in plugins if p["id"] == UDR7_ALIAS_ID), None)
        protection = alias["detail"] if alias else None
        usb = "nao_observavel"  # only the NUT driver sees USB; Fase 1+ may refine
        return {
            "usb": usb,
            "nut": "ok" if comm_ok else ("falha" if last_error else "sem_dados"),
            "bridge": "ok",
            # Research verdict (docs/PESQUISA_UDR7_UPS_TERCEIROS_20260831.md): no documented
            # native path for a console to consume a third-party UPS — not "impossible".
            "unifi": "sem_caminho_nativo_documentado",
            # Fase 3'-EXP: closed enum from the protection policy; None until the first tick.
            "udr7": alias["state"] if alias else "desabilitado",
            "udr7_detail": protection,
            # Todo dispositivo protegido, do registro do daemon.
            "plugins": plugins,
            "ha": "nao_observavel",
            "last_error": last_error,
            "has_snapshot": snapshot is not None,
            "version": version,
        }
