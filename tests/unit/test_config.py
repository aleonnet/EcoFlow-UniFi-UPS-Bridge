"""Fence tests for the .env allowlist parser (spec §22).

These are the tests the gate's mutation scene relies on: if the allowlist or
the required-key check is removed from config.py, they MUST fail.
"""

import pytest

from river_unifi_bridge.config import _ALLOWLIST, ConfigError, load_config

MINIMAL = """RIVER_NAME=river-office
NUT_HOST=127.0.0.1
NUT_PORT=3493
NUT_UPS=river-office
"""


def write(tmp_path, content):
    path = tmp_path / "bridge.env"
    path.write_text(content, encoding="utf-8")
    return str(path)


def test_minimal_config_parses_with_defaults(tmp_path):
    cfg = load_config(write(tmp_path, MINIMAL))
    assert cfg.river_name == "river-office"
    assert cfg.nut_port == 3493
    assert cfg.poll_interval_seconds == 2
    assert cfg.ui_api_port == 35493
    assert cfg.warnings == []


def test_unknown_key_is_reported_with_line_number(tmp_path):
    cfg = load_config(write(tmp_path, MINIMAL + "TYPO_KEY=1\n"))
    assert len(cfg.warnings) == 1
    assert ":5:" in cfg.warnings[0]
    assert "TYPO_KEY" in cfg.warnings[0]


def test_missing_required_key_fails(tmp_path):
    with pytest.raises(ConfigError, match="obrigatórias"):
        load_config(write(tmp_path, "RIVER_NAME=x\nNUT_HOST=h\nNUT_PORT=3493\n"))


def test_empty_required_value_fails(tmp_path):
    content = MINIMAL.replace("NUT_UPS=river-office", "NUT_UPS=")
    with pytest.raises(ConfigError, match="NUT_UPS"):
        load_config(write(tmp_path, content))


def test_out_of_range_int_fails_with_line(tmp_path):
    with pytest.raises(ConfigError, match="faixa"):
        load_config(write(tmp_path, MINIMAL + "POLL_INTERVAL_SECONDS=999\n"))


def test_bad_bool_fails(tmp_path):
    with pytest.raises(ConfigError, match="booleano"):
        load_config(write(tmp_path, MINIMAL + "UI_API_ENABLED=talvez\n"))


def test_inline_comment_is_rejected_not_silently_parsed(tmp_path):
    # House rule: comments only on their own line. An inline comment corrupts
    # the value and must fail loudly for ints, never parse as something else.
    with pytest.raises(ConfigError):
        load_config(write(tmp_path, MINIMAL + "POLL_INTERVAL_SECONDS=2  # rapido\n"))


def test_missing_file_fails(tmp_path):
    with pytest.raises(ConfigError, match="não encontrado"):
        load_config(str(tmp_path / "nope.env"))


def test_example_file_in_repo_parses(tmp_path):
    import pathlib

    example = pathlib.Path(__file__).parents[2] / "config" / "river-unifi-bridge.env.example"
    cfg = load_config(str(example))
    assert cfg.warnings == []
    assert cfg.ui_api_port == 35493


def test_allowlist_matches_spec_keys():
    expected = {
        "RIVER_NAME", "NUT_HOST", "NUT_PORT", "NUT_UPS",
        "POLL_INTERVAL_SECONDS",
        "POWER_LOSS_DELAY_SECONDS", "RESTORE_DELAY_SECONDS",
        "COMM_LOSS_DELAY_SECONDS", "LOW_BATTERY_PERCENT",
        "UI_API_ENABLED", "UI_API_PORT", "HISTORY_RETENTION_DAYS",
        # Fase 3'-EXP (spec §22 bloco 6)
        "PROTECT_UDR7", "PROTECT_DRY_RUN", "UDR7_ARM_ALLOWED",
        "UDR7_SSH_HOST", "UDR7_SSH_PORT", "UDR7_SSH_USER", "UDR7_SSH_KEY",
        "UDR7_EXPECTED_SERIAL", "UDR7_CUTOFF_PERCENT", "UDR7_SHUTDOWN_PERCENT",
        "UDR7_DISCHARGE_SECONDS_PER_PCT", "UDR7_RUNTIME_MINUTES",
        "UDR7_MIN_OUTAGE_SECONDS", "UDR7_CONFIRM_SECONDS", "UDR7_RETRY_MAX",
        "UDR7_WOL_MAC", "UDR7_NAME",
        # Leitura de potência pela porta serial do River (0.4.0)
        "RIVER_SERIAL_ENABLED", "RIVER_SERIAL_PORT",
        # Ações sobre o próprio River (0.5.0)
        "RIVER_POWEROFF_ALLOWED", "RIVER_NUT_MANAGED",
        # A ponte publicando no NUT o que o app mostra, e a trava das ordens à
        # mão num dispositivo protegido (0.7.0)
        "RIVER_NUT_PUBLICA", "RIVER_NUT_APARELHO", "DEVICE_CMD_ALLOWED",
        # O cabo passando sozinho para o aplicativo do fabricante (0.7.0)
        "RIVER_CABO_AUTOMATICO",
    }
    assert set(_ALLOWLIST) == expected
    assert len(expected) == 37


