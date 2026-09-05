"""The device-plugin contract, exercised over EVERY registered plugin.

Parametrised over `TYPES + (FakePlugin,)`: this is what proves the contract is
general without a second real device. A test that only ever sees the UDR7 would
pass for a contract shaped exactly like the UDR7.
"""

from __future__ import annotations

from dataclasses import replace

import pytest

from fake_plugin import FakePlugin
from river_unifi_bridge.config import (
    _ALLOWLIST, DEVICE_NAME_KEYS, HOT_RELOAD_KEYS, LEGACY_CORE_KEYS, PROTECTION_KEYS, load_config,
)
from river_unifi_bridge.devices import DeviceInstance, DeviceStore
from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.plugins import TYPES, build_plugins, plugin_statuses
from river_unifi_bridge.plugins.udr7_ssh import legacy_instance

MINIMAL = "NUT_HOST=127.0.0.1\nNUT_PORT=3493\nNUT_UPS=river\nRIVER_NAME=River\n"
ALL_CLASSES = list(TYPES.values()) + [FakePlugin]


@pytest.fixture
def cfg(tmp_path):
    path = tmp_path / "bridge.env"
    path.write_text(MINIMAL, encoding="utf-8")
    return load_config(str(path))


def sample(cls) -> DeviceInstance:
    """Uma instância de teste do tipo, com os defaults dos campos."""
    return DeviceInstance(id=f"{cls.type_id}_teste", type=cls.type_id, name=cls.default_name,
                          fields={spec.name: spec.default for spec in cls.fields})


@pytest.mark.parametrize("cls", ALL_CLASSES)
def test_contract_attributes(cls):
    assert cls.type_id and cls.type_id == cls.type_id.lower()
    assert cls.label_pt and cls.label_en and cls.default_name and cls.event_prefix.endswith("_")
    assert cls.legacy_keys <= set(_ALLOWLIST), "legacy_keys fora da allowlist"
    # Everything a type owns in the .env must be frozen while armed, EXCEPT the
    # name: the whole point of DEVICE_NAME_KEYS is that renaming stays possible.
    assert cls.frozen_keys >= (cls.legacy_keys - DEVICE_NAME_KEYS)
    names = [spec.name for spec in cls.fields]
    assert len(set(names)) == len(names), "campo repetido no tipo"


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
    plugin = cls.build(sample(cls), cfg, str(tmp_path))
    assert plugin.id == f"{cls.type_id}_teste"
    assert isinstance(plugin.armed, bool)
    assert isinstance(plugin.observe(leitura, []), list)
    assert isinstance(plugin.observe_failure([]), list)
    st = plugin.status()
    assert "state" in st and "name" in st, "status() tem de trazer state e name"
    plugin.drain_transition()                       # não pode levantar
    # A key that belongs to NOBODY is never vetoed by this plugin.
    alheia = "HISTORY_RETENTION_DAYS"
    assert alheia not in (plugin.legacy_keys | plugin.frozen_keys)
    assert plugin.authorize({alheia: "7"}, None, False) is None
    assert plugin.authorize_update({"name": "Outro"}, None, False) is None
    assert isinstance(plugin.apply_patch(sample(cls)), list)


def test_udr7_frozen_keys_include_nut(cfg, tmp_path):
    """Só o UDR7: as chaves NUT_* condicionam a FONTE que alimenta a política."""
    plugin = TYPES["udr7_ssh"].build(legacy_instance(cfg), cfg, str(tmp_path))
    assert {"NUT_HOST", "NUT_PORT", "NUT_UPS"} <= plugin.frozen_keys


def test_registry_is_static_and_ids_unique():
    ids = list(TYPES)
    assert len(set(ids)) == len(ids)
    assert all(TYPES[type_id].type_id == type_id for type_id in TYPES)


