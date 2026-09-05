"""As ordens que chegam pelo NUT passam pelas MESMAS cercas da tela.

É a regra que este arquivo inteiro existe para garantir: o Home Assistant é mais
um cliente, não um caminho paralelo em que as travas do dono não valem.
"""

from __future__ import annotations

import pytest

from river_unifi_bridge.config import BridgeConfig
from river_unifi_bridge.nut_comandos import (
    DESLIGAR, REINICIAR, ExecutorDeComandos, comandos_do_dispositivo, comandos_do_river)
from river_unifi_bridge.nut_driver import (
    CMD_DESCONHECIDO, CMD_FALHOU, CMD_FEITO, CMD_INVALIDO)

APARELHO = "river-bridge"


def cfg(**over):
    base = dict(river_name="r", nut_host="127.0.0.1", nut_port=3493, nut_ups="river-office")
    base.update(over)
    return BridgeConfig(**base)


class PluginFalso:
    def __init__(self, identificador="udr7", *, armado=False, acoes=None, erro=""):
        self.id = identificador
        self.armed = armado
        self._acoes = acoes if acoes is not None else {
            "desligar": "ubnt-systool poweroff", "reiniciar": "ubnt-systool reboot"}
        self._erro = erro
        self.feitas: list[str] = []

    def acoes_manuais(self):
        return dict(self._acoes)

    def executar_acao(self, acao, **_kw):
        self.feitas.append(acao)
        return self._erro


def executor(**kw):
    linha: list[tuple[str, str]] = []
    kw.setdefault("cfg", cfg(device_cmd_allowed=True))
    padrao = dict(aparelho_do_river=APARELHO, plugins=(),
                  registrar=lambda evento, detalhe: linha.append((evento, detalhe)),
                  desligar_river=lambda: None,
                  executar_no_dispositivo=lambda plugin, acao: plugin.executar_acao(acao))
    configuracao = kw.pop("cfg", cfg())
    padrao.update(kw)
    exe = ExecutorDeComandos(configuracao, **padrao)
    exe.linha = linha
    return exe


# -- que nomes são anunciados ---------------------------------------------------

def test_the_river_offers_no_shutdown_while_the_file_lock_is_shut():
    """Melhor não oferecer a ordem do que oferecê-la e recusar sempre.

    A trava só muda com reinício do serviço, então o anúncio não fica oscilando
    na tela do Home Assistant.
    """
    assert comandos_do_river(cfg(river_poweroff_allowed=False)) == ()
    assert comandos_do_river(cfg(river_poweroff_allowed=True)) == (DESLIGAR,)


def test_only_what_the_type_knows_how_to_do_is_announced():
    """O console UniFi sabe desligar e reiniciar; um host genérico só desliga."""
    aberta = cfg(device_cmd_allowed=True)
    assert set(comandos_do_dispositivo(PluginFalso(), aberta)) == {DESLIGAR, REINICIAR}
    so_desliga = PluginFalso(acoes={"desligar": "shutdown -h now"})
    assert comandos_do_dispositivo(so_desliga, aberta) == (DESLIGAR,)


def test_a_device_offers_no_order_while_the_file_lock_is_shut():
    """Terceira trava de arquivo da casa, pelo mesmo motivo das outras duas.

    Desligar um roteador de produção é ato destrutivo, e todo ato destrutivo aqui
    tem uma trava que só o arquivo abre. Antes desta, mandar num roteador à mão
    era o ÚNICO ato destrutivo do sistema sem trava — a diferença que a revisão
    fria da 0.7.0 apontou.
    """
    assert comandos_do_dispositivo(PluginFalso(), cfg(device_cmd_allowed=False)) == ()


def test_the_lock_is_checked_again_when_the_order_arrives():
    """Anunciar de menos é cortesia; recusar é a cerca.

    Quem fala com o soquete não é obrigado a perguntar o que existe antes de
    mandar — a trava tem de valer também para quem manda direto.
    """
    plugin = PluginFalso()
    exe = executor(cfg=cfg(device_cmd_allowed=False), plugins=[plugin])
    assert exe("udr7", DESLIGAR) == CMD_INVALIDO
    assert plugin.feitas == []
    assert exe.linha[0][0] == "UDR7_ORDEM_RECUSADA"


def test_the_names_are_the_ones_home_assistant_understands():
    """Nome inventado é aceito pelo NUT e INVISÍVEL no Home Assistant.

    A lista de comandos que ele entende é fechada (medido no código dele em
    2026-09-05); estes dois estão nela.
    """
    assert DESLIGAR == "load.off" and REINICIAR == "shutdown.reboot"


# -- desligar o River -----------------------------------------------------------

def test_the_river_is_not_turned_off_with_the_file_lock_shut():
    """A trava de arquivo é a mesma da tela: nem a API nem o NUT a abrem."""
    desligou = []
    exe = executor(cfg=cfg(river_poweroff_allowed=False, device_cmd_allowed=True),
                   desligar_river=lambda: desligou.append(1))
    assert exe(APARELHO, DESLIGAR) == CMD_INVALIDO
    assert desligou == []
    assert exe.linha[0][0] == "RIVER_DESLIGAR_RECUSADO"


