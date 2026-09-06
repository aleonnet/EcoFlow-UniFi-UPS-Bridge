"""O que a ponte conta ao NUT — e, por tabela, o que o Home Assistant mostra.

Cada nome aqui é o do dicionário oficial do NUT (`docs/nut-names.txt`). Não é
preciosismo: o Home Assistant só cria sensor para o nome que ele conhece, então
um nome nosso significaria um número que chega e não aparece em lugar nenhum.
"""

from __future__ import annotations

from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.nut_publicacao import variaveis_do_dispositivo, variaveis_do_river

VARS_DO_NOBREAK = {
    "device.mfr": "EcoFlow", "device.model": "RIVER 3 Plus",
    "device.serial": "R331ZEB4XXXX", "ups.status": "OL CHRG",
    "battery.charge": "88", "battery.runtime": "3600", "battery.voltage": "25.6",
    "battery.charge.low": "20", "input.voltage": "121.4", "output.voltage": "120.0",
}
TOMADAS = {
    "total_w": 41.2, "input_w": 55.0, "ac_w": 30.5, "dc_w": 0.0,
    "usb_a_w": 2.7, "usb_c_w": 8.0, "line_frequency_hz": 60.0,
}


def snapshot(*, com_tomadas: bool = False, **extra):
    """A leitura de um ciclo, como o serviço a monta.

    Com a porta serial respondendo, é o próprio serviço que grava as tomadas, o
    consumo total, a entrada e a frequência no mesmo objeto (`_completa_pela_serial`
    em service.py) — então o teste monta a leitura do mesmo jeito.
    """
    snap = snapshot_from_nut_vars("River", dict(VARS_DO_NOBREAK, **extra))
    if com_tomadas:
        snap.outlets = TOMADAS
        snap.output_power_w = TOMADAS["total_w"]
        snap.input_power_w = TOMADAS["input_w"]
        snap.line_frequency_hz = TOMADAS["line_frequency_hz"]
    return snap


def test_the_raw_status_travels_untouched():
    """O NUT fala "OL CHRG", não "ONLINE". Traduzir aqui quebraria todo cliente."""
    assert variaveis_do_river(snapshot())["ups.status"] == "OL CHRG"


def test_a_status_token_we_do_not_know_is_not_dropped():
    """Token desconhecido continua indo: quem o entende pode não ser nós."""
    saida = variaveis_do_river(snapshot(**{"ups.status": "OL XPTO"}))
    assert saida["ups.status"] == "OL XPTO"


def test_the_battery_and_the_line_come_out_with_the_official_names():
    saida = variaveis_do_river(snapshot())
    assert saida["battery.charge"] == "88"
    assert saida["battery.runtime"] == "3600"
    assert saida["battery.voltage"] == "25.60"
    assert saida["input.voltage"] == "121.4"
    assert saida["device.serial"] == "R331ZEB4XXXX"
    assert saida["device.type"] == "ups"


def test_the_outlets_only_exist_when_the_serial_port_answered():
    """Sem leitura da porta, tomada nenhuma — e não uma tabela de zeros.

    Zero watt numa tomada é uma AFIRMAÇÃO ("não há consumo"); a ausência de
    leitura é outra coisa, e o Home Assistant tem de mostrar a segunda como
    ausência.
    """
    assert "outlet.count" not in variaveis_do_river(snapshot())
    assert "outlet.1.realpower" not in variaveis_do_river(snapshot())


def test_the_four_outlets_come_out_named_and_measured():
    """`outlet.count` é o que faz o Home Assistant procurar as tomadas.

    Medido no código dele (`outlet_numbers_from_status`): sem a contagem, ou sem
    chaves `outlet.<n>.*`, os watts por tomada não viram sensor nenhum.
    """
    saida = variaveis_do_river(snapshot(com_tomadas=True))
    assert saida["outlet.count"] == "4"
    assert saida["outlet.1.desc"] == "120 V (tomadas AC)"
    assert saida["outlet.1.realpower"] == "30.5"
    assert saida["outlet.2.realpower"] == "0.0"       # zero MEDIDO continua indo
    assert saida["outlet.3.realpower"] == "2.7"
    assert saida["outlet.4.realpower"] == "8.0"
    assert saida["input.realpower"] == "55.0"
    assert saida["input.frequency"] == "60.0"


