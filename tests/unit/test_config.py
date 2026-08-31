"""Fence tests for the .env allowlist parser (spec §22).

These are the tests the gate's mutation scene relies on: if the allowlist or
the required-key check is removed from config.py, they MUST fail.
"""

import pytest

from river_unifi_bridge.config import ConfigError, allowlist_keys, load_config

MINIMAL = """RIVER_NAME=river-office
NUT_HOST=127.0.0.1
NUT_PORT=3493
NUT_UPS=river-office
"""


def write(tmp_path, content):
    path = tmp_path / "bridge.env"
    path.write_text(content, encoding="utf-8")
    return str(path)


def test_minimal_config_parses_with_defaults(tmp_path):
    cfg = load_config(write(tmp_path, MINIMAL))
    assert cfg.river_name == "river-office"
    assert cfg.nut_port == 3493
    assert cfg.poll_interval_seconds == 2
    assert cfg.read_only is True
    assert cfg.ui_api_port == 35493
    assert cfg.warnings == []


def test_unknown_key_is_reported_with_line_number(tmp_path):
    cfg = load_config(write(tmp_path, MINIMAL + "TYPO_KEY=1\n"))
    assert len(cfg.warnings) == 1
    assert ":5:" in cfg.warnings[0]
    assert "TYPO_KEY" in cfg.warnings[0]


def test_missing_required_key_fails(tmp_path):
    with pytest.raises(ConfigError, match="obrigatórias"):
        load_config(write(tmp_path, "RIVER_NAME=x\nNUT_HOST=h\nNUT_PORT=3493\n"))


def test_empty_required_value_fails(tmp_path):
    content = MINIMAL.replace("NUT_UPS=river-office", "NUT_UPS=")
    with pytest.raises(ConfigError, match="NUT_UPS"):
        load_config(write(tmp_path, content))


def test_out_of_range_int_fails_with_line(tmp_path):
    with pytest.raises(ConfigError, match="faixa"):
        load_config(write(tmp_path, MINIMAL + "POLL_INTERVAL_SECONDS=999\n"))


def test_bad_bool_fails(tmp_path):
    with pytest.raises(ConfigError, match="booleano"):
        load_config(write(tmp_path, MINIMAL + "READ_ONLY=talvez\n"))


def test_inline_comment_is_rejected_not_silently_parsed(tmp_path):
    # House rule: comments only on their own line. An inline comment corrupts
    # the value and must fail loudly for ints, never parse as something else.
    with pytest.raises(ConfigError):
        load_config(write(tmp_path, MINIMAL + "POLL_INTERVAL_SECONDS=2  # rapido\n"))


def test_missing_file_fails(tmp_path):
    with pytest.raises(ConfigError, match="não encontrado"):
        load_config(str(tmp_path / "nope.env"))


def test_example_file_in_repo_parses(tmp_path):
    import pathlib

    example = pathlib.Path(__file__).parents[2] / "config" / "river-unifi-bridge.env.example"
    cfg = load_config(str(example))
    assert cfg.warnings == []
    assert cfg.unifi_host == ""


def test_allowlist_matches_spec_keys():
    expected = {
        "RIVER_NAME", "NUT_HOST", "NUT_PORT", "NUT_UPS",
        "UNIFI_HOST", "UNIFI_VERIFY_TLS",
        "POLL_INTERVAL_SECONDS", "READ_ONLY", "EMULATE_MODEL",
        "POWER_LOSS_DELAY_SECONDS", "RESTORE_DELAY_SECONDS",
        "COMM_LOSS_DELAY_SECONDS", "LOW_BATTERY_PERCENT",
        "UI_API_ENABLED", "UI_API_PORT", "HISTORY_RETENTION_DAYS",
    }
    assert set(allowlist_keys()) == expected
