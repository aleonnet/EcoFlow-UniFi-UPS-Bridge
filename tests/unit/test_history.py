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


def test_dense_window_for_ui_chart(store):
    # Fixture determinística da cena de densidade (plano v5, banca M2): 60 min
    # de amostras a cada 10 s → o gráfico Tesla-denso tem ≥ 100 buckets SEM
    # depender de wall-clock. Fixture de teste; a demo usa só acumulação real.
    base = 1_000_000
    for i in range(360):
        store.record_sample(snap(power=40 + (i % 30)), ts=base + i * 10)
    rows = store.query("power_w", base, base + 3600, bucket_seconds=10)
    assert len(rows) >= 100
    assert all(r["n"] >= 1 for r in rows)


def test_events_recent_first(store):
    store.record_event("A", ts=100)
    store.record_event("B", ts=200)
    events = store.recent_events()
    assert [e["type"] for e in events] == ["B", "A"]


def test_events_carry_device_and_filter_by_it(store):
    store.record_event("POWER_LOSS", ts=100)                       # evento do bridge: sem dono
    store.record_event("UDR7_SHUTDOWN_DRYRUN", "ok", ts=200, device="udr7")
    store.record_event("SSH_HOST_SHUTDOWN_DRYRUN", "ok", ts=300, device="sshhost_3fa9c1d2")
    rows = store.query_events(0, 2**33)
    assert [(r["type"], r["device"]) for r in rows] == [
        ("SSH_HOST_SHUTDOWN_DRYRUN", "sshhost_3fa9c1d2"),
        ("UDR7_SHUTDOWN_DRYRUN", "udr7"),
        ("POWER_LOSS", None),
    ]
    only = store.query_events(0, 2**33, device="udr7")
    assert [r["type"] for r in only] == ["UDR7_SHUTDOWN_DRYRUN"]
    assert store.recent_events()[0]["device"] == "sshhost_3fa9c1d2"


def test_history_device_column(tmp_path):
    """Uma base criada ANTES da coluna `device` (esquema de 2026-09-01) ganha a
    coluna no primeiro `HistoryStore`; abrir de novo não duplica nem falha; as
    linhas antigas ficam com device NULL e continuam legíveis."""
    import sqlite3

    path = tmp_path / "old.sqlite"
    with sqlite3.connect(path) as conn:
        conn.executescript(
            "CREATE TABLE events (ts INTEGER NOT NULL, type TEXT NOT NULL, detail TEXT);"
            "CREATE TABLE samples (ts INTEGER NOT NULL, state TEXT, charge REAL,"
            " runtime REAL, load REAL, power_w REAL);"
            "INSERT INTO events (ts, type, detail) VALUES (100, 'UDR7_ARMED', 'armado');"
        )
    for _ in range(3):                                             # idempotente
        store = HistoryStore(str(path))
    with sqlite3.connect(path) as conn:
        columns = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
    assert columns.count("device") == 1
    rows = store.query_events(0, 2**33)
    assert rows == [{"ts": 100, "type": "UDR7_ARMED", "detail": "armado", "device": None}]
