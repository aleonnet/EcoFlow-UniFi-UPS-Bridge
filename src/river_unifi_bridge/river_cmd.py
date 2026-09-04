"""Falar com o nosso próprio servidor NUT: ler, gravar e mandar comando.

Só o protocolo de texto do NUT, por soquete, sem depender de `upsc`/`upsrw`/
`upscmd` no PATH — o serviço roda sob launchd, onde o PATH é mínimo, e um daemon
que vigia energia não pode depender de onde o Homebrew instalou binário.

O que o River 3 Plus aceita, medido no aparelho do dono em 2026-09-04:

    $ upsrw river-office@127.0.0.1     → battery.charge.low (o "Low battery
                                          reminder" do aplicativo da EcoFlow)
    $ upscmd -l river-office@127.0.0.1 → driver.killpower, trancado por
                                          driver.flag.allow_killpower

Nada mais. Ligar e desligar tomadas NÃO existe por aqui, e não se inventa quadro
para um aparelho que alimenta os equipamentos de alguém.
"""

from __future__ import annotations

import socket
from dataclasses import dataclass

TEMPO_LIMITE = 5.0
# A conta de administração do nosso próprio servidor. Diferente da conta de
# leitura que o aplicativo da EcoFlow usa: aquela é `upsmon secondary` e não pode
# mandar nada no aparelho.
USUARIO_PADRAO = "riverbridge"


class RiverCmdError(Exception):
    """O servidor NUT recusou, ou não respondeu o que o protocolo promete."""


@dataclass
class Alvo:
    """Onde mora o aparelho e com que conta falamos com ele."""

    ups: str
    host: str = "127.0.0.1"
    porta: int = 3493
    usuario: str = USUARIO_PADRAO
    senha: str = ""


def _linha(arquivo) -> str:
    resposta = arquivo.readline()
    if not resposta:
        raise RiverCmdError("o servidor do no-break fechou a conversa sem responder")
    return resposta.strip()


def _fala(alvo: Alvo, comandos: list[str], *, conectar=socket.create_connection) -> list[str]:
    """Uma conversa curta: autentica, manda os comandos, devolve as respostas.

    Cada comando é respondido antes do próximo — o protocolo do NUT é síncrono, e
    encavalar pedidos foi o que já levou outras implementações a ler a resposta
    errada como se fosse a certa.
    """
    respostas: list[str] = []
    with conectar((alvo.host, alvo.porta), TEMPO_LIMITE) as sock:
        sock.settimeout(TEMPO_LIMITE)
        with sock.makefile("rw", encoding="utf-8", newline="\n") as arquivo:
            def manda(texto: str) -> str:
                arquivo.write(texto + "\n")
                arquivo.flush()
                return _linha(arquivo)

            if alvo.usuario:
                if not manda(f"USERNAME {alvo.usuario}").startswith("OK"):
                    raise RiverCmdError("o servidor do no-break recusou a nossa conta")
                if alvo.senha and not manda(f"PASSWORD {alvo.senha}").startswith("OK"):
                    raise RiverCmdError("o servidor do no-break recusou a nossa senha")
            for comando in comandos:
                respostas.append(manda(comando))
            arquivo.write("LOGOUT\n")
            arquivo.flush()
    return respostas


def ler_variavel(alvo: Alvo, nome: str, *, fala=_fala) -> str | None:
    """O valor de uma variável do aparelho, ou None quando ele não a publica."""
    resposta = fala(alvo, [f"GET VAR {alvo.ups} {nome}"])[0]
    if resposta.startswith("ERR"):
        return None
    # VAR <ups> <nome> "<valor>"
    partes = resposta.split('"')
    return partes[1] if len(partes) >= 2 else None


def gravar_variavel(alvo: Alvo, nome: str, valor: str, *, fala=_fala) -> None:
    """Grava e CONFERE lendo de volta: gravação que não volta não aconteceu."""
    resposta = fala(alvo, [f'SET VAR {alvo.ups} {nome} "{valor}"'])[0]
    if not resposta.startswith("OK"):
        raise RiverCmdError(_humano(resposta))
    de_volta = ler_variavel(alvo, nome, fala=fala)
    if de_volta is None:
        # Falha FECHADA: não conseguir conferir não é ter conseguido gravar. O
        # driver pode ter caído entre a escrita e a leitura, e a tela mostraria
        # sucesso com valor nenhum (revisão fria da 0.5.0).
        raise RiverCmdError("gravei, mas o aparelho não confirmou o valor novo — "
                            "não posso dizer que valeu")
    if de_volta.strip() != valor.strip():
        raise RiverCmdError(
            f"o aparelho aceitou o pedido e continua com {de_volta}")


def mandar_comando(alvo: Alvo, comando: str, *, fala=_fala) -> None:
    resposta = fala(alvo, [f"INSTCMD {alvo.ups} {comando}"])[0]
    if not resposta.startswith("OK"):
        raise RiverCmdError(_humano(resposta))


def _humano(resposta: str) -> str:
    """A recusa do servidor em português, sem sigla na tela do dono."""
    codigo = resposta.replace("ERR", "").strip().split(" ")[0]
    return {
        "ACCESS-DENIED": "a nossa conta não tem permissão para isto no servidor do no-break",
        "UNKNOWN-UPS": "o servidor do no-break não conhece este aparelho",
        "CMD-NOT-SUPPORTED": "este aparelho não aceita esse comando",
        "VAR-NOT-SUPPORTED": "este aparelho não aceita mudar esse valor",
        "READONLY": "esse valor é somente leitura neste aparelho",
        "INVALID-VALUE": "valor fora do que o aparelho aceita",
        "PASSWORD-REQUIRED": "o servidor do no-break exige senha para esta conta",
        "DRIVER-NOT-CONNECTED": "o leitor do aparelho não está no ar",
        "INSTCMD-FAILED": "o aparelho recusou o comando",
        "SET-FAILED": "o aparelho recusou a mudança",
    }.get(codigo, "o servidor do no-break recusou o pedido")
