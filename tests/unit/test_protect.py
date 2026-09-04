"""Fase 3'-EXP — fences of the UDR7 protection policy (property M1).

Every test here runs with the anti-spawn fixture (tests/unit/conftest.py). The
gate's mutation scenes S4c/S4d/S4f/S4h/S4i/S4k select nodes from this file: their
fixtures are FULLY ARMED and real-looking so that only the mutated fence decides.
"""

from __future__ import annotations

import json
import pathlib
import os
import re
import shutil
import subprocess
from dataclasses import replace

import pytest

from river_unifi_bridge import protect
from river_unifi_bridge.config import BridgeConfig
from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.plugins.udr7_ssh import POWEROFF
from river_unifi_bridge.protect import (
    EV_ARMED, EV_BLIND, EV_BLOCKED, EV_DISARMED, EV_DRYRUN, EV_FAILED, EV_REARMED,
    EV_SENT, EV_WOL_DRYRUN, EV_WOL_SENT, SUBPROCESS_TIMEOUT_SECONDS,
    ConfigHolder, ProtectionConfig, ProtectionPolicy, known_host_ok, source_verdict,
    ssh_argv,
)

REAL_SERIAL = "R3P-TEST-0001"
# O comando é do aparelho: vem da tabela do plugin do UDR7, com fonte por linha.
POWEROFF_COMMAND = POWEROFF.argv


# --- helpers ------------------------------------------------------------------
class FakeClock:
    def __init__(self, now: float = 1000.0) -> None:
        self.now = now

    def __call__(self) -> float:
        return self.now


class Result:
    def __init__(self, returncode: int = 0, stderr: bytes = b"") -> None:
        self.returncode = returncode
        self.stderr = stderr
        self.stdout = b""


class Spy:
    """Counts only real ssh invocations (argv[0] == the configured binary)."""

    def __init__(self, returncode: int = 0, stderr: bytes = b"", raise_timeout: bool = False):
        self.calls: list[list[str]] = []
        self.returncode = returncode
        self.stderr = stderr
        self.raise_timeout = raise_timeout

    def __call__(self, argv, **kwargs):
        assert argv[0] == protect.SSH_BINARY, argv[0]
        self.calls.append(list(argv))
        if self.raise_timeout:
            raise subprocess.TimeoutExpired(argv, kwargs.get("timeout", 0))
        return Result(self.returncode, self.stderr)


class FakeKeygen:
    def __init__(self, returncode: int = 0) -> None:
        self.calls: list[list[str]] = []
        self.returncode = returncode

    def __call__(self, argv, **kwargs):
        self.calls.append(list(argv))
        return Result(self.returncode)


def make_cfg(**over) -> BridgeConfig:
    base = dict(river_name="r", nut_host="127.0.0.1", nut_port=3493, nut_ups="r")
    base.update(over)
    return BridgeConfig(**base)


def make_pc(**over) -> ProtectionConfig:
    return ProtectionConfig.from_cfg(make_cfg(**over))


def real_vars(**over) -> dict[str, str]:
    base = {
        "ups.status": "OB DISCHRG", "battery.charge": "8", "battery.runtime": "600",
        "battery.charge.low": "10", "device.mfr": "EcoFlow", "device.model": "RIVER 3 Plus",
        "device.serial": REAL_SERIAL, "driver.name": "usbhid-ups", "driver.version": "2.8.4",
    }
    base.update(over)
    return base


def snap(**over):
    return snapshot_from_nut_vars("r", real_vars(**over))


@pytest.fixture
def key_file(tmp_path):
    key = tmp_path / "river-bridge-udr7"
    key.write_text("PRIVATE KEY (fake)\n")
    key.chmod(0o600)
    return str(key)


@pytest.fixture
def paths(tmp_path):
    state = tmp_path / "state"
    return {
        "known_hosts_path": str(state / "udr7_known_hosts"),
        "armed_path": str(state / "udr7_armed.json"),
        "runtime_path": str(state / "udr7_runtime.json"),
    }


def armed_overrides(key_file, **extra) -> dict:
    """Config that passes every gate: real-looking source, loopback NUT, thresholds,
    key, host — armed (dry-run off)."""
    base = dict(
        protect_udr7=True, protect_dry_run=False, udr7_arm_allowed=False,
        udr7_ssh_host="192.0.2.1", udr7_ssh_port=22, udr7_ssh_user="root",
        udr7_ssh_key=key_file, udr7_expected_serial=REAL_SERIAL,
        udr7_cutoff_percent=10, udr7_shutdown_percent=20, udr7_min_outage_seconds=0,
        udr7_confirm_seconds=0, udr7_retry_max=3,
    )
    base.update(extra)
    return base


class Rig:
    """Holder + policy + fake runners, with helpers to arm and drive an outage."""

    def __init__(self, paths, cfg_over, *, spy=None, keygen=None, wol=None, clock=None):
        self.clock = clock or FakeClock()
        self.spy = spy if spy is not None else Spy()
        self.keygen = keygen if keygen is not None else FakeKeygen(0)
        self.wol_calls: list[str] = []
        self.holder = ConfigHolder(make_pc(**cfg_over))
        self.policy = ProtectionPolicy(
            self.holder, clock=self.clock, runner=self.spy, keygen_runner=self.keygen,
            wol_sender=wol if wol is not None else self.wol_calls.append,
            shutdown_command=POWEROFF_COMMAND, **paths,
        )
        self.paths = paths
        # A dedicated known_hosts exists by default; the (fake) keygen decides.
        # Tests about the absent file remove it explicitly.
        os.makedirs(os.path.dirname(paths["known_hosts_path"]), exist_ok=True)
        if not os.path.exists(paths["known_hosts_path"]):
            with open(paths["known_hosts_path"], "w") as fh:
                fh.write("192.0.2.1 ssh-ed25519 AAAAfake\n")

    def arm_file(self):
        """Write armed.json through the real transition (dry-run on -> off)."""
        pc = self.holder.get()
        old = replace(pc, protect_dry_run=True)
        return self.policy.on_config_applied(old, pc)

    def apply(self, **over):
        old = self.holder.get()
        new = replace(old, **over)
        self.holder.replace(new)
        return self.policy.on_config_applied(old, new)

    def outage(self, s=None):
        return self.policy.observe(s or snap(), ["POWER_LOSS"])

    def tick(self, s=None, events=()):
        return self.policy.observe(s or snap(), list(events))


