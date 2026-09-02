"""The device-plugin contract on the daemon side.

A "device plugin" is a piece of hardware the bridge protects. The UDR7 is the
first one; a second one is a new module here plus one line in PLUGINS.

Design rules, all of them deliberate:

* **Only members with a runtime consumer.** The first draft carried `hot_keys`,
  `file_only_keys`, `event_types` and `state()`; none had a caller, so none of
  them is here. Two members ARE declarative data and that relaxation is stated
  out loud: `frozen_keys` (read by the plugin's own `authorize`) and
  `config_keys` (read by the test that partitions the allowlist among plugins).
* **No `display_name`.** The name lives in `status()["name"]`, so the health
  entry and its detail can never disagree: `plugin_statuses` reads the status
  ONCE. Two reads — one for the name, one for the state — would let a rename
  landing between them publish `plugins[0].name != plugins[0].detail.name`.
* **`status()` is abstract** and must carry `state` and `name`: the health
  builder depends on both, and a plugin that forgets one would publish a card
  with no state or no title.

The policy itself does NOT move: `protect.py` stays where it is (six gate
anchors, two tests that read `protect.__file__` and the anti-spawn fence that
patches attributes on the module point at it). The plugin is a thin ADAPTER that
composes the policy and its config holder.
"""

from __future__ import annotations

import abc


class DevicePlugin(abc.ABC):
    """One protected device, from the daemon's point of view.

    `id`, `config_keys` and `frozen_keys` are class annotations — `abc` does not
    enforce attributes, so the fence for them is `test_contract_attributes`.
    """

    id: str
    config_keys: frozenset[str]
    frozen_keys: frozenset[str]

    @classmethod
    @abc.abstractmethod
    def build(cls, cfg, state_dir: str) -> "DevicePlugin":
        """Create the plugin from the effective config and the state directory."""

    @property
    @abc.abstractmethod
    def armed(self) -> bool:
        """True when this device is protected for real (not a rehearsal)."""

    @abc.abstractmethod
    def observe(self, snap, tracker_events: list[str]) -> list:
        """React to one telemetry reading. Returns actions for the caller to emit."""

    @abc.abstractmethod
    def observe_failure(self, tracker_events: list[str]) -> list:
        """React to a polling failure (no reading at all)."""

    @abc.abstractmethod
    def on_config_applied(self, cfg) -> list:
        """Apply a hot config change. The plugin owns its holder."""

    @abc.abstractmethod
    def authorize(self, changes: dict, snapshot: dict | None,
                  comm_ok: bool) -> tuple[int, str, str] | None:
        """Veto a PUT before anything is written.

        Returns `(status, motivo, mensagem)` to refuse, or None to allow. The
        first plugin to refuse wins.
        """

    @abc.abstractmethod
    def status(self) -> dict:
        """Pure view for /v1/health. MUST contain `state` and `name`."""

    @abc.abstractmethod
    def drain_transition(self) -> tuple[str | None, str] | None:
        """Hand over a pending state transition, for the audit line."""
