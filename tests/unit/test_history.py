"""HistoryStore: buckets, honesty (NULLs excluded), retention."""

import pytest

from river_unifi_bridge.history import HistoryStore


def snap(charge=None, power=None, state="ONLINE"):
    return {
        "power": {"state": state, "load_percent": None, "output_power_w": power},
        "battery": {"charge_percent": charge, "runtime_seconds": None},
    }


@pytest.fixture
def store(tmp_path):
    return HistoryStore(str(tmp_path / "h.sqlite"), retention_days=7)


def test_bucketed_average(store):
    # ts 1200 is bucket-aligned (1200 % 60 == 0): all 3 samples in one bucket.
    for i, charge in enumerate([80, 90, 100]):
        store.record_sample(snap(charge=charge), ts=1200 + i * 10)
    rows = store.query("charge", 0, 2000, bucket_seconds=60)
    assert len(rows) == 1
    assert rows[0]["ts"] == 1200
    assert rows[0]["avg"] == 90.0
    assert rows[0]["min"] == 80.0
    assert rows[0]["max"] == 100.0
    assert rows[0]["n"] == 3


def test_null_samples_not_counted(store):
    store.record_sample(snap(charge=None), ts=1000)
    store.record_sample(snap(charge=50), ts=1010)
    rows = store.query("charge", 0, 2000, bucket_seconds=3600)
    assert rows[0]["n"] == 1
    assert rows[0]["avg"] == 50.0


def test_unknown_metric_rejected(store):
    with pytest.raises(ValueError, match="métrica desconhecida"):
        store.query("cpu", 0, 1, 60)


def test_retention_prunes_old_data(store):
    now = 100 * 86400
    store.record_sample(snap(charge=10), ts=now - 8 * 86400)  # older than 7d
    store.record_sample(snap(charge=20), ts=now - 3600)
    store.record_event("POWER_LOSS", ts=now - 8 * 86400)
    removed = store.prune(now=now)
    assert removed == 2
    rows = store.query("charge", 0, now, bucket_seconds=86400 * 100)
    assert rows[0]["n"] == 1


def test_events_recent_first(store):
    store.record_event("A", ts=100)
    store.record_event("B", ts=200)
    events = store.recent_events()
    assert [e["type"] for e in events] == ["B", "A"]
