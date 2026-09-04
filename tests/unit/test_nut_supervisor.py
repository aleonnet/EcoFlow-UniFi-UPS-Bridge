"""O serviço cuidando dos dois processos do NUT.

Nenhum teste sobe processo de verdade: o lançador é injetado. A cerca da casa
(tests/unit/conftest.py) já proíbe spawn, e aqui a razão é a mesma — subir um
driver de no-break de verdade numa máquina de teste é falar com o aparelho de
quem estiver rodando a suíte.
"""

from __future__ import annotations

import pytest

from river_unifi_bridge.nut_supervisor import (
    NOME_DRIVER, NOME_SERVIDOR, RECUO_MAXIMO, EstadoDoCabo, NutSupervisor,
)


class FakeProc:
    def __init__(self, argv, **_kwargs):
        self.argv = argv
        self.pid = 4242
        self._rc: int | None = None
        self.terminado = False

    def poll(self):
        return self._rc

    def terminate(self):
        self.terminado = True
        self._rc = 0

    def kill(self):
        self._rc = -9

    def morre(self, rc: int = 1):
        self._rc = rc


@pytest.fixture
def sup(monkeypatch, tmp_path):
    (tmp_path / "bin").mkdir()
    (tmp_path / "bin" / "usbhid-ups").write_text("")
    lancados: list[FakeProc] = []

    def spawn(argv, **kwargs):
        p = FakeProc(argv, **kwargs)
        lancados.append(p)
        return p

    monkeypatch.setattr("river_unifi_bridge.nut_supervisor.time.sleep", lambda _s: None)
    relogio = {"agora": 0.0}
    s = NutSupervisor("river-office", usuario="alessandro", prefixo=str(tmp_path),
                      spawn=spawn, clock=lambda: relogio["agora"])
    s.lancados = lancados
    s.relogio = relogio
    return s


def _sobe_tudo(sup):
    """Duas voltas: o driver sobe na primeira, o servidor na segunda.

    O servidor precisa do soquete do driver, e esperar por ele DENTRO do laço
    atrasava a vigilância em 2 s por ciclo (revisão fria da 0.5.0). Agora a
    espera é uma volta do próprio laço.
    """
    sup.iniciar()
    sup.vigiar()


def test_the_processes_are_born_with_our_own_name(sup):
    """O aplicativo da EcoFlow mata `usbhid-ups` e `upsd` pelo nome, como root.

    Com nome próprio, ele não nos alcança — e essa é a razão de existir do
    `exec -a` aqui, não estética.
    """
    _sobe_tudo(sup)
    assert len(sup.lancados) == 2
    comando_driver = sup.lancados[0].argv[-1]
    comando_servidor = sup.lancados[1].argv[-1]
    assert f"exec -a {NOME_DRIVER} " in comando_driver
    assert "usbhid-ups" in comando_driver and "'-a' 'river-office'" in comando_driver
    assert f"exec -a {NOME_SERVIDOR} " in comando_servidor
    assert "upsd" in comando_servidor
    assert sup.estado().lendo is True


def test_a_process_that_dies_comes_back_after_the_backoff(sup):
    """Leitor que morre volta — mas com recuo, para não virar tempestade.

    Sem o recuo, um cabo solto fazia o serviço lançar dois processos a cada
    quatro segundos, sem teto (medido na máquina do dono: 173 em 5min44s).
    """
    _sobe_tudo(sup)
    sup.lancados[0].morre(rc=1)
    assert sup.estado().lendo is False
    sup.vigiar()                                   # marca a falha e recua
    assert len(sup.lancados) == 2                  # ninguém foi relançado ainda
    sup.relogio["agora"] += 60                     # passado o recuo
    sup.vigiar()
    assert len(sup.lancados) == 3                  # o driver voltou
    assert sup.estado().lendo is True


def test_pausing_frees_the_cable_and_does_not_resurrect(sup):
    """Pausado é pausado: o vigia não pode ressuscitar o que o dono liberou."""
    _sobe_tudo(sup)
    estado = sup.pausar("empréstimo ao aplicativo da EcoFlow")
    assert estado.pausado_pelo_dono and not estado.lendo
    assert all(p.terminado for p in sup.lancados)
    sup.vigiar()
    assert len(sup.lancados) == 2          # ninguém subiu de novo
    assert sup.estado().pausado_pelo_dono


