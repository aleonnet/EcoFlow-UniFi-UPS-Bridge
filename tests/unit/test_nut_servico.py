"""Quem a ponte publica no NUT — e, principalmente, quem ela NÃO publica.

Nenhum soquete de verdade aqui: o driver é injetado. O protocolo tem casa
própria (`test_nut_driver.py`); o que se testa aqui é a decisão.
"""

from __future__ import annotations

import pytest

from river_unifi_bridge.config import ConfigError, load_config, recusa_do_vigia_espelho
from river_unifi_bridge.model import snapshot_from_nut_vars
from river_unifi_bridge.nut_servico import PonteDoNut

CONFIG_MINIMA = (
    "RIVER_NAME=River\nNUT_HOST=127.0.0.1\nNUT_PORT=3493\nNUT_UPS=river-office\n")


class DriverFalso:
    def __init__(self, caminho, *, log=None, executor=None):
        self.caminho = caminho
        self.executor = executor
        self.publicado: dict = {}
        self.comandos: tuple = ()
        self.no_ar = False
        self.velho = False

    def iniciar(self):
        self.no_ar = True

    def encerrar(self):
        self.no_ar = False

    def publicar(self, variaveis, *, comandos=(), dados_ok=True):
        self.publicado = dict(variaveis)
        self.comandos = tuple(comandos)
        self.velho = not dados_ok

    def marcar_sem_dados(self):
        self.velho = True


class PluginFalso:
    fabricante = "Ubiquiti"

    def __init__(self, identificador="udr7", *, provado=True, registro=None):
        self.id = identificador
        self._provado = provado
        self._registro = registro if registro is not None else {
            "modelo": "UniFi Dream Router 7", "firmware": "5.1.31"}

    def status(self):
        return {"name": "UDR7 da sala", "state": "ensaio"}

    def alcance_valido(self):
        return self._provado

    def alcance_registrado(self):
        return dict(self._registro)


def snapshot():
    return snapshot_from_nut_vars("River", {
        "device.mfr": "EcoFlow", "device.model": "RIVER 3 Plus",
        "device.serial": "R331ZEB4XXXX", "ups.status": "OL", "battery.charge": "88",
    })


@pytest.fixture
def criados():
    """Guarda cada driver que a ponte pediu, na ordem."""
    feitos: list[DriverFalso] = []

    def fabrica(caminho, **kw):
        d = DriverFalso(caminho, **kw)
        feitos.append(d)
        return d

    fabrica.feitos = feitos
    return fabrica


def ponte(tmp_path, criados, **kw):
    return PonteDoNut(estado=str(tmp_path), criar_driver=criados, **kw)


# -- o River -------------------------------------------------------------------

def test_the_river_is_published_with_the_name_the_configuration_gives(tmp_path, criados):
    p = ponte(tmp_path, criados, aparelho="river-bridge")
    p.iniciar()
    assert p.aparelhos() == ["river-bridge"]
    assert criados.feitos[0].caminho.endswith("/river-bridge-river-bridge")


def test_without_nut_installed_nothing_is_published(tmp_path, criados):
    """Sem a pasta de estado do NUT não há para quem publicar.

    Criá-la assim mesmo seria deixar lixo numa máquina que não pediu nada — e o
    serviço tem de continuar vigiando o River do mesmo jeito.
    """
    p = ponte(tmp_path / "nao-existe", criados)
    p.iniciar()
    assert p.aparelhos() == []
    assert criados.feitos == []


def test_the_reading_of_the_cycle_reaches_the_server(tmp_path, criados):
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot())
    assert criados.feitos[0].publicado["battery.charge"] == "88"
    assert criados.feitos[0].publicado["ups.status"] == "OL"


def test_when_the_ups_goes_quiet_the_server_is_told(tmp_path, criados):
    """Sem isto, o Home Assistant mostraria a última carga como se fosse a de agora."""
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot(), [PluginFalso()])
    p.marcar_sem_dados()
    assert all(d.velho for d in criados.feitos)


# -- os dispositivos protegidos ------------------------------------------------

def test_a_device_without_proven_reach_is_not_published(tmp_path, criados):
    """Um aparelho no Home Assistant com ordem que não chega a lugar nenhum é
    pior que aparelho nenhum — e a hora de descobrir seria a pior possível."""
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot(), [PluginFalso(provado=False)])
    assert p.aparelhos() == ["river-bridge"]


