"""Line-preserving .env editor fences (§7A.5)."""

import os

import pytest

from river_unifi_bridge.envfile import EnvFileError, update_env_file

CONTENT = """# river-unifi-bridge — configuração
# ── 1. river ──────────────────────────────
RIVER_NAME=river-office
NUT_PORT=3493

# ── 4. alarms ─────────────────────────────
LOW_BATTERY_PERCENT=15
"""


@pytest.fixture
def env(tmp_path):
    path = tmp_path / "bridge.env"
    path.write_text(CONTENT, encoding="utf-8")
    os.chmod(path, 0o600)
    return str(path)


def test_change_preserves_comments_and_blocks(env):
    update_env_file(env, {"LOW_BATTERY_PERCENT": "20"})
    text = open(env).read()
    assert "LOW_BATTERY_PERCENT=20" in text
    assert "# ── 1. river ─" in text
    assert "# ── 4. alarms ─" in text
    assert "RIVER_NAME=river-office" in text


def test_mode_600_preserved_and_bak_created(env):
    update_env_file(env, {"NUT_PORT": "3494"})
    assert (os.stat(env).st_mode & 0o777) == 0o600
    assert os.path.isfile(env + ".bak")
    assert "NUT_PORT=3493" in open(env + ".bak").read()


def test_missing_key_appended_explicitly(env):
    update_env_file(env, {"UI_API_PORT": "35494"})
    assert open(env).read().rstrip().endswith("UI_API_PORT=35494")


def test_unexpected_line_aborts_without_touching_file(env):
    with open(env, "a") as fh:
        fh.write("linha estranha sem igual\n")
    before = open(env).read()
    with pytest.raises(EnvFileError, match="linha inesperada"):
        update_env_file(env, {"NUT_PORT": "1"})
    assert open(env).read() == before


def test_missing_file_aborts(tmp_path):
    with pytest.raises(EnvFileError, match="não encontrado"):
        update_env_file(str(tmp_path / "nope.env"), {"A": "1"})
