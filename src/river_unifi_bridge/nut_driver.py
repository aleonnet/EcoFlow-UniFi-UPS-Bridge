"""Nós viramos um driver do NUT — é assim que o Home Assistant recebe tudo.

Por que existe: o Home Assistant fala com o `upsd`, e o `upsd` só conhece o que
algum driver lhe contou. O driver de fábrica (`usbhid-ups`) conta o que o perfil
de no-break do River publica, que **não** inclui os watts por tomada nem comando
nenhum. O caminho que eu havia proposto — o driver de mentira (`dummy-ups`) — não
serve, e a documentação do NUT diz por quê, literalmente:

    "Instant commands are not yet supported in Dummy Mode"

Então a ponte passa a ser ela mesma um driver. Na arquitetura do NUT quem serve o
soquete é o driver, e o servidor é o cliente:

    "each driver is a server on the Unix socket … and the data server `upsd` is a
    client which knows where to find such sockets, how they are named, and
    connects to all of them to send commands and receive data updates"
    — docs/sock-protocol.txt do projeto NUT

Este módulo é só a tradução: soquete, enquadramento e protocolo. Nenhuma regra de
negócio mora aqui — quem decide se um comando pode ser executado é o serviço, com
as MESMAS cercas da tela.

Tudo o que segue foi lido no código e na documentação do NUT (2026-09-05), não
suposto:

- o nome do arquivo do soquete é `<driver>-<nome do aparelho>`, montado pelo
  servidor a partir do `ups.conf` (`server/conf.c`, `upsconf_add`);
- o driver cria o soquete com `unlink`, `umask(0007)`, `bind`, `chmod 0660`,
  `listen` (`drivers/dstate.c`, `open_sockfd`);
- a resposta a `DUMPALL` é `DATASTALE` (se os dados estiverem velhos), depois um
  `SETINFO` por variável, depois um `ADDCMD` por comando, depois `DATAOK` (se não
  estiverem velhos) e por fim `DUMPDONE` (`drivers/dstate.c`, `sock_arg`);
- o servidor manda `PING` quando faz um terço do `MAXAGE` sem notícia, e o driver
  tem de responder `PONG` "within a few seconds at the most";
- o retorno de um comando é `TRACKING <id> <inteiro>`, e os inteiros são os de
  `drivers/upshandler.h` (0 feito, 1 desconhecido, 2 inválido, 3 falhou).

Só biblioteca padrão: um serviço de no-break não ganha dependência por causa de
um soquete de texto.
"""

from __future__ import annotations

import errno
import os
import select
import socket
import stat
import threading
from typing import Callable, Iterable

# Os códigos que o servidor espera de volta num TRACKING. São os de
# `drivers/upshandler.h` do NUT; o servidor os traduz em texto para o cliente.
CMD_FEITO = 0
CMD_DESCONHECIDO = 1
CMD_INVALIDO = 2
CMD_FALHOU = 3

# Onde o Homebrew guarda o estado do NUT no Apple Silicon — é onde os soquetes
# dos drivers vivem, e é onde o `upsd` os procura (medido no Mac mini: o do
# leitor de fábrica é `usbhid-ups-river-office`).
ESTADO_PADRAO = "/opt/homebrew/var/state/ups"
# O nome com que nos declaramos no `ups.conf`. O servidor concatena
# `<driver>-<aparelho>` para achar o soquete, então este nome é metade do
# caminho do arquivo.
NOME_DO_DRIVER = "river-bridge"

# Limites do parseconf, que é quem lê os dois lados do soquete: "These default to
# 32 arguments of 512 characters each". Uma linha maior que isso não seria
# entendida pelo servidor — cortar aqui é preferível a mandar lixo.
LIMITE_ARGUMENTOS = 32
LIMITE_CARACTERES = 512

# O caminho de um soquete Unix não cabe onde um caminho de arquivo cabe: o campo
# do sistema tem 104 bytes no macOS, e passar disso é um erro seco na criação. O
# NUT confere o mesmo (`check_unix_socket_filename`, em `server/sstate.c`), e a
# medida vale para nós porque o diretório de estado do macOS é fundo
# ("Application Support"). Falhar aqui, com frase, é melhor que falhar no `bind`.
LIMITE_DO_CAMINHO = 100


class DriverError(Exception):
    """Não deu para servir o soquete deste aparelho."""


def caminho_do_soquete(aparelho: str, estado: str = ESTADO_PADRAO) -> str:
    """`<estado>/<driver>-<aparelho>` — a regra que o servidor usa para nos achar."""
    return os.path.join(estado, f"{NOME_DO_DRIVER}-{aparelho}")


