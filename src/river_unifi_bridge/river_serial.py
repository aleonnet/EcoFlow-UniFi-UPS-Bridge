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
ESPERA_SEGUNDOS = 2.0

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
_TIPO_TEMPERATURAS = 4
_TIPO_FREQUENCIA = 15
_TIPO_SERIE = 22


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
    temperatura_c: float | None = None
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
            # Quatro sensores; o segundo é o da bateria (r3pcomms).
            leitura.temperatura_c = float(struct.unpack("<BBBB", dados)[1])
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
        controle[termios.VTIME] = 10          # 1 s de espera por leitura
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

    `porta="auto"` percorre as portas seriais do Mac e aceita a primeira que
    devolver um quadro válido — e, se `serie_esperada` for dada, só a que trouxer
    ESSA série. Com dois aparelhos na mesma máquina, ler o vizinho seria pior que
    não ler nada.
    """
    alvos = [porta] if porta and porta != "auto" else (
        portas_candidatas() if portas is None else portas)
    for candidata in alvos:
        try:
            quadro = conversa(candidata)
            if not quadro:
                continue
            leitura = interpreta(quadro)
        except (OSError, RiverSerialError, struct.error):
            continue
        if serie_esperada and leitura.serie and leitura.serie != serie_esperada:
            continue
        return leitura, candidata
    return None
