"""The device-plugin contract, exercised over EVERY registered plugin.

Parametrised over `PLUGINS + (FakePlugin,)`: this is what proves the contract is
general without a second real device. A test that only ever sees the UDR7 would
pass for a contract shaped exactly like the UDR7.
"""

from __future__ import annotations

import pytest

from fake_plugin import FakePlugin
from river_unifi_bridge.config import DEVICE_NAME_KEYS, HOT_RELOAD_KEYS, PROTECTION_KEYS, allowlist_keys, load_config
from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.plugins import PLUGINS, build_plugins, plugin_statuses

MINIMAL = "NUT_HOST=127.0.0.1\nNUT_PORT=3493\nNUT_UPS=river\nRIVER_NAME=River\n"
ALL_CLASSES = list(PLUGINS) + [FakePlugin]


@pytest.fixture
def cfg(tmp_path):
    path = tmp_path / "bridge.env"
    path.write_text(MINIMAL, encoding="utf-8")
    return load_config(str(path))


@pytest.mark.parametrize("cls", ALL_CLASSES)
def test_contract_attributes(cls):
    assert cls.id and cls.id == cls.id.lower()
    assert cls.config_keys <= set(allowlist_keys()), "config_keys fora da allowlist"
    # Everything a plugin owns must be frozen while armed, EXCEPT the name: the
    # whole point of DEVICE_NAME_KEYS is that renaming stays possible.
    assert cls.frozen_keys >= (cls.config_keys - DEVICE_NAME_KEYS)


@pytest.mark.parametrize("cls", ALL_CLASSES)
def test_contract_methods(cls, cfg, tmp_path):
    """build/observe/status/drain run under the anti-spawn fence.

    `udr7_cutoff_percent=0` (the default of the minimal config) matters: it makes
    `_first_fail` return `corte_nao_configurado` BEFORE the known_hosts gate, so
    nothing tries to run ssh-keygen. It matters because `known_host_ok` only
    catches (OSError, SubprocessError) — an AssertionError from the fence would
    escape and be reported as a plugin bug.
    """
    leitura = snapshot_from_nut_vars("r", {
        "ups.status": "OL", "battery.charge": "80", "battery.runtime": "3600",
        "device.mfr": "EcoFlow", "device.model": "RIVER 3 Plus",
        "driver.name": "usbhid-ups", "driver.version": "2.8.4",
    })
    plugin = cls.build(cfg, str(tmp_path))
    assert isinstance(plugin.armed, bool)
    assert isinstance(plugin.observe(leitura, []), list)
    assert isinstance(plugin.observe_failure([]), list)
    st = plugin.status()
    assert "state" in st and "name" in st, "status() tem de trazer state e name"
    plugin.drain_transition()                       # não pode levantar
    # A key that belongs to NOBODY is never vetoed by this plugin.
    alheia = "HISTORY_RETENTION_DAYS"
    assert alheia not in (plugin.config_keys | plugin.frozen_keys)
    assert plugin.authorize({alheia: "7"}, None, False) is None


def test_udr7_frozen_keys_include_nut(cfg, tmp_path):
    """Só o UDR7: as chaves NUT_* condicionam a FONTE que alimenta a política."""
    plugin = PLUGINS[0].build(cfg, str(tmp_path))
    assert {"NUT_HOST", "NUT_PORT", "NUT_UPS"} <= plugin.frozen_keys


def test_registry_is_static_and_ids_unique():
    ids = [cls.id for cls in PLUGINS]
    assert len(set(ids)) == len(ids)
    assert PLUGINS == tuple(PLUGINS), "o registro é estático"


def test_device_keys_are_partitioned_among_plugins():
    """Toda chave PROTECT_/UDR7_ da allowlist tem exatamente um dono.

    Compara o literal declarado em cada plugin com o conjunto montado por
    PREFIXO a partir da allowlist. Por isso o literal existe: derivá-lo por
    prefixo tornaria este teste uma tautologia. Cego a prefixo NOVO — quando o
    2º plugin chegar, a convenção PLUGIN_<ID>_* entra junto (BACKLOG).
    """
    por_prefixo = {k for k in allowlist_keys() if k.startswith(("PROTECT_", "UDR7_"))}
    dos_plugins: set[str] = set()
    for cls in PLUGINS:
        assert not (dos_plugins & cls.config_keys), "duas plugins reivindicam a mesma chave"
        dos_plugins |= cls.config_keys
    assert dos_plugins == por_prefixo


@pytest.mark.parametrize("cls", ALL_CLASSES)
def test_no_plugin_freezes_another_plugins_key(cls):
    """Congelar a chave alheia deixaria um plugin VETAR o desarme do outro.

    Sem esta cerca, um plugin B que congelasse PROTECT_DRY_RUN faria o desarme
    do plugin A cair na regra "a primeira recusa vence". Vale nos dois sentidos
    graças ao FakePlugin, que tem config_keys não vazio.
    """
    outros: set[str] = set()
    for outro in ALL_CLASSES:
        if outro is not cls:
            outros |= outro.config_keys
    assert not (cls.frozen_keys & outros)