def events_of(actions):
    return [a.event for a in actions]


def armed_rig(paths, key_file, **extra) -> Rig:
    rig = Rig(paths, armed_overrides(key_file, **extra))
    rig.arm_file()
    return rig


# --- the fixture itself -------------------------------------------------------
def test_fixture_forbids_spawn(paths, key_file):
    # A policy built WITHOUT an injected runner must hit the conftest seam.
    rig = Rig(paths, armed_overrides(key_file), spy=None)
    rig.policy._runner = None
    rig.arm_file()
    actions = rig.outage()
    assert events_of(actions) == [EV_FAILED]
    assert "spawn proibido" in actions[0].payload["error"]
    with pytest.raises(AssertionError, match="spawn proibido"):
        subprocess.run(["/bin/true"])
    with pytest.raises(AssertionError, match="spawn proibido"):
        protect._WOL_SENDER("aa:bb:cc:dd:ee:ff")


# --- argv / shape ---------------------------------------------------------------
def test_ssh_argv_is_isolated_and_terminated(paths, key_file):
    pc = make_pc(**armed_overrides(key_file, udr7_ssh_port=2222))
    argv = ssh_argv(pc, paths["known_hosts_path"], POWEROFF_COMMAND)
    assert argv[0] == protect.SSH_BINARY
    assert argv[-1] == POWEROFF_COMMAND
    assert argv[-2] == f"root@192.0.2.1"
    assert argv[-3] == "--"                      # options end BEFORE the destination
    opts = {argv[i + 1] for i, a in enumerate(argv) if a == "-o"}
    for required in (
        "BatchMode=yes", "StrictHostKeyChecking=yes", "IdentitiesOnly=yes",
        "PasswordAuthentication=no", "KbdInteractiveAuthentication=no",
        "ProxyCommand=none", "PermitLocalCommand=no", "ControlMaster=no",
        "ControlPath=none", "ForwardAgent=no", "ClearAllForwardings=yes",
        f"UserKnownHostsFile={paths['known_hosts_path']}", "GlobalKnownHostsFile=/dev/null",
    ):
        assert required in opts, required
    assert "-F" in argv and argv[argv.index("-F") + 1] == "/dev/null"
    assert argv[argv.index("-p") + 1] == "2222"
    assert argv[argv.index("-i") + 1] == key_file
    assert "-n" in argv and "-T" in argv


def test_user_or_host_with_option_prefix_is_rejected():
    from river_unifi_bridge.config import ConfigError, validate_update

    for key, bad in (
        ("UDR7_SSH_USER", "-oProxyCommand=/bin/echo"), ("UDR7_SSH_USER", "-E"),
        ("UDR7_SSH_USER", "-J"), ("UDR7_SSH_USER", "--"),
        ("UDR7_SSH_HOST", "-oProxyCommand=x"), ("UDR7_SSH_HOST", "--"),
    ):
        with pytest.raises(ConfigError):
            validate_update(key, bad)


# --- source fence --------------------------------------------------------------
def test_synthetic_source_blocks_even_when_armed(paths, key_file):
    rig = armed_rig(paths, key_file)
    fake = snap(**{"driver.name": "fake-nut-ups", "driver.version": "fake-nut-ups",
                   "device.serial": REAL_SERIAL})   # serial matches on purpose
    actions = rig.outage(fake)
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["detail"] == "fonte_nao_real"
    assert actions[0].payload["source_detail"] == "telemetria_sintetica"
    assert rig.spy.calls == []


def test_contract_fake_is_caught_by_denylist(paths, key_file):
    # Goes through observe() with the simulator's own BASE_VARS (+ a matching
    # registered serial would still not help: the driver name decides first).
    import importlib.machinery, importlib.util, pathlib
    path = str(pathlib.Path(__file__).parents[2] / "tools" / "fake-nut-ups")
    loader = importlib.machinery.SourceFileLoader("fake_nut_ups_contract", path)
    sim = importlib.util.module_from_spec(importlib.util.spec_from_loader("fake_nut_ups_contract", loader))
    loader.exec_module(sim)
    rig = armed_rig(paths, key_file, udr7_expected_serial="R3P-ANY")
    vars_ = {**sim.scenario_low_battery(60.0)}
    vars_["device.serial"] = "R3P-ANY"          # even a "registered" serial cannot help
    s = snapshot_from_nut_vars("r", vars_)
    actions = rig.outage(s)
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["source_detail"] == "telemetria_sintetica"
    assert rig.spy.calls == []


def test_nut_dummy_driver_is_caught(paths, key_file):
    rig = armed_rig(paths, key_file)
    for name in ("dummy-ups", "clone", "clone-outlet", "Dummy"):
        s = snap(**{"driver.name": name, "driver.version": "2.8.4"})
        actions = rig.outage(s)
        assert events_of(actions) == [EV_BLOCKED], name
        assert actions[0].payload["source_detail"] == "telemetria_sintetica", name
        rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])
    assert rig.spy.calls == []


def test_unknown_source_fail_closed(paths, key_file):
    rig = armed_rig(paths, key_file)
    actions = rig.outage(snap(**{"driver.name": ""}))
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["source_detail"] == "fonte_nao_verificada"
    assert source_verdict(None, "2.8.4", REAL_SERIAL, REAL_SERIAL) == "fonte_nao_verificada"
    assert source_verdict("usbhid-ups", None, REAL_SERIAL, REAL_SERIAL) == "fonte_nao_verificada"


def test_serial_missing_blocks(paths, key_file):
    rig = armed_rig(paths, key_file, udr7_expected_serial="")
    actions = rig.outage()
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["source_detail"] == "serial_nao_registrado"


def test_serial_mismatch_blocks(paths, key_file):
    rig = armed_rig(paths, key_file, udr7_expected_serial="R3P-OUTRA")
    actions = rig.outage()
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["source_detail"] == "serial_divergente"
    assert rig.spy.calls == []


