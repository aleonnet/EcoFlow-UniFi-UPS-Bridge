"""O serviço se retira sozinho quando o pacote vai para o Lixo.

A ordem do dono (2026-09-05): *"um mover para lixeira que remove tudo"*. O que o
macOS faz sozinho quando um pacote vai para o Lixo é NADA disto — o serviço
continua registrado, o processo continua vivo (rodando de dentro do Lixo, visto
pelo dono no Mac mini em 2026-09-05), e a chave do console, as senhas e o
histórico continuam no disco. Então quem faz é o próprio serviço.

Como ele percebe: um descritor aberto no `Info.plist` do próprio pacote, e a
pergunta `F_GETPATH` ao sistema — "qual é o caminho ATUAL deste arquivo?". O
caminho acompanha o `mv` do Finder; medido nesta máquina em 2026-09-05 e provado
pelos testes com um `mv` de verdade. Quando o caminho passa a conter `/.Trash/`,
o pacote foi para o Lixo.

Duas armadilhas, as duas achadas pela revisão fria do plano:

1. **Atualizar não é jogar fora.** Substituir o pacote pelo Finder pode pôr o
   antigo no Lixo enquanto o novo ocupa o caminho original. Por isso a remoção
   exige TAMBÉM que não exista mais pacote no caminho original. E "o arquivo
   sumiu" não dispara nada: apagado não é Lixo.
2. **Relançado de dentro do Lixo** (o launchd pode fazê-lo num reinício, antes de
   o Lixo ser esvaziado), o caminho gravado na partida já é o do Lixo e a regra
   acima não veria diferença. Então, na partida, o caminho conter `/.Trash/`
   basta: remove na primeira volta.

O que a remoção faz, nesta ordem: apaga o diretório de estado inteiro (chave,
senhas, histórico, dispositivos, a configuração e o estado do NUT), tira o
nosso trecho do `ups.conf` do Homebrew (caminho da linha de comando), e só
então pede ao launchd para desregistrar o serviço. O `launchctl` nasce em
sessão nova por causa do manual do sistema (launchd.plist(5)): *"When a job
dies, launchd kills any remaining processes with the same process group ID as
the job"* — no mesmo grupo, ele morreria junto com o serviço antes de agir.

O diário em `/Library/Logs` fica de propósito: é a única pista de por que o
serviço sumiu.
"""

from __future__ import annotations

import fcntl
import os
import shutil
import subprocess

from . import nut_conf

# Os pedaços de caminho que só existem dentro de um Lixo do macOS: o do usuário
# no volume de partida (`~/.Trash/`) e o de um volume externo (`/.Trashes/<uid>/`).
MARCAS_DO_LIXO = ("/.Trash/", "/.Trashes/")


def no_lixo(caminho: str | None) -> bool:
    return bool(caminho) and any(marca in caminho for marca in MARCAS_DO_LIXO)
# O rótulo do serviço no launchd, o mesmo do plist dentro do pacote.
ROTULO = "com.river.unifi-bridge"
_TAMANHO_DO_CAMINHO = 1024


class VigiaDoPacote:
    """Vigia onde o pacote está, pelo descritor aberto no `Info.plist` dele."""

    def __init__(self, pacote: str) -> None:
        self.original = os.path.abspath(pacote)
        self._fd = os.open(os.path.join(self.original, "Contents", "Info.plist"), os.O_RDONLY)

    def caminho_atual(self) -> str | None:
        """Onde o `Info.plist` está AGORA, ou None quando o sistema não sabe."""
        try:
            bruto = fcntl.fcntl(self._fd, fcntl.F_GETPATH, b"\0" * _TAMANHO_DO_CAMINHO)
        except OSError:
            return None
        return bruto.rstrip(b"\0").decode("utf-8", "replace") or None

    def deve_remover(self) -> bool:
        # (a) Relançado de dentro do Lixo: o caminho da partida já diz tudo.
        if no_lixo(self.original):
            return True
        # (b) Foi para o Lixo durante a vida — e ninguém ocupou o lugar dele.
        atual = self.caminho_atual()
        if not no_lixo(atual):
            return False
        return not os.path.isdir(self.original)

    def fechar(self) -> None:
        try:
            os.close(self._fd)
        except OSError:
            pass


def apagar_tudo(state_dir: str | None, ups_conf: str, log=None) -> list[str]:
    """Tudo o que o serviço criou nesta máquina. Devolve o que saiu, para o registro.

    O diretório de estado sai INTEIRO — arquivos e pastas: chave do console,
    senhas das contas do no-break, histórico, dispositivos, a configuração do
    serviço, e (no pacote) a configuração e o estado do NUT. Deixar para trás um
    arquivo com as travas do dono seria a próxima instalação herdar decisões que
    ninguém tomou de novo. O trecho no `ups.conf` do Homebrew (instalação pela
    linha de comando) sai pelo mesmo motivo de sempre: o servidor do no-break
    procuraria para sempre soquetes de um driver que não existe mais.
    """
    log = log or (lambda *_a, **_k: None)
    apagados: list[str] = []
    if state_dir and os.path.isdir(state_dir):
        for nome in sorted(os.listdir(state_dir)):
            caminho = os.path.join(state_dir, nome)
            try:
                if os.path.isdir(caminho) and not os.path.islink(caminho):
                    shutil.rmtree(caminho)
                else:
                    os.remove(caminho)
                apagados.append(nome)
            except OSError as exc:
                log("WARN", "estado_nao_apagado", arquivo=nome, reason=str(exc)[:200])
        try:
            os.rmdir(state_dir)
        except OSError:
            pass                           # sobrou algo que não era nosso: fica
    try:
        if nut_conf.remover(ups_conf):
            apagados.append("ups.conf (o nosso trecho)")
    except (nut_conf.ConfMalformada, OSError) as exc:
        log("WARN", "ups_conf_nao_limpo", reason=str(exc)[:200])
    return apagados


def desregistrar(rotulo: str = ROTULO, *, spawn=subprocess.Popen, log=None) -> None:
    """Pede ao launchd para desregistrar o serviço — sem esperar.

    Em sessão nova de propósito: o serviço vai sair logo em seguida, e o launchd
    mata o grupo de processos do job que morre (launchd.plist(5),
    `AbandonProcessGroup`). No mesmo grupo, o `launchctl` morreria antes de agir.
    """
    log = log or (lambda *_a, **_k: None)
    try:
        spawn(["/bin/launchctl", "bootout", f"system/{rotulo}"],
              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
              start_new_session=True)
    except OSError as exc:
        log("WARN", "desregistro_nao_lancado", reason=str(exc)[:200])


def retirar(state_dir: str | None, ups_conf: str, rotulo: str = ROTULO, *,
            apagar=apagar_tudo, desregistrar_=desregistrar, log=None) -> list[str]:
    """A remoção inteira, na ordem que importa: apagar primeiro, desregistrar depois.

    Ao contrário, o launchd derrubaria o serviço no meio da limpeza e a chave do
    console ficaria no disco com o pacote já no Lixo.
    """
    apagados = apagar(state_dir, ups_conf, log)
    desregistrar_(rotulo, log=log)
    return apagados
