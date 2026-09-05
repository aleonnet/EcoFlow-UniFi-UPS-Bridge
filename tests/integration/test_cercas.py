"""Nenhum teste desta pasta lança o serviço sem a cerca do ambiente.

É uma cerca de FORMA, e ela existe porque a de comportamento chegou tarde: o
daemon de um teste escreveu na configuração real do NUT da máquina do dono
(2026-09-05). Um teste novo que esqueça o ambiente isolado reprova aqui, antes
de escrever em lugar nenhum.
"""

from __future__ import annotations

import pathlib
import re

PASTA = pathlib.Path(__file__).parent


def test_todo_daemon_de_teste_usa_o_ambiente_isolado():
    padrao = re.compile(r"river_unifi_bridge\.service")
    faltando: list[str] = []
    for arquivo in sorted(PASTA.glob("test_*.py")):
        texto = arquivo.read_text(encoding="utf-8")
        for pedaco in texto.split("subprocess.Popen(")[1:]:
            cabeca = pedaco[:600]
            if not padrao.search(cabeca):
                continue                      # não é o serviço (é o simulador)
            if "ambiente_do_daemon(" not in cabeca:
                faltando.append(arquivo.name)
    assert not faltando, (
        "serviço lançado sem ambiente_do_daemon() — escreveria na instalação real "
        f"de quem roda a suíte: {sorted(set(faltando))}")