@pytest.mark.parametrize(
    "key,value",
    [
        ("UDR7_SSH_USER", "-oProxyCommand=/bin/echo"),
        ("UDR7_SSH_USER", "--"),
        ("UDR7_SSH_USER", "-E"),
        ("UDR7_SSH_USER", "-J"),
        ("UDR7_SSH_USER", "root evil"),
        ("UDR7_SSH_USER", "1234"),               # numeric-only (first char must be a letter)
        ("UDR7_SSH_USER", "r" * 33),
        ("UDR7_SSH_HOST", "-oProxyCommand=x"),
        ("UDR7_SSH_HOST", "host name"),
        ("UDR7_SSH_HOST", "a_b"),
        ("UDR7_SSH_HOST", "::1"),
        ("UDR7_SSH_KEY", "~/.ssh/id_ed25519"),
        ("UDR7_SSH_KEY", "relative/key"),
        ("UDR7_SSH_KEY", "-i"),
        ("UDR7_EXPECTED_SERIAL", "SIM0001"),      # simulator serial can never be registered
        ("UDR7_EXPECTED_SERIAL", "has space"),
        ("UDR7_WOL_MAC", "AA:BB:CC:DD:EE"),
        ("UDR7_WOL_MAC", "AA:BB-CC:DD-EE:FF"),    # mixed separators
        ("UDR7_WOL_MAC", "GG:BB:CC:DD:EE:FF"),
    ],
)
def test_protection_string_shapes_are_rejected_in_file_and_put(tmp_path, key, value):
    from river_unifi_bridge.config import validate_update

    with pytest.raises(ConfigError, match=key):
        load_config(write(tmp_path, MINIMAL + f"{key}={value}\n"))
    with pytest.raises(ConfigError, match=key):
        validate_update(key, value)


def test_protection_string_with_embedded_newline_is_rejected_by_put():
    from river_unifi_bridge.config import validate_update

    with pytest.raises(ConfigError, match="UDR7_SSH_USER"):
        validate_update("UDR7_SSH_USER", "root\nUDR7_SSH_HOST=evil")


@pytest.mark.parametrize(
    "key,value",
    [
        ("UDR7_SSH_USER", "root"),
        ("UDR7_SSH_USER", "svc.bridge-01"),
        ("UDR7_SSH_HOST", "192.168.1.1"),
        ("UDR7_SSH_HOST", "udr7.home.arpa"),
        ("UDR7_SSH_KEY", "/Users/svc/.ssh/river-bridge-udr7"),
        ("UDR7_EXPECTED_SERIAL", "R3P-1234567890"),
        ("UDR7_WOL_MAC", "aa:bb:cc:dd:ee:ff"),
        ("UDR7_WOL_MAC", "AA-BB-CC-DD-EE-FF"),
        # O nome do dispositivo: texto que o usuário escolhe.
        ("UDR7_NAME", "Meu UDR"),
        ("UDR7_NAME", "Café do Zé"),
        ("UDR7_NAME", "X"),
        ("UDR7_NAME", "x" * 32),
        ("UDR7_NAME", "Roteador da Sala 2"),
    ],
)
def test_protection_string_shapes_accepted(tmp_path, key, value):
    from river_unifi_bridge.config import validate_update

    cfg = load_config(write(tmp_path, MINIMAL + f"{key}={value}\n"))
    assert getattr(cfg, key.lower()) == value
    assert validate_update(key, value) == value


@pytest.mark.parametrize(
    "value",
    [
        "x" * 33,                 # 33 caracteres: passa do teto
        "a" + " b" * 30,          # 61 caracteres, todos válidos um a um
        "a  b",                   # espaço duplo
        "~",                      # load_config expandiria para o diretório do usuário
        "a~b",
        "a\tb",
        "a\x1bb",
        "a\xa0b",                 # espaço inquebrável
        "a\u200bb",               # zero-width space
        "\ufeffUDR7",             # BOM
        "\u061cUDR7",             # ALM (bidi)
        "a\u00adb",               # hífen suave
        "UDR7\ufe0f",             # variation selector (BMP)
        "UDR7\U000e0100",         # variation selector suplementar: renderiza "UDR7"
        "UDR7\U000e0001",         # tag
        "a\u180bb",               # variation selector mongol
        "\u2800",                 # braille em branco
        "a\nb",
    ],
)
def test_device_name_shapes_rejected(value):
    """A forma do nome barra o que faria um nome "parecer UDR7" sem ser."""
    from river_unifi_bridge.config import validate_update

    with pytest.raises(ConfigError):
        validate_update("UDR7_NAME", value)


