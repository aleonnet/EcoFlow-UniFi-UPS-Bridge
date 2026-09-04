"""Fase 3'-EXP wiring fences: the loop feeds the policy (success and failure paths),
`--once` never builds a policy, and the audit line follows state transitions."""

import json
import os

import pytest

from river_unifi_bridge import service
from river_unifi_bridge.config import BridgeConfig
from river_unifi_bridge.history import HistoryStore
from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.nut import NutError
from river_unifi_bridge.protect import (
    EV_BLIND, EV_DRYRUN, ConfigHolder, ProtectionConfig, ProtectionPolicy,
)
from river_unifi_bridge.service import (
    TransitionTracker, _handle_poll_failure, _process_snapshot, run_loop,
)
from river_unifi_bridge.state import SharedState


def make_cfg(**over):
    base = dict(river_name="r", nut_host="127.0.0.1", nut_port=3493, nut_ups="r",
                power_loss_delay_seconds=0, protect_udr7=True, protect_dry_run=True,
                udr7_cutoff_percent=10, udr7_shutdown_percent=20, udr7_confirm_seconds=0)
    base.update(over)
    return BridgeConfig(**base)


class Clock:
    now = 100.0

    def __call__(self):
        return self.now


def sim_snap(status="OB DISCHRG", charge="12"):
    return snapshot_from_nut_vars("r", {
        "ups.status": status, "battery.charge": charge, "battery.charge.low": "10",
        "device.serial": "SIM0001", "driver.name": "fake-nut-ups", "driver.version": "fake-nut-ups",
    })


@pytest.fixture
def rig(tmp_path):
    cfg = make_cfg()
    clock = Clock()
    holder = ConfigHolder(ProtectionConfig.from_cfg(cfg))
    policy = ProtectionPolicy(
        holder, clock=clock, runner=lambda *a, **k: None, keygen_runner=lambda *a, **k: None,
        wol_sender=lambda m: None,
        known_hosts_path=str(tmp_path / "kh"), armed_path=str(tmp_path / "armed.json"),
        runtime_path=str(tmp_path / "runtime.json"),
    )
    from river_unifi_bridge.plugins import Udr7SshPlugin
    from river_unifi_bridge.plugins.udr7_ssh import legacy_instance

    plugin = Udr7SshPlugin(legacy_instance(cfg), holder, policy, cfg)
    return dict(cfg=cfg, clock=clock, tracker=TransitionTracker(cfg, clock), policy=policy,
                plugin=plugin, plugins=[plugin],
                shared=SharedState(), history=HistoryStore(str(tmp_path / "h.sqlite")))


def test_process_snapshot_drives_policy_state_and_history(rig, capsys):
    _process_snapshot(sim_snap(), rig["tracker"], rig["plugins"], rig["shared"], rig["history"])
    events = [e["event"] for e in rig["shared"].events()]
    assert events == ["POWER_LOSS", "LOW_BATTERY", EV_DRYRUN]      # tracker then policy
    health = rig["shared"].health()
    assert health["udr7"] == "fonte_nao_real"
    assert health["udr7_detail"]["dry_run"] is True
    assert health["udr7_detail"]["source_detail"] == "telemetria_sintetica"
    # A lista de dispositivos e o alias descrevem o mesmo elo — nó da cena S4n.
    assert health["plugins"][0]["id"] == "udr7"
    assert health["plugins"][0]["state"] == health["udr7"]
    assert health["plugins"][0]["detail"] == health["udr7_detail"]
    types = [r["type"] for r in rig["history"].query_events(0, 2**33)]
    assert EV_DRYRUN in types
    out = capsys.readouterr().out
    audit = [json.loads(l) for l in out.splitlines() if '"udr7_protection_state"' in l]
    assert audit and audit[0]["para"] == "fonte_nao_real"
    assert audit[0]["plugin"] == "udr7"          # a linha de auditoria nomeia o dispositivo
    assert any('"UDR7_SHUTDOWN_DRYRUN"' in l for l in out.splitlines())


