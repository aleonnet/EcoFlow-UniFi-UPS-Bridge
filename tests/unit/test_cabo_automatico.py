"""O cabo indo e voltando sozinho — e as duas vezes em que ele NÃO vai.

Nenhum teste procura processo de verdade: quem responde "o aplicativo está
aberto?" é injetado. A cerca anti-spawn da casa já proíbe o contrário.
"""

from __future__ import annotations

import re

from river_unifi_bridge.cabo_automatico import (
    APLICATIVO_DO_FABRICANTE, EV_LARGADO, EV_MANTIDO, EV_RETOMADO, CaboAutomatico)
from river_unifi_bridge.nut_supervisor import EstadoDoCabo

# As linhas de comando MEDIDAS no Mac mini em 2026-09-05, com a interface aberta.
_DAEMON_DELES = ("/Applications/PowerManager.app/Contents/MacOS/PowerManager_1.0.0.16.app"
                 "/Contents/PowerManagerService/PowerManagerService")
_INTERFACE_DELES = ("/Applications/PowerManager.app/Contents/MacOS/PowerManager_1.0.0.16.app"
                    "/Contents/MacOS/PowerManager")
_LANCADOR_DELES = "/Applications/PowerManager.app/Contents/MacOS/PowerManager"


def test_o_daemon_deles_nao_e_o_aplicativo():
    """O padrão casa a INTERFACE e não casa o daemon que roda sempre.

    `pgrep -f` lê o padrão como expressão regular sobre a linha de comando
    inteira — o que `re.search` reproduz aqui. As duas versões anteriores do
    padrão casavam o daemon, e o cabo era largado para sempre.
    """
    assert re.search(APLICATIVO_DO_FABRICANTE, _INTERFACE_DELES)
    assert re.search(APLICATIVO_DO_FABRICANTE, _LANCADOR_DELES)
    assert not re.search(APLICATIVO_DO_FABRICANTE, _DAEMON_DELES), \
        "o padrão casa o daemon permanente da EcoFlow: o cabo seria largado para sempre"


class SupervisorFalso:
    def __init__(self, *, pausado_pelo_dono=False):
        self.acoes: list[str] = []
        self.pausado_pelo_dono = pausado_pelo_dono
        # Quantas vezes o leitor morreu por conta própria (o `pkill` deles).
        self.quedas_do_driver = 0

    def leitor_morto_pelo_aplicativo_deles(self):
        self.quedas_do_driver += 1

    def estado(self):
        return EstadoDoCabo(lendo=not self.pausado_pelo_dono,
                            pausado_pelo_dono=self.pausado_pelo_dono)

    def pausar(self, motivo=""):
        self.acoes.append(f"pausar:{motivo}")
        return EstadoDoCabo(lendo=False, pausado_pelo_dono=True, motivo=motivo)

    def retomar(self):
        self.acoes.append("retomar")
        return EstadoDoCabo(lendo=True, pausado_pelo_dono=False)


def montar(*, aberto=False, armada=False, supervisor=None):
    estado = {"aberto": aberto, "armada": armada, "agora": 0.0}
    avisos: list[tuple[str, str]] = []
    sup = supervisor or SupervisorFalso()
    cabo = CaboAutomatico(
        sup,
        procurar=lambda _p: estado["aberto"],
        ha_protecao_armada=lambda: estado["armada"],
        avisar=lambda evento, detalhe: avisos.append((evento, detalhe)),
        clock=lambda: estado["agora"],
    )
    return cabo, sup, estado, avisos


def test_the_cable_goes_over_when_the_vendor_app_takes_it():
    """Sem botão nenhum: o aplicativo abriu em modo Local, matou o leitor
    (`pkill -9 usbhid-ups`, lido no pacote dele), o cabo passa."""
    cabo, sup, estado, avisos = montar()
    cabo.vigiar()
    assert sup.acoes == []                       # ninguém aberto, nada acontece
    estado["aberto"] = True
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes == [], "abriu mas ainda não tomou o cabo: nada a ceder"
    sup.leitor_morto_pelo_aplicativo_deles()
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes == ["pausar:o aplicativo da EcoFlow tomou o cabo"]
    assert avisos[0][0] == EV_LARGADO


def test_o_cabo_fica_quando_o_aplicativo_nao_o_pede():
    """Modo Remoto (medido no Mac mini, 2026-09-06: 120 s aberto, leitor de pé):
    o aplicativo abriu e fechou sem tocar no leitor. O cabo fica, os dois leem,
    e a linha do tempo não ganha evento nenhum — não há o que avisar."""
    cabo, sup, estado, avisos = montar(aberto=True)
    for _ in range(6):
        estado["agora"] += 10
        cabo.vigiar()
    assert sup.acoes == []
    estado["aberto"] = False
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes == [] and avisos == []


def test_uma_queda_entre_duas_olhadas_ainda_conta_como_pedido():
    """O `pkill` deles pode vir antes de o aplicativo ser visto aberto: a
    referência é a olhada ANTERIOR, e a queda entre as duas ainda é dele."""
    cabo, sup, estado, avisos = montar()
    cabo.vigiar()                                 # olhada 1: fechado, 0 quedas
    sup.leitor_morto_pelo_aplicativo_deles()      # o pkill deles
    estado["aberto"] = True
    estado["agora"] += 10
    cabo.vigiar()                                 # olhada 2: aberto, 1 queda
    assert sup.acoes == ["pausar:o aplicativo da EcoFlow tomou o cabo"]


