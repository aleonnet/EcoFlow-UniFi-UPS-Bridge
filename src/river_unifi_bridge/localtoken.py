"""Onde mora o estado do serviço, e a ficha com que o app fala com ele (§7A.3).

Arquivo 0600 em vez do Chaveiro — exceção registrada à §15 da especificação: o
serviço roda sem ninguém logado, onde o Chaveiro pode estar trancado, e a ficha é
local, só de laço interno e refeita à vontade.

**Duas pastas de estado, e o motivo de cada uma.** Quem instala pela linha de
comando roda o serviço como o próprio usuário, e o estado fica na pasta dele.
Quem instala arrastando o App roda o serviço como serviço de sistema (root), e aí
o estado fica em `/Library/Application Support/…` — estado de serviço de sistema
não mora na pasta de um usuário. As duas convivem, e `RUB_STATE_DIR` manda sobre
as duas (é o que o lançador dentro do pacote define, e o que deixa os testes
herméticos).

A ficha da API é o ÚNICO arquivo que atravessa essa fronteira: o app roda como o
dono e precisa lê-la para falar com um serviço que roda como root. Ela nasce
0640 do grupo `admin`, e só ela — chave privada, senhas e histórico continuam
0600, invisíveis para qualquer outra conta.
"""

from __future__ import annotations

import grp
import os
import secrets
import shutil

TOKEN_FILENAME = "ui-api.token"
PASTA_DO_USUARIO = "~/Library/Application Support/river-unifi-bridge"
PASTA_DO_SISTEMA = "/Library/Application Support/river-unifi-bridge"
# O grupo dos administradores do macOS. É o que o app usa para ler a ficha de um
# serviço que roda como root.
GRUPO_ADMIN = "admin"


def state_dir() -> str:
    override = os.environ.get("RUB_STATE_DIR")
    if override:
        return override
    if os.geteuid() == 0:
        return PASTA_DO_SISTEMA
    return os.path.expanduser(PASTA_DO_USUARIO)


def _gid_admin() -> int | None:
    try:
        return grp.getgrnam(GRUPO_ADMIN).gr_gid
    except KeyError:
        return None


def _abrir_a_pasta_para_o_dono(directory: str) -> None:
    """Rodando como root, o dono precisa ATRAVESSAR a pasta para ler a ficha.

    Só atravessar: 0750 dá caminho, não dá lista de conteúdo a estranhos, e cada
    arquivo lá dentro continua com a permissão dele.
    """
    if os.geteuid() != 0:
        return
    gid = _gid_admin()
    if gid is None:
        return
    try:
        os.chown(directory, 0, gid)
        os.chmod(directory, 0o750)
    except OSError:
        pass


def get_or_create_token(directory: str | None = None) -> str:
    directory = directory or state_dir()
    os.makedirs(directory, mode=0o700, exist_ok=True)
    _abrir_a_pasta_para_o_dono(directory)
    path = os.path.join(directory, TOKEN_FILENAME)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            token = fh.read().strip()
        if token:
            _liberar_a_ficha(path)
            return token
    token = secrets.token_urlsafe(32)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(token + "\n")
    _liberar_a_ficha(path)
    return token


def _liberar_a_ficha(path: str) -> None:
    """0640 do grupo `admin` quando somos root; 0600 no resto do tempo.

    Sem isto, o app (que roda como o dono) não conseguia ler a ficha de um
    serviço que roda como root — e a tela dizia "serviço parado" com o serviço
    no ar.
    """
    if os.geteuid() != 0:
        return
    gid = _gid_admin()
    if gid is None:
        return
    try:
        os.chown(path, 0, gid)
        os.chmod(path, 0o640)
    except OSError:
        pass


def estados_de_usuario(raiz: str = "/Users") -> list[str]:
    """As pastas de estado que existem nas casas dos usuários desta máquina."""
    achados = []
    try:
        casas = sorted(os.listdir(raiz))
    except OSError:
        return achados
    for casa in casas:
        if casa.startswith("."):
            continue
        caminho = os.path.join(raiz, casa, "Library/Application Support/river-unifi-bridge")
        if os.path.isdir(caminho):
            achados.append(caminho)
    return achados


def migrar_estado_uma_vez(destino: str | None = None, *, log=None,
                          origens=None) -> str | None:
    """Traz o estado de uma instalação anterior para a pasta do sistema, uma vez.

    Trocar a forma de instalar não pode custar a chave do console, o histórico
    nem a lista de dispositivos. A cópia acontece **só** quando o destino está
    vazio e existe **exatamente uma** origem: com duas casas de usuário, não há
    como saber qual é a boa, e adivinhar seria pior que não copiar. O original
    fica onde está, intocado — voltar atrás continua possível.
    """
    log = log or (lambda *_a, **_k: None)
    destino = destino or state_dir()
    if destino != PASTA_DO_SISTEMA:
        return None
    # "Vazio" aqui é medido pelo ESTADO, não pela pasta: o lançador dentro do
    # pacote cria a pasta e copia a configuração de exemplo antes de o Python
    # rodar, então uma pasta com arquivo dentro não quer dizer instalação
    # anterior. O que diz é a ficha da API ou a lista de dispositivos.
    if any(os.path.exists(os.path.join(destino, nome))
           for nome in (TOKEN_FILENAME, "devices.json")):
        return None
    candidatas = estados_de_usuario() if origens is None else list(origens)
    if not candidatas:
        return None
    if len(candidatas) > 1:
        log("WARN", "estado_nao_migrado",
            reason="há mais de uma instalação anterior nesta máquina e não dá para "
                   "saber qual é a boa", candidatas=candidatas)
        return None
    origem = candidatas[0]
    os.makedirs(destino, mode=0o700, exist_ok=True)
    for nome in sorted(os.listdir(origem)):
        de, para = os.path.join(origem, nome), os.path.join(destino, nome)
        if os.path.isdir(de):
            continue
        # A configuração é a EXCEÇÃO: o lançador acabou de copiar o exemplo para
        # cá, e o exemplo não tem os limiares, as travas nem o número de série que
        # o dono ajustou. A dele vence.
        if os.path.exists(para) and nome != "bridge.env":
            continue
        shutil.copy2(de, para)
    _abrir_a_pasta_para_o_dono(destino)
    log("INFO", "estado_migrado", de=origem, para=destino)
    return origem


if __name__ == "__main__":                      # pragma: no cover — chamado pelo lançador
    # Chamado por `Contents/Resources/servico.sh` ANTES de ele criar a
    # configuração de exemplo: é a única janela em que dá para trazer a
    # configuração de uma instalação anterior sem o exemplo já estar no lugar.
    import json
    import sys

    def _diga(nivel: str, evento: str, **payload) -> None:
        print(json.dumps({"level": nivel, "event": evento, **payload}, ensure_ascii=False),
              flush=True)

    migrar_estado_uma_vez(sys.argv[1] if len(sys.argv) > 1 else None, log=_diga)