def test_non_loopback_nut_blocks_when_armed(paths, key_file):
    # armed.json pins the SAME non-loopback host, so only the loopback gate decides.
    rig = armed_rig(paths, key_file, nut_host="192.168.1.13")
    actions = rig.outage()
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["detail"] == "fonte_nao_local"
    assert rig.spy.calls == []


def test_localhost_is_not_loopback(paths, key_file):
    rig = armed_rig(paths, key_file, nut_host="localhost")
    actions = rig.outage()
    assert actions[0].payload["detail"] == "fonte_nao_local"
    assert protect._is_loopback("127.0.0.1") and protect._is_loopback("::1")
    assert not protect._is_loopback("localhost") and not protect._is_loopback("127.0.0.2")


# --- cutoff / threshold ------------------------------------------------------------
def test_cutoff_or_threshold_unconfigured_blocks(paths, key_file):
    rig = armed_rig(paths, key_file, udr7_cutoff_percent=0)
    assert rig.outage()[0].payload["detail"] == "corte_nao_configurado"
    rig2 = armed_rig(paths, key_file, udr7_shutdown_percent=0)
    assert rig2.outage(snap(**{"battery.charge": "0"}))[0].payload["detail"] == "limiar_nao_configurado"


def test_threshold_at_or_below_cutoff_blocks(paths, key_file):
    for shutdown in (9, 10, 11):
        rig = armed_rig(paths, key_file, udr7_cutoff_percent=10, udr7_shutdown_percent=shutdown)
        actions = rig.outage(snap(**{"battery.charge": "5"}))
        assert actions[0].payload["detail"] == "limiar_abaixo_do_corte", shutdown
    rig = armed_rig(paths, key_file, udr7_cutoff_percent=10, udr7_shutdown_percent=12)
    assert events_of(rig.outage(snap(**{"battery.charge": "11"}))) == [EV_SENT]


# --- armed file / pins ---------------------------------------------------------------
def test_armed_file_missing_blocks(paths, key_file):
    rig = Rig(paths, armed_overrides(key_file))   # dry-run off but never armed via API
    actions = rig.outage()
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["detail"] == "armamento_ausente"
    assert rig.spy.calls == []


def test_armed_file_pin_mismatch_blocks(paths, key_file):
    rig = armed_rig(paths, key_file)
    # A pin without its own gate diverges after arming: ssh_port 22 -> 2222.
    rig.holder.replace(replace(rig.holder.get(), udr7_ssh_port=2222))
    actions = rig.outage()
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["detail"] == "config_trocada"
    assert rig.spy.calls == []


def test_rename_while_armed_keeps_pins(paths, key_file):
    """Trocar o nome com o daemon ARMADO não é divergência de configuração.

    É o nó da cena S4o: se `udr7_name` deixar de estar em _PIN_EXCLUDED, ele vira
    pino, a comparação com o arquivo de armamento acusa `config_trocada` e a queda
    seguinte é BLOQUEADA — o usuário perderia a proteção por ter renomeado o
    aparelho na tela de Ajustes.
    """
    rig = armed_rig(paths, key_file)
    rig.holder.replace(replace(rig.holder.get(), udr7_name="Meu UDR"))
    actions = rig.outage()
    assert events_of(actions) == [EV_SENT]
    assert all(a.payload.get("detail") != "config_trocada" for a in actions)


def test_status_carries_name_with_fallback(paths, key_file):
    """O nome sai no status(), e o fallback mora aqui — num lugar só."""
    rig = armed_rig(paths, key_file)
    assert rig.policy.status()["name"] == "UDR7"
    rig.holder.replace(replace(rig.holder.get(), udr7_name="Meu UDR"))
    assert rig.policy.status()["name"] == "Meu UDR"
    rig.holder.replace(replace(rig.holder.get(), udr7_name=""))
    assert rig.policy.status()["name"] == "UDR7"


def test_status_before_first_tick_never_says_dry_run_when_armed(paths, key_file):
    """Sem nenhum tick, o estado publicado tem de ser verdadeiro.

    Ligada e sem ensaio = armada e não verificada. Dizer "dry_run" aí seria
    afirmar ensaio para uma instância capaz de desligar o aparelho de verdade.
    """
    armada = Rig(paths, armed_overrides(key_file, protect_dry_run=False))
    assert armada.policy.status()["state"] == "armado_nao_verificado"
    ensaio = Rig(paths, armed_overrides(key_file, protect_dry_run=True))
    assert ensaio.policy.status()["state"] == "dry_run"
    desligada = Rig(paths, armed_overrides(key_file, protect_udr7=False))
    assert desligada.policy.status()["state"] == "desabilitado"


def test_status_keys_match_the_fixture(paths, key_file):
    """A fixture health_udr7.json e o status() real não podem divergir em CHAVES.

    test_fixtures_contract compara valores contra a fixture, o que só prova que a
    fixture ecoa a si mesma; esta compara o conjunto de chaves com o que o código
    produz agora.
    """
    import json as _json

    raiz = pathlib.Path(__file__).resolve().parents[2]
    fixture = _json.loads((raiz / "tests" / "fixtures" / "health_udr7.json").read_text())
    rig = armed_rig(paths, key_file)
    assert set(rig.policy.status()) == set(fixture["udr7_detail"])


def test_arm_disarm_write_and_remove_file_and_emit(paths, key_file):
    rig = Rig(paths, armed_overrides(key_file, protect_dry_run=True))
    assert events_of(rig.apply(protect_dry_run=False)) == [EV_ARMED]
    data = json.loads(open(paths["armed_path"]).read())
    assert data["pins"]["udr7_ssh_host"] == "192.0.2.1"
    assert "protect_udr7" not in data["pins"] and "udr7_arm_allowed" not in data["pins"]
    # O nome do dispositivo NÃO é pino: renomear com o daemon armado é permitido, e
    # um arquivo de armamento escrito por um daemon anterior continua válido.
    assert "udr7_name" not in data["pins"]
    assert oct(os.stat(paths["armed_path"]).st_mode & 0o777) == "0o600"
    assert events_of(rig.apply(protect_dry_run=True)) == [EV_DISARMED]
    assert not os.path.exists(paths["armed_path"])
    assert rig.apply(udr7_ssh_port=2222) == []   # no predicate transition: no event