def test_uma_queda_antiga_nao_e_pedido():
    """O leitor caiu ontem por outro motivo e voltou; hoje o aplicativo abre em
    modo Remoto. A queda antiga não pode contar como pedido de cabo."""
    cabo, sup, estado, _avisos = montar()
    sup.leitor_morto_pelo_aplicativo_deles()
    cabo.vigiar()                                 # fechado; a queda fica para trás
    estado["aberto"] = True
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes == []


def test_the_cable_comes_back_when_the_vendor_app_closes():
    """Fechou, travou ou morreu: o serviço volta a vigiar sozinho."""
    cabo, sup, estado, avisos = montar(aberto=True)
    cabo.vigiar()
    sup.leitor_morto_pelo_aplicativo_deles()
    estado["agora"] += 10
    cabo.vigiar()
    estado["aberto"] = False
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes[-1] == "retomar"
    assert [e for e, _ in avisos] == [EV_LARGADO, EV_RETOMADO]


def test_the_cable_is_never_handed_over_while_a_protection_is_armed():
    """Largar o cabo com proteção armada é ficar cego para a queda de energia
    justamente com o desligamento automático ligado."""
    cabo, sup, estado, avisos = montar(aberto=True, armada=True)
    cabo.vigiar()
    sup.leitor_morto_pelo_aplicativo_deles()      # ele pediu o cabo
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes == []
    assert avisos[0][0] == EV_MANTIDO
    assert "proteção armada" in avisos[0][1]


def test_com_protecao_armada_e_o_aplicativo_em_remoto_nao_ha_aviso_nenhum():
    """Em Remoto ele não pede o cabo; o aviso "mantive o cabo" seria mentira
    (bloqueador da revisão fria da 0.8.5)."""
    cabo, sup, estado, avisos = montar(aberto=True, armada=True)
    for _ in range(4):
        estado["agora"] += 10
        cabo.vigiar()
    assert sup.acoes == [] and avisos == []


def test_the_refusal_is_said_once_per_opening_not_every_five_seconds():
    """O aviso é para o dono ler, não para encher a linha do tempo."""
    cabo, sup, estado, avisos = montar(aberto=True, armada=True)
    cabo.vigiar()
    sup.leitor_morto_pelo_aplicativo_deles()
    for _ in range(5):
        estado["agora"] += 10
        cabo.vigiar()
    assert [e for e, _ in avisos] == [EV_MANTIDO]


def test_after_disarming_the_cable_finally_goes_over():
    cabo, sup, estado, avisos = montar(aberto=True, armada=True)
    cabo.vigiar()
    sup.leitor_morto_pelo_aplicativo_deles()      # ele pediu o cabo
    estado["agora"] += 10
    cabo.vigiar()                                 # armada: mantém e avisa
    estado["armada"] = False
    estado["agora"] += 10
    cabo.vigiar()                                 # desarmou: agora cede
    assert sup.acoes == ["pausar:o aplicativo da EcoFlow tomou o cabo"]
    assert [e for e, _ in avisos] == [EV_MANTIDO, EV_LARGADO]


def test_what_the_owner_lent_by_hand_is_not_taken_back_by_us():
    """Se o dono emprestou o cabo pela tela, ele volta pela tela.

    O automático desfazendo a escolha dele seria o programa discutindo com o
    dono — e ele descobriria isso no meio de usar o aplicativo do fabricante.
    """
    sup = SupervisorFalso(pausado_pelo_dono=True)
    cabo, _sup, estado, avisos = montar(aberto=True, supervisor=sup)
    cabo.vigiar()
    sup.leitor_morto_pelo_aplicativo_deles()
    estado["agora"] += 10
    cabo.vigiar()
    estado["aberto"] = False
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes == [], "mexemos num empréstimo que não era nosso"
    assert avisos == []


def test_looking_for_the_app_is_not_done_on_every_lap():
    """Cada olhada é um processo novo; a cada 2 s isso seria 1.800 por hora."""
    olhadas = []
    estado = {"agora": 0.0}
    cabo = CaboAutomatico(SupervisorFalso(),
                          procurar=lambda _p: olhadas.append(1) or False,
                          clock=lambda: estado["agora"])
    for _ in range(10):
        cabo.vigiar()
        estado["agora"] += 1            # dez voltas de um segundo
    # Dez voltas cobrindo 10 s: duas olhadas (a do início e a dos 5 s).
    assert len(olhadas) == 2, f"olhou {len(olhadas)} vezes em 10 s"


def test_a_search_that_blows_up_brings_the_cable_back_instead_of_keeping_it():
    """Falhar ao procurar responde "não achei" — e não achar é RETOMAR.

    É o lado seguro: na dúvida, o serviço volta a vigiar a energia.
    """
    cabo, sup, estado, _avisos = montar(aberto=True)
    cabo.vigiar()
    sup.leitor_morto_pelo_aplicativo_deles()
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes[-1].startswith("pausar")
    cabo._procurar = lambda _p: False    # como se a busca tivesse falhado
    estado["agora"] += 10
    cabo.vigiar()
    assert sup.acoes[-1] == "retomar"
