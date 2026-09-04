"""O serviço cuidando dos dois processos do NUT.

Nenhum teste sobe processo de verdade: o lançador é injetado. A cerca da casa
(tests/unit/conftest.py) já proíbe spawn, e aqui a razão é a mesma — subir um
driver de no-break de verdade numa máquina de teste é falar com o aparelho de
quem estiver rodando a suíte.
"""

from __future__ import annotations

import pytest

from river_unifi_bridge.nut_supervisor import (
    NOME_DRIVER, NOME_SERVIDOR, EstadoDoCabo, NutSupervisor,
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
    s = NutSupervisor("river-office", usuario="alessandro", prefixo=str(tmp_path),
                      spawn=spawn, clock=lambda: 0.0)
    s.lancados = lancados
    return s


def test_the_processes_are_born_with_our_own_name(sup):
    """O aplicativo da EcoFlow mata `usbhid-ups` e `upsd` pelo nome, como root.

    Com nome próprio, ele não nos alcança — e essa é a razão de existir do
    `exec -a` aqui, não estética.
    """
    sup.iniciar()
    assert len(sup.lancados) == 2
    comando_driver = sup.lancados[0].argv[-1]
    comando_servidor = sup.lancados[1].argv[-1]
    assert f"exec -a {NOME_DRIVER} " in comando_driver
    assert "usbhid-ups" in comando_driver and "'-a' 'river-office'" in comando_driver
    assert f"exec -a {NOME_SERVIDOR} " in comando_servidor
    assert "upsd" in comando_servidor
    assert sup.estado().lendo is True


def test_a_process_that_dies_comes_back_on_the_next_tick(sup):
    """Leitor que morre e não volta é pior que leitor que nunca subiu."""
    sup.iniciar()
    sup.lancados[0].morre(rc=1)
    assert sup.estado().lendo is False
    sup.vigiar()
    assert len(sup.lancados) == 3          # o driver foi relançado
    assert sup.estado().lendo is True


def test_pausing_frees_the_cable_and_does_not_resurrect(sup):
    """Pausado é pausado: o vigia não pode ressuscitar o que o dono liberou."""
    sup.iniciar()
    estado = sup.pausar("empréstimo ao aplicativo da EcoFlow")
    assert estado.pausado_pelo_dono and not estado.lendo
    assert all(p.terminado for p in sup.lancados)
    sup.vigiar()
    assert len(sup.lancados) == 2          # ninguém subiu de novo
    assert sup.estado().pausado_pelo_dono


def test_resuming_takes_the_cable_back(sup):
    sup.iniciar()
    sup.pausar()
    estado = sup.retomar()
    assert estado.lendo and not estado.pausado_pelo_dono
    assert len(sup.lancados) == 4          # driver e servidor de novo


def test_leaving_never_leaves_an_orphan_holding_the_cable(sup):
    sup.iniciar()
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