def test_a_device_with_proven_reach_becomes_a_device_of_its_own(tmp_path, criados):
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot(), [PluginFalso()])
    assert p.aparelhos() == ["river-bridge", "udr7"]
    do_dispositivo = criados.feitos[1].publicado
    assert do_dispositivo["device.model"] == "UniFi Dream Router 7"
    assert do_dispositivo["ups.firmware"] == "5.1.31"
    assert do_dispositivo["device.mfr"] == "Ubiquiti"
    assert do_dispositivo["ups.status"] == "OL"      # a energia dele é a do River
    assert do_dispositivo["device.description"] == "UDR7 da sala"


def test_a_device_removed_from_the_app_stops_being_published(tmp_path, criados):
    """Apagado na tela, ele tem de sumir do NUT — não ficar como fantasma."""
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot(), [PluginFalso()])
    p.atualizar(snapshot(), [])
    assert p.aparelhos() == ["river-bridge"]
    assert criados.feitos[1].no_ar is False


def test_a_device_that_loses_its_reach_proof_stops_being_published(tmp_path, criados):
    """A prova vale 30 dias. Vencida, o aparelho sai — em vez de continuar
    oferecendo um desligamento que já não se sabe se chega."""
    plugin = PluginFalso()
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot(), [plugin])
    plugin._provado = False
    p.atualizar(snapshot(), [plugin])
    assert p.aparelhos() == ["river-bridge"]


def test_a_device_name_that_would_not_be_a_valid_ups_is_refused(tmp_path, criados):
    """O nome vira metade do nome de um arquivo de soquete e entra no ups.conf."""
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot(), [PluginFalso("../fora")])
    assert p.aparelhos() == ["river-bridge"]


def test_closing_takes_every_device_with_it(tmp_path, criados):
    p = ponte(tmp_path, criados)
    p.iniciar()
    p.atualizar(snapshot(), [PluginFalso()])
    p.encerrar()
    assert p.aparelhos() == []
    assert not any(d.no_ar for d in criados.feitos)


# -- a cerca do vigia espelho ---------------------------------------------------

def test_the_protection_may_not_read_a_device_we_publish(tmp_path):
    """Lendo o próprio eco, a proteção decidiria com dados que ela mesma escreveu.

    Um erro de leitura viraria verdade e se confirmaria sozinho a cada volta. É
    recusa de partida: um serviço que sobe assim parece saudável e não vigia nada.
    """
    arquivo = tmp_path / "bridge.env"
    arquivo.write_text(CONFIG_MINIMA.replace("NUT_UPS=river-office",
                                             "NUT_UPS=river-bridge"), encoding="utf-8")
    with pytest.raises(ConfigError, match="a própria ponte publica"):
        load_config(str(arquivo))


def test_the_same_name_is_fine_when_we_are_not_publishing(tmp_path):
    """Sem publicar, não há eco para a proteção ler — e a configuração vale."""
    arquivo = tmp_path / "bridge.env"
    arquivo.write_text(
        CONFIG_MINIMA.replace("NUT_UPS=river-office", "NUT_UPS=river-bridge")
        + "RIVER_NUT_PUBLICA=0\n", encoding="utf-8")
    assert load_config(str(arquivo)).nut_ups == "river-bridge"


def test_a_protected_device_name_is_refused_as_the_protection_source():
    """O aparelho de um dispositivo protegido também é publicado por nós.

    A instância migrada se chama `udr7`, e com `NUT_UPS=udr7` a proteção passaria
    a ler a carga de bateria que ela mesma escreveu na volta anterior — o mesmo
    laço fechado, por outra porta (revisão fria da 0.7.0).
    """
    motivo = recusa_do_vigia_espelho("udr7", "river-bridge", publica=True,
                                     dispositivos={"udr7"})
    assert motivo is not None and "dispositivo protegido" in motivo


def test_the_rule_is_the_same_one_the_screen_uses_before_writing():
    """A mesma função vale nos dois caminhos: o arquivo, na partida, e a tela.

    Só no arquivo não bastava — a tela gravava a configuração ruim, mandava
    reiniciar, e no reinício o serviço parava de propósito e não voltava.
    """
    assert recusa_do_vigia_espelho("river-office", "river-bridge", publica=True,
                                   dispositivos={"udr7"}) is None
    assert recusa_do_vigia_espelho("udr7", "river-bridge", publica=False,
                                   dispositivos={"udr7"}) is None


def test_the_factory_reader_keeps_working_as_the_source(tmp_path):
    """O caminho normal: a proteção lê o leitor de fábrica, nós publicamos ao lado."""
    arquivo = tmp_path / "bridge.env"
    arquivo.write_text(CONFIG_MINIMA, encoding="utf-8")
    cfg = load_config(str(arquivo))
    assert cfg.nut_ups == "river-office" and cfg.river_nut_aparelho == "river-bridge"
