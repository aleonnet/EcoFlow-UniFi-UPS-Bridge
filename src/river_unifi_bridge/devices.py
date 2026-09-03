"""A loja de instâncias de dispositivos protegidos (2026-09-03).

As instâncias vivem em `<RUB_STATE_DIR>/devices.json` — JSON, 0600, escrita
atômica pelo mesmo `_write_private_json` que grava `<id>_armed.json`, leitura
pelo `_read_private_json`, que recusa arquivo de outro uid ou com permissão
aberta. É a VERDADE sobre quais dispositivos existem; o `.env` continua sendo
o núcleo (NUT, alarmes, API, a trava e as duas chaves do River) e, para a
instância migrada `udr7`, um espelho das 14 chaves legadas.

Regras deliberadas:
* Arquivo ausente → migração: o construtor legado (do tipo `udr7_ssh`) monta a
  instância `udr7` a partir do `.env`, uma única vez. Arquivo presente → carrega
  e NUNCA relê o `.env` para instâncias: rodar dez vezes não duplica, não perde o
  que foi adicionado, não ressuscita o que foi apagado.
* Arquivo presente mas ilegível (uid/permissão/JSON/forma) → `DevicesError`. O
  chamador para deliberadamente — "lista vazia silenciosa" apagaria a proteção
  sem aviso.
* Ids são gerados aqui (`<prefixo>_<8 hex>`), nunca escolhidos pelo usuário: eles
  entram em nomes de arquivo (`<id>_known_hosts`…) e na linha de auditoria.
* Nome único entre instâncias (strip + casefold): recusado, não diferenciado.
"""

from __future__ import annotations

import os
import re
import secrets
import time
from dataclasses import dataclass, field

from .plugins.base import FieldSpec
from .protect import _read_private_json, _write_private_json, log_json

STORE_VERSION = 1
LEGACY_INSTANCE_ID = "udr7"
ID_PATTERN = re.compile(r"[a-z][a-z0-9_]{0,39}")


class DevicesError(Exception):
    """A loja está inválida ou um pedido foi recusado; a mensagem nomeia o motivo."""


