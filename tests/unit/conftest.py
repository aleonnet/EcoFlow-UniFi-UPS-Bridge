"""Unit-test fence (Fase 3'-EXP, M1): no test may spawn a process.

The protection module resolves its process seams at call time; here every one of
them is replaced by a function that fails loudly, the ssh/ssh-keygen paths point to
nowhere, and `subprocess.run` itself is blocked. A test that legitimately needs a
local process (only `ssh -G`, which never connects) opts out with the `spawn_ok`
marker — and even then the three module seams stay blocked.
"""

import subprocess

import pytest

from river_unifi_bridge import protect


def _forbidden(*_args, **_kwargs):
    raise AssertionError("spawn proibido em teste (fixture anti-spawn de tests/unit)")


@pytest.fixture(autouse=True)
def _no_spawn(request, monkeypatch):
    monkeypatch.setattr(protect, "_RUNNER", _forbidden)
    monkeypatch.setattr(protect, "_KEYGEN_RUNNER", _forbidden)
    monkeypatch.setattr(protect, "_WOL_SENDER", _forbidden)
    monkeypatch.setattr(protect, "SSH_BINARY", "/nonexistent/river-test/ssh")
    monkeypatch.setattr(protect, "SSH_KEYGEN", "/nonexistent/river-test/ssh-keygen")
    if request.node.get_closest_marker("spawn_ok") is None:
        monkeypatch.setattr(subprocess, "run", _forbidden)
    yield
