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
    assert body["unifi"] == "pendente_fase_3"
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
