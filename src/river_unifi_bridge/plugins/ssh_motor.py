"""O motor SSH comum aos tipos que desligam um aparelho por `ssh` (2026-09-03).

Compõe `ProtectionPolicy` + `ConfigHolder` de `protect.py` (que não se move) para
UMA instância: caminhos de estado por id (`<id>_known_hosts`, `<id>_armed.json`,
`<id>_runtime.json`), ações etiquetadas com o dono (`device`, `device_name`) e o
prefixo de evento do tipo, e as regras de armamento que antes viviam no adaptador
do UDR7 — agora sobre o patch de uma instância (`enabled`, `dry_run`, `name`,
`fields`), que é o que `PUT /v1/devices/{id}` recebe.

O que cada TIPO acrescenta: `type_id`, rótulos, `default_name`, `event_prefix`,
`fields` (FieldSpec) e `shutdown_command_for(instance)` — a tabela de comandos do
UDR7 ou o comando escolhido de uma lista fechada no host genérico.
"""

from __future__ import annotations

import os

from ..config import CORE_FROZEN_KEYS
from ..protect import ConfigHolder, ProtectionConfig, ProtectionPolicy, _is_synthetic_driver
from .base import DevicePlugin

# As duas chaves do patch que formam o predicado de armamento. Um PUT que só as
# toca e torna `armed` falso é um desarme puro — sempre aceito (o botão de parada).
_PREDICATE_KEYS = frozenset({"enabled", "dry_run"})


def _is_pure_disarm(changes: dict, pc: ProtectionConfig) -> bool:
    if not set(changes) <= _PREDICATE_KEYS:
        return False
    enabled = changes.get("enabled", pc.protect_udr7)
    dry_run = changes.get("dry_run", pc.protect_dry_run)
    return not (bool(enabled) and not bool(dry_run))


class SshMotorPlugin(DevicePlugin):
    frozen_keys = CORE_FROZEN_KEYS
    legacy_keys: frozenset[str] = frozenset()

    def __init__(self, instance, holder: ConfigHolder, policy: ProtectionPolicy, cfg=None) -> None:
        self.instance = instance
        self.id = instance.id
        self._holder = holder
        self._policy = policy
        self._cfg = cfg

    # --- o que cada tipo define ------------------------------------------------
    @classmethod
    def shutdown_command_for(cls, instance) -> str:   # pragma: no cover — abstrato por contrato
        raise NotImplementedError

    @classmethod
    def state_paths(cls, instance_id: str, state_dir: str) -> dict:
        return {
            "known_hosts_path": os.path.join(state_dir, f"{instance_id}_known_hosts"),
            "armed_path": os.path.join(state_dir, f"{instance_id}_armed.json"),
            "runtime_path": os.path.join(state_dir, f"{instance_id}_runtime.json"),
        }

    @classmethod
    def build(cls, instance, cfg, state_dir: str) -> "SshMotorPlugin":
        command = cls.shutdown_command_for(instance)
        holder = ConfigHolder(ProtectionConfig.from_instance(instance, cfg, shutdown_command=command))
        policy = ProtectionPolicy(
            holder, shutdown_command=command, default_name=cls.default_name,
            **cls.state_paths(instance.id, state_dir),
        )
        return cls(instance, holder, policy, cfg)

    # --- o que o laço chama --------------------------------------------------------
    @property
    def armed(self) -> bool:
        return self._holder.get().armed

    def _event_name(self, event: str | None) -> str | None:
        """O motor fala UDR7_*; cada tipo publica com o SEU prefixo."""
        if event is not None and event.startswith("UDR7_"):
            return self.event_prefix + event[len("UDR7_"):]
        return event

    def _tag(self, actions: list) -> list:
        """Toda ação sai com o dono e com o prefixo de evento do tipo."""
        name = self._holder.get().udr7_name or self.default_name
        for action in actions:
            action.event = self._event_name(action.event)
            action.payload["device"] = self.id
            action.payload["device_name"] = name
        return actions

    def observe(self, snap, tracker_events: list[str]) -> list:
        return self._tag(self._policy.observe(snap, tracker_events))

    def observe_failure(self, tracker_events: list[str]) -> list:
        return self._tag(self._policy.observe_failure(tracker_events))

    def _rebuild(self) -> list:
        """Reconstrói a configuração da política a partir da instância + núcleo.

        `holder.replace` corre FORA da trava da política (o holder tem a sua);
        a política só é avisada quando algo mudou — é ela que grava/apaga o
        `<id>_armed.json` e emite ARMED/DISARMED.
        """
        new = ProtectionConfig.from_instance(
            self.instance, self._cfg, shutdown_command=self.shutdown_command_for(self.instance))
        old = self._holder.get()
        self._holder.replace(new)
        if new == old:
            return []
        return self._tag(self._policy.on_config_applied(old, new))

    def on_config_applied(self, cfg) -> list:
        """O NÚCLEO mudou (NUT, trava, série esperada, corte): refresca esta instância."""
        self._cfg = cfg
        return self._rebuild()

    def apply_patch(self, instance) -> list:
        self.instance = instance
        return self._rebuild()

    def status(self) -> dict:
        st = self._policy.status()
        st["last_event"] = self._event_name(st.get("last_event"))   # o health fala a língua do tipo
        return st

    def drain_transition(self) -> tuple[str | None, str] | None:
        return self._policy.drain_transition()

    # --- autorização ----------------------------------------------------------------
    def authorize(self, changes: dict, snapshot: dict | None,
                  comm_ok: bool) -> tuple[int, str, str] | None:
        """PUT /v1/config: as chaves do núcleo que esta instância congela quando armada."""
        pc = self._holder.get()
        if pc.armed:
            touched = sorted(set(changes) & self.frozen_keys)
            if touched:
                return 409, "armado", (
                    f"{touched[0]}: configuração congelada enquanto {pc.udr7_name or self.default_name} "
                    "está armado — desligue a proteção (ligar modo ensaio) antes")
        return None

    def authorize_update(self, changes: dict, snapshot: dict | None,
                         comm_ok: bool) -> tuple[int, str, str] | None:
        """§7A.5 sobre o patch de UMA instância. Corre ANTES de qualquer escrita.

        `changes` traz um subconjunto de {name, enabled, dry_run, fields}. O nome
        nunca é congelado (renomear armado é permitido); tudo o mais é.
        """
        pc = self._holder.get()
        enabled_after = changes.get("enabled", pc.protect_udr7)
        dry_run_after = changes.get("dry_run", pc.protect_dry_run)
        armed_after = bool(enabled_after) and not bool(dry_run_after)
        if pc.armed:
            if _is_pure_disarm(changes, pc):
                return None
            touched = sorted(set(changes) - {"name"})
            if touched:
                return 409, "armado", (
                    f"{touched[0]}: configuração congelada enquanto {pc.udr7_name or self.default_name} "
                    "está armado — desligue a proteção (ligar modo ensaio) antes")
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
            expected = pc.udr7_expected_serial
            serial = (snapshot.get("identity") or {}).get("serial")
            if not expected or serial != expected:
                return 409, "fonte_nao_real", (
                    "serial da leitura corrente não confere com o número de série esperado do River")
        return None
