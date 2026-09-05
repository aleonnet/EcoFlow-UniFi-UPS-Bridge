"""Preparar o acesso ao console sem terminal: chave, identidade e prova de alcance.

Por que este módulo existe, na ordem em que os fatos apareceram:

1. O serviço entra no console com **chave**, nunca com senha — é o que permite
   agir sozinho de madrugada (`protect.ssh_argv`: `BatchMode=yes`,
   `PasswordAuthentication=no`).
2. Instalar essa chave exigia terminal (`ssh-keygen` + `ssh-copy-id`). O dono
   recusou, com razão: *"o App tem que ser User friendly e não para nerds"*.
3. A interface do console dele **não tem** tela de colar chave — medido em
   2026-09-04, Network 10.6.101: o "System" não tem "Advanced" nem "Device
   Authentication".
4. A API oficial do console, com chave, **não desliga** o aparelho: o próprio
   console responde `valid values: 'RESTART'` (medido no ato). Logo o caminho do
   desligamento continua sendo o SSH — e a prova de alcance tem de exercitar
   ESSE caminho, não outro.

Daí as quatro coisas aqui: criar a chave, ler a identidade do console, instalar a
chave usando a senha UMA vez, e provar alcance com os comandos de leitura.

Duas regras que o resto do arquivo obedece sem exceção:

- **A chave privada nunca sai daqui.** Nenhuma função a devolve, nenhuma a
  registra. Só a pública e a impressão digital saem.
- **A senha é de passagem.** Existe como argumento, é escrita no terminal do
  `ssh` e morre com a função: nunca em disco, nunca em log, nunca na resposta.

Só biblioteca padrão: um daemon que vigia energia não ganha dependência por causa
de uma configuração que roda uma vez.
"""

from __future__ import annotations

import os
import pty
import re
import select
import signal
import subprocess
import time
from dataclasses import dataclass

# Quanto esperar pela conversa com o console em cada etapa.
TEMPO_LIMITE = 20.0
# O que o `ssh-keyscan` e o `ssh-keygen` levam, no máximo, numa rede local.
TEMPO_LIMITE_CURTO = 10.0
# Tipo de chave: ed25519 é curta, rápida e aceita por qualquer OpenSSH moderno.
TIPO_DE_CHAVE = "ed25519"
COMENTARIO = "river-bridge"
# Caminho absoluto, como no resto do projeto (`protect.SSH_BINARY`) e como o
# instalador exige em letras maiúsculas: este é justamente o trecho que carrega a
# senha do console — confiar no PATH de quem chamou seria o pior lugar para isso.
SSH = "/usr/bin/ssh"
SSH_KEYGEN = "/usr/bin/ssh-keygen"
SSH_KEYSCAN = "/usr/bin/ssh-keyscan"


class AcessoError(Exception):
    """Falha ao preparar o acesso, já em português."""


class SenhaRecusada(AcessoError):
    """O console recusou a senha — e só isso.

    Classe própria porque a tela dá conselhos diferentes: trocar a senha não
    resolve console inalcançável, e mandar o dono trocar a senha por causa de um
    endereço errado foi o que a classificação por texto produzia (revisão fria).
    """


class IdentidadeDivergente(AcessoError):
    """O console apresentou identidade diferente da que já estava registrada.

    Não é aviso: é recusa. Trocar a identidade de host em silêncio é justamente o
    passo de que um ataque de intermediário precisa.
    """


@dataclass
class Chave:
    """O que pode sair daqui: a parte pública e a impressão digital."""

    publica: str
    impressao: str


