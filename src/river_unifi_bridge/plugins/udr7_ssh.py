"""The UDR7 over SSH — the first device type, and the one with a legacy `.env`.

Desde 2026-09-03 é um TIPO sobre o motor SSH comum (`ssh_motor.py`): o que fica
aqui é o que só o UDR7 tem — a tabela verificada de comandos, e o mapa das 14
chaves legadas `PROTECT_*`/`UDR7_*` que o `.env` do Mac mini ainda carrega e que
espelham a instância migrada `udr7` (as outras três — trava, série esperada e
corte — são do núcleo: `config.LEGACY_CORE_KEYS`).
"""

from __future__ import annotations

from ..config import (
    HOST_PATTERN, KEY_PATH_PATTERN, LEGACY_CORE_KEYS, MAC_PATTERN, NAME_PATTERN,
    PROTECTION_KEYS, USER_PATTERN,
)
from ..devices import DeviceInstance, LEGACY_INSTANCE_ID, now_iso
from ..protect import INSTANCE_FIELD_DEFAULTS
from .base import FieldSpec
from .ssh_motor import SshMotorPlugin

# --- O VOCABULÁRIO DE COMANDOS DESTE DISPOSITIVO -----------------------------
#
# Mora AQUI, no plugin, e não em protect.py: `protect.py` é o transporte (monta o
# ssh isolado e executa); o que se diz do outro lado é do dispositivo. Um segundo
# aparelho traz a sua própria tabela e não toca em nada disto.
#
# Cada comando traz a fonte E O GRAU dela, na gramática da casa (docs/README.md):
#   [P] primária — a origem: código do fabricante, especificação, medição no aparelho
#   [S] secundária — wiki, gist, blog. NÃO vira [P] por ser citada três vezes.
# Hoje o `poweroff` é [S]: a porta 22 do console está fechada e NENHUM comando foi
# confirmado no UDR7. Vira [P] quando rodar lá e a saída entrar no runbook.

class Cmd:
    """Um comando remoto: o que se manda, se destrói algo, e de onde veio."""

    __slots__ = ("nome", "argv", "destrutivo", "fonte")

    def __init__(self, nome: str, argv: str, destrutivo: bool, fonte: str):
        self.nome = nome
        self.argv = argv
        self.destrutivo = destrutivo
        self.fonte = fonte


COMMANDS: dict[str, Cmd] = {
    # --- prova de alcance (não destrutivos) ---------------------------------
    "probe": Cmd(
        "probe", "command -v ubnt-systool", False,
        "[P] POSIX. É o mesmo teste que o instalador oficial do unifi-common usa "
        "DENTRO do console (`command_exists()` em remote_install.sh)"),
    "model": Cmd(
        "model", "ubnt-device-info model", False,
        "[P] unifi-common/remote_install.sh:38 e :131 — código que EXECUTA no console "
        "e casa a saída com a string \"UniFi Dream Router 7\", o nosso aparelho"),
    "firmware": Cmd(
        "firmware", "ubnt-device-info firmware", False,
        "[P] unifi-common/remote_install.sh:131 — código que executa no console"),
    # --- ato final (destrutivo) ---------------------------------------------
    "poweroff": Cmd(
        "poweroff", "ubnt-systool poweroff", True,
        "[S] wiki CLI de ubnt-systool + gist \"Graceful shutdown of UDMP via NUT\" + "
        "LazyAdmin. TRÊS fontes secundárias concordam que é o desligamento gracioso do "
        "UniFi OS, e nenhuma delas é primária: não foi confirmado no aparelho porque a "
        "porta 22 está fechada. É o ÚNICO comando destrutivo, e o que menos deveria "
        "estar em [S]"),
    "reboot": Cmd(
        "reboot", "ubnt-systool reboot", True,
        "[S] wiki CLI de ubnt-systool. NÃO é usado pela proteção: reiniciar numa "
        "queda gastaria bateria e devolveria o console ligado. Fica declarado para o "
        "operador saber que existe e que a escolha foi consciente"),
}

# O que a política dispara quando decide agir. É `poweroff` por decisão, não por
# acaso: ver a nota do `reboot` acima.
POWEROFF = COMMANDS["poweroff"]
# O que prova alcance sem tocar em nada. Existe porque o estado
# `armado_nao_verificado` denunciava que o daemon armava sem NUNCA ter falado
# com o console.
PROBE = COMMANDS["probe"]


