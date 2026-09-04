"""API fences (§7A.3): auth, loopback bind, honest nulls, PUT allowlist,
restart contract. These back the gate's bind-mutation scene."""

import pytest

from river_unifi_bridge import api as api_module
from river_unifi_bridge.api import ApiServer, ensure_loopback
from river_unifi_bridge.config import BridgeConfig, ConfigError
from river_unifi_bridge.history import HistoryStore
from river_unifi_bridge.state import SharedState

TOKEN = "test-token"


def make_cfg(env_path, **overrides):
    base = dict(river_name="river-office", nut_host="127.0.0.1", nut_port=3493,
                nut_ups="river-office")
    base.update(overrides)
    return BridgeConfig(**base)


@pytest.fixture
def env_file(tmp_path):
    path = tmp_path / "bridge.env"
    path.write_text(
        "RIVER_NAME=river-office\nNUT_HOST=127.0.0.1\nNUT_PORT=3493\n"
        "NUT_UPS=river-office\nLOW_BATTERY_PERCENT=15\n",
        encoding="utf-8",
    )
    return str(path)


@pytest.fixture
def server(tmp_path, env_file):
    restarts = []
    srv = ApiServer(
        cfg=make_cfg(env_file),
        state=SharedState(),
        history=HistoryStore(str(tmp_path / "h.sqlite")),
        env_path=env_file,
        restart_cb=lambda: restarts.append(1),
        token=TOKEN,
    )
    srv.restarts = restarts
    return srv


@pytest.fixture
async def client(server, aiohttp_client):
    import asyncio

    c = await aiohttp_client(server.build_app())
    # The restart handler schedules via self._loop; in tests that's this loop.
    server._loop = asyncio.get_running_loop()
    c.auth = {"Authorization": f"Bearer {TOKEN}"}
    return c


def test_bind_host_is_loopback_constant():
    # Gate mutation scene flips this constant to 0.0.0.0 — this test MUST fail then.
    assert api_module.BIND_HOST == "127.0.0.1"
    ensure_loopback("127.0.0.1")
    with pytest.raises(ConfigError, match="não-loopback"):
        ensure_loopback("0.0.0.0")


async def test_auth_required(client):
    resp = await client.get("/v1/state")
    assert resp.status == 401
    resp = await client.get("/v1/state", headers={"Authorization": "Bearer errado"})
    assert resp.status == 401


async def test_state_without_snapshot_is_honest_nulls(client):
    resp = await client.get("/v1/state", headers=client.auth)
    assert resp.status == 200
    body = await resp.json()
    assert body["power"]["state"] == "UNKNOWN"
    assert body["battery"]["charge_percent"] is None
    assert body["health"]["communication_ok"] is False


async def test_state_reflects_snapshot(client, server):
    server.state.update_snapshot({"power": {"state": "ONLINE"}, "battery": {}})
    resp = await client.get("/v1/state", headers=client.auth)
    assert (await resp.json())["power"]["state"] == "ONLINE"


async def test_put_config_unknown_key_400_names_key(client):
    resp = await client.put("/v1/config", json={"NAO_EXISTE": "1"}, headers=client.auth)
    assert resp.status == 400
    assert "NAO_EXISTE" in (await resp.json())["erro"]


async def test_put_config_out_of_range_400(client):
    resp = await client.put(
        "/v1/config", json={"LOW_BATTERY_PERCENT": "99"}, headers=client.auth
    )
    assert resp.status == 400
    assert "faixa" in (await resp.json())["erro"]


async def test_put_config_hot_reload_applies_and_persists(client, server, env_file):
    resp = await client.put(
        "/v1/config", json={"LOW_BATTERY_PERCENT": "20"}, headers=client.auth
    )
    assert resp.status == 200
    body = await resp.json()
    assert body["aplicadas_a_quente"] == ["LOW_BATTERY_PERCENT"]
    assert body["restart_required"] is False
    assert server.cfg.low_battery_percent == 20
    assert "LOW_BATTERY_PERCENT=20" in open(env_file).read()


async def test_put_config_restart_required_not_applied_hot(client, server, env_file):
    resp = await client.put(
        "/v1/config", json={"NUT_PORT": "3494"}, headers=client.auth
    )
    body = await resp.json()
    assert body["restart_required"] is True
    assert server.cfg.nut_port == 3493            # not hot-applied
    assert "NUT_PORT=3494" in open(env_file).read()  # but persisted


async def test_restart_answers_202_then_fires_callback(client, server):
    import asyncio

    resp = await client.post("/v1/service/restart", headers=client.auth)
    assert resp.status == 202
    assert server.restarts == []                  # not yet — response drains first
    await asyncio.sleep(api_module.RESTART_EXIT_DELAY_SECONDS + 0.3)
    assert server.restarts == [1]


async def test_health_and_version(client, server):
    resp = await client.get("/v1/health", headers=client.auth)
    body = await resp.json()
    assert body["unifi"] == "sem_caminho_nativo_documentado"
    assert body["udr7"] == "desabilitado" and body["udr7_detail"] is None
    assert body["ha"] == "nao_observavel"
    resp = await client.get("/v1/version", headers=client.auth)
    assert "version" in await resp.json()


