"""A cerca dos testes que sobem o serviço DE VERDADE.

Os testes desta pasta não são herméticos por natureza: eles lançam o daemon como
processo, contra um servidor de no-break de mentira. O que eles NÃO podem fazer é
tocar na instalação real da máquina de quem os roda.

Isto aqui existe porque aconteceu. Em 2026-09-05 o serviço passou a escrever a
configuração do NUT quando ela falta — é o que faz a instalação por arrastar
funcionar — e, como esta pasta não tinha `conftest.py`, o daemon lançado pelo
teste criou `ups.conf`, `upsd.conf`, `nut.conf` e `upsd.users` em
`/opt/homebrew/etc/nut` do MacBook do dono.

`ambiente_do_daemon()` é a única forma de montar o ambiente de um daemon de
teste, e `test_cercas.py` reprova quem lançar o serviço sem ela.
"""

from __future__ import annotations

import pathlib


def ambiente_do_daemon(tmp_path: pathlib.Path, **extra: str) -> dict[str, str]:
    """O ambiente de um daemon de teste: tudo o que ele escreve fica em `tmp_path`.

    As três variáveis não são detalhe — cada uma tapa um caminho pelo qual o
    serviço escreve fora dele mesmo: o estado (chaves e senhas), a configuração
    do NUT, e os soquetes que ele publica.
    """
    raiz = pathlib.Path(__file__).resolve().parents[2]
    base: dict[str, str] = {
        "PATH": "/usr/bin:/bin",
        "PYTHONPATH": str(raiz / "src"),
        "RUB_STATE_DIR": str(tmp_path / "state"),
        "RUB_NUT_ETC": str(tmp_path / "nutetc"),
        "RUB_NUT_STATE": str(tmp_path / "nutstate"),
    }
    for pasta in ("state", "nutetc", "nutstate"):
        (tmp_path / pasta).mkdir(parents=True, exist_ok=True)
    base.update(extra)
    return base
