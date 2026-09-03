"""Contract fixtures (§7A.3): the SAME JSON files are decoded by Swift
(macos/RiverBridge/Tests). If the Python shape drifts, this fails; if the
Swift models drift, `swift test` fails. Both sides break loudly together."""

import json
import pathlib

from river_unifi_bridge.api import _empty_state
from river_unifi_bridge.model import snapshot_from_nut_vars

FIXTURES = pathlib.Path(__file__).parents[1] / "fixtures"


def load(name):
    with open(FIXTURES / f"{name}.json", encoding="utf-8") as fh:
        return json.load(fh)


def test_state_nulls_fixture_matches_code():
    assert load("state_nulls") == _empty_state("river-office", False, None)


def test_state_online_fixture_matches_code():
    snap = snapshot_from_nut_vars(
        "river-office",
        {
            "ups.status": "OL CHRG", "battery.charge": "87",
            "battery.runtime": "3600", "ups.load": "12",
            "input.voltage": "230.0", "output.voltage": "230.0",
            "ups.realpower": "45", "device.mfr": "EcoFlow",
            "device.model": "RIVER 3 Plus", "device.serial": "SIM0001",
            "driver.name": "fake-nut-ups", "driver.version": "fake-nut-ups",
            "battery.charge.low": "10",
        },
    ).to_dict()
    snap["timestamp"] = "2026-08-31T17:00:00+00:00"  # fixture freezes the clock
    assert load("state_online") == snap


def test_health_udr7_fixture_matches_code():
    from river_unifi_bridge.state import SharedState

    fixture = load("health_udr7")
    state = SharedState()
    # A lista como o daemon publica: o alias udr7/udr7_detail é derivado dela.
    state.set_plugins(fixture["plugins"])
    assert state.health() == fixture


def test_health_legacy_fixture_is_swift_only():
    # Decoded only by Swift (udr7 absent -> nil); the daemon never emits it any more.
    legacy = load("health_legacy")
    assert "udr7" not in legacy and "udr7_detail" not in legacy


def test_device_types_fixture_matches_code():
    """O catálogo de tipos que o Swift decodifica é o que o daemon publica; se um
    campo mudar de nome, faixa ou lista, os dois lados quebram juntos."""
    from river_unifi_bridge.plugins import type_catalog

    assert load("device_types") == {"types": type_catalog()}


# --- instâncias (2026-09-03): o mesmo JSON que o Swift decodifica ------------------
def devices_fixture_objects():
    """udr7 migrado + dois hosts SSH, com ids e datas fixos: determinístico."""
    from river_unifi_bridge.config import BridgeConfig
    from river_unifi_bridge.devices import DeviceInstance
    from river_unifi_bridge.plugins import build_plugins, plugin_statuses
    from river_unifi_bridge.plugins.udr7_ssh import legacy_instance

    cfg = BridgeConfig(river_name="river-office", nut_host="127.0.0.1", nut_port=3493,
                       nut_ups="river-office", udr7_ssh_host="192.0.2.1",
                       udr7_expected_serial="R3P-TEST-0001", udr7_cutoff_percent=10,
                       udr7_shutdown_percent=20, protect_udr7=True)
    ts = "2026-09-03T00:00:00-0300"
    udr7 = legacy_instance(cfg)
    udr7.created_at = udr7.updated_at = ts
    nas = DeviceInstance(id="sshhost_3fa9c1d2", type="ssh_host", name="NAS da sala",
                         fields={"ssh_host": "192.0.2.5", "ssh_port": 22, "ssh_user": "admin",
                                 "ssh_key": "/Users/x/.ssh/river-bridge-sshhost_3fa9c1d2",
                                 "shutdown_percent": 25, "discharge_seconds_per_pct": 0,
                                 "runtime_minutes": 0, "min_outage_seconds": 0,
                                 "confirm_seconds": 6, "retry_max": 3,
                                 "shutdown_command": "sudo -n shutdown -h now"},
                         created_at=ts, updated_at=ts)
    srv = DeviceInstance(id="sshhost_7b2e4d10", type="ssh_host", name="Servidor",
                         fields={"ssh_host": "192.0.2.6", "ssh_port": 2222, "ssh_user": "ops",
                                 "ssh_key": "/Users/x/.ssh/river-bridge-sshhost_7b2e4d10",
                                 "shutdown_percent": 30, "discharge_seconds_per_pct": 0,
                                 "runtime_minutes": 0, "min_outage_seconds": 0,
                                 "confirm_seconds": 6, "retry_max": 3,
                                 "shutdown_command": "systemctl poweroff"},
                         enabled=True, created_at=ts, updated_at=ts)
    devices = [udr7, nas, srv]
    statuses = plugin_statuses(build_plugins(devices, cfg, "/tmp/estado-fixture"))
    for entry in statuses:                       # a fixture documenta o binário de produção;
        entry["detail"]["ssh_binary"] = "/usr/bin/ssh"   # o conftest aponta para um stub
    return cfg, devices, statuses


def test_devices_tres_fixture_matches_code():
    _cfg, devices, _statuses = devices_fixture_objects()
    assert load("devices_tres") == {"devices": [d.to_json() for d in devices]}


def test_health_dispositivos_fixture_matches_code():
    from river_unifi_bridge.state import SharedState

    _cfg, _devices, statuses = devices_fixture_objects()
    state = SharedState()
    state.set_plugins(statuses)
    fixture = load("health_dispositivos")
    assert fixture == state.health()
    assert [p["id"] for p in fixture["plugins"]] == ["udr7", "sshhost_3fa9c1d2", "sshhost_7b2e4d10"]
    assert fixture["udr7"] == fixture["plugins"][0]["state"]        # alias = instância migrada