def test_device_keys_are_partitioned_among_plugins():
    """Toda chave PROTECT_/UDR7_ da allowlist tem exatamente um dono.

    Compara o literal declarado em cada plugin com o conjunto montado por
    PREFIXO a partir da allowlist. Por isso o literal existe: derivá-lo por
    prefixo tornaria este teste uma tautologia. Cego a prefixo NOVO — quando o
    2º plugin chegar, a convenção PLUGIN_<ID>_* entra junto (BACKLOG).
    """
    por_prefixo = {k for k in _ALLOWLIST if k.startswith(("PROTECT_", "UDR7_"))}
    dos_plugins: set[str] = set()
    for cls in TYPES.values():
        assert not (dos_plugins & cls.legacy_keys), "dois tipos reivindicam a mesma chave"
        dos_plugins |= cls.legacy_keys
    # As três do núcleo (trava, série esperada, corte) não são de instância nenhuma.
    assert dos_plugins == por_prefixo - LEGACY_CORE_KEYS
    assert LEGACY_CORE_KEYS <= por_prefixo
    # Tipos novos NUNCA ganham chave no .env: só o UDR7 migrado tem espelho.
    assert [t for t, cls in TYPES.items() if cls.legacy_keys] == ["udr7_ssh"]


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
            outros |= outro.legacy_keys
    assert not (cls.frozen_keys & outros)


def test_udr7_name_is_hot_owned_and_never_frozen():
    udr7 = TYPES["udr7_ssh"]
    assert "UDR7_NAME" in udr7.legacy_keys
    assert "UDR7_NAME" in HOT_RELOAD_KEYS
    assert "UDR7_NAME" not in udr7.frozen_keys
    assert "UDR7_NAME" not in PROTECTION_KEYS


def test_udr7_status_name_falls_back_when_empty(cfg, tmp_path):
    from dataclasses import replace

    plugin = TYPES["udr7_ssh"].build(legacy_instance(cfg), cfg, str(tmp_path))
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


def test_build_plugins_builds_the_store(cfg, tmp_path):
    """Os plugins nascem da LOJA (uma instância por entrada), na ordem dela; a
    migração do .env põe o udr7 na posição 0."""
    store = DeviceStore(str(tmp_path / "devices.json"))
    devices = store.load_or_migrate(lambda: legacy_instance(cfg))
    plugins = build_plugins(devices, cfg, str(tmp_path))
    assert [p.id for p in plugins] == ["udr7"]
    entradas = plugin_statuses(plugins)
    assert entradas[0]["id"] == "udr7" and entradas[0]["type"] == "udr7_ssh"
    assert entradas[0]["name"] == "UDR7"
    assert plugins[0]._policy._known_hosts_path == str(tmp_path / "udr7_known_hosts")


def test_build_plugins_refuses_unknown_type(cfg, tmp_path):
    from river_unifi_bridge.devices import DevicesError
    with pytest.raises(DevicesError, match="tipo de dispositivo desconhecido"):
        build_plugins([DeviceInstance(id="x_1", type="nao_existe", name="X")], cfg, str(tmp_path))


def test_build_plugins_refuses_fields_edited_by_hand(cfg, tmp_path):
    """O arquivo de dispositivos editado à mão passa pela mesma conferência da tela.

    As rotas já validavam o que entra pela interface; o boot lia o arquivo cru e
    entregava ao motor um comando fora da tabela ou uma porta impossível.
    """
    from river_unifi_bridge.devices import DevicesError

    fora_da_tabela = DeviceInstance(
        id="ssh_1", type="ssh_host", name="Servidor",
        fields={"ssh_host": "192.0.2.9", "ssh_port": 22, "ssh_user": "root",
                "ssh_key": "/tmp/k", "shutdown_command": "rm -rf /"},
    )
    with pytest.raises(DevicesError, match="instância ssh_1"):
        build_plugins([fora_da_tabela], cfg, str(tmp_path))


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
        # A fonte declara o GRAU (docs/README.md): [P] primária ou [S] secundária.
        # Sem isso, wiki citada três vezes começa a parecer especificação.
        assert cmd.fonte.startswith(("[P]", "[S]")), (
            f"{nome}: a fonte não declara o grau — use [P] (origem/medição) ou [S] (wiki, blog)")