async def test_events_log_query_by_period_and_type(client, server):
    h = server.history
    h.record_event("POWER_LOSS", ts=100)
    h.record_event("POWER_RESTORED", ts=160)
    h.record_event("COMM_LOST", "upsd fora", ts=300)

    resp = await client.get("/v1/events/log", headers=client.auth)
    assert resp.status == 200
    rows = (await resp.json())["rows"]
    assert [r["type"] for r in rows] == ["COMM_LOST", "POWER_RESTORED", "POWER_LOSS"]

    resp = await client.get(
        "/v1/events/log?from=150&to=200", headers=client.auth
    )
    rows = (await resp.json())["rows"]
    assert [r["ts"] for r in rows] == [160]

    resp = await client.get(
        "/v1/events/log?types=POWER_LOSS,COMM_LOST", headers=client.auth
    )
    rows = (await resp.json())["rows"]
    assert {r["type"] for r in rows} == {"POWER_LOSS", "COMM_LOST"}
    assert rows[0]["detail"] == "upsd fora"

    resp = await client.get("/v1/events/log?limit=0", headers=client.auth)
    assert resp.status == 400
    resp = await client.get("/v1/events/log?from=9&to=1", headers=client.auth)
    assert resp.status == 400


async def test_events_delete_requires_to_and_removes_range(client, server):
    h = server.history
    h.record_event("POWER_LOSS", ts=100)
    h.record_event("POWER_RESTORED", ts=160)
    h.record_event("COMM_LOST", ts=300)

    # fence: sem token nao apaga nada
    resp = await client.delete("/v1/events/log?to=999")
    assert resp.status == 401

    # `to` obrigatorio: DELETE sem parametro jamais limpa o log
    resp = await client.delete("/v1/events/log", headers=client.auth)
    assert resp.status == 400
    assert "to" in (await resp.json())["erro"]

    resp = await client.delete("/v1/events/log?to=200", headers=client.auth)
    assert resp.status == 200
    assert (await resp.json())["removidos"] == 2
    rows = h.query_events(0, 2**33)
    assert [r["type"] for r in rows] == ["COMM_LOST"]


# --- Fase 3'-EXP: arming rules of PUT /v1/config (§7A.5) ------------------------------
import json as _json
import re as _re
import os as _os

from river_unifi_bridge.protect import (
    EV_ARMED, EV_DISARMED, ConfigHolder, ProtectionConfig, ProtectionPolicy,
)

REAL = {
    "identity": {"name": "r", "manufacturer": "EcoFlow", "model": "RIVER 3 Plus", "serial": "R3P-1"},
    "power": {"state": "ONLINE", "states": ["ONLINE"]},
    "battery": {"charge_percent": 80.0},
    "source": {"nut": True, "usb_hid": True, "usb_cdc": False,
               "driver_name": "usbhid-ups", "driver_version": "2.8.4"},
}
FAKE = {**REAL, "identity": {**REAL["identity"], "serial": "SIM0001"},
        "source": {**REAL["source"], "driver_name": "fake-nut-ups", "driver_version": "fake-nut-ups"}}


def _prot_env(tmp_path, arm_allowed: bool) -> str:
    key = tmp_path / "k"; key.write_text("k"); key.chmod(0o600)
    path = tmp_path / "prot.env"
    path.write_text(
        "RIVER_NAME=r\nNUT_HOST=127.0.0.1\nNUT_PORT=3493\nNUT_UPS=r\n"
        f"PROTECT_UDR7=1\nPROTECT_DRY_RUN=1\nUDR7_ARM_ALLOWED={'1' if arm_allowed else '0'}\n"
        f"UDR7_SSH_HOST=192.0.2.1\nUDR7_SSH_KEY={key}\nUDR7_EXPECTED_SERIAL=R3P-1\n"
        "UDR7_CUTOFF_PERCENT=10\nUDR7_SHUTDOWN_PERCENT=20\n",
        encoding="utf-8",
    )
    return str(path)


def _prot_server(tmp_path, arm_allowed: bool, extra=()):
    from river_unifi_bridge.config import load_config
    env = _prot_env(tmp_path, arm_allowed)
    from river_unifi_bridge.devices import DeviceStore
    from river_unifi_bridge.plugins.udr7_ssh import POWEROFF, legacy_instance
    cfg = load_config(env)
    instance = legacy_instance(cfg)
    holder = ConfigHolder(ProtectionConfig.from_instance(instance, cfg, shutdown_command=POWEROFF.argv))
    state = tmp_path / "state"
    policy = ProtectionPolicy(
        holder, runner=lambda *a, **k: None, keygen_runner=lambda *a, **k: None,
        wol_sender=lambda mac: None, shutdown_command=POWEROFF.argv,
        known_hosts_path=str(state / "kh"), armed_path=str(state / "udr7_armed.json"),
        runtime_path=str(state / "udr7_runtime.json"),
    )
    from river_unifi_bridge.plugins import Udr7SshPlugin

    plugin = Udr7SshPlugin(instance, holder, policy, cfg)
    store = DeviceStore(str(state / "devices.json"))
    store.save([plugin.instance, *[p.instance for p in extra if hasattr(p, "instance")]])
    srv = ApiServer(cfg=cfg, state=SharedState(), history=HistoryStore(str(tmp_path / "h.sqlite")),
                    env_path=env, restart_cb=lambda: None, token=TOKEN,
                    plugins=[plugin, *extra], store=store, state_dir=str(state))
    srv.store = store
    # Atalhos ad hoc para os testes: holder e policy continuam sendo lidos
    # diretamente por várias asserções, e o plugin é só o invólucro deles.
    srv.holder = holder
    srv.policy = policy
    srv.armed_path = str(state / "udr7_armed.json")
    srv.env = env
    return srv


