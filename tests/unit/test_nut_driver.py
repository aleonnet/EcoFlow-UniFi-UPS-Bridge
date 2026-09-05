"""Nós como driver do NUT: o soquete, o protocolo e o que sai nele.

Nenhum teste sobe processo: o soquete é criado numa pasta temporária e quem faz
o papel do servidor do no-break é o próprio teste. O protocolo testado aqui é o
de `docs/sock-protocol.txt` do projeto NUT, e cada expectativa abaixo existe
porque o outro lado — o `upsd` de verdade — desliga o driver quando ela falha.
"""

from __future__ import annotations

import os
import shutil
import socket
import stat
import tempfile
import threading
import time

import pytest

from river_unifi_bridge import nut_driver as nd


@pytest.fixture
def pasta_curta():
    """Um diretório curto para o soquete.

    O `tmp_path` do pytest é fundo demais: o caminho de um soquete Unix cabe em
    104 bytes no macOS, e o caminho de teste padrão estoura isso — o mesmo limite
    que o serviço confere antes de tentar criar o arquivo.
    """
    caminho = tempfile.mkdtemp(prefix="rb", dir="/tmp")
    try:
        yield caminho
    finally:
        shutil.rmtree(caminho, ignore_errors=True)


# -- o enquadramento -----------------------------------------------------------

def test_a_value_with_spaces_survives_the_trip():
    """Aspas mantêm o valor inteiro — sem elas, "OB LB" viraria dois argumentos."""
    linha = f'SETINFO ups.status "{nd.codifica("OB LB")}"'
    assert nd.divide_linha(linha) == ["SETINFO", "ups.status", "OB LB"]


def test_a_value_with_a_quote_does_not_split_the_line():
    """Uma aspa dentro do valor partiria a linha e o servidor guardaria metade.

    O `pconf_encode` do NUT existe para isto, e nós o reproduzimos.
    """
    sujo = 'Sala "A" \\ fundos'
    linha = f'SETINFO device.description "{nd.codifica(sujo)}"'
    assert nd.divide_linha(linha) == ["SETINFO", "device.description", sujo]


def test_the_socket_name_is_the_one_the_server_looks_for():
    """O servidor monta `<driver>-<aparelho>` a partir do ups.conf (server/conf.c).

    Errar este nome é o driver existir e o servidor nunca o encontrar.
    """
    assert nd.caminho_do_soquete("river", "/x/state") == "/x/state/river-bridge-river"


# -- o soquete ----------------------------------------------------------------

class Servidor:
    """Faz o papel do `upsd`: conecta, manda linhas e lê o que vem."""

    def __init__(self, caminho: str) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(caminho)
        self._resto = b""

    def manda(self, linha: str) -> None:
        self.sock.sendall((linha + "\n").encode())

    def linha(self, tempo: float = 3.0) -> str:
        limite = time.monotonic() + tempo
        while b"\n" not in self._resto:
            if time.monotonic() > limite:
                raise AssertionError(f"o driver não respondeu (buffer: {self._resto!r})")
            self.sock.settimeout(0.3)
            try:
                pedaco = self.sock.recv(4096)
            except socket.timeout:
                continue
            if not pedaco:
                raise AssertionError("o driver fechou a conexão")
            self._resto += pedaco
        bruta, _, resto = self._resto.partition(b"\n")
        self._resto = resto
        return bruta.decode()

    def espera(self, prefixo: str, tempo: float = 3.0) -> str:
        """Lê até achar a linha procurada.

        O driver fala sozinho (é o desenho do protocolo: "The drivers may send
        things on the socket at any time"), então esperar por posição seria
        esperar por sorte.
        """
        limite = time.monotonic() + tempo
        vistas = []
        while time.monotonic() < limite:
            linha = self.linha(tempo)
            vistas.append(linha)
            if linha.startswith(prefixo):
                return linha
        raise AssertionError(f"não veio {prefixo!r}; vieram {vistas!r}")

    def liga(self) -> "Servidor":
        """O primeiro ato do servidor de verdade é sempre um `DUMPALL`."""
        self.manda("DUMPALL")
        self.ate("DUMPDONE")
        return self

    def ate(self, marca: str, tempo: float = 3.0) -> list[str]:
        linhas = []
        while True:
            linha = self.linha(tempo)
            linhas.append(linha)
            if linha == marca:
                return linhas

    def fecha(self) -> None:
        self.sock.close()


