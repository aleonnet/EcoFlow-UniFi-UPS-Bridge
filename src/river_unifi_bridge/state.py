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


def _epoca(ts: str | None) -> float:
    """O carimbo do evento em segundos. Ilegível vira infinito: na dúvida, mantém."""
    if not ts:
        return float("inf")
    try:
        return time.mktime(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
    except (ValueError, TypeError):
        return float("inf")


def _selo_do_cabo(snapshot: dict | None, comm_ok: bool, last_error: str | None) -> str:
    """O que dá para afirmar sobre o cabo, sem inventar.

    Quem enxerga o USB é o driver do no-break; o que sabemos é se a leitura
    corrente veio dele (e não de um simulador). Só isso, e é o bastante.
    """
    # Import local de propósito: `state.py` é folha da árvore de imports (ver a
    # nota do alias, acima) e amarrá-la a `protect` no topo trocaria um selo
    # honesto por um ciclo.
    from .protect import _is_synthetic_driver

    if snapshot is None:
        return "falha" if last_error else "sem_dados"
    if not comm_ok:
        return "falha"
    fonte = snapshot.get("source") or {}
    nome, versao = fonte.get("driver_name"), fonte.get("driver_version")
    if not nome or not versao:
        return "sem_dados"
    if _is_synthetic_driver(nome, versao):
        return "simulado"
    return "ok"


class SharedState:
    def __init__(self, events_maxlen: int = 100) -> None:
        self._lock = threading.Lock()
        self._version = 0
        self._snapshot: dict | None = None
        self._events: deque[dict] = deque(maxlen=events_maxlen)
        # Sequência que só cresce. A fila é limitada e o cliente SSE não pode se
        # orientar por índice: quando ela satura, o índice para de andar e os
        # eventos novos deixam de sair. O número dá ao cliente um "já vi até aqui"
        # que sobrevive ao descarte dos mais antigos.
        self._seq = 0
        self._comm_ok = False
        self._last_error: str | None = None
        self._plugins: list[dict] = []         # última leitura de plugin_statuses()
        # Erro de SOFTWARE no ciclo (um plugin que levantou), separado do erro do
        # UPS: confundir os dois faria a tela dizer "NUT com falha" quando o NUT
        # está bem e quem quebrou fomos nós.
        self._last_tick_error: str | None = None

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

    def record_tick_error(self, reason: str) -> None:
        with self._lock:
            self._last_tick_error = reason
            self._version += 1

    def record_failure(self, reason: str) -> None:
        with self._lock:
            self._comm_ok = False
            self._last_error = reason
            self._version += 1

    def add_event(self, name: str, payload: dict | None = None) -> None:
        with self._lock:
            self._seq += 1
            self._events.append(
                {
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                    "event": name,
                    "seq": self._seq,
                    **(payload or {}),
                }
            )
            self._version += 1

    def get(self) -> tuple[int, dict | None, bool, str | None]:
        with self._lock:
            return self._version, self._snapshot, self._comm_ok, self._last_error

    def clear_events(self, ts_to: int, ts_from: int = 0) -> int:
        """Esquece os eventos até `ts_to` (inclusive). Devolve quantos saíram.

        Limpar o histórico gravado não bastava: esta fila é o que o SSE entrega
        a QUEM CONECTA, então os eventos apagados voltavam à tela na reconexão
        seguinte. A faixa é a MESMA do banco (`from`..`to`): esquecer da memória o
        que o banco manteve seria outra divergência. Evento com carimbo ilegível
        fica — nunca apago o que não sei datar.
        """
        with self._lock:
            antes = len(self._events)
            mantidos = [e for e in self._events
                        if not (ts_from <= _epoca(e.get("ts")) <= ts_to)]
            self._events = deque(mantidos, maxlen=self._events.maxlen)
            self._version += 1
            return antes - len(self._events)

    def events(self, after: int = -1) -> list[dict]:
        """Os eventos posteriores a `after` (a sequência, não o índice)."""
        with self._lock:
            return [e for e in self._events if e["seq"] > after]

    def health(self) -> dict:
        """Chain view (§7A.3): honest 'não observável' for links we can't see yet."""
        with self._lock:
            version = self._version
            snapshot = self._snapshot
            comm_ok = self._comm_ok
            last_error = self._last_error
            last_tick_error = self._last_tick_error
            plugins = [dict(p) for p in self._plugins]
        # O alias udr7/udr7_detail continua sendo a entrada deste id. É PERMANENTE
        # enquanto o instalador o ler com sed (river-bridge-install.sh): a regex
        # casa `"udr7": "..."` no topo e não casaria `"id": "udr7"` dentro da lista.
        alias = next((p for p in plugins if p["id"] == UDR7_ALIAS_ID), None)
        protection = alias["detail"] if alias else None
        # O cabo: até a 0.5.1 este selo era uma constante — dizia "não observável"
        # acontecesse o que acontecesse, e o dono chamou o que era: um selo que
        # não mede nada. Hoje temos resposta: se a leitura corrente veio do driver
        # de verdade, o cabo está entregando dados.
        usb = _selo_do_cabo(snapshot, comm_ok, last_error)
        return {
            "usb": usb,
            "nut": "ok" if comm_ok else ("falha" if last_error else "sem_dados"),
            "bridge": "ok",
            # Research verdict (docs/2026-08-31-2345-pesquisa-udr7-ups-terceiros.md): no documented
            # native path for a console to consume a third-party UPS — not "impossible".
            "unifi": "sem_caminho_nativo_documentado",
            # Fase 3'-EXP: closed enum from the protection policy; None until the first tick.
            "udr7": alias["state"] if alias else "desabilitado",
            "udr7_detail": protection,
            # Todo dispositivo protegido, do registro do daemon.
            "plugins": plugins,
            "ha": "nao_observavel",
            "last_error": last_error,
            "last_tick_error": last_tick_error,
            "has_snapshot": snapshot is not None,
            "version": version,
        }