def test_secondary_sourced_commands_are_named_out_loud():
    """Um comando DESTRUTIVO com fonte apenas secundária é dívida, e tem nome.

    Hoje `ubnt-systool poweroff` é [S]: três fontes secundárias concordam, mas a
    porta 22 do console está fechada e ele nunca foi confirmado no aparelho. Esta
    cerca não proíbe — ela IMPEDE que o fato se perca: quando o comando for
    rodado no UDR7 e virar [P], a lista aqui embaixo tem de encolher junto.
    """
    from river_unifi_bridge.plugins.udr7_ssh import COMMANDS

    secundarios = {n for n, c in COMMANDS.items() if c.fonte.startswith("[S]")}
    assert secundarios == {"poweroff", "reboot"}, (
        "mudou o conjunto de comandos com fonte secundária — se um virou [P] "
        "porque foi medido no aparelho, atualize esta cerca e o runbook juntos")
    destrutivos_sem_primaria = {n for n in secundarios if COMMANDS[n].destrutivo}
    assert destrutivos_sem_primaria == {"poweroff", "reboot"}


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

    plugin = Udr7SshPlugin.build(legacy_instance(cfg), cfg, str(tmp_path))
    assert plugin._policy._shutdown_command == POWEROFF.argv
    assert plugin._holder.get().shutdown_command == POWEROFF.argv     # e está pinado

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


# --- o espelho legado (.env ↔ instância udr7) ----------------------------------------
def test_apply_instance_to_cfg_reports_shadowed_keys_and_never_writes_env(cfg, tmp_path):
    """No boot a loja vence: o cfg em memória recebe a instância, e as chaves em que
    o .env divergia são devolvidas (nomes, nunca valores). O .env não é tocado."""
    from river_unifi_bridge.plugins.udr7_ssh import apply_instance_to_cfg

    inst = legacy_instance(cfg)
    assert apply_instance_to_cfg(inst, cfg) == []          # recém-migrada: nada sombreado
    inst.fields["ssh_host"] = "192.0.2.7"
    inst.name = "Console da sala"
    inst.enabled = True
    shadowed = apply_instance_to_cfg(inst, cfg)
    assert sorted(shadowed) == ["PROTECT_UDR7", "UDR7_NAME", "UDR7_SSH_HOST"]
    assert (cfg.udr7_ssh_host, cfg.udr7_name, cfg.protect_udr7) == ("192.0.2.7", "Console da sala", True)


def test_legacy_put_translates_to_an_instance_patch():
    from river_unifi_bridge.plugins.udr7_ssh import legacy_changes_to_patch

    patch = legacy_changes_to_patch({"PROTECT_DRY_RUN": False, "UDR7_SSH_PORT": 2222,
                                     "UDR7_NAME": "X", "NUT_PORT": 3494})
    assert patch == {"dry_run": False, "name": "X", "fields": {"ssh_port": 2222}}
    assert legacy_changes_to_patch({"NUT_PORT": 3494}) == {}


# --- o tipo host SSH genérico ----------------------------------------------------------
def test_ssh_host_module_has_no_process_seam_of_its_own():
    """Todo spawn passa pelo ssh_argv + runner de protect.py (cerca anti-spawn e S4w).
    Um `subprocess`/`os.system`/`shell=` próprio no módulo do tipo abriria um segundo
    caminho, fora das cercas."""
    import ast
    import inspect
    from river_unifi_bridge.plugins import ssh_host

    tree = ast.parse(inspect.getsource(ssh_host))      # só CÓDIGO: docstrings não contam
    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            nomes = [a.name for a in node.names] + [getattr(node, "module", "") or ""]
            assert "subprocess" not in nomes, "import subprocess no tipo"
        if isinstance(node, ast.Call):
            assert not any(k.arg == "shell" for k in node.keywords), "shell= no tipo"
            if isinstance(node.func, ast.Attribute):
                assert node.func.attr not in ("system", "popen", "run", "Popen"), node.func.attr


def test_ssh_host_rejects_command_outside_allowlist(cfg, tmp_path):
    """Lista fechada nos dois portões: validate_fields (POST/PUT) e o build (loja editada
    à mão). Nó da cena S4r."""
    from river_unifi_bridge.devices import DevicesError, validate_fields
    from river_unifi_bridge.plugins.ssh_host import SHUTDOWN_COMMANDS, SshHostPlugin

    with pytest.raises(DevicesError, match="fora da lista permitida"):
        validate_fields(SshHostPlugin.fields, {"shutdown_command": "rm -rf / ; shutdown -h now"})
    inst = sample(SshHostPlugin)
    inst.fields["shutdown_command"] = "shutdown -h now; curl evil"
    with pytest.raises(DevicesError, match="fora da lista permitida"):
        SshHostPlugin.build(inst, cfg, str(tmp_path))
    for command, fonte in SHUTDOWN_COMMANDS.items():
        assert fonte.startswith("[P]") and len(fonte) >= 40, command
        inst.fields["shutdown_command"] = command
        plugin = SshHostPlugin.build(inst, cfg, str(tmp_path))
        assert plugin._holder.get().shutdown_command == command      # pinado
        assert plugin._policy._shutdown_command == command


