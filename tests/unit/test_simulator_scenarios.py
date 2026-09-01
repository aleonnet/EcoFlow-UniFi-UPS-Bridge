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


def test_apagao_phases_and_bounds():
    grid = sim.scenario_apagao(5)
    outage_start = sim.scenario_apagao(21)
    outage_end = sim.scenario_apagao(119)
    back = sim.scenario_apagao(125)
    again = sim.scenario_apagao(5 + 140)
    assert grid["ups.status"] == "OL CHRG"
    assert outage_start["ups.status"] == "OB DISCHRG" and "LB" not in outage_start["ups.status"]
    assert outage_end["ups.status"] == "OB DISCHRG"
    assert back["ups.status"] == "OL CHRG"
    assert again == grid
    # Drains monotonically 40 -> 3 during the outage; the published (truncated)
    # charge first reads <= 20 % around 52-54 s into the outage (0.37 %/s).
    charges = [int(sim.scenario_apagao(float(20 + s))["battery.charge"]) for s in range(0, 100)]
    assert charges[0] == 40 and charges[-1] <= 4
    assert all(a >= b for a, b in zip(charges, charges[1:]))
    first_at_or_below_20 = next(i for i, c in enumerate(charges) if c <= 20)
    assert 50 <= first_at_or_below_20 <= 56


def test_simulator_base_vars_are_synthetic():
    # Contract with protect.py: the simulator must always be caught by the
    # source fence — by driver name AND by a serial that cannot be registered.
    assert "fake" in sim.BASE_VARS["driver.name"]
    assert "fake" in sim.BASE_VARS["driver.version"]
    assert sim.BASE_VARS["device.serial"] == "SIM0001"
    for name, scenario in sim.SCENARIOS.items():
        vars_ = scenario(3.0)
        assert vars_["driver.name"] == sim.BASE_VARS["driver.name"], name
        assert vars_["device.serial"] == "SIM0001", name
