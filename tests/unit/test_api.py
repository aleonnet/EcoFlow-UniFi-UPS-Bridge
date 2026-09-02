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
    cfg = load_config(env)
    holder = ConfigHolder(ProtectionConfig.from_cfg(cfg))
    state = tmp_path / "state"
    policy = ProtectionPolicy(
        holder, runner=lambda *a, **k: None, keygen_runner=lambda *a, **k: None,
        wol_sender=lambda mac: None,
        known_hosts_path=str(state / "kh"), armed_path=str(state / "udr7_armed.json"),
        runtime_path=str(state / "udr7_runtime.json"),
    )
    from river_unifi_bridge.plugins import Udr7SshPlugin

    plugin = Udr7SshPlugin(holder, policy)
    srv = ApiServer(cfg=cfg, state=SharedState(), history=HistoryStore(str(tmp_path / "h.sqlite")),
                    env_path=env, restart_cb=lambda: None, token=TOKEN,
                    plugins=[plugin, *extra])
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
    """PUT com nome vazio grava vazio; quem repõe o padrão é o status()."""
    srv, c = unlocked
    srv.state.update_snapshot(REAL)
    assert (await _put(c, {"UDR7_NAME": "Meu UDR"}))[0] == 200
    assert (await _put(c, {"UDR7_NAME": ""}))[0] == 200
    assert srv.holder.get().udr7_name == ""
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
