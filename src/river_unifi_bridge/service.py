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
from .devices import DeviceStore, DevicesError
from .localtoken import state_dir
from .model import UpsSnapshot, snapshot_from_nut_vars
from . import river_serial
from .nut import NutClient, NutError
# Import no TOPO, não dentro da função: um monkeypatch de
# `service.build_plugins` no teste só intercepta se o nome viver aqui.
from .plugins import PluginSet, build_plugins, plugin_statuses
from .plugins.udr7_ssh import apply_instance_to_cfg, legacy_instance
from .protect import _emit

# Folga (em pontos de carga) para o alerta de bateria baixa poder ser emitido de
# novo: a condição só é considerada cessada acima do limiar mais esta margem.
LOW_BATTERY_HYSTERESIS_PERCENT = 5

# De quanto em quanto tempo o histórico é limpo pela retenção configurada.
PRUNE_INTERVAL_SECONDS = 3600

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

        # Bateria baixa só faz sentido NA BATERIA: 25 % carregando na tomada é
        # normal, e virava alerta (B01). A condição também tem de poder cessar,
        # senão o alerta some para o resto da vida do processo depois da primeira
        # queda; a folga evita que uma carga oscilando no limiar dispare em rajada.
        low = snap.state == "ON_BATTERY" and (
            snap.low_battery or (
                snap.charge_percent is not None
                and snap.charge_percent <= self._cfg.low_battery_percent
            )
        )
        if low and not self._low_battery_reported:
            self._low_battery_reported = True
            events.append("LOW_BATTERY")
        elif (
            self._low_battery_reported
            and not snap.low_battery
            and snap.charge_percent is not None
            and snap.charge_percent
            >= self._cfg.low_battery_percent + LOW_BATTERY_HYSTERESIS_PERCENT
        ):
            self._low_battery_reported = False

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


# A porta serial que respondeu na última vez. Procurar de novo a cada leitura
# custaria abrir todas as portas do Mac por ciclo.
_porta_serial_lembrada: str | None = None


def _completa_pela_serial(snap: UpsSnapshot, cfg: BridgeConfig, ler=river_serial.ler) -> None:
    """Preenche consumo e tomadas pela porta serial do aparelho, quando ela existe.

    O perfil de no-break do River 3 Plus não publica potência (medido; ver
    `docs/decisions/2026-09-04-0110-…`). A segunda porta do mesmo cabo publica, e
    as duas convivem. Falha aqui **não** é falha de leitura do UPS: o ciclo segue
    com o que o NUT deu, e os campos ficam nulos, que é a verdade.
    """
    global _porta_serial_lembrada
    if not cfg.river_serial_enabled:
        return
    porta = cfg.river_serial_port or "auto"
    if porta == "auto" and _porta_serial_lembrada:
        porta = _porta_serial_lembrada
    try:
        resultado = ler(porta, serie_esperada=snap.serial or None)
        if resultado is None and porta != "auto":
            # A porta lembrada calou (cabo trocado de lugar): procura de novo.
            resultado = ler("auto", serie_esperada=snap.serial or None)
    except Exception as exc:  # serial_read_failed: o vigia não depende disto
        _log("WARN", "serial_read_failed", reason=f"{type(exc).__name__}: {exc}")
        return
    if resultado is None:
        return
    leitura, porta_usada = resultado
    _porta_serial_lembrada = porta_usada
    snap.outlets = leitura.to_dict()
    snap.input_power_w = leitura.entrada_total_w
    snap.line_frequency_hz = leitura.frequencia_hz
    snap.serial_port_read = True
    # O que o resto do sistema já entende: consumo total e temperatura.
    if leitura.carga_total_w is not None:
        snap.output_power_w = leitura.carga_total_w
    if snap.temperature_c is None and leitura.temperatura_c is not None:
        snap.temperature_c = leitura.temperatura_c


EXIT_RESTART_REQUESTED = 75


def _detail_do_evento(payload: dict) -> str | None:
    """O texto que acompanha o evento no histórico.

    Sem ele, o detalhe de uma queda ou de uma restauração aparecia vazio na tela:
    o motivo só existe no caminho de falha, e o caminho de sucesso mandava `None`.
    """
    motivo = payload.get("reason")
    if motivo:
        return str(motivo)
    partes = []
    if payload.get("state"):
        partes.append(f"estado={payload['state']}")
    if payload.get("charge") is not None:
        partes.append(f"carga={payload['charge']:g}")
    return " ".join(partes) or None


def _record_tracker_events(events: list[str], payload_fn, shared, history) -> None:
    for event in events:
        payload = payload_fn(event)
        _log("WARN", event, **payload)
        if shared is not None:
            shared.add_event(event, payload)
        if history is not None:
            history.record_event(event, _detail_do_evento(payload))


def _audit_plugins(plugins) -> None:
    """Uma linha de auditoria por dispositivo que mudou de estado.

    O nome do evento leva o id do plugin, então o UDR7 continua gravando
    `udr7_protection_state` — o que os testes e o operador já conhecem.
    """
    for plugin in plugins:
        transition = plugin.drain_transition()
        if transition is not None:
            _log("WARN", f"{plugin.id}_protection_state",
                 plugin=plugin.id, de=transition[0], para=transition[1])


