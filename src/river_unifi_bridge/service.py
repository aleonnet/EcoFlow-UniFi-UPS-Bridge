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
import signal
import sys
import threading
import time

from . import __version__
from .config import BridgeConfig, ConfigError, load_config, recusa_do_vigia_espelho
from .devices import DeviceStore, DevicesError
from .localtoken import state_dir
from .model import UpsSnapshot, snapshot_from_nut_vars
from . import river_serial
from .cabo_automatico import CaboAutomatico
from .nut_supervisor import NutSupervisor
from .nut_comandos import (
    ExecutorDeComandos, comandos_do_dispositivo, comandos_do_river)
from .nut_servico import PonteDoNut
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

# Onde ficam os soquetes pelos quais o servidor do no-break fala com os drivers.
# É o mesmo seam do prefixo do NUT: sem ele, uma cena do portão criaria soquetes
# na instalação REAL de quem roda a suíte.
ESTADO_DO_NUT = "/opt/homebrew/var/state/ups"
# E onde mora a configuração dele. O serviço só reescreve o trecho entre as
# marcas do River Bridge; o resto do arquivo é do dono (ver nut_conf.py).
ETC_DO_NUT = "/opt/homebrew/etc/nut"

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
# Quando a última varredura completa aconteceu. Sem isto, uma máquina sem River
# abriria todas as portas seriais a cada ciclo, para nada.
_ultima_varredura: float = float("-inf")
VARREDURA_INTERVALO_SEGUNDOS = 300
# Última leitura boa da porta serial, e quando ela chegou. Uma leitura que falha
# num ciclo não pode APAGAR o consumo da tela: sem isto, o bloco "consumo por
# tomada" aparecia e sumia a cada ciclo em que a porta não respondia (visto pelo
# dono no Mac mini, 2026-09-04). O valor mostrado continua sendo uma leitura de
# verdade, no máximo alguns segundos mais velha — passado esse prazo, some.
_ultima_leitura_serial: tuple[object, str, float] | None = None
SERIAL_VALIDADE_SEGUNDOS = 10.0


def _leitura_serial_recente(clock):
    """A última leitura boa, enquanto ela ainda for recente — senão, nada.

    Serve para o consumo por tomada não piscar na tela quando um ciclo falha.
    Passado o prazo, devolve `None` e a tela mostra ausência, não número velho.
    """
    if _ultima_leitura_serial is None:
        return None
    leitura, porta, quando = _ultima_leitura_serial
    if clock() - quando > SERIAL_VALIDADE_SEGUNDOS:
        return None
    return leitura, porta


def _completa_pela_serial(snap: UpsSnapshot, cfg: BridgeConfig, ler=river_serial.ler,
                          clock=time.monotonic) -> None:
    """Preenche consumo e tomadas pela porta serial do aparelho, quando ela existe.

    O perfil de no-break do River 3 Plus não publica potência (medido; ver
    `docs/decisions/2026-09-04-0110-…`). A segunda porta do mesmo cabo publica, e
    as duas convivem. Falha aqui **não** é falha de leitura do UPS: o ciclo segue
    com o que o NUT deu, e os campos ficam nulos, que é a verdade.
    """
    global _porta_serial_lembrada, _ultima_varredura, _ultima_leitura_serial
    if not cfg.river_serial_enabled:
        return
    escolhida = cfg.river_serial_port or "auto"
    porta = escolhida
    if escolhida == "auto" and _porta_serial_lembrada:
        porta = _porta_serial_lembrada
    # Varrer todas as portas do Mac é caro; só acontece de tempos em tempos.
    pode_varrer = clock() - _ultima_varredura >= VARREDURA_INTERVALO_SEGUNDOS
    try:
        if porta == "auto" and not pode_varrer:
            return
        if porta == "auto":
            _ultima_varredura = clock()
        resultado = ler(porta, serie_esperada=snap.serial or None)
        if resultado is None and porta != "auto" and escolhida == "auto" and pode_varrer:
            # A porta lembrada calou (cabo trocado de lugar): procura de novo.
            _ultima_varredura = clock()
            _porta_serial_lembrada = None
            resultado = ler("auto", serie_esperada=snap.serial or None)
    except Exception as exc:  # serial_read_failed: o vigia não depende disto
        _log("WARN", "serial_read_failed", reason=f"{type(exc).__name__}: {exc}")
        resultado = None
    if resultado is None:
        resultado = _leitura_serial_recente(clock)
        if resultado is None:
            return
    else:
        _ultima_leitura_serial = (resultado[0], resultado[1], clock())
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
        # O ESTADO de cada dispositivo muda quando o UPS cala (a política passa a
        # "cega"), e é este ponto que republica a lista com esse estado novo. A
        # lista em si nunca é esvaziada por ninguém — dizer que ela "sumia na
        # falha" era enunciado errado meu, corrigido depois da revisão fria.
        # Sem esta linha, a tela continuaria mostrando o estado ANTERIOR à queda.
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