def test_resuming_takes_the_cable_back(sup):
    _sobe_tudo(sup)
    sup.pausar()
    estado = sup.retomar()
    assert estado.lendo and not estado.pausado_pelo_dono
    assert len(sup.lancados) == 3          # o driver de novo (o servidor vem na volta seguinte)


def test_leaving_never_leaves_an_orphan_holding_the_cable(sup):
    _sobe_tudo(sup)
    sup.encerrar()
    assert all(p.terminado for p in sup.lancados)
    assert sup.estado().lendo is False


def test_without_nut_installed_it_says_so_instead_of_pretending(tmp_path):
    s = NutSupervisor("river-office", prefixo=str(tmp_path / "nao-existe"),
                      spawn=lambda *a, **k: pytest.fail("não podia lançar nada"))
    s.iniciar()
    estado = s.estado()
    assert estado.lendo is False
    assert "não está instalado" in (estado.motivo or "")


def test_the_state_that_goes_to_the_screen():
    e = EstadoDoCabo(lendo=False, pausado_pelo_dono=True, motivo="teste")
    assert e.to_dict() == {"lendo": False, "pausado": True, "motivo": "teste"}


def test_a_reader_that_never_comes_up_does_not_become_a_process_storm(sup):
    """Cabo solto: o leitor morre ao nascer. Isso não pode virar enxurrada.

    Medido na máquina do dono antes do recuo: 173 processos em 5min44s, porque
    cada volta do laço (4 s) lançava o par de novo. Com o recuo dobrando até o
    teto de 60 s, uma hora de cabo solto cabe em dezenas de tentativas.
    """
    sup.iniciar()
    for _ in range(200):                       # 200 voltas do laço, de 4 em 4 s
        for processo in sup.lancados:
            processo.morre(rc=1)               # nada consegue subir
        sup.vigiar()
        sup.relogio["agora"] += 4
    # 200 voltas × 4 s = 800 s de cabo solto. Sem recuo seriam 200 lançamentos.
    assert len(sup.lancados) <= 20
    # E não desiste: passado o recuo, tenta de novo.
    antes = len(sup.lancados)
    sup.relogio["agora"] += RECUO_MAXIMO + 1
    sup.vigiar()
    assert len(sup.lancados) == antes + 1


def test_a_server_that_never_survives_also_makes_the_backoff_grow(sup):
    """Quando quem cai é o SERVIDOR, o recuo tem de crescer igual.

    Medido na revisão fria da 0.5.0: o recuo zerava no LANÇAMENTO do servidor, e
    não na sobrevivência dele. Com outro servidor já na porta 3493, o nosso
    morria a cada volta, o contador voltava a zero e saíam 451 lançamentos por
    hora — sem recuo nenhum.
    """
    sup.iniciar()                                  # sobe o driver
    for _ in range(200):
        sup.vigiar()
        for processo in sup.lancados:              # o servidor nunca sobrevive
            if "upsd" in processo.argv[-1]:
                processo.morre(rc=1)
        sup.relogio["agora"] += 4
    assert len(sup.lancados) <= 20


def test_the_backoff_resets_only_after_the_pair_survives_a_whole_round(sup):
    """Sobreviveu a uma volta inteira: o recuo volta a zero, e a queda seguinte
    é tratada como a primeira."""
    _sobe_tudo(sup)
    sup.vigiar()                                   # volta inteira com os dois vivos
    sup.lancados[0].morre(rc=1)
    sup.vigiar()                                   # 1.ª falha depois do reset
    sup.relogio["agora"] += 4.1                    # o recuo da 1.ª falha é curto
    sup.vigiar()
    assert len(sup.lancados) == 3


def test_the_nut_seam_is_respected_by_the_daemon_too(monkeypatch, tmp_path):
    """O daemon obedece à MESMA costura do instalador para achar o NUT.

    Sem isto, uma cena do portão que sobe o serviço de verdade lançava o
    `usbhid-ups` REAL contra o River do dono e tomava o cabo dele — medido na
    2.ª rodada da revisão fria da 0.5.0, nos registros do daemon descartável.
    """
    monkeypatch.setenv("RUB_NUT_PREFIX", str(tmp_path / "nut-que-nao-existe"))
    lancados = []
    s = NutSupervisor("river-office", spawn=lambda *a, **k: lancados.append(a) or None)
    assert s.disponivel is False
    s.iniciar()
    assert lancados == []                          # nada foi lançado contra o aparelho real
