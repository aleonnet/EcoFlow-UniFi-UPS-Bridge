"""Falar com o servidor NUT: ler, gravar e mandar comando.

Sem soquete de verdade: a conversa é injetada. O que estes testes protegem é o
contrato do protocolo e, principalmente, a REGRA da casa — gravação que não volta
na leitura seguinte não aconteceu, e recusa nunca chega à tela como sigla.
"""

from __future__ import annotations

import pytest

from river_unifi_bridge import river_cmd as rc

ALVO = rc.Alvo(ups="river-office", usuario="riverbridge", senha="segredo")


def conversa(respostas):
    """Um `fala` falso que devolve as respostas na ordem e guarda os comandos."""
    vistos = []

    def _fala(alvo, comandos, **_k):
        vistos.append((alvo.ups, list(comandos)))
        return [respostas.pop(0) for _ in comandos]

    _fala.vistos = vistos
    return _fala


def test_reading_a_variable():
    fala = conversa(['VAR river-office battery.charge.low "10"'])
    assert rc.ler_variavel(ALVO, "battery.charge.low", fala=fala) == "10"
    assert fala.vistos[0][1] == ["GET VAR river-office battery.charge.low"]


def test_a_variable_the_device_does_not_publish_is_none_not_zero():
    fala = conversa(["ERR VAR-NOT-SUPPORTED"])
    assert rc.ler_variavel(ALVO, "outlet.1.status", fala=fala) is None


def test_writing_checks_by_reading_back():
    """Gravação que não volta não aconteceu."""
    fala = conversa(["OK", 'VAR river-office battery.charge.low "15"'])
    rc.gravar_variavel(ALVO, "battery.charge.low", "15", fala=fala)
    assert fala.vistos[0][1] == ['SET VAR river-office battery.charge.low "15"']


def test_a_write_the_device_silently_ignores_is_reported():
    """O aparelho respondeu OK e continuou como estava: isso é falha, não sucesso."""
    fala = conversa(["OK", 'VAR river-office battery.charge.low "0"'])
    with pytest.raises(rc.RiverCmdError, match="continua com"):
        rc.gravar_variavel(ALVO, "battery.charge.low", "15", fala=fala)


def test_a_write_that_cannot_be_confirmed_fails_closed():
    """Não conseguir conferir não é ter conseguido gravar.

    O leitor pode cair entre a escrita e a leitura de volta. Antes desta cerca a
    tela dizia "salvo" com valor nenhum no aparelho (revisão fria da 0.5.0).
    """
    fala = conversa(["OK", "ERR DRIVER-NOT-CONNECTED"])
    with pytest.raises(rc.RiverCmdError, match="não confirmou"):
        rc.gravar_variavel(ALVO, "battery.charge.low", "15", fala=fala)


def test_a_refused_write_speaks_portuguese():
    fala = conversa(["ERR READONLY"])
    with pytest.raises(rc.RiverCmdError, match="somente leitura"):
        rc.gravar_variavel(ALVO, "battery.charge.low", "15", fala=fala)


def test_a_command_that_the_device_refuses_speaks_portuguese():
    fala = conversa(["ERR CMD-NOT-SUPPORTED"])
    with pytest.raises(rc.RiverCmdError, match="não aceita esse comando"):
        rc.mandar_comando(ALVO, "driver.killpower", fala=fala)


def test_an_unknown_refusal_never_shows_a_code_alone():
    fala = conversa(["ERR ALGO-NOVO"])
    with pytest.raises(rc.RiverCmdError, match="recusou"):
        rc.mandar_comando(ALVO, "driver.killpower", fala=fala)


def test_the_command_sent_is_the_one_asked():
    fala = conversa(["OK"])
    rc.mandar_comando(ALVO, "driver.killpower", fala=fala)
    assert fala.vistos[0][1] == ["INSTCMD river-office driver.killpower"]


def test_the_conversation_authenticates_before_anything(monkeypatch):
    """Conta e senha vão ANTES do comando; sem isso o servidor recusa em silêncio."""
    trocas = []

    class FakeArquivo:
        def __init__(self): self.saida = []
        def write(self, t): trocas.append(t.strip()); self.saida.append(t)
        def flush(self): pass
        def readline(self): return "OK\n"
        def __enter__(self): return self
        def __exit__(self, *a): return False

    class FakeSock:
        def settimeout(self, _t): pass
        def makefile(self, *_a, **_k): return FakeArquivo()
        def __enter__(self): return self
        def __exit__(self, *a): return False

    rc._fala(ALVO, ["GET VAR river-office battery.charge"],
             conectar=lambda *_a, **_k: FakeSock())
    assert trocas[0] == "USERNAME riverbridge"
    assert trocas[1] == "PASSWORD segredo"
    assert trocas[2].startswith("GET VAR")
    assert trocas[-1] == "LOGOUT"
