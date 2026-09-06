"""Potência do River 3 Plus pela porta serial do próprio cabo.

Por que este módulo existe: o perfil de no-break (USB HID) que o NUT lê **não**
publica consumo — medido no aparelho em 2026-09-04 e confirmado no driver oficial
(`networkupstools/nut`, `drivers/ecoflow-hid.c`, que não mapeia `ups.load` nem
`ups.realpower`). O mesmo cabo expõe uma segunda porta, serial, e é por ela que
vêm potência total, entrada e consumo por tomada. As duas convivem: o NUT
continua na interface de no-break enquanto lemos aqui.

Protocolo: enquadramento, verificação e desofuscação conforme o projeto público
**greyltc/r3pcomms** (licença MIT, <https://github.com/greyltc/r3pcomms>), lido e
reimplementado aqui — o crédito é dele, os defeitos são nossos.

Os segmentos do quadro (r3pcomms `_r3pcomms.py`, `serial_segmenter`, lido em
2026-09-06; o valor é o do quadro real de `tests/fixtures/river_serial_frame.hex`):

    tipo  conteúdo                                  fonte / certeza
    3     capacidade de projeto, `<I`, mAh          r3pcomms; 12800 no quadro real
    4     quatro temperaturas `<BBBB`, °C           r3pcomms diz "a 2.ª é a bateria"; o
                                                    arquivo de Home Assistant do autor
                                                    (`doc/configuration.yaml`) usa [1] =
                                                    bateria e [0] = sistema; [2] e [3]
                                                    não têm nome em fonte nenhuma
    7/8/9/12  carga total, entrada total, entrada   float, W (r3pcomms)
              da rede, entrada solar/DC
    14/16/17/18  cargas AC, 12 V, USB-A, USB-C      float, W, negativas no aparelho
    15    frequência (`<HH`, 1.º)                   r3pcomms marca com "?"; 60 no real
    22    série                                     ASCII
    23    tempo para carga completa, `<HH` (1.º),   r3pcomms: bytes `33 17` = "não está
          minutos                                   carregando" — com interrogação lá,
                                                    CONFIRMADO pelo nosso quadro real
                                                    (aparelho a 100 % na tomada → `33 17`).
                                                    Um valor em minutos com o aparelho
                                                    carregando ainda não foi medido por
                                                    nós (é linha da bancada da primeira
                                                    queda real); a 2.ª metade é 0 no real
    13, 25  "Line Frequency?", "Model/Batch?"       incertos no próprio r3pcomms: não lidos

Firmware não existe em fonte nenhuma (nem serial nem HID): o r3pcomms não o lê, e a
"Version" da saída dele é a do programa. Registrado em 2026-09-06 porque uma proposta
anterior o prometia.

Só biblioteca padrão: um daemon de no-break não ganha dependência por causa de
uma leitura de 200 bytes.
"""

from __future__ import annotations

import glob
import os
import struct
import termios
import time
from dataclasses import dataclass

# Preâmbulo do quadro e tamanho fixo do cabeçalho, do protocolo do aparelho.
PREAMBULO = 0x03AA
SOBRECARGA = 14
# Pedido de métricas. É LEITURA: não muda nada no aparelho.
PEDIDO_METRICAS = "de2d00000000ffff220201016602"
# A carga útil vem ofuscada por XOR a partir deste deslocamento, com o byte baixo
# do número de sequência (que o próprio quadro devolve, no deslocamento 6).
OFUSCACAO_INICIO = 18
SEQUENCIA_INICIO = 6
SEGMENTOS_INICIO = 22
BAUD = termios.B115200
# Quanto esperar por porta. O aparelho responde em milissegundos (medido: 197
# bytes de volta na primeira leitura); o valor alto só castigava o ciclo quando a
# porta está muda. O laço que decide desligar aparelhos não pode ficar parado.
ESPERA_SEGUNDOS = 0.6

# Tipo de segmento → (campo, sinal). O aparelho manda as CARGAS negativas.
_CAMPOS_W = {
    7: ("carga_total_w", 1),
    8: ("entrada_total_w", 1),
    9: ("entrada_ac_w", 1),
    12: ("entrada_solar_dc_w", 1),
    14: ("carga_ac_w", -1),
    16: ("carga_dc_w", -1),
    17: ("carga_usb_a_w", -1),
    18: ("carga_usb_c_w", -1),
}
_TIPO_CAPACIDADE = 3
_TIPO_TEMPERATURAS = 4
_TIPO_FREQUENCIA = 15
_TIPO_SERIE = 22
_TIPO_TEMPO_PARA_CARGA = 23
# Os dois primeiros bytes do tipo 23 quando o aparelho NÃO está carregando (ver
# a tabela do cabeçalho). Não é um número de minutos: é ausência.
_NAO_CARREGANDO = b"\x33\x17"
# Qual dos quatro sensores é qual (tabela do cabeçalho).
_SENSOR_SISTEMA = 0
_SENSOR_BATERIA = 1


