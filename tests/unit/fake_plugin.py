"""A second plugin that exists only in tests.

Without it the contract tests would be vacuous in one direction: with a single
plugin, "no plugin freezes another plugin's key" is true because there is no
other plugin. `config_keys` is deliberately NOT empty — an empty set would make
the UDR7→Fake direction vacuous too — and the key it owns is a real one from the
allowlist, so `config_keys ⊆ allowlist_keys()` holds.
"""

from __future__ import annotations

from river_unifi_bridge.plugins.base import DevicePlugin


class FakePlugin(DevicePlugin):
    id = "fake"
    config_keys = frozenset({"LOW_BATTERY_PERCENT"})
    frozen_keys = frozenset({"LOW_BATTERY_PERCENT"})

    def __init__(self, armed: bool = False, refuse: tuple[int, str, str] | None = None):
        self._armed = armed
        self.refuse = refuse
        self.applied: list = []
        self.observed: list = []

    @classmethod
    def build(cls, cfg, state_dir: str) -> "FakePlugin":
        return cls()

    @property
    def armed(self) -> bool:
        return self._armed

    def observe(self, snap, tracker_events):
        self.observed.append((snap, list(tracker_events)))
        return []

    def observe_failure(self, tracker_events):
        self.observed.append((None, list(tracker_events)))
        return []

    def on_config_applied(self, cfg):
        self.applied.append(cfg)
        return []

    def authorize(self, changes, snapshot, comm_ok):
        # Only vetoes what it owns, and only when the test asked it to.
        if self.refuse is not None and set(changes) & self.frozen_keys:
            return self.refuse
        return None

    def status(self) -> dict:
        # `state` and `name` are contract: plugin_statuses reads st["name"]
        # without a .get, so a plugin that forgets it fails loudly.
        return {"state": "fake_ok", "name": "Fake"}

    def drain_transition(self):
        return None