def _rodar(argv: list[str], *, tempo: float = TEMPO_LIMITE_CURTO,
           entrada: bytes | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(argv, capture_output=True, timeout=tempo,
                              check=False, input=entrada)
    except FileNotFoundError as exc:
        raise AcessoError(f"não encontrei o programa {argv[0]} nesta máquina") from exc
    except subprocess.TimeoutExpired as exc:
        raise AcessoError("o console não respondeu a tempo") from exc


def _impressao_de(texto: str, *, rodar=None) -> str:
    """A impressão digital de uma chave pública, como o OpenSSH a mostra."""
    executor = rodar or _rodar
    saida = executor([SSH_KEYGEN, "-l", "-f", "-"], entrada=texto.encode())
    if saida.returncode != 0:
        raise AcessoError("não consegui calcular a impressão digital da chave")
    partes = saida.stdout.decode("utf-8", "replace").split()
    # `256 SHA256:xxxx comentário (ED25519)` — a impressão é o segundo campo.
    return partes[1] if len(partes) >= 2 else saida.stdout.decode().strip()


def garantir_chave(caminho: str, *, rodar=_rodar) -> Chave:
    """A chave dedicada deste dispositivo; cria se faltar, nunca recria.

    Recriar seria pior que não ter: a chave antiga já pode estar instalada no
    console, e o acesso morreria em silêncio.
    """
    publica = f"{caminho}.pub"
    if os.path.exists(caminho) and not os.path.exists(publica):
        # A privada existe e só a pública sumiu: a pública se DERIVA dela. Apagar
        # as duas e gerar outra tiraria o acesso que já está instalado no console
        # — e a prova de alcance continuaria valendo por 30 dias, mentindo.
        saida = rodar([SSH_KEYGEN, "-y", "-f", caminho])
        if saida.returncode != 0:
            raise AcessoError("a chave de acesso ao console está ilegível")
        with open(publica, "w", encoding="utf-8") as fh:
            fh.write(saida.stdout.decode("utf-8", "replace").strip() + f" {COMENTARIO}\n")
    if not os.path.exists(caminho):
        os.makedirs(os.path.dirname(caminho) or ".", exist_ok=True)
        if os.path.exists(publica):             # meia chave é pior que nenhuma
            os.remove(publica)
        saida = rodar([SSH_KEYGEN, "-q", "-t", TIPO_DE_CHAVE, "-N", "",
                       "-C", COMENTARIO, "-f", caminho])
        if saida.returncode != 0:
            raise AcessoError("não consegui criar a chave de acesso ao console")
        os.chmod(caminho, 0o600)
    with open(publica, encoding="utf-8") as fh:
        texto = fh.read().strip()
    return Chave(publica=texto, impressao=_impressao_de(texto, rodar=rodar))


def identidade_do_host(host: str, porta: int = 22, *, rodar=_rodar) -> tuple[list[str], str]:
    """As linhas de identidade do console e a impressão digital para conferência.

    **Todas** as linhas que a varredura devolver são gravadas, e isso importa: o
    `ssh` escolhe o tipo de chave na negociação, e um arquivo com só uma delas o
    faz recusar a conexão com "No ED25519 host key is known" — foi o que
    aconteceu no console do dono em 2026-09-04.

    A varredura é feita em paralelo por tipo, com tempo limite: ela PODE voltar
    incompleta (medido: a mesma máquina devolveu 1 linha numa rodada e 3 noutra).
    Incompleta não é silêncio — o passo seguinte falha na cara, com o que o `ssh`
    respondeu na mensagem.

    Endereço que comece com `-` é recusado aqui, antes de virar argumento (é o que
    o `--` daria, e assim não depende de como cada versão do `ssh-keyscan` o trata).
    """
    if host.startswith("-"):
        raise AcessoError("endereço de console inválido")
    saida = rodar([SSH_KEYSCAN, "-T", "5", "-p", str(porta), host],
                  tempo=TEMPO_LIMITE_CURTO)
    linhas = [l for l in saida.stdout.decode("utf-8", "replace").splitlines()
              if l and not l.startswith("#")]
    if not linhas:
        raise AcessoError("o console não respondeu quando perguntei quem ele é")
    # A impressão mostrada é a da chave mais forte que ele ofereceu.
    preferida = next((l for l in linhas if " ssh-ed25519 " in l), linhas[0])
    return linhas, _impressao_de(preferida.split(" ", 1)[1], rodar=rodar)


def marcador(host: str, porta: int = 22) -> str:
    """Como o OpenSSH nomeia o host no arquivo de identidades.

    Porta diferente de 22 vira `[host]:porta` — a mesma forma que `protect.py`
    já usa ao conferir. Comparar com o endereço puro fazia a recusa de identidade
    divergente **não existir** em porta não padrão (revisão fria da 0.6.0).
    """
    return host if porta == 22 else f"[{host}]:{porta}"


def gravar_identidade(caminho: str, host: str, linhas: list[str], *,
                      porta: int = 22, substituir: bool = False) -> None:
    """Grava a identidade do console. Divergência é recusa, não substituição."""
    existentes: list[str] = []
    if os.path.exists(caminho):
        with open(caminho, encoding="utf-8") as fh:
            existentes = [l.strip() for l in fh if l.strip()]
    alvo = marcador(host, porta)
    do_host = [l for l in existentes if l.split(" ", 1)[0].split(",")[0] == alvo]
    novas = [l.strip() for l in linhas]
    if do_host and sorted(do_host) != sorted(novas) and not substituir:
        raise IdentidadeDivergente(
            "este console está se apresentando com uma identidade diferente da "
            "que foi registrada aqui. Isso acontece quando o aparelho é trocado "
            "ou reinstalado — e também quando alguém se coloca no meio do "
            "caminho. Confira a impressão digital antes de aceitar.")
    outros = [l for l in existentes if l.split(" ", 1)[0].split(",")[0] != alvo]
    # Troca ATÔMICA: um desligamento em curso não pode ler este arquivo pela
    # metade — leitura vazia aqui vira conexão recusada.
    temporario = f"{caminho}.novo"
    with open(temporario, "w", encoding="utf-8") as fh:
        fh.write("\n".join(outros + novas) + "\n")
    os.chmod(temporario, 0o600)
    os.replace(temporario, caminho)


def _colher(pid: int, limite: float) -> int | None:
    """Espera o filho terminar até o limite; passado ele, mata e colhe.

    Sem colher, o processo vira zumbi preso ao serviço; sem matar, um `ssh`
    travado ficaria vivo para sempre segurando o terminal.
    """
    while time.monotonic() < limite:
        pego, estado = os.waitpid(pid, os.WNOHANG)
        if pego == pid:
            return estado
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
    try:
        return os.waitpid(pid, 0)[1]
    except OSError:                          # pragma: no cover — já colhido
        return None


def _resumo(bruto: bytes, limite: int = 300) -> str:
    """O que o console escreveu, em uma linha, para caber numa mensagem de erro."""
    texto = " ".join(bruto.decode("utf-8", "replace").split())
    return texto[:limite]


_PEDE_SENHA = re.compile(rb"assword:|assphrase")
_RECUSOU = re.compile(rb"Permission denied|denied \(|Authentication failed")


def instalar_chave_com_senha(host: str, porta: int, usuario: str, senha: str,
                             publica: str, known_hosts: str,
                             *, spawn=pty.fork, tempo: float = TEMPO_LIMITE) -> None:
    """Acrescenta a chave pública ao console, usando a senha UMA vez.

    A senha entra por terminal (é a única coisa que o `ssh` aceita), nunca por
    linha de comando — argumento de processo é visível para toda a máquina.
    Ela não é registrada, não é gravada e não volta na resposta.

    O comando remoto é fixo e idempotente: cria a pasta, acrescenta a chave se
    ela ainda não estiver lá, e ajusta as permissões.
    """
    # A conferência vem ANTES de montar o comando: a chave é base64 mais um
    # comentário, e uma aspa simples aí dentro sairia do texto citado no shell
    # do console. (Ela é nossa, mas a ordem certa é a que não depende disso.)
    if "'" in publica or "\n" in publica:
        raise AcessoError("a chave pública tem um caractere inesperado")
    remoto = (
        "umask 077; mkdir -p ~/.ssh; "
        f"grep -qxF '{publica}' ~/.ssh/authorized_keys 2>/dev/null "
        f"|| printf '%s\\n' '{publica}' >> ~/.ssh/authorized_keys; "
        "chmod 600 ~/.ssh/authorized_keys"
    )
    argv = [
        SSH, "-T", "-F", "/dev/null",
        "-o", "BatchMode=no",
        "-o", "PubkeyAuthentication=no",    # é a senha que estamos usando agora
        "-o", "PreferredAuthentications=password,keyboard-interactive",
        "-o", "StrictHostKeyChecking=yes",
        # Aspas: o `ssh` divide este valor por espaços (ver a nota em
        # `protect.ssh_argv`), e o nosso caminho tem "Application Support".
        "-o", f'UserKnownHostsFile="{known_hosts}"',
        "-o", "GlobalKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=10",
        "-p", str(porta), "--", f"{usuario}@{host}", remoto,
    ]
    pid, fd = spawn()
    if pid == 0:                            # filho: vira o próprio ssh
        os.execvp(argv[0], argv)
        os._exit(127)                       # pragma: no cover — execvp não volta
    limite = time.monotonic() + tempo
    visto = b""
    mandou_senha = False
    try:
        while time.monotonic() < limite:
            pronto, _, _ = select.select([fd], [], [], 0.5)
            if pronto:
                try:
                    pedaco = os.read(fd, 4096)
                except OSError:             # o filho fechou o terminal: acabou
                    break
                if not pedaco:
                    break
                visto += pedaco
                if not mandou_senha and _PEDE_SENHA.search(visto):
                    os.write(fd, senha.encode() + b"\n")
                    mandou_senha = True
                    visto = b""             # não guardamos o eco da senha
            if _RECUSOU.search(visto):
                raise SenhaRecusada("o console recusou a senha")
        estado = _colher(pid, limite)
    finally:
        os.close(fd)
    if _RECUSOU.search(visto):
        raise SenhaRecusada("o console recusou a senha")
    if estado is None:
        raise AcessoError("o console não terminou a conversa a tempo")
    if os.WIFEXITED(estado) and os.WEXITSTATUS(estado) != 0:
        # Sem isto, um `ssh` que sai com erro DEPOIS da senha (uma segunda
        # pergunta, um comando remoto que falhou) era relatado como sucesso, e só
        # o teste de alcance seguinte denunciava (revisão fria da 0.6.0).
        raise AcessoError("o console não aceitou a instalação da chave: "
                          + (_resumo(visto) or "sem resposta"))
    if not mandou_senha:
        # A resposta do console ENTRA na mensagem: sem ela, "não pediu senha" é
        # um beco sem saída para quem está na frente da tela (e para quem está
        # depurando). O que o `ssh` escreveu é a única pista que existe aqui.
        raise AcessoError("o console não pediu senha. O que ele respondeu: "
                          + (_resumo(visto) or "nada"))


def testar_alcance(argv_para, comandos: dict[str, str], *,
                   rodar=_rodar) -> dict[str, str | None]:
    """Roda os comandos de LEITURA pelo mesmo caminho do comando que desliga.

    `argv_para(comando)` monta a linha do `ssh` com as opções da proteção — é
    ESSE o ponto: provar alcance por um caminho diferente do que executa o ato
    destrutivo não prova nada sobre ele.
    """
    resposta: dict[str, str | None] = {}
    for nome, comando in comandos.items():
        saida = rodar(argv_para(comando), tempo=TEMPO_LIMITE)
        texto = saida.stdout.decode("utf-8", "replace").strip()
        resposta[nome] = texto if saida.returncode == 0 and texto else None
    return resposta
