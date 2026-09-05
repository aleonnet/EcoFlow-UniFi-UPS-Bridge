"""As ordens que chegam pelo NUT — e as cercas delas, que são as da tela.

Regra que manda em tudo o que está aqui: **um comando pelo NUT não pode ter menos
cerca que o mesmo comando pelo aplicativo.** O Home Assistant é mais um cliente,
não um caminho paralelo.

Os nomes dos comandos não são escolha nossa. Medido no código do Home Assistant
em 2026-09-05: ele só oferece comando cujo nome está numa lista fechada
(`INTEGRATION_SUPPORTED_COMMANDS`), e nela

- `load.off` é *"Turn off the load immediately"*
- `shutdown.reboot` é *"Shut down the load briefly while rebooting the UPS"*

No aparelho `river-bridge`, a carga é tudo o que está ligado no River, e
`load.off` desliga o River. No aparelho de um dispositivo protegido, a carga **é**
o aparelho — então `load.off` o desliga e `shutdown.reboot` o reinicia. Um nome
inventado (`device.udr7.shutdown`) seria aceito pelo NUT e invisível no Home
Assistant; usar o nome padrão é o que faz a ordem existir de verdade.

Onde vive cada cerca:

| Ordem | O que ela exige |
|---|---|
| desligar o River | a trava de arquivo `RIVER_POWEROFF_ALLOWED` aberta **e** nenhuma proteção armada |
| desligar/reiniciar um dispositivo | a trava de arquivo `DEVICE_CMD_ALLOWED` aberta **e** alcance provado nos últimos 30 dias |

A trava de arquivo é a mesma de sempre: nem esta rota nem a da tela a abrem. E
"nenhuma proteção armada" existe para não haver duas ordens de desligamento ao
mesmo tempo — a automática e a do dono.

O modo ensaio **não** entra aqui de propósito: ele governa o que a proteção faz
sozinha numa queda de energia. Uma ordem que o dono dá agora é uma ordem.

Uma pergunta que valia a pena responder antes da bancada: desligar o River abre
uma conversa NOVA com o servidor do no-break, enquanto esse mesmo servidor espera
a nossa resposta do comando. Isso travaria? Não: lido no código do NUT
(`server/upsd.c`, o laço principal), o servidor faz `poll()` sobre todos os
descritores de uma vez — clientes, portas de escuta e soquetes de driver — e a
resposta de rastreio é guardada para depois (a própria limpeza dela tem uma hora
de prazo). Ele não fica parado esperando driver nenhum.
"""

from __future__ import annotations

from . import eventos
from .nut_driver import CMD_DESCONHECIDO, CMD_FALHOU, CMD_FEITO, CMD_INVALIDO

def _evento(plugin, sufixo: str) -> str:
    """O nome do evento deste dispositivo, com o prefixo do TIPO dele.

    Nome de evento é vocabulário FECHADO: a tela traduz cada um para uma frase
    em português, e o que ela não conhece aparece cru na linha do tempo do dono.
    A primeira versão disto montava o nome a partir do id da instância
    (`f"{id.upper()}_ORDEM_ENVIADA"`), o que criava um nome novo por dispositivo
    — impossível de traduzir, e por isso impossível de mostrar.
    """
    nomear = getattr(plugin, "nome_de_evento", None)
    if nomear is not None:
        return nomear(sufixo)
    return f"{getattr(plugin, 'type_id', 'DEVICE').upper()}_{sufixo}"


# Os dois nomes da lista fechada do Home Assistant que sabemos honrar.
DESLIGAR = "load.off"
REINICIAR = "shutdown.reboot"
# Qual ação de dispositivo cada nome do NUT significa.
_ACAO_DO_COMANDO = {DESLIGAR: "desligar", REINICIAR: "reiniciar"}


def comandos_do_river(cfg) -> tuple[str, ...]:
    """O que o aparelho `river-bridge` anuncia.

    Com a trava de arquivo fechada, `load.off` **não é anunciado**: melhor o Home
    Assistant não oferecer a ordem do que oferecê-la e recusar sempre. A trava só
    muda com reinício do serviço, então o anúncio não fica oscilando.
    """
    return (DESLIGAR,) if getattr(cfg, "river_poweroff_allowed", False) else ()


def comandos_do_dispositivo(plugin, cfg=None) -> tuple[str, ...]:
    """O que o aparelho de um dispositivo protegido anuncia.

    Duas condições, e as duas têm de valer:

    1. **A trava de arquivo do serviço tem de estar aberta.** Desligar um roteador
       de produção é ato destrutivo, e na casa todo ato destrutivo tem uma trava
       que só o arquivo abre — a mesma mecânica do desligamento do River e do
       armamento da proteção. Fechada, a ordem não é oferecida a ninguém.
    2. **O tipo tem de saber fazer.** O console UniFi sabe desligar e reiniciar;
       um host genérico por SSH sabe desligar. O que ele não sabe não vira botão.
    """
    if cfg is not None and not getattr(cfg, "device_cmd_allowed", False):
        return ()
    acoes = plugin.acoes_manuais() if hasattr(plugin, "acoes_manuais") else {}
    return tuple(nome for nome, acao in _ACAO_DO_COMANDO.items() if acao in acoes)