def test_run_loop_feeds_policy_on_comm_failure(rig):
    _process_snapshot(sim_snap(charge="50"), rig["tracker"], rig["plugins"], rig["shared"], rig["history"])
    rig["clock"].now += 30
    _handle_poll_failure(NutError("upsd fora"), rig["tracker"], rig["plugins"], rig["shared"], rig["history"])
    events = [e["event"] for e in rig["shared"].events()]
    assert events[-2:] == ["COMM_LOST", EV_BLIND]
    assert rig["shared"].health()["nut"] == "falha"


def test_process_snapshot_without_plugins_or_state(rig):
    # `--once` / API desligada: lista VAZIA de plugins e shared None, inócuos.
    _process_snapshot(sim_snap(), rig["tracker"], [], None, None)
    _handle_poll_failure(NutError("x"), rig["tracker"], [], None, None)


def test_once_never_protects(tmp_path, monkeypatch):
    """`--once` é diagnóstico: nenhum plugin é construído, logo nada protege."""
    built = []

    def boom(devices, cfg, state_dir):
        built.append(1)
        raise AssertionError("nenhum plugin pode existir em --once")

    monkeypatch.setattr(service, "build_plugins", boom)
    monkeypatch.setattr(service, "poll_once", lambda cfg: sim_snap("OL CHRG", "80"))
    monkeypatch.setenv("RUB_STATE_DIR", str(tmp_path))
    assert run_loop(make_cfg(), once=True) == service.EXIT_OK
    assert built == []
    assert not (tmp_path / "devices.json").exists()     # --once nem lê nem escreve a loja


def test_loop_feeds_every_plugin_and_health_lists_both(rig):
    """O laço alimenta TODOS os plugins, não só o primeiro."""
    from fake_plugin import FakePlugin

    fake = FakePlugin()
    plugins = [rig["plugin"], fake]
    _process_snapshot(sim_snap(), rig["tracker"], plugins, rig["shared"], rig["history"])
    assert len(fake.observed) == 1
    ids = [p["id"] for p in rig["shared"].health()["plugins"]]
    assert ids == ["udr7", "fake"]


def test_health_lists_devices_before_first_poll(tmp_path, monkeypatch):
    """O health publica os dispositivos ANTES da primeira leitura do UPS.

    A asserção corre dentro do `poll_once` monkeypatchado, na 1.ª chamada: nesse
    instante nenhum tick rodou e nenhum caminho de falha passou, então a lista só
    pode ter vindo da linha do boot. Sem ela, o app subia com o River desligado
    dizendo "nenhum dispositivo protegido" (medido no Mac mini).
    """
    class Terminador(BaseException):     # BaseException: nenhum `except Exception` a apara
        pass

    visto = {}

    class Servidor:
        def __init__(self, cfg, shared, *a, **k):
            visto["shared"] = shared

        def start_in_thread(self):
            return None

    def olha_e_para(_cfg):
        visto["health"] = visto["shared"].health()
        raise Terminador()

    from river_unifi_bridge import api as api_mod

    cfg = make_cfg()
    cfg.ui_api_enabled = True
    monkeypatch.setattr(api_mod, "ApiServer", Servidor)
    monkeypatch.setattr(service, "poll_once", olha_e_para)
    monkeypatch.setenv("RUB_STATE_DIR", str(tmp_path))
    with pytest.raises(Terminador):
        run_loop(cfg, once=False)
    plugins = visto["health"]["plugins"]
    assert [p["id"] for p in plugins] == ["udr7"]
    assert visto["health"]["udr7"] == plugins[0]["state"]


def test_health_keeps_devices_when_the_ups_goes_quiet(rig):
    """A falha de leitura não apaga a lista: ela é configuração, não telemetria."""
    _process_snapshot(sim_snap(), rig["tracker"], rig["plugins"], rig["shared"], rig["history"])
    assert len(rig["shared"].health()["plugins"]) == 1
    _handle_poll_failure(NutError("upsd caiu"), rig["tracker"], rig["plugins"],
                         rig["shared"], rig["history"])
    health = rig["shared"].health()
    assert [p["id"] for p in health["plugins"]] == ["udr7"]
    assert health["nut"] == "falha"


