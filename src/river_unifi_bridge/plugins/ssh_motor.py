"""O motor SSH comum aos tipos que desligam um aparelho por `ssh` (2026-09-03).

Compõe `ProtectionPolicy` + `ConfigHolder` de `protect.py` (que não se move) para
UMA instância: caminhos de estado por id (`<id>_known_hosts`, `<id>_armed.json`,
`<id>_runtime.json`), ações etiquetadas com o dono (`device`, `device_name`) e o
prefixo de evento do tipo, e as regras de armamento que antes viviam no adaptador
do UDR7 — agora sobre o patch de uma instância (`enabled`, `dry_run`, `name`,
`fields`), que é o que `PUT /v1/devices/{id}` recebe.

O que cada TIPO acrescenta: `type_id`, rótulos, `default_name`, `event_prefix`,
`fields` (FieldSpec) e `shutdown_command_for(instance)` — a tabela de comandos do
UDR7 ou o comando escolhido de uma lista fechada no host genérico.
"""

from __future__ import annotations

import os
import time
from dataclasses import replace

from ..config import CORE_FROZEN_KEYS
from ..protect import (
    SUBPROCESS_TIMEOUT_SECONDS, ConfigHolder, ProtectionConfig, ProtectionPolicy,
    _is_synthetic_driver, _read_private_json, _write_private_json, ssh_argv,
)

def _com_chave_gerida(pc: ProtectionConfig, chave_path: str) -> ProtectionConfig:
    """A chave que o SERVIÇO criou manda sobre o campo digitado.

    Ela é a que a tela instalou no console; o campo continua valendo para quem
    trouxer a própria chave, e para quem não usa o fluxo da tela.
    """
    if chave_path and os.path.exists(chave_path):
        return replace(pc, udr7_ssh_key=chave_path)
    return pc


# Por quanto tempo uma prova de alcance vale. Endereço muda, chave é revogada,
# console é trocado: prova velha não diz nada sobre hoje.
ALCANCE_VALIDADE_SEGUNDOS = 30 * 86400
from .base import DevicePlugin

# As duas chaves do patch que formam o predicado de armamento. Um PUT que só as
# toca e torna `armed` falso é um desarme puro — sempre aceito (o botão de parada).
_PREDICATE_KEYS = frozenset({"enabled", "dry_run"})


def _is_pure_disarm(changes: dict, pc: ProtectionConfig) -> bool:
    if not set(changes) <= _PREDICATE_KEYS:
        return False
    enabled = changes.get("enabled", pc.protect_udr7)
    dry_run = changes.get("dry_run", pc.protect_dry_run)
    return not (bool(enabled) and not bool(dry_run))


