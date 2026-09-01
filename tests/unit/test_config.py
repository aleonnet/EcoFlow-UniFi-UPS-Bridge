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
        # Fase 3'-EXP (spec §22 bloco 6)
        "PROTECT_UDR7", "PROTECT_DRY_RUN", "UDR7_ARM_ALLOWED",
        "UDR7_SSH_HOST", "UDR7_SSH_PORT", "UDR7_SSH_USER", "UDR7_SSH_KEY",
        "UDR7_EXPECTED_SERIAL", "UDR7_CUTOFF_PERCENT", "UDR7_SHUTDOWN_PERCENT",
        "UDR7_DISCHARGE_SECONDS_PER_PCT", "UDR7_RUNTIME_MINUTES",
        "UDR7_MIN_OUTAGE_SECONDS", "UDR7_CONFIRM_SECONDS", "UDR7_RETRY_MAX",
        "UDR7_WOL_MAC",
    }
    assert set(allowlist_keys()) == expected
    assert len(expected) == 32


@pytest.mark.parametrize(
    "key,value",
    [
        ("UDR7_SSH_USER", "-oProxyCommand=/bin/echo"),
        ("UDR7_SSH_USER", "--"),
        ("UDR7_SSH_USER", "-E"),
        ("UDR7_SSH_USER", "-J"),
        ("UDR7_SSH_USER", "root evil"),
        ("UDR7_SSH_USER", "1234"),               # numeric-only (first char must be a letter)
        ("UDR7_SSH_USER", "r" * 33),
        ("UDR7_SSH_HOST", "-oProxyCommand=x"),
        ("UDR7_SSH_HOST", "host name"),
        ("UDR7_SSH_HOST", "a_b"),
        ("UDR7_SSH_HOST", "::1"),
        ("UDR7_SSH_KEY", "~/.ssh/id_ed25519"),
        ("UDR7_SSH_KEY", "relative/key"),
        ("UDR7_SSH_KEY", "-i"),
        ("UDR7_EXPECTED_SERIAL", "SIM0001"),      # simulator serial can never be registered
        ("UDR7_EXPECTED_SERIAL", "has space"),
        ("UDR7_WOL_MAC", "AA:BB:CC:DD:EE"),
        ("UDR7_WOL_MAC", "AA:BB-CC:DD-EE:FF"),    # mixed separators
        ("UDR7_WOL_MAC", "GG:BB:CC:DD:EE:FF"),
    ],
)
def test_protection_string_shapes_are_rejected_in_file_and_put(tmp_path, key, value):
    from river_unifi_bridge.config import validate_update

    with pytest.raises(ConfigError, match=key):
        load_config(write(tmp_path, MINIMAL + f"{key}={value}\n"))
    with pytest.raises(ConfigError, match=key):
        validate_update(key, value)


def test_protection_string_with_embedded_newline_is_rejected_by_put():
    from river_unifi_bridge.config import validate_update

    with pytest.raises(ConfigError, match="UDR7_SSH_USER"):
        validate_update("UDR7_SSH_USER", "root\nUDR7_SSH_HOST=evil")


@pytest.mark.parametrize(
    "key,value",
    [
        ("UDR7_SSH_USER", "root"),
        ("UDR7_SSH_USER", "svc.bridge-01"),
        ("UDR7_SSH_HOST", "192.168.1.1"),
        ("UDR7_SSH_HOST", "udr7.home.arpa"),
        ("UDR7_SSH_KEY", "/Users/svc/.ssh/river-bridge-udr7"),
        ("UDR7_EXPECTED_SERIAL", "R3P-1234567890"),
        ("UDR7_WOL_MAC", "aa:bb:cc:dd:ee:ff"),
        ("UDR7_WOL_MAC", "AA-BB-CC-DD-EE-FF"),
    ],
)
def test_protection_string_shapes_accepted(tmp_path, key, value):
    from river_unifi_bridge.config import validate_update

    cfg = load_config(write(tmp_path, MINIMAL + f"{key}={value}\n"))
    assert getattr(cfg, key.lower()) == value
    assert validate_update(key, value) == value


def test_empty_protection_string_is_absent_not_invalid(tmp_path):
    from river_unifi_bridge.config import validate_update

    cfg = load_config(write(tmp_path, MINIMAL + "UDR7_SSH_HOST=\nUDR7_SSH_KEY=\n"))
    assert cfg.udr7_ssh_host == "" and cfg.udr7_ssh_key == ""
    assert validate_update("UDR7_SSH_HOST", "") == ""


def test_protection_key_sets_are_consistent():
    from river_unifi_bridge.config import (
        FILE_ONLY_KEYS, HOT_RELOAD_KEYS, PROTECTION_KEYS, RESTART_REQUIRED_KEYS,
    )
    assert FILE_ONLY_KEYS == {"UDR7_ARM_ALLOWED"}
    assert "UDR7_ARM_ALLOWED" in RESTART_REQUIRED_KEYS
    assert "UNIFI_HOST" in RESTART_REQUIRED_KEYS and "UNIFI_HOST" not in PROTECTION_KEYS
    assert {"NUT_HOST", "NUT_PORT", "NUT_UPS", "PROTECT_UDR7", "PROTECT_DRY_RUN"} <= PROTECTION_KEYS
    assert len(PROTECTION_KEYS) == 19
    assert (PROTECTION_KEYS - FILE_ONLY_KEYS - {"NUT_HOST", "NUT_PORT", "NUT_UPS"}) <= HOT_RELOAD_KEYS
