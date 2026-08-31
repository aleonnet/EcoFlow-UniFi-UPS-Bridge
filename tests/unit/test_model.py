"""Normalization tests (spec §5.6) and honesty rules (§5.5: absent = None)."""

from river_unifi_bridge.model import (
    normalize_status,
    primary_state,
    snapshot_from_nut_vars,
)


def test_status_map_single_and_combined():
    assert normalize_status("OL") == (["ONLINE"], [])
    states, unknown = normalize_status("OB DISCHRG LB")
    assert states == ["ON_BATTERY", "DISCHARGING", "LOW_BATTERY"]
    assert unknown == []


def test_unknown_token_preserved_never_guessed():
    states, unknown = normalize_status("OL FSD")
    assert states == ["ONLINE"]
    assert unknown == ["FSD"]


def test_primary_state_priority():
    assert primary_state(["ON_BATTERY", "ONLINE"]) == "ON_BATTERY"
    assert primary_state(["ONLINE", "CHARGING"]) == "ONLINE"
    assert primary_state([]) == "UNKNOWN"


def test_missing_vars_stay_none():
    snap = snapshot_from_nut_vars("river-office", {"ups.status": "OL"})
    d = snap.to_dict()
    assert d["battery"]["charge_percent"] is None
    assert d["power"]["input_voltage_v"] is None
    assert d["identity"]["serial"] is None
    assert d["power"]["state"] == "ONLINE"
    assert d["power"]["input_present"] is True


def test_full_snapshot_maps_fields():
    snap = snapshot_from_nut_vars(
        "river-office",
        {
            "ups.status": "OB DISCHRG",
            "battery.charge": "42",
            "battery.runtime": "1680",
            "ups.load": "12",
            "device.mfr": "EcoFlow",
            "device.model": "RIVER 3 Plus",
        },
    )
    assert snap.charge_percent == 42.0
    assert snap.runtime_seconds == 1680.0
    assert snap.state == "ON_BATTERY"
    assert snap.input_present is False
    assert snap.model == "RIVER 3 Plus"
    assert snap.timestamp  # RFC3339, always stamped


def test_non_numeric_value_kept_visible_not_invented():
    snap = snapshot_from_nut_vars("x", {"battery.charge": "n/a"})
    assert snap.charge_percent is None
    assert "battery.charge=n/a" in snap.unknown_tokens
