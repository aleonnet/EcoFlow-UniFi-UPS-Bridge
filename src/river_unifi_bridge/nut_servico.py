"""Quais aparelhos a ponte publica no NUT, e o que cada um carrega.

`nut_driver.py` é o protocolo e `nut_publicacao.py` são os nomes; aqui mora a
decisão: **quem** aparece no servidor do no-break.

São dois tipos de aparelho publicado:

1. **o River completo** — tudo o que sabemos dele, o que o no-break diz mais o que
   a porta serial do mesmo cabo entrega (potência total, watts por tomada,
   frequência). O aparelho de fábrica (`usbhid-ups`) continua existindo ao lado, e
   **é ele** que a proteção lê: ler o nosso seria o vigia decidindo com dados que
   ele mesmo escreveu.

2. **um por dispositivo protegido** — o roteador, publicado como carga própria.
   Ele existe por um motivo medido: o Home Assistant só entende comando cujo nome
   está na lista fechada dele, e nessa lista `load.off` significa "Turn off the
   load immediately". Publicando o roteador como aparelho, a carga **é** ele, e o
   nome padrão passa a dizer a verdade — em vez de um `device.udr7.shutdown` que o
   NUT aceitaria e o Home Assistant jamais mostraria.

Um dispositivo protegido só é publicado depois de o serviço ter **provado** que
alcança o console. Sem essa prova o aparelho não aparece: um botão que não tem
para onde ir é pior que botão nenhum.
"""

from __future__ import annotations

import os
import re

from . import nut_conf
from .nut_driver import DriverDoNut, DriverError, ESTADO_PADRAO, caminho_do_soquete
from .nut_publicacao import variaveis_do_dispositivo, variaveis_do_river

# O nome de um aparelho no NUT vira metade do nome de um arquivo de soquete e vai
# inteiro para dentro do `ups.conf`. A forma é fechada de propósito.
NOME_DE_APARELHO = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,31}")
# Como o aparelho composto se chama quando ninguém escolhe outro nome. Não é
# "river" de propósito: esse nome já é usado por quem instalou o leitor de
# fábrica à mão, e o serviço recusa subir quando os dois coincidem.
APARELHO_PADRAO = "river-bridge"