def _registrador(shared, history):
    """Uma ordem destrutiva tem de aparecer na LINHA DO TEMPO, não só no registro.

    Quem manda pelo Home Assistant não vê o registro do sistema; quem abre o app
    depois precisa achar ali o que aconteceu com o aparelho dele.
    """
    def registrar(evento: str, detalhe: str) -> None:
        if shared is not None:
            shared.add_event(evento, {"detail": detalhe})
        if history is not None:
            history.record_event(evento, detalhe)

    return registrar


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
        # A mesma cerca do arquivo, agora com a lista de dispositivos na mão: o
        # nome de um deles também é aparelho publicado por nós, e a proteção não
        # pode ler o que ela mesma escreve. No arquivo isto não dava para conferir
        # — os dispositivos vivem na loja, não no `.env` (revisão fria da 0.7.0).
        recusa = recusa_do_vigia_espelho(
            cfg.nut_ups, cfg.river_nut_aparelho, publica=cfg.river_nut_publica,
            dispositivos={plugin.id for plugin in plugins})
        if recusa is not None:
            _log("ERROR", "config_invalid", reason=recusa)
            _log("ERROR", "parada_deliberada",
                 reason="a proteção leria um aparelho publicado por nós")
            return EXIT_OK if os.environ.get("RUB_LAUNCHD") == "1" else EXIT_VALIDATION
        for plugin in plugins:
            if plugin.id == "udr7" and hasattr(plugin, "instance"):
                shadowed = apply_instance_to_cfg(plugin.instance, cfg)
                if shadowed:
                    _log("INFO", "legacy_key_shadowed", keys=sorted(shadowed))

    api_server = None
    shared = None
    history = None
    restart_requested = threading.Event()
    # O leitor do River passa a ser filho DESTE serviço: sobe no boot junto com
    # ele (que é do sistema), para e volta sem senha, e nasce com nome próprio,
    # fora da mira do `pkill -9 usbhid-ups` que o app do fabricante roda como
    # root. Ver nut_supervisor.py para as três medições que levaram a isto.
    supervisor = None
    if not once and cfg.river_nut_managed:
        supervisor = NutSupervisor(cfg.nut_ups, log=_log)
        supervisor.iniciar()
    # A ponte também PUBLICA no NUT (ver nut_servico.py); ela nasce lá dentro do
    # `try`, depois da linha do tempo existir — as ordens que chegam pelo NUT
    # entram nela como as da tela. O mesmo vale para o cabo automático, cujo
    # aviso é a única coisa que o dono vê da troca.
    ponte = None
    cabo = None
    # O `finally` abaixo é o que impede leitor órfão: o launchd manda SIGTERM ao
    # atualizar ou ao desligar a máquina (o `main` converte o sinal em
    # interrupção), e sem ele os dois processos do no-break ficavam com o cabo.
    # Tudo o que vem depois de o leitor existir corre DENTRO do `try`: as
    # saídas daqui até o laço (porta ocupada, histórico que não abre) voltavam
    # sem passar pelo `finally` e deixavam os dois processos do no-break vivos,
    # sem pai, COM O CABO — o serviço seguinte não conseguia abrir o aparelho
    # (revisão fria da 0.5.0, 2.ª rodada: reproduzido com a porta tomada).
    try:
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
                supervisor=supervisor,
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

        # A ponte publica no NUT um aparelho com tudo o que ela sabe do River
        # (watts por tomada inclusive) e um por dispositivo protegido — é por aqui
        # que o Home Assistant recebe o mesmo que o app mostra. As ordens que
        # chegam por ali passam pelas MESMAS cercas da tela (nut_comandos.py).
        # Falhar aqui não derruba o serviço: publicar é um extra, e a proteção,
        # que é o motivo de ele existir, não depende disto.
        if not once and cfg.river_nut_publica:
            executor = ExecutorDeComandos(
                cfg, aparelho_do_river=cfg.river_nut_aparelho, plugins=plugins,
                state_dir=state_dir(), log=_log,
                registrar=_registrador(shared, history))
            ponte = PonteDoNut(
                aparelho=cfg.river_nut_aparelho,
                estado=os.environ.get("RUB_NUT_STATE") or ESTADO_DO_NUT,
                log=_log, executor=executor,
                comandos_do_river=comandos_do_river(cfg),
                comandos_do_dispositivo=lambda plugin: comandos_do_dispositivo(plugin, cfg),
                ups_conf=os.path.join(
                    os.environ.get("RUB_NUT_ETC") or ETC_DO_NUT, "ups.conf"),
                # Aparelho que entra ou sai precisa de um servidor que releia a
                # configuração. Só o SERVIDOR reinicia: o leitor de fábrica é
                # quem segura o cabo do River, e derrubá-lo por causa de uma
                # linha deixaria a proteção cega por segundos.
                ao_mudar_a_declaracao=(
                    supervisor.reiniciar_servidor if supervisor is not None
                    else (lambda: None)))
            ponte.iniciar()

        # O cabo do River é um só, e o aplicativo do fabricante também o quer.
        # Ligado, o serviço larga quando aquele aplicativo abre e retoma quando
        # ele fecha — sem botão nenhum, só o aviso na tela. Com proteção armada,
        # não larga: seria ficar cego para a queda justamente com o desligamento
        # automático ligado.
        if supervisor is not None and cfg.river_cabo_automatico:
            cabo = CaboAutomatico(
                supervisor, log=_log,
                avisar=_registrador(shared, history),
                ha_protecao_armada=lambda: any(p.armed for p in plugins))

        while True:
            try:
                snap = poll_once(cfg)
            except NutError as exc:
                _handle_poll_failure(exc, tracker, plugins, shared, history)
                # O no-break calou: quem lê pelo NUT precisa saber que o número
                # na tela dele envelheceu. Sem isto, o Home Assistant mostraria a
                # última carga como se fosse a de agora.
                if ponte is not None:
                    ponte.marcar_sem_dados()
                if once:
                    _log("ERROR", "poll_failed", reason=str(exc))
                    return EXIT_CONNECTION
            else:
                # A PROTEÇÃO decide primeiro, com o que o no-break disse. Só depois a
                # porta serial completa consumo e tomadas, e o estado é republicado.
                # Ordem invertida, a leitura serial atrasaria em segundos o laço que
                # decide desligar aparelhos (revisão fria, 2.ª rodada).
                _process_snapshot(snap, tracker, plugins, shared, history)
                _completa_pela_serial(snap, cfg)
                if snap.serial_port_read and shared is not None:
                    shared.update_snapshot(snap.to_dict())
                    if history is not None:
                        history.record_sample(snap.to_dict())
                # Publicar vem DEPOIS da proteção e da porta serial: antes, o
                # Home Assistant receberia a leitura sem os watts por tomada, que
                # é justamente o que ele não tinha antes desta versão.
                if ponte is not None:
                    ponte.atualizar(snap, plugins)
                if once:
                    return EXIT_OK
            # "Manter histórico: N dias" era só um número na tela: a limpeza existia e
            # nunca era chamada. Roda no 1.º ciclo e a cada hora, e acompanha a
            # configuração quando ela muda a quente.
            # Leitor que morre e não volta é pior que leitor que nunca subiu: a tela
            # continuaria com a última leitura e ninguém avisaria.
            if cabo is not None:
                cabo.vigiar()
            if supervisor is not None:
                supervisor.vigiar()
            if history is not None and clock() - last_prune >= PRUNE_INTERVAL_SECONDS:
                last_prune = clock()
                history.retention_days = cfg.history_retention_days
                history.prune()  # retenção
            if restart_requested.wait(timeout=cfg.poll_interval_seconds):
                # §7A.3 contract: deliberate restart exits 75; launchd
                # (KeepAlive={SuccessfulExit: false}) relaunches us.
                _log("INFO", "restart_requested", exit_code=EXIT_RESTART_REQUESTED)
                return EXIT_RESTART_REQUESTED
    finally:
        if ponte is not None:
            ponte.encerrar()
        if supervisor is not None:
            supervisor.encerrar()


def _sinal_de_termino(_sinal, _quadro) -> None:
    """SIGTERM vira interrupção: o mesmo caminho de saída do Ctrl-C."""
    raise KeyboardInterrupt


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

    # O launchd pede a saída com SIGTERM (ao atualizar, ao desligar a máquina).
    # Sem tratá-lo, o processo morria na hora e os dois processos do NUT ficavam
    # órfãos COM O CABO — o serviço seguinte não conseguia abrir o aparelho.
    # Traduzido para interrupção, ele passa pelo `finally` do laço, que os leva
    # junto.
    signal.signal(signal.SIGTERM, _sinal_de_termino)
    try:
        return run_loop(cfg, once=args.once, env_path=args.env)
    except KeyboardInterrupt:
        _log("INFO", "stopped", reason="pedido de encerramento")
        return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