def _observe_guarded(plugin, chamada, shared, history) -> None:
    """Um dispositivo doente não pode cegar os outros nem matar o vigia.

    A exceção vira registro (`tick_failed`) e um campo próprio no health, separado
    do erro do UPS; o resto do ciclo — os demais dispositivos, a lista, o snapshot,
    o histórico — continua. Só `Exception`: interrupção do usuário passa.
    """
    try:
        _emit(chamada(), shared, history, log=_log)
    except Exception as exc:  # tick_failed: o vigia continua
        motivo = f"{plugin.id}: {type(exc).__name__}: {exc}"
        _log("ERROR", "tick_failed", plugin=plugin.id, tipo=type(exc).__name__, reason=str(exc))
        if shared is not None:
            shared.record_tick_error(motivo)


def _handle_poll_failure(exc: Exception, tracker, plugins, shared, history) -> None:
    events = tracker.observe_failure()
    _record_tracker_events(events, lambda _e: {"reason": str(exc)}, shared, history)
    for plugin in plugins:
        _observe_guarded(plugin, lambda p=plugin: p.observe_failure(events), shared, history)
    _audit_plugins(plugins)
    if shared is not None:
        shared.record_failure(str(exc))
        # A lista de dispositivos é CONFIGURAÇÃO: ela não some porque o UPS calou.
        # Sem esta linha, uma queda do NUT esvaziava o `plugins` do health e o app
        # (e a contagem do instalador) passavam a dizer "nenhum dispositivo".
        shared.set_plugins(plugin_statuses(plugins))  # mantém na falha


def _process_snapshot(snap: UpsSnapshot, tracker, plugins, shared, history) -> None:
    """One good poll: tracker events -> every plugin -> state/history/log."""
    snap_dict = snap.to_dict()
    events = tracker.observe(snap)
    _record_tracker_events(
        events, lambda _e: {"state": snap.state, "charge": snap.charge_percent}, shared, history)
    for plugin in plugins:
        _observe_guarded(plugin, lambda p=plugin: p.observe(snap, events), shared, history)
    if plugins and shared is not None:
        shared.set_plugins(plugin_statuses(plugins))
    _audit_plugins(plugins)
    if shared is not None:
        shared.update_snapshot(snap_dict)
    if history is not None:
        history.record_sample(snap_dict)
    _log("INFO", "state", **snap_dict)


def run_loop(cfg: BridgeConfig, *, once: bool = False, env_path: str = "",
             clock=time.monotonic) -> int:
    tracker = TransitionTracker(cfg)
    last_prune = float("-inf")

    # Cada instância traz o próprio holder e a própria política; `--once` é
    # diagnóstico e não constrói nenhuma (nem lê nem escreve a loja).
    store = None
    plugins = PluginSet()
    if not once:
        store = DeviceStore(os.path.join(state_dir(), "devices.json"))
        try:
            devices = store.load_or_migrate(lambda: legacy_instance(cfg))
            plugins = PluginSet(build_plugins(devices, cfg, state_dir()))
        except DevicesError as exc:
            # Mesma classe do config_invalid: repetiria a cada relançamento. Sob
            # launchd a parada é deliberada (exit 0); no CLI, 3 = validação.
            _log("ERROR", "devices_invalid", reason=str(exc))
            _log("ERROR", "parada_deliberada", reason="loja de dispositivos inválida não relança")
            return EXIT_OK if os.environ.get("RUB_LAUNCHD") == "1" else EXIT_VALIDATION
        # A loja vence: a instância migrada `udr7` é copiada para o cfg em memória
        # (GET /v1/config diz a verdade); o .env NÃO é reescrito no boot.
        for plugin in plugins:
            if plugin.id == "udr7" and hasattr(plugin, "instance"):
                shadowed = apply_instance_to_cfg(plugin.instance, cfg)
                if shadowed:
                    _log("INFO", "legacy_key_shadowed", keys=sorted(shadowed))

    api_server = None
    shared = None
    history = None
    restart_requested = threading.Event()
    if not once and cfg.ui_api_enabled:
        # Lazy import: aiohttp only loads when the API is actually enabled.
        from .api import ApiServer
        from .history import HistoryStore
        from .state import SharedState

        shared = SharedState()
        history = HistoryStore(
            os.path.join(state_dir(), "history.sqlite"), cfg.history_retention_days,
            on_error=_log,
        )
        api_server = ApiServer(
            cfg, shared, history, env_path, restart_cb=restart_requested.set,
            plugins=plugins, store=store, state_dir=state_dir(),
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
        # O health nasce com os dispositivos: antes desta linha a lista só existia
        # depois da 1.ª leitura boa do UPS, e o app subia dizendo "nenhum
        # dispositivo protegido" com o River desligado (medido no Mac mini).
        shared.set_plugins(plugin_statuses(plugins))  # desde o boot

    while True:
        try:
            snap = poll_once(cfg)
            _completa_pela_serial(snap, cfg)
        except NutError as exc:
            _handle_poll_failure(exc, tracker, plugins, shared, history)
            if once:
                _log("ERROR", "poll_failed", reason=str(exc))
                return EXIT_CONNECTION
        else:
            _process_snapshot(snap, tracker, plugins, shared, history)
            if once:
                return EXIT_OK
        # "Manter histórico: N dias" era só um número na tela: a limpeza existia e
        # nunca era chamada. Roda no 1.º ciclo e a cada hora, e acompanha a
        # configuração quando ela muda a quente.
        if history is not None and clock() - last_prune >= PRUNE_INTERVAL_SECONDS:
            last_prune = clock()
            history.retention_days = cfg.history_retention_days
            history.prune()  # retenção
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
