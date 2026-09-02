"""The UDR7 over SSH — the first device plugin.

A thin adapter: it COMPOSES `ProtectionPolicy` and `ConfigHolder` from
`protect.py`, which does not move. What lives here is what is specific to this
device as a *plugin*: which keys it owns, which of them are frozen while armed,
and the arming rules that used to sit in `api._authorize`.
"""

from __future__ import annotations

import os

from ..config import PROTECTION_KEYS
from ..protect import ConfigHolder, ProtectionConfig, ProtectionPolicy, _is_synthetic_driver
from .base import DevicePlugin

# --- O VOCABULÁRIO DE COMANDOS DESTE DISPOSITIVO -----------------------------
#
# Mora AQUI, no plugin, e não em protect.py: `protect.py` é o transporte (monta o
# ssh isolado e executa); o que se diz do outro lado é do dispositivo. Um segundo
# aparelho traz a sua própria tabela e não toca em nada disto.
#
# TODO comando abaixo tem fonte verificada em 2026-09-01 — nada aqui é suposição.
# Antes desta tabela o código tinha UM comando com o comentário "H11a — hypothesis
# until probed", e eu cheguei a propor um `ubnt-systool info` que NÃO EXISTE.

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
        "POSIX `command -v`; é o mesmo teste que o instalador oficial do "
        "unifi-common usa (`command_exists()` em remote_install.sh)"),
    "model": Cmd(
        "model", "ubnt-device-info model", False,
        "unifi-common/remote_install.sh:38 e :131 — o script oficial da comunidade "
        "roda isto NO console e casa a saída com \"UniFi Dream Router 7\""),
    "firmware": Cmd(
        "firmware", "ubnt-device-info firmware", False,
        "unifi-common/remote_install.sh:131 — `ubnt-device-info firmware`"),
    # --- ato final (destrutivo) ---------------------------------------------
    "poweroff": Cmd(
        "poweroff", "ubnt-systool poweroff", True,
        "wiki CLI de ubnt-systool (lista completa de subcomandos) + gist "
        "\"Graceful shutdown of UDMP via NUT\" + LazyAdmin: é o desligamento "
        "gracioso do UniFi OS, preferível ao `poweroff` do Linux"),
    "reboot": Cmd(
        "reboot", "ubnt-systool reboot", True,
        "wiki CLI de ubnt-systool. NÃO é usado pela proteção: reiniciar numa "
        "queda gastaria bateria e devolveria o console ligado. Fica declarado "
        "para o operador saber que existe e que a escolha foi consciente"),
}

# O que a política dispara quando decide agir. É `poweroff` por decisão, não por
# acaso: ver a nota do `reboot` acima.
POWEROFF = COMMANDS["poweroff"]
# O que prova alcance sem tocar em nada. Existe porque o estado
# `armado_nao_verificado` denunciava que o daemon armava sem NUNCA ter falado
# com o console.
PROBE = COMMANDS["probe"]


# The two keys that form the arming predicate. A PUT touching ONLY these, and
# making `armed` false, is a pure disarm and is always accepted.
_PREDICATE_KEYS = frozenset({"PROTECT_UDR7", "PROTECT_DRY_RUN"})


def _is_pure_disarm(changes: dict, pc: ProtectionConfig) -> bool:
    """A PUT that contains ONLY the predicate keys and makes `armed` false."""
    if not set(changes) <= _PREDICATE_KEYS:
        return False
    protect = changes.get("PROTECT_UDR7", pc.protect_udr7)
    dry_run = changes.get("PROTECT_DRY_RUN", pc.protect_dry_run)
    return not (protect and not dry_run)


