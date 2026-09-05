"""O trecho do `ups.conf` que o serviço mantém — e o que ele NUNCA toca.

A promessa do instalador é que quem configurou o NUT à mão continua com a
configuração dele. Todo teste aqui existe para provar que essa promessa
sobrevive ao serviço passar a declarar os aparelhos que publica.
"""

from __future__ import annotations

import os

from river_unifi_bridge import nut_conf

DO_DONO = """maxretry = 3

[river-office]
    driver = usbhid-ups
    port = auto
    desc = "EcoFlow RIVER 3 Plus"
"""

APARELHOS = [("river-bridge", "River 3 Plus (River Bridge)"),
             ("udr7", "UDR7 da sala")]


def arquivo(tmp_path, texto=DO_DONO, modo=0o644):
    caminho = tmp_path / "ups.conf"
    caminho.write_text(texto, encoding="utf-8")
    os.chmod(caminho, modo)
    return str(caminho)


def test_a_file_that_does_not_exist_is_not_created(tmp_path):
    """Quem cria o `ups.conf` é o instalador, uma vez. O serviço nunca inventa um."""
    caminho = str(tmp_path / "nao-existe.conf")
    assert nut_conf.atualizar(caminho, APARELHOS) is False
    assert not os.path.exists(caminho)


def test_what_the_owner_wrote_by_hand_is_never_touched(tmp_path):
    caminho = arquivo(tmp_path)
    nut_conf.atualizar(caminho, APARELHOS)
    texto = open(caminho, encoding="utf-8").read()
    assert texto.startswith(DO_DONO), "o que já estava no arquivo mudou de lugar"
    assert "[river-office]" in texto and "driver = usbhid-ups" in texto


def test_the_devices_we_publish_are_declared_the_way_the_server_expects(tmp_path):
    """`driver` e `port` são obrigatórios, e o `driver` é metade do nome do soquete.

    Errando esse nome, o servidor procura num lugar em que ninguém escuta.
    """
    caminho = arquivo(tmp_path)
    assert nut_conf.atualizar(caminho, APARELHOS) is True
    texto = open(caminho, encoding="utf-8").read()
    assert "[river-bridge]\n    driver = river-bridge\n    port = auto\n" in texto
    assert "[udr7]\n    driver = river-bridge\n    port = auto\n" in texto


def test_a_device_that_goes_away_leaves_the_file(tmp_path):
    """Apagado na tela, ele some do `ups.conf` — não fica como declaração morta."""
    caminho = arquivo(tmp_path)
    nut_conf.atualizar(caminho, APARELHOS)
    assert nut_conf.atualizar(caminho, APARELHOS[:1]) is True
    texto = open(caminho, encoding="utf-8").read()
    assert "[udr7]" not in texto and "[river-bridge]" in texto
    assert "[river-office]" in texto          # o do dono continua


def test_nothing_changes_when_nothing_changed(tmp_path):
    """Reescrever à toa faria o servidor do no-break reiniciar a cada volta do laço —
    e cada reinício é um buraco na leitura do River."""
    caminho = arquivo(tmp_path)
    assert nut_conf.atualizar(caminho, APARELHOS) is True
    assert nut_conf.atualizar(caminho, APARELHOS) is False


def test_the_file_mode_survives(tmp_path):
    """A troca atômica não pode devolver o arquivo com outra permissão."""
    caminho = arquivo(tmp_path, modo=0o640)
    nut_conf.atualizar(caminho, APARELHOS)
    assert oct(os.stat(caminho).st_mode)[-3:] == "640"


def test_a_half_cut_block_is_not_used_as_an_excuse_to_eat_the_rest(tmp_path):
    """Marca de abertura sem a de fim: alguém cortou o arquivo no meio.

    Reescrever dali para a frente apagaria o que viesse depois — inclusive a
    seção do leitor de fábrica, que é a que a proteção lê.
    """
    caminho = arquivo(tmp_path, DO_DONO + nut_conf.MARCA_INICIO + "\n[quebrado]\n")
    nut_conf.atualizar(caminho, APARELHOS)
    texto = open(caminho, encoding="utf-8").read()
    assert "[river-office]" in texto and "[quebrado]" in texto
    assert "[river-bridge]" in texto


def test_no_temporary_file_is_left_behind(tmp_path):
    caminho = arquivo(tmp_path)
    nut_conf.atualizar(caminho, APARELHOS)
    assert [n for n in os.listdir(tmp_path)] == ["ups.conf"]


def test_what_comes_after_our_block_survives_a_rewrite(tmp_path):
    """O trecho pode estar no MEIO do arquivo, com coisa do dono depois dele.

    Reescrever até o fim, em vez de trocar só o miolo, apagaria o que vem
    depois — inclusive a seção do leitor de fábrica, que é a que a proteção lê.
    """
    depois_do_nosso = """
[outro-nobreak]
    driver = usbhid-ups
    port = auto
"""
    caminho = arquivo(
        tmp_path,
        DO_DONO + nut_conf.bloco([("river-bridge", "antigo")]) + depois_do_nosso)
    nut_conf.atualizar(caminho, APARELHOS)
    texto = open(caminho, encoding="utf-8").read()
    assert "[river-office]" in texto, "sumiu o que vinha ANTES do nosso trecho"
    assert "[outro-nobreak]" in texto, "sumiu o que vinha DEPOIS do nosso trecho"
    assert "[udr7]" in texto and 'desc = "antigo"' not in texto