def test_device_name_keeps_the_inner_shape(tmp_path):
    cfg = load_config(write(tmp_path, MINIMAL + "UDR7_NAME=Meu UDR\n"))
    assert cfg.udr7_name == "Meu UDR"


def test_device_name_is_trimmed_not_refused():
    """Espaço nas pontas é APARADO, não recusado — é o que load_config e
    validate_update já fazem com toda chave de texto (`.strip()`), e não uma regra
    do nome. A forma só decide o miolo; por isso " Meu UDR " vira "Meu UDR"."""
    from river_unifi_bridge.config import validate_update

    assert validate_update("UDR7_NAME", "  Meu UDR  ") == "Meu UDR"
    assert validate_update("UDR7_NAME", "   ") == ""


def test_device_name_defaults_when_absent(tmp_path):
    cfg = load_config(write(tmp_path, MINIMAL))
    assert cfg.udr7_name == "UDR7"


def test_empty_protection_string_is_absent_not_invalid(tmp_path):
    from river_unifi_bridge.config import validate_update

    cfg = load_config(write(tmp_path, MINIMAL + "UDR7_SSH_HOST=\nUDR7_SSH_KEY=\n"))
    assert cfg.udr7_ssh_host == "" and cfg.udr7_ssh_key == ""
    assert validate_update("UDR7_SSH_HOST", "") == ""


def test_put_empty_value_is_refused_on_non_string_keys():
    """Vazio em número ou booleano derrubava o serviço no tick seguinte.

    `validate_update` devolvia a string vazia, o PUT gravava isso a quente na
    configuração viva e a política comparava texto com número. Em texto o vazio
    continua válido (limpar um nome, limpar um host).
    """
    from river_unifi_bridge.config import validate_update

    for chave in ("UDR7_CUTOFF_PERCENT", "POLL_INTERVAL_SECONDS", "UI_API_ENABLED"):
        with pytest.raises(ConfigError, match="valor vazio"):
            validate_update(chave, "")
    assert validate_update("UDR7_SSH_HOST", "") == ""
    assert validate_update("UDR7_NAME", "") == ""


def test_retired_keys_only_warn_in_an_installed_env(tmp_path):
    """Um .env instalado com as chaves aposentadas sobe, com aviso — nunca erro."""
    cfg = load_config(write(tmp_path, MINIMAL + "READ_ONLY=1\nUNIFI_HOST=192.168.1.1\n"))
    assert len(cfg.warnings) == 2
    assert all("chave desconhecida ignorada" in w for w in cfg.warnings)


def test_protection_key_sets_are_consistent():
    from river_unifi_bridge.config import (
        _ALLOWLIST, HOT_RELOAD_KEYS, PROTECTION_KEYS,
    )
    # O que NÃO aplica a quente exige reiniciar o serviço; o endereço do NUT está
    # desse lado, e é o que o app informa ao usuário depois de salvar.
    exige_reinicio = set(_ALLOWLIST) - HOT_RELOAD_KEYS
    # As três travas são interruptores na tela desde a 0.8.0 e aplicam a quente.
    # Uma arma a proteção; outra autoriza desligar o próprio River, que corta a
    # energia de tudo o que estiver nele; a terceira autoriza mandar um
    # dispositivo protegido desligar ou reiniciar AGORA, à mão.
    assert {"UDR7_ARM_ALLOWED", "RIVER_POWEROFF_ALLOWED",
            "DEVICE_CMD_ALLOWED"} <= HOT_RELOAD_KEYS
    assert "UDR7_ARM_ALLOWED" not in exige_reinicio
    assert "NUT_HOST" in exige_reinicio
    assert {"NUT_HOST", "NUT_PORT", "NUT_UPS", "PROTECT_UDR7", "PROTECT_DRY_RUN"} <= PROTECTION_KEYS
    assert len(PROTECTION_KEYS) == 19
    assert (PROTECTION_KEYS - {"NUT_HOST", "NUT_PORT", "NUT_UPS"}) <= HOT_RELOAD_KEYS
    # O nome do dispositivo tem prefixo UDR7_ mas NÃO é configuração de proteção:
    # aplica a quente e pode ser trocado com o daemon armado. É o nó da cena S4m —
    # sem o `- DEVICE_NAME_KEYS` em config.py, o prefixo o engoliria e renomear
    # passaria a devolver 409.
    from river_unifi_bridge.config import DEVICE_NAME_KEYS

    assert DEVICE_NAME_KEYS == {"UDR7_NAME"}
    assert "UDR7_NAME" in HOT_RELOAD_KEYS and "UDR7_NAME" not in PROTECTION_KEYS
