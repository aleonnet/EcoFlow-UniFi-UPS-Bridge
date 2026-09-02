"""The plugin registry: STATIC, on purpose.

No disk discovery, no entry points, no schema. With one plugin those would be
structure with no consumer; a second device is a module here plus one line in
`PLUGINS`. The registry is what the loop, the API and the health iterate over.
"""

from __future__ import annotations

from .base import DevicePlugin
from .udr7_ssh import Udr7SshPlugin

PLUGINS: tuple[type[DevicePlugin], ...] = (Udr7SshPlugin,)

__all__ = ["DevicePlugin", "PLUGINS", "Udr7SshPlugin", "build_plugins", "plugin_statuses"]


def build_plugins(cfg, state_dir: str) -> list[DevicePlugin]:
    """Every registered plugin, built from the effective config."""
    return [plugin.build(cfg, state_dir) for plugin in PLUGINS]


def plugin_statuses(plugins: list[DevicePlugin]) -> list[dict]:
    """The `plugins` array of /v1/health.

    ONE `status()` call per plugin, and both the name and the state come from
    that single read. Asking the plugin twice — once for the name, once for the
    state — would let a rename landing between the two calls publish an entry
    whose `name` disagrees with its own `detail.name`.
    """
    out = []
    for plugin in plugins:
        st = plugin.status()
        out.append({
            "id": plugin.id,
            "name": st["name"],
            "state": st["state"],
            "detail": st,
        })
    return out
