"""Token file fences: 0600, stable, regenerated only when absent."""

import os

from river_unifi_bridge.localtoken import get_or_create_token


def test_token_created_0600_and_stable(tmp_path):
    d = str(tmp_path / "state")
    t1 = get_or_create_token(d)
    t2 = get_or_create_token(d)
    assert t1 == t2
    assert len(t1) >= 32
    path = os.path.join(d, "ui-api.token")
    assert (os.stat(path).st_mode & 0o777) == 0o600
    assert (os.stat(d).st_mode & 0o777) == 0o700


def test_state_dir_override_via_env(tmp_path, monkeypatch):
    from river_unifi_bridge import localtoken

    monkeypatch.setenv("RUB_STATE_DIR", str(tmp_path / "override"))
    assert localtoken.state_dir() == str(tmp_path / "override")
