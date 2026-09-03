"""The registry of device TYPES: STATIC, on purpose (2026-09-03: instances).

No disk discovery, no entry points, no schema. A new type is a module here plus
one entry in `TYPES`. What the loop, the API and the health iterate over is the
`PluginSet`: one plugin object per INSTANCE of `devices.json`, built from the
type's `build(instance, cfg, state_dir)`.
"""

from __future__ import annotations

import threading

from ..devices import DevicesError
from .base import DevicePlugin, FieldSpec
from .udr7_ssh import Udr7SshPlugin

TYPES: dict[str, type[DevicePlugin]] = {
    Udr7SshPlugin.type_id: Udr7SshPlugin,
}
PLUGINS: tuple[type[DevicePlugin], ...] = tuple(TYPES.values())

__all__ = ["DevicePlugin", "FieldSpec", "PLUGINS", "TYPES", "PluginSet", "Udr7SshPlugin",
           "build_plugins", "plugin_statuses", "type_catalog"]


def build_plugins(devices, cfg, state_dir: str) -> list[DevicePlugin]:
    """One plugin per instance, in the order of the store. Unknown type = the store
    is invalid for THIS daemon (a stop, never a silently skipped device)."""
    out: list[DevicePlugin] = []
    for instance in devices:
        cls = TYPES.get(instance.type)
        if cls is None:
            raise DevicesError(f"tipo de dispositivo desconhecido: {instance.type!r} (instância {instance.id})")
        out.append(cls.build(instance, cfg, state_dir))
    return out


def plugin_statuses(plugins) -> list[dict]:
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
            "type": plugin.type_id,
            "name": st["name"],
            "state": st["state"],
            "detail": st,
        })
    return out


def type_catalog() -> list[dict]:
    """GET /v1/device-types: what each type is and which fields an instance has."""
    return [
        {
            "id": cls.type_id,
            "label_pt": cls.label_pt,
            "label_en": cls.label_en,
            "default_name": cls.default_name,
            "event_prefix": cls.event_prefix,
            "fields": [spec.to_json() for spec in cls.fields],
        }
        for cls in TYPES.values()
    ]


class PluginSet:
    """The live list of plugins, shared by the poll thread and the API thread.

    Iteration hands out a COPY under the lock, so the loop never sees a list
    mutated mid-tick; add/remove are the only writers (the API's POST/DELETE).
    """

    def __init__(self, plugins=()) -> None:
        self._lock = threading.Lock()
        self._plugins: list[DevicePlugin] = list(plugins)

    def snapshot(self) -> list[DevicePlugin]:
        with self._lock:
            return list(self._plugins)

    def __iter__(self):
        return iter(self.snapshot())

    def __len__(self) -> int:
        with self._lock:
            return len(self._plugins)

    def __bool__(self) -> bool:
        return len(self) > 0

    def get(self, instance_id: str) -> DevicePlugin | None:
        for plugin in self.snapshot():
            if plugin.id == instance_id:
                return plugin
        return None

    def add(self, plugin: DevicePlugin) -> None:
        with self._lock:
            if any(p.id == plugin.id for p in self._plugins):
                raise DevicesError(f"instância repetida: {plugin.id}")
            self._plugins.append(plugin)

    def remove(self, instance_id: str) -> DevicePlugin | None:
        with self._lock:
            for i, plugin in enumerate(self._plugins):
                if plugin.id == instance_id:
                    return self._plugins.pop(i)
        return None
