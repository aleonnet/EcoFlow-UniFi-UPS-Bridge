"""O que a ponte conta ao NUT, nos nomes que o NUT (e o Home Assistant) entendem.

Este módulo não fala com ninguém: recebe a leitura que o serviço já tem e devolve
o dicionário de variáveis. Isso o mantém testável sem soquete e sem aparelho.

**Os nomes não são escolha nossa.** Cada um saiu de `docs/nut-names.txt` do
projeto NUT, e a razão de segui-los à risca é o outro lado: o Home Assistant só
cria sensor para variável que ele conhece pelo nome. As que usamos aqui:

- `ups.realpower` — "Current value of real power (Watts)"
- `input.realpower`, `input.frequency` — entrada e frequência da linha
- `outlet.count`, `outlet.n.desc`, `outlet.n.id`, `outlet.n.realpower`,
  `outlet.n.switchable` — a coleção de tomadas
- `battery.charge`, `battery.runtime`, `battery.voltage`, `battery.charge.low`
- `device.type`, `device.mfr`, `device.model`, `device.serial`, `ups.status`

Medido no código do Home Assistant em 2026-09-05 (`components/nut/__init__.py`,
`outlet_numbers_from_status`): as tomadas só aparecem se houver `outlet.count`
**ou** chaves `outlet.<n>.*`. Sem essa contagem, os watts por tomada que temos
não virariam sensor nenhum.

Regra da casa que vale aqui inteira: **dado ausente não vira zero.** Uma variável
que não temos simplesmente não é publicada — o Home Assistant mostra a falta, em
vez de mostrar um número inventado.
"""

from __future__ import annotations

from . import __version__

# As quatro saídas do River, na ordem em que a tela do aplicativo as mostra. O
# número é o índice da tomada no NUT; o texto é o que aparece no Home Assistant.
TOMADAS: tuple[tuple[int, str, str, str], ...] = (
    (1, "ac", "120 V (tomadas AC)", "ac"),
    (2, "dc", "12 V (saída DC)", "dc"),
    (3, "usb_a", "USB-A", "usb-a"),
    (4, "usb_c", "USB-C", "usb-c"),
)
# O campo de `LeituraRiver.to_dict()` que traz os watts de cada uma.
_CAMPO_DA_TOMADA = {"ac": "ac_w", "dc": "dc_w", "usb_a": "usb_a_w", "usb_c": "usb_c_w"}

# O que devolvemos ao NUT quando o estado bruto do no-break não chegou. Não é
# palpite: é a ausência declarada, e o NUT a entende assim.
_SEM_ESTADO = ""


def _texto(valor, casas: int = 1) -> str | None:
    """Número em texto, do jeito que o NUT publica. `None` continua `None`."""
    if valor is None:
        return None
    try:
        numero = float(valor)
    except (TypeError, ValueError):
        return None
    if casas == 0:
        return f"{numero:.0f}"
    formatado = f"{numero:.{casas}f}"
    return formatado


def _poe(destino: dict[str, str], nome: str, valor) -> None:
    """Grava só o que existe — ausência não vira zero (regra §5.5 da casa)."""
    if valor is None:
        return
    texto = valor if isinstance(valor, str) else _texto(valor)
    if texto is None or texto == "":
        return
    destino[nome] = texto


