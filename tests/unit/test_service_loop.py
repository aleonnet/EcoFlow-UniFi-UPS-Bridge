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


def test_run_loop_builds_registered_plugins(tmp_path, monkeypatch):
    """run_loop constrói o REGISTRO, com a config e o diretório de estado certos.

    Mecanismo de término: `once=False` só sai por restart_requested, então o
    plugin injetado levanta uma sentinela no primeiro observe.
    """
    class Sentinela(Exception):
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