class SshMotorPlugin(DevicePlugin):
    frozen_keys = CORE_FROZEN_KEYS
    legacy_keys: frozenset[str] = frozenset()

    def __init__(self, instance, holder: ConfigHolder, policy: ProtectionPolicy, cfg=None,
                 *, chave_path: str = "", acesso_path: str = "",
                 known_hosts_path: str = "") -> None:
        self.instance = instance
        self.id = instance.id
        self._holder = holder
        self._policy = policy
        self._cfg = cfg
        self.chave_path = chave_path
        self._acesso_path = acesso_path
        self.known_hosts_path = known_hosts_path

    # --- o que cada tipo define ------------------------------------------------
    @classmethod
    def shutdown_command_for(cls, instance) -> str:   # pragma: no cover — abstrato por contrato
        raise NotImplementedError

    @classmethod
    def state_paths(cls, instance_id: str, state_dir: str) -> dict:
        return {
            "known_hosts_path": os.path.join(state_dir, f"{instance_id}_known_hosts"),
            "armed_path": os.path.join(state_dir, f"{instance_id}_armed.json"),
            "runtime_path": os.path.join(state_dir, f"{instance_id}_runtime.json"),
        }

    @classmethod
    def comandos_de_leitura(cls) -> dict[str, str]:
        """Os comandos que provam alcance sem tocar em nada. Cada tipo diz os seus."""
        return {}

    # --- ordens que o dono dá à mão --------------------------------------------
    # A proteção age sozinha numa queda de energia. Isto aqui é outra coisa: o
    # dono (pela tela ou pelo Home Assistant) manda AGORA. O tipo diz o que sabe
    # mandar; o que ele não souber, não é oferecido a ninguém.
    def acoes_manuais(self) -> dict[str, str]:
        """`{nome da ação: comando remoto}` deste dispositivo."""
        return {"desligar": self.shutdown_command_for(self.instance)}

    def executar_acao(self, acao: str, *, runner=None) -> str:
        """Manda a ordem pelo MESMO caminho que a proteção usa para desligar.

        Uma só cerca, e ela é a que importa: sem alcance provado, não se manda
        nada. Provar por outro caminho não diria nada sobre este, e é este que
        corta a energia do aparelho de alguém.

        O modo ensaio NÃO vale aqui de propósito: ele governa o que a proteção
        faz SOZINHA numa queda. Uma ordem que o dono dá agora é uma ordem — um
        botão que não faz nada seria pior que botão nenhum.

        Devolve texto vazio quando deu certo, ou o motivo em português.
        """
        comando = self.acoes_manuais().get(acao)
        if comando is None:
            return f"este dispositivo não sabe {acao}"
        if not self.alcance_valido():
            return ("ainda não foi provado que este serviço alcança o aparelho: "
                    "use Testar conexão na tela do dispositivo")
        from ..protect import _RUNNER
        argv = ssh_argv(self._holder.get(), self.known_hosts_path, comando)
        try:
            resultado = (runner or _RUNNER)(
                argv, capture_output=True, timeout=SUBPROCESS_TIMEOUT_SECONDS, check=False)
        except Exception as exc:                 # tempo esgotado, ssh ausente, …
            return f"{type(exc).__name__}: {exc}"[:200]
        if getattr(resultado, "returncode", None) == 0:
            return ""
        erro = getattr(resultado, "stderr", b"") or b""
        if isinstance(erro, bytes):
            erro = erro.decode("utf-8", "replace")
        return (erro.strip()[:200]
                or f"o aparelho respondeu {getattr(resultado, 'returncode', None)}")

    @classmethod
    def caminhos_do_acesso(cls, instance_id: str, state_dir: str) -> dict:
        """A chave que o SERVIÇO cria e o registro da prova de alcance.

        Não são campos digitáveis, e não podem ser: o padrão de caminho recusa
        espaços (`config.KEY_PATH_PATTERN`) e o diretório de estado do macOS é
        "~/Library/Application Support/…". Derivar do id resolve, do mesmo jeito
        que já resolvemos para o arquivo de identidades do console.
        """
        return {
            "chave": os.path.join(state_dir, f"{instance_id}_key"),
            "acesso": os.path.join(state_dir, f"{instance_id}_acesso.json"),
        }

    @classmethod
    def build(cls, instance, cfg, state_dir: str) -> "SshMotorPlugin":
        command = cls.shutdown_command_for(instance)
        acesso = cls.caminhos_do_acesso(instance.id, state_dir)
        pc = _com_chave_gerida(
            ProtectionConfig.from_instance(instance, cfg, shutdown_command=command),
            acesso["chave"])
        holder = ConfigHolder(pc)
        caminhos = cls.state_paths(instance.id, state_dir)
        policy = ProtectionPolicy(
            holder, shutdown_command=command, default_name=cls.default_name,
            **caminhos,
        )
        return cls(instance, holder, policy, cfg,
                   chave_path=acesso["chave"], acesso_path=acesso["acesso"],
                   known_hosts_path=caminhos["known_hosts_path"])

    # --- o que o laço chama --------------------------------------------------------
    @property
    def armed(self) -> bool:
        return self._holder.get().armed

    def _event_name(self, event: str | None) -> str | None:
        """O motor fala UDR7_*; cada tipo publica com o SEU prefixo."""
        if event is not None and event.startswith("UDR7_"):
            return self.event_prefix + event[len("UDR7_"):]
        return event

    def nome_de_evento(self, sufixo: str) -> str:
        """O nome de um evento deste TIPO — `UDR7_ORDEM_ENVIADA`, `SSH_HOST_…`.

        Existe porque o nome de evento é **vocabulário fechado**: a tela traduz
        cada um para uma frase em português, e um nome que ela não conheça
        aparece cru, em maiúsculas com sublinhados, na linha do tempo do dono.
        Montar o nome a partir do ID da instância (`f"{id.upper()}_…"`) parecia
        funcionar e criava um nome novo por dispositivo — impossível de traduzir.
        O prefixo é do TIPO, e é só isso que a tela precisa conhecer.
        """
        return f"{self.event_prefix}{sufixo}"

    def _tag(self, actions: list) -> list:
        """Toda ação sai com o dono e com o prefixo de evento do tipo."""
        name = self._holder.get().udr7_name or self.default_name
        for action in actions:
            action.event = self._event_name(action.event)
            action.payload["device"] = self.id
            action.payload["device_name"] = name
        return actions

    def observe(self, snap, tracker_events: list[str]) -> list:
        return self._tag(self._policy.observe(snap, tracker_events))

    def observe_failure(self, tracker_events: list[str]) -> list:
        return self._tag(self._policy.observe_failure(tracker_events))

    def _rebuild(self) -> list:
        """Reconstrói a configuração da política a partir da instância + núcleo.

        `holder.replace` corre FORA da trava da política (o holder tem a sua);
        a política só é avisada quando algo mudou — é ela que grava/apaga o
        `<id>_armed.json` e emite ARMED/DISARMED.
        """
        # A chave gerida entra AQUI também, e não só no boot. Sem isto, o
        # primeiro salvamento (ou qualquer mudança do núcleo) remontava a
        # configuração a partir dos campos digitados — onde o caminho da chave
        # está vazio, porque no fluxo novo o dono não digita caminho nenhum. A
        # proteção armava e ficava em "configuração incompleta": na queda de
        # energia, nada seria enviado (revisão fria da 0.6.0, medido).
        new = _com_chave_gerida(
            ProtectionConfig.from_instance(
                self.instance, self._cfg,
                shutdown_command=self.shutdown_command_for(self.instance)),
            self.chave_path)
        old = self._holder.get()
        self._holder.replace(new)
        if new == old:
            return []
        return self._tag(self._policy.on_config_applied(old, new))

    def on_config_applied(self, cfg) -> list:
        """O NÚCLEO mudou (NUT, trava, série esperada, corte): refresca esta instância."""
        self._cfg = cfg
        return self._rebuild()

    def apply_patch(self, instance) -> list:
        self.instance = instance
        return self._rebuild()

    def status(self) -> dict:
        st = self._policy.status()
        st["last_event"] = self._event_name(st.get("last_event"))   # o health fala a língua do tipo
        # A tela precisa saber ANTES de tentar armar: sem isto, o botão convidava
        # ao erro e a recusa só aparecia depois do clique.
        registro = self.alcance_registrado() or {}
        st["alcance_verificado"] = self.alcance_valido()
        st["alcance_modelo"] = registro.get("modelo")
        st["alcance_em"] = registro.get("verificado_em")
        return st

    def drain_transition(self) -> tuple[str | None, str] | None:
        return self._policy.drain_transition()

    # --- autorização ----------------------------------------------------------------
    def authorize(self, changes: dict, snapshot: dict | None,
                  comm_ok: bool) -> tuple[int, str, str] | None:
        """PUT /v1/config: as chaves do núcleo que esta instância congela quando armada."""
        pc = self._holder.get()
        if pc.armed:
            touched = sorted(set(changes) & self.frozen_keys)
            if touched:
                return 409, "armado", (
                    f"{touched[0]}: configuração congelada enquanto {pc.udr7_name or self.default_name} "
                    "está armado — desligue a proteção (ligar modo ensaio) antes")
        return None

    def authorize_update(self, changes: dict, snapshot: dict | None,
                         comm_ok: bool) -> tuple[int, str, str] | None:
        """§7A.5 sobre o patch de UMA instância. Corre ANTES de qualquer escrita.

        `changes` traz um subconjunto de {name, enabled, dry_run, fields}. O nome
        nunca é congelado (renomear armado é permitido); tudo o mais é.
        """
        pc = self._holder.get()
        enabled_after = changes.get("enabled", pc.protect_udr7)
        dry_run_after = changes.get("dry_run", pc.protect_dry_run)
        armed_after = bool(enabled_after) and not bool(dry_run_after)
        if pc.armed:
            if _is_pure_disarm(changes, pc):
                return None
            touched = sorted(set(changes) - {"name"})
            if touched:
                return 409, "armado", (
                    f"{touched[0]}: configuração congelada enquanto {pc.udr7_name or self.default_name} "
                    "está armado — desligue a proteção (ligar modo ensaio) antes")
            return None
        if armed_after:
            if not pc.udr7_arm_allowed:
                return 409, "armamento_bloqueado", (
                    "trava fechada: ligue \"Permitir armar a proteção\" em Ajustes › Travas antes de armar")
            if snapshot is None or not comm_ok:
                return 409, "sem_snapshot", "sem leitura corrente do NUT — não há como verificar a fonte"
            source = snapshot.get("source") or {}
            name, version = source.get("driver_name"), source.get("driver_version")
            if not name or not version or _is_synthetic_driver(name, version):
                return 409, "fonte_nao_real", (
                    "a fonte de telemetria corrente não é aceita para armar "
                    f"(driver {name!r} {version!r})")
            expected = pc.udr7_expected_serial
            serial = (snapshot.get("identity") or {}).get("serial")
            if not expected or serial != expected:
                return 409, "fonte_nao_real", (
                    "serial da leitura corrente não confere com o número de série esperado do River")
            if not self.alcance_valido():
                # O portão que faltava: até aqui a proteção podia armar sem NUNCA
                # ter falado com o console, e o primeiro contato real seria o
                # desligamento, numa queda. Provar alcance é rodar os comandos de
                # leitura pelo MESMO caminho do comando que desliga.
                return 409, "alcance_nao_verificado", (
                    "ainda não foi provado que este serviço alcança o console: "
                    "use Testar conexão na tela do dispositivo antes de armar")
        return None

    # --- prova de alcance ------------------------------------------------------
    def alcance_valido(self, *, agora: float | None = None) -> bool:
        """Houve prova de alcance recente o bastante para armar?

        Recente porque endereço muda, chave é revogada e console é trocado — uma
        prova de um ano atrás não diz nada sobre hoje.
        """
        registro = self.alcance_registrado()
        if not registro:
            return False
        quando = registro.get("verificado_em")
        if not isinstance(quando, (int, float)):
            return False
        agora = time.time() if agora is None else agora
        return (agora - quando) <= ALCANCE_VALIDADE_SEGUNDOS

    def alcance_registrado(self) -> dict | None:
        return _read_private_json(self._acesso_path)

    def registrar_alcance(self, saida: dict) -> dict:
        """Grava a prova de que falamos com o console, com data e o que ele disse."""
        registro = {"verificado_em": time.time(),
                    "modelo": saida.get("model"), "firmware": saida.get("firmware"),
                    "desligamento_disponivel": bool(saida.get("probe"))}
        _write_private_json(self._acesso_path, registro)
        return registro

    def esquecer_acesso(self) -> None:
        """Apaga chave, identidade e prova — o dispositivo volta ao ponto zero."""
        for caminho in (self.chave_path, f"{self.chave_path}.pub",
                        self.known_hosts_path, self._acesso_path):
            try:
                os.remove(caminho)
            except OSError:
                pass
