"""E2E UI-0: full daemon (poll loop + API thread) against fake-nut-ups.

Real subprocesses, real TCP, real token file (in a tmp RUB_STATE_DIR).
Covers the ordem-4 gate: curl-equivalent on /v1/state, SSE first frame,
history filling up.
"""

import json
import pathlib
import socket
import subprocess
import sys
import time
import urllib.request

import pytest

from conftest import ambiente_do_daemon

REPO = pathlib.Path(__file__).parents[2]
SIMULATOR = REPO / "tools" / "fake-nut-ups"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def stack(tmp_path):
    nut_port = free_port()
    api_port = free_port()
    state_dir = tmp_path / "state"

    sim = subprocess.Popen(
        [sys.executable, str(SIMULATOR), "--port", str(nut_port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    env_file = tmp_path / "bridge.env"
    env_file.write_text(
        "RIVER_NAME=river-office\nNUT_HOST=127.0.0.1\n"
        f"NUT_PORT={nut_port}\nNUT_UPS=river-office\n"
        f"UI_API_PORT={api_port}\nPOLL_INTERVAL_SECONDS=1\n",
        encoding="utf-8",
    )
    daemon = subprocess.Popen(
        [sys.executable, "-m", "river_unifi_bridge.service", "--env", str(env_file)],
        cwd=str(REPO),
        env=ambiente_do_daemon(tmp_path, RUB_STATE_DIR=str(state_dir)),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    # Wait for the API port to open.
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            socket.create_connection(("127.0.0.1", api_port), 0.2).close()
            break
        except OSError:
            time.sleep(0.1)
    else:
        daemon.kill()
        sim.kill()
        pytest.fail("API não abriu a porta em 10 s")

    token = (state_dir / "ui-api.token").read_text().strip()
    yield api_port, token, daemon
    daemon.terminate()
    sim.terminate()
    daemon.wait(timeout=5)
    sim.wait(timeout=5)


def get_json(port, token, path):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return resp.status, json.loads(resp.read())


def test_e2e_state_history_and_sse(stack):
    port, token, _daemon = stack

    # /v1/state converges to real simulator data
    deadline = time.time() + 10
    body = None
    while time.time() < deadline:
        status, body = get_json(port, token, "/v1/state")
        assert status == 200
        if body["power"]["state"] == "ONLINE":
            break
        time.sleep(0.3)
    assert body["power"]["state"] == "ONLINE"
    assert body["identity"]["model"] == "RIVER 3 Plus"
    assert body["battery"]["charge_percent"] == 87.0

    # token fence: request without token is refused
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/state", timeout=5)
        assert False, "sem token deveria falhar"
    except urllib.error.HTTPError as exc:
        assert exc.code == 401

    # /v1/history fills up with real samples
    time.sleep(1.5)
    status, hist = get_json(port, token, "/v1/history?metric=charge&bucket=60")
    assert status == 200
    assert hist["rows"] and hist["rows"][0]["n"] >= 1

    # SSE: first frame arrives with an event: state header
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/events",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        first = resp.readline().decode()
        assert first.startswith("event: state")