# --- dry-run ------------------------------------------------------------------------
def test_dry_run_never_spawns(paths, key_file):
    # Fully armed and real-looking; ONLY dry_run=True separates this from SENT.
    rig = armed_rig(paths, key_file, protect_dry_run=True)
    actions = rig.outage()
    assert events_of(actions) == [EV_DRYRUN]
    assert rig.spy.calls == []
    assert not os.path.exists(paths["runtime_path"])


def test_dry_run_payload_reports_would_block(paths, key_file):
    rig = Rig(paths, armed_overrides(key_file, protect_dry_run=True))   # no armed.json
    actions = rig.outage(snap(**{"driver.name": "fake-nut-ups"}))
    p = actions[0].payload
    assert actions[0].event == EV_DRYRUN
    assert p["would_block"] == "fonte_nao_real" and p["source_detail"] == "telemetria_sintetica"
    rig2 = armed_rig(paths, key_file, protect_dry_run=True)
    assert rig2.outage()[0].payload["would_block"] is None


# --- firing, retries, latch ----------------------------------------------------------
def test_real_source_armed_runs_once(paths, key_file):
    rig = armed_rig(paths, key_file)
    actions = rig.outage()
    assert events_of(actions) == [EV_SENT]
    assert len(rig.spy.calls) == 1
    assert rig.spy.calls[0][-1] == POWEROFF_COMMAND
    rig.clock.now += 100
    assert rig.tick() == []                    # latched: one SENT per outage
    assert len(rig.spy.calls) == 1
    assert json.loads(open(paths["runtime_path"]).read())["sent_pending_restore"] is True


def test_one_attempt_per_tick_reevaluates_and_stops_on_restore(paths, key_file):
    rig = Rig(paths, armed_overrides(key_file), spy=Spy(returncode=255, stderr=b"timeout"))
    rig.arm_file()
    assert events_of(rig.outage()) == [EV_FAILED]
    assert len(rig.spy.calls) == 1
    rig.clock.now += 1
    assert rig.tick() == []                    # spacing not elapsed: no 2nd attempt yet
    rig.clock.now += SUBPROCESS_TIMEOUT_SECONDS
    assert events_of(rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])) == [EV_REARMED]
    assert len(rig.spy.calls) == 1             # power back: never retried


def test_failed_retries_up_to_budget_then_latches(paths, key_file):
    rig = Rig(paths, armed_overrides(key_file, udr7_retry_max=2), spy=Spy(returncode=1))
    rig.arm_file()
    seen = []
    for _ in range(6):
        seen += events_of(rig.tick(events=["POWER_LOSS"] if not seen else []))
        rig.clock.now += SUBPROCESS_TIMEOUT_SECONDS
    # 2 tentativas = 2 envios; no tick seguinte a política bloqueia e trava.
    assert seen == [EV_FAILED, EV_FAILED, EV_BLOCKED]
    assert len(rig.spy.calls) == 2


def test_retry_max_is_the_number_of_attempts(paths, key_file):
    """O número que a tela mostra é o número de tentativas, nem uma a mais."""
    rig = Rig(paths, armed_overrides(key_file, udr7_retry_max=3), spy=Spy(returncode=1))
    rig.arm_file()
    seen = []
    for _ in range(8):
        seen += events_of(rig.tick(events=["POWER_LOSS"] if not seen else []))
        rig.clock.now += SUBPROCESS_TIMEOUT_SECONDS
    assert seen == [EV_FAILED, EV_FAILED, EV_FAILED, EV_BLOCKED]
    assert len(rig.spy.calls) == 3
    bloqueio = [a for a in rig.tick() if a.event == EV_BLOCKED]
    assert bloqueio == []                       # travada: um bloqueio por queda


def test_retry_max_zero_never_spawns(paths, key_file):
    """Zero tentativas é uma escolha legítima: vigia, avisa e nunca desliga."""
    rig = armed_rig(paths, key_file, udr7_retry_max=0)
    acoes = rig.outage()
    assert events_of(acoes) == [EV_BLOCKED]
    assert acoes[0].payload["detail"] == "tentativas_esgotadas"
    assert acoes[0].payload["attempt"] == 0     # nenhuma tentativa foi feita
    assert rig.spy.calls == []


def test_retry_max_zero_still_reports_in_dry_run(paths, key_file):
    """Em ensaio, zero tentativas não pode calar o aviso do que aconteceria."""
    rig = armed_rig(paths, key_file, udr7_retry_max=0, protect_dry_run=True)
    assert events_of(rig.outage()) == [EV_DRYRUN]
    assert rig.spy.calls == []


def test_blocked_and_dryrun_latch_per_outage(paths, key_file):
    rig = armed_rig(paths, key_file, udr7_expected_serial="R3P-OUTRA")
    assert events_of(rig.outage()) == [EV_BLOCKED]
    rig.clock.now += 50
    assert rig.tick() == []
    assert events_of(rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])) == [EV_REARMED]
    assert events_of(rig.outage()) == [EV_BLOCKED]  # new outage: evaluates again


def test_no_fire_without_power_loss(paths, key_file):
    rig = armed_rig(paths, key_file)
    for _ in range(3):
        assert rig.tick() == []               # ON_BATTERY but tracker never confirmed
        rig.clock.now += 10
    assert rig.spy.calls == []


def test_no_fire_on_grid_even_when_low(paths, key_file):
    rig = armed_rig(paths, key_file)
    rig.outage(snap(**{"battery.charge": "50"}))
    rig.clock.now += 5
    assert rig.tick(snap(**{"ups.status": "OL CHRG", "battery.charge": "5"})) == []
    assert rig.spy.calls == []


def test_calibrating_blocks(paths, key_file):
    rig = armed_rig(paths, key_file)
    actions = rig.outage(snap(**{"ups.status": "OB DISCHRG CAL"}))
    assert actions == [] or actions[0].payload.get("detail") != "enviado"
    assert rig.spy.calls == []
    assert rig.policy.status()["state"] == "calibrando"