def test_the_river_is_not_turned_off_while_a_protection_is_armed():
    """Duas ordens de desligamento ao mesmo tempo — a automática e a do dono."""
    desligou = []
    exe = executor(cfg=cfg(river_poweroff_allowed=True, device_cmd_allowed=True),
                   plugins=[PluginFalso(armado=True)],
                   desligar_river=lambda: desligou.append(1))
    assert exe(APARELHO, DESLIGAR) == CMD_INVALIDO
    assert desligou == []


def test_with_both_locks_open_the_river_is_turned_off_and_it_goes_to_the_timeline():
    """Ordem destrutiva não pode existir só no registro do sistema.

    Quem manda pelo Home Assistant não vê aquele registro; quem abre o app depois
    precisa achar ali o que aconteceu com o aparelho dele.
    """
    desligou = []
    exe = executor(cfg=cfg(river_poweroff_allowed=True, device_cmd_allowed=True),
                   desligar_river=lambda: desligou.append(1))
    assert exe(APARELHO, DESLIGAR) == CMD_FEITO
    assert desligou == [1]
    assert [e for e, _ in exe.linha] == ["RIVER_DESLIGANDO"]


def test_a_shutdown_that_fails_says_so_instead_of_reporting_success():
    def estoura():
        raise RuntimeError("o servidor do no-break recusou o pedido")

    exe = executor(cfg=cfg(river_poweroff_allowed=True, device_cmd_allowed=True), desligar_river=estoura)
    assert exe(APARELHO, DESLIGAR) == CMD_FALHOU
    assert "RIVER_DESLIGAR_FALHOU" in [e for e, _ in exe.linha]


def test_an_unknown_command_on_the_river_is_refused():
    exe = executor(cfg=cfg(river_poweroff_allowed=True, device_cmd_allowed=True))
    assert exe(APARELHO, "test.battery.start") == CMD_DESCONHECIDO


# -- os dispositivos protegidos -------------------------------------------------

def test_a_device_is_turned_off_through_the_same_path_the_protection_uses():
    plugin = PluginFalso()
    exe = executor(plugins=[plugin])
    assert exe("udr7", DESLIGAR) == CMD_FEITO
    assert plugin.feitas == ["desligar"]
    assert [e for e, _ in exe.linha] == ["UDR7_ORDEM_ENVIADA"]


def test_a_device_can_be_rebooted_when_its_type_knows_how():
    plugin = PluginFalso()
    exe = executor(plugins=[plugin])
    assert exe("udr7", REINICIAR) == CMD_FEITO
    assert plugin.feitas == ["reiniciar"]


def test_a_type_that_cannot_reboot_refuses_instead_of_shutting_down():
    """Trocar uma ordem por outra num roteador de produção é o pior desfecho."""
    plugin = PluginFalso(acoes={"desligar": "shutdown -h now"})
    exe = executor(plugins=[plugin])
    assert exe("udr7", REINICIAR) == CMD_DESCONHECIDO
    assert plugin.feitas == []


def test_an_order_to_a_device_nobody_registered_goes_nowhere():
    exe = executor(plugins=[PluginFalso("udr7")])
    assert exe("outro", DESLIGAR) == CMD_DESCONHECIDO


def test_a_device_that_refuses_the_order_reports_the_reason():
    plugin = PluginFalso(erro="ainda não foi provado que este serviço alcança o aparelho")
    exe = executor(plugins=[plugin])
    assert exe("udr7", DESLIGAR) == CMD_FALHOU
    evento, detalhe = exe.linha[0]
    assert evento == "UDR7_ORDEM_FALHOU" and "alcança" in detalhe


# -- a cerca que vive no próprio dispositivo ------------------------------------

def test_a_device_without_proven_reach_never_spawns_an_ssh(tmp_path, monkeypatch):
    """A única cerca da ordem manual, e é a que importa.

    Provar alcance por outro caminho não diria nada sobre este — e é este que
    corta a energia do aparelho de alguém.
    """
    from river_unifi_bridge.plugins.udr7_ssh import Udr7SshPlugin
    from river_unifi_bridge.devices import DeviceInstance

    instancia = DeviceInstance(id="udr7", type="udr7_ssh", name="UDR7", enabled=False,
                               dry_run=True, fields={"ssh_host": "192.168.1.1"})
    plugin = Udr7SshPlugin.build(instancia, cfg(), str(tmp_path))

    def nunca(*_a, **_k):
        raise AssertionError("não pode abrir ssh sem alcance provado")

    assert "alcança" in plugin.executar_acao("desligar", runner=nunca)


def test_an_action_the_type_does_not_have_is_refused_by_name(tmp_path):
    from river_unifi_bridge.plugins.ssh_host import SshHostPlugin
    from river_unifi_bridge.devices import DeviceInstance

    instancia = DeviceInstance(id="mini", type="ssh_host", name="Mac mini", enabled=False,
                               dry_run=True, fields={"ssh_host": "192.168.1.9"})
    plugin = SshHostPlugin.build(instancia, cfg(), str(tmp_path))
    assert "não sabe reiniciar" in plugin.executar_acao("reiniciar")