@dataclass
class LeituraRiver:
    """O que a porta serial entrega. `None` em campo que não veio — nunca zero."""

    carga_total_w: float | None = None
    entrada_total_w: float | None = None
    entrada_ac_w: float | None = None
    entrada_solar_dc_w: float | None = None
    carga_ac_w: float | None = None
    carga_dc_w: float | None = None
    carga_usb_a_w: float | None = None
    carga_usb_c_w: float | None = None
    frequencia_hz: float | None = None
    # A da bateria (sensor [1]); é o que já ia para `battery.temperature`.
    temperatura_c: float | None = None
    # A do sistema (sensor [0]) e as quatro cruas, na ordem do aparelho.
    temperatura_sistema_c: float | None = None
    temperaturas_c: tuple[float, ...] | None = None
    capacidade_projeto_mah: int | None = None
    # Minutos até a carga completa; `None` quando o aparelho não está carregando.
    tempo_para_carga_min: int | None = None
    serie: str | None = None

    def to_dict(self) -> dict:
        return {
            "total_w": self.carga_total_w,
            "input_w": self.entrada_total_w,
            "input_ac_w": self.entrada_ac_w,
            "input_solar_dc_w": self.entrada_solar_dc_w,
            "ac_w": self.carga_ac_w,
            "dc_w": self.carga_dc_w,
            "usb_a_w": self.carga_usb_a_w,
            "usb_c_w": self.carga_usb_c_w,
            "line_frequency_hz": self.frequencia_hz,
            "design_capacity_mah": self.capacidade_projeto_mah,
            "time_to_full_minutes": self.tempo_para_carga_min,
            "battery_temperature_c": self.temperatura_c,
            "system_temperature_c": self.temperatura_sistema_c,
            "temperatures_c": list(self.temperaturas_c) if self.temperaturas_c is not None else None,
        }


class RiverSerialError(Exception):
    """A porta respondeu algo que não é um quadro deste aparelho."""


def crc16(dados: bytes) -> int:
    """CRC-16/ARC, o mesmo do aparelho (polinômio refletido 0xA001)."""
    crc = 0
    for byte in dados:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc & 0xFFFF


def monta_pedido(msg_hex: str = PEDIDO_METRICAS, sequencia: int = 1) -> bytes:
    corpo_bruto = bytes.fromhex(msg_hex)
    corpo = corpo_bruto[:2] + struct.pack("<I", sequencia) + corpo_bruto[6:]
    cabeca = struct.pack("<HH", PREAMBULO, len(corpo_bruto) - SOBRECARGA) + corpo
    return cabeca + struct.pack("<H", crc16(cabeca))


def desofusca(quadro: bytes) -> bytes:
    """Desfaz o XOR da carga útil. O quadro carrega a própria chave."""
    if len(quadro) <= OFUSCACAO_INICIO:
        raise RiverSerialError("quadro curto demais para ser deste aparelho")
    sequencia = struct.unpack_from("<I", quadro, SEQUENCIA_INICIO)[0] & 0xFF
    claro = bytes((b ^ sequencia) & 0xFF for b in quadro[OFUSCACAO_INICIO:])
    return quadro[:OFUSCACAO_INICIO] + claro


