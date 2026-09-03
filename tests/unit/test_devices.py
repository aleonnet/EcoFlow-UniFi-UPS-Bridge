"""A loja de instâncias (devices.json): migração única, permissões, forma, nomes."""

from __future__ import annotations

import json
import os
import re
import stat

import pytest

from river_unifi_bridge import devices as dev
from river_unifi_bridge.devices import (
    DeviceInstance, DeviceStore, DevicesError, ID_PATTERN, LEGACY_INSTANCE_ID, new_id,
    validate_fields,
)
from river_unifi_bridge.plugins.base import FieldSpec


def legacy():
    return DeviceInstance(id=LEGACY_INSTANCE_ID, type="udr7_ssh", name="UDR7",
                          fields={"ssh_host": "192.0.2.1"})


def host(n: int, name: str | None = None) -> DeviceInstance:
    return DeviceInstance(id=f"sshhost_{n:08x}", type="ssh_host", name=name or f"Servidor {n}",
                          fields={"ssh_host": f"192.0.2.{n}"})


@pytest.fixture
def store(tmp_path):
    return DeviceStore(str(tmp_path / "state" / "devices.json"))


# --- migração ---------------------------------------------------------------------
def test_migration_runs_once_in_ten_boots(store):
    calls = []

    def builder():
        calls.append(1)
        return legacy()

    for _ in range(10):
        devices = store.load_or_migrate(builder)
    assert calls == [1]
    assert [d.id for d in devices] == [LEGACY_INSTANCE_ID]


def test_migration_is_idempotent_keeps_added_instance(store):
    store.load_or_migrate(legacy)
    store.save(store.load() + [host(1)])
    devices = store.load_or_migrate(legacy)          # 2.º "boot": arquivo presente
    assert [d.id for d in devices] == [LEGACY_INSTANCE_ID, "sshhost_00000001"]


def test_deleted_udr7_is_not_resurrected(store):
    store.load_or_migrate(legacy)
    store.save([])                                    # o dono removeu o UDR7 pela interface
    assert store.load_or_migrate(legacy) == []


def test_migration_with_nothing_to_migrate_creates_an_empty_store(store):
    assert store.load_or_migrate(lambda: None) == []
    assert store.exists()


def test_migrated_instance_id_is_the_alias(store):
    from river_unifi_bridge.state import UDR7_ALIAS_ID
    assert LEGACY_INSTANCE_ID == UDR7_ALIAS_ID
    with pytest.raises(DevicesError, match="instância migrada"):
        store.load_or_migrate(lambda: host(7))


# --- permissões e forma ------------------------------------------------------------
def test_store_is_private_0600(store):
    store.save([legacy()])
    mode = stat.S_IMODE(os.stat(store.path).st_mode)
    assert mode == 0o600
    assert os.stat(store.path).st_uid == os.getuid()


def test_store_invalid_file_raises(store):
    os.makedirs(os.path.dirname(store.path), exist_ok=True)
    with open(store.path, "w", encoding="utf-8") as fh:
        fh.write("{not json")
    os.chmod(store.path, 0o600)
    with pytest.raises(DevicesError):
        store.load()
    with open(store.path, "w", encoding="utf-8") as fh:
        json.dump({"version": 1, "devices": [legacy().to_json()]}, fh)
    os.chmod(store.path, 0o644)                       # permissão aberta: não é nossa
    with pytest.raises(DevicesError, match="0600"):
        store.load()
    os.chmod(store.path, 0o600)
    assert [d.id for d in store.load()] == [LEGACY_INSTANCE_ID]


def test_store_rejects_unknown_version_and_bad_shape(store):
    os.makedirs(os.path.dirname(store.path), exist_ok=True)
    for payload in ({"version": 2, "devices": []}, {"version": 1, "devices": {}},
                    {"version": 1, "devices": [{"id": "UDR7", "type": "x", "name": "n"}]},
                    {"version": 1, "devices": [{"id": "ok", "type": "x", "name": "  "}]}):
        with open(store.path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
        os.chmod(store.path, 0o600)
        with pytest.raises(DevicesError):
            store.load()


def test_ids_are_generated_lowercase_and_file_safe():
    for _ in range(20):
        i = new_id("sshhost")
        assert ID_PATTERN.fullmatch(i) and re.fullmatch(r"sshhost_[0-9a-f]{8}", i)


# --- nomes -------------------------------------------------------------------------
def test_store_rejects_duplicate_name_casefold(store):
    with pytest.raises(DevicesError, match="nome_duplicado"):
        store.save([host(1, "Servidor"), host(2, " servidor ")])
    assert DeviceStore.name_taken([host(1, "Servidor")], "SERVIDOR")
    assert not DeviceStore.name_taken([host(1, "Servidor")], "Servidor", except_id="sshhost_00000001")


# --- validate_fields ---------------------------------------------------------------
SPECS = (
    FieldSpec("ssh_host", "str", "", pattern=re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}"), required=True),
    FieldSpec("ssh_port", "int", 22, bounds=(1, 65535)),
    FieldSpec("shutdown_command", "str", "shutdown -h now", enum=("shutdown -h now", "poweroff")),
    FieldSpec("serial", "str", "", forbidden={"SIM0001": "serial_de_simulador"}),
    FieldSpec("flag", "bool", False),
)


def test_validate_fields_fills_defaults_and_coerces():
    out = validate_fields(SPECS, {"ssh_host": " 192.0.2.1 ", "ssh_port": "2222", "flag": "1"})
    assert out == {"ssh_host": "192.0.2.1", "ssh_port": 2222, "shutdown_command": "shutdown -h now",
                   "serial": "", "flag": True}


@pytest.mark.parametrize("raw, msg", [
    ({"ssh_port": 1}, "obrigatório ausente: ssh_host"),
    ({"ssh_host": "-x"}, "formato exigido"),
    ({"ssh_host": "h", "ssh_port": "70000"}, "fora da faixa"),
    ({"ssh_host": "h", "ssh_port": "abc"}, "inteiro inválido"),
    ({"ssh_host": "h", "shutdown_command": "rm -rf /"}, "fora da lista permitida"),
    ({"ssh_host": "h", "serial": "SIM0001"}, "serial_de_simulador"),
    ({"ssh_host": "h", "flag": "talvez"}, "booleano inválido"),
    ({"ssh_host": "h", "extra": 1}, "campo desconhecido: extra"),
])
def test_validate_fields_refuses(raw, msg):
    with pytest.raises(DevicesError, match=msg):
        validate_fields(SPECS, raw)


def test_validate_fields_partial_only_touches_given_keys():
    assert validate_fields(SPECS, {"ssh_port": "22"}, partial=True) == {"ssh_port": 22}
