"""O trecho do `ups.conf` que o serviço mantém — e o que ele NUNCA toca.

A promessa do instalador é que quem configurou o NUT à mão continua com a
configuração dele. Todo teste aqui existe para provar que essa promessa
sobrevive ao serviço passar a declarar os aparelhos que publica.
"""

from __future__ import annotations

import os

import pytest

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


def test_a_half_cut_block_makes_us_keep_our_hands_off(tmp_path):
    """Marca de abertura sem a de fim: alguém cortou o arquivo no meio.

    A primeira versão disto acrescentava o trecho novo no fim e deixava a marca
    órfã para trás. A volta SEGUINTE do laço — dois segundos depois — tomava a
    órfã como começo e a marca de fim recém-escrita como término, e apagava tudo
    entre as duas: conteúdo do dono, inclusive a seção do leitor de fábrica, que
    é a que a proteção lê (2.ª revisão fria da 0.7.0, reproduzido).

    Não mexer é a única resposta honesta.
    """
    caminho = arquivo(tmp_path, DO_DONO + nut_conf.MARCA_INICIO + "\n[quebrado]\n")
    antes = open(caminho, encoding="utf-8").read()
    for _ in range(3):                      # o laço chama a cada dois segundos
        with pytest.raises(nut_conf.ConfMalformada, match="uma marca só"):
            nut_conf.atualizar(caminho, APARELHOS)
    assert open(caminho, encoding="utf-8").read() == antes


def test_two_blocks_are_refused_instead_of_leaving_one_orphan_forever(tmp_path):
    """Dois trechos: o arquivo não é o que pensamos, e não se adivinha qual vale."""
    caminho = arquivo(tmp_path, DO_DONO + nut_conf.bloco([("a", "x")])
                      + nut_conf.bloco([("b", "y")]))
    with pytest.raises(nut_conf.ConfMalformada, match="deveria haver uma de cada"):
        nut_conf.atualizar(caminho, APARELHOS)


def test_a_file_the_owner_locked_stays_locked(tmp_path):
    """A troca atômica passa pela permissão da PASTA, não pela do arquivo.

    Sem esta conferência, o "não mexa" do dono era ignorado em silêncio.
    """
    caminho = arquivo(tmp_path, modo=0o444)
    with pytest.raises(nut_conf.ConfMalformada, match="permissão de escrita"):
        nut_conf.atualizar(caminho, APARELHOS)
    assert open(caminho, encoding="utf-8").read() == DO_DONO


def test_a_symlink_is_followed_not_destroyed(tmp_path):
    """Quem guarda a configuração do NUT num repositório pessoal aponta um link.

    Trocando o link por um arquivo comum, ele passava a editar um arquivo que o
    NUT não lê mais — e a edição dele sumia do sistema sem uma linha de registro.
    """
    real = tmp_path / "real.conf"
    real.write_text(DO_DONO, encoding="utf-8")
    link = tmp_path / "ups.conf"
    link.symlink_to(real)
    assert nut_conf.atualizar(str(link), APARELHOS) is True
    assert link.is_symlink(), "o link virou arquivo comum"
    assert "[river-bridge]" in real.read_text(encoding="utf-8")


def test_a_description_with_a_quote_does_not_break_the_line(tmp_path):
    """O texto vem de fora: é o modelo que o no-break declarou."""
    caminho = arquivo(tmp_path)
    nut_conf.atualizar(caminho, [("river-bridge", 'RIVER 3 "Plus"')])
    # A última: a primeira é a do próprio dono, no fixture.
    linha = [l for l in open(caminho, encoding="utf-8") if "desc =" in l][-1]
    assert linha.strip() == 'desc = "RIVER 3 \\"Plus\\""'


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


def test_removing_takes_the_marks_with_it(tmp_path):
    """Um trecho vazio, só com as duas marcas, continuaria dizendo ao servidor do
    no-break que este arquivo é nosso. A remoção completa tira tudo."""
    caminho = arquivo(tmp_path)
    nut_conf.atualizar(caminho, APARELHOS)
    assert nut_conf.remover(caminho) is True
    texto = open(caminho, encoding="utf-8").read()
    assert nut_conf.MARCA_INICIO not in texto and nut_conf.MARCA_FIM not in texto
    assert "[river-office]" in texto and texto.startswith("maxretry = 3")
    # E remover de novo não muda nada: não há o que tirar.
    assert nut_conf.remover(caminho) is False
