"""Fences for the simulator timelines (pure functions of elapsed time)."""

import importlib.machinery
import importlib.util
import pathlib

# The simulator has no .py extension: spec_from_file_location alone yields a
# loaderless spec — an explicit SourceFileLoader is required.
_path = str(pathlib.Path(__file__).parents[2] / "tools" / "fake-nut-ups")
_loader = importlib.machinery.SourceFileLoader("fake_nut_ups", _path)
_spec = importlib.util.spec_from_loader("fake_nut_ups", _loader)
sim = importlib.util.module_from_spec(_spec)
_loader.exec_module(sim)


def test_power_loss_timeline():
    assert sim.scenario_power_loss(2)["ups.status"] == "OL CHRG"
    assert sim.scenario_power_loss(10)["ups.status"] == "OB DISCHRG"


def test_instavel_alternates_and_repeats():
    on = sim.scenario_instavel(10)
    off = sim.scenario_instavel(50)
    again = sim.scenario_instavel(10 + 75)          # next cycle, same phase
    assert on["ups.status"].startswith("OL")
    assert off["ups.status"].startswith("OB")
    assert again["ups.status"] == on["ups.status"]
    # Charge stays inside honest bounds, never fabricated out of range.
    for t in range(0, 300, 7):
        charge = int(sim.scenario_instavel(float(t))["battery.charge"])
        assert 30 <= charge <= 100