def test_ssh_host_events_carry_type_prefix_and_owner(cfg, tmp_path):
    from river_unifi_bridge.plugins.ssh_host import SshHostPlugin
    from river_unifi_bridge.protect import EV_DRYRUN, EV_SENT, ProtectionAction

    inst = sample(SshHostPlugin)
    inst.name = "NAS da sala"
    plugin = SshHostPlugin.build(inst, cfg, str(tmp_path))
    tagged = plugin._tag([ProtectionAction(EV_DRYRUN, {}), ProtectionAction(EV_SENT, {"host": "h"})])
    assert [a.event for a in tagged] == ["SSH_HOST_SHUTDOWN_DRYRUN", "SSH_HOST_SHUTDOWN_SENT"]
    assert all(a.payload["device"] == inst.id and a.payload["device_name"] == "NAS da sala" for a in tagged)
    assert plugin._policy._known_hosts_path == str(tmp_path / f"{inst.id}_known_hosts")
    # O health também fala a língua do tipo: o last_event anotado pela política
    # (UDR7_*) sai renomeado — defeito visto no e2e em 2026-09-03.
    plugin._policy._note(EV_SENT)
    assert plugin.status()["last_event"] == "SSH_HOST_SHUTDOWN_SENT"


def test_udr7_events_keep_their_prefix(cfg, tmp_path):
    from river_unifi_bridge.protect import EV_ARMED, ProtectionAction

    plugin = TYPES["udr7_ssh"].build(legacy_instance(cfg), cfg, str(tmp_path))
    tagged = plugin._tag([ProtectionAction(EV_ARMED, {})])
    assert tagged[0].event == "UDR7_ARMED" and tagged[0].payload["device"] == "udr7"


def test_type_catalog_lists_every_type_with_its_fields():
    from river_unifi_bridge.plugins import type_catalog

    catalog = type_catalog()
    assert [t["id"] for t in catalog] == ["udr7_ssh", "ssh_host"]
    by_id = {t["id"]: t for t in catalog}
    assert "wol_mac" in [f["name"] for f in by_id["udr7_ssh"]["fields"]]
    cmd = next(f for f in by_id["ssh_host"]["fields"] if f["name"] == "shutdown_command")
    assert cmd["enum"] and cmd["default"] == "shutdown -h now"
    # série esperada e corte NÃO são campos de instância de tipo nenhum (D16)
    for t in catalog:
        assert not {"expected_serial", "cutoff_percent"} & {f["name"] for f in t["fields"]}


def test_the_installed_key_survives_saving_and_arming(tmp_path, cfg):
    """A chave que o serviço instalou tem de continuar valendo depois de salvar.

    Defeito medido pela revisão fria da 0.6.0: a chave gerida entrava só na
    partida. Qualquer salvamento (ou mudança do núcleo) remontava a configuração
    a partir dos campos digitados — onde o caminho está vazio, porque no fluxo da
    tela o dono não digita caminho nenhum. A proteção armava e ficava em
    "configuração incompleta": numa queda de energia, nada seria enviado.
    """
    from river_unifi_bridge.plugins import Udr7SshPlugin
    from river_unifi_bridge.plugins.udr7_ssh import legacy_instance

    estado = tmp_path / "state"
    estado.mkdir()
    instancia = legacy_instance(cfg)
    chave = estado / f"{instancia.id}_key"
    chave.write_text("PRIVADA")
    chave.chmod(0o600)

    plugin = Udr7SshPlugin.build(instancia, cfg, str(estado))
    assert plugin._holder.get().udr7_ssh_key == str(chave)

    # o mesmo caminho de um salvamento pela tela e de uma mudança do núcleo
    plugin.apply_patch(replace(instancia, name="UDR7 da sala"))
    assert plugin._holder.get().udr7_ssh_key == str(chave), "a chave se perdeu ao salvar"
    plugin.on_config_applied(cfg)
    assert plugin._holder.get().udr7_ssh_key == str(chave), "a chave se perdeu com o núcleo"
