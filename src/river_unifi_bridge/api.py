"""Local HTTP + SSE API for the native UI (§7A.3).

Serves ONLY on 127.0.0.1 (hard fence — non-loopback bind is refused), bearer
token from a 0600 file, no TLS/rate limiting (registered §15 exceptions).
Runs inside a daemon thread with its own asyncio loop; the sync poll loop
shares data through SharedState (thread-safe).

Restart contract (§7A.3): POST /v1/service/restart answers 202, the response
is drained, and the exit callback fires ~0.5 s later OUTSIDE the handler —
never exit inside a handler (the client would see a reset instead of the 202).
"""

from __future__ import annotations

import asyncio
import concurrent.futures
import json
import os
from dataclasses import replace
import threading
import time

from aiohttp import web

from . import __version__, eventos
from .config import (
    BridgeConfig,
    ConfigError,
    HOT_RELOAD_KEYS,
    config_field_names,
    recusa_do_vigia_espelho,
    validate_update,
)
from .devices import DeviceInstance, DevicesError, new_id, now_iso, validate_fields
from .envfile import EnvFileError, update_env_file
from .history import HistoryStore
from .localtoken import get_or_create_token
from .plugins import TYPES, PluginSet, plugin_statuses, type_catalog
from .plugins.base import FieldSpec
from .plugins.udr7_ssh import LEGACY_ATTR_TO_KEY, LEGACY_FIELD_TO_KEY, NAME_FIELD
from .protect import _emit, log_json
from .state import SharedState

# Fence: the API is loopback-only by design (§7A.3). Tests + gate mutation
# scene assert on this constant — do not parametrize it away.
BIND_HOST = "127.0.0.1"

RESTART_EXIT_DELAY_SECONDS = 0.5

# Os dois booleanos do predicado de armamento de uma instância, validados com a
# mesma régua dos campos (1/0, true/false); `enabled` nasce falso, `dry_run` nasce ligado.
_BOOL_ENABLED = FieldSpec("enabled", "bool", False)
_BOOL_DRY_RUN = FieldSpec("dry_run", "bool", True)


def ensure_loopback(host: str) -> None:
    if host != "127.0.0.1":
        raise ConfigError(f"bind não-loopback recusado: {host} (API é local por desenho)")


# Chaves legadas que formam o predicado de armamento no PUT de configuração.
_DESARME_CHAVES = frozenset({"PROTECT_UDR7", "PROTECT_DRY_RUN"})


def _e_desarme_puro(mudancas: dict) -> bool:
    """O PUT só desliga a proteção (ou liga o ensaio) e não toca em mais nada?

    Desarmar é o botão de parada do dono: ele vale mesmo quando o disco falha.
    Qualquer chave fora do predicado tira o PUT desta categoria.
    """
    if not mudancas or not set(mudancas) <= _DESARME_CHAVES:
        return False
    if "PROTECT_UDR7" in mudancas and not bool(mudancas["PROTECT_UDR7"]):
        return True
    return bool(mudancas.get("PROTECT_DRY_RUN", False))


def _patch_e_desarme_puro(patch: dict, instancia) -> bool:
    """O mesmo, para o PUT de uma instância: `armed` tem de ficar falso."""
    if not patch or not set(patch) <= {"enabled", "dry_run"}:
        return False
    ligado = patch.get("enabled", instancia.enabled)
    ensaio = patch.get("dry_run", instancia.dry_run)
    return not (bool(ligado) and not bool(ensaio))


def _sem_servidor_humano(exc: OSError) -> str:
    """Falha de rede em português, sem número de sistema na tela do dono."""
    return ("não consegui falar com o leitor do River. Ele pode estar parado, ou o "
            "cabo emprestado ao aplicativo da EcoFlow.")


def _empty_state(name: str, comm_ok: bool, last_error: str | None) -> dict:
    """Honest §7.3 shape when no snapshot exists yet: nulls, never invention."""
    return {
        "identity": {"name": name, "manufacturer": None, "model": None, "serial": None},
        "power": {
            "state": "UNKNOWN", "states": [], "input_present": None,
            "input_voltage_v": None, "output_voltage_v": None,
            "output_power_w": None, "load_percent": None,
            "input_power_w": None, "line_frequency_hz": None,
        },
        "outlets": None,
        "battery": {
            "charge_percent": None, "charge_low_percent": None,
            "runtime_seconds": None, "voltage_v": None, "temperature_c": None,
        },
        "health": {
            # Sem leitura não há bateria baixa nem sobrecarga a afirmar: `null` é o
            # que o contrato promete ("nulos, nunca invenção"), e `false` era invenção.
            "communication_ok": comm_ok, "low_battery": None, "overload": None,
            "alarm": [], "unknown_status_tokens": [],
            "last_error": last_error,
        },
        "source": {
            "nut": True, "usb_hid": True, "usb_cdc": False,
            "driver_name": None, "driver_version": None,
        },
        "timestamp": None,
    }


def _authorize(changes: dict, plugins: list, snapshot: dict | None,
               comm_ok: bool) -> tuple[int, str, str] | None:
    """Runs BEFORE anything is written, so a 4xx never leaves a trace no .env.

    Every rule belongs to a device, and the FIRST plugin to refuse wins. (Até a
    0.7.0 havia uma regra genérica aqui: as três travas eram "somente arquivo".
    Desde a 0.8.0 elas são interruptores na tela, e o que as protege é a
    confirmação do ato mais as cercas de cada dispositivo — fechar a trava de
    armamento com a proteção armada continua sendo 409 `armado`, pelo motor.)
    """
    for plugin in plugins:
        refusal = plugin.authorize(changes, snapshot, comm_ok)
        if refusal is not None:
            return refusal
    return None