def codifica(valor: str) -> str:
    """Prepara um valor para viajar: escapa a estrutura e achata o que não é linha.

    Duas coisas, e a segunda é a que dói:

    1. `\\` e `"` são escapados, como o `pconf_encode` do NUT faz — sem isso, um
       valor com aspas partiria a linha em duas e o servidor guardaria metade de
       um número como se fosse o todo.
    2. **Quebra de linha e demais caracteres de controle viram espaço.** Uma
       variável do NUT é uma linha; um valor com `\\n` no meio não é um valor
       estranho, é uma LINHA NOVA injetada no protocolo. E boa parte do que
       publicamos vem de fora: o modelo e a versão do firmware saem do que o
       console respondeu. Um console comprometido — ou só um firmware que responde
       em duas linhas — passaria a escrever `ups.status` do aparelho publicado.
       (Revisão fria da 0.7.0, reproduzido.)

    O corte em `LIMITE_CARACTERES` é do parseconf, que lê os dois lados do
    soquete: valor maior não seria entendido do outro lado.
    """
    limpo = "".join(" " if (ord(c) < 0x20 or ord(c) == 0x7F) else c for c in valor)
    limpo = limpo.replace("\\", "\\\\").replace('"', '\\"')
    return limpo[:LIMITE_CARACTERES]


def divide_linha(linha: str) -> list[str]:
    """Quebra uma linha nas regras do parseconf: espaços separam, aspas juntam.

    "The \"\" construct is used throughout to force a multi-word value to stay
    together on its way to the other end." — docs/sock-protocol.txt
    """
    partes: list[str] = []
    atual: list[str] = []
    dentro_de_aspas = False
    escapado = False
    tem_algo = False
    for caractere in linha:
        if escapado:
            atual.append(caractere)
            escapado = False
            continue
        if caractere == "\\":
            escapado = True
            tem_algo = True
            continue
        if caractere == '"':
            dentro_de_aspas = not dentro_de_aspas
            tem_algo = True
            continue
        if caractere.isspace() and not dentro_de_aspas:
            if tem_algo:
                partes.append("".join(atual))
                atual = []
                tem_algo = False
            continue
        atual.append(caractere)
        tem_algo = True
    if tem_algo:
        partes.append("".join(atual))
    return partes


class _Cliente:
    """Uma conexão do servidor do no-break, com a fila do que falta sair.

    A fila existe porque escrever direto no soquete travaria o laço do serviço se
    o outro lado parasse de ler — e o laço que trava é o que decide desligar
    aparelhos numa queda de energia.
    """

    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.saida = bytearray()
        self.entrada = bytearray()
        self.quer_broadcast = True

    def enfileira(self, texto: str) -> None:
        self.saida.extend(texto.encode("utf-8", "replace"))

    def escoa(self) -> bool:
        """Manda o que der agora. Devolve False quando a conexão morreu."""
        while self.saida:
            try:
                enviados = self.sock.send(bytes(self.saida))
            except BlockingIOError:
                return True
            except OSError:
                return False
            if enviados <= 0:
                return False
            del self.saida[:enviados]
        return True