class PonteDoNut:
    """Os aparelhos que publicamos, criados, mantidos em dia e recolhidos."""

    def __init__(self, *, aparelho: str = APARELHO_PADRAO, estado: str = ESTADO_PADRAO,
                 log=None, criar_driver=DriverDoNut, executor=None,
                 comandos_do_river=(), comandos_do_dispositivo=None,
                 ups_conf: str = "", ao_mudar_a_declaracao=None) -> None:
        self.aparelho = aparelho
        self.estado = estado
        # O servidor do no-break só serve aparelho declarado no `ups.conf`, e os
        # dispositivos entram e saem pela tela do app a qualquer hora. Sem manter
        # essa declaração em dia, um roteador adicionado hoje só apareceria no
        # Home Assistant depois de o dono rodar o instalador de novo.
        self.ups_conf = ups_conf
        self._ao_mudar_a_declaracao = ao_mudar_a_declaracao or (lambda: None)
        self._log = log or (lambda *_a, **_k: None)
        self._criar = criar_driver
        self._executor = executor
        # Uma função `() -> tupla de comandos`, lida a cada volta: a trava do
        # desligamento virou interruptor na tela (0.8.0), e o aparelho publicado
        # ganha ou perde `load.off` sem reinício. Uma tupla ainda é aceita (os
        # testes e quem não tem trava passam uma), e vale para sempre.
        if callable(comandos_do_river):
            self._comandos_do_river = comandos_do_river
        else:
            fixos = tuple(comandos_do_river)
            self._comandos_do_river = lambda: fixos
        # Uma função `(plugin) -> tupla de comandos`: cada TIPO diz o que sabe
        # fazer, em vez de este módulo saber de roteador.
        self._comandos_do_dispositivo = comandos_do_dispositivo or (lambda _p: ())
        self._river: DriverDoNut | None = None
        self._dispositivos: dict[str, DriverDoNut] = {}
        # O nome que o dono deu a cada dispositivo, para a declaração no `ups.conf`
        # dizer o mesmo que a tela.
        self._descricoes: dict[str, str] = {}
        # A última queixa sobre o `ups.conf`, para ela sair uma vez e não a cada
        # volta do laço.
        self._ultima_queixa_do_conf: str | None = None

    # -- ciclo de vida ------------------------------------------------------
    def iniciar(self) -> None:
        # Sem NUT instalado não há para quem publicar, e criar a pasta de estado
        # dele seria deixar lixo numa máquina que não pediu nada.
        if not os.path.isdir(self.estado):
            self._log("WARN", "nut_sem_pasta_de_estado", pasta=self.estado)
            return
        self._river = self._abrir(self.aparelho)

    def encerrar(self) -> None:
        for driver in list(self._dispositivos.values()):
            driver.encerrar()
        self._dispositivos.clear()
        if self._river is not None:
            self._river.encerrar()
            self._river = None

    def _abrir(self, nome: str) -> DriverDoNut | None:
        """Um aparelho novo no ar. Erro aqui NÃO derruba o serviço.

        Publicar é um extra: sem ele o Home Assistant fica sem os dados, e a
        proteção — que é o motivo de o serviço existir — segue igual.
        """
        if NOME_DE_APARELHO.fullmatch(nome) is None:
            self._log("WARN", "nut_aparelho_nome_invalido", aparelho=nome)
            return None
        caminho = caminho_do_soquete(nome, self.estado)
        driver = self._criar(caminho, log=self._log,
                             executor=self._executor and
                             (lambda comando, parametro, _n=nome:
                              self._executor(_n, comando, parametro)))
        try:
            driver.iniciar()
        except (DriverError, OSError) as exc:
            self._log("ERROR", "nut_aparelho_nao_publicado", aparelho=nome,
                      reason=str(exc)[:200])
            return None
        return driver

    # -- o ciclo ------------------------------------------------------------
    def atualizar(self, snap, plugins=()) -> None:
        """Uma volta do laço: o River e os dispositivos, com o que se sabe agora."""
        if self._river is not None:
            self._river.publicar(variaveis_do_river(snap),
                                 comandos=self._comandos_do_river(), dados_ok=True)
        self._reconciliar(snap, plugins)
        self._declarar(snap)

    def _declarar(self, snap) -> None:
        """Deixa o `ups.conf` com os aparelhos que estão no ar — e só então avisa.

        O aviso (que reinicia o servidor do no-break) só sai quando o arquivo
        MUDOU de verdade: reiniciar a cada volta do laço deixaria a leitura do
        River com um buraco a cada dois segundos.
        """
        if not self.ups_conf or self._river is None:
            return
        declarados = [(self.aparelho, (snap.model or "River") + " (River Bridge)")]
        declarados += [(identificador, self._descricoes.get(identificador, identificador))
                       for identificador in sorted(self._dispositivos)]
        try:
            mudou = nut_conf.atualizar(self.ups_conf, declarados)
        except (nut_conf.ConfMalformada, OSError) as exc:
            # Uma vez, não a cada dois segundos: o laço passa por aqui em toda
            # volta, e um arquivo que ninguém foi consertar encheria o registro
            # com a mesma linha 1.800 vezes por hora. A queixa volta a sair se o
            # motivo mudar — ou se o arquivo for consertado e quebrar de novo.
            motivo = str(exc)[:200]
            if motivo != self._ultima_queixa_do_conf:
                self._ultima_queixa_do_conf = motivo
                self._log("WARN", "nut_conf_nao_escrito", reason=motivo)
            return
        self._ultima_queixa_do_conf = None
        if mudou:
            self._log("INFO", "nut_conf_atualizado",
                      aparelhos=[nome for nome, _ in declarados])
            self._ao_mudar_a_declaracao()

    def marcar_sem_dados(self) -> None:
        """O no-break calou: o servidor precisa saber que o que ele tem envelheceu.

        Sem isto, o Home Assistant mostraria a última carga de bateria como se
        fosse a de agora — exatamente quando ela deixou de ser.
        """
        for driver in [self._river, *self._dispositivos.values()]:
            if driver is not None:
                driver.marcar_sem_dados()

    def _reconciliar(self, snap, plugins) -> None:
        """Dispositivo entra e sai pela tela; os aparelhos do NUT acompanham."""
        publicaveis = {}
        for plugin in plugins:
            if not self._pode_publicar(plugin):
                continue
            publicaveis[plugin.id] = plugin
        for identificador in list(self._dispositivos):
            if identificador not in publicaveis:
                self._dispositivos.pop(identificador).encerrar()
                self._descricoes.pop(identificador, None)
                self._log("INFO", "nut_dispositivo_recolhido", aparelho=identificador)
        for identificador, plugin in publicaveis.items():
            driver = self._dispositivos.get(identificador)
            if driver is None:
                driver = self._abrir(identificador)
                if driver is None:
                    continue
                self._dispositivos[identificador] = driver
                self._log("INFO", "nut_dispositivo_publicado", aparelho=identificador)
            registro = plugin.alcance_registrado() or {}
            nome = plugin.status().get("name") or identificador
            self._descricoes[identificador] = nome
            driver.publicar(
                variaveis_do_dispositivo(
                    snap, nome=nome,
                    modelo=registro.get("modelo"), firmware=registro.get("firmware"),
                    fabricante=getattr(plugin, "fabricante", None)),
                comandos=self._comandos_do_dispositivo(plugin), dados_ok=True)

    @staticmethod
    def _pode_publicar(plugin) -> bool:
        """Só entra no NUT o dispositivo que o serviço PROVOU alcançar.

        Sem a prova, o aparelho apareceria no Home Assistant com uma ordem de
        desligar que não chega a lugar nenhum — e a hora de descobrir isso seria
        a pior possível.
        """
        alcance = getattr(plugin, "alcance_valido", None)
        return bool(alcance and alcance())

    # -- para a tela e para os testes ---------------------------------------
    def aparelhos(self) -> list[str]:
        nomes = [] if self._river is None else [self.aparelho]
        return nomes + sorted(self._dispositivos)