def test_udr7_name_is_hot_owned_and_never_frozen():
    udr7 = PLUGINS[0]
    assert "UDR7_NAME" in udr7.config_keys
    assert "UDR7_NAME" in HOT_RELOAD_KEYS
    assert "UDR7_NAME" not in udr7.frozen_keys
    assert "UDR7_NAME" not in PROTECTION_KEYS


def test_udr7_status_name_falls_back_when_empty(cfg, tmp_path):
    from dataclasses import replace

    plugin = PLUGINS[0].build(cfg, str(tmp_path))
    assert plugin.status()["name"] == "UDR7"
    plugin._holder.replace(replace(plugin._holder.get(), udr7_name="Meu UDR"))
    assert plugin.status()["name"] == "Meu UDR"
    plugin._holder.replace(replace(plugin._holder.get(), udr7_name=""))
    assert plugin.status()["name"] == "UDR7"


def test_plugin_statuses_reads_status_once(cfg, tmp_path):
    """O nome da entrada e o do detalhe vêm da MESMA leitura.

    Se `plugin_statuses` perguntasse duas vezes (uma para o nome, outra para o
    estado), um rename que caísse entre as duas publicaria uma entrada em que
    `name` diverge de `detail["name"]`.
    """
    class Contador(FakePlugin):
        def __init__(self):
            super().__init__()
            self.chamadas = 0

        def status(self):
            self.chamadas += 1
            return {"state": f"s{self.chamadas}", "name": f"n{self.chamadas}"}

    p = Contador()
    entradas = plugin_statuses([p])
    assert p.chamadas == 1
    assert entradas[0]["name"] == entradas[0]["detail"]["name"]
    assert entradas[0]["state"] == entradas[0]["detail"]["state"]


def test_build_plugins_builds_the_registry(cfg, tmp_path):
    plugins = build_plugins(cfg, str(tmp_path))
    assert [p.id for p in plugins] == [cls.id for cls in PLUGINS]
    entradas = plugin_statuses(plugins)
    assert entradas[0]["id"] == "udr7"
    assert entradas[0]["name"] == "UDR7"


# --- a tabela de comandos do dispositivo -------------------------------------

def test_every_device_command_has_a_verified_source():
    """Nenhum comando entra na tabela sem fonte, e nenhum é hipótese.

    Esta cerca existe porque o código carregou por semanas um único comando com
    o comentário "H11a — hypothesis until probed", e porque eu cheguei a propor
    ao dono um `ubnt-systool info` que NÃO EXISTE (a lista de subcomandos do
    ubnt-systool não tem `info`). Comando sem fonte é chute com cara de fato.
    """
    from river_unifi_bridge.plugins.udr7_ssh import COMMANDS

    assert COMMANDS, "a tabela de comandos não pode ser vazia"
    for nome, cmd in COMMANDS.items():
        assert cmd.nome == nome
        assert cmd.argv.strip() == cmd.argv and cmd.argv, f"{nome}: argv malformado"
        assert isinstance(cmd.destrutivo, bool)
        assert len(cmd.fonte) >= 40, f"{nome}: fonte curta demais para ser verificável"
        for proibida in ("hypothesis", "hipótese", "TODO", "supõe", "acho que"):
            assert proibida.lower() not in cmd.fonte.lower(), (
                f"{nome}: a fonte contém '{proibida}' — não é fonte, é suposição")


def test_the_only_destructive_command_the_policy_fires_is_poweroff():
    """O que a política dispara é o desligamento, e nada mais.

    `reboot` está na tabela porque existe e o operador precisa saber que a
    escolha foi consciente — mas reiniciar numa queda gastaria bateria e
    devolveria o console ligado. Se alguém trocar o comando de disparo, esta
    cerca acusa.
    """
    from river_unifi_bridge.plugins.udr7_ssh import COMMANDS, POWEROFF, PROBE

    assert POWEROFF.argv == "ubnt-systool poweroff"
    assert POWEROFF.destrutivo is True
    assert PROBE.destrutivo is False
    destrutivos = {n for n, c in COMMANDS.items() if c.destrutivo}
    assert destrutivos == {"poweroff", "reboot"}


def test_policy_fires_the_command_the_plugin_declares(cfg, tmp_path):
    """O comando que vai no ssh vem da TABELA do plugin, não de um literal solto
    em protect.py. Prova: construir a política com outro comando muda o argv."""
    from river_unifi_bridge.protect import ProtectionConfig, ConfigHolder, ProtectionPolicy, ssh_argv
    from river_unifi_bridge.plugins.udr7_ssh import POWEROFF, Udr7SshPlugin

    plugin = Udr7SshPlugin.build(cfg, str(tmp_path))
    assert plugin._policy._shutdown_command == POWEROFF.argv

    holder = ConfigHolder(ProtectionConfig.from_cfg(cfg))
    outra = ProtectionPolicy(
        holder, known_hosts_path=str(tmp_path / "kh"),
        armed_path=str(tmp_path / "a.json"), runtime_path=str(tmp_path / "r.json"),
        shutdown_command="comando-de-teste",
    )
    assert outra._shutdown_command == "comando-de-teste"
    # e o transporte usa o que recebeu, sem reintroduzir o literal
    argv = ssh_argv(holder.get(), str(tmp_path / "kh"), outra._shutdown_command)
    assert argv[-1] == "comando-de-teste"