class Udr7SshPlugin(DevicePlugin):
    id = "udr7"
    # Literal on purpose, NOT derived by prefix: the test that partitions the
    # allowlist among plugins compares this literal with the set built from the
    # prefixes, so it catches a PROTECT_/UDR7_ key that no plugin owns. Deriving
    # it here would make that test compare a thing with itself.
    config_keys = frozenset({
        "PROTECT_UDR7", "PROTECT_DRY_RUN", "UDR7_ARM_ALLOWED", "UDR7_SSH_HOST",
        "UDR7_SSH_PORT", "UDR7_SSH_USER", "UDR7_SSH_KEY", "UDR7_EXPECTED_SERIAL",
        "UDR7_CUTOFF_PERCENT", "UDR7_SHUTDOWN_PERCENT", "UDR7_DISCHARGE_SECONDS_PER_PCT",
        "UDR7_RUNTIME_MINUTES", "UDR7_MIN_OUTAGE_SECONDS", "UDR7_CONFIRM_SECONDS",
        "UDR7_RETRY_MAX", "UDR7_WOL_MAC", "UDR7_NAME",
    })
    # Includes the three NUT_* keys: they decide WHICH source feeds the policy,
    # so changing them while armed would move the ground under it. Note that
    # UDR7_NAME is NOT here — renaming the device while armed is allowed.
    frozen_keys = PROTECTION_KEYS

    def __init__(self, holder: ConfigHolder, policy: ProtectionPolicy):
        self._holder = holder
        self._policy = policy

    @classmethod
    def build(cls, cfg, state_dir: str) -> "Udr7SshPlugin":
        holder = ConfigHolder(ProtectionConfig.from_cfg(cfg))
        policy = ProtectionPolicy(
            holder,
            known_hosts_path=os.path.join(state_dir, "udr7_known_hosts"),
            armed_path=os.path.join(state_dir, "udr7_armed.json"),
            runtime_path=os.path.join(state_dir, "udr7_runtime.json"),
            shutdown_command=POWEROFF.argv,      # da tabela deste plugin
        )
        return cls(holder, policy)

    # --- what the loop calls ----------------------------------------------------
    @property
    def armed(self) -> bool:
        return self._holder.get().armed

    def observe(self, snap, tracker_events: list[str]) -> list:
        return self._policy.observe(snap, tracker_events)

    def observe_failure(self, tracker_events: list[str]) -> list:
        return self._policy.observe_failure(tracker_events)

    def on_config_applied(self, cfg) -> list:
        """Rebuild this plugin's snapshot from the new effective config.

        `holder.replace` runs OUTSIDE the policy lock (the holder owns its own),
        and the policy is only told when something actually changed.
        """
        new = ProtectionConfig.from_cfg(cfg)
        old = self._holder.get()
        self._holder.replace(new)
        if new == old:
            return []
        return self._policy.on_config_applied(old, new)

    def status(self) -> dict:
        return self._policy.status()

    def drain_transition(self) -> tuple[str | None, str] | None:
        return self._policy.drain_transition()

    # --- the arming rules (were api._authorize) ---------------------------------
    def authorize(self, changes: dict, snapshot: dict | None,
                  comm_ok: bool) -> tuple[int, str, str] | None:
        """§7A.5. Runs BEFORE anything is written, so a 4xx leaves no trace.

        The 400 for file-only keys is NOT here: it is generic and stays in the
        API, because it must answer the same way with no plugins at all.
        """
        pc = self._holder.get()
        protect_after = changes.get("PROTECT_UDR7", pc.protect_udr7)
        dry_run_after = changes.get("PROTECT_DRY_RUN", pc.protect_dry_run)
        armed_after = bool(protect_after) and not bool(dry_run_after)
        if pc.armed:
            if _is_pure_disarm(changes, pc):
                return None
            touched = sorted(set(changes) & self.frozen_keys)
            if touched:
                return 409, "armado", (
                    f"{touched[0]}: configuração congelada enquanto a proteção está armada — "
                    "desligue a proteção (ligar modo ensaio) antes")
            return None
        if armed_after:
            if not pc.udr7_arm_allowed:
                return 409, "armamento_bloqueado", (
                    "trava fechada: UDR7_ARM_ALLOWED=1 no arquivo do serviço e reinicie antes de armar")
            if snapshot is None or not comm_ok:
                return 409, "sem_snapshot", "sem leitura corrente do NUT — não há como verificar a fonte"
            source = snapshot.get("source") or {}
            name, version = source.get("driver_name"), source.get("driver_version")
            if not name or not version or _is_synthetic_driver(name, version):
                return 409, "fonte_nao_real", (
                    "a fonte de telemetria corrente não é aceita para armar "
                    f"(driver {name!r} {version!r})")
            expected = changes.get("UDR7_EXPECTED_SERIAL", pc.udr7_expected_serial)
            serial = (snapshot.get("identity") or {}).get("serial")
            if not expected or serial != expected:
                return 409, "fonte_nao_real", (
                    "serial da leitura corrente não confere com UDR7_EXPECTED_SERIAL")
        return None