def interpreta(quadro: bytes) -> LeituraRiver:
    """Do quadro cru (como veio da porta) para a leitura, com verificação."""
    if len(quadro) < SEGMENTOS_INICIO + 3:
        raise RiverSerialError("resposta curta demais")
    if struct.unpack_from("<H", quadro, 0)[0] != PREAMBULO:
        raise RiverSerialError("preâmbulo não é deste aparelho")
    if crc16(quadro) != 0:
        raise RiverSerialError("verificação de integridade falhou")

    claro = desofusca(quadro)
    leitura = LeituraRiver()
    posicao = SEGMENTOS_INICIO
    while posicao + 3 <= len(claro) - 2:          # os 2 últimos bytes são o CRC
        tipo, tamanho = struct.unpack_from("<HB", claro, posicao)
        dados = claro[posicao + 3: posicao + 3 + tamanho]
        posicao += 3 + tamanho
        if len(dados) != tamanho:
            break
        if tipo in _CAMPOS_W and tamanho == 4:
            campo, sinal = _CAMPOS_W[tipo]
            # `+ 0.0` normaliza o zero negativo: "-0,0 W" na tela é ruído.
            setattr(leitura, campo, round(struct.unpack("<f", dados)[0] * sinal, 1) + 0.0)
        elif tipo == _TIPO_FREQUENCIA and tamanho == 4:
            leitura.frequencia_hz = float(struct.unpack_from("<H", dados, 0)[0])
        elif tipo == _TIPO_TEMPERATURAS and tamanho == 4:
            sensores = struct.unpack("<BBBB", dados)
            leitura.temperaturas_c = tuple(float(t) for t in sensores)
            leitura.temperatura_c = float(sensores[_SENSOR_BATERIA])
            leitura.temperatura_sistema_c = float(sensores[_SENSOR_SISTEMA])
        elif tipo == _TIPO_CAPACIDADE and tamanho == 4:
            leitura.capacidade_projeto_mah = struct.unpack("<I", dados)[0]
        elif tipo == _TIPO_TEMPO_PARA_CARGA and tamanho == 4:
            # Não carregando: ausência, não um número de minutos.
            if dados[:2] != _NAO_CARREGANDO:
                leitura.tempo_para_carga_min = struct.unpack_from("<H", dados, 0)[0]
        elif tipo == _TIPO_SERIE:
            leitura.serie = dados.decode("ascii", "replace").strip("\x00").strip() or None
    return leitura


def _abre(porta: str) -> int:
    """Abre a porta em modo cru. Sem pyserial: são três chamadas de termios."""
    fd = os.open(porta, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        atributos = termios.tcgetattr(fd)
        controle = list(atributos[6])
        controle[termios.VMIN] = 0
        controle[termios.VTIME] = 3           # 0,3 s por leitura
        termios.tcsetattr(
            fd, termios.TCSANOW,
            [0, 0, termios.CS8 | termios.CREAD | termios.CLOCAL, 0, BAUD, BAUD, controle],
        )
        os.set_blocking(fd, True)
        termios.tcflush(fd, termios.TCIOFLUSH)
    except Exception:
        os.close(fd)
        raise
    return fd


def _conversa(porta: str, espera: float = ESPERA_SEGUNDOS) -> bytes:
    fd = _abre(porta)
    try:
        os.write(fd, monta_pedido())
        limite = time.monotonic() + espera
        resposta = b""
        while time.monotonic() < limite:
            try:
                pedaco = os.read(fd, 4096)
            except BlockingIOError:
                pedaco = b""
            if pedaco:
                resposta += pedaco
                # O quadro declara o próprio tamanho no cabeçalho.
                if len(resposta) >= 4:
                    _, extra = struct.unpack_from("<HH", resposta, 0)
                    if len(resposta) >= 20 + extra:
                        break
            else:
                time.sleep(0.02)
        return resposta
    finally:
        os.close(fd)


def portas_candidatas(padrao: str = "/dev/cu.usbmodem*") -> list[str]:
    return sorted(glob.glob(padrao))


def ler(porta: str = "auto", *, serie_esperada: str | None = None,
        conversa=_conversa, portas: list[str] | None = None
        ) -> tuple[LeituraRiver, str] | None:
    """A leitura e a porta que respondeu, ou `None` quando ninguém respondeu.

    A **série é cerca, não preferência**: só é aceito o quadro que traga a MESMA
    série do aparelho que o no-break identificou. Sem série esperada, ou com
    quadro que não a traga, a leitura é recusada — atribuir a outro aparelho os
    watts que aparecem na tela do dono seria pior que não mostrar watt nenhum.
    A única exceção é a porta escolhida À MÃO na configuração: aí a escolha é do
    dono, e ela vale mesmo sem série (aparelho que não a publica).
    """
    escolhida_a_mao = bool(porta) and porta != "auto"
    alvos = [porta] if escolhida_a_mao else (
        portas_candidatas() if portas is None else portas)
    for candidata in alvos:
        try:
            quadro = conversa(candidata)
            if not quadro:
                continue
            leitura = interpreta(quadro)
        except (OSError, RiverSerialError, struct.error):
            continue
        if not escolhida_a_mao:
            if not serie_esperada or leitura.serie != serie_esperada:
                continue          # aparelho errado, ou sem como saber: recusa
        return leitura, candidata
    return None
