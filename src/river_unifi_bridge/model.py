"""Normalized UPS model (spec §7.3) and NUT status normalization (spec §5.6).

Hard rule (spec §5.5/§12): absent data is None — never fabricated.
Unknown status tokens are preserved verbatim (never guessed, never dropped).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone

# spec §5.6 — raw NUT token -> normalized name
STATUS_MAP: dict[str, str] = {
    "OL": "ONLINE",
    "OB": "ON_BATTERY",
    "LB": "LOW_BATTERY",
    "CHRG": "CHARGING",
    "DISCHRG": "DISCHARGING",
    "OVER": "OVERLOAD",
    "RB": "REPLACE_BATTERY",
    "CAL": "CALIBRATING",
    "OFF": "OUTPUT_OFF",
    "BYPASS": "BYPASS",
}

# NUT variable names consumed from usbhid-ups (spec §5.5)
_FLOAT_VARS = {
    "battery.charge": ("battery", "charge_percent"),
    "battery.charge.low": ("battery", "battery_charge_low_percent"),
    "battery.runtime": ("battery", "runtime_seconds"),
    "battery.voltage": ("battery", "voltage_v"),
    "battery.temperature": ("battery", "temperature_c"),
    "ups.load": ("power", "load_percent"),
    "input.voltage": ("power", "input_voltage_v"),
    "output.voltage": ("power", "output_voltage_v"),
    "ups.realpower": ("power", "output_power_w"),
}


def normalize_status(raw: str | None) -> tuple[list[str], list[str]]:
    """Split a raw ups.status ("OL CHRG") into (normalized, unknown_tokens)."""
    if raw is None:
        return [], []
    normalized: list[str] = []
    unknown: list[str] = []
    for token in raw.split():
        if token in STATUS_MAP:
            normalized.append(STATUS_MAP[token])
        else:
            unknown.append(token)
    return normalized, unknown


def primary_state(states: list[str]) -> str:
    """Single headline state for logs/UI. UNKNOWN when nothing observed."""
    if "ON_BATTERY" in states:
        return "ON_BATTERY"
    if "ONLINE" in states:
        return "ONLINE"
    if "OUTPUT_OFF" in states:
        return "OUTPUT_OFF"
    return "UNKNOWN"


@dataclass
class UpsSnapshot:
    """One observation of the UPS, normalized. Field layout mirrors spec §7.3."""

    name: str
    manufacturer: str | None = None
    model: str | None = None
    serial: str | None = None

    states: list[str] = field(default_factory=list)
    unknown_tokens: list[str] = field(default_factory=list)
    input_voltage_v: float | None = None
    output_voltage_v: float | None = None
    output_power_w: float | None = None
    load_percent: float | None = None

    charge_percent: float | None = None
    # battery.charge.low as published by the driver (EcoFlow: the app's
    # Discharge Limit). Display only — the protection cutoff is the owner's key.
    battery_charge_low_percent: float | None = None
    runtime_seconds: float | None = None
    voltage_v: float | None = None
    temperature_c: float | None = None

    communication_ok: bool = True
    alarm: list[str] = field(default_factory=list)

    # Fase 3'-EXP: source identity (driver.name / driver.version). None when the
    # upsd does not publish them — the protection policy fails closed on None.
    driver_name: str | None = None
    driver_version: str | None = None

    timestamp: str = ""

    @property
    def state(self) -> str:
        return primary_state(self.states)

    @property
    def input_present(self) -> bool | None:
        if "ONLINE" in self.states:
            return True
        if "ON_BATTERY" in self.states:
            return False
        return None

    @property
    def low_battery(self) -> bool:
        return "LOW_BATTERY" in self.states

    @property
    def overload(self) -> bool:
        return "OVERLOAD" in self.states

    def to_dict(self) -> dict:
        """spec §7.3 JSON shape; None serializes as null downstream."""
        return {
            "identity": {
                "name": self.name,
                "manufacturer": self.manufacturer,
                "model": self.model,
                "serial": self.serial,
            },
            "power": {
                "state": self.state,
                "states": self.states,
                "input_present": self.input_present,
                "input_voltage_v": self.input_voltage_v,
                "output_voltage_v": self.output_voltage_v,
                "output_power_w": self.output_power_w,
                "load_percent": self.load_percent,
            },
            "battery": {
                "charge_percent": self.charge_percent,
                "charge_low_percent": self.battery_charge_low_percent,
                "runtime_seconds": self.runtime_seconds,
                "voltage_v": self.voltage_v,
                "temperature_c": self.temperature_c,
            },
            "health": {
                "communication_ok": self.communication_ok,
                "low_battery": self.low_battery,
                "overload": self.overload,
                "alarm": self.alarm,
                "unknown_status_tokens": self.unknown_tokens,
            },
            "source": {
                "nut": True, "usb_hid": True, "usb_cdc": False,
                "driver_name": self.driver_name,
                "driver_version": self.driver_version,
            },
            "timestamp": self.timestamp,
        }


def snapshot_from_nut_vars(name: str, nut_vars: dict[str, str]) -> UpsSnapshot:
    """Build a snapshot from `LIST VAR` output. Missing vars stay None."""
    states, unknown = normalize_status(nut_vars.get("ups.status"))
    snap = UpsSnapshot(
        name=name,
        manufacturer=nut_vars.get("device.mfr") or nut_vars.get("ups.mfr"),
        model=nut_vars.get("device.model") or nut_vars.get("ups.model"),
        serial=nut_vars.get("device.serial"),
        driver_name=nut_vars.get("driver.name") or None,
        driver_version=nut_vars.get("driver.version") or None,
        states=states,
        unknown_tokens=unknown,
        alarm=[a for a in (nut_vars.get("ups.alarm"),) if a],
        timestamp=datetime.now(timezone.utc).isoformat(timespec="seconds"),
    )
    for var, (_section, attr) in _FLOAT_VARS.items():
        raw = nut_vars.get(var)
        if raw is None:
            continue
        try:
            value = float(raw)
        except ValueError:
            # Non-numeric value from the driver: preserve honesty, keep None.
            snap.unknown_tokens.append(f"{var}={raw}")
            continue
        if var == "battery.charge" and not 0.0 <= value <= 100.0:
            # Out-of-range charge is not a reading — keep None, keep it visible.
            snap.unknown_tokens.append(f"{var}={raw}")
            continue
        setattr(snap, attr, value)
    return snap
