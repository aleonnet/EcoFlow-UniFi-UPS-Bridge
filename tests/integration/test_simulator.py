"""Integration: real TCP against tools/fake-nut-ups (spec §18 T01/T05/T08).

Spawns the simulator as a subprocess on an ephemeral port; no hardware, no
sleeps longer than the scenario timings require (kept short via monkeypatched
config delays).
"""

import pathlib
import socket
import subprocess
import sys
import time

import pytest

from river_unifi_bridge.config import BridgeConfig
from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.nut import NutClient, NutError
from river_unifi_bridge.service import TransitionTracker

REPO = pathlib.Path(__file__).parents[2]
SIMULATOR = REPO / "tools" / "fake-nut-ups"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def sim(request):
    scenario = getattr(request, "param", "online")
    port = free_port()
    proc = subprocess.Popen(
        [sys.executable, str(SIMULATOR), "--port", str(port), "--scenario", scenario],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    # Wait for the listener (banner line) before letting the test connect.
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), 0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        proc.kill()
        pytest.fail("simulador não abriu a porta em 5 s")
    yield port, proc
    proc.terminate()
    proc.wait(timeout=5)


def test_t01_boot_with_ups_connected(sim):
    port, _proc = sim
    with NutClient("127.0.0.1", port) as client:
        nut_vars = client.list_vars("river-office")
    snap = snapshot_from_nut_vars("river-office", nut_vars)
    assert snap.state == "ONLINE"
    assert snap.charge_percent == 87.0
    assert snap.model == "RIVER 3 Plus"


def test_unknown_ups_is_an_error(sim):
    port, _proc = sim
    with NutClient("127.0.0.1", port) as client:
        with pytest.raises(NutError, match="UNKNOWN-UPS"):
            client.list_vars("nope")


@pytest.mark.parametrize("sim", ["power-loss"], indirect=True)
def test_t05_power_loss_detected_with_debounce(sim):
    port, _proc = sim
    cfg = BridgeConfig(
        river_name="river-office", nut_host="127.0.0.1", nut_port=port,
        nut_ups="river-office", power_loss_delay_seconds=1,
    )
    tracker = TransitionTracker(cfg)
    events: list[str] = []
    deadline = time.time() + 12
    while time.time() < deadline and "POWER_LOSS" not in events:
        with NutClient("127.0.0.1", port) as client:
            snap = snapshot_from_nut_vars("river-office", client.list_vars("river-office"))
        events += tracker.observe(snap)
        time.sleep(0.5)
    assert "POWER_LOSS" in events


def test_t08_upsd_loss_detected(sim):
    port, proc = sim
    cfg = BridgeConfig(
        river_name="river-office", nut_host="127.0.0.1", nut_port=port,
        nut_ups="river-office", comm_loss_delay_seconds=1,
    )
    tracker = TransitionTracker(cfg)
    with NutClient("127.0.0.1", port) as client:
        tracker.observe(snapshot_from_nut_vars("river-office", client.list_vars("river-office")))

    proc.terminate()
    proc.wait(timeout=5)

    events: list[str] = []
    deadline = time.time() + 6
    while time.time() < deadline and "COMM_LOST" not in events:
        try:
            with NutClient("127.0.0.1", port, timeout=0.5) as client:
                client.list_vars("river-office")
        except NutError:
            events += tracker.observe_failure()
        time.sleep(0.3)
    assert "COMM_LOST" in events


def test_simulator_lists_ups_for_ha_discovery(tmp_path):
    # HA's NUT integration begins with LIST UPS — the simulator must answer.
    import socket
    import subprocess
    import time as _t

    proc = subprocess.Popen(
        [sys.executable, str(SIMULATOR), "--scenario", "online", "--port", "0"],
        stdout=subprocess.PIPE, text=True,
    )
    try:
        line = proc.stdout.readline()
        port = int(line.rsplit("porta=", 1)[1])
        with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
            sock.sendall(b"LIST UPS\n")
            data = sock.recv(4096).decode()
        assert "BEGIN LIST UPS" in data
        assert 'UPS river-office' in data
        assert "END LIST UPS" in data
    finally:
        proc.terminate()