def test_run_loop_builds_registered_plugins(tmp_path, monkeypatch):
    """run_loop constrói o REGISTRO, com a config e o diretório de estado certos.

    Mecanismo de término: `once=False` só sai por restart_requested, então o
    plugin injetado levanta uma sentinela no primeiro observe. Ela é `BaseException`
    porque a rede de proteção do laço apara `Exception` — o vigia não pode morrer
    por um defeito de um dispositivo.
    """
    class Sentinela(BaseException):
        pass

    class Explode:
        id = "explode"

        def observe(self, *a, **k):
            raise Sentinela()

    visto = {}

    def fake_build(devices, cfg, state_dir):
        visto["devices"] = devices
        visto["cfg"] = cfg
        visto["state_dir"] = state_dir
        return [Explode()]

    cfg = make_cfg()
    cfg.ui_api_enabled = False
    monkeypatch.setattr(service, "build_plugins", fake_build)
    monkeypatch.setattr(service, "poll_once", lambda c: sim_snap("OL CHRG", "80"))
    monkeypatch.setenv("RUB_STATE_DIR", str(tmp_path))
    with pytest.raises(Sentinela):
        run_loop(cfg, once=False)
    assert visto["cfg"] is cfg
    assert visto["state_dir"] == str(tmp_path)
    # A loja foi migrada do .env no boot: uma instância `udr7`, e o arquivo existe.
    assert [d.id for d in visto["devices"]] == ["udr7"]
    assert (tmp_path / "devices.json").exists()


def test_loop_survives_plugin_exception(rig, capsys):
    """Um dispositivo doente não mata o vigia nem cega os outros.

    O erro é de SOFTWARE, não do UPS: vira `tick_failed` no log e `last_tick_error`
    no health; a leitura do NUT continua boa (`nut` fica `ok`) e o snapshot é
    publicado. Sem a rede, a exceção subia pelo laço e derrubava o serviço.
    """
    from fake_plugin import FakePlugin

    class Doente(FakePlugin):
        def observe(self, snap, tracker_events):
            raise RuntimeError("cabo solto")

    doente = Doente()
    doente.id = "doente"
    sadio = FakePlugin()
    _process_snapshot(sim_snap(), rig["tracker"], [doente, sadio], rig["shared"], rig["history"])

    assert len(sadio.observed) == 1                    # o segundo dispositivo rodou
    health = rig["shared"].health()
    assert "RuntimeError" in health["last_tick_error"]
    assert "cabo solto" in health["last_tick_error"]
    assert health["nut"] == "ok"                       # o UPS respondeu: não é falha dele
    assert health["last_error"] is None
    assert health["has_snapshot"] is True
    assert [p["id"] for p in health["plugins"]] == ["doente", "fake"]
    linhas = [json.loads(l) for l in capsys.readouterr().out.splitlines()
              if '"tick_failed"' in l]
    assert linhas and linhas[0]["plugin"] == "doente" and linhas[0]["tipo"] == "RuntimeError"


def test_loop_survives_plugin_exception_on_the_failure_path(rig):
    """A rede também cobre o caminho da falha de leitura."""
    from fake_plugin import FakePlugin

    class Doente(FakePlugin):
        def observe_failure(self, tracker_events):
            raise RuntimeError("cabo solto")

    doente = Doente()
    doente.id = "doente"
    sadio = FakePlugin()
    _handle_poll_failure(NutError("upsd fora"), rig["tracker"], [doente, sadio],
                         rig["shared"], rig["history"])
    assert len(sadio.observed) == 1
    health = rig["shared"].health()
    assert "cabo solto" in health["last_tick_error"]
    assert health["nut"] == "falha"          # esse sim é erro do UPS, e continua sendo