# --- os campos de uma instância deste tipo ------------------------------------------
_D = INSTANCE_FIELD_DEFAULTS
SSH_FIELDS: tuple[FieldSpec, ...] = (
    FieldSpec("ssh_host", "str", _D["ssh_host"], pattern=HOST_PATTERN),
    FieldSpec("ssh_port", "int", _D["ssh_port"], bounds=(1, 65535)),
    FieldSpec("ssh_user", "str", _D["ssh_user"], pattern=USER_PATTERN),
    FieldSpec("ssh_key", "str", _D["ssh_key"], pattern=KEY_PATH_PATTERN),
    FieldSpec("shutdown_percent", "int", _D["shutdown_percent"], bounds=(0, 50)),
    FieldSpec("discharge_seconds_per_pct", "int", _D["discharge_seconds_per_pct"], bounds=(0, 3600)),
    FieldSpec("runtime_minutes", "int", _D["runtime_minutes"], bounds=(0, 60)),
    FieldSpec("min_outage_seconds", "int", _D["min_outage_seconds"], bounds=(0, 3600)),
    FieldSpec("confirm_seconds", "int", _D["confirm_seconds"], bounds=(0, 600)),
    FieldSpec("retry_max", "int", _D["retry_max"], bounds=(0, 3)),
)
UDR7_FIELDS: tuple[FieldSpec, ...] = SSH_FIELDS + (
    FieldSpec("wol_mac", "str", _D["wol_mac"], pattern=MAC_PATTERN),
)
NAME_FIELD = FieldSpec("name", "str", "", pattern=NAME_PATTERN, required=True)

# --- o espelho legado: 14 chaves do .env ↔ a instância `udr7` -------------------------
LEGACY_KEY_TO_FIELD: dict[str, str] = {
    "UDR7_SSH_HOST": "ssh_host", "UDR7_SSH_PORT": "ssh_port", "UDR7_SSH_USER": "ssh_user",
    "UDR7_SSH_KEY": "ssh_key", "UDR7_SHUTDOWN_PERCENT": "shutdown_percent",
    "UDR7_DISCHARGE_SECONDS_PER_PCT": "discharge_seconds_per_pct",
    "UDR7_RUNTIME_MINUTES": "runtime_minutes", "UDR7_MIN_OUTAGE_SECONDS": "min_outage_seconds",
    "UDR7_CONFIRM_SECONDS": "confirm_seconds", "UDR7_RETRY_MAX": "retry_max",
    "UDR7_WOL_MAC": "wol_mac",
}
LEGACY_KEY_TO_ATTR: dict[str, str] = {
    "PROTECT_UDR7": "enabled", "PROTECT_DRY_RUN": "dry_run", "UDR7_NAME": "name",
}
LEGACY_FIELD_TO_KEY = {v: k for k, v in LEGACY_KEY_TO_FIELD.items()}
LEGACY_ATTR_TO_KEY = {v: k for k, v in LEGACY_KEY_TO_ATTR.items()}


def legacy_instance(cfg) -> DeviceInstance:
    """A instância `udr7` montada do `.env` (migração na 1.ª execução da 0.3.0)."""
    return DeviceInstance(
        id=LEGACY_INSTANCE_ID, type=Udr7SshPlugin.type_id,
        name=cfg.udr7_name or Udr7SshPlugin.default_name,
        enabled=bool(cfg.protect_udr7), dry_run=bool(cfg.protect_dry_run),
        fields={f: getattr(cfg, k.lower()) for k, f in LEGACY_KEY_TO_FIELD.items()},
        created_at=now_iso(), updated_at=now_iso(),
    )


def absorb_legacy_keys(instance: DeviceInstance, cfg, keys) -> DeviceInstance:
    """Depois de um PUT legado: as chaves tocadas entram na instância (.env → loja)."""
    for key in keys:
        if key in LEGACY_KEY_TO_FIELD:
            instance.fields[LEGACY_KEY_TO_FIELD[key]] = getattr(cfg, key.lower())
        elif key in LEGACY_KEY_TO_ATTR:
            attr = LEGACY_KEY_TO_ATTR[key]
            value = getattr(cfg, key.lower())
            if attr == "name":
                value = value or Udr7SshPlugin.default_name
            setattr(instance, attr, value)
    instance.updated_at = now_iso()
    return instance


