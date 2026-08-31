"""Parser tests for the NUT client (pure functions, no network)."""

from river_unifi_bridge.nut import parse_list_var


def test_parse_list_var_strips_quotes():
    lines = [
        'VAR river-office battery.charge "87"',
        'VAR river-office ups.status "OL CHRG"',
        'VAR river-office device.model "RIVER 3 Plus"',
    ]
    out = parse_list_var(lines, "river-office")
    assert out == {
        "battery.charge": "87",
        "ups.status": "OL CHRG",
        "device.model": "RIVER 3 Plus",
    }


def test_parse_ignores_lines_for_other_ups():
    lines = ['VAR other battery.charge "10"', 'VAR river-office ups.load "12"']
    assert parse_list_var(lines, "river-office") == {"ups.load": "12"}


def test_parse_empty_payload():
    assert parse_list_var([], "x") == {}