def test_history_write_failure_is_not_a_tick_error(rig, capsys):
    """Base bloqueada: aviso e o ciclo segue; não é erro do vigia nem do UPS."""
    import sqlite3

    from river_unifi_bridge.history import HistoryStore

    avisos = []
    history = HistoryStore(str(rig["history"].path) + "2",
                           on_error=lambda level, event, **p: avisos.append((event, p)))

    def travada(*_a, **_k):
        raise sqlite3.OperationalError("database is locked")

    history._connect = travada
    _process_snapshot(sim_snap(), rig["tracker"], rig["plugins"], rig["shared"], history)
    history.prune()

    health = rig["shared"].health()
    assert health["last_tick_error"] is None      # gravar histórico não é vigiar
    assert health["nut"] == "ok"
    assert health["has_snapshot"] is True         # o ciclo terminou inteiro
    assert {e for e, _ in avisos} == {"history_write_failed"}
    assert {p["op"] for _, p in avisos} == {"record_sample", "record_event", "prune"}


def test_loop_prunes_history_hourly(tmp_path, monkeypatch):
    """A retenção configurada passa a ser verdade: limpa no boot e a cada hora."""
    class Terminador(BaseException):
        pass

    relogio = {"agora": 0.0}
    podas = []

    class Servidor:
        def __init__(self, cfg, shared, *a, **k):
            pass

        def start_in_thread(self):
            return None

    voltas = {"n": 0}

    def anda(_cfg):
        voltas["n"] += 1
        if voltas["n"] == 1:
            return sim_snap("OL CHRG", "80")      # 1.ª poda: o boot
        if voltas["n"] == 2:
            relogio["agora"] += 3601              # passou uma hora
            return sim_snap("OL CHRG", "80")      # 2.ª poda
        raise Terminador()

    from river_unifi_bridge import api as api_mod
    from river_unifi_bridge.history import HistoryStore

    real_prune = HistoryStore.prune

    def espia(self):
        podas.append(self.retention_days)
        return real_prune(self)

    monkeypatch.setattr(HistoryStore, "prune", espia)
    monkeypatch.setattr(api_mod, "ApiServer", Servidor)
    monkeypatch.setattr(service, "poll_once", anda)
    monkeypatch.setenv("RUB_STATE_DIR", str(tmp_path))
    cfg = make_cfg(poll_interval_seconds=0)
    cfg.ui_api_enabled = True
    cfg.history_retention_days = 3
    with pytest.raises(Terminador):
        run_loop(cfg, once=False, clock=lambda: relogio["agora"])
    # Uma poda no boot e outra na volta seguinte à hora cheia, com a retenção viva.
    assert podas == [3, 3]


def test_prune_does_not_run_every_tick(tmp_path, monkeypatch):
    """Sem uma hora entre as voltas, a limpeza não repete: é retenção, não varredura."""
    class Terminador(BaseException):
        pass

    podas = []
    voltas = {"n": 0}

    class Servidor:
        def __init__(self, cfg, shared, *a, **k):
            pass

        def start_in_thread(self):
            return None

    def anda(_cfg):
        voltas["n"] += 1
        if voltas["n"] >= 3:
            raise Terminador()
        return sim_snap("OL CHRG", "80")

    from river_unifi_bridge import api as api_mod
    from river_unifi_bridge.history import HistoryStore

    monkeypatch.setattr(HistoryStore, "prune", lambda self: podas.append(1))
    monkeypatch.setattr(api_mod, "ApiServer", Servidor)
    monkeypatch.setattr(service, "poll_once", anda)
    monkeypatch.setenv("RUB_STATE_DIR", str(tmp_path))
    cfg = make_cfg(poll_interval_seconds=0)
    cfg.ui_api_enabled = True
    with pytest.raises(Terminador):
        run_loop(cfg, once=False, clock=lambda: 0.0)
    assert podas == [1]
