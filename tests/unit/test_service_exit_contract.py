"""§7A.3 relaunch contract fences: config error = house code 3 in CLI mode,
DELIBERATE exit 0 under launchd (RUB_LAUNCHD=1) so KeepAlive never loops."""

from river_unifi_bridge.service import EXIT_OK, EXIT_VALIDATION, main


def test_config_error_cli_mode_returns_validation(tmp_path, monkeypatch):
    monkeypatch.delenv("RUB_LAUNCHD", raising=False)
    rc = main(["--env", str(tmp_path / "nao-existe.env")])
    assert rc == EXIT_VALIDATION


def test_config_error_launchd_mode_is_deliberate_stop(tmp_path, monkeypatch):
    monkeypatch.setenv("RUB_LAUNCHD", "1")
    rc = main(["--env", str(tmp_path / "nao-existe.env")])
    assert rc == EXIT_OK