@pytest.fixture
def driver(pasta_curta):
    d = nd.DriverDoNut(os.path.join(pasta_curta, "river-bridge-river"))
    d.iniciar()
    yield d
    d.encerrar()


def test_only_who_runs_the_service_can_send_an_order_through_the_socket(pasta_curta):
    """0600 — mais estrito que o 0660 dos drivers de fábrica, de propósito.

    A documentação do NUT é literal: "There are no access controls in the
    drivers. Anything that can connect to their sockets can make requests,
    including SET and INSTCMD … These sockets must be kept secure."

    E a pasta em que eles vivem nesta máquina é 0755 com grupo `admin` (medido em
    2026-09-05): com 0660, qualquer conta administradora mandaria desligar o
    River sem ficha, sem senha e sem rastro de quem foi — enquanto a mesma ordem
    pela tela exige uma ficha de arquivo 0600. Era a maior diferença de trava
    entre os dois caminhos (revisão fria da 0.7.0).
    """
    caminho = os.path.join(pasta_curta, "river-bridge-river")
    d = nd.DriverDoNut(caminho)
    d.iniciar()
    try:
        modo = stat.S_IMODE(os.stat(caminho).st_mode)
        assert modo == 0o600, f"modo {oct(modo)}"
        assert stat.S_ISSOCK(os.stat(caminho).st_mode)
    finally:
        d.encerrar()
    assert not os.path.exists(caminho), "o soquete tem de sumir quando o serviço sai"


def test_a_leftover_socket_from_a_crash_does_not_block_the_start(pasta_curta):
    """Um serviço que morreu deixa o arquivo para trás; o NUT desfaz isso com
    `unlink` antes do `bind`, e sem ele o driver nunca mais subiria."""
    caminho = os.path.join(pasta_curta, "river-bridge-river")
    open(caminho, "w").close()
    d = nd.DriverDoNut(caminho)
    d.iniciar()
    try:
        assert stat.S_ISSOCK(os.stat(caminho).st_mode)
    finally:
        d.encerrar()


def test_the_server_gets_everything_it_asked_for_in_a_dump(driver):
    """`DUMPALL` responde variáveis, comandos e o fim — nessa ordem.

    É o contrato do `sock_arg` do NUT: sem o `DUMPDONE`, o servidor fica
    esperando para sempre e nunca serve o primeiro cliente.
    """
    driver.publicar({"ups.status": "OL", "battery.charge": "88"},
                    comandos=["load.off"], dados_ok=True)
    servidor = Servidor(driver.caminho)
    try:
        servidor.manda("DUMPALL")
        linhas = servidor.ate("DUMPDONE")
    finally:
        servidor.fecha()
    assert 'SETINFO ups.status "OL"' in linhas
    assert 'SETINFO battery.charge "88"' in linhas
    assert "ADDCMD load.off" in linhas
    assert linhas[-2:] == ["DATAOK", "DUMPDONE"]


def test_stale_data_is_announced_before_the_dump(driver):
    """Dados velhos são avisados ANTES, para o servidor não os repassar como bons."""
    driver.publicar({"ups.status": "OL"}, dados_ok=False)
    servidor = Servidor(driver.caminho)
    try:
        servidor.manda("DUMPALL")
        linhas = servidor.ate("DUMPDONE")
    finally:
        servidor.fecha()
    assert linhas[0] == "DATASTALE"
    assert "DATAOK" not in linhas


def test_a_ping_is_answered(driver):
    """Sem o `PONG`, o servidor conclui em segundos que o driver morreu.

    "If a driver does not respond with the PONG within a few seconds at the
    most, it should be treated as dead/unavailable" — sock-protocol.txt.
    """
    servidor = Servidor(driver.caminho)
    try:
        servidor.manda("PING")
        assert servidor.linha() == "PONG"
    finally:
        servidor.fecha()


