"""A configuração do NUT: escrita uma vez, por quem chegar primeiro.

Por que este módulo existe, e é um defeito meu ter demorado: o caminho novo de
instalação — arrastar o programa para Aplicativos — **não roda o instalador de
linha de comando**. Medido em 2026-09-05: `/opt/homebrew/etc/nut/` tinha só os
arquivos `.sample` do Homebrew, e o pacote do App não escreve nenhum. Quem
instalasse arrastando teria um serviço que sobe, tenta abrir o leitor do no-break
e não consegue — porque não há `ups.conf` dizendo qual é o aparelho, nem conta
nenhuma no `upsd.users`. Nada funcionaria, e o programa não saberia dizer por quê.

A regra de sempre continua: **só se escreve o que não existe**. Quem configurou o
NUT à mão continua com a configuração dele, arquivo por arquivo.

E há uma fonte só. O instalador de linha de comando chama este mesmo módulo, em
vez de ter uma segunda cópia dos textos em `heredoc`: duas cópias divergem, e a
que divergisse seria descoberta na máquina de alguém.
"""

from __future__ import annotations

import grp
import os
import secrets

# Onde o Homebrew guarda a configuração do NUT no Apple Silicon.
ETC_PADRAO = "/opt/homebrew/etc/nut"
# O nome do aparelho de fábrica, quando ninguém escolhe outro.
APARELHO_PADRAO = "river-office"

# As fichas onde cada senha fica guardada, no diretório de estado.
FICHA_ADMIN = "nut-admin.token"
FICHA_HOME_ASSISTANT = "nut-homeassistant.token"


def secao_do_river(aparelho: str) -> str:
    """O leitor de fábrica, com os ajustes medidos no aparelho do dono.

    Cada linha tem motivo: `vendorid`/`productid` são os do River 3 Plus;
    `ignorelb` e `override.battery.runtime.low` existem porque o aviso de bateria
    baixa do NUT nunca dispara neste aparelho (issue NUT #3068), e quem decide o
    corte é a nossa política.
    """
    return (f"maxretry = 3\n\n"
            f"[{aparelho}]\n"
            f"    driver = usbhid-ups\n"
            f"    port = auto\n"
            f"    vendorid = 3746\n"
            f"    productid = ffff\n"
            f"    ignorelb\n"
            f"    override.battery.runtime.low = -1\n"
            f"    pollfreq = 1\n"
            f"    pollinterval = 2\n"
            f'    desc = "EcoFlow RIVER 3 Plus"\n')


CONTA_DE_LEITURA = """# Conta de LEITURA para outros programas desta máquina (o Power Manager da
# EcoFlow aceita apontar para um servidor NUT: Communication mode -> Remote).
# 'secondary' de propósito: acompanha e NÃO pode mandar o River desligar.
[powermanager]
    password = river-local
    upsmon secondary
"""

# As duas formas do `upsd.conf` que NÓS escrevemos: só esta máquina, ou a rede
# local (é o que o Home Assistant, noutra máquina, precisa). Qualquer outra
# forma é do dono, e o interruptor da tela não toca nela.
UPSD_CONF_LOCAL = "LISTEN 127.0.0.1 3493\n"
UPSD_CONF_REDE = "LISTEN 0.0.0.0 3493\n"
UPSD_CONF = UPSD_CONF_LOCAL
NUT_CONF = "MODE=standalone\n"


class ConfiguracaoDoDono(Exception):
    """O `upsd.conf` não é o que escrevemos: é do dono, e fica como está."""


def rede_aberta(etc: str = ETC_PADRAO) -> bool | None:
    """O servidor do no-break aceita a rede? `None` = o arquivo não é nosso, ou não existe."""
    try:
        with open(os.path.join(etc, "upsd.conf"), encoding="utf-8") as fh:
            conteudo = fh.read()
    except OSError:
        return None
    if conteudo == UPSD_CONF_REDE:
        return True
    if conteudo == UPSD_CONF_LOCAL:
        return False
    return None


