"""Config loader for river-unifi-bridge.

House pattern (spec §22, mold ABHOME-macmini/macmini-backup.sh:452-464):
- .env style KEY=VALUE, parsed line by line — never `source`d;
- strict allowlist: unknown keys are reported with their line number;
- required keys must be present and non-empty;
- comments only on their own line;
- `~` expanded manually.

The SAME allowlist will validate PUT /v1/config in UI-0 (§7A.5) — single
source of truth for what a valid configuration is.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field, fields


class ConfigError(Exception):
    """Invalid or incomplete configuration (house exit code 3 at the CLI)."""


# key -> (type, required, default, (min, max) for ints)
_ALLOWLIST: dict[str, tuple[type, bool, object, tuple[int, int] | None]] = {
    "RIVER_NAME": (str, True, None, None),
    "NUT_HOST": (str, True, None, None),
    "NUT_PORT": (int, True, None, (1, 65535)),
    "NUT_UPS": (str, True, None, None),
    "POLL_INTERVAL_SECONDS": (int, False, 2, (1, 60)),
    # Defaults ancorados em fonte (docs/PESQUISA_PARAMETROS_UPS_20260831.md):
    # 6 = apcupsd ONBATTERYDELAY; 0 = NUT/apcupsd notificam restauração na hora;
    # 15 = NUT upsmon DEADTIME; 30 = fallback lowbatt do usbhid-ups (o LB do
    # NUT nunca dispara no River 3 Plus — issue NUT #3068).
    "POWER_LOSS_DELAY_SECONDS": (int, False, 6, (0, 600)),
    "RESTORE_DELAY_SECONDS": (int, False, 0, (0, 600)),
    "COMM_LOSS_DELAY_SECONDS": (int, False, 15, (0, 600)),
    "LOW_BATTERY_PERCENT": (int, False, 30, (5, 50)),
    # Fase 3'-EXP — proteção do UDR7 (spec §2.5/§7A.5/§22; runbook
    # docs/2026-09-01-0817-runbook-protecao-udr7-ssh.md). Nasce em ensaio; armar exige a trava
    # UDR7_ARM_ALLOWED (somente arquivo) + ato no app. Defaults sem fonte são 0
    # ("não configurado" → a política bloqueia); os demais têm fonte/marca no runbook.
    "PROTECT_UDR7": (bool, False, False, None),
    "PROTECT_DRY_RUN": (bool, False, True, None),
    "UDR7_ARM_ALLOWED": (bool, False, False, None),
    "UDR7_SSH_HOST": (str, False, "", None),
    "UDR7_SSH_PORT": (int, False, 22, (1, 65535)),
    "UDR7_SSH_USER": (str, False, "root", None),
    "UDR7_SSH_KEY": (str, False, "", None),
    "UDR7_EXPECTED_SERIAL": (str, False, "", None),
    "UDR7_CUTOFF_PERCENT": (int, False, 0, (0, 48)),
    "UDR7_SHUTDOWN_PERCENT": (int, False, 0, (0, 50)),
    "UDR7_DISCHARGE_SECONDS_PER_PCT": (int, False, 0, (0, 3600)),
    "UDR7_RUNTIME_MINUTES": (int, False, 0, (0, 60)),
    "UDR7_MIN_OUTAGE_SECONDS": (int, False, 0, (0, 3600)),
    "UDR7_CONFIRM_SECONDS": (int, False, 6, (0, 600)),
    "UDR7_RETRY_MAX": (int, False, 3, (0, 3)),
    "UDR7_WOL_MAC": (str, False, "", None),
    # O nome que o usuário dá ao dispositivo — aparece nos relatórios e gráficos.
    # Não entra em PROTECTION_KEYS: renomear com a proteção armada é permitido.
    "UDR7_NAME": (str, False, "UDR7", None),
    "UI_API_ENABLED": (bool, False, True, None),
    "UI_API_PORT": (int, False, 35493, (1024, 65535)),
    "HISTORY_RETENTION_DAYS": (int, False, 7, (1, 365)),
    # Leitura de potência pela porta serial do River (2026-09-04). O perfil de
    # no-break não publica consumo; a segunda porta do mesmo cabo publica. "auto"
    # procura a porta e aceita a que responder com a série esperada.
    "RIVER_SERIAL_ENABLED": (bool, False, True, None),
    "RIVER_SERIAL_PORT": (str, False, "auto", None),
    # Desligar o PRÓPRIO River corta a energia de tudo o que está nele. Trava de
    # ARQUIVO, como a de armamento: a API nunca a abre, e a tela só age com ela
    # aberta MAIS a confirmação do dono.
    "RIVER_POWEROFF_ALLOWED": (bool, False, False, None),
    # Mandar um dispositivo protegido desligar ou reiniciar AGORA, à mão. Terceira
    # trava de arquivo da casa, pelo mesmo motivo das outras duas: é ato
    # destrutivo num aparelho de produção. Fechada, a ordem nem é oferecida a
    # quem lê pelo NUT — a proteção automática continua valendo, com a trava dela.
    "DEVICE_CMD_ALLOWED": (bool, False, False, None),
    # O serviço cuida do driver e do servidor do NUT como filhos (ver
    # nut_supervisor.py). Desligado, quem cuida é você, por fora.
    "RIVER_NUT_MANAGED": (bool, False, True, None),
    # A ponte também PUBLICA no NUT: um aparelho com tudo o que ela sabe do River
    # (watts por tomada inclusive) e um por dispositivo protegido, para o Home
    # Assistant receber o mesmo que o app mostra. Ver nut_servico.py.
    "RIVER_NUT_PUBLICA": (bool, False, True, None),
    "RIVER_NUT_APARELHO": (str, False, "river-bridge", None),
    # O cabo do River é um só, e dois programas o querem. Ligado, o serviço larga
    # o cabo quando o aplicativo do fabricante abre e retoma quando ele fecha —
    # sem botão na tela (ver cabo_automatico.py). Nunca larga com proteção armada.
    "RIVER_CABO_AUTOMATICO": (bool, False, True, None),
}


_NAME_BAD = (r"\s~\x00-\x1f\x7f\u00ad\u061c\u180b-\u180e\u200b-\u200f\u2028-\u202e"
             r"\u2060-\u206f\u115f\u1160\u2800\u3164\ufe00-\ufe0f\ufeff\uffa0"
             r"\U000e0000-\U000e01ef")
_NAME_PATTERN = rf"(?=.{{1,32}}\Z)[^{_NAME_BAD}](?: ?[^{_NAME_BAD}])*"

# Fase 3'-EXP — shape of string keys that end up in an ssh argv or in a file path.
# Structure fences (first char alphanumeric/letter, no whitespace) so a value can
# never be parsed as an ssh option; sources/marks in docs/2026-09-01-0817-runbook-protecao-udr7-ssh.md.
# Nomeadas porque os campos de uma INSTÂNCIA de dispositivo (devices.json, desde
# 2026-09-03) usam as mesmas formas — uma regex, dois consumidores.
HOST_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}")
USER_PATTERN = re.compile(r"[A-Za-z][A-Za-z0-9._-]{0,31}")
KEY_PATH_PATTERN = re.compile(r"/[^\s~]+")
SERIAL_PATTERN = re.compile(r"[A-Za-z0-9-]{1,64}")
MAC_PATTERN = re.compile(r"[0-9A-Fa-f]{2}([:-])(?:[0-9A-Fa-f]{2}\1){4}[0-9A-Fa-f]{2}")
NAME_PATTERN = re.compile(_NAME_PATTERN)
UPS_NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,31}")
_PATTERNS: dict[str, re.Pattern[str]] = {
    "UDR7_SSH_HOST": HOST_PATTERN,
    "UDR7_SSH_USER": USER_PATTERN,
    "UDR7_SSH_KEY": KEY_PATH_PATTERN,
    "UDR7_EXPECTED_SERIAL": SERIAL_PATTERN,
    "UDR7_WOL_MAC": MAC_PATTERN,
    # O nome de um aparelho no NUT vira metade do nome de um arquivo de soquete e
    # entra inteiro no `ups.conf`: forma fechada, sem espaço nem barra.
    "RIVER_NUT_APARELHO": UPS_NAME_PATTERN,
    # UDR7_NAME é texto que o usuário escolhe, então a regra é de FORMA, não de
    # conteúdo: 1 a 32 caracteres (o lookahead conta o total — sem ele o {0,30}
    # limitaria só os não-brancos e "aaa…" com 61 passaria), espaço apenas U+0020 e
    # só simples entre dois não-brancos. Proibidos: controle, `\s`, `~` (load_config
    # expande `~` em toda string), e a família de invisíveis que deixaria um nome
    # "parecer UDR7" sem ser — hífen suave, zero-width, BOM, bidi (ALM incluído),
    # preenchedores Hangul, braille em branco, variation selectors (BMP, mongóis e
    # suplementares) e tags. A classe vai com escapes \uXXXX de propósito: colar os
    # caracteres de verdade já corrompeu a classe uma vez, criando um range acidental
    # que rejeitava "Meu UDR". Homóglifos (cirílico) e combinantes ficam de fora por
    # natureza — lacuna declarada.
    "UDR7_NAME": NAME_PATTERN,
}
# Values that are syntactically fine but must never be accepted: the simulator's
# serial would make synthetic telemetry look "registered" (fence M1).
_FORBIDDEN_VALUES: dict[str, dict[str, str]] = {
    "UDR7_EXPECTED_SERIAL": {"SIM0001": "serial_de_simulador"},
}


def _validate_str(key: str, value: str, where: str = "") -> None:
    """Shape check for a non-empty string value (same rule for file and PUT)."""
    pattern = _PATTERNS.get(key)
    if pattern is not None and pattern.fullmatch(value) is None:
        raise ConfigError(f"{where}{key}: valor inválido para o formato exigido")
    reason = _FORBIDDEN_VALUES.get(key, {}).get(value)
    if reason is not None:
        raise ConfigError(f"{where}{key}: valor recusado ({reason})")


@dataclass
class BridgeConfig:
    river_name: str
    nut_host: str
    nut_port: int
    nut_ups: str
    poll_interval_seconds: int = 2
    power_loss_delay_seconds: int = 6
    restore_delay_seconds: int = 0
    comm_loss_delay_seconds: int = 15
    low_battery_percent: int = 30
    protect_udr7: bool = False
    protect_dry_run: bool = True
    udr7_arm_allowed: bool = False
    udr7_ssh_host: str = ""
    udr7_ssh_port: int = 22
    udr7_ssh_user: str = "root"
    udr7_ssh_key: str = ""
    udr7_expected_serial: str = ""
    udr7_cutoff_percent: int = 0
    udr7_shutdown_percent: int = 0
    udr7_discharge_seconds_per_pct: int = 0
    udr7_runtime_minutes: int = 0
    udr7_min_outage_seconds: int = 0
    udr7_confirm_seconds: int = 6
    udr7_retry_max: int = 3
    udr7_wol_mac: str = ""
    udr7_name: str = "UDR7"
    ui_api_enabled: bool = True
    ui_api_port: int = 35493
    history_retention_days: int = 7
    river_serial_enabled: bool = True
    river_serial_port: str = "auto"
    river_poweroff_allowed: bool = False
    device_cmd_allowed: bool = False
    river_nut_managed: bool = True
    river_nut_publica: bool = True
    river_nut_aparelho: str = "river-bridge"
    river_cabo_automatico: bool = True
    # Diagnostics for the caller (never fatal): "<line>: <message>"
    warnings: list[str] = field(default_factory=list)


def _parse_bool(raw: str) -> bool:
    if raw in ("1", "true", "TRUE", "yes"):
        return True
    if raw in ("0", "false", "FALSE", "no"):
        return False
    raise ValueError(f"valor booleano inválido: {raw!r} (use 1/0)")


def load_config(path: str) -> BridgeConfig:
    """Parse `path` against the allowlist. Raises ConfigError on violations."""
    if not os.path.isfile(path):
        raise ConfigError(f"arquivo de configuração não encontrado: {path}")

    values: dict[str, object] = {}
    warnings: list[str] = []

    with open(path, encoding="utf-8") as fh:
        for lineno, raw_line in enumerate(fh, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ConfigError(f"{path}:{lineno}: linha sem '=' — comentário só em linha própria")
            key, _, raw_value = line.partition("=")
            key = key.strip()
            value = raw_value.strip()

            if key not in _ALLOWLIST:
                warnings.append(f"{path}:{lineno}: chave desconhecida ignorada: {key}")
                continue

            typ, _required, _default, bounds = _ALLOWLIST[key]
            if value == "":
                # Empty value: treated below as absent (required check decides).
                continue
            if typ is str:
                _validate_str(key, value, f"{path}:{lineno}: ")
            value = value.replace("~", os.path.expanduser("~")) if typ is str else value
            try:
                if typ is bool:
                    parsed: object = _parse_bool(value)
                elif typ is int:
                    parsed = int(value)
                else:
                    parsed = value
            except ValueError as exc:
                raise ConfigError(f"{path}:{lineno}: {key}: {exc}") from exc

            if typ is int and bounds is not None:
                low, high = bounds
                if not (low <= parsed <= high):  # type: ignore[operator]
                    raise ConfigError(
                        f"{path}:{lineno}: {key}={parsed} fora da faixa [{low}, {high}]"
                    )
            values[key] = parsed

    missing = [k for k, (_, req, _, _) in _ALLOWLIST.items() if req and k not in values]
    if missing:
        raise ConfigError(f"{path}: chaves obrigatórias ausentes ou vazias: {', '.join(missing)}")

    kwargs: dict[str, object] = {}
    for key, (_typ, required, default, _bounds) in _ALLOWLIST.items():
        kwargs[key.lower()] = values.get(key, default)
    cfg = BridgeConfig(**kwargs)  # type: ignore[arg-type]
    recusa = recusa_do_vigia_espelho(cfg.nut_ups, cfg.river_nut_aparelho,
                                     publica=cfg.river_nut_publica)
    if recusa is not None:
        raise ConfigError(f"{path}: {recusa}")
    cfg.warnings = warnings
    return cfg


def recusa_do_vigia_espelho(nut_ups: str, aparelho: str, *, publica: bool,
                            dispositivos: "frozenset[str] | set[str] | tuple" = ()
                            ) -> str | None:
    """A proteção não pode ler um aparelho publicado por NÓS. Devolve o motivo.

    A ponte publica no NUT um aparelho com tudo o que ela sabe do River, e mais um
    por dispositivo protegido. Se a política de proteção fosse apontada para
    qualquer um deles, ela decidiria desligar um roteador com base em dados que
    ela mesma escreveu — um laço fechado, em que um erro de leitura vira verdade e
    se confirma sozinho a cada volta.

    Devolve texto (e não levanta) porque os DOIS caminhos precisam dela: o arquivo,
    na partida, e a tela, antes de gravar. Só no arquivo não bastava — um PUT
    gravava a configuração ruim, respondia "reinicie", e no reinício o serviço
    parava de propósito e não voltava mais (revisão fria da 0.7.0).
    """
    if not publica:
        return None
    if nut_ups == aparelho:
        return (f"NUT_UPS={nut_ups} é o aparelho que a própria ponte publica. "
                "A proteção tem de ler o leitor de fábrica (por exemplo river-office); "
                "lendo o nosso, ela decidiria com dados que ela mesma escreveu.")
    if nut_ups in set(dispositivos):
        return (f"NUT_UPS={nut_ups} é um dispositivo protegido, que a ponte também "
                "publica no NUT. A proteção tem de ler o leitor de fábrica; lendo "
                "esse, ela decidiria com dados que ela mesma escreveu.")
    return None


# §7A.5 — which changed keys apply live vs. require a service restart.
HOT_RELOAD_KEYS = frozenset(
    {
        "POLL_INTERVAL_SECONDS",
        "POWER_LOSS_DELAY_SECONDS",
        "RESTORE_DELAY_SECONDS",
        "COMM_LOSS_DELAY_SECONDS",
        "LOW_BATTERY_PERCENT",
        "HISTORY_RETENTION_DAYS",
        "RIVER_SERIAL_ENABLED",
        "RIVER_SERIAL_PORT",
        # Fase 3'-EXP: tudo da proteção aplica a quente, exceto a trava (arquivo).
        "PROTECT_UDR7",
        "PROTECT_DRY_RUN",
        "UDR7_SSH_HOST",
        "UDR7_SSH_PORT",
        "UDR7_SSH_USER",
        "UDR7_SSH_KEY",
        "UDR7_EXPECTED_SERIAL",
        "UDR7_CUTOFF_PERCENT",
        "UDR7_SHUTDOWN_PERCENT",
        "UDR7_DISCHARGE_SECONDS_PER_PCT",
        "UDR7_RUNTIME_MINUTES",
        "UDR7_MIN_OUTAGE_SECONDS",
        "UDR7_CONFIRM_SECONDS",
        "UDR7_RETRY_MAX",
        "UDR7_WOL_MAC",
        "UDR7_NAME",
    }
)

# Fase 3'-EXP — trava de armamento: só o arquivo .env (nunca o PUT) a abre/fecha.
FILE_ONLY_KEYS = frozenset({"UDR7_ARM_ALLOWED", "RIVER_POWEROFF_ALLOWED",
                            "DEVICE_CMD_ALLOWED"})
# Conjunto congelado enquanto o daemon está armado (PUT → 409 `armado`), com a única
# exceção do desarme (PUT contendo só as chaves do predicado que o torna falso).
# O nome do dispositivo tem prefixo UDR7_ mas NÃO é configuração de proteção: pode
# ser trocado com o daemon armado. Sem o `- DEVICE_NAME_KEYS` o prefixo o engoliria.
DEVICE_NAME_KEYS = frozenset({"UDR7_NAME"})
# Chaves do NÚCLEO que toda instância de dispositivo protegido congela enquanto
# armada: as três do NUT (decidem QUAL fonte alimenta a política) e as duas do
# River que as cercas de tempo de execução leem para qualquer instância — o
# número de série esperado e o corte físico da saída (decisão D16, 2026-09-03).
CORE_FROZEN_KEYS = frozenset({
    "NUT_HOST", "NUT_PORT", "NUT_UPS", "UDR7_EXPECTED_SERIAL", "UDR7_CUTOFF_PERCENT",
})
# As três chaves com prefixo UDR7_ que NÃO pertencem à instância migrada `udr7` e
# sim ao núcleo: a trava global de armamento (somente arquivo) e as duas do River
# acima. O nome ficou pelo .env do Mac mini; a semântica é do núcleo (D3/D16).
LEGACY_CORE_KEYS = frozenset({"UDR7_ARM_ALLOWED", "UDR7_EXPECTED_SERIAL", "UDR7_CUTOFF_PERCENT"})
PROTECTION_KEYS = (
    frozenset(
        {k for k in _ALLOWLIST if k.startswith(("PROTECT_", "UDR7_"))}
        | CORE_FROZEN_KEYS
    )
    - DEVICE_NAME_KEYS
)


def validate_update(key: str, raw_value: str) -> object:
    """Validate one KEY=raw_value pair with the SAME rules as load_config.

    Used by PUT /v1/config — single source of truth for what is valid.
    Raises ConfigError naming the key on any violation.
    """
    if key not in _ALLOWLIST:
        raise ConfigError(f"chave desconhecida: {key}")
    typ, required, _default, bounds = _ALLOWLIST[key]
    value = str(raw_value).strip()
    if value == "":
        if required:
            raise ConfigError(f"{key}: valor obrigatório não pode ser vazio")
        if typ is not str:
            # Vazio só faz sentido em texto (um nome, um host que se limpa). Num
            # número ou num booleano, a string vazia era aceita, gravada a quente
            # no config e derrubava o serviço no tick seguinte, ao comparar texto
            # com número.
            raise ConfigError(f"{key}: valor vazio")
        return ""
    if typ is str:
        _validate_str(key, value)
    try:
        if typ is bool:
            parsed: object = _parse_bool(value)
        elif typ is int:
            parsed = int(value)
        else:
            parsed = value
    except ValueError as exc:
        raise ConfigError(f"{key}: {exc}") from exc
    if typ is int and bounds is not None:
        low, high = bounds
        if not (low <= parsed <= high):  # type: ignore[operator]
            raise ConfigError(f"{key}={parsed} fora da faixa [{low}, {high}]")
    return parsed


def config_field_names() -> list[str]:
    return [f.name for f in fields(BridgeConfig) if f.name != "warnings"]