def test_only_what_changed_travels(driver):
    """Republicar tudo a cada 2 s seria repetição pura no soquete."""
    servidor = Servidor(driver.caminho)
    try:
        driver.publicar({"ups.status": "OL", "battery.charge": "88"})
        servidor.manda("DUMPALL")
        servidor.ate("DUMPDONE")
        driver.publicar({"ups.status": "OL", "battery.charge": "87"})
        assert servidor.linha() == 'SETINFO battery.charge "87"'
    finally:
        servidor.fecha()


def test_a_variable_that_disappears_is_removed_not_left_behind(driver):
    """A porta serial calou: o watt por tomada tem de SUMIR, não congelar."""
    servidor = Servidor(driver.caminho)
    try:
        driver.publicar({"ups.status": "OL", "outlet.1.realpower": "12.0"})
        servidor.liga()
        driver.publicar({"ups.status": "OL"})
        assert servidor.espera("DELINFO") == "DELINFO outlet.1.realpower"
    finally:
        servidor.fecha()


def test_a_command_that_appears_is_announced_and_one_that_goes_is_withdrawn(driver):
    servidor = Servidor(driver.caminho)
    try:
        driver.publicar({}, comandos=["load.off"])
        servidor.liga()
        driver.publicar({}, comandos=["load.off", "shutdown.reboot"])
        assert servidor.espera("ADDCMD") == "ADDCMD shutdown.reboot"
        driver.publicar({}, comandos=["load.off"])
        assert servidor.espera("DELCMD") == "DELCMD shutdown.reboot"
    finally:
        servidor.fecha()


# -- comandos -----------------------------------------------------------------

def test_a_command_runs_and_its_result_goes_back_with_the_tracking_id(pasta_curta):
    """O servidor identifica cada ordem; a resposta tem de citar a MESMA."""
    feitos: list[tuple[str, str | None]] = []

    def executor(nome, parametro):
        feitos.append((nome, parametro))
        return nd.CMD_FEITO

    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"), executor=executor)
    d.iniciar()
    d.publicar({}, comandos=["load.off"])
    servidor = Servidor(d.caminho).liga()
    try:
        servidor.manda("INSTCMD load.off 10 TRACKING abc-123")
        assert servidor.espera("TRACKING") == "TRACKING abc-123 0"
        assert feitos == [("load.off", "10")]
    finally:
        servidor.fecha()
        d.encerrar()


def test_a_command_nobody_declared_is_refused_and_never_executed(pasta_curta):
    """Executar comando não declarado seria obedecer a quem pediu qualquer coisa."""
    def executor(_nome, _parametro):
        raise AssertionError("comando não declarado não pode ser executado")

    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"), executor=executor)
    d.iniciar()
    d.publicar({}, comandos=["load.off"])
    servidor = Servidor(d.caminho).liga()
    try:
        servidor.manda("INSTCMD shutdown.reboot TRACKING zz")
        assert servidor.espera("TRACKING") == f"TRACKING zz {nd.CMD_DESCONHECIDO}"
    finally:
        servidor.fecha()
        d.encerrar()


def test_a_command_that_blows_up_does_not_take_the_driver_with_it(pasta_curta):
    """Um `ssh` que estoura não pode derrubar a publicação inteira.

    Se derrubasse, uma tentativa de desligar o roteador apagaria do Home
    Assistant todas as leituras do no-break — justamente durante a queda.
    """
    def executor(_nome, _parametro):
        raise RuntimeError("o console não respondeu")

    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"), executor=executor)
    d.iniciar()
    d.publicar({}, comandos=["load.off"])
    servidor = Servidor(d.caminho).liga()
    try:
        servidor.manda("INSTCMD load.off TRACKING q1")
        assert servidor.espera("TRACKING") == f"TRACKING q1 {nd.CMD_FALHOU}"
        servidor.manda("PING")
        assert servidor.espera("PONG") == "PONG"
    finally:
        servidor.fecha()
        d.encerrar()