def abrir_para_a_rede(etc: str, aberta: bool) -> bool:
    """Liga ou desliga a escuta na rede. Devolve se o arquivo mudou.

    Só mexe num `upsd.conf` que seja EXATAMENTE uma das duas formas nossas: o
    dono que configurou o servidor à mão continua com o arquivo dele, e a tela
    diz isso em vez de reescrever por cima. A linha `LISTEN` só é lida na
    partida do servidor (upsd.conf(5): "This parameter will only be read at
    startup"), então quem chama reinicia o servidor depois.
    """
    caminho = os.path.join(etc, "upsd.conf")
    atual = rede_aberta(etc)
    if atual is None:
        raise ConfiguracaoDoDono(
            f"{caminho} não é o arquivo que o serviço escreveu; ele é seu e fica como está")
    if atual == aberta:
        return False
    novo = UPSD_CONF_REDE if aberta else UPSD_CONF_LOCAL
    modo = os.stat(caminho).st_mode & 0o777
    descritor = os.open(caminho, os.O_WRONLY | os.O_TRUNC, modo)
    with os.fdopen(descritor, "w", encoding="utf-8") as fh:
        fh.write(novo)
    return True


def _gid_admin() -> int | None:
    try:
        return grp.getgrnam("admin").gr_gid
    except KeyError:
        return None


def _escreve_se_faltar(caminho: str, modo: int, conteudo: str, dono: str | None,
                       log) -> bool:
    if os.path.exists(caminho):
        return False
    os.makedirs(os.path.dirname(caminho) or ".", exist_ok=True)
    descritor = os.open(caminho, os.O_WRONLY | os.O_CREAT | os.O_EXCL, modo)
    with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
        arquivo.write(conteudo)
    os.chmod(caminho, modo)
    _dar_o_dono(caminho, dono)
    log("INFO", "nut_arquivo_criado", caminho=caminho)
    return True


def _dar_o_dono(caminho: str, dono: str | None) -> None:
    if dono is None or os.geteuid() != 0:
        return
    import pwd
    try:
        os.chown(caminho, pwd.getpwnam(dono).pw_uid, -1)
    except (KeyError, OSError):
        pass


def _senha_da_secao(arquivo: str, secao: str) -> str | None:
    """A senha que JÁ está no arquivo, quando a conta já existe.

    Gerar outra deixaria os dois lados divergentes — a conta com uma senha e a
    ficha com outra —, e o serviço ouviria "acesso negado" sem ninguém entender.
    """
    try:
        with open(arquivo, encoding="utf-8") as fh:
            dentro = False
            for linha in fh:
                bruta = linha.strip()
                if bruta.startswith("["):
                    dentro = bruta == f"[{secao}]"
                    continue
                if dentro and bruta.lower().startswith("password"):
                    return bruta.split("=", 1)[1].strip().strip('"')
    except OSError:
        return None
    return None


def garantir_conta(etc: str, secao: str, permissoes: str, proposito: str,
                   ficha: str, state_dir: str, dono: str | None, log) -> bool:
    """Uma conta no `upsd.users` e a ficha com a senha dela. Devolve se mudou."""
    arquivo = os.path.join(etc, "upsd.users")
    senha = _senha_da_secao(arquivo, secao)
    mudou = False
    if senha is None:
        senha = secrets.token_urlsafe(24).replace("-", "").replace("_", "")[:32]
        with open(arquivo, "a", encoding="utf-8") as fh:
            fh.write(f"\n# {proposito}\n# Senha gerada na instalação; ela também está em {ficha}.\n"
                     f"[{secao}]\n    password = {senha}\n{permissoes}\n")
        os.chmod(arquivo, 0o640)
        _dar_o_dono(arquivo, dono)
        log("INFO", "nut_conta_criada", conta=secao)
        mudou = True
    caminho_da_ficha = os.path.join(state_dir, ficha)
    atual = None
    try:
        with open(caminho_da_ficha, encoding="utf-8") as fh:
            atual = fh.read().strip()
    except OSError:
        pass
    if atual != senha:
        os.makedirs(state_dir, mode=0o700, exist_ok=True)
        descritor = os.open(caminho_da_ficha, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descritor, "w", encoding="utf-8") as fh:
            fh.write(senha)
        mudou = True
    _abrir_a_ficha_para_o_dono(caminho_da_ficha, ficha)
    return mudou


