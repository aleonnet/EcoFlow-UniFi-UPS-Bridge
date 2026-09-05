"""O vocabulário fechado de eventos: tudo o que pode aparecer na linha do tempo.

Por que existe uma lista, e por que ela é FECHADA: a tela traduz cada nome de
evento para uma frase em português. Um nome que ela não conheça aparece cru —
`CABO_LARGADO_AUTOMATICO`, em maiúsculas com sublinhados — na linha do tempo de
quem usa o programa. Medido em 2026-09-05: **oito** dos quinze nomes apareciam
assim, e cinco deles já eram anteriores a esta versão.

A causa não era esquecimento: era não haver lugar nenhum que dissesse "estes são
todos os eventos". Cada emissor escrevia o nome na mão, e a tela tinha um `switch`
que terminava em "devolve o nome cru". Este módulo é esse lugar, e o teste que
compara esta lista com o que a tela conhece é o que impede a próxima vez.

Duas famílias:

- **os do serviço**, com nome inteiro aqui (energia, o River como aparelho, o cabo);
- **os de dispositivo**, que são um SUFIXO. O nome sai do prefixo do TIPO —
  `UDR7_` + `SHUTDOWN_SENT` —, porque o mesmo motor serve tipos diferentes e a
  tela traduz uma vez por tipo, não uma vez por aparelho.
"""

from __future__ import annotations

# -- energia (o laço de transições) -------------------------------------------
QUEDA = "POWER_LOSS"
ENERGIA_VOLTOU = "POWER_RESTORED"
BATERIA_BAIXA = "LOW_BATTERY"
SEM_COMUNICACAO = "COMM_LOST"
COMUNICACAO_VOLTOU = "COMM_RESTORED"

# -- o River como aparelho ----------------------------------------------------
RIVER_DESLIGANDO = "RIVER_DESLIGANDO"
RIVER_DESLIGADO = "RIVER_POWEROFF_SENT"
RIVER_DESLIGAR_FALHOU = "RIVER_DESLIGAR_FALHOU"
RIVER_DESLIGAR_RECUSADO = "RIVER_DESLIGAR_RECUSADO"
RIVER_TRAVA_ABERTA = "RIVER_KILLPOWER_FLAG_ABERTA"

# -- o cabo indo e voltando ---------------------------------------------------
CABO_LARGADO = "CABO_LARGADO_AUTOMATICO"
CABO_RETOMADO = "CABO_RETOMADO_AUTOMATICO"
CABO_MANTIDO = "CABO_MANTIDO_PROTECAO_ARMADA"

# -- o pacote foi para o Lixo (0.8.0) -----------------------------------------
PACOTE_NO_LIXO = "PACOTE_NO_LIXO_REMOVIDO"

DO_SERVICO: tuple[str, ...] = (
    QUEDA, ENERGIA_VOLTOU, BATERIA_BAIXA, SEM_COMUNICACAO, COMUNICACAO_VOLTOU,
    RIVER_DESLIGANDO, RIVER_DESLIGADO, RIVER_DESLIGAR_FALHOU,
    RIVER_DESLIGAR_RECUSADO, RIVER_TRAVA_ABERTA,
    CABO_LARGADO, CABO_RETOMADO, CABO_MANTIDO,
    PACOTE_NO_LIXO,
)

# -- de dispositivo: o SUFIXO, que ganha o prefixo do tipo ---------------------
DE_DISPOSITIVO: tuple[str, ...] = (
    "SHUTDOWN_DRYRUN", "SHUTDOWN_SENT", "SHUTDOWN_FAILED", "SHUTDOWN_BLOCKED",
    "PROTECTION_REARMED", "PROTECTION_BLIND", "ARMED", "DISARMED",
    "WOL_SENT", "WOL_DRYRUN",
    # As ordens que o dono dá à mão, pela tela ou pelo Home Assistant (0.7.0).
    "ORDEM_ENVIADA", "ORDEM_FALHOU", "ORDEM_RECUSADA",
)
# Religar pela rede só existe em tipo que tenha onde guardar o endereço da placa.
# Listar esses dois para todo tipo faria a tela ser cobrada por uma frase que
# nenhum aparelho jamais emitiria.
SO_COM_ENDERECO_DE_PLACA = ("WOL_SENT", "WOL_DRYRUN")


def sufixos_do_tipo(tem_endereco_de_placa: bool) -> tuple[str, ...]:
    return tuple(s for s in DE_DISPOSITIVO
                 if tem_endereco_de_placa or s not in SO_COM_ENDERECO_DE_PLACA)


def por_tipo() -> dict[str, list[str]]:
    """Os nomes que CADA tipo instalado pode emitir, com o prefixo dele.

    Sai do registro de tipos, não de uma lista à parte: um tipo novo entra aqui
    sozinho, e a tela é cobrada pelas frases dele no mesmo instante.
    """
    from .plugins import TYPES

    saida: dict[str, list[str]] = {}
    for cls in TYPES.values():
        tem_placa = any(f.name == "wol_mac" for f in cls.fields)
        saida[cls.event_prefix] = [f"{cls.event_prefix}{s}"
                                   for s in sufixos_do_tipo(tem_placa)]
    return saida


def todos() -> list[str]:
    """Todo nome que pode chegar à tela."""
    nomes = list(DO_SERVICO)
    for lista in por_tipo().values():
        nomes += lista
    return sorted(nomes)