def test_a_slow_command_does_not_hold_the_ping(pasta_curta):
    """Desligar um roteador leva segundos; o `PING` não pode esperar por isso.

    Segurando o laço, o servidor concluiria que o driver morreu e apagaria todas
    as leituras da tela do Home Assistant no meio de um desligamento.
    """
    comecou = threading.Event()
    libera = threading.Event()

    def executor(_nome, _parametro):
        comecou.set()
        libera.wait(5)
        return nd.CMD_FEITO

    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"), executor=executor)
    d.iniciar()
    d.publicar({}, comandos=["load.off"])
    servidor = Servidor(d.caminho).liga()
    try:
        servidor.manda("INSTCMD load.off TRACKING lento")
        assert comecou.wait(3), "o comando nem começou"
        servidor.manda("PING")
        assert servidor.espera("PONG") == "PONG"   # com o comando ainda rodando
        libera.set()
        assert servidor.espera("TRACKING") == "TRACKING lento 0"
    finally:
        libera.set()
        servidor.fecha()
        d.encerrar()


def test_writing_a_variable_from_the_network_is_refused(pasta_curta):
    """Nada se muda por aqui: o que se configura, se configura na tela.

    Aceitar `SET` abriria um segundo caminho de escrita sem nenhuma das cercas
    que a tela tem.
    """
    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"))
    d.iniciar()
    d.publicar({"ups.status": "OL"})
    servidor = Servidor(d.caminho).liga()
    try:
        servidor.manda('SET ups.status "OB" TRACKING w1')
        assert servidor.espera("TRACKING") == f"TRACKING w1 {nd.CMD_INVALIDO}"
        assert d.variaveis()["ups.status"] == "OL"
    finally:
        servidor.fecha()
        d.encerrar()


# -- o que a revisão fria da 0.7.0 achou ---------------------------------------

def test_a_value_with_a_newline_cannot_inject_a_second_line(pasta_curta):
    """Uma variável do NUT é UMA linha. Quebra no meio não é valor estranho: é
    linha nova injetada no protocolo.

    E boa parte do que publicamos vem de fora — o modelo e o firmware saem do que
    o console respondeu. Um console comprometido, ou só um firmware que responde
    em duas linhas, passaria a escrever o estado do aparelho publicado.
    """
    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"))
    d.iniciar()
    servidor = Servidor(d.caminho).liga()
    try:
        d.publicar({"ups.status": "OL",
                    "device.model": 'UDR7\nSETINFO ups.status "OB LB'})
        linha = servidor.espera("SETINFO device.model")
        assert "\n" not in linha
        assert nd.divide_linha(linha)[1] == "device.model"
        # E o valor continua UM só argumento, com o texto achatado.
        assert nd.divide_linha(linha)[2].startswith("UDR7 SETINFO")
    finally:
        servidor.fecha()
        d.encerrar()


def test_the_answer_goes_to_who_asked_even_with_broadcasts_off(pasta_curta):
    """`NOBROADCAST` desliga os AVISOS, não as respostas.

    Sem esta distinção, o River era desligado (o executor rodava) e o Home
    Assistant nunca recebia a confirmação: para quem mandou, a ordem falhou; para
    o aparelho, ela aconteceu (revisão fria da 0.7.0, reproduzido).
    """
    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"),
                       executor=lambda _c, _p: nd.CMD_FEITO)
    d.iniciar()
    d.publicar({}, comandos=["load.off"])
    servidor = Servidor(d.caminho).liga()
    try:
        servidor.manda("NOBROADCAST")
        servidor.manda("INSTCMD load.off TRACKING mudo")
        assert servidor.espera("TRACKING") == "TRACKING mudo 0"
    finally:
        servidor.fecha()
        d.encerrar()


def test_the_answer_does_not_go_to_a_client_that_did_not_ask(pasta_curta):
    """Resposta é para quem perguntou. Quem não perguntou recebe os avisos, e só."""
    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"),
                       executor=lambda _c, _p: nd.CMD_FEITO)
    d.iniciar()
    d.publicar({"ups.status": "OL"}, comandos=["load.off"])
    quem_pergunta = Servidor(d.caminho).liga()
    outro = Servidor(d.caminho).liga()
    try:
        quem_pergunta.manda("INSTCMD load.off TRACKING p1")
        assert quem_pergunta.espera("TRACKING") == "TRACKING p1 0"
        # No outro, o que chega é a publicação seguinte — e NADA da resposta
        # alheia pelo caminho: uma marca de rastreio de outro cliente diria a ele
        # que uma ordem que ele não deu terminou.
        d.publicar({"ups.status": "OB"}, comandos=["load.off"])
        vistas = []
        while True:
            linha = outro.linha()
            vistas.append(linha)
            if linha.startswith("SETINFO"):
                break
        assert vistas == ['SETINFO ups.status "OB"'], f"vazou para quem não pediu: {vistas}"
    finally:
        quem_pergunta.fecha()
        outro.fecha()
        d.encerrar()