def _abrir_a_ficha_para_o_dono(caminho: str, ficha: str) -> None:
    """A senha do Home Assistant é a única que a TELA mostra.

    Rodando como serviço de sistema, ela nasceria só do root e o programa — que
    roda como o dono — não conseguiria lê-la para mostrar. As outras ficam 0600:
    ninguém precisa vê-las.
    """
    if ficha != FICHA_HOME_ASSISTANT or os.geteuid() != 0:
        return
    gid = _gid_admin()
    if gid is None:
        return
    try:
        os.chown(caminho, 0, gid)
        os.chmod(caminho, 0o640)
    except OSError:
        pass


def garantir_configuracao(*, etc: str = ETC_PADRAO, aparelho: str = APARELHO_PADRAO,
                          state_dir: str, dono: str | None = None, log=None) -> list[str]:
    """Escreve o que faltar. Devolve o que foi criado, para o registro."""
    log = log or (lambda *_a, **_k: None)
    if not os.path.isdir(os.path.dirname(etc) or "/"):
        log("WARN", "nut_sem_pasta_de_configuracao", pasta=etc)
        return []
    os.makedirs(etc, exist_ok=True)
    criados: list[str] = []
    if _escreve_se_faltar(os.path.join(etc, "ups.conf"), 0o644,
                          secao_do_river(aparelho), dono, log):
        criados.append("ups.conf")
    if _escreve_se_faltar(os.path.join(etc, "upsd.conf"), 0o640, UPSD_CONF, dono, log):
        criados.append("upsd.conf")
    if _escreve_se_faltar(os.path.join(etc, "nut.conf"), 0o644, NUT_CONF, dono, log):
        criados.append("nut.conf")
    if _escreve_se_faltar(os.path.join(etc, "upsd.users"), 0o640,
                          CONTA_DE_LEITURA, dono, log):
        criados.append("upsd.users")
    if garantir_conta(etc, "riverbridge", "    actions = SET\n    instcmds = ALL",
                      "Conta com que o SERVIÇO manda no aparelho (lembrete de bateria "
                      "baixa, desligamento). Não a use noutro programa.",
                      FICHA_ADMIN, state_dir, dono, log):
        criados.append("conta riverbridge")
    if garantir_conta(etc, "homeassistant", "    instcmds = ALL",
                      "Conta do Home Assistant: acompanha o River e pode mandar as "
                      "ordens que a ponte publica. Cada ordem passa pelas mesmas "
                      "travas da tela do aplicativo.",
                      FICHA_HOME_ASSISTANT, state_dir, dono, log):
        criados.append("conta homeassistant")
    return criados


if __name__ == "__main__":                      # pragma: no cover — chamado pelo instalador
    import json
    import sys

    def _diga(nivel: str, evento: str, **payload) -> None:
        print(json.dumps({"level": nivel, "event": evento, **payload}, ensure_ascii=False),
              flush=True)

    etc = os.environ.get("RUB_NUT_ETC") or ETC_PADRAO
    aparelho = sys.argv[1] if len(sys.argv) > 1 else APARELHO_PADRAO
    estado = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("RUB_STATE_DIR", "")
    dono = sys.argv[3] if len(sys.argv) > 3 else None
    feitos = garantir_configuracao(etc=etc, aparelho=aparelho, state_dir=estado,
                                   dono=dono, log=_diga)
    print(json.dumps({"criados": feitos}, ensure_ascii=False))
