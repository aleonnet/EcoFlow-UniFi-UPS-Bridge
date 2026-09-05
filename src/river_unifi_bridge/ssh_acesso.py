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


class AcessoError(Exception):
    """Falha ao preparar o acesso, já em português."""


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
    saida = executor(["ssh-keygen", "-l", "-f", "-"], entrada=texto.encode())
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
    if not os.path.exists(caminho) or not os.path.exists(publica):
        os.makedirs(os.path.dirname(caminho) or ".", exist_ok=True)
        for sobra in (caminho, publica):        # meia chave é pior que nenhuma
            if os.path.exists(sobra):
                os.remove(sobra)
        saida = rodar(["ssh-keygen", "-q", "-t", TIPO_DE_CHAVE, "-N", "",
                       "-C", COMENTARIO, "-f", caminho])
        if saida.returncode != 0:
            raise AcessoError("não consegui criar a chave de acesso ao console")
        os.chmod(caminho, 0o600)
    with open(publica, encoding="utf-8") as fh:
        texto = fh.read().strip()
    return Chave(publica=texto, impressao=_impressao_de(texto, rodar=rodar))


def identidade_do_host(host: str, porta: int = 22, *, rodar=_rodar) -> tuple[list[str], str]:
    """As linhas de identidade do console e a impressão digital para conferência.

    Sem `--` antes do endereço, e a razão é medida, não estética: o
    `ssh-keyscan` NÃO o trata como fim de opções — com ele, a varredura devolve
    apenas a chave RSA e some com as demais (medido no Mac mini em 2026-09-04,
    contra o console real: com `--`, uma linha; sem, três). Gravar só a RSA fazia
    o `ssh` recusar a conexão com "No ED25519 host key is known".

    A proteção que o `--` daria vem explícita: endereço que comece com `-` é
    recusado aqui, antes de virar argumento.
    """
    if host.startswith("-"):
        raise AcessoError("endereço de console inválido")
    saida = rodar(["ssh-keyscan", "-T", "5", "-p", str(porta), host],
                  tempo=TEMPO_LIMITE_CURTO)
    linhas = [l for l in saida.stdout.decode("utf-8", "replace").splitlines()
              if l and not l.startswith("#")]
    if not linhas:
        raise AcessoError("o console não respondeu quando perguntei quem ele é")
    # A impressão mostrada é a da chave mais forte que ele ofereceu.
    preferida = next((l for l in linhas if " ssh-ed25519 " in l), linhas[0])
    return linhas, _impressao_de(preferida.split(" ", 1)[1], rodar=rodar)


def gravar_identidade(caminho: str, host: str, linhas: list[str], *,
                      substituir: bool = False) -> None:
    """Grava a identidade do console. Divergência é recusa, não substituição."""
    existentes: list[str] = []
    if os.path.exists(caminho):
        with open(caminho, encoding="utf-8") as fh:
            existentes = [l.strip() for l in fh if l.strip()]
    do_host = [l for l in existentes if l.split(" ", 1)[0].split(",")[0] == host]
    novas = [l.strip() for l in linhas]
    if do_host and sorted(do_host) != sorted(novas) and not substituir:
        raise IdentidadeDivergente(
            "este console está se apresentando com uma identidade diferente da "
            "que foi registrada aqui. Isso acontece quando o aparelho é trocado "
            "ou reinstalado — e também quando alguém se coloca no meio do "
            "caminho. Confira a impressão digital antes de aceitar.")
    outros = [l for l in existentes if l.split(" ", 1)[0].split(",")[0] != host]
    with open(caminho, "w", encoding="utf-8") as fh:
        fh.write("\n".join(outros + novas) + "\n")
    os.chmod(caminho, 0o600)


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
        "ssh", "-T", "-F", "/dev/null",
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
                raise AcessoError("o console recusou a senha")
        _, estado = os.waitpid(pid, os.WNOHANG)
    finally:
        os.close(fd)
    if _RECUSOU.search(visto):
        raise AcessoError("o console recusou a senha")
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