def test_a_second_order_while_one_is_running_is_refused_not_queued(pasta_curta):
    """Uma ordem por vez.

    Sem isto, cada `INSTCMD` criava uma linha de execução nova, sem limite — e
    duas ordens de desligamento correndo juntas num roteador de produção não é
    paralelismo, é confusão.
    """
    libera = threading.Event()
    comecou = threading.Event()

    def devagar(_comando, _parametro):
        comecou.set()
        libera.wait(5)
        return nd.CMD_FEITO

    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"), executor=devagar)
    d.iniciar()
    d.publicar({}, comandos=["load.off"])
    servidor = Servidor(d.caminho).liga()
    try:
        servidor.manda("INSTCMD load.off TRACKING primeira")
        assert comecou.wait(3)
        servidor.manda("INSTCMD load.off TRACKING segunda")
        assert servidor.espera("TRACKING") == f"TRACKING segunda {nd.CMD_FALHOU}"
        libera.set()
        assert servidor.espera("TRACKING") == "TRACKING primeira 0"
        # E depois que a primeira termina, a fila volta a andar.
        servidor.manda("INSTCMD load.off TRACKING terceira")
        assert servidor.espera("TRACKING") == "TRACKING terceira 0"
    finally:
        libera.set()
        servidor.fecha()
        d.encerrar()


def test_a_very_long_value_is_cut_without_splitting_an_escape(pasta_curta):
    """O corte não pode cair no MEIO de um par de escape.

    Terminando em número ímpar de contrabarras, a última escaparia a aspa de
    fechamento e a linha ficaria aberta: o servidor engoliria a linha seguinte
    inteira como continuação desta. Um banner de console cheio de arte ASCII
    basta (2.ª revisão fria da 0.7.0).
    """
    # Um texto que, escapado, cai com uma contrabarra exatamente no limite.
    comprido = "A" * (nd.LIMITE_CARACTERES - 1) + "\\" * 20
    saida = nd.codifica(comprido)
    assert len(saida) <= nd.LIMITE_CARACTERES
    assert (len(saida) - len(saida.rstrip("\\"))) % 2 == 0, "sobrou barra ímpar"

    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"))
    d.iniciar()
    servidor = Servidor(d.caminho).liga()
    try:
        d.publicar({"device.model": comprido, "battery.charge": "42"})
        # As DUAS linhas chegam inteiras — a segunda não é engolida pela primeira.
        modelo = servidor.espera("SETINFO device.model")
        carga = servidor.espera("SETINFO battery.charge")
        assert nd.divide_linha(carga)[2] == "42"
        assert len(nd.divide_linha(modelo)) == 3
    finally:
        servidor.fecha()
        d.encerrar()


def test_the_socket_is_never_group_writable_not_even_for_an_instant(pasta_curta, monkeypatch):
    """A fresta entre criar e ajustar a permissão também conta.

    Com a máscara antiga o soquete NASCIA 0770 e só virava 0600 na linha
    seguinte. Nessa fresta, na pasta 0755 de grupo `admin` desta máquina, uma
    conta administradora conectava — que é exatamente a cerca que esta versão
    veio fechar (2.ª revisão fria da 0.7.0, medido: "modo entre bind e chmod:
    0o770").
    """
    import stat as _stat

    vistos = []
    chmod_real = nd.os.chmod

    def espia(caminho, modo):
        try:
            vistos.append(_stat.S_IMODE(os.stat(caminho).st_mode))
        except OSError:
            pass
        return chmod_real(caminho, modo)

    monkeypatch.setattr(nd.os, "chmod", espia)
    d = nd.DriverDoNut(os.path.join(pasta_curta, "sock"))
    d.iniciar()
    try:
        assert vistos, "o driver não chegou a ajustar a permissão"
        for modo in vistos:
            assert not modo & 0o077, f"o soquete existiu com {oct(modo)}"
    finally:
        d.encerrar()
