"""Debounce fence tests (spec §11) with an injected fake clock — no sleeps."""

from river_unifi_bridge.config import BridgeConfig
from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.service import TransitionTracker


def make_cfg(**overrides):
    base = dict(
        river_name="r", nut_host="h", nut_port=3493, nut_ups="r",
        power_loss_delay_seconds=3, restore_delay_seconds=5,
        comm_loss_delay_seconds=20, low_battery_percent=15,
    )
    base.update(overrides)
    return BridgeConfig(**base)


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


def snap(status, charge="87"):
    return snapshot_from_nut_vars("r", {"ups.status": status, "battery.charge": charge})


def test_power_loss_debounced_not_instant():
    clock = FakeClock()
    t = TransitionTracker(make_cfg(), clock)
    assert t.observe(snap("OB DISCHRG")) == []          # t=0: condition starts
    clock.now = 2.9
    assert t.observe(snap("OB DISCHRG")) == []          # below delay: silent
    clock.now = 3.1
    assert t.observe(snap("OB DISCHRG")) == ["POWER_LOSS"]
    clock.now = 4.0
    assert t.observe(snap("OB DISCHRG")) == []          # fires once


def test_restore_debounced_and_resets():
    clock = FakeClock()
    t = TransitionTracker(make_cfg(), clock)
    t.observe(snap("OB DISCHRG"))
    clock.now = 4
    assert "POWER_LOSS" in t.observe(snap("OB DISCHRG"))
    clock.now = 5
    assert t.observe(snap("OL CHRG")) == []             # restore window opens
    clock.now = 9.9
    assert t.observe(snap("OL CHRG")) == []
    clock.now = 10.1
    assert t.observe(snap("OL CHRG")) == ["POWER_RESTORED"]


def test_restore_delay_zero_fires_same_tick():
    # Default de produção (pesquisa 2026-08-31): restauração imediata, como
    # NUT/apcupsd. Com delay 0 o evento sai no MESMO tick da volta ao OL.
    clock = FakeClock()
    t = TransitionTracker(make_cfg(restore_delay_seconds=0), clock)
    t.observe(snap("OB DISCHRG"))
    clock.now = 4
    assert "POWER_LOSS" in t.observe(snap("OB DISCHRG"))
    clock.now = 5
    assert t.observe(snap("OL CHRG")) == ["POWER_RESTORED"]


def test_blip_shorter_than_delay_never_fires():
    clock = FakeClock()
    t = TransitionTracker(make_cfg(), clock)
    t.observe(snap("OB DISCHRG"))
    clock.now = 1.0
    t.observe(snap("OB DISCHRG"))
    clock.now = 2.0
    assert t.observe(snap("OL CHRG")) == []             # back before 3 s
    clock.now = 6.0
    assert t.observe(snap("OL CHRG")) == []             # no restore: no loss happened


def test_low_battery_fires_once_by_lb_flag_or_threshold():
    clock = FakeClock()
    t = TransitionTracker(make_cfg(), clock)
    assert t.observe(snap("OB DISCHRG LB", charge="40")) == ["LOW_BATTERY"]
    assert t.observe(snap("OB DISCHRG LB", charge="39")) == []
    t2 = TransitionTracker(make_cfg(), clock)
    assert t2.observe(snap("OB DISCHRG", charge="14")) == ["LOW_BATTERY"]


def sem_carga(status):
    return snapshot_from_nut_vars("r", {"ups.status": status})


def test_low_battery_needs_on_battery():
    """Carga baixa NA TOMADA não é bateria baixa (B01): o River carregando a 10 %
    é normal, e virava alerta na linha do tempo e no Home Assistant."""
    clock = FakeClock()
    t = TransitionTracker(make_cfg(), clock)
    assert t.observe(snap("OL CHRG", charge="10")) == []
    assert t.observe(snap("OL CHRG LB", charge="8")) == []
    # na bateria, o mesmo valor alerta (sem esperar o atraso da queda)
    assert t.observe(snap("OB DISCHRG", charge="10")) == ["LOW_BATTERY"]


def test_low_battery_rearms_after_the_condition_clears():
    """Duas quedas, dois alertas — e nada de rajada enquanto a carga oscila."""
    clock = FakeClock()
    t = TransitionTracker(make_cfg(), clock)          # limiar 15, folga 5 → rearma em 20
    assert t.observe(snap("OB DISCHRG", charge="14")) == ["LOW_BATTERY"]
    assert t.observe(snap("OB DISCHRG", charge="16")) == []      # dentro da folga: não rearma
    assert t.observe(snap("OB DISCHRG", charge="14")) == []      # e por isso não repete
    assert t.observe(snap("OB DISCHRG", charge="20")) == []      # cessou: rearmado, sem evento
    assert t.observe(snap("OB DISCHRG", charge="13")) == ["LOW_BATTERY"]   # 2.ª queda alerta
    # leitura ausente não rearma
    assert t.observe(sem_carga("OB DISCHRG")) == []
    assert t.observe(snap("OB DISCHRG", charge="13")) == []


def test_comm_lost_debounced_and_restored():
    clock = FakeClock()
    t = TransitionTracker(make_cfg(), clock)
    t.observe(snap("OL"))
    clock.now = 10
    assert t.observe_failure() == []                    # below 20 s
    clock.now = 20.5
    assert t.observe_failure() == ["COMM_LOST"]
    clock.now = 21
    assert t.observe_failure() == []                    # fires once
    clock.now = 22
    assert t.observe(snap("OL")) == ["COMM_RESTORED"]
