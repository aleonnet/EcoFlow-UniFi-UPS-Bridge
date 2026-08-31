"""Config loader for river-unifi-bridge.

House pattern (spec §22, mold ABHOME-macmini/macmini-backup.sh:452-464):
- .env style KEY=VALUE, parsed line by line — never `source`d;
- strict allowlist: unknown keys are reported with their line number;
- required keys must be present and non-empty;
- comments only on their own line;
- `~` expanded manually.

The SAME allowlist will validate PUT /v1/config in UI-0 (§7A.5) — single
source of truth for what a valid configuration is.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field, fields


class ConfigError(Exception):
    """Invalid or incomplete configuration (house exit code 3 at the CLI)."""


# key -> (type, required, default, (min, max) for ints)
_ALLOWLIST: dict[str, tuple[type, bool, object, tuple[int, int] | None]] = {
    "RIVER_NAME": (str, True, None, None),
    "NUT_HOST": (str, True, None, None),
    "NUT_PORT": (int, True, None, (1, 65535)),
    "NUT_UPS": (str, True, None, None),
    "UNIFI_HOST": (str, False, "", None),
    "UNIFI_VERIFY_TLS": (bool, False, True, None),
    "POLL_INTERVAL_SECONDS": (int, False, 2, (1, 60)),
    "READ_ONLY": (bool, False, True, None),
    "EMULATE_MODEL": (bool, False, False, None),
    "POWER_LOSS_DELAY_SECONDS": (int, False, 3, (0, 600)),
    "RESTORE_DELAY_SECONDS": (int, False, 5, (0, 600)),
    "COMM_LOSS_DELAY_SECONDS": (int, False, 20, (0, 600)),
    "LOW_BATTERY_PERCENT": (int, False, 15, (5, 50)),
    "UI_API_ENABLED": (bool, False, True, None),
    "UI_API_PORT": (int, False, 35493, (1024, 65535)),
    "HISTORY_RETENTION_DAYS": (int, False, 7, (1, 365)),
}


@dataclass
class BridgeConfig:
    river_name: str
    nut_host: str
    nut_port: int
    nut_ups: str
    unifi_host: str = ""
    unifi_verify_tls: bool = True
    poll_interval_seconds: int = 2
    read_only: bool = True
    emulate_model: bool = False
    power_loss_delay_seconds: int = 3
    restore_delay_seconds: int = 5
    comm_loss_delay_seconds: int = 20
    low_battery_percent: int = 15
    ui_api_enabled: bool = True
    ui_api_port: int = 35493
    history_retention_days: int = 7
    # Diagnostics for the caller (never fatal): "<line>: <message>"
    warnings: list[str] = field(default_factory=list)


def _parse_bool(raw: str) -> bool:
    if raw in ("1", "true", "TRUE", "yes"):
        return True
    if raw in ("0", "false", "FALSE", "no"):
        return False
    raise ValueError(f"valor booleano inválido: {raw!r} (use 1/0)")


def load_config(path: str) -> BridgeConfig:
    """Parse `path` against the allowlist. Raises ConfigError on violations."""
    if not os.path.isfile(path):
        raise ConfigError(f"arquivo de configuração não encontrado: {path}")

    values: dict[str, object] = {}
    warnings: list[str] = []

    with open(path, encoding="utf-8") as fh:
        for lineno, raw_line in enumerate(fh, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ConfigError(f"{path}:{lineno}: linha sem '=' — comentário só em linha própria")
            key, _, raw_value = line.partition("=")
            key = key.strip()
            value = raw_value.strip()

            if key not in _ALLOWLIST:
                warnings.append(f"{path}:{lineno}: chave desconhecida ignorada: {key}")
                continue

            typ, _required, _default, bounds = _ALLOWLIST[key]
            if value == "":
                # Empty value: treated below as absent (required check decides).
                continue
            value = value.replace("~", os.path.expanduser("~")) if typ is str else value
            try:
                if typ is bool:
                    parsed: object = _parse_bool(value)
                elif typ is int:
                    parsed = int(value)
                else:
                    parsed = value
            except ValueError as exc:
                raise ConfigError(f"{path}:{lineno}: {key}: {exc}") from exc

            if typ is int and bounds is not None:
                low, high = bounds
                if not (low <= parsed <= high):  # type: ignore[operator]
                    raise ConfigError(
                        f"{path}:{lineno}: {key}={parsed} fora da faixa [{low}, {high}]"
                    )
            values[key] = parsed

    missing = [k for k, (_, req, _, _) in _ALLOWLIST.items() if req and k not in values]
    if missing:
        raise ConfigError(f"{path}: chaves obrigatórias ausentes ou vazias: {', '.join(missing)}")

    kwargs: dict[str, object] = {}
    for key, (_typ, required, default, _bounds) in _ALLOWLIST.items():
        kwargs[key.lower()] = values.get(key, default)
    cfg = BridgeConfig(**kwargs)  # type: ignore[arg-type]
    cfg.warnings = warnings
    return cfg


def allowlist_keys() -> list[str]:
    """Public view of the allowlist (reused by the UI API in UI-0)."""
    return list(_ALLOWLIST)


# §7A.5 — which changed keys apply live vs. require a service restart.
HOT_RELOAD_KEYS = frozenset(
    {
        "POLL_INTERVAL_SECONDS",
        "POWER_LOSS_DELAY_SECONDS",
        "RESTORE_DELAY_SECONDS",
        "COMM_LOSS_DELAY_SECONDS",
        "LOW_BATTERY_PERCENT",
        "HISTORY_RETENTION_DAYS",
    }
)
RESTART_REQUIRED_KEYS = frozenset(_ALLOWLIST) - HOT_RELOAD_KEYS


def validate_update(key: str, raw_value: str) -> object:
    """Validate one KEY=raw_value pair with the SAME rules as load_config.

    Used by PUT /v1/config — single source of truth for what is valid.
    Raises ConfigError naming the key on any violation.
    """
    if key not in _ALLOWLIST:
        raise ConfigError(f"chave desconhecida: {key}")
    typ, required, _default, bounds = _ALLOWLIST[key]
    value = str(raw_value).strip()
    if value == "":
        if required:
            raise ConfigError(f"{key}: valor obrigatório não pode ser vazio")
        return ""
    try:
        if typ is bool:
            parsed: object = _parse_bool(value)
        elif typ is int:
            parsed = int(value)
        else:
            parsed = value
    except ValueError as exc:
        raise ConfigError(f"{key}: {exc}") from exc
    if typ is int and bounds is not None:
        low, high = bounds
        if not (low <= parsed <= high):  # type: ignore[operator]
            raise ConfigError(f"{key}={parsed} fora da faixa [{low}, {high}]")
    return parsed


def config_field_names() -> list[str]:
    return [f.name for f in fields(BridgeConfig) if f.name != "warnings"]
