"""A leitura de potência do River pela porta serial.

O quadro de `tests/fixtures/river_serial_frame.hex` foi capturado do aparelho do
dono em 2026-09-04 (River 3 Plus, série R631ZBBAWH270046, ligado ao Mac mini com
cerca de 110 W na tomada). É um quadro REAL: se o formato mudar, estes testes
reprovam antes de a tela mentir.
"""

from __future__ import annotations

import pathlib
import struct

import pytest

from river_unifi_bridge import river_serial as rs

QUADRO = bytes.fromhex(
    (pathlib.Path(__file__).parents[1] / "fixtures" / "river_serial_frame.hex").read_text().strip()
)


def test_frame_from_the_real_device_decodes():
    leitura = rs.interpreta(QUADRO)
    assert leitura.carga_total_w == 110.6
    assert leitura.entrada_ac_w == 110.6
    assert leitura.carga_ac_w == 110.6          # o sinal negativo do aparelho é invertido
    assert leitura.carga_dc_w == 0.0            # e o zero nunca sai negativo
    assert leitura.carga_usb_a_w == 0.0
    assert leitura.carga_usb_c_w == 0.0
    assert leitura.entrada_solar_dc_w == 0.0
    assert leitura.frequencia_hz == 60.0
    assert leitura.temperatura_c == 34.0
    assert leitura.serie == "R631ZBBAWH270046"


def test_the_dict_that_goes_to_the_app():
    d = rs.interpreta(QUADRO).to_dict()
    assert d["total_w"] == 110.6 and d["ac_w"] == 110.6 and d["usb_c_w"] == 0.0
    assert d["line_frequency_hz"] == 60.0
    assert set(d) == {"total_w", "input_w", "input_ac_w", "input_solar_dc_w",
                      "ac_w", "dc_w", "usb_a_w", "usb_c_w", "line_frequency_hz"}


def test_a_corrupted_frame_is_refused_not_guessed():
    """Um byte trocado tem de reprovar na verificação, não virar número na tela."""
    estragado = bytearray(QUADRO)
    estragado[40] ^= 0x01
    with pytest.raises(rs.RiverSerialError, match="integridade"):
        rs.interpreta(bytes(estragado))


def test_noise_on_the_port_is_refused():
    with pytest.raises(rs.RiverSerialError):
        rs.interpreta(b"\x00\x01\x02\x03\x04\x05\x06\x07")
    with pytest.raises(rs.RiverSerialError):
        rs.interpreta(b"")


def test_request_is_well_formed_and_is_a_read():
    pedido = rs.monta_pedido()
    assert struct.unpack_from("<H", pedido, 0)[0] == rs.PREAMBULO
    assert rs.crc16(pedido) == 0                 # o quadro fecha na própria verificação
    assert pedido.hex().startswith("aa03")


def test_auto_discovery_takes_the_port_that_answers():
    portas = ["/dev/cu.mudo", "/dev/cu.river"]
    vistas = []

    def conversa(porta):
        vistas.append(porta)
        return QUADRO if porta == "/dev/cu.river" else b""

    leitura, porta = rs.ler("auto", conversa=conversa, portas=portas)
    assert porta == "/dev/cu.river"
    assert leitura.carga_total_w == 110.6
    assert vistas == portas          # tentou a muda antes, e não parou nela


def test_wrong_device_on_the_port_is_skipped():
    """Com dois aparelhos, ler o vizinho é pior que não ler: a série decide."""
    resultado = rs.ler("/dev/cu.river", serie_esperada="OUTRO-SERIAL",
                       conversa=lambda _p: QUADRO)
    assert resultado is None
    leitura, _ = rs.ler("/dev/cu.river", serie_esperada="R631ZBBAWH270046",
                        conversa=lambda _p: QUADRO)
    assert leitura.serie == "R631ZBBAWH270046"


def test_a_port_that_explodes_never_breaks_the_caller():
    def explode(_porta):
        raise OSError(6, "Device not configured")

    assert rs.ler("/dev/cu.sumiu", conversa=explode) is None
