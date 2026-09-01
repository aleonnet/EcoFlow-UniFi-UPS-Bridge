"""Read-only bridge service (spec §23 Fase 2): poll NUT -> normalize -> log.

No UniFi, no API, no writes anywhere. Structured JSON logs on stdout
(spec §17 — daemon layer). Transition debounce per spec §11, driven by an
injectable clock so tests never sleep.

CLI (pt-BR output, house exit codes): 0 ok · 2 uso · 3 validação · 10 conexão.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import time

from . import __version__
from .config import BridgeConfig, ConfigError, load_config
from .model import UpsSnapshot, snapshot_from_nut_vars
from .nut import NutClient, NutError

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_VALIDATION = 3
EXIT_CONNECTION = 10


class TransitionTracker:
    """Debounced event detection over a stream of (snapshot | comm failure).

    Events: POWER_LOSS, POWER_RESTORED, LOW_BATTERY, COMM_LOST, COMM_RESTORED.
    A condition must hold for its configured delay before the event fires
    (spec §11); LOW_BATTERY fires immediately once the state is confirmed.
    """

    def __init__(self, cfg: BridgeConfig, clock=time.monotonic) -> None:
        self._cfg = cfg
        self._clock = clock
        self._on_battery_since: float | None = None
        self._online_since: float | None = None
        self._last_ok_poll: float | None = None
        self._power_lost = False
        self._comm_lost = False
        self._low_battery_reported = False

    def observe(self, snap: UpsSnapshot) -> list[str]:
        now = self._clock()
        events: list[str] = []

        if self._comm_lost:
            events.append("COMM_RESTORED")
            self._comm_lost = False
        self._last_ok_poll = now

        # A janela abre E a condição é avaliada no MESMO tick: com delay 0 o
        # evento sai imediatamente (semântica NUT/apcupsd — pesquisa
        # 2026-08-31); com delay > 0 o primeiro tick nunca satisfaz (0 >= d).
        if snap.state == "ON_BATTERY":
            self._online_since = None
            if self._on_battery_since is None:
                self._on_battery_since = now
            if (
                not self._power_lost
                and now - self._on_battery_since >= self._cfg.power_loss_delay_seconds
            ):
                self._power_lost = True
                events.append("POWER_LOSS")
        elif snap.state == "ONLINE":
            self._on_battery_since = None
            if self._online_since is None:
                self._online_since = now
            if (
                self._power_lost
                and now - self._online_since >= self._cfg.restore_delay_seconds
            ):
                self._power_lost = False
                self._low_battery_reported = False
                events.append("POWER_RESTORED")

        low = snap.low_battery or (
            snap.charge_percent is not None
            and snap.charge_percent <= self._cfg.low_battery_percent
        )
        if low and not self._low_battery_reported:
            self._low_battery_reported = True
            events.append("LOW_BATTERY")

        return events

    def observe_failure(self) -> list[str]:
        now = self._clock()
        if self._last_ok_poll is None:
            self._last_ok_poll = now
            return []
        if (
            not self._comm_lost
            and now - self._last_ok_poll >= self._cfg.comm_loss_delay_seconds
        ):
            self._comm_lost = True
            return ["COMM_LOST"]
        return []


def _log(level: str, event: str, **payload) -> None:
    record = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "level": level, "event": event}
    record.update(payload)
    print(json.dumps(record, ensure_ascii=False), flush=True)


def poll_once(cfg: BridgeConfig) -> UpsSnapshot:
    with NutClient(cfg.nut_host, cfg.nut_port) as client:
        nut_vars = client.list_vars(cfg.nut_ups)
    return snapshot_from_nut_vars(cfg.river_name, nut_vars)


EXIT_RESTART_REQUESTED = 75


def run_loop(cfg: BridgeConfig, *, once: bool = False, env_path: str = "") -> int:
    tracker = TransitionTracker(cfg)

    api_server = None
    shared = None
    history = None
    restart_requested = threading.Event()
    if not once and cfg.ui_api_enabled:
        # Lazy import: aiohttp only loads when the API is actually enabled.
        from .api import ApiServer
        from .history import HistoryStore
        from .localtoken import state_dir
        from .state import SharedState

        shared = SharedState()
        history = HistoryStore(
            os.path.join(state_dir(), "history.sqlite"), cfg.history_retention_days
        )
        api_server = ApiServer(
            cfg, shared, history, env_path, restart_cb=restart_requested.set
        )
        # Bind failures (e.g. EADDRINUSE) get 3 attempts with backoff; a
        # persistent failure is config-class → deliberate stop under launchd.
        api_ok = False
        for attempt in range(3):
            try:
                api_server.start_in_thread()
                api_ok = True
                break
            except Exception as exc:  # noqa: BLE001 — bind/loop startup errors
                _log("WARN", "api_start_failed", attempt=attempt + 1, reason=str(exc))
                time.sleep(2 * (attempt + 1))
        if not api_ok:
            _log("ERROR", "parada_deliberada", reason="API local não subiu após 3 tentativas")
            return EXIT_OK if os.environ.get("RUB_LAUNCHD") == "1" else EXIT_VALIDATION
        _log("INFO", "api_started", port=cfg.ui_api_port)

    while True:
        try:
            snap = poll_once(cfg)
        except NutError as exc:
            for event in tracker.observe_failure():
                _log("WARN", event, reason=str(exc))
                if shared is not None:
                    shared.add_event(event, {"reason": str(exc)})
                if history is not None:
                    history.record_event(event, str(exc))
            if shared is not None:
                shared.record_failure(str(exc))
            if once:
                _log("ERROR", "poll_failed", reason=str(exc))
                return EXIT_CONNECTION
        else:
            snap_dict = snap.to_dict()
            for event in tracker.observe(snap):
                _log("WARN", event, state=snap.state, charge=snap.charge_percent)
                if shared is not None:
                    shared.add_event(event, {"state": snap.state, "charge": snap.charge_percent})
                if history is not None:
                    history.record_event(event)
            if shared is not None:
                shared.update_snapshot(snap_dict)
            if history is not None:
                history.record_sample(snap_dict)
            _log("INFO", "state", **snap_dict)
            if once:
                return EXIT_OK
        if restart_requested.wait(timeout=cfg.poll_interval_seconds):
            # §7A.3 contract: deliberate restart exits 75; launchd
            # (KeepAlive={SuccessfulExit: false}) relaunches us.
            _log("INFO", "restart_requested", exit_code=EXIT_RESTART_REQUESTED)
            return EXIT_RESTART_REQUESTED


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="river-unifi-bridge",
        description="Ponte read-only: NUT -> modelo normalizado -> logs (Fase 2).",
    )
    parser.add_argument("--env", required=True, help="caminho do arquivo .env de configuração")
    parser.add_argument("--once", action="store_true", help="uma leitura e sai (diagnóstico)")
    parser.add_argument("--version", action="version", version=__version__)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:  # argparse uses 2 for usage errors — house code matches
        return int(exc.code or EXIT_USAGE)

    launchd_mode = os.environ.get("RUB_LAUNCHD") == "1"
    try:
        cfg = load_config(args.env)
    except ConfigError as exc:
        _log("ERROR", "config_invalid", reason=str(exc))
        # §7A.3 contract: a config error would repeat on every relaunch.
        # Under launchd (KeepAlive={SuccessfulExit: false}) exit(0) is the
        # DELIBERATE stop — no crash loop; the log carries the cause.
        # In CLI mode the house exit codes apply (3 = validação).
        if launchd_mode:
            _log("ERROR", "parada_deliberada", reason="config inválida não relança")
            return EXIT_OK
        return EXIT_VALIDATION
    for warning in cfg.warnings:
        _log("WARN", "config_warning", reason=warning)

    try:
        return run_loop(cfg, once=args.once, env_path=args.env)
    except KeyboardInterrupt:
        _log("INFO", "stopped", reason="interrompido pelo usuário")
        return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
