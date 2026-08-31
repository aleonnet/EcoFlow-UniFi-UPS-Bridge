"""Read-only bridge service (spec §23 Fase 2): poll NUT -> normalize -> log.

No UniFi, no API, no writes anywhere. Structured JSON logs on stdout
(spec §17 — daemon layer). Transition debounce per spec §11, driven by an
injectable clock so tests never sleep.

CLI (pt-BR output, house exit codes): 0 ok · 2 uso · 3 validação · 10 conexão.
"""

from __future__ import annotations

import argparse
import json
import sys
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

        if snap.state == "ON_BATTERY":
            self._online_since = None
            if self._on_battery_since is None:
                self._on_battery_since = now
            elif (
                not self._power_lost
                and now - self._on_battery_since >= self._cfg.power_loss_delay_seconds
            ):
                self._power_lost = True
                events.append("POWER_LOSS")
        elif snap.state == "ONLINE":
            self._on_battery_since = None
            if self._online_since is None:
                self._online_since = now
            elif (
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


def run_loop(cfg: BridgeConfig, *, once: bool = False) -> int:
    tracker = TransitionTracker(cfg)
    while True:
        try:
            snap = poll_once(cfg)
        except NutError as exc:
            for event in tracker.observe_failure():
                _log("WARN", event, reason=str(exc))
            if once:
                _log("ERROR", "poll_failed", reason=str(exc))
                return EXIT_CONNECTION
        else:
            for event in tracker.observe(snap):
                _log("WARN", event, state=snap.state, charge=snap.charge_percent)
            _log("INFO", "state", **snap.to_dict())
            if once:
                return EXIT_OK
        time.sleep(cfg.poll_interval_seconds)


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

    try:
        cfg = load_config(args.env)
    except ConfigError as exc:
        _log("ERROR", "config_invalid", reason=str(exc))
        return EXIT_VALIDATION
    for warning in cfg.warnings:
        _log("WARN", "config_warning", reason=warning)

    try:
        return run_loop(cfg, once=args.once)
    except KeyboardInterrupt:
        _log("INFO", "stopped", reason="interrompido pelo usuário")
        return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