def test_min_outage_guard(paths, key_file):
    rig = armed_rig(paths, key_file, udr7_min_outage_seconds=60)
    assert rig.outage() == []
    rig.clock.now += 59
    assert rig.tick() == []
    rig.clock.now += 2
    assert events_of(rig.tick()) == [EV_SENT]


def test_confirm_window_requires_continuous_condition(paths, key_file):
    rig = armed_rig(paths, key_file, udr7_confirm_seconds=6)
    assert rig.outage(snap(**{"battery.charge": "18"})) == []       # window opens
    rig.clock.now += 3
    assert rig.tick(snap(**{"battery.charge": "25"})) == []        # condition broke: reset
    rig.clock.now += 3
    assert rig.tick(snap(**{"battery.charge": "18"})) == []        # reopened at t+6
    rig.clock.now += 5.9
    assert rig.tick(snap(**{"battery.charge": "17"})) == []
    rig.clock.now += 0.2
    assert events_of(rig.tick(snap(**{"battery.charge": "17"}))) == [EV_SENT]


def test_charge_out_of_range_is_ignored(paths, key_file):
    rig = armed_rig(paths, key_file)
    assert rig.outage(snap(**{"battery.charge": "-1"})) == []
    assert rig.tick(snap(**{"battery.charge": "250"})) == []
    assert rig.spy.calls == []


def test_charge_none_warns_and_blind(paths, key_file):
    rig = armed_rig(paths, key_file)
    assert rig.outage(snap(**{"battery.charge": "n/a"})) == []
    st = rig.policy.status()
    assert "charge_missing" in st["warnings"]
    assert events_of(rig.policy.observe_failure(["COMM_LOST"])) == [EV_BLIND]
    assert rig.policy.observe_failure(["COMM_LOST"]) == []       # once per outage


def test_low_battery_flag_is_ignored(paths, key_file):
    rig = armed_rig(paths, key_file)
    assert rig.outage(snap(**{"ups.status": "OB DISCHRG LB", "battery.charge": "60"})) == []
    assert rig.spy.calls == []


def test_runtime_axis_off_by_default_and_170_yes_181_no_none_no_when_on(paths, key_file):
    off = armed_rig(paths, key_file)
    assert off.outage(snap(**{"battery.charge": "60", "battery.runtime": "100"})) == []
    on = armed_rig(paths, key_file, udr7_runtime_minutes=3)
    assert on.outage(snap(**{"battery.charge": "60", "battery.runtime": "181"})) == []
    assert events_of(on.tick(snap(**{"battery.charge": "60", "battery.runtime": "170"}))) == [EV_SENT]
    none_rig = armed_rig(paths, key_file, udr7_runtime_minutes=3)
    vars_ = real_vars(**{"battery.charge": "60"}); vars_.pop("battery.runtime")
    assert none_rig.outage(snapshot_from_nut_vars("r", vars_)) == []
    crazy = armed_rig(paths, key_file, udr7_runtime_minutes=3)
    assert crazy.outage(snap(**{"battery.charge": "60", "battery.runtime": "90000"})) == []


def test_rearm_and_new_outage(paths, key_file):
    rig = armed_rig(paths, key_file)
    assert events_of(rig.outage()) == [EV_SENT]
    restored = rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])
    assert events_of(restored) == [EV_REARMED]
    assert json.loads(open(paths["runtime_path"]).read())["sent_pending_restore"] is False
    assert events_of(rig.outage()) == [EV_SENT]
    assert len(rig.spy.calls) == 2


def test_sent_pending_restore_blocks_until_online_seen(paths, key_file):
    rig = armed_rig(paths, key_file)
    assert events_of(rig.outage()) == [EV_SENT]
    # Daemon restarts mid-outage: a fresh policy reads the runtime file.
    rig2 = Rig(paths, armed_overrides(key_file))
    actions = rig2.outage()
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["detail"] == "aguardando_restauracao"
    assert rig2.spy.calls == []
    # First ONLINE snapshot clears it even without a POWER_RESTORED event.
    rig2.tick(snap(**{"ups.status": "OL CHRG"}))
    assert events_of(rig2.outage()) == [EV_SENT]


# --- key / known_hosts -----------------------------------------------------------------
def test_key_missing_or_permissive_blocks(paths, key_file, tmp_path):
    missing = armed_rig(paths, key_file, udr7_ssh_key=str(tmp_path / "nao-existe"))
    assert missing.outage()[0].payload["detail"] == "chave_insegura"
    os.chmod(key_file, 0o644)
    loose = armed_rig(paths, key_file)
    assert loose.outage()[0].payload["detail"] == "chave_insegura"
    empty = armed_rig(paths, key_file, udr7_ssh_key="")
    a = empty.outage()[0]
    assert a.payload["detail"] == "config_incompleta"
    assert empty.policy.status()["missing_key"] == "UDR7_SSH_KEY"


def test_unknown_host_blocks_and_uses_port_form(paths, key_file):
    kg = FakeKeygen(returncode=1)
    rig = Rig(paths, armed_overrides(key_file, udr7_ssh_port=2222), keygen=kg)
    os.makedirs(os.path.dirname(paths["known_hosts_path"]), exist_ok=True)
    open(paths["known_hosts_path"], "w").write("x\n")
    rig.arm_file()
    actions = rig.outage()
    assert actions[0].payload["detail"] == "host_desconhecido"
    assert kg.calls and kg.calls[0][2] == "[192.0.2.1]:2222"
    assert rig.spy.calls == []


def test_known_host_cache_status_never_spawns(paths, key_file):
    kg = FakeKeygen(returncode=0)
    rig = Rig(paths, armed_overrides(key_file), keygen=kg)
    os.makedirs(os.path.dirname(paths["known_hosts_path"]), exist_ok=True)
    open(paths["known_hosts_path"], "w").write("192.0.2.1 ssh-ed25519 AAAA\n")
    rig.arm_file()
    rig.outage(snap(**{"battery.charge": "50"}))
    n = len(kg.calls)
    assert n == 1
    for _ in range(5):
        rig.policy.status()
        rig.tick(snap(**{"battery.charge": "50"}))
    assert len(kg.calls) == n                  # cached by (host, port, mtime, size)
    # Absent file: memorised as unknown, no keygen call at all.
    kg2 = FakeKeygen(returncode=0)
    rig2 = Rig(paths, armed_overrides(key_file, udr7_ssh_host="192.0.2.2"), keygen=kg2)
    os.unlink(paths["known_hosts_path"])
    rig2.arm_file()
    rig2.outage()
    rig2.tick()
    assert kg2.calls == []


