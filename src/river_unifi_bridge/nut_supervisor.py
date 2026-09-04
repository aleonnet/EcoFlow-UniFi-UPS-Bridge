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

O nome próprio é dado por `exec -a` do shell — é o mesmo mecanismo que o NUT usa
para rebatizar drivers, e o único portátil no macOS sem reescrever o binário.
"""

from __future__ import annotations

import os
import shutil
import signal
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
PREFIXO_PADRAO = "/opt/homebrew/opt/nut"

# Tempo que damos ao processo para sair com educação antes do sinal duro.
ESPERA_TERMINO = 5.0
# Quanto esperar entre subir o driver e subir o servidor: o servidor procura o
# soquete do driver e reclama se ele ainda não existe.
ATRASO_SERVIDOR = 2.0


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
                 prefixo: str = PREFIXO_PADRAO, log=None,
                 spawn=subprocess.Popen, clock=time.monotonic) -> None:
        self._ups = ups
        self._usuario = usuario or os.environ.get("USER") or "nobody"
        self._prefixo = prefixo
        self._log = log or (lambda *_a, **_k: None)
        self._spawn = spawn
        self._clock = clock
        self._lock = threading.Lock()
        self._driver: subprocess.Popen | None = None
        self._servidor: subprocess.Popen | None = None
        self._pausado = False

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
        if self._driver is None or self._driver.poll() is not None:
            self._driver = self._spawn(
                self._comando(NOME_DRIVER, f"{self._prefixo}/bin/usbhid-ups",
                              "-a", self._ups, "-u", self._usuario, "-F"),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            self._log("INFO", "nut_driver_iniciado", pid=self._driver.pid, ups=self._ups)
            time.sleep(ATRASO_SERVIDOR)
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
            for nome, proc in (("driver", self._driver), ("servidor", self._servidor)):
                rc = proc.poll() if proc is not None else None
                if proc is not None and rc is not None:
                    self._log("WARN", "nut_processo_caiu", qual=nome, rc=rc)
            self._subir_se_preciso()

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
