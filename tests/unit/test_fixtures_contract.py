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
