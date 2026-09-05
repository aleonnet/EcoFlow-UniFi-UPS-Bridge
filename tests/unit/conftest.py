"""Unit-test fence (Fase 3'-EXP, M1): no test may spawn a process.

The protection module resolves its process seams at call time; here every one of
them is replaced by a function that fails loudly, the ssh/ssh-keygen paths point to
nowhere, and `subprocess.run` itself is blocked. A test that legitimately needs a
local process (only `ssh -G`, which never connects) opts out with the `spawn_ok`
marker — and even then the three module seams stay blocked.
"""

import subprocess

import pytest

from river_unifi_bridge import protect, river_serial, service


def _forbidden(*_args, **_kwargs):
    raise AssertionError("spawn proibido em teste (fixture anti-spawn de tests/unit)")


@pytest.fixture(autouse=True)
def _no_spawn(request, monkeypatch):
    monkeypatch.setattr(protect, "_RUNNER", _forbidden)
    monkeypatch.setattr(protect, "_KEYGEN_RUNNER", _forbidden)
    monkeypatch.setattr(protect, "_WOL_SENDER", _forbidden)
    monkeypatch.setattr(protect, "SSH_BINARY", "/nonexistent/river-test/ssh")
    monkeypatch.setattr(protect, "SSH_KEYGEN", "/nonexistent/river-test/ssh-keygen")
    if request.node.get_closest_marker("spawn_ok") is None:
        monkeypatch.setattr(subprocess, "run", _forbidden)
    yield


@pytest.fixture(autouse=True)
def _sem_porta_serial(monkeypatch):
    """Nenhum teste abre uma porta serial de verdade.

    A leitura do River percorre `/dev/cu.usbmodem*` da máquina que roda a suíte;
    sem esta cerca, o teste falava com o aparelho de quem estivesse rodando — e a
    memória de porta do módulo vazava de um teste para o outro.
    """
    def _proibido(*_a, **_k):
        raise AssertionError("porta serial proibida em teste (fixture de tests/unit)")

    monkeypatch.setattr(river_serial, "_conversa", _proibido)
    # E ninguém sobe o driver do no-break de verdade. Esta máquina TEM o NUT
    # instalado (medido: /opt/homebrew/opt/nut/bin/usbhid-ups existe), então sem
    # esta linha a suíte disputava o aparelho de quem a rodasse — e cada volta do
    # laço parava 2 s esperando um servidor que ela mesma tinha subido.
    class _SupervisorDeTeste:
        def __init__(self, *_a, **_k): self.acoes = []
        def iniciar(self): self.acoes.append("iniciar")
        def vigiar(self): self.acoes.append("vigiar")
        def encerrar(self): self.acoes.append("encerrar")
        def estado(self):
            from river_unifi_bridge.nut_supervisor import EstadoDoCabo
            return EstadoDoCabo(lendo=False, pausado_pelo_dono=False, motivo="teste")

    monkeypatch.setattr(service, "NutSupervisor", _SupervisorDeTeste)

    # E ninguém publica no NUT de verdade. A ponte cria soquetes em
    # /opt/homebrew/var/state/ups — a instalação REAL de quem roda a suíte —, e um
    # teste que subisse o laço deixaria lá um aparelho fantasma que o servidor do
    # dono passaria a servir. Quem testa a publicação é tests/unit/test_nut_servico.py,
    # com pasta própria.
    class _PonteDeTeste:
        def __init__(self, *_a, **_k): self.acoes = []
        def iniciar(self): self.acoes.append("iniciar")
        def atualizar(self, *_a, **_k): self.acoes.append("atualizar")
        def marcar_sem_dados(self): self.acoes.append("sem_dados")
        def encerrar(self): self.acoes.append("encerrar")

    monkeypatch.setattr(service, "PonteDoNut", _PonteDeTeste)
    monkeypatch.setattr(service, "_porta_serial_lembrada", None, raising=False)
    monkeypatch.setattr(service, "_ultima_varredura", float("-inf"), raising=False)
    monkeypatch.setattr(service, "_ultima_leitura_serial", None, raising=False)
    yield
