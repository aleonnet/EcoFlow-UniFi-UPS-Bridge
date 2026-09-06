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
então DESREGISTRA o serviço — em dois passos, porque são duas coisas:

1. O registro nos Itens de Início de Sessão (o interruptor "River Bridge" nos
   Ajustes do Sistema) só é desfeito por `SMAppService.unregister()`; a Apple é
   literal: "Unregisters the service so the system no longer launches it. …
   If the service is currently running it, the system terminates it." E só um
   processo DESTE pacote pode chamá-lo. Por isso o pacote traz
   `Contents/MacOS/river-bridge-servico`, que o serviço executa como o usuário
   da sessão (o registro é do usuário que autorizou). Até a 0.8.2 este passo
   não existia: o dono viu, no Mac mini em 2026-09-06, o programa no Lixo e o
   interruptor ainda ligado. O caminho do ajudante é o ATUAL do pacote (já no
   Lixo): é de lá que ele roda.
2. `launchctl bootout` para o processo de vez, para o caso de o ajudante não
   ter conseguido (o diário registra o que ele respondeu). Nasce em sessão nova
   por causa do manual do sistema (launchd.plist(5)): *"When a job dies,
   launchd kills any remaining processes with the same process group ID as
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

    def pacote_atual(self) -> str | None:
        """Onde o PACOTE está agora (`…/River Bridge.app`), ou None."""
        atual = self.caminho_atual()
        if not atual:
            return None
        return os.path.dirname(os.path.dirname(atual))   # Contents/Info.plist → .app

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


# O ajudante dentro do pacote.
AJUDANTE_DO_REGISTRO = os.path.join("Contents", "MacOS", "river-bridge-servico")


def usuario_da_console() -> int | None:
    """O uid de quem está na sessão gráfica (dono de /dev/console); None sem ninguém."""
    try:
        uid = os.stat("/dev/console").st_uid
    except OSError:
        return None
    return uid if uid > 0 else None


def comando_do_ajudante(pacote: str | None, uid: int | None) -> list[str] | None:
    """O argv que desfaz o registro nos Itens de Início de Sessão, ou None sem pacote.

    Como o usuário da sessão, porque o registro é dele (foi ele quem autorizou);
    o serviço é root e usa `launchctl asuser` + `sudo -u` para trocar de pele.
    Sem ninguém na sessão, tenta como root mesmo — e o diário diz o resultado.
    """
    if not pacote:
        return None
    ajudante = os.path.join(pacote, AJUDANTE_DO_REGISTRO)
    if not os.access(ajudante, os.X_OK):
        return None
    if uid is None:
        return [ajudante, "unregister"]
    return ["/bin/launchctl", "asuser", str(uid), "/usr/bin/sudo", "-u", f"#{uid}",
            ajudante, "unregister"]


def desregistrar(rotulo: str = ROTULO, *, pacote: str | None = None,
                 uid_da_console=usuario_da_console, spawn=subprocess.Popen,
                 log=None) -> None:
    """Desfaz o registro do serviço: o ajudante do pacote, e depois o launchd.

    O ajudante (`SMAppService.unregister()`) HERDA a saída deste serviço — que
    o launchd grava no diário — e escreve nela o que fez (`status=…`,
    `unregister=ok`): é a prova de que o interruptor nos Ajustes do Sistema se
    apagou, e ela entra no diário mesmo que o `unregister` derrube este serviço
    no instante seguinte ("if the service is currently running it, the system
    terminates it"). Por isso ninguém espera por ele: esperar era uma corrida
    contra o próprio SIGTERM, e uma árvore `launchctl asuser → sudo → ajudante`
    travada não se mata por um pid só (revisão fria da 0.8.3, duas rodadas).
    Nasce em sessão nova, como o `bootout`: o launchd mata o grupo de processos
    do job que morre (launchd.plist(5), `AbandonProcessGroup`), e os dois têm
    de sobreviver à saída deste serviço.
    """
    log = log or (lambda *_a, **_k: None)
    argv = comando_do_ajudante(pacote, uid_da_console())
    if argv is None:
        log("WARN", "ajudante_do_registro_ausente", pacote=pacote)
    else:
        log("INFO", "ajudante_do_registro_lancado", argv=argv)
        try:
            # stdout/stderr = None: HERDA os do serviço (o diário), de propósito.
            spawn(argv, stdout=None, stderr=None, start_new_session=True)
        except OSError as exc:
            log("WARN", "ajudante_do_registro_falhou", reason=str(exc)[:200])
    try:
        spawn(["/bin/launchctl", "bootout", f"system/{rotulo}"],
              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
              start_new_session=True)
    except OSError as exc:
        log("WARN", "desregistro_nao_lancado", reason=str(exc)[:200])


def retirar(state_dir: str | None, ups_conf: str, rotulo: str = ROTULO, *,
            pacote: str | None = None, apagar=apagar_tudo, desregistrar_=desregistrar,
            log=None) -> list[str]:
    """A remoção inteira, na ordem que importa: apagar primeiro, desregistrar depois.

    Ao contrário, o launchd derrubaria o serviço no meio da limpeza e a chave do
    console ficaria no disco com o pacote já no Lixo.
    """
    apagados = apagar(state_dir, ups_conf, log)
    desregistrar_(rotulo, pacote=pacote, log=log)
    return apagados