def test_keygen_missing_is_fail_closed(paths):
    def boom(*a, **k):
        raise OSError("no such file")
    assert known_host_ok("h", 22, paths["known_hosts_path"], runner=boom) is False
    assert known_host_ok("h", 22, paths["known_hosts_path"], runner=FakeKeygen(255)) is False
    assert known_host_ok("h", 22, paths["known_hosts_path"], runner=FakeKeygen(0)) is True


# --- comm / wol -------------------------------------------------------------------------
def test_comm_lost_during_outage_emits_blind_once(paths, key_file):
    rig = armed_rig(paths, key_file)
    assert rig.policy.observe_failure(["COMM_LOST"]) == []      # not in an outage
    rig.outage(snap(**{"battery.charge": "50"}))
    assert events_of(rig.policy.observe_failure(["COMM_LOST"])) == [EV_BLIND]
    assert rig.policy.observe_failure(["COMM_LOST"]) == []


def test_wol_sent_only_after_sent_and_wol_dryrun_in_rehearsal(paths, key_file):
    rig = armed_rig(paths, key_file, udr7_wol_mac="aa:bb:cc:dd:ee:ff")
    rig.outage(snap(**{"battery.charge": "50"}))
    assert events_of(rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])) == []
    assert rig.wol_calls == []                 # no SENT: no packet
    rig.outage()
    actions = rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])
    assert events_of(actions) == [EV_REARMED, EV_WOL_SENT]
    assert rig.wol_calls == ["aa:bb:cc:dd:ee:ff"]   # sent through the injected seam only
    rehearsal = armed_rig(paths, key_file, protect_dry_run=True, udr7_wol_mac="aa:bb:cc:dd:ee:ff")
    rehearsal.outage()
    acts = rehearsal.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])
    assert events_of(acts) == [EV_REARMED, EV_WOL_DRYRUN]
    assert rehearsal.wol_calls == []               # rehearsal never sends


def test_wol_only_touches_socket_in_sender(monkeypatch):
    sent = []

    class FakeSock:
        def __init__(self, *a, **k): pass
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def setsockopt(self, *a): sent.append(("opt", a))
        def sendto(self, payload, addr): sent.append((payload, addr))

    monkeypatch.setattr(protect.socket, "socket", FakeSock)
    protect.send_magic_packet("AA-BB-CC-DD-EE-FF")
    payload, addr = sent[-1]
    assert payload == b"\xff" * 6 + bytes.fromhex("aabbccddeeff") * 16
    assert addr == (protect.WOL_BROADCAST, protect.WOL_PORT)
    src = open(protect.__file__, encoding="utf-8").read()
    body = src.split("def send_magic_packet", 1)[1].split("\n\n\n", 1)[0]
    assert src.count("socket.socket(") == 1 and "socket.socket(" in body


# --- holder / atomicity / status ---------------------------------------------------------
def test_policy_reads_holder_not_cfg(paths, key_file):
    cfg = make_cfg(**armed_overrides(key_file))
    holder = ConfigHolder(ProtectionConfig.from_cfg(cfg))
    rig = Rig(paths, armed_overrides(key_file))
    rig.holder = holder
    rig.policy._holder = holder
    rig.arm_file()
    cfg.protect_dry_run = True                 # mutating BridgeConfig changes nothing
    assert events_of(rig.outage()) == [EV_SENT]
    holder.replace(ProtectionConfig.from_cfg(cfg))
    rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])
    assert events_of(rig.outage()) == [EV_DRYRUN]


def test_holder_replace_is_atomic(paths, key_file):
    import threading
    holder = ConfigHolder(make_pc(**armed_overrides(key_file)))
    stop = threading.Event()
    torn = []

    def reader():
        while not stop.is_set():
            pc = holder.get()
            if (pc.udr7_ssh_port == 2222) != (pc.udr7_ssh_user == "svc"):
                torn.append(pc)

    t = threading.Thread(target=reader); t.start()
    for i in range(2000):
        base = holder.get()
        holder.replace(replace(base, udr7_ssh_port=2222 if i % 2 else 22,
                               udr7_ssh_user="svc" if i % 2 else "root"))
    stop.set(); t.join()
    assert torn == []


def test_disarm_not_blocked_by_in_flight_attempt(paths, key_file):
    import threading
    started, release = threading.Event(), threading.Event()

    def slow_runner(argv, **kw):
        assert argv[0] == protect.SSH_BINARY
        started.set(); release.wait(5)
        return Result(0)

    rig = Rig(paths, armed_overrides(key_file), spy=slow_runner)
    rig.arm_file()
    out: list = []
    t = threading.Thread(target=lambda: out.extend(rig.outage())); t.start()
    assert started.wait(5)
    disarmed = rig.apply(protect_dry_run=True)   # must not wait for the spawn
    assert events_of(disarmed) == [EV_DISARMED]
    release.set(); t.join(5)
    assert events_of(out) == [EV_SENT]           # physics: the in-flight attempt completes


def test_status_precedence_matches_gate_order(paths, key_file):
    rig = Rig(paths, dict(protect_udr7=False))
    rig.tick(); assert rig.policy.status()["state"] == "desabilitado"
    rig = Rig(paths, armed_overrides(key_file, protect_dry_run=True, udr7_expected_serial=""))
    rig.tick(snap(**{"driver.name": "fake-nut-ups"}))
    st = rig.policy.status()
    assert st["state"] == "fonte_nao_real" and st["dry_run"] is True    # first_fail > dry_run
    assert st["source"] == "sintetica" and st["ssh_binary"] == protect.SSH_BINARY
    rig = armed_rig(paths, key_file, protect_dry_run=True)
    rig.tick(); assert rig.policy.status()["state"] == "dry_run"
    rig = armed_rig(paths, key_file)
    rig.tick(); assert rig.policy.status()["state"] == "armado_nao_verificado"
    rig.outage(); assert rig.policy.status()["state"] == "enviado"
    assert rig.policy.drain_transition() == ("armado_nao_verificado", "enviado")
    assert rig.policy.drain_transition() is None