@pytest.fixture
async def locked(tmp_path, aiohttp_client):
    import asyncio
    srv = _prot_server(tmp_path, arm_allowed=False)
    c = await aiohttp_client(srv.build_app()); c.auth = {"Authorization": f"Bearer {TOKEN}"}
    srv._loop = asyncio.get_running_loop()
    return srv, c


@pytest.fixture
async def unlocked(tmp_path, aiohttp_client):
    import asyncio
    srv = _prot_server(tmp_path, arm_allowed=True)
    c = await aiohttp_client(srv.build_app()); c.auth = {"Authorization": f"Bearer {TOKEN}"}
    srv._loop = asyncio.get_running_loop()
    return srv, c


async def _put(c, body):
    resp = await c.put("/v1/config", json=body, headers=c.auth)
    return resp.status, await resp.json()


async def test_put_file_only_key_is_400(locked):
    srv, c = locked
    before = open(srv.env).read()
    status, body = await _put(c, {"UDR7_ARM_ALLOWED": "1"})
    assert status == 400 and body["motivo"] == "chave_somente_arquivo"
    assert open(srv.env).read() == before


async def test_put_arming_refused_when_lock_closed(locked):
    srv, c = locked
    srv.state.update_snapshot(REAL)
    status, body = await _put(c, {"PROTECT_DRY_RUN": "0"})
    assert status == 409 and body["motivo"] == "armamento_bloqueado"
    assert not _os.path.exists(srv.armed_path)


async def test_put_refused_leaves_env_intact(locked):
    srv, c = locked
    srv.state.update_snapshot(REAL)
    before = open(srv.env).read()
    status, _ = await _put(c, {"PROTECT_DRY_RUN": "0", "UDR7_SSH_PORT": "2222"})
    assert status == 409
    assert open(srv.env).read() == before
    assert srv.cfg.protect_dry_run is True and srv.cfg.udr7_ssh_port == 22
    assert srv.holder.get().protect_dry_run is True


async def test_arming_without_snapshot_is_refused(unlocked):
    srv, c = unlocked
    status, body = await _put(c, {"PROTECT_DRY_RUN": "0"})
    assert status == 409 and body["motivo"] == "sem_snapshot"