class DriverDoNut:
    """Um aparelho publicado no NUT por nós: variáveis, comandos e o soquete.

    Uma instância por aparelho declarado no `ups.conf`. O laço de rede roda numa
    linha de execução própria; publicar é barato e nunca bloqueia.
    """

    def __init__(self, caminho: str, *, log=None,
                 executor: Callable[[str, str | None], int] | None = None) -> None:
        self.caminho = caminho
        self._log = log or (lambda *_a, **_k: None)
        self._executor = executor
        self._lock = threading.RLock()
        self._variaveis: dict[str, str] = {}
        self._comandos: set[str] = set()
        self._dados_ok = False
        self._clientes: list[_Cliente] = []
        self._servidor: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._parar = threading.Event()
        self._acorda_r = -1
        self._acorda_w = -1

    # -- ciclo de vida ------------------------------------------------------
    def iniciar(self) -> None:
        """Cria o soquete e passa a atender. Os passos são os do `dstate.c`."""
        with self._lock:
            if self._servidor is not None:
                return
            if len(os.fsencode(self.caminho)) > LIMITE_DO_CAMINHO:
                raise DriverError(
                    f"o caminho do soquete tem {len(self.caminho)} caracteres e o "
                    f"sistema aceita até {LIMITE_DO_CAMINHO}: {self.caminho}")
            pasta = os.path.dirname(self.caminho)
            if pasta:
                os.makedirs(pasta, exist_ok=True)
            try:
                os.unlink(self.caminho)          # sobra de uma execução anterior
            except FileNotFoundError:
                pass
            servidor = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            umask_antes = os.umask(0o007)
            try:
                servidor.bind(self.caminho)
            finally:
                os.umask(umask_antes)
            # 0600, e NÃO o 0660 que os drivers do NUT usam. A diferença é
            # deliberada e o motivo está na documentação do próprio NUT: "There
            # are no access controls in the drivers. Anything that can connect to
            # their sockets can make requests, including SET and INSTCMD … These
            # sockets must be kept secure."
            #
            # Medido nesta máquina em 2026-09-05: /opt/homebrew/var/state/ups é
            # 0755 com grupo `admin`, e um soquete 0660 ali dentro fica gravável
            # por QUALQUER conta administradora — que poderia mandar desligar o
            # River sem ficha, sem senha e sem deixar rastro de quem foi. Com
            # 0600, só quem roda o serviço conecta; o servidor do no-break sobe
            # como o mesmo usuário (o supervisor lhe passa `-u`), então nada muda
            # para ele. Quem rodar o `upsd` com outro usuário simplesmente não vê
            # os nossos aparelhos — falha visível, não buraco silencioso.
            os.chmod(self.caminho, stat.S_IRUSR | stat.S_IWUSR)
            servidor.listen(16)
            servidor.setblocking(False)
            self._servidor = servidor
            self._acorda_r, self._acorda_w = os.pipe()
            os.set_blocking(self._acorda_r, False)
            os.set_blocking(self._acorda_w, False)
            self._parar.clear()
            self._thread = threading.Thread(target=self._atender, name="nut-driver", daemon=True)
            self._thread.start()
            self._log("INFO", "nut_driver_soquete", caminho=self.caminho)

    def encerrar(self) -> None:
        self._parar.set()
        self._cutuca()
        thread = self._thread
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=5)
        with self._lock:
            for cliente in self._clientes:
                try:
                    cliente.sock.close()
                except OSError:
                    pass
            self._clientes.clear()
            if self._servidor is not None:
                try:
                    self._servidor.close()
                except OSError:
                    pass
                self._servidor = None
            # Os números somem ANTES de os arquivos fecharem: quem cutucar em
            # seguida vê -1 e desiste, em vez de escrever num descritor fechado.
            descritores = (self._acorda_r, self._acorda_w)
            self._acorda_r = self._acorda_w = -1
            for descritor in descritores:
                if descritor >= 0:
                    try:
                        os.close(descritor)
                    except OSError:
                        pass
            self._thread = None
        try:
            os.unlink(self.caminho)
        except OSError:
            pass

    def _cutuca(self) -> None:
        """Tira o laço do `select` sem esperar o tempo limite.

        Sob a trava de propósito: fora dela, um `encerrar()` concorrente fecharia
        o cano entre a leitura do número e a escrita, e o número já poderia ter
        sido reaproveitado por outro descritor do processo — o banco do histórico,
        o cano de um `ssh`. Escrever um byte no arquivo errado é o tipo de defeito
        que aparece uma vez por mês e nunca no teste (revisão fria da 0.7.0).
        """
        with self._lock:
            if self._acorda_w >= 0:
                try:
                    os.write(self._acorda_w, b"x")
                except OSError:
                    pass

    # -- o que publicamos ---------------------------------------------------
    def publicar(self, variaveis: dict[str, str], *,
                 comandos: Iterable[str] = (), dados_ok: bool = True) -> None:
        """Estado novo: manda para quem está ligado só o que MUDOU.

        Mandar tudo a cada volta encheria o soquete de repetição: com 2 s de
        ciclo, são 30 linhas por segundo que o servidor teria de reprocessar sem
        nenhuma delas dizer nada novo.
        """
        comandos = set(comandos)
        with self._lock:
            linhas: list[str] = []
            for nome, valor in variaveis.items():
                if self._variaveis.get(nome) != valor:
                    linhas.append(f'SETINFO {nome} "{codifica(valor)}"\n')
            for nome in self._variaveis:
                if nome not in variaveis:
                    linhas.append(f"DELINFO {nome}\n")
            for comando in sorted(comandos - self._comandos):
                linhas.append(f"ADDCMD {comando}\n")
            for comando in sorted(self._comandos - comandos):
                linhas.append(f"DELCMD {comando}\n")
            if dados_ok != self._dados_ok:
                linhas.append("DATAOK\n" if dados_ok else "DATASTALE\n")
            self._variaveis = dict(variaveis)
            self._comandos = comandos
            self._dados_ok = dados_ok
            if linhas:
                self._para_todos("".join(linhas))

    def marcar_sem_dados(self) -> None:
        """O no-break calou: o servidor precisa saber que o que ele tem envelheceu."""
        with self._lock:
            if self._dados_ok:
                self._dados_ok = False
                self._para_todos("DATASTALE\n")

    def _para_todos(self, texto: str) -> None:
        for cliente in list(self._clientes):
            if cliente.quer_broadcast:
                cliente.enfileira(texto)
        self._cutuca()

    # -- o laço de rede -----------------------------------------------------
    def _atender(self) -> None:
        while not self._parar.is_set():
            with self._lock:
                servidor = self._servidor
                if servidor is None:
                    return
                leitura = [servidor, self._acorda_r]
                escrita = []
                for cliente in self._clientes:
                    leitura.append(cliente.sock)
                    if cliente.saida:
                        escrita.append(cliente.sock)
            try:
                prontos_r, prontos_w, _ = select.select(leitura, escrita, [], 1.0)
            except (OSError, ValueError):
                if self._parar.is_set():
                    return
                continue
            if self._acorda_r in prontos_r:
                try:
                    os.read(self._acorda_r, 4096)
                except OSError:
                    pass
            if servidor in prontos_r:
                self._aceitar(servidor)
            for sock in prontos_r:
                if sock is servidor or sock is self._acorda_r or isinstance(sock, int):
                    continue
                self._ler(sock)
            for sock in prontos_w:
                self._escoar(sock)
            with self._lock:
                for cliente in list(self._clientes):
                    if cliente.saida and not cliente.escoa():
                        self._desligar(cliente)

    def _aceitar(self, servidor: socket.socket) -> None:
        try:
            sock, _ = servidor.accept()
        except (BlockingIOError, OSError) as exc:
            if getattr(exc, "errno", None) not in (errno.EAGAIN, errno.EWOULDBLOCK):
                self._log("WARN", "nut_driver_accept_falhou", reason=str(exc)[:200])
            return
        sock.setblocking(False)
        with self._lock:
            self._clientes.append(_Cliente(sock))
        self._log("INFO", "nut_driver_cliente", caminho=self.caminho)

    def _cliente_de(self, sock) -> _Cliente | None:
        for cliente in self._clientes:
            if cliente.sock is sock:
                return cliente
        return None

    def _ler(self, sock) -> None:
        with self._lock:
            cliente = self._cliente_de(sock)
            if cliente is None:
                return
        try:
            pedaco = sock.recv(4096)
        except BlockingIOError:
            return
        except OSError:
            pedaco = b""
        if not pedaco:
            with self._lock:
                self._desligar(cliente)
            return
        cliente.entrada.extend(pedaco)
        while b"\n" in cliente.entrada:
            bruta, _, resto = bytes(cliente.entrada).partition(b"\n")
            cliente.entrada = bytearray(resto)
            self._comando_do_servidor(cliente, bruta.decode("utf-8", "replace"))

    def _escoar(self, sock) -> None:
        with self._lock:
            cliente = self._cliente_de(sock)
            if cliente is not None and not cliente.escoa():
                self._desligar(cliente)

    def _desligar(self, cliente: _Cliente) -> None:
        try:
            cliente.sock.close()
        except OSError:
            pass
        if cliente in self._clientes:
            self._clientes.remove(cliente)

    # -- o que o servidor nos pede ------------------------------------------
    def _comando_do_servidor(self, cliente: _Cliente, linha: str) -> None:
        partes = divide_linha(linha)
        if not partes:
            return
        verbo = partes[0].upper()
        if verbo == "PING":
            cliente.enfileira("PONG\n")
        elif verbo == "DUMPALL":
            self._despejar(cliente)
        elif verbo == "DUMPSTATUS":
            self._despejar_um(cliente, "ups.status")
        elif verbo == "DUMPVALUE" and len(partes) > 1:
            self._despejar_um(cliente, partes[1])
        elif verbo == "GETPID":
            cliente.enfileira(f"PID {os.getpid()}\n")
        elif verbo == "LOGOUT":
            cliente.enfileira("OK Goodbye\n")
        elif verbo == "NOBROADCAST":
            cliente.quer_broadcast = False
        elif verbo == "BROADCAST":
            numero = partes[1] if len(partes) > 1 else "1"
            try:
                cliente.quer_broadcast = int(numero) > 0
            except ValueError:
                cliente.quer_broadcast = True
        elif verbo == "INSTCMD" and len(partes) > 1:
            self._instcmd(cliente, partes[1:])
        elif verbo == "SET":
            # Nós não expomos variável para escrita: o que se muda aqui se muda
            # na tela, com as cercas dela. Recusar em silêncio seria pior — o
            # rastreio devolve "inválido" e o servidor traduz para o cliente.
            self._responder_rastreio(cliente, partes, CMD_INVALIDO)
        self._cutuca()

    def _despejar(self, cliente: _Cliente) -> None:
        with self._lock:
            if not self._dados_ok:
                cliente.enfileira("DATASTALE\n")
            for nome, valor in self._variaveis.items():
                cliente.enfileira(f'SETINFO {nome} "{codifica(valor)}"\n')
            for comando in sorted(self._comandos):
                cliente.enfileira(f"ADDCMD {comando}\n")
            if self._dados_ok:
                cliente.enfileira("DATAOK\n")
            cliente.enfileira("DUMPDONE\n")

    def _despejar_um(self, cliente: _Cliente, nome: str) -> None:
        with self._lock:
            if not self._dados_ok:
                cliente.enfileira("DATASTALE\n")
            valor = self._variaveis.get(nome)
            if valor is not None:
                cliente.enfileira(f'SETINFO {nome} "{codifica(valor)}"\n')
            if self._dados_ok:
                cliente.enfileira("DATAOK\n")
            cliente.enfileira("DUMPDONE\n")

    # -- comandos -----------------------------------------------------------
    @staticmethod
    def _rastreio(partes: list[str]) -> str | None:
        """O `TRACKING <id>` do fim da linha, quando o servidor o mandou."""
        for indice, parte in enumerate(partes):
            if parte.upper() == "TRACKING" and indice + 1 < len(partes):
                return partes[indice + 1]
        return None

    def _responder_rastreio(self, cliente: _Cliente, partes: list[str], codigo: int) -> None:
        identificador = self._rastreio(partes)
        if identificador is not None:
            self._para_um(cliente, f"TRACKING {identificador} {codigo}\n")

    def _para_um(self, cliente: _Cliente, texto: str) -> None:
        """Resposta é para QUEM PERGUNTOU.

        Mandá-la como aviso geral tinha duas consequências, as duas medidas na
        revisão fria da 0.7.0: chegava a quem não perguntou, e **não chegava** a
        quem tivesse pedido para não receber avisos (`NOBROADCAST`) — o River era
        desligado e o Home Assistant nunca sabia se a ordem valeu.
        """
        with self._lock:
            if cliente in self._clientes:      # desligou no meio: não há a quem responder
                cliente.enfileira(texto)
        self._cutuca()

    def _instcmd(self, cliente: _Cliente, argumentos: list[str]) -> None:
        """`INSTCMD <cmd> [<param>] [TRACKING <id>]`.

        O comando roda em linha de execução PRÓPRIA: desligar um roteador por
        `ssh` leva segundos, e o laço do soquete parado esses segundos deixaria o
        `PING` do servidor sem resposta — o que, pelo protocolo, faz o driver ser
        tratado como morto e todas as leituras sumirem da tela do Home Assistant.
        """
        nome = argumentos[0]
        identificador = self._rastreio(argumentos)
        parametro: str | None = None
        if len(argumentos) > 1 and argumentos[1].upper() != "TRACKING":
            parametro = argumentos[1]
        with self._lock:
            conhecido = nome in self._comandos
            executor = self._executor
        if not conhecido or executor is None:
            self._log("WARN", "nut_instcmd_desconhecido", comando=nome)
            if identificador is not None:
                self._para_um(cliente, f"TRACKING {identificador} {CMD_DESCONHECIDO}\n")
            return

        def rodar() -> None:
            try:
                codigo = int(executor(nome, parametro))
            except Exception as exc:      # o driver não morre por causa de um comando
                self._log("ERROR", "nut_instcmd_falhou", comando=nome,
                          tipo=type(exc).__name__, reason=str(exc)[:200])
                codigo = CMD_FALHOU
            if identificador is not None:
                self._para_um(cliente, f"TRACKING {identificador} {codigo}\n")

        threading.Thread(target=rodar, name=f"nut-instcmd-{nome}", daemon=True).start()

    # -- para a tela e para os testes ---------------------------------------
    @property
    def clientes(self) -> int:
        with self._lock:
            return len(self._clientes)

    def variaveis(self) -> dict[str, str]:
        with self._lock:
            return dict(self._variaveis)

    def comandos(self) -> set[str]:
        with self._lock:
            return set(self._comandos)
