"""O cabo do River vai e volta sozinho, sem botão nenhum na tela.

O problema: o River tem **um** cabo, e dois programas o querem. O nosso serviço o
segura para vigiar a energia; o aplicativo do fabricante precisa dele para
mostrar o aparelho e mudar a configuração. Até aqui isso era um botão
("emprestar o cabo"), e quem esquecesse de apertá-lo ficava sem um dos dois.

O que este módulo faz: percebe o aplicativo do fabricante abrir e, se ele
**tomar** o cabo, larga; percebe ele fechar — ou travar, ou morrer — e
**retoma**. O dono não aperta nada; só recebe o aviso na tela.

O sinal é medido, não suposto. Do que foi lido dentro do pacote do fabricante em
2026-09-04 (`docs/decisions/2026-09-04-0110-…`, seção 5): o aplicativo mora em
`/Applications/PowerManager.app` e, em modo **Local**, roda `pkill -9 usbhid-ups`
como root ao abrir — o nosso leitor morre, e é essa morte que diz "ele quer o
cabo". Em modo **Remoto** (o aplicativo lendo pelo nosso servidor, na rede) ele
não toca no leitor: medido no Mac mini em 2026-09-06, 120 s aberto, leitor e
servidor de pé, nenhum pedido de senha de administrador. Até a 0.8.4 o cabo era
largado só porque o aplicativo abriu — e em modo Remoto isso deixava os DOIS
sem leitura (o dono perguntou "por que não permitimos ambos?").

Então a regra é: o aplicativo abriu e o leitor CAIU → o cabo é dele; abriu e o
leitor segue de pé → o cabo fica e os dois leem. O que se procura na lista de
processos é o **caminho de pacote** da interface — não um nome adivinhado.

O compromisso, dito: QUALQUER queda do leitor com o aplicativo aberto conta como
pedido de cabo — inclusive uma queda por outro motivo (o River desligado, o cabo
solto) enquanto o aplicativo estiver aberto em modo Remoto. Nesse caso o serviço
cede (para leitor e servidor) até o aplicativo fechar, e volta sozinho. É o
preço de não depender de nenhum arquivo do fabricante. Tempo até ceder, pela
leitura do código: a queda é vista na volta seguinte do laço (2 s) e o cabo é
cedido na olhada seguinte deste vigia (a cada 5 s) — cerca de 8 s no pior caso;
a bancada no Mac mini é quem mede.

Duas regras que não se negociam:

1. **Com proteção armada, o cabo NÃO é largado.** Largar seria ficar cego para a
   queda de energia justamente com o desligamento automático ligado. O aviso sai
   na tela, e o cabo fica.
2. **Só se retoma o que nós mesmos largamos.** Se o dono emprestou o cabo pela
   tela, ele volta pela tela — o automático não desfaz a escolha dele.
"""

from __future__ import annotations

import subprocess
import time

# O executável da INTERFACE do fabricante — e só ele.
#
# É uma expressão regular (é assim que `pgrep -f` lê o padrão), ancorada no fim
# da linha de comando. A anatomia do pacote deles, medida no Mac mini em
# 2026-09-05 com a interface aberta (`open -a PowerManager; pgrep -fl`):
#
#   …/PowerManager.app/Contents/MacOS/PowerManager_1.0.0.16.app/Contents/MacOS/PowerManager
#       → a interface: só existe enquanto o dono a tem aberta
#   …/PowerManager.app/Contents/MacOS/PowerManager_1.0.0.16.app/Contents/PowerManagerService/PowerManagerService
#       → o daemon deles (LaunchDaemon `com.ecoflow.PowerManagerService`): roda SEMPRE
#
# As duas versões anteriores erravam para o mesmo lado: a primeira procurava o
# caminho do pacote, a segunda o prefixo `…/PowerManager.app/Contents/MacOS/`,
# e as duas casam o daemon, cujo caminho inteiro passa por ali. Com qualquer
# uma o cabo era largado na primeira volta e nunca voltava, com a interface
# fechada. Ancorar no executável da interface é o que distingue "o dono abriu"
# de "o serviço de fundo deles está instalado".
APLICATIVO_DO_FABRICANTE = r"/Contents/MacOS/PowerManager$"
# De quanto em quanto tempo olhamos. Não é a cada ciclo do laço (2 s) de
# propósito: cada olhada é um processo novo, e o que se ganha em pressa não paga.
# Com 5 s, o aplicativo do fabricante espera no máximo isso para receber o cabo.
INTERVALO_SEGUNDOS = 5.0

EV_LARGADO = "CABO_LARGADO_AUTOMATICO"
EV_RETOMADO = "CABO_RETOMADO_AUTOMATICO"
EV_MANTIDO = "CABO_MANTIDO_PROTECAO_ARMADA"


def _procurar_padrao(padrao: str) -> bool:
    """Existe algum processo cuja linha de comando contenha isto?

    `pgrep -f` é o caminho do sistema para essa pergunta, e não depende de
    biblioteca nenhuma. Falha (binário ausente, tempo esgotado) responde "não
    achei" — e não achar leva a RETOMAR o cabo, que é o lado seguro: o serviço
    volta a vigiar.
    """
    try:
        resultado = subprocess.run(["/usr/bin/pgrep", "-f", padrao],
                                   capture_output=True, timeout=5, check=False)
    except (OSError, subprocess.SubprocessError):
        return False
    return resultado.returncode == 0 and bool(resultado.stdout.strip())