def test_no_outlet_is_announced_as_switchable():
    """Não há caminho medido para ligar/desligar uma saída do River.

    Dizendo que há, o Home Assistant desenha um interruptor que não funciona — e
    o dono descobre isso justamente quando precisar dele.
    """
    saida = variaveis_do_river(snapshot(com_tomadas=True))
    for indice in (1, 2, 3, 4):
        assert saida[f"outlet.{indice}.switchable"] == "no"


def test_a_missing_reading_is_absent_never_zero():
    """A regra da casa vale no protocolo também: ausência não vira número."""
    magro = snapshot_from_nut_vars("River", {"ups.status": "OL"})
    saida = variaveis_do_river(magro)
    assert "battery.charge" not in saida
    assert "ups.realpower" not in saida
    assert "input.voltage" not in saida


def test_the_total_watts_come_from_the_serial_port_when_it_answered():
    """O perfil de no-break do River não publica potência; a porta serial sim."""
    assert variaveis_do_river(snapshot(com_tomadas=True))["ups.realpower"] == "41.2"


def snapshot_com_detalhes_da_serial():
    snap = snapshot(com_tomadas=True, **{"battery.temperature": "30"})
    snap.outlets = dict(TOMADAS, design_capacity_mah=12800, time_to_full_minutes=90,
                        battery_temperature_c=30.0, system_temperature_c=21.0,
                        temperatures_c=[21.0, 30.0, 25.0, 25.0], input_solar_dc_w=12.5)
    return snap


def test_capacity_comes_out_in_ah():
    """`battery.capacity.nominal` é em Ah no dicionário do NUT; a serial fala em mAh."""
    assert variaveis_do_river(snapshot_com_detalhes_da_serial())["battery.capacity.nominal"] == "12.8"
    assert "battery.capacity.nominal" not in variaveis_do_river(snapshot(com_tomadas=True))


def test_the_two_temperatures_have_their_own_sensors():
    """Bateria e sistema são sensores diferentes; sem serial, o sistema repete a bateria."""
    saida = variaveis_do_river(snapshot_com_detalhes_da_serial())
    assert saida["battery.temperature"] == "30.0"
    assert saida["ups.temperature"] == "21.0"
    sem_serial = variaveis_do_river(snapshot(**{"battery.temperature": "30"}))
    assert sem_serial["ups.temperature"] == "30.0"


def test_what_has_no_nut_name_is_not_invented():
    """Tempo até a carga completa e entrada solar não têm nome no dicionário: não saem."""
    saida = variaveis_do_river(snapshot_com_detalhes_da_serial())
    assert not any("full" in k or "solar" in k or "dc" in k.split(".") for k in saida)


# -- o dispositivo protegido como aparelho próprio -----------------------------

def test_a_protected_device_carries_the_power_situation_of_the_river():
    """A situação de energia do roteador É a do River que o alimenta."""
    saida = variaveis_do_dispositivo(snapshot(), nome="UDR7",
                                     modelo="UniFi Dream Router 7", firmware="5.1.31",
                                     fabricante="Ubiquiti")
    assert saida["ups.status"] == "OL CHRG"
    assert saida["battery.charge"] == "88"
    assert saida["device.model"] == "UniFi Dream Router 7"
    assert saida["ups.firmware"] == "5.1.31"


def test_a_serial_we_do_not_know_is_not_invented():
    """Sem número de série de verdade, nenhum é publicado.

    Inventar um o faria aparecer na tela do Home Assistant como se fosse o do
    aparelho — e a regra da casa é que dado ausente fica ausente.
    """
    saida = variaveis_do_dispositivo(snapshot(), nome="UDR7")
    assert "device.serial" not in saida
    assert "ups.serial" not in saida