@dataclass
class DeviceInstance:
    id: str
    type: str
    name: str
    enabled: bool = False
    dry_run: bool = True
    fields: dict = field(default_factory=dict)
    created_at: str = ""
    updated_at: str = ""

    @property
    def armed(self) -> bool:
        return bool(self.enabled) and not bool(self.dry_run)

    def to_json(self) -> dict:
        return {
            "id": self.id, "type": self.type, "name": self.name,
            "enabled": bool(self.enabled), "dry_run": bool(self.dry_run),
            "fields": dict(self.fields),
            "created_at": self.created_at, "updated_at": self.updated_at,
        }

    @classmethod
    def from_json(cls, data: object) -> "DeviceInstance":
        if not isinstance(data, dict):
            raise DevicesError("instância não é um objeto")
        try:
            inst = cls(
                id=str(data["id"]), type=str(data["type"]), name=str(data["name"]),
                enabled=bool(data.get("enabled", False)), dry_run=bool(data.get("dry_run", True)),
                fields=dict(data.get("fields") or {}),
                created_at=str(data.get("created_at", "")), updated_at=str(data.get("updated_at", "")),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise DevicesError(f"instância inválida: {exc}") from exc
        if ID_PATTERN.fullmatch(inst.id) is None:
            raise DevicesError(f"id inválido: {inst.id!r}")
        if not inst.name.strip():
            raise DevicesError(f"instância {inst.id}: nome vazio")
        return inst


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def new_id(prefix: str) -> str:
    """`<prefixo>_<8 hex>`: só minúsculas, dígitos e underscore — vai em nome de arquivo."""
    return f"{prefix}_{secrets.token_hex(4)}"


def _parse_bool(raw: object) -> bool:
    if isinstance(raw, bool):
        return raw
    if str(raw) in ("1", "true", "TRUE", "yes"):
        return True
    if str(raw) in ("0", "false", "FALSE", "no"):
        return False
    raise DevicesError(f"valor booleano inválido: {raw!r} (use 1/0)")


def validate_fields(specs: tuple[FieldSpec, ...], raw: dict, *, partial: bool = False) -> dict:
    """Aplica a especificação do tipo a um dicionário cru (POST: completo; PUT: parcial).

    Mesmas regras de `config.validate_update`: strip, bool por 1/0, faixa para int,
    `fullmatch` para str, valores proibidos, lista fechada (`enum`). Campo
    desconhecido é erro — a forma não é aberta. Devolve o dicionário limpo.
    """
    if not isinstance(raw, dict):
        raise DevicesError("fields não é um objeto")
    known = {s.name: s for s in specs}
    unknown = sorted(set(raw) - set(known))
    if unknown:
        raise DevicesError(f"campo desconhecido: {unknown[0]}")
    out: dict = {}
    for spec in specs:
        if spec.name not in raw:
            if partial:
                continue
            if spec.required:
                raise DevicesError(f"campo obrigatório ausente: {spec.name}")
            out[spec.name] = spec.default
            continue
        value = raw[spec.name]
        if spec.type == "bool":
            out[spec.name] = _parse_bool(value)
            continue
        if spec.type == "int":
            try:
                number = int(str(value).strip())
            except ValueError as exc:
                raise DevicesError(f"campo {spec.name}: inteiro inválido") from exc
            if spec.bounds is not None and not spec.bounds[0] <= number <= spec.bounds[1]:
                raise DevicesError(
                    f"campo {spec.name}: fora da faixa ({spec.bounds[0]}..{spec.bounds[1]})")
            out[spec.name] = number
            continue
        text = str(value).strip()
        if text == "":
            if spec.required:
                raise DevicesError(f"campo obrigatório vazio: {spec.name}")
            out[spec.name] = ""
            continue
        if spec.enum is not None and text not in spec.enum:
            raise DevicesError(f"campo {spec.name}: valor fora da lista permitida")
        if spec.pattern is not None and spec.pattern.fullmatch(text) is None:
            raise DevicesError(f"campo {spec.name}: valor inválido para o formato exigido")
        reason = (spec.forbidden or {}).get(text)
        if reason is not None:
            raise DevicesError(f"campo {spec.name}: valor recusado ({reason})")
        out[spec.name] = text
    return out


class DeviceStore:
    def __init__(self, path: str) -> None:
        self.path = path

    def exists(self) -> bool:
        return os.path.exists(self.path)

    def load(self) -> list[DeviceInstance]:
        """Lê a loja. Arquivo ausente = lista vazia; presente e inválido = DevicesError."""
        if not self.exists():
            return []
        data = _read_private_json(self.path)
        if data is None:
            raise DevicesError(
                f"{self.path}: ilegível, de outro usuário ou com permissão aberta (esperado 0600 do serviço)")
        if data.get("version") != STORE_VERSION:
            raise DevicesError(f"{self.path}: versão desconhecida {data.get('version')!r}")
        raw = data.get("devices")
        if not isinstance(raw, list):
            raise DevicesError(f"{self.path}: 'devices' não é uma lista")
        devices = [DeviceInstance.from_json(item) for item in raw]
        self._check_unique(devices)
        return devices

    def save(self, devices: list[DeviceInstance]) -> None:
        self._check_unique(devices)
        _write_private_json(self.path, {
            "version": STORE_VERSION,
            "devices": [d.to_json() for d in devices],
        })

    def load_or_migrate(self, legacy_builder) -> list[DeviceInstance]:
        """Arquivo presente: carrega (nunca re-migra). Ausente: migra UMA vez.

        `legacy_builder()` devolve a instância `udr7` montada do `.env` (é o tipo
        `udr7_ssh` quem sabe o mapa das chaves legadas), ou None quando não há o
        que migrar — a loja nasce vazia.
        """
        if self.exists():   # arquivo presente: nunca re-migra
            return self.load()
        legacy = legacy_builder()
        devices = [legacy] if legacy is not None else []
        if legacy is not None and legacy.id != LEGACY_INSTANCE_ID:
            raise DevicesError(f"a instância migrada tem de ser {LEGACY_INSTANCE_ID!r}, veio {legacy.id!r}")
        self.save(devices)
        log_json("INFO", "devices_migrated", path=self.path, devices=[d.id for d in devices])
        return devices

    @staticmethod
    def name_taken(devices: list[DeviceInstance], name: str, *, except_id: str | None = None) -> bool:
        wanted = name.strip().casefold()
        for other in devices:
            if other.id == except_id:
                continue
            if other.name.strip().casefold() == wanted:
                return True
        return False

    @classmethod
    def _check_unique(cls, devices: list[DeviceInstance]) -> None:
        ids = [d.id for d in devices]
        if len(set(ids)) != len(ids):
            raise DevicesError("ids repetidos na loja")
        for i, d in enumerate(devices):
            if cls.name_taken(devices[:i], d.name):
                raise DevicesError(f"nome_duplicado: já existe um dispositivo chamado {d.name!r}")