class ApiServer:
    def __init__(
        self,
        cfg: BridgeConfig,
        state: SharedState,
        history: HistoryStore,
        env_path: str,
        restart_cb,
        token: str | None = None,
        plugins=None,
        store=None,
        state_dir: str | None = None,
        supervisor=None,
    ) -> None:
        ensure_loopback(BIND_HOST)
        self.cfg = cfg
        self.state = state
        self.history = history
        # Exportações de CSV com a thread produtora ainda viva (0.9.0; a cerca da
        # desconexão no meio do CSV lê este número).
        self._exportacoes_em_curso = 0
        self.env_path = env_path
        self.restart_cb = restart_cb
        # Sempre um PluginSet: é o que POST/DELETE mutam. Uma lista (fixtures) é
        # embrulhada; uma fixture sem plugins itera vazio, sem guardas `is None`.
        self.plugins = plugins if isinstance(plugins, PluginSet) else PluginSet(plugins or [])
        # Quem cuida dos processos do NUT (nut_supervisor.py). None em fixtures e
        # quando o dono cuida deles por fora (RIVER_NUT_MANAGED=0).
        self.supervisor = supervisor
        # A loja de instâncias (devices.json) e o diretório de estado: None nas
        # fixtures que não os exercitam — o espelho legado então não grava a loja.
        self.store = store
        self.state_dir = state_dir
        # Uma trava por dispositivo para as rotas de acesso ao console.
        self._travas_de_acesso: dict[str, asyncio.Lock] = {}
        self.token = token if token is not None else get_or_create_token()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._started = threading.Event()
        self.port: int | None = None

    # -- app ---------------------------------------------------------------

    def build_app(self) -> web.Application:
        @web.middleware
        async def auth(request: web.Request, handler):
            header = request.headers.get("Authorization", "")
            if header != f"Bearer {self.token}":
                return web.json_response({"erro": "token ausente ou inválido"}, status=401)
            return await handler(request)

        app = web.Application(middlewares=[auth])
        app.router.add_get("/v1/state", self._h_state)
        app.router.add_get("/v1/events", self._h_events)
        app.router.add_get("/v1/events/log", self._h_events_log)
        app.router.add_delete("/v1/events/log", self._h_events_delete)
        app.router.add_get("/v1/history", self._h_history)
        # 0.9.0: os registros em CSV, para o "Compartilhar…" do app. A ficha é o
        # middleware `auth`, como em toda rota.
        app.router.add_get("/v1/events/log.csv", self._h_events_log_csv)
        app.router.add_get("/v1/history/samples.csv", self._h_samples_csv)
        app.router.add_get("/v1/health", self._h_health)
        app.router.add_get("/v1/config", self._h_config_get)
        app.router.add_put("/v1/config", self._h_config_put)
        app.router.add_post("/v1/service/restart", self._h_restart)
        app.router.add_post("/v1/service/apagar-estado", self._h_apagar_estado)
        app.router.add_get("/v1/version", self._h_version)
        app.router.add_get("/v1/device-types", self._h_device_types)
        app.router.add_get("/v1/devices", self._h_devices_list)
        app.router.add_post("/v1/devices", self._h_devices_post)
        app.router.add_get("/v1/devices/{id}", self._h_devices_get)
        app.router.add_put("/v1/devices/{id}", self._h_devices_put)
        app.router.add_delete("/v1/devices/{id}", self._h_devices_delete)
        app.router.add_post("/v1/devices/{id}/acesso/{acao}", self._h_device_acesso)
        app.router.add_get("/v1/river/cabo", self._h_river_cabo_get)
        app.router.add_post("/v1/river/cabo", self._h_river_cabo_post)
        app.router.add_post("/v1/river/desligar", self._h_river_desligar)
        app.router.add_put("/v1/river/aparelho", self._h_river_aparelho)
        app.router.add_get("/v1/nut/rede", self._h_nut_rede_get)
        app.router.add_put("/v1/nut/rede", self._h_nut_rede_put)
        return app

    # -- o servidor do no-break na rede (o Home Assistant mora noutra máquina) --

    @staticmethod
    def _etc_do_nut() -> str:
        return os.environ.get("RUB_NUT_ETC") or "/opt/homebrew/etc/nut"

    async def _h_nut_rede_get(self, _req: web.Request) -> web.Response:
        """`aberta`: true/false quando o arquivo é nosso; null quando é do dono."""
        from . import nut_bootstrap

        aberta = await asyncio.to_thread(nut_bootstrap.rede_aberta, self._etc_do_nut())
        return web.json_response({"aberta": aberta, "propria": aberta is not None})

    async def _h_nut_rede_put(self, request: web.Request) -> web.Response:
        """Liga ou desliga a escuta na rede local — o interruptor da tela.

        Até a 0.7.0 isto era editar o `upsd.conf` à mão e reiniciar o serviço
        (o caminho de nerd que o dono vetou). A linha só é lida na partida do
        servidor, então o servidor do no-break é reiniciado aqui — só ele: o
        leitor de fábrica segura o cabo do River e não é tocado.
        """
        from . import nut_bootstrap

        try:
            corpo = await request.json()
        except Exception:
            return self._refuse(400, "validacao", "esperado {\"aberta\": true|false}")
        if not isinstance(corpo.get("aberta"), bool):
            return self._refuse(400, "validacao", "aberta tem de ser true ou false")
        try:
            mudou = await asyncio.to_thread(
                nut_bootstrap.abrir_para_a_rede, self._etc_do_nut(), corpo["aberta"])
        except nut_bootstrap.ConfiguracaoDoDono as exc:
            return self._refuse(409, "configuracao_do_dono", str(exc))
        except OSError as exc:
            return self._refuse(500, "arquivo_nut",
                                f"não consegui gravar a configuração do no-break: {exc}"[:200])
        reiniciado = False
        if mudou and self.supervisor is not None:
            await asyncio.to_thread(self.supervisor.reiniciar_servidor)
            reiniciado = True
        log_json("WARN" if mudou else "INFO", "nut_rede",
                 aberta=corpo["aberta"], mudou=mudou, servidor_reiniciado=reiniciado)
        return web.json_response({"aberta": corpo["aberta"], "mudou": mudou,
                                  "servidor_reiniciado": reiniciado})

    # -- o River como APARELHO: quem está com o cabo, e o que mandamos nele ---

    def _alvo_river(self):
        """Com que conta falamos com o nosso servidor do no-break.

        A senha mora num arquivo 0600 do diretório de estado, escrito pelo
        instalador — nunca no `.env`, que a rota de configuração devolve inteiro
        para o app. Sem o arquivo, as rotas de ação recusam com frase clara, em
        vez de tentar com senha vazia e receber "acesso negado" (revisão fria).

        A montagem em si mora em `river_cmd`: a mesma conta é usada pela ordem que
        chega pelo NUT, e duas cópias poderiam discordar sobre onde está a senha.
        """
        from .river_cmd import alvo_do_river
        return alvo_do_river(self.cfg, self.state_dir)

    def _cabo_emprestado(self, arma: bool) -> web.Response | None:
        """Armar com o cabo na mão do outro aplicativo é armar às cegas.

        Enquanto o River está emprestado, ninguém lê bateria nem autonomia aqui:
        a última leitura ainda parece boa por alguns segundos, e é essa janela
        que esta recusa fecha (revisão fria da 0.5.0). Desarmar continua sempre
        permitido — o botão de parada nunca é recusado.
        """
        if not arma or self.supervisor is None:
            return None
        if not self.supervisor.estado().pausado_pelo_dono:
            return None
        return self._refuse(409, "cabo_emprestado",
                            "o River está emprestado ao aplicativo da EcoFlow: não dá para "
                            "armar sem ler a bateria. Retome o cabo primeiro.")

    def _sem_conta_de_admin(self) -> web.Response | None:
        """Recusa clara quando a conta que manda no aparelho não foi configurada."""
        if self._alvo_river().senha:
            return None
        return self._refuse(409, "sem_conta_do_aparelho",
                            "o serviço ainda não tem uma conta para mandar no River. "
                            "Rode a instalação de novo para criá-la.")

    async def _h_device_acesso(self, request: web.Request) -> web.Response:
        """Preparar, instalar, testar e esquecer o acesso ao console.

        Quatro passos porque a tela precisa explicar cada um. Nenhum deles
        devolve a chave privada, e a senha do console (quando vem) é usada uma
        vez e descartada: não é gravada, não é registrada e não volta aqui.
        """
        from . import ssh_acesso as sa

        plugin = self.plugins.get(request.match_info["id"])
        if plugin is None or not hasattr(plugin, "chave_path") or not plugin.chave_path:
            return self._refuse(404, "dispositivo_ausente",
                                "não existe dispositivo com esse id, ou ele não usa console")
        acao = request.match_info["acao"]
        if acao not in ("preparar", "instalar", "testar", "esquecer"):
            return self._refuse(404, "dispositivo_ausente", "ação desconhecida")
        # Trocar a chave ou apagar a identidade com a proteção ARMADA deixaria o
        # dispositivo armado e sem como falar com o aparelho — e a tela
        # continuaria dizendo "armada". Testar continua permitido: é leitura, e é
        # justamente o que confirma que o armamento ainda vale.
        if acao != "testar" and plugin.armed:
            return self._refuse(409, "armado",
                                "esta proteção está armada: ligue o modo ensaio antes de "
                                "mexer no acesso ao console")
        pc = plugin._holder.get()
        if acao != "esquecer" and not pc.udr7_ssh_host:
            return self._refuse(400, "validacao",
                                "preencha o endereço do console antes de preparar o acesso")
        # Uma de cada vez POR DISPOSITIVO: duas preparações simultâneas viam a
        # chave faltando e rodavam `ssh-keygen` no mesmo caminho.
        trava = self._travas_de_acesso.setdefault(plugin.id, asyncio.Lock())
        corpo: dict = {}
        if request.can_read_body:
            try:
                corpo = await request.json()
            except Exception:
                return self._refuse(400, "validacao", "corpo não é JSON")
        try:
          async with trava:
              if acao == "preparar":
                  return web.json_response(await asyncio.to_thread(
                      self._acesso_preparar, plugin, pc, sa,
                      bool(corpo.get("aceitar_identidade"))))
              if acao == "instalar":
                  senha = corpo.get("senha")
                  if not isinstance(senha, str) or not senha:
                      return self._refuse(400, "validacao", "informe a senha do console")
                  return web.json_response(await asyncio.to_thread(
                      self._acesso_instalar, plugin, pc, sa, senha))
              if acao == "testar":
                  return web.json_response(await asyncio.to_thread(
                      self._acesso_testar, plugin, pc, sa))
              await asyncio.to_thread(plugin.esquecer_acesso)
              return web.json_response({"esquecido": True})
        except sa.IdentidadeDivergente as exc:
            return self._refuse(409, "identidade_divergente", str(exc))
        except sa.SenhaRecusada as exc:
            return self._refuse(502, "senha_recusada", str(exc))
        except sa.AcessoError as exc:
            # Classificar por TEXTO mandava o dono trocar a senha do console por
            # causa de um endereço errado: "o console não pediu senha" contém a
            # palavra "senha" (revisão fria da 0.6.0).
            return self._refuse(502, "acesso_falhou", str(exc))

    # -- os quatro passos, fora do laço de eventos ---------------------------
    def _acesso_preparar(self, plugin, pc, sa, aceitar_identidade: bool) -> dict:
        chave = sa.garantir_chave(plugin.chave_path)
        linhas, impressao = sa.identidade_do_host(pc.udr7_ssh_host, pc.udr7_ssh_port)
        sa.gravar_identidade(plugin.known_hosts_path, pc.udr7_ssh_host, linhas,
                             porta=pc.udr7_ssh_port, substituir=aceitar_identidade)
        return {"chave_publica": chave.publica, "impressao_da_chave": chave.impressao,
                "impressao_do_console": impressao}

    def _acesso_instalar(self, plugin, pc, sa, senha: str) -> dict:
        chave = sa.garantir_chave(plugin.chave_path)
        sa.instalar_chave_com_senha(pc.udr7_ssh_host, pc.udr7_ssh_port, pc.udr7_ssh_user,
                                    senha, chave.publica, plugin.known_hosts_path)
        resultado = self._acesso_testar(plugin, pc, sa)
        del senha                       # daqui para a frente ela não existe mais
        return resultado

    def _acesso_testar(self, plugin, pc, sa) -> dict:
        from .protect import ssh_argv

        comandos = plugin.comandos_de_leitura()
        chave_gerida = os.path.exists(plugin.chave_path)
        pc_teste = pc if not chave_gerida else replace(pc, udr7_ssh_key=plugin.chave_path)
        saida = sa.testar_alcance(
            lambda comando: ssh_argv(pc_teste, plugin.known_hosts_path, comando), comandos)
        if not saida.get("model"):
            return {"alcance": False, "resposta": saida,
                    "motivo": "o console não respondeu — a chave ainda não foi aceita, "
                              "ou o endereço não é este"}
        return {"alcance": True, "resposta": saida,
                "registro": plugin.registrar_alcance(saida)}

    async def _h_river_cabo_get(self, _req: web.Request) -> web.Response:
        if self.supervisor is None:
            return web.json_response({"lendo": None, "pausado": False,
                                      "motivo": "este serviço não cuida do leitor do River"})
        return web.json_response(self.supervisor.estado().to_dict())

    async def _h_river_cabo_post(self, request: web.Request) -> web.Response:
        """Empresta o cabo ao aplicativo do fabricante, ou toma de volta.

        A interface de no-break do River é exclusiva: um leitor por vez (medido
        nos dois sentidos em 2026-09-04). Por isso isto existe como ATO explícito,
        com a tela dizendo quem está com o cabo — esconder a exclusividade seria
        mentir para o dono.
        """
        if self.supervisor is None:
            return self._refuse(501, "sem_supervisor",
                                "este serviço não cuida do leitor do River")
        try:
            corpo = await request.json()
        except Exception:
            return self._refuse(400, "validacao", "esperado {\"acao\": \"liberar\"|\"retomar\"}")
        acao = str(corpo.get("acao", "")).strip()
        if acao == "liberar":
            # Com proteção armada, largar o cabo é ficar cego para a queda.
            if any(plugin.armed for plugin in self.plugins):
                # Motivo PRÓPRIO, não o "armado" das rotas de configuração: o
                # app traduz pelo motivo, e a frase de lá ("ligue o ensaio antes
                # de mudar estes campos") não diz nada sobre emprestar o cabo.
                return self._refuse(409, "armado_emprestimo",
                                    "há proteção armada: desligue-a (modo ensaio) antes de "
                                    "emprestar o cabo, senão o serviço fica sem ver a queda")
            # Fora do laço de eventos: parar os dois processos com educação leva
            # até 10 s, e nesse tempo a API inteira (inclusive o fluxo de eventos
            # do app) ficaria muda (revisão fria da 0.5.0, 2.ª rodada).
            estado = await asyncio.to_thread(self.supervisor.pausar, "liberado pelo app")
        elif acao == "retomar":
            estado = await asyncio.to_thread(self.supervisor.retomar)
        else:
            return self._refuse(400, "validacao", "ação desconhecida: use liberar ou retomar")
        return web.json_response(estado.to_dict())

    async def _h_apagar_estado(self, _req: web.Request) -> web.Response:
        """Apaga o que o SERVIÇO criou nesta máquina, a pedido da tela.

        É a mesma limpeza que o serviço faz sozinho quando o pacote vai para o
        Lixo (remocao.py) — aqui, sem jogar o programa fora, e sem a saída do
        processo: quem desregistra o serviço em seguida é o app. O app roda como
        o dono e não consegue apagar o que um serviço de sistema escreveu; quem
        apaga é o próprio serviço, que é dono dos arquivos.

        O leitor e o servidor do no-break são PAUSADOS antes de apagar: no
        pacote, a configuração e os soquetes deles moram no diretório que sai, e
        apagar por baixo de processo vivo deixaria os dois falando com arquivos
        que não existem (revisão fria da 0.8.0). Pausado, o vigia não os
        ressuscita; se o dono cancelar o desregistro em seguida, o serviço
        segue vivo e mudo até reiniciar — e o reinício recria tudo.

        Duas cercas: nenhuma proteção armada (apagar a chave com a proteção
        ligada a deixaria armada e sem para onde mandar o comando), e a
        confirmação que a tela pede antes de chamar — ela nomeia cada coisa que
        sai.
        """
        if any(plugin.armed for plugin in self.plugins):
            return self._refuse(409, "armado_remocao",
                                "há proteção armada: desligue-a (modo ensaio) antes de "
                                "apagar o estado, senão ela ficaria armada sem a chave "
                                "que manda o comando")
        from . import remocao

        if self.supervisor is not None:
            await asyncio.to_thread(self.supervisor.pausar, "remoção pela tela")
        ups_conf = os.path.join(
            os.environ.get("RUB_NUT_ETC") or "/opt/homebrew/etc/nut", "ups.conf")
        apagados = await asyncio.to_thread(
            remocao.apagar_tudo, self.state_dir, ups_conf, log_json)
        log_json("WARN", "estado_apagado", arquivos=len(apagados))
        return web.json_response({"apagados": apagados})

    async def _h_river_desligar(self, _req: web.Request) -> web.Response:
        """Desliga o PRÓPRIO River — o ato mais destrutivo do sistema.

        Corta a energia de tudo o que estiver ligado nele. Três cercas, todas
        obrigatórias: trava de arquivo aberta (a API nunca a abre), nenhuma
        proteção armada (para não confundir com o desligamento do console), e a
        confirmação que a tela pede antes de chamar esta rota.
        """
        from .river_cmd import RiverCmdError

        if not self.cfg.river_poweroff_allowed:
            return self._refuse(409, "desligamento_bloqueado",
                                "desligar o River está bloqueado no arquivo do serviço. "
                                "Abra a trava e reinicie para poder usar este botão.")
        if any(plugin.armed for plugin in self.plugins):
            return self._refuse(409, "armado_desligamento",
                                "há proteção armada: desligue-a antes, para não haver duas "
                                "ordens de desligamento ao mesmo tempo")
        recusa = self._sem_conta_de_admin()
        if recusa is not None:
            return recusa
        alvo = self._alvo_river()
        from .river_cmd import desligar_o_aparelho

        def trava_ficou_aberta(exc) -> None:
            # Não é só registro: isto vai à linha do tempo do app, porque o
            # aparelho ficou desligável por qualquer programa desta máquina e o
            # dono precisa saber para reiniciar o leitor.
            log_json("ERROR", "killpower_flag_aberta", reason=str(exc)[:200])
            self.state.add_event(eventos.RIVER_TRAVA_ABERTA, {
                "detail": "não consegui fechar a trava de desligamento do "
                          "leitor; reinicie o serviço"})
            if self.history is not None:
                self.history.record_event(
                    eventos.RIVER_TRAVA_ABERTA,
                    "não consegui fechar a trava de desligamento do leitor")

        def conversa_com_o_aparelho() -> None:
            """As três conversas de soquete, fora do laço de eventos.

            Cada uma espera até 5 s; no laço, isso deixava a API muda justamente
            enquanto o dono acompanha o desligamento na tela. A sequência em si
            mora em `river_cmd`: é a MESMA que a ordem vinda do NUT executa.
            """
            desligar_o_aparelho(alvo, ao_nao_fechar_a_trava=trava_ficou_aberta)

        try:
            await asyncio.to_thread(conversa_com_o_aparelho)
        except RiverCmdError as exc:
            return self._refuse(502, "aparelho_recusou", str(exc))
        except OSError as exc:
            return self._refuse(502, "sem_servidor", _sem_servidor_humano(exc))
        self.state.add_event(eventos.RIVER_DESLIGADO, {"detail": "enviado pelo app"})
        if self.history is not None:
            self.history.record_event(eventos.RIVER_DESLIGADO, "enviado pelo app")
        log_json("WARN", eventos.RIVER_DESLIGADO, ups=self.cfg.nut_ups)
        return web.json_response({"status": "desligamento enviado ao River"})

    async def _h_river_aparelho(self, request: web.Request) -> web.Response:
        """Muda um ajuste DO APARELHO (hoje: o aviso de bateria fraca dele)."""
        from .river_cmd import RiverCmdError, gravar_variavel, ler_variavel

        try:
            corpo = await request.json()
        except Exception:
            return self._refuse(400, "validacao", "esperado um objeto com o ajuste")
        if "battery_charge_low" not in corpo:
            return self._refuse(400, "validacao",
                                "o único ajuste do aparelho que esta versão muda é o aviso "
                                "de bateria fraca")
        try:
            valor = int(corpo["battery_charge_low"])
        except (TypeError, ValueError):
            return self._refuse(400, "validacao", "o aviso de bateria fraca é um número")
        if not 0 <= valor <= 50:
            return self._refuse(400, "validacao", "o aviso de bateria fraca vai de 0 a 50")
        recusa = self._sem_conta_de_admin()
        if recusa is not None:
            return recusa
        alvo = self._alvo_river()
        def grava_e_confere() -> str | None:
            gravar_variavel(alvo, "battery.charge.low", str(valor))
            return ler_variavel(alvo, "battery.charge.low")

        try:
            atual = await asyncio.to_thread(grava_e_confere)
        except RiverCmdError as exc:
            return self._refuse(502, "aparelho_recusou", str(exc))
        except OSError as exc:
            return self._refuse(502, "sem_servidor", _sem_servidor_humano(exc))
        return web.json_response({"battery_charge_low": atual})

    # -- handlers ----------------------------------------------------------

    async def _h_state(self, _req: web.Request) -> web.Response:
        _version, snapshot, comm_ok, last_error = self.state.get()
        if snapshot is None:
            return web.json_response(_empty_state(self.cfg.river_name, comm_ok, last_error))
        return web.json_response(snapshot)

    async def _h_events(self, request: web.Request) -> web.StreamResponse:
        resp = web.StreamResponse(
            headers={
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            }
        )
        await resp.prepare(request)
        last_version = -1
        # A sequência do último evento entregue, nunca um índice: com a fila cheia
        # o índice congelava e o cliente parava de receber no 100.º evento.
        last_seq = -1
        try:
            while True:
                version, snapshot, comm_ok, last_error = self.state.get()
                if version != last_version:
                    last_version = version
                    payload = snapshot or _empty_state(
                        self.cfg.river_name, comm_ok, last_error
                    )
                    await resp.write(
                        f"event: state\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n".encode()
                    )
                    for event in self.state.events(after=last_seq):
                        await resp.write(
                            f"event: event\ndata: {json.dumps(event, ensure_ascii=False)}\n\n".encode()
                        )
                        last_seq = event["seq"]
                await asyncio.sleep(0.25)
        except (ConnectionResetError, asyncio.CancelledError):
            return resp

    async def _h_events_log(self, request: web.Request) -> web.Response:
        q = request.query
        try:
            ts_from = int(q.get("from", "0"))
            ts_to = int(q.get("to", str(2**33)))
            limit = int(q.get("limit", "200"))
            types = [t for t in q.get("types", "").split(",") if t] or None
            device = q.get("device") or None
            rows = self.history.query_events(ts_from, ts_to, types, limit, device=device)
        except ValueError as exc:
            return web.json_response({"erro": str(exc)}, status=400)
        return web.json_response({"rows": rows})

    async def _h_events_log_csv(self, request: web.Request) -> web.StreamResponse:
        return await self._csv(request, "eventos.csv", self.history.export_events_csv)

    async def _h_samples_csv(self, request: web.Request) -> web.StreamResponse:
        return await self._csv(request, "amostras.csv", self.history.export_samples_csv)

    async def _csv(self, request: web.Request, nome: str, exporta) -> web.StreamResponse:
        """Um CSV da faixa `from`..`to` (padrão: tudo até agora), em UTF-8 com BOM —
        é o que faz o Numbers e o Excel abrirem os acentos certos.

        Em FLUXO, não em memória: medido no Mac mini em 2026-09-06, a base tinha
        192.786 amostras em 5,6 dias (uma a cada 2,5 s), ≈ 65 bytes por linha de
        CSV; com a retenção máxima (`HISTORY_RETENTION_DAYS` = 365) o arquivo
        passaria de meio gigabyte. O SQLite é síncrono e roda numa thread; as
        linhas viajam para o laço em blocos por uma fila com limite, então a
        thread espera o cliente ler (contrapressão) em vez de encher a memória.
        """
        q = request.query
        try:
            ts_from = int(q.get("from", "0"))
            ts_to = int(q.get("to", str(int(time.time()))))
        except ValueError as exc:
            return web.json_response({"erro": str(exc)}, status=400)
        resp = web.StreamResponse(
            headers={"Content-Disposition": f'attachment; filename="{nome}"'})
        resp.content_type = "text/csv"
        resp.charset = "utf-8"
        await resp.prepare(request)
        await resp.write("\ufeff".encode("utf-8"))

        loop = asyncio.get_running_loop()
        fila: asyncio.Queue[bytes | None] = asyncio.Queue(maxsize=4)
        # O consumidor avisa a thread quando o cliente foi embora; sem isso a
        # thread ficava presa num `put` que ninguém drenava (revisão fria da
        # 0.9.0, medido: cada desconexão no meio do CSV prendia um worker do
        # executor e a conexão do SQLite, para sempre).
        cliente_foi = threading.Event()
        LINHAS_POR_BLOCO = 512

        class _ClienteFoi(Exception):
            pass

        def produz() -> None:
            bloco: list[str] = []

            def envia(pedaco: bytes | None) -> None:
                futuro = asyncio.run_coroutine_threadsafe(fila.put(pedaco), loop)
                while True:
                    try:
                        futuro.result(timeout=0.2)
                        return
                    except concurrent.futures.TimeoutError:
                        if cliente_foi.is_set():
                            raise _ClienteFoi()

            def escreve(texto: str) -> None:
                if cliente_foi.is_set():
                    raise _ClienteFoi()
                bloco.append(texto)
                if len(bloco) >= LINHAS_POR_BLOCO:
                    envia("".join(bloco).encode("utf-8"))
                    bloco.clear()

            try:
                exporta(ts_from, ts_to, escreve)
                if bloco:
                    envia("".join(bloco).encode("utf-8"))
            except _ClienteFoi:
                pass
            finally:
                if not cliente_foi.is_set():
                    envia(None)

        self._exportacoes_em_curso += 1
        produtor = asyncio.create_task(asyncio.to_thread(produz))
        try:
            while True:
                pedaco = await fila.get()
                if pedaco is None:
                    break
                await resp.write(pedaco)
            await resp.write_eof()
        finally:
            # Aconteça o que acontecer (cliente foi embora, erro do SQLite): a
            # thread tem de terminar. Avisa e drena a fila até ela acabar.
            cliente_foi.set()
            while not produtor.done():
                while not fila.empty():
                    fila.get_nowait()
                await asyncio.sleep(0.02)
            self._exportacoes_em_curso -= 1
            await produtor
        return resp

    async def _h_events_delete(self, request: web.Request) -> web.Response:
        # `to` is mandatory by design: an accidental parameterless DELETE must
        # never wipe the log. "Tudo" is the UI sending to=now explicitly.
        q = request.query
        if "to" not in q:
            return web.json_response(
                {"erro": "parâmetro to é obrigatório (limite superior da faixa)"},
                status=400,
            )
        try:
            ts_from = int(q.get("from", "0"))
            ts_to = int(q["to"])
            removed = self.history.delete_events(ts_from, ts_to)
            # A fila da memória é o que o SSE entrega a quem conecta: sem isto os
            # eventos apagados reapareciam na tela na reconexão seguinte.
            self.state.clear_events(ts_to, ts_from=ts_from)
        except ValueError as exc:
            return web.json_response({"erro": str(exc)}, status=400)
        return web.json_response({"removidos": removed})

    async def _h_history(self, request: web.Request) -> web.Response:
        q = request.query
        metric = q.get("metric", "charge")
        try:
            ts_from = int(q.get("from", "0"))
            ts_to = int(q.get("to", str(2**33)))
            bucket = int(q.get("bucket", "60"))
            rows = self.history.query(metric, ts_from, ts_to, bucket)
        except ValueError as exc:
            return web.json_response({"erro": str(exc)}, status=400)
        return web.json_response(
            {"metric": metric, "bucket_seconds": bucket, "rows": rows,
             "events": self.history.recent_events()}
        )

    async def _h_health(self, _req: web.Request) -> web.Response:
        return web.json_response(self.state.health())

    async def _h_config_get(self, _req: web.Request) -> web.Response:
        cfg = {name: getattr(self.cfg, name) for name in config_field_names()}
        return web.json_response({"config": cfg})

    async def _h_config_put(self, request: web.Request) -> web.Response:
        try:
            body = await request.json()
        except json.JSONDecodeError:
            return web.json_response({"erro": "corpo não é JSON"}, status=400)
        if not isinstance(body, dict) or not body:
            return web.json_response({"erro": "esperado objeto {CHAVE: valor}"}, status=400)

        parsed: dict[str, object] = {}
        for key, raw in body.items():
            try:
                parsed[key] = validate_update(str(key), str(raw))
            except ConfigError as exc:
                return web.json_response({"erro": str(exc)}, status=400)

        # A regra CRUZADA: uma chave sozinha pode ser válida e o conjunto não.
        # Apontar a proteção para um aparelho que a própria ponte publica fecha um
        # laço, e o serviço recusa subir com isso. Sem esta conferência aqui, o
        # PUT gravava, respondia "reinicie", e no reinício o serviço fazia parada
        # deliberada — que sob o launchd é a saída que NÃO relança. O dono ficava
        # sem proteção nenhuma, com uma linha de registro e uma tela que dissera
        # que tinha dado certo (revisão fria da 0.7.0).
        recusa_espelho = recusa_do_vigia_espelho(
            str(parsed.get("NUT_UPS", self.cfg.nut_ups)),
            str(parsed.get("RIVER_NUT_APARELHO", self.cfg.river_nut_aparelho)),
            publica=bool(parsed.get("RIVER_NUT_PUBLICA", self.cfg.river_nut_publica)),
            dispositivos={plugin.id for plugin in self.plugins},
        )
        if recusa_espelho is not None:
            return self._refuse(409, "vigia_espelho", recusa_espelho)

        # Order is a fence: validate -> authorize -> write -> apply. A refusal never
        # leaves a trace in the .env file.
        _version, snapshot, comm_ok, _err = self.state.get()
        recusa = self._cabo_emprestado(
            parsed.get("PROTECT_UDR7") is True or parsed.get("PROTECT_DRY_RUN") is False)
        if recusa is not None:
            return recusa
        refusal = _authorize(parsed, self.plugins, snapshot, comm_ok)
        if refusal is not None:
            status, motivo, mensagem = refusal
            return web.json_response({"erro": mensagem, "motivo": motivo}, status=status)

        try:
            update_env_file(self.env_path, {k: str(v) if not isinstance(v, bool) else ("1" if v else "0") for k, v in parsed.items()})
        except (EnvFileError, OSError) as exc:
            log_json("ERROR", "env_write_failed", path=self.env_path, reason=str(exc)[:200])
            if not _e_desarme_puro(parsed):
                # Nada foi aplicado ainda: o arquivo é o primeiro a ser escrito.
                # 500 aqui é a verdade — a mudança não valeu, nem agora nem no reinício.
                return self._refuse(500, "arquivo_env",
                                    "não consegui gravar a configuração do serviço no disco; "
                                    "nada foi alterado")
            # DESARMAR NUNCA É RECUSADO. Disco cheio é exatamente quando o dono
            # aperta o botão de parada; recusar aí seria travar a proteção armada
            # por causa de um arquivo. O estado em memória vale, e o arquivo fica
            # divergente com aviso — o próximo PUT que gravar o corrige.
            log_json("WARN", "desarme_aplicado_sem_gravar", keys=sorted(parsed))

        applied_hot: list[str] = []
        restart_required = False
        for key, value in parsed.items():
            if key in HOT_RELOAD_KEYS:
                # Fora de qualquer trava: quem lê `cfg` (a política, via
                # on_config_applied logo abaixo; as ordens do NUT, na chamada)
                # lê o objeto inteiro, e um atributo trocado é atômico em Python.
                setattr(self.cfg, key.lower(), value)
                applied_hot.append(key)
            else:
                restart_required = True
        for plugin in self.plugins:
            _emit(plugin.on_config_applied(self.cfg), self.state, self.history)
        # Espelho legado (.env → loja): um PUT em chave legada do UDR7 já entrou na
        # instância pelo on_config_applied; a loja é gravada para a verdade e o
        # espelho não divergirem. Sem loja (fixtures antigas), nada a gravar.
        if self.store is not None and any(
                key in getattr(plugin, "legacy_keys", ()) for plugin in self.plugins for key in parsed):
            try:
                self.store.save([plugin.instance for plugin in self.plugins if hasattr(plugin, "instance")])
            except OSError as exc:
                # MESMA regra da gravação do .env, e pelo mesmo motivo: aqui já
                # está aplicado em memória, e as chaves do desarme SÃO chaves
                # legadas — sem esta guarda, todo desarme com disco cheio saía
                # 500 cru, com a proteção desarmada por dentro e a tela dizendo
                # o contrário (revisão fria, 2.ª rodada).
                log_json("ERROR", "devices_write_failed", reason=str(exc)[:200])
                if not _e_desarme_puro(parsed):
                    return self._refuse(500, "arquivo_dispositivos",
                                        "a mudança valeu agora, mas não consegui gravá-la no "
                                        "disco; ela se perde no próximo reinício do serviço")
                log_json("WARN", "desarme_aplicado_sem_gravar", keys=sorted(parsed))
        # O health é atualizado no fim do PUT: sem isto a tela mostraria o estado
        # anterior até o próximo tick do laço (≤ POLL_INTERVAL_SECONDS).
        self.state.set_plugins(plugin_statuses(self.plugins))
        return web.json_response(
            {"aplicadas_a_quente": applied_hot, "restart_required": restart_required}
        )

    async def _h_restart(self, _req: web.Request) -> web.Response:
        if any(plugin.armed for plugin in self.plugins):
            return web.json_response(
                {"erro": "proteção armada: desligue a proteção antes de reiniciar; ou reinicie "
                         "pelo terminal (sudo launchctl kickstart -k system/com.river.unifi-bridge)",
                 "motivo": "armado"},
                status=409,
            )
        # 202 first; the callback fires outside the handler after the response
        # has been flushed (see module docstring for the race this avoids).
        if self._loop is None:
            # Servidor construído fora do `start_in_thread` (dublê de teste, uso
            # embutido): não há laço para agendar a saída. Recusar é honesto;
            # um `assert` viraria erro 500 sem explicação — ou sumiria com -O.
            return self._refuse(503, "servidor_sem_laco",
                                "o serviço não consegue se reiniciar sozinho agora; "
                                "reinicie pelo terminal")
        self._loop.call_later(RESTART_EXIT_DELAY_SECONDS, self.restart_cb)
        return web.json_response({"status": "reinício agendado"}, status=202)

    async def _h_version(self, _req: web.Request) -> web.Response:
        return web.json_response({"version": __version__})

    async def _h_device_types(self, _req: web.Request) -> web.Response:
        """O catálogo de TIPOS de dispositivo: o app confere os campos por tipo
        contra a sua metade de tela (escrita à mão), nunca gera formulário daqui."""
        return web.json_response({"types": type_catalog()})

    # -- instâncias de dispositivos protegidos (2026-09-03) --------------------
    #
    # Ordem de toda escrita, e ela é a cerca: validar → autorizar → gravar a loja
    # → aplicar no plugin → espelhar no .env (só a instância `udr7`) → health.
    # Uma recusa não deixa rastro em devices.json nem no .env.

    @staticmethod
    def _device_json(plugin) -> dict:
        st = plugin.status()
        return {**plugin.instance.to_json(), "armed": plugin.armed, "state": st["state"]}

    def _instances(self) -> list[DeviceInstance]:
        return [p.instance for p in self.plugins if hasattr(p, "instance")]

    @staticmethod
    def _refuse(status: int, motivo: str, mensagem: str) -> web.Response:
        return web.json_response({"erro": mensagem, "motivo": motivo}, status=status)

    def _mirror_udr7_to_env(self, instance: DeviceInstance, patch: dict) -> None:
        """A instância migrada continua espelhada no .env do Mac mini (D2)."""
        env_changes: dict[str, str] = {}
        for attr, key in LEGACY_ATTR_TO_KEY.items():
            if attr in patch:
                value = getattr(instance, attr)
                env_changes[key] = ("1" if value else "0") if isinstance(value, bool) else str(value)
                setattr(self.cfg, key.lower(), value)
        for field_name, value in (patch.get("fields") or {}).items():
            key = LEGACY_FIELD_TO_KEY.get(field_name)
            if key is not None:
                env_changes[key] = str(value)
                setattr(self.cfg, key.lower(), value)
        if env_changes:
            try:
                update_env_file(self.env_path, env_changes)
            except (EnvFileError, OSError) as exc:
                # A verdade é a loja de dispositivos, já gravada: a mudança VALEU.
                # O espelho no .env existe para quem voltar à 0.2.0, e a divergência
                # é registrada em vez de derrubar o pedido do usuário.
                log_json("WARN", "env_mirror_failed", path=self.env_path,
                         keys=sorted(env_changes), reason=str(exc)[:200])

    async def _h_devices_list(self, _req: web.Request) -> web.Response:
        return web.json_response({"devices": [self._device_json(p) for p in self.plugins
                                              if hasattr(p, "instance")]})

    async def _h_devices_get(self, request: web.Request) -> web.Response:
        plugin = self.plugins.get(request.match_info["id"])
        if plugin is None or not hasattr(plugin, "instance"):
            return self._refuse(404, "dispositivo_ausente", "não existe dispositivo com esse id")
        return web.json_response({"device": self._device_json(plugin)})

    async def _h_devices_post(self, request: web.Request) -> web.Response:
        if self.store is None or self.state_dir is None:
            return self._refuse(501, "sem_loja", "este serviço não gerencia dispositivos")
        try:
            body = await request.json()
        except json.JSONDecodeError:
            return web.json_response({"erro": "corpo não é JSON"}, status=400)
        if not isinstance(body, dict):
            return web.json_response({"erro": "esperado objeto {type, name, fields}"}, status=400)
        cls = TYPES.get(str(body.get("type", "")))
        if cls is None:
            return self._refuse(400, "tipo_desconhecido", "o serviço instalado não conhece este tipo de dispositivo")
        try:
            name = validate_fields((NAME_FIELD,), {"name": body.get("name", "")})["name"]
            enabled = validate_fields((_BOOL_ENABLED,), {"enabled": body.get("enabled", False)})["enabled"]
            dry_run = validate_fields((_BOOL_DRY_RUN,), {"dry_run": body.get("dry_run", True)})["dry_run"]
            fields = validate_fields(cls.fields, body.get("fields") or {})
        except DevicesError as exc:
            return self._refuse(400, "validacao", str(exc))
        # Armar é ato separado, pelo PUT, com trava + fonte real + confirmação.
        if enabled and not dry_run:
            return self._refuse(400, "armar_no_post", "um dispositivo nasce em ensaio; armar é pelo PUT")
        instances = self._instances()
        if self.store.name_taken(instances, name):
            return self._refuse(409, "nome_duplicado", "já existe um dispositivo com este nome")
        instance = DeviceInstance(
            id=new_id(cls.type_id.replace("_", "")), type=cls.type_id, name=name,
            enabled=enabled, dry_run=dry_run, fields=fields,
            created_at=now_iso(), updated_at=now_iso(),
        )
        try:
            plugin = cls.build(instance, self.cfg, self.state_dir)
            self.store.save(instances + [instance])
        except DevicesError as exc:
            return self._refuse(400, "validacao", str(exc))
        self.plugins.add(plugin)
        self.state.set_plugins(plugin_statuses(self.plugins))
        return web.json_response({"device": self._device_json(plugin)}, status=201)

    async def _h_devices_put(self, request: web.Request) -> web.Response:
        plugin = self.plugins.get(request.match_info["id"])
        if plugin is None or not hasattr(plugin, "instance"):
            return self._refuse(404, "dispositivo_ausente", "não existe dispositivo com esse id")
        try:
            body = await request.json()
        except json.JSONDecodeError:
            return web.json_response({"erro": "corpo não é JSON"}, status=400)
        if not isinstance(body, dict) or not body:
            return web.json_response({"erro": "esperado objeto {name?, enabled?, dry_run?, fields?}"}, status=400)
        if "type" in body or "id" in body:
            return self._refuse(400, "validacao", "type e id são imutáveis")
        unknown = sorted(set(body) - {"name", "enabled", "dry_run", "fields"})
        if unknown:
            return self._refuse(400, "validacao", f"campo desconhecido: {unknown[0]}")
        cls = TYPES[plugin.instance.type]
        patch: dict = {}
        try:
            if "name" in body:
                patch["name"] = validate_fields((NAME_FIELD,), {"name": body["name"]})["name"]
            if "enabled" in body:
                patch["enabled"] = validate_fields((_BOOL_ENABLED,), {"enabled": body["enabled"]})["enabled"]
            if "dry_run" in body:
                patch["dry_run"] = validate_fields((_BOOL_DRY_RUN,), {"dry_run": body["dry_run"]})["dry_run"]
            if "fields" in body:
                patch["fields"] = validate_fields(cls.fields, body["fields"] or {}, partial=True)
        except DevicesError as exc:
            return self._refuse(400, "validacao", str(exc))
        instances = self._instances()
        if "name" in patch and self.store is not None \
                and self.store.name_taken(instances, patch["name"], except_id=plugin.id):
            return self._refuse(409, "nome_duplicado", "já existe um dispositivo com este nome")
        _version, snapshot, comm_ok, _err = self.state.get()
        recusa = self._cabo_emprestado(
            patch.get("enabled") is True or patch.get("dry_run") is False)
        if recusa is not None:
            return recusa
        refusal = plugin.authorize_update(patch, snapshot, comm_ok)
        if refusal is not None:
            return self._refuse(*refusal)
        old = plugin.instance
        new = DeviceInstance(
            id=old.id, type=old.type,
            name=patch.get("name", old.name),
            enabled=patch.get("enabled", old.enabled), dry_run=patch.get("dry_run", old.dry_run),
            fields={**old.fields, **patch.get("fields", {})},
            created_at=old.created_at, updated_at=now_iso(),
        )
        if self.store is not None:
            try:
                self.store.save([new if i.id == old.id else i for i in instances])
            except DevicesError as exc:
                return self._refuse(400, "validacao", str(exc))
            except OSError as exc:
                log_json("ERROR", "devices_write_failed", reason=str(exc)[:200])
                if not _patch_e_desarme_puro(patch, old):
                    return self._refuse(500, "arquivo_dispositivos",
                                        "não consegui gravar a lista de dispositivos no disco; "
                                        "nada foi alterado")
                log_json("WARN", "desarme_aplicado_sem_gravar", device=old.id)
        _emit(plugin.apply_patch(new), self.state, self.history)
        if plugin.id == "udr7":
            self._mirror_udr7_to_env(new, patch)
        self.state.set_plugins(plugin_statuses(self.plugins))
        return web.json_response({"device": self._device_json(plugin)})

    async def _h_devices_delete(self, request: web.Request) -> web.Response:
        plugin = self.plugins.get(request.match_info["id"])
        if plugin is None or not hasattr(plugin, "instance"):
            return self._refuse(404, "dispositivo_ausente", "não existe dispositivo com esse id")
        if plugin.armed:  # DELETE nunca remove um dispositivo armado
            return self._refuse(409, "armado", (
                f"{plugin.instance.name} está armado — desligue a proteção (ligar modo ensaio) antes de remover"))
        if self.store is not None:
            self.store.save([i for i in self._instances() if i.id != plugin.id])
        self.plugins.remove(plugin.id)
        if self.state_dir is not None:
            # A chave e a prova de alcance saem junto: elas foram criadas por
            # NÓS para este dispositivo, e deixá-las no disco é deixar uma chave
            # privada órfã que ninguém sabe que existe. O `known_hosts` continua
            # ficando (pode ter sido semeado à mão).
            for suffix in ("_armed.json", "_runtime.json",
                           "_key", "_key.pub", "_acesso.json"):
                caminho = os.path.join(self.state_dir, f"{plugin.id}{suffix}")
                try:
                    os.unlink(caminho)
                except FileNotFoundError:
                    pass                      # não existir é o caso comum
                except OSError as exc:
                    log_json("WARN", "device_state_unlink_failed",
                             device=plugin.id, path=caminho, reason=str(exc)[:200])
            if os.path.exists(os.path.join(self.state_dir, f"{plugin.id}_known_hosts")):
                log_json("WARN", "known_hosts_kept", device=plugin.id,
                         reason="semeado à mão pelo dono; remoção é decisão dele")
        self.state.set_plugins(plugin_statuses(self.plugins))
        return web.Response(status=204)

    # -- lifecycle ---------------------------------------------------------

    def start_in_thread(self) -> None:
        def runner() -> None:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            self._loop = loop

            async def serve() -> None:
                app_runner = web.AppRunner(self.build_app())
                await app_runner.setup()
                site = web.TCPSite(app_runner, BIND_HOST, self.cfg.ui_api_port)
                await site.start()
                self.port = self.cfg.ui_api_port
                self._started.set()

            loop.run_until_complete(serve())
            loop.run_forever()

        self._thread = threading.Thread(target=runner, name="ui-api", daemon=True)
        self._thread.start()
        if not self._started.wait(timeout=10):
            raise RuntimeError("API local não subiu em 10 s")

    def stop(self) -> None:
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._loop.stop)