def test_margin_estimate_warnings(paths, key_file):
    rig = armed_rig(paths, key_file)               # rate unknown
    rig.tick()
    assert "margin_unknown" in rig.policy.status()["warnings"]
    short = armed_rig(paths, key_file, udr7_discharge_seconds_per_pct=5)   # 10 % * 5 s = 50 s
    short.tick()
    st = short.policy.status()
    assert st["margin_estimate_s"] == 50 and "margin_short" in st["warnings"]
    ok = armed_rig(paths, key_file, udr7_discharge_seconds_per_pct=60)    # 600 s
    ok.tick()
    assert "margin_short" not in ok.policy.status()["warnings"]
    lock = armed_rig(paths, key_file, udr7_arm_allowed=True)
    lock.tick()
    assert "lock_open" in lock.policy.status()["warnings"]


def test_margin_counts_the_attempts_that_really_happen(paths, key_file):
    """A margem reserva tempo para as tentativas que existem, não para uma a mais.

    Com 3 tentativas de 20 s e 30 s de desligamento, o mínimo é 90 s. A folga
    medida aqui é 100 s: sobra pela conta certa e faltaria pela antiga (110 s).
    """
    rig = armed_rig(paths, key_file, udr7_retry_max=3, udr7_confirm_seconds=0,
                    udr7_discharge_seconds_per_pct=10)
    rig.tick()
    st = rig.policy.status()
    assert st["margin_estimate_s"] == 100
    assert "margin_short" not in st["warnings"]


def test_simulator_base_vars_are_synthetic():
    import importlib.machinery, importlib.util, pathlib
    path = str(pathlib.Path(__file__).parents[2] / "tools" / "fake-nut-ups")
    loader = importlib.machinery.SourceFileLoader("fake_nut_ups_synth", path)
    sim = importlib.util.module_from_spec(importlib.util.spec_from_loader("fake_nut_ups_synth", loader))
    loader.exec_module(sim)
    assert protect._is_synthetic_driver(sim.BASE_VARS["driver.name"], sim.BASE_VARS["driver.version"])
    assert source_verdict(sim.BASE_VARS["driver.name"], sim.BASE_VARS["driver.version"],
                          "SIM0001", "SIM0001") == "telemetria_sintetica"


# --- ssh -G (the only test allowed to run a local process; never connects) --------------
@pytest.mark.spawn_ok
def test_ssh_G_reflects_argv(paths, key_file):
    ssh = "/usr/bin/ssh"
    if not os.path.exists(ssh):
        pytest.skip("/usr/bin/ssh ausente")
    pc = replace(make_pc(**armed_overrides(key_file, udr7_ssh_port=2222)), ssh_binary=ssh)
    argv = ssh_argv(pc, paths["known_hosts_path"], POWEROFF_COMMAND)
    argv.insert(1, "-G")
    out = subprocess.run(argv, capture_output=True, text=True, timeout=10)
    assert out.returncode == 0, out.stderr
    cfg = {}
    for line in out.stdout.splitlines():
        k, _, v = line.partition(" ")
        cfg.setdefault(k, v)
    assert cfg["user"] == "root" and cfg["hostname"] == "192.0.2.1" and cfg["port"] == "2222"
    assert cfg["batchmode"] == "yes"
    assert cfg["stricthostkeychecking"] in ("true", "yes")
    assert not any(re.match(r"^proxycommand ", l) or re.match(r"^proxyjump ", l)
                   for l in out.stdout.splitlines())
    # Negative control: a ProxyCommand WOULD show up.
    neg = subprocess.run([ssh, "-G", "-F", "/dev/null", "-o", "ProxyCommand=/bin/echo", "--",
                          "root@192.0.2.1", "true"], capture_output=True, text=True, timeout=10)
    assert any(l.startswith("proxycommand /bin/echo") for l in neg.stdout.splitlines())
    # A malicious destination after `--` is an ssh error (exit 255), never an option.
    bad = subprocess.run([ssh, "-G", "-F", "/dev/null", "--", "-oProxyCommand=/bin/echo@192.0.2.1",
                          "true"], capture_output=True, text=True, timeout=10)
    assert bad.returncode == 255
    version = subprocess.run([ssh, "-V"], capture_output=True, text=True, timeout=10).stderr.strip()
    findings = os.path.join(os.path.dirname(protect.__file__), "..", "..", "research", "findings.md")
    findings = os.path.abspath(findings)
    marker = "[FATO 2026-09-01] `ssh -G` com o argv da proteção"
    text = open(findings, encoding="utf-8").read()
    if marker not in text:
        with open(findings, "a", encoding="utf-8") as fh:
            fh.write(
                f"\n- {marker}: `stricthostkeychecking {cfg['stricthostkeychecking']}`, "
                f"sem linha `proxycommand` com `ProxyCommand=none`; destino malicioso após `--` "
                f"→ rc 255 ({version}). Comando: `{' '.join(argv)}` (tests/unit/test_protect.py).\n"
            )


# --- motor para N instâncias (2026-09-03) -------------------------------------------
class KwSpy(Spy):
    """Spy que também guarda os kwargs: a cerca S4w exige argv em LISTA e sem `shell`."""

    def __init__(self):
        super().__init__()
        self.kwargs: list[dict] = []

    def __call__(self, argv, **kwargs):
        self.kwargs.append(dict(kwargs))
        return super().__call__(argv, **kwargs)


class FakeInstance:
    def __init__(self, **over):
        self.enabled = over.pop("enabled", True)
        self.dry_run = over.pop("dry_run", False)
        self.name = over.pop("name", "Servidor SSH")
        self.fields = over


def test_ssh_spawn_is_argv_list_without_shell(paths, key_file):
    spy = KwSpy()
    rig = Rig(paths, armed_overrides(key_file), spy=spy)
    rig.arm_file()
    assert events_of(rig.outage()) == [EV_SENT]
    assert len(spy.calls) == 1 and isinstance(spy.calls[0], list)
    assert "shell" not in spy.kwargs[0]
    assert spy.calls[0][-1] == POWEROFF_COMMAND and spy.calls[0][-3] == "--"


