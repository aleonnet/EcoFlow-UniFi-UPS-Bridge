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
