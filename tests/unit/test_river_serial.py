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
    assert leitura.temperatura_c == 34.0            # sensor [1], a bateria
    assert leitura.temperatura_sistema_c == 34.0    # sensor [0], o sistema
    assert leitura.temperaturas_c == (34.0, 34.0, 25.0, 25.0)
    assert leitura.capacidade_projeto_mah == 12800
    # Aparelho a 100 % na tomada: os bytes `33 17` são "não está carregando".
    assert leitura.tempo_para_carga_min is None
    assert leitura.serie == "R631ZBBAWH270046"


def test_the_dict_that_goes_to_the_app():
    d = rs.interpreta(QUADRO).to_dict()
    assert d["total_w"] == 110.6 and d["ac_w"] == 110.6 and d["usb_c_w"] == 0.0
    assert d["line_frequency_hz"] == 60.0
    assert d["design_capacity_mah"] == 12800 and d["time_to_full_minutes"] is None
    assert d["battery_temperature_c"] == 34.0 and d["system_temperature_c"] == 34.0
    assert d["temperatures_c"] == [34.0, 34.0, 25.0, 25.0]
    assert set(d) == {"total_w", "input_w", "input_ac_w", "input_solar_dc_w",
                      "ac_w", "dc_w", "usb_a_w", "usb_c_w", "line_frequency_hz",
                      "design_capacity_mah", "time_to_full_minutes",
                      "battery_temperature_c", "system_temperature_c", "temperatures_c"}


def quadro_com(segmentos):
    """Um quadro sintético em cima do REAL: mesma chave de ofuscação, tamanho e
    verificação recalculados. Só a área de segmentos muda."""
    claro = bytearray(rs.desofusca(QUADRO))
    corpo = b"".join(struct.pack("<HB", tipo, len(dados)) + dados for tipo, dados in segmentos)
    novo = claro[:rs.SEGMENTOS_INICIO] + corpo
    struct.pack_into("<H", novo, 2, len(novo) + 2 - 20)      # o que `_conversa` espera
    chave = struct.unpack_from("<I", novo, rs.SEQUENCIA_INICIO)[0] & 0xFF
    ofuscado = bytes(novo[:rs.OFUSCACAO_INICIO]) + bytes((b ^ chave) & 0xFF for b in novo[rs.OFUSCACAO_INICIO:])
    return ofuscado + struct.pack("<H", rs.crc16(ofuscado))


def test_time_to_full_is_null_when_not_charging():
    """Bytes `33 17` no tipo 23 são ausência (r3pcomms, confirmado pelo quadro
    real a 100 %); qualquer outro valor é minutos."""
    carregando = rs.interpreta(quadro_com([(23, struct.pack("<HH", 90, 0))]))
    assert carregando.tempo_para_carga_min == 90
    cheio = rs.interpreta(quadro_com([(23, b"\x33\x17\x00\x00")]))
    assert cheio.tempo_para_carga_min is None
    assert cheio.to_dict()["time_to_full_minutes"] is None


def test_the_four_temperatures_and_their_names():
    """[0] é o sistema, [1] é a bateria (o arquivo de Home Assistant do autor do
    r3pcomms); trocar os índices trocaria o sensor que o Home Assistant grava."""
    leitura = rs.interpreta(quadro_com([(4, bytes([21, 30, 25, 26]))]))
    assert leitura.temperaturas_c == (21.0, 30.0, 25.0, 26.0)
    assert leitura.temperatura_sistema_c == 21.0
    assert leitura.temperatura_c == 30.0


def test_design_capacity_is_read_in_mah():
    leitura = rs.interpreta(quadro_com([(3, struct.pack("<I", 12800))]))
    assert leitura.capacidade_projeto_mah == 12800


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

    leitura, porta = rs.ler("auto", serie_esperada="R631ZBBAWH270046",
                            conversa=conversa, portas=portas)
    assert porta == "/dev/cu.river"
    assert leitura.carga_total_w == 110.6
    assert vistas == portas          # tentou a muda antes, e não parou nela


def test_discovery_refuses_the_neighbour_device():
    """Com dois aparelhos, ler o vizinho é pior que não ler: a série decide."""
    assert rs.ler("auto", serie_esperada="OUTRO-SERIAL",
                  conversa=lambda _p: QUADRO, portas=["/dev/cu.river"]) is None


def test_discovery_refuses_when_there_is_no_serial_to_compare():
    """Sem série esperada, a descoberta não adivinha: recusa.

    Atribuir a outro aparelho os watts que aparecem na tela do dono é pior que
    não mostrar watt nenhum (revisão fria, 2.ª rodada).
    """
    assert rs.ler("auto", conversa=lambda _p: QUADRO, portas=["/dev/cu.river"]) is None


def test_a_port_chosen_by_hand_is_the_owner_s_call():
    """Porta escolhida na configuração vale mesmo sem série: a escolha é do dono."""
    leitura, porta = rs.ler("/dev/cu.river", conversa=lambda _p: QUADRO)
    assert porta == "/dev/cu.river" and leitura.serie == "R631ZBBAWH270046"


def test_a_port_that_explodes_never_breaks_the_caller():
    def explode(_porta):
        raise OSError(6, "Device not configured")

    assert rs.ler("/dev/cu.sumiu", conversa=explode) is None
