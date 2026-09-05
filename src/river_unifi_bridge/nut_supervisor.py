"""O serviço passa a cuidar dos dois processos do NUT, em vez de terceirizá-los.

Por que isto existe, medido no Mac mini em 2026-09-04:

1. **Registrados como programa do usuário, eles não sobem sem alguém logado.** O mini
   reiniciou às 01h17, ninguém logou, e o River ficou sem vigia por uma hora.
2. **Registrados como serviço do sistema, só o root os pausa** — e pausar é
   necessário para emprestar o cabo ao aplicativo da EcoFlow. Isso obrigaria a
   senha do dono a cada vez.
3. **O aplicativo da EcoFlow mata leitores pelo NOME do processo**: o pacote dele
   traz `pkill -9 usbhid-ups` e `pkill -9 upsd`, rodados como root ao abrir.

Como filhos do nosso serviço, os três problemas somem: sobem quando o serviço
sobe (que é do sistema, logo no boot), param e voltam sem root, e nascem com nome
próprio (`river-bridge-ups`), fora da mira daquele `pkill`.

O nome próprio é dado por `exec -a` do shell, que escolhe o `argv[0]` do processo:
medido em 2026-09-04, `ps -o comm=` mostra `river-bridge-ups` e o `pkill` pelo nome
de fábrica não o alcança. É o caminho portátil no macOS sem reescrever o binário.
"""

from __future__ import annotations

import os
import pwd
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass

# Nomes próprios. Não são enfeite: é o que tira os nossos processos da mira do
# `pkill -9 usbhid-ups` que o aplicativo do fabricante executa como root.
NOME_DRIVER = "river-bridge-ups"
NOME_SERVIDOR = "river-bridge-upsd"

# Onde o Homebrew instala o NUT no Apple Silicon. Caminho estável (`opt`), não a
# pasta com número de versão, que muda a cada atualização.
#
# A variável de ambiente é a MESMA costura que o instalador já respeitava. Sem ela
# aqui, uma cena do portão que sobe o serviço de verdade lançava o `usbhid-ups`
# REAL contra o River do dono e tomava o cabo dele — medido na revisão fria da
# 0.5.0, com os processos registrados no diário do daemon descartável.
PREFIXO_PADRAO = "/opt/homebrew/opt/nut"

# Tempo que damos ao processo para sair com educação antes do sinal duro.
ESPERA_TERMINO = 5.0
# Quanto esperar entre subir o driver e subir o servidor: o servidor procura o
# soquete do driver e reclama se ele ainda não existe.
ATRASO_SERVIDOR = 2.0
# Recuo entre tentativas depois de um processo cair, em segundos.
RECUO_BASE = 2.0
RECUO_MAXIMO = 60.0


def _usuario_do_processo() -> str:
    """Quem somos, pelo sistema — nunca pela variável de ambiente.

    Um serviço do sistema pode subir sem `USER` no ambiente, e a queda para
    "nobody" fazia o leitor nascer com o dono errado (e a limpeza de órfão do
    instalador, que filtra pelo nome do usuário, deixava de casar).
    """
    try:
        return pwd.getpwuid(os.geteuid()).pw_name
    except KeyError:                                   # uid sem entrada: raro, mas existe
        return os.environ.get("USER") or "nobody"


@dataclass
class EstadoDoCabo:
    """Quem está com o River, em português, para a tela."""

    lendo: bool
    pausado_pelo_dono: bool
    motivo: str | None = None

    def to_dict(self) -> dict:
        return {
            "lendo": self.lendo,
            "pausado": self.pausado_pelo_dono,
            "motivo": self.motivo,
        }