def test_policy_fires_the_pinned_shutdown_command(paths, key_file):
    """Um comando pinado na ProtectionConfig tem precedência sobre o do construtor."""
    rig = Rig(paths, armed_overrides(key_file))
    rig.holder.replace(replace(rig.holder.get(), shutdown_command="shutdown -h now"))
    rig.arm_file()
    assert events_of(rig.outage()) == [EV_SENT]
    assert rig.spy.calls[0][-1] == "shutdown -h now"


def test_shutdown_command_is_pinned(paths, key_file):
    """Trocar o comando de uma instância ARMADA vira config_trocada (S4p): o envio
    nunca difere do que foi pinado no <id>_armed.json."""
    rig = Rig(paths, armed_overrides(key_file))
    rig.holder.replace(replace(rig.holder.get(), shutdown_command="shutdown -h now"))
    rig.arm_file()
    assert "shutdown_command" in rig.holder.get().pins()
    new = replace(rig.holder.get(), shutdown_command="poweroff")
    rig.holder.replace(new)                      # fora do caminho de armar/desarmar
    actions = rig.outage()
    assert events_of(actions) == [EV_BLOCKED]
    assert actions[0].payload["detail"] == "config_trocada"
    assert rig.spy.calls == []


def test_from_instance_maps_fields_and_reads_river_keys_from_core(key_file):
    cfg = make_cfg(udr7_expected_serial=REAL_SERIAL, udr7_cutoff_percent=12,
                   udr7_arm_allowed=True)
    inst = FakeInstance(ssh_host="192.0.2.9", ssh_user="admin", ssh_key=key_file,
                        shutdown_percent=30, dry_run=True)
    pc = ProtectionConfig.from_instance(inst, cfg, shutdown_command="sudo -n poweroff")
    assert (pc.protect_udr7, pc.protect_dry_run, pc.armed) == (True, True, False)
    assert (pc.udr7_ssh_host, pc.udr7_ssh_user, pc.udr7_ssh_key) == ("192.0.2.9", "admin", key_file)
    assert pc.udr7_ssh_port == 22 and pc.udr7_retry_max == 3 and pc.udr7_confirm_seconds == 6
    # D16: série esperada e corte são do River (núcleo), nunca da instância.
    assert (pc.udr7_expected_serial, pc.udr7_cutoff_percent) == (REAL_SERIAL, 12)
    assert pc.udr7_arm_allowed is True and pc.udr7_name == "Servidor SSH"
    assert pc.shutdown_command == "sudo -n poweroff" and pc.ssh_binary == protect.SSH_BINARY
    assert (pc.nut_host, pc.nut_port, pc.nut_ups) == ("127.0.0.1", 3493, "r")


def test_from_cfg_still_serves_the_legacy_instance(key_file):
    pc = make_pc(**armed_overrides(key_file))
    assert pc.shutdown_command == "" and pc.udr7_name == "UDR7"


def test_status_name_falls_back_to_the_policy_default_name(paths, key_file):
    holder = ConfigHolder(make_pc(**armed_overrides(key_file, udr7_name="")))
    policy = ProtectionPolicy(holder, runner=Spy(), keygen_runner=FakeKeygen(0),
                              default_name="Servidor SSH",
                              shutdown_command=POWEROFF_COMMAND, **paths)
    assert policy.status()["name"] == "Servidor SSH"


def test_runtime_write_failure_still_resets_outage_and_records_sent(paths, key_file, monkeypatch, capsys):
    """Disco cheio na hora de anotar não pode travar nem calar a proteção.

    O arquivo de memória ("já enviei nesta queda") é conveniência entre reinícios;
    o estado em memória é o que decide. Antes, a exceção subia pelo tick; com a
    rede do laço aparando, a instância ficaria travada em silêncio — o pior dos
    dois mundos.
    """
    escrita_real = protect._write_private_json

    def disco_cheio(path, data):
        raise OSError(28, "No space left on device")

    # 1) No ENVIO: o evento sai e o comando é chamado, mesmo sem conseguir anotar.
    rig = armed_rig(paths, key_file)
    monkeypatch.setattr(protect, "_write_private_json", disco_cheio)
    actions = rig.outage()
    assert events_of(actions) == [EV_SENT]
    assert len(rig.spy.calls) == 1
    assert not os.path.exists(paths["runtime_path"])
    avisos = [json.loads(l) for l in capsys.readouterr().out.splitlines()
              if '"runtime_write_failed"' in l]
    assert len(avisos) == 1

    # 2) Na RESTAURAÇÃO: a queda é zerada e a instância volta a poder disparar.
    rig.clock.now += 100
    # REARMED: a política estava travada pelo envio e volta a ficar elegível.
    assert events_of(rig.tick(snap(**{"ups.status": "OL CHRG"}), ["POWER_RESTORED"])) == [EV_REARMED]
    # Volta a escrever (o `undo` do monkeypatch levaria junto a cerca anti-spawn
    # do conftest, que compartilha a mesma instância da fixture).
    monkeypatch.setattr(protect, "_write_private_json", escrita_real)
    rig.clock.now += 100
    assert events_of(rig.outage()) == [EV_SENT]        # nova queda, novo envio
    assert len(rig.spy.calls) == 2


def test_disarm_still_wins_when_the_armed_file_cannot_be_deleted(paths, key_file, monkeypatch, capsys):
    """O botão de parada nunca falha, nem com o arquivo de armamento preso.

    O arquivo órfão é inócuo: só é lido com a proteção ligada e é reescrito no
    próximo armamento. O que não pode acontecer é o desarme ser recusado.
    """
    rig = armed_rig(paths, key_file)
    assert os.path.exists(paths["armed_path"])

    def preso(_path):
        raise PermissionError(13, "Permission denied")

    monkeypatch.setattr(os, "unlink", preso)
    acoes = rig.apply(protect_dry_run=True)
    assert events_of(acoes) == [EV_DISARMED]
    assert rig.policy.status()["dry_run"] is True
    avisos = [json.loads(l) for l in capsys.readouterr().out.splitlines()
              if '"armed_file_unlink_failed"' in l]
    assert len(avisos) == 1