class ExecutorDeComandos:
    """Recebe a ordem do servidor do no-break e a cumpre — ou a recusa, com motivo."""

    def __init__(self, cfg, *, aparelho_do_river: str, plugins=(), state_dir: str = "",
                 log=None, registrar=None, desligar_river=None, executar_no_dispositivo=None):
        self.cfg = cfg
        self.aparelho_do_river = aparelho_do_river
        self.plugins = plugins
        self.state_dir = state_dir
        self._log = log or (lambda *_a, **_k: None)
        # `registrar(evento, detalhe)` põe a ordem na linha do tempo do app. Uma
        # ordem destrutiva que só existisse no registro do sistema seria invisível
        # para quem usa o programa.
        self._registrar = registrar or (lambda *_a, **_k: None)
        self._desligar_river = desligar_river or self._desligar_river_de_verdade
        self._executar_no_dispositivo = (
            executar_no_dispositivo or (lambda plugin, acao: plugin.executar_acao(acao)))

    # -- o ponto de entrada -------------------------------------------------
    def __call__(self, aparelho: str, comando: str, _parametro=None) -> int:
        if aparelho == self.aparelho_do_river:
            return self._no_river(comando)
        return self._no_dispositivo(aparelho, comando)

    # -- o River ------------------------------------------------------------
    def _no_river(self, comando: str) -> int:
        if comando != DESLIGAR:
            return CMD_DESCONHECIDO
        recusa = self._por_que_nao_desligar_o_river()
        if recusa is not None:
            self._recusou(eventos.RIVER_DESLIGAR_RECUSADO, comando, recusa)
            return CMD_INVALIDO
        self._log("WARN", "nut_river_desligando", origem="NUT")
        self._registrar(eventos.RIVER_DESLIGANDO,
                        "ordem recebida pelo NUT (Home Assistant)")
        try:
            self._desligar_river()
        except Exception as exc:
            self._log("ERROR", "nut_river_desligar_falhou", reason=str(exc)[:200])
            self._registrar(eventos.RIVER_DESLIGAR_FALHOU, str(exc)[:200])
            return CMD_FALHOU
        return CMD_FEITO

    def _por_que_nao_desligar_o_river(self) -> str | None:
        if not getattr(self.cfg, "river_poweroff_allowed", False):
            return ("desligar o River está bloqueado no arquivo do serviço; "
                    "abra a trava e reinicie para poder usar esta ordem")
        if any(getattr(p, "armed", False) for p in self.plugins):
            return ("há proteção armada: desligue-a antes, para não haver duas "
                    "ordens de desligamento ao mesmo tempo")
        return None

    def _desligar_river_de_verdade(self) -> None:
        from .river_cmd import alvo_do_river, desligar_o_aparelho

        alvo = alvo_do_river(self.cfg, self.state_dir)
        if not alvo.senha:
            raise RuntimeError("não achei a senha da conta que manda no aparelho; "
                               "reinstale o serviço para recriá-la")
        desligar_o_aparelho(
            alvo,
            ao_nao_fechar_a_trava=lambda exc: self._trava_ficou_aberta(exc))

    def _trava_ficou_aberta(self, exc) -> None:
        """O aparelho ficou desligável por qualquer programa desta máquina.

        Não é só registro: o dono precisa saber para reiniciar o serviço.
        """
        self._log("ERROR", "killpower_flag_aberta", reason=str(exc)[:200])
        self._registrar(eventos.RIVER_TRAVA_ABERTA,
                        "não consegui fechar a trava de desligamento do leitor; "
                        "reinicie o serviço")

    # -- os dispositivos protegidos -----------------------------------------
    def _no_dispositivo(self, aparelho: str, comando: str) -> int:
        plugin = next((p for p in self.plugins if p.id == aparelho), None)
        acao = _ACAO_DO_COMANDO.get(comando)
        if plugin is None or acao is None:
            return CMD_DESCONHECIDO
        if not getattr(self.cfg, "device_cmd_allowed", False):
            # A trava é conferida de novo AQUI, e não só no que se anuncia: quem
            # fala com o soquete não é obrigado a perguntar o que existe antes de
            # mandar. Anunciar de menos é cortesia; recusar é a cerca.
            self._recusou(_evento(plugin, "ORDEM_RECUSADA"), comando,
                          "mandar neste dispositivo à mão está bloqueado no arquivo "
                          "do serviço; abra a trava e reinicie para poder usar esta ordem")
            return CMD_INVALIDO
        if acao not in (plugin.acoes_manuais() if hasattr(plugin, "acoes_manuais") else {}):
            return CMD_DESCONHECIDO
        self._log("WARN", "nut_dispositivo_ordem", aparelho=aparelho, acao=acao, origem="NUT")
        try:
            motivo = self._executar_no_dispositivo(plugin, acao)
        except Exception as exc:
            motivo = f"{type(exc).__name__}: {exc}"[:200]
        if motivo:
            self._log("ERROR", "nut_dispositivo_ordem_falhou", aparelho=aparelho,
                      acao=acao, reason=motivo)
            self._registrar(_evento(plugin, "ORDEM_FALHOU"), f"{acao}: {motivo}")
            return CMD_FALHOU
        self._registrar(_evento(plugin, "ORDEM_ENVIADA"),
                        f"{acao} — ordem recebida pelo NUT (Home Assistant)")
        return CMD_FEITO

    # -- registro -----------------------------------------------------------
    def _recusou(self, evento: str, comando: str, motivo: str) -> None:
        self._log("WARN", "nut_comando_recusado", comando=comando, reason=motivo)
        self._registrar(evento, motivo)