class NutSupervisor:
    """Sobe, vigia e para o driver e o servidor do NUT como processos filhos."""

    def __init__(self, ups: str, *, usuario: str | None = None,
                 prefixo: str | None = None, log=None,
                 spawn=subprocess.Popen, clock=time.monotonic) -> None:
        self._ups = ups
        self._usuario = usuario or _usuario_do_processo()
        self._prefixo = prefixo or os.environ.get("RUB_NUT_PREFIX") or PREFIXO_PADRAO
        self._log = log or (lambda *_a, **_k: None)
        self._spawn = spawn
        self._clock = clock
        self._lock = threading.Lock()
        self._driver: subprocess.Popen | None = None
        self._servidor: subprocess.Popen | None = None
        self._pausado = False
        # Recuo: um leitor que não sobe (cabo solto, aparelho desligado) não pode
        # virar tempestade de processos. Cada falha seguida espera mais, até o teto.
        self._falhas = 0
        self._proxima_tentativa = float("-inf")

    # -- o que existe na máquina -------------------------------------------
    @property
    def disponivel(self) -> bool:
        """Há NUT instalado para supervisionar?"""
        return bool(shutil.which(f"{self._prefixo}/bin/usbhid-ups")
                    or os.path.exists(f"{self._prefixo}/bin/usbhid-ups"))

    def _comando(self, nome: str, binario: str, *args: str) -> list[str]:
        # `exec -a` roda pelo shell: é a forma portátil de escolher o argv[0].
        partes = " ".join(f"'{a}'" for a in args)
        return ["/bin/sh", "-c", f"exec -a {nome} '{binario}' {partes}"]

    # -- ciclo de vida ------------------------------------------------------
    def iniciar(self) -> None:
        with self._lock:
            self._pausado = False
            self._subir_se_preciso()

    def _subir_se_preciso(self) -> None:
        if not self.disponivel:
            self._log("WARN", "nut_ausente", prefixo=self._prefixo)
            return
        if self._clock() < self._proxima_tentativa:
            return
        if self._driver is None or self._driver.poll() is not None:
            self._driver = self._spawn(
                self._comando(NOME_DRIVER, f"{self._prefixo}/bin/usbhid-ups",
                              "-a", self._ups, "-u", self._usuario, "-F"),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            self._log("INFO", "nut_driver_iniciado", pid=self._driver.pid, ups=self._ups)
            # O servidor procura o soquete do driver e reclama se ele ainda não
            # existe — então ele sobe na volta SEGUINTE do laço. Dormir aqui
            # atrasava em 2 s cada ciclo da vigilância, justamente quando o
            # leitor está falhando (revisão fria da 0.5.0).
            return
        if self._servidor is None or self._servidor.poll() is not None:
            self._servidor = self._spawn(
                self._comando(NOME_SERVIDOR, f"{self._prefixo}/sbin/upsd",
                              "-u", self._usuario, "-F"),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            self._log("INFO", "nut_servidor_iniciado", pid=self._servidor.pid)

    def vigiar(self) -> None:
        """Chamada a cada ciclo do laço: filho que morreu volta, salvo se pausado.

        Um leitor de no-break que morre e não volta é pior que um que nunca
        subiu: a tela continua com a última leitura e ninguém avisa.
        """
        with self._lock:
            if self._pausado:
                return
            caiu = False
            for nome in ("driver", "servidor"):
                proc = self._driver if nome == "driver" else self._servidor
                rc = proc.poll() if proc is not None else None
                if proc is None or rc is None:
                    continue
                self._log("WARN", "nut_processo_caiu", qual=nome, rc=rc)
                # Soltar o morto é o que faz o recuo AVANÇAR. Guardando o
                # cadáver, cada volta o via morrer de novo, contava outra falha
                # e empurrava a próxima tentativa para depois do relógio — o
                # leitor nunca mais voltava.
                if nome == "driver":
                    self._driver = None
                else:
                    self._servidor = None
                caiu = True
            if caiu:
                # Uma falha por volta, não uma por processo: os dois caem juntos
                # quando o cabo sai, e isso é UM problema, não dois.
                self._falhas += 1
                espera = min(RECUO_MAXIMO, RECUO_BASE * (2 ** min(self._falhas, 6)))
                self._proxima_tentativa = self._clock() + espera
            elif self._de_pe():
                # O recuo zera quando o par SOBREVIVEU a uma volta inteira, não
                # quando foi lançado. Zerando no lançamento, um servidor que
                # morria sempre (outro `upsd` já na porta) reiniciava o contador
                # a cada volta e o recuo nunca crescia: 451 lançamentos por hora,
                # medido na revisão fria da 0.5.0.
                self._falhas = 0
                self._proxima_tentativa = float("-inf")
            self._subir_se_preciso()

    def _de_pe(self) -> bool:
        """Os dois processos vivos agora."""
        return (self._driver is not None and self._driver.poll() is None
                and self._servidor is not None and self._servidor.poll() is None)

    def _parar(self, proc: subprocess.Popen | None) -> None:
        if proc is None or proc.poll() is not None:
            return
        try:
            proc.terminate()
        except OSError:
            return
        limite = self._clock() + ESPERA_TERMINO
        while self._clock() < limite:
            if proc.poll() is not None:
                return
            time.sleep(0.1)
        try:
            proc.kill()            # não saiu com educação: sai assim mesmo
        except OSError:
            pass

    def pausar(self, motivo: str = "pedido do dono") -> EstadoDoCabo:
        """Larga o cabo. O aplicativo do fabricante consegue abrir o aparelho."""
        with self._lock:
            self._pausado = True
            self._parar(self._servidor)
            self._parar(self._driver)
            self._servidor = None
            self._driver = None
            self._log("WARN", "cabo_liberado", motivo=motivo)
            return EstadoDoCabo(lendo=False, pausado_pelo_dono=True, motivo=motivo)

    def retomar(self) -> EstadoDoCabo:
        with self._lock:
            self._pausado = False
            self._subir_se_preciso()
            vivo = self._driver is not None and self._driver.poll() is None
            self._log("INFO", "cabo_retomado", lendo=vivo)
            return EstadoDoCabo(lendo=vivo, pausado_pelo_dono=False,
                                motivo=None if vivo else "o leitor não subiu")

    def reiniciar_servidor(self) -> None:
        """Derruba o servidor do no-break; a vigilância o traz de volta.

        Serve para uma coisa só: o `ups.conf` mudou (um dispositivo entrou ou
        saiu pela tela) e o servidor precisa lê-lo de novo. O leitor de fábrica
        NÃO é tocado — ele é quem segura o cabo do River, e derrubá-lo por causa
        de uma linha de configuração deixaria a proteção cega por segundos.
        """
        with self._lock:
            if self._pausado:
                return
            self._parar(self._servidor)
            self._servidor = None
            self._log("INFO", "nut_servidor_reiniciando", motivo="configuração mudou")

    def encerrar(self) -> None:
        """Serviço saindo: leva os filhos junto, para não deixar órfão com o cabo."""
        with self._lock:
            self._parar(self._servidor)
            self._parar(self._driver)
            self._servidor = None
            self._driver = None

    def estado(self) -> EstadoDoCabo:
        with self._lock:
            if self._pausado:
                return EstadoDoCabo(lendo=False, pausado_pelo_dono=True,
                                    motivo="liberado para o aplicativo da EcoFlow")
            vivo = self._driver is not None and self._driver.poll() is None
            if vivo:
                return EstadoDoCabo(lendo=True, pausado_pelo_dono=False)
            if not self.disponivel:
                return EstadoDoCabo(lendo=False, pausado_pelo_dono=False,
                                    motivo="o NUT não está instalado nesta máquina")
            return EstadoDoCabo(lendo=False, pausado_pelo_dono=False,
                                motivo="o leitor não está no ar")