def apply_instance_to_cfg(instance: DeviceInstance, cfg) -> list[str]:
    """No boot: a loja vence. Copia a instância `udr7` para o BridgeConfig em memória
    (para `GET /v1/config` dizer a verdade) e devolve as chaves cujo `.env` divergia —
    nomes só, nunca valores. O `.env` NÃO é reescrito aqui."""
    shadowed: list[str] = []
    for key, attr in LEGACY_KEY_TO_ATTR.items():
        value = getattr(instance, attr)
        if getattr(cfg, key.lower()) != value:
            shadowed.append(key)
            setattr(cfg, key.lower(), value)
    for key, field_name in LEGACY_KEY_TO_FIELD.items():
        value = instance.fields.get(field_name, INSTANCE_FIELD_DEFAULTS[field_name])
        if getattr(cfg, key.lower()) != value:
            shadowed.append(key)
            setattr(cfg, key.lower(), value)
    return shadowed


def legacy_changes_to_patch(changes: dict) -> dict:
    """Um PUT legado (`{UDR7_SSH_HOST: ..., PROTECT_DRY_RUN: ...}`) como patch de instância."""
    patch: dict = {}
    fields: dict = {}
    for key, value in changes.items():
        if key in LEGACY_KEY_TO_ATTR:
            patch[LEGACY_KEY_TO_ATTR[key]] = value
        elif key in LEGACY_KEY_TO_FIELD:
            fields[LEGACY_KEY_TO_FIELD[key]] = value
    if fields:
        patch["fields"] = fields
    return patch


class Udr7SshPlugin(SshMotorPlugin):
    type_id = "udr7_ssh"
    label_pt = "Console UniFi (UDR7)"
    label_en = "UniFi console (UDR7)"
    default_name = "UDR7"
    event_prefix = "UDR7_"
    fields = UDR7_FIELDS
    # As 14 chaves legadas que este tipo ainda possui no .env (espelho da instância
    # `udr7`). Literal de propósito: o teste de partição compara com o conjunto
    # montado por prefixo, descontadas as três do núcleo (LEGACY_CORE_KEYS).
    legacy_keys = frozenset(LEGACY_KEY_TO_FIELD) | frozenset(LEGACY_KEY_TO_ATTR)
    # O que este tipo congela no PUT /v1/config enquanto armado: as suas chaves
    # legadas (menos o nome) mais as do núcleo — exatamente PROTECTION_KEYS.
    frozen_keys = PROTECTION_KEYS

    @classmethod
    def shutdown_command_for(cls, instance) -> str:
        return POWEROFF.argv          # da tabela deste tipo, com fonte verificada

    def authorize(self, changes: dict, snapshot: dict | None,
                  comm_ok: bool) -> tuple[int, str, str] | None:
        """PUT /v1/config legado: traduz as chaves para um patch e aplica as MESMAS
        regras de `authorize_update`; as chaves do núcleo seguem a regra do motor."""
        core = super().authorize({k: v for k, v in changes.items() if k in LEGACY_CORE_KEYS
                                  or k not in self.legacy_keys}, snapshot, comm_ok)
        if core is not None:
            return core
        patch = legacy_changes_to_patch(changes)
        if not patch:
            return None
        return self.authorize_update(patch, snapshot, comm_ok)

    def on_config_applied(self, cfg) -> list:
        """Um PUT legado já gravou o .env e o `cfg`: absorve as chaves na instância e
        refresca a política (núcleo incluído)."""
        touched = [k for k in self.legacy_keys if self._cfg_value(cfg, k) != self._instance_value(k)]
        if touched:
            absorb_legacy_keys(self.instance, cfg, touched)
        return super().on_config_applied(cfg)

    def _instance_value(self, key: str):
        if key in LEGACY_KEY_TO_FIELD:
            field_name = LEGACY_KEY_TO_FIELD[key]
            return self.instance.fields.get(field_name, INSTANCE_FIELD_DEFAULTS[field_name])
        return getattr(self.instance, LEGACY_KEY_TO_ATTR[key])

    def _cfg_value(self, cfg, key: str):
        value = getattr(cfg, key.lower())
        if key == "UDR7_NAME":
            return value or self.default_name      # nome vazio no .env = o padrão
        return value