async def test_arming_refused_when_comm_lost(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    srv.state.record_failure("upsd fora")        # snapshot survives, comm_ok does not
    status, body = await _put(c, {"PROTECT_DRY_RUN": "0"})
    assert status == 409 and body["motivo"] == "sem_snapshot"


async def test_arming_requires_real_source_snapshot(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(FAKE)              # simulator telemetry (serial SIM0001)
    status, body = await _put(c, {"PROTECT_DRY_RUN": "0"})
    assert status == 409 and body["motivo"] == "fonte_nao_real"
    srv.state.update_snapshot({**REAL, "identity": {**REAL["identity"], "serial": "R3P-2"}})
    status, body = await _put(c, {"PROTECT_DRY_RUN": "0"})
    assert status == 409 and body["motivo"] == "fonte_nao_real"
    assert not _os.path.exists(srv.armed_path)


async def test_arming_ok_writes_armed_file_and_emits(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    status, body = await _put(c, {"PROTECT_DRY_RUN": "0"})
    assert status == 200 and body["restart_required"] is False
    assert _os.path.exists(srv.armed_path)
    pins = _json.loads(open(srv.armed_path).read())["pins"]
    assert pins["udr7_ssh_host"] == "192.0.2.1" and pins["udr7_expected_serial"] == "R3P-1"
    assert [e["event"] for e in srv.state.events()] == [EV_ARMED]
    assert srv.history.query_events(0, 2**33)[0]["type"] == EV_ARMED
    assert "PROTECT_DRY_RUN=0" in open(srv.env).read()


async def test_armed_config_keys_are_frozen_and_restart_refused(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200
    for key, value in (("UDR7_SSH_HOST", "192.0.2.9"), ("NUT_PORT", "3494"),
                       ("UDR7_SHUTDOWN_PERCENT", "30"), ("UDR7_WOL_MAC", "aa:bb:cc:dd:ee:ff")):
        status, body = await _put(c, {key: value})
        assert status == 409 and body["motivo"] == "armado", key
    resp = await c.post("/v1/service/restart", headers=c.auth)
    assert resp.status == 409 and (await resp.json())["motivo"] == "armado"
    # Non-protection keys still flow normally while armed.
    assert (await _put(c, {"LOW_BATTERY_PERCENT": "25"}))[0] == 200


async def test_disarm_is_always_allowed_while_armed(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200
    status, _ = await _put(c, {"PROTECT_DRY_RUN": "1"})
    assert status == 200
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200     # re-arm (lock still open)
    status, _ = await _put(c, {"PROTECT_UDR7": "0"})
    assert status == 200
    assert (await _put(c, {"PROTECT_UDR7": "0", "PROTECT_DRY_RUN": "1"}))[0] == 200


@pytest.fixture
async def two_plugins(tmp_path, aiohttp_client):
    """UDR7 + FakePlugin: prova que a API fala com o REGISTRO, não com o UDR7."""
    import asyncio

    from fake_plugin import FakePlugin

    fake = FakePlugin()
    srv = _prot_server(tmp_path, arm_allowed=True, extra=(fake,))
    c = await aiohttp_client(srv.build_app()); c.auth = {"Authorization": f"Bearer {TOKEN}"}
    srv._loop = asyncio.get_running_loop()
    return srv, c, fake


async def test_health_lists_every_plugin_and_keeps_alias(two_plugins):
    from river_unifi_bridge.plugins import plugin_statuses

    srv, c, _fake = two_plugins
    srv.state.set_plugins(plugin_statuses(srv.plugins))
    body = await (await c.get("/v1/health", headers=c.auth)).json()
    assert [p["id"] for p in body["plugins"]] == ["udr7", "fake"]
    assert body["plugins"][1]["name"] == "Fake"
    # O alias continua sendo o do UDR7, e não o do primeiro da lista por acaso.
    assert body["udr7"] == body["plugins"][0]["state"]
    assert body["udr7_detail"] == body["plugins"][0]["detail"]


async def test_put_consults_every_plugin_before_writing(two_plugins):
    """A recusa do 2º plugin impede a GRAVAÇÃO — a ordem é autorizar, depois escrever."""
    srv, c, fake = two_plugins
    antes = open(srv.env, encoding="utf-8").read()
    fake.refuse = (409, "fake_recusa", "o plugin de teste recusou")
    status, body = await _put(c, {"LOW_BATTERY_PERCENT": "33"})
    assert status == 409 and body["motivo"] == "fake_recusa"
    assert open(srv.env, encoding="utf-8").read() == antes


async def test_put_notifies_every_plugin(two_plugins):
    srv, c, fake = two_plugins
    assert (await _put(c, {"LOW_BATTERY_PERCENT": "33"}))[0] == 200
    assert len(fake.applied) == 1        # o Fake também foi avisado da config nova


async def test_put_refreshes_health_immediately(unlocked):
    """O health não espera o próximo tick do laço para refletir o PUT."""
    srv, c = unlocked
    assert (await _put(c, {"UDR7_NAME": "Meu UDR"}))[0] == 200
    body = await (await c.get("/v1/health", headers=c.auth)).json()
    assert body["plugins"][0]["name"] == "Meu UDR"


async def test_restart_refused_when_any_plugin_armed(two_plugins):
    """Basta UM dispositivo armado para o reinício pela API ser recusado."""
    srv, c, fake = two_plugins
    fake._armed = True
    resp = await c.post("/v1/service/restart", headers=c.auth)
    assert resp.status == 409 and (await resp.json())["motivo"] == "armado"


async def test_file_only_key_is_refused_even_with_no_plugins(tmp_path, aiohttp_client):
    """A regra da trava de arquivo é GENÉRICA: vale sem plugin nenhum."""
    import asyncio

    srv = _prot_server(tmp_path, arm_allowed=True)
    srv.plugins = []
    c = await aiohttp_client(srv.build_app()); c.auth = {"Authorization": f"Bearer {TOKEN}"}
    srv._loop = asyncio.get_running_loop()
    status, body = await _put(c, {"UDR7_ARM_ALLOWED": "1"})
    assert status == 400 and body["motivo"] == "chave_somente_arquivo"


async def test_rename_allowed_while_armed(unlocked):
    """Renomear o dispositivo com a proteção ARMADA é permitido, e a quente.

    Nó da cena S4m: UDR7_NAME tem o prefixo UDR7_ e, sem o `- DEVICE_NAME_KEYS`
    em config.py, cairia em PROTECTION_KEYS — o PUT devolveria 409 `armado` e o
    usuário não conseguiria dar nome ao aparelho sem antes desarmar a proteção.
    """
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200
    assert srv.holder.get().armed
    status, _ = await _put(c, {"UDR7_NAME": "Meu UDR"})
    assert status == 200
    assert srv.holder.get().udr7_name == "Meu UDR"      # aplicou a quente
    assert srv.holder.get().armed                        # e não desarmou
    assert srv.policy.status()["name"] == "Meu UDR"


async def test_rename_empty_via_put_falls_back_to_default(unlocked):
    """PUT legado com nome vazio grava vazio no .env; a INSTÂNCIA (que exige nome)
    repõe o padrão, e é isso que o status() e a loja mostram."""
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"UDR7_NAME": "Meu UDR"}))[0] == 200
    assert srv.store.load()[0].name == "Meu UDR"           # espelho .env → loja
    assert (await _put(c, {"UDR7_NAME": ""}))[0] == 200
    assert "UDR7_NAME=\n" in open(srv.env, encoding="utf-8").read()
    assert srv.holder.get().udr7_name == "UDR7"
    assert srv.store.load()[0].name == "UDR7"
    assert srv.policy.status()["name"] == "UDR7"


async def test_rename_with_bad_shape_is_refused(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    status, body = await _put(c, {"UDR7_NAME": "x" * 33})
    assert status == 400
    assert srv.holder.get().udr7_name == "UDR7"


async def test_disarm_batched_with_other_key_is_refused(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200
    status, body = await _put(c, {"PROTECT_DRY_RUN": "1", "UDR7_SSH_PORT": "2222"})
    assert status == 409 and body["motivo"] == "armado"
    status, body = await _put(c, {"PROTECT_UDR7": "0", "UDR7_ARM_ALLOWED": "0"})
    assert status == 400 and body["motivo"] == "chave_somente_arquivo"   # 400 wins
    assert srv.holder.get().armed


async def test_disarm_removes_armed_file_and_emits_disarmed(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200
    assert _os.path.exists(srv.armed_path)
    assert (await _put(c, {"PROTECT_DRY_RUN": "1"}))[0] == 200
    assert not _os.path.exists(srv.armed_path)
    assert [e["event"] for e in srv.state.events()] == [EV_ARMED, EV_DISARMED]
    resp = await c.post("/v1/service/restart", headers=c.auth)
    assert resp.status == 202


async def test_protect_udr7_toggle_cannot_rearm_with_lock_closed(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200      # armed with the lock open
    # Owner re-locks (file + restart): simulate the restarted config.
    srv.cfg.udr7_arm_allowed = False
    srv.holder.replace(ProtectionConfig.from_cfg(srv.cfg))
    assert (await _put(c, {"PROTECT_UDR7": "0"}))[0] == 200          # disarm: always allowed
    assert (await _put(c, {"UDR7_SSH_HOST": "192.0.2.9"}))[0] == 200 # not armed: editable
    status, body = await _put(c, {"PROTECT_UDR7": "1"})              # re-arm needs the lock
    assert status == 409 and body["motivo"] == "armamento_bloqueado"
    assert not _os.path.exists(srv.armed_path)


async def test_health_exposes_udr7_detail_after_a_tick(unlocked):
    from river_unifi_bridge.model import snapshot_from_nut_vars
    srv, c = unlocked
    snap = snapshot_from_nut_vars("r", {"ups.status": "OL CHRG", "battery.charge": "80",
                                        "driver.name": "fake-nut-ups", "driver.version": "x",
                                        "device.serial": "SIM0001"})
    from river_unifi_bridge.plugins import plugin_statuses

    srv.policy.observe(snap, [])
    srv.state.set_plugins(plugin_statuses(srv.plugins))
    resp = await c.get("/v1/health", headers=c.auth)
    body = await resp.json()
    assert body["udr7"] == "fonte_nao_real"
    d = body["udr7_detail"]
    assert d["dry_run"] is True and d["source"] == "sintetica"
    assert d["source_detail"] == "telemetria_sintetica" and "lock_open" in d["warnings"]
    assert d["ssh_binary"] == srv.holder.get().ssh_binary
    # O alias e a entrada da lista descrevem o MESMO dispositivo.
    assert body["plugins"][0]["id"] == "udr7"
    assert body["plugins"][0]["state"] == body["udr7"]
    assert body["plugins"][0]["detail"] == d
    assert body["plugins"][0]["name"] == d["name"]


async def test_device_types_endpoint_matches_the_catalog(client):
    from river_unifi_bridge.plugins import type_catalog

    resp = await client.get("/v1/device-types", headers=client.auth)
    assert resp.status == 200
    assert (await resp.json()) == {"types": type_catalog()}
    assert (await client.get("/v1/device-types")).status == 401


# --- instâncias de dispositivos: /v1/devices (2026-09-03) ------------------------------
HOST = {"type": "ssh_host", "name": "NAS da sala",
        "fields": {"ssh_host": "192.0.2.5", "ssh_user": "admin", "ssh_key": "/tmp/k",
                   "shutdown_percent": 25, "shutdown_command": "sudo -n shutdown -h now"}}


async def _post(c, body):
    resp = await c.post("/v1/devices", json=body, headers=c.auth)
    return resp.status, (await resp.json())


async def _put_dev(c, dev_id, body):
    resp = await c.put(f"/v1/devices/{dev_id}", json=body, headers=c.auth)
    return resp.status, (await resp.json())


async def test_devices_list_get_and_post_create_ssh_host(unlocked):
    srv, c = unlocked
    body = await (await c.get("/v1/devices", headers=c.auth)).json()
    assert [d["id"] for d in body["devices"]] == ["udr7"]
    assert body["devices"][0]["type"] == "udr7_ssh" and body["devices"][0]["armed"] is False
    status, body = await _post(c, HOST)
    assert status == 201, body
    dev = body["device"]
    assert dev["type"] == "ssh_host" and dev["name"] == "NAS da sala"
    assert _re.fullmatch(r"sshhost_[0-9a-f]{8}", dev["id"])
    assert dev["enabled"] is False and dev["dry_run"] is True and dev["armed"] is False
    assert dev["fields"]["ssh_port"] == 22 and dev["fields"]["shutdown_command"] == "sudo -n shutdown -h now"
    assert dev["state"] == "desabilitado"
    # persistiu na loja, entrou no health e no GET por id
    assert [i.id for i in srv.store.load()] == ["udr7", dev["id"]]
    health = await (await c.get("/v1/health", headers=c.auth)).json()
    assert [p["id"] for p in health["plugins"]] == ["udr7", dev["id"]]
    assert health["plugins"][1]["type"] == "ssh_host" and health["udr7"] == health["plugins"][0]["state"]
    resp = await c.get(f"/v1/devices/{dev['id']}", headers=c.auth)
    assert resp.status == 200 and (await resp.json())["device"]["id"] == dev["id"]
    assert (await c.get("/v1/devices/nao_existe", headers=c.auth)).status == 404


async def test_devices_post_refusals(unlocked):
    srv, c = unlocked
    antes = srv.store.load()
    assert (await _post(c, {**HOST, "type": "torradeira"}))[0:1] == (400,)
    status, body = await _post(c, {**HOST, "type": "torradeira"})
    assert body["motivo"] == "tipo_desconhecido"
    status, body = await _post(c, {**HOST, "name": ""})
    assert status == 400 and body["motivo"] == "validacao"
    status, body = await _post(c, {**HOST, "fields": {**HOST["fields"], "ssh_port": "70000"}})
    assert status == 400 and "ssh_port" in body["erro"]
    status, body = await _post(c, {**HOST, "fields": {**HOST["fields"], "shutdown_command": "rm -rf /"}})
    assert status == 400 and "shutdown_command" in body["erro"]
    status, body = await _post(c, {**HOST, "name": "udr7"})            # casefold do UDR7
    assert status == 409 and body["motivo"] == "nome_duplicado"
    assert [i.id for i in srv.store.load()] == [i.id for i in antes]  # nada gravado


async def test_devices_post_cannot_create_armed(unlocked):
    """Nó da cena S4v: armar é ato separado, pelo PUT."""
    srv, c = unlocked
    status, body = await _post(c, {**HOST, "enabled": True, "dry_run": False})
    assert status == 400 and body["motivo"] == "armar_no_post"
    assert [i.id for i in srv.store.load()] == ["udr7"]


async def test_devices_put_arming_rules_and_frozen_fields(tmp_path, aiohttp_client):
    import asyncio
    srv = _prot_server(tmp_path, arm_allowed=False)
    c = await aiohttp_client(srv.build_app()); c.auth = {"Authorization": f"Bearer {TOKEN}"}
    srv._loop = asyncio.get_running_loop()
    dev = (await _post(c, HOST))[1]["device"]
    # trava fechada → armamento_bloqueado, sem armed.json
    status, body = await _put_dev(c, dev["id"], {"enabled": True, "dry_run": False})
    assert status == 409 and body["motivo"] == "armamento_bloqueado"
    assert not _os.path.exists(str(tmp_path / "state" / f"{dev['id']}_armed.json"))
    # trava aberta, sem snapshot → sem_snapshot; fonte sintética → fonte_nao_real
    (tmp_path / "b").mkdir()
    srv2 = _prot_server(tmp_path / "b", arm_allowed=True)
    c2 = await aiohttp_client(srv2.build_app()); c2.auth = c.auth
    srv2._loop = asyncio.get_running_loop()
    dev2 = (await _post(c2, HOST))[1]["device"]
    status, body = await _put_dev(c2, dev2["id"], {"enabled": True, "dry_run": False})
    assert status == 409 and body["motivo"] == "sem_snapshot"
    srv2.state.update_snapshot(FAKE)
    status, body = await _put_dev(c2, dev2["id"], {"enabled": True, "dry_run": False})
    assert status == 409 and body["motivo"] == "fonte_nao_real"
    # fonte real com o serial esperado do NÚCLEO (D16) → arma; armed.json da instância
    srv2.state.update_snapshot(REAL)
    status, body = await _put_dev(c2, dev2["id"], {"enabled": True, "dry_run": False})
    assert status == 200 and body["device"]["armed"] is True, body
    armed_path = tmp_path / "b" / "state" / f"{dev2['id']}_armed.json"
    assert armed_path.exists()
    pins = _json.loads(armed_path.read_text())["pins"]
    assert pins["shutdown_command"] == "sudo -n shutdown -h now" and pins["udr7_expected_serial"] == "R3P-1"
    assert [e["event"] for e in srv2.state.events()][-1] == "SSH_HOST_ARMED"
    assert srv2.history.query_events(0, 2**33)[0] == {
        **srv2.history.query_events(0, 2**33)[0], "type": "SSH_HOST_ARMED", "device": dev2["id"]}
    # armado: campos congelados (409 armado nomeando a instância); nome livre
    status, body = await _put_dev(c2, dev2["id"], {"fields": {"ssh_port": 2222}})
    assert status == 409 and body["motivo"] == "armado" and "NAS da sala" in body["erro"]
    status, body = await _put_dev(c2, dev2["id"], {"name": "NAS do escritório"})
    assert status == 200 and body["device"]["name"] == "NAS do escritório" and body["device"]["armed"]
    # o UDR7 (desarmado) continua editável enquanto o host está armado
    assert (await _put_dev(c2, "udr7", {"fields": {"ssh_port": 2222}}))[0] == 200
    # desarme puro sempre aceito; apaga o armed.json
    status, body = await _put_dev(c2, dev2["id"], {"dry_run": True})
    assert status == 200 and body["device"]["armed"] is False
    assert not armed_path.exists()
    assert "SSH_HOST_DISARMED" in [e["event"] for e in srv2.state.events()]


async def test_other_armed_instance_does_not_veto_disarm(unlocked):
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    dev = (await _post(c, HOST))[1]["device"]
    assert (await _put_dev(c, dev["id"], {"enabled": True, "dry_run": False}))[0] == 200
    assert (await _put(c, {"PROTECT_DRY_RUN": "0"}))[0] == 200        # udr7 arma pela via legada
    assert (await _put_dev(c, "udr7", {"dry_run": True}))[0] == 200   # desarme do udr7 com o host armado
    assert (await _put_dev(c, dev["id"], {"enabled": False}))[0] == 200


async def test_devices_delete_refused_while_armed(unlocked):
    """Nó da cena S4q."""
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    dev = (await _post(c, HOST))[1]["device"]
    assert (await _put_dev(c, dev["id"], {"enabled": True, "dry_run": False}))[0] == 200
    resp = await c.delete(f"/v1/devices/{dev['id']}", headers=c.auth)
    assert resp.status == 409 and (await resp.json())["motivo"] == "armado"
    assert [i.id for i in srv.store.load()] == ["udr7", dev["id"]]


async def test_devices_delete_removes_instance_state_and_keeps_known_hosts(unlocked):
    srv, c = unlocked
    dev = (await _post(c, HOST))[1]["device"]
    state = _os.path.dirname(srv.armed_path)
    for suffix in ("_armed.json", "_runtime.json", "_known_hosts"):
        open(_os.path.join(state, f"{dev['id']}{suffix}"), "w").close()
    resp = await c.delete(f"/v1/devices/{dev['id']}", headers=c.auth)
    assert resp.status == 204
    assert [i.id for i in srv.store.load()] == ["udr7"]
    assert not _os.path.exists(_os.path.join(state, f"{dev['id']}_armed.json"))
    assert not _os.path.exists(_os.path.join(state, f"{dev['id']}_runtime.json"))
    assert _os.path.exists(_os.path.join(state, f"{dev['id']}_known_hosts"))
    health = await (await c.get("/v1/health", headers=c.auth)).json()
    assert [p["id"] for p in health["plugins"]] == ["udr7"]
    assert (await c.delete("/v1/devices/nao_existe", headers=c.auth)).status == 404
    # remover o udr7 desarmado é permitido: o alias volta a "desabilitado"
    assert (await c.delete("/v1/devices/udr7", headers=c.auth)).status == 204
    health = await (await c.get("/v1/health", headers=c.auth)).json()
    assert health["udr7"] == "desabilitado" and health["plugins"] == []


async def test_devices_put_udr7_mirrors_env_and_cfg(unlocked):
    srv, c = unlocked
    status, body = await _put_dev(c, "udr7", {"name": "Console", "fields": {"ssh_port": 2222}})
    assert status == 200
    env = open(srv.env, encoding="utf-8").read()
    assert "UDR7_SSH_PORT=2222" in env and "UDR7_NAME=Console" in env
    assert srv.cfg.udr7_ssh_port == 2222 and srv.cfg.udr7_name == "Console"
    assert srv.store.load()[0].fields["ssh_port"] == 2222
    assert srv.holder.get().udr7_ssh_port == 2222 and srv.policy.status()["name"] == "Console"
    status, body = await _put_dev(c, "udr7", {"type": "ssh_host"})
    assert status == 400 and "imutáveis" in body["erro"]


async def test_core_river_keys_refresh_every_instance(unlocked):
    """Aceitação 6c: série esperada e corte são do núcleo e chegam a TODA instância a quente."""
    srv, c = unlocked
    dev = (await _post(c, HOST))[1]["device"]
    assert (await _put(c, {"UDR7_CUTOFF_PERCENT": "12", "UDR7_EXPECTED_SERIAL": "R3P-9"}))[0] == 200
    for plugin in srv.plugins:
        assert plugin.status()["cutoff"] == 12
        assert plugin._holder.get().udr7_expected_serial == "R3P-9"
    body = await (await c.get(f"/v1/devices/{dev['id']}", headers=c.auth)).json()
    assert body["device"]["fields"].get("cutoff_percent") is None       # não é campo de instância


async def test_sse_delivers_past_the_hundredth_event(client, server):
    """A fila guarda 100 eventos; o cliente tem de continuar recebendo depois disso.

    Em DUAS fases, que é como o defeito aparece: o cliente recebe um primeiro lote
    (o cursor avança além de 100), a fila satura e descarta os mais antigos, e só
    então chegam eventos novos. Orientado por índice, o cursor congela e nada mais
    sai; orientado pela sequência, que só cresce, tudo continua chegando.
    """
    import asyncio
    import json as _j

    async with client.get("/v1/events", headers=client.auth) as resp:
        assert resp.status == 200
        recebidos: list[str] = []

        async def ler_ate(alvo: str) -> bool:
            for _ in range(2000):
                linha = (await resp.content.readline()).decode()
                if linha.startswith("data: ") and '"event"' in linha:
                    recebidos.append(_j.loads(linha[6:])["event"])
                    if recebidos[-1] == alvo:
                        return True
            return False

        for i in range(120):                      # 1.ª fase: o cursor passa de 100
            server.state.add_event(f"E{i}")
        assert await asyncio.wait_for(ler_ate("E119"), timeout=10)

        for i in range(120, 150):                 # 2.ª fase: fila já saturada
            server.state.add_event(f"E{i}")
        assert await asyncio.wait_for(ler_ate("E149"), timeout=10)

    assert recebidos[-1] == "E149"
    assert recebidos == sorted(recebidos, key=lambda e: int(e[1:]))
    seqs = [e["seq"] for e in server.state.events()]
    assert seqs == sorted(seqs) and len(seqs) == 100


async def test_restart_without_a_loop_refuses_instead_of_crashing(server, aiohttp_client):
    """Servidor sem laço não tem como se reiniciar: recusa com texto humano.

    Era um `assert`: virava 500 sem explicação, e com o Python otimizado (-O)
    sumiria, deixando um `None.call_later` no lugar.
    """
    c = await aiohttp_client(server.build_app())
    c.auth = {"Authorization": f"Bearer {TOKEN}"}
    server._loop = None
    resp = await c.post("/v1/service/restart", headers=c.auth)
    assert resp.status == 503
    body = await resp.json()
    assert body["motivo"] == "servidor_sem_laco"
    assert "reinicie pelo terminal" in body["erro"]
    assert server.restarts == []


async def test_config_put_reports_a_disk_failure_instead_of_a_silent_500(client, server, monkeypatch):
    """Se o arquivo do serviço não pode ser gravado, o usuário ouve isso."""
    from river_unifi_bridge import api as api_mod

    def disco_cheio(*_a, **_k):
        raise OSError(28, "No space left on device")

    monkeypatch.setattr(api_mod, "update_env_file", disco_cheio)
    resp = await client.put("/v1/config", json={"LOW_BATTERY_PERCENT": 33}, headers=client.auth)
    assert resp.status == 500
    body = await resp.json()
    assert body["motivo"] == "arquivo_env"
    assert "nada foi alterado" in body["erro"]
    assert server.cfg.low_battery_percent != 33      # nada aplicado a quente


async def test_clearing_events_also_forgets_them_in_memory(client, server):
    """Limpar tem de valer para quem conectar depois, não só para o banco.

    A fila da memória é o que o SSE entrega a QUEM CONECTA. Sem limpá-la, os
    eventos apagados voltavam à tela na reconexão seguinte — o dono limpava e
    eles reapareciam.
    """
    import time as _t

    server.state.add_event("POWER_LOSS", {"reason": "queda"})
    server.history.record_event("POWER_LOSS", "queda")
    assert len(server.state.events()) == 1

    agora = int(_t.time()) + 1
    resp = await client.delete(f"/v1/events/log?to={agora}", headers=client.auth)
    assert resp.status == 200
    assert server.state.events() == []          # a fila do SSE esqueceu junto
    rows = await (await client.get("/v1/events/log", headers=client.auth)).json()
    assert rows["rows"] == []


async def test_clearing_a_window_keeps_what_is_outside_it(client, server):
    """Limpar 'anteriores a 7 dias' não pode levar o evento de agora junto."""
    import time as _t

    server.state.add_event("COMM_LOST", {"reason": "upsd fora"})
    antigo = int(_t.time()) - 30 * 86400
    resp = await client.delete(f"/v1/events/log?to={antigo}", headers=client.auth)
    assert resp.status == 200
    assert [e["event"] for e in server.state.events()] == ["COMM_LOST"]


async def test_disarming_is_never_refused_by_a_full_disk_with_the_real_wiring(unlocked, monkeypatch):
    """A cerca do desarme, agora na fiação de PRODUÇÃO: com loja e com plugin.

    A primeira versão deste teste usava um servidor sem loja de dispositivos e
    não tocava a SEGUNDA gravação em disco do mesmo pedido — que existia e
    devolvia 500 cru, com a proteção já desarmada por dentro (revisão fria, 2.ª
    rodada). As chaves do desarme são chaves legadas: elas passam pelos dois
    caminhos de escrita.
    """
    from river_unifi_bridge import api as api_mod

    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    # Arma de verdade primeiro, para o desarme ter o que desfazer.
    status, _ = await _put(c, {"PROTECT_UDR7": "1", "PROTECT_DRY_RUN": "0"})
    assert status == 200
    assert _os.path.exists(srv.armed_path)

    def disco_cheio(*_a, **_k):
        raise OSError(28, "No space left on device")

    monkeypatch.setattr(api_mod, "update_env_file", disco_cheio)
    if srv.store is not None:
        monkeypatch.setattr(type(srv.store), "save", disco_cheio)

    status, corpo = await _put(c, {"PROTECT_DRY_RUN": "1"})
    assert status == 200, corpo            # o botão de parada não é recusado
    assert not _os.path.exists(srv.armed_path)   # e desarmou de verdade
    # E a tela recebe o estado novo: o health foi republicado no fim do PUT.
    assert srv.state.health()["plugins"][0]["detail"]["dry_run"] is True


async def test_disarming_is_never_refused_by_a_full_disk(client, server, monkeypatch):
    """O botão de parada vale mesmo com o disco cheio.

    Disco cheio é exatamente quando o dono quer desarmar. Recusar aí deixaria a
    proteção armada por causa de um arquivo — o pior desfecho possível.
    """
    from river_unifi_bridge import api as api_mod

    def disco_cheio(*_a, **_k):
        raise OSError(28, "No space left on device")

    monkeypatch.setattr(api_mod, "update_env_file", disco_cheio)

    # Desarme puro: aceito, aplicado a quente, com aviso no log.
    resp = await client.put("/v1/config", json={"PROTECT_DRY_RUN": "1"}, headers=client.auth)
    assert resp.status == 200
    assert server.cfg.protect_dry_run is True

    resp = await client.put("/v1/config", json={"PROTECT_UDR7": "0"}, headers=client.auth)
    assert resp.status == 200
    assert server.cfg.protect_udr7 is False

    # Qualquer outra mudança continua sendo 500 sem aplicar nada.
    antes = server.cfg.low_battery_percent
    resp = await client.put("/v1/config", json={"LOW_BATTERY_PERCENT": 33}, headers=client.auth)
    assert resp.status == 500 and (await resp.json())["motivo"] == "arquivo_env"
    assert server.cfg.low_battery_percent == antes

    # Desarme MISTURADO com outra chave não é desarme puro: recusa.
    resp = await client.put("/v1/config",
                            json={"PROTECT_DRY_RUN": "1", "LOW_BATTERY_PERCENT": 44},
                            headers=client.auth)
    assert resp.status == 500


async def test_clearing_a_window_leaves_the_memory_in_step_with_the_database(client, server):
    """A faixa apagada da memória é a mesma do banco, nos dois lados."""
    import time as _t

    agora = int(_t.time())
    server.state.add_event("POWER_LOSS", {})
    # Faixa que TERMINA antes do evento: nada some.
    resp = await client.delete(f"/v1/events/log?from=0&to={agora - 3600}", headers=client.auth)
    assert resp.status == 200
    assert len(server.state.events()) == 1
    # Faixa que COMEÇA depois do evento: também não some (era o defeito).
    resp = await client.delete(f"/v1/events/log?from={agora + 60}&to={agora + 120}",
                               headers=client.auth)
    assert resp.status == 200
    assert len(server.state.events()) == 1
    # Faixa que contém o evento: some.
    resp = await client.delete(f"/v1/events/log?from={agora - 60}&to={agora + 60}",
                               headers=client.auth)
    assert resp.status == 200
    assert server.state.events() == []