def variaveis_do_river(snap) -> dict[str, str]:
    """O River inteiro, como o NUT o descreve: o que o no-break diz MAIS a serial.

    A única entrada é a leitura do ciclo. As tomadas saem de `snap.outlets`, que
    é onde o serviço guarda o `LeituraRiver.to_dict()` quando a porta serial
    responde — uma fonte só, para a publicação não poder discordar da tela.
    Porta muda, nenhuma variável de tomada: a verdade daquele instante, e não uma
    tabela de zeros.
    """
    tomadas = snap.outlets
    variaveis: dict[str, str] = {"device.type": "ups"}
    _poe(variaveis, "device.mfr", snap.manufacturer)
    _poe(variaveis, "ups.mfr", snap.manufacturer)
    _poe(variaveis, "device.model", snap.model)
    _poe(variaveis, "ups.model", snap.model)
    _poe(variaveis, "device.serial", snap.serial)
    _poe(variaveis, "ups.serial", snap.serial)
    # O estado vai no formato BRUTO do NUT ("OL CHRG"), não no nosso normalizado:
    # é o que todo cliente do protocolo espera ler, o Home Assistant inclusive.
    _poe(variaveis, "ups.status", getattr(snap, "status_raw", "") or _SEM_ESTADO)

    _poe(variaveis, "battery.charge", _texto(snap.charge_percent, 0))
    _poe(variaveis, "battery.charge.low", _texto(snap.battery_charge_low_percent, 0))
    _poe(variaveis, "battery.runtime", _texto(snap.runtime_seconds, 0))
    _poe(variaveis, "battery.voltage", _texto(snap.voltage_v, 2))
    _poe(variaveis, "battery.temperature", _texto(snap.temperature_c, 1))
    _poe(variaveis, "ups.temperature", _texto(snap.temperature_c, 1))

    _poe(variaveis, "ups.load", _texto(snap.load_percent, 0))
    _poe(variaveis, "ups.realpower", _texto(snap.output_power_w, 1))
    _poe(variaveis, "input.voltage", _texto(snap.input_voltage_v, 1))
    _poe(variaveis, "output.voltage", _texto(snap.output_voltage_v, 1))
    _poe(variaveis, "input.realpower", _texto(snap.input_power_w, 1))
    _poe(variaveis, "input.frequency", _texto(snap.line_frequency_hz, 1))

    if tomadas:
        # `outlet.count` é o que faz o Home Assistant procurar as tomadas. Sem
        # ele, os watts por tomada chegariam e não virariam sensor.
        variaveis["outlet.count"] = str(len(TOMADAS))
        for indice, chave, rotulo, identificador in TOMADAS:
            variaveis[f"outlet.{indice}.id"] = identificador
            variaveis[f"outlet.{indice}.desc"] = rotulo
            # NÃO declaramos a tomada como comandável: não há caminho medido para
            # ligar ou desligar uma saída do River, e dizer que há faria o Home
            # Assistant desenhar um interruptor que não funciona.
            variaveis[f"outlet.{indice}.switchable"] = "no"
            _poe(variaveis, f"outlet.{indice}.realpower",
                 _texto(tomadas.get(_CAMPO_DA_TOMADA[chave]), 1))

    variaveis["driver.name"] = "river-bridge"
    variaveis["driver.version"] = __version__
    variaveis["driver.version.internal"] = __version__
    return variaveis


def variaveis_do_dispositivo(snap, *, nome: str, modelo: str | None = None,
                             firmware: str | None = None,
                             fabricante: str | None = None) -> dict[str, str]:
    """Um dispositivo protegido, publicado como aparelho próprio no NUT.

    Por que ele existe: o Home Assistant só transforma em ação o comando cujo
    NOME está na lista fechada dele (`INTEGRATION_SUPPORTED_COMMANDS`, medido no
    código em 2026-09-05). Um comando chamado `device.udr7.shutdown` seria aceito
    pelo NUT e **invisível** no Home Assistant. Publicando o roteador como um
    aparelho, o comando volta a ser o padrão `load.off` — "Turn off the load
    immediately" —, e ali a carga É o roteador. O nome passa a dizer a verdade em
    vez de contorná-la.

    Nada de série inventada: sem número de série de verdade, não publicamos
    nenhum. O Home Assistant se vira com o identificador dele.
    """
    variaveis: dict[str, str] = {"device.type": "ups"}
    _poe(variaveis, "device.mfr", fabricante)
    _poe(variaveis, "ups.mfr", fabricante)
    _poe(variaveis, "device.model", modelo)
    _poe(variaveis, "ups.model", modelo)
    _poe(variaveis, "ups.firmware", firmware)
    _poe(variaveis, "device.description", nome)
    # A situação de energia do dispositivo É a do River que o alimenta: se o
    # River caiu para a bateria, ele está na bateria.
    _poe(variaveis, "ups.status", getattr(snap, "status_raw", "") or _SEM_ESTADO)
    _poe(variaveis, "battery.charge", _texto(snap.charge_percent, 0))
    _poe(variaveis, "battery.runtime", _texto(snap.runtime_seconds, 0))
    variaveis["driver.name"] = "river-bridge"
    variaveis["driver.version"] = __version__
    return variaveis