class CaboAutomatico:
    """Vigia o aplicativo do fabricante e passa o cabo de mão em mão."""

    def __init__(self, supervisor, *, aplicativo: str = APLICATIVO_DO_FABRICANTE,
                 intervalo: float = INTERVALO_SEGUNDOS, log=None, avisar=None,
                 ha_protecao_armada=None, procurar=_procurar_padrao,
                 quedas_do_driver=None, clock=time.monotonic) -> None:
        self._supervisor = supervisor
        # Quantas vezes o leitor morreu por conta própria: é o que distingue o
        # aplicativo que TOMOU o cabo (modo Local) do que só abriu (modo Remoto).
        self._quedas_do_driver = quedas_do_driver or (
            lambda: getattr(supervisor, "quedas_do_driver", 0))
        self._aplicativo = aplicativo
        self._intervalo = intervalo
        self._log = log or (lambda *_a, **_k: None)
        # `avisar(evento, detalhe)` põe a troca na linha do tempo do app: é assim
        # que o dono fica sabendo, já que não há botão.
        self._avisar = avisar or (lambda *_a, **_k: None)
        self._ha_protecao_armada = ha_protecao_armada or (lambda: False)
        self._procurar = procurar
        self._clock = clock
        self._proxima = float("-inf")
        # Nós largamos o cabo? Só o que largamos é que retomamos.
        self._largamos = False
        # Para o aviso de "não larguei" sair uma vez por abertura, e não a cada
        # cinco segundos enquanto o aplicativo estiver aberto.
        self._ja_avisei_que_mantive = False
        # As quedas do leitor contadas na olhada ANTERIOR e no momento em que o
        # aplicativo apareceu aberto. A referência é a olhada anterior de
        # propósito: o `pkill` deles pode vir entre duas olhadas, antes de o
        # aplicativo ser visto — uma queda entre as duas ainda é dele.
        self._quedas_na_olhada_anterior = 0
        self._quedas_ao_abrir: int | None = None

    def vigiar(self) -> None:
        """Chamada a cada volta do laço; só age de tempos em tempos."""
        agora = self._clock()
        if agora < self._proxima:
            return
        self._proxima = agora + self._intervalo
        aberto = self._procurar(self._aplicativo)
        if aberto:
            self._alguem_abriu()
        else:
            self._ninguem_mais_quer()
        self._quedas_na_olhada_anterior = self._quedas_do_driver()

    # -- os dois lados ------------------------------------------------------
    def _alguem_abriu(self) -> None:
        if self._largamos:
            return                       # já está com ele
        if self._quedas_ao_abrir is None:
            self._quedas_ao_abrir = self._quedas_na_olhada_anterior
        estado = self._supervisor.estado()
        if getattr(estado, "pausado_pelo_dono", False):
            return                       # o dono já emprestou pela tela
        if self._quedas_do_driver() <= self._quedas_ao_abrir:
            return                       # abriu, mas não tomou o cabo: os dois leem
        # Daqui para baixo ele TOMOU o cabo (o leitor caiu). A proteção armada
        # vem depois dessa pergunta de propósito: em modo Remoto ele nem pede o
        # cabo, e o aviso "mantive" seria mentira (revisão fria da 0.8.5).
        if self._ha_protecao_armada():
            if not self._ja_avisei_que_mantive:
                self._ja_avisei_que_mantive = True
                self._log("WARN", "cabo_mantido_protecao_armada",
                          aplicativo=self._aplicativo)
                self._avisar(EV_MANTIDO,
                             "o aplicativo da EcoFlow pediu o cabo, mas há proteção "
                             "armada: o serviço fica com ele para não ficar cego numa "
                             "queda. Desligue a proteção (modo ensaio) se quiser usar o "
                             "aplicativo dele")
            return
        self._largamos = True
        self._ja_avisei_que_mantive = False
        self._supervisor.pausar("o aplicativo da EcoFlow tomou o cabo")
        self._log("WARN", "cabo_largado_automatico", aplicativo=self._aplicativo,
                  quedas=self._quedas_do_driver())
        self._avisar(EV_LARGADO,
                     "o aplicativo da EcoFlow tomou o cabo (modo Local) e o serviço o "
                     "cedeu; eu retomo sozinho quando ele fechar")

    def _ninguem_mais_quer(self) -> None:
        self._ja_avisei_que_mantive = False
        if self._quedas_ao_abrir is not None and not self._largamos:
            self._log("INFO", "aplicativo_fechou_sem_tomar_o_cabo",
                      aplicativo=self._aplicativo)
        self._quedas_ao_abrir = None
        if not self._largamos:
            return                       # não fomos nós que largamos
        self._largamos = False
        estado = self._supervisor.retomar()
        self._log("INFO", "cabo_retomado_automatico", lendo=getattr(estado, "lendo", None))
        self._avisar(EV_RETOMADO,
                     "o aplicativo da EcoFlow fechou e o cabo voltou para o serviço")

    # -- para a tela --------------------------------------------------------
    @property
    def largamos_o_cabo(self) -> bool:
        return self._largamos
