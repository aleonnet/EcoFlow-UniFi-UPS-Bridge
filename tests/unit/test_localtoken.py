"""Onde o estado mora, quem consegue ler a ficha, e a mudança de casa.

Nenhum teste toca em `/Library` nem em `/Users`: as duas pastas são injetadas.
"""

from __future__ import annotations

import os

from river_unifi_bridge import localtoken


def test_the_token_is_created_once_and_reused(tmp_path):
    primeira = localtoken.get_or_create_token(str(tmp_path))
    assert primeira == localtoken.get_or_create_token(str(tmp_path))
    caminho = tmp_path / localtoken.TOKEN_FILENAME
    assert oct(os.stat(caminho).st_mode)[-3:] == "600"


def test_an_empty_token_file_is_replaced_not_used(tmp_path):
    """Ficha vazia é ficha nenhuma: usá-la deixaria a API sem autenticação."""
    (tmp_path / localtoken.TOKEN_FILENAME).write_text("\n", encoding="utf-8")
    assert localtoken.get_or_create_token(str(tmp_path)).strip()


def test_the_environment_wins_over_both_folders(monkeypatch, tmp_path):
    """É o que o lançador dentro do pacote define, e o que deixa os testes herméticos."""
    monkeypatch.setenv("RUB_STATE_DIR", str(tmp_path))
    assert localtoken.state_dir() == str(tmp_path)


def test_without_the_environment_the_folder_follows_who_is_running(monkeypatch):
    """Estado de serviço de SISTEMA não mora na pasta de um usuário.

    Quem instala pela linha de comando roda como o próprio usuário; quem instala
    arrastando o app roda como serviço do sistema.
    """
    monkeypatch.delenv("RUB_STATE_DIR", raising=False)
    monkeypatch.setattr(localtoken.os, "geteuid", lambda: 0)
    assert localtoken.state_dir() == localtoken.PASTA_DO_SISTEMA
    monkeypatch.setattr(localtoken.os, "geteuid", lambda: 501)
    assert localtoken.state_dir().endswith("Library/Application Support/river-unifi-bridge")
    assert not localtoken.state_dir().startswith("/Library")


# -- a mudança de casa ---------------------------------------------------------

def montar_origem(tmp_path, **arquivos):
    origem = tmp_path / "antiga"
    origem.mkdir()
    for nome, conteudo in arquivos.items():
        (origem / nome).write_text(conteudo, encoding="utf-8")
    return str(origem)


def test_changing_how_you_install_does_not_cost_the_console_key(tmp_path, monkeypatch):
    """A chave, o histórico e a lista de dispositivos vêm junto — uma vez."""
    origem = montar_origem(tmp_path, **{"udr7_key": "PRIVADA", "devices.json": "[]",
                                        "bridge.env": "NUT_UPS=river-office\n"})
    destino = tmp_path / "sistema"
    monkeypatch.setattr(localtoken, "PASTA_DO_SISTEMA", str(destino))
    assert localtoken.migrar_estado_uma_vez(str(destino), origens=[origem]) == origem
    assert (destino / "udr7_key").read_text(encoding="utf-8") == "PRIVADA"
    assert (destino / "devices.json").exists()
    # E o original fica intocado: voltar atrás continua possível.
    assert os.path.exists(os.path.join(origem, "udr7_key"))


def test_the_owners_configuration_wins_over_the_example_the_launcher_copied(tmp_path, monkeypatch):
    """O lançador copia o exemplo antes de o Python rodar.

    Sem esta exceção, o exemplo — que não tem os limiares, as travas nem o número
    de série que o dono ajustou — ganharia da configuração dele.
    """
    origem = montar_origem(tmp_path, **{"bridge.env": "UDR7_SHUTDOWN_PERCENT=35\n"})
    destino = tmp_path / "sistema"
    destino.mkdir()
    (destino / "bridge.env").write_text("# exemplo\n", encoding="utf-8")
    monkeypatch.setattr(localtoken, "PASTA_DO_SISTEMA", str(destino))
    localtoken.migrar_estado_uma_vez(str(destino), origens=[origem])
    assert "UDR7_SHUTDOWN_PERCENT=35" in (destino / "bridge.env").read_text(encoding="utf-8")


def test_a_destination_that_already_has_state_is_left_alone(tmp_path, monkeypatch):
    """Já instalado é já instalado: copiar por cima apagaria o que está valendo."""
    origem = montar_origem(tmp_path, **{"devices.json": "[antiga]"})
    destino = tmp_path / "sistema"
    destino.mkdir()
    (destino / "devices.json").write_text("[a que vale]", encoding="utf-8")
    monkeypatch.setattr(localtoken, "PASTA_DO_SISTEMA", str(destino))
    assert localtoken.migrar_estado_uma_vez(str(destino), origens=[origem]) is None
    assert (destino / "devices.json").read_text(encoding="utf-8") == "[a que vale]"


def test_two_previous_installations_stop_the_move_instead_of_guessing(tmp_path, monkeypatch):
    """Com duas casas de usuário não dá para saber qual é a boa.

    Adivinhar seria levar para o serviço a chave e os dispositivos da pessoa
    errada. O registro diz o que aconteceu, e ninguém perde nada.
    """
    uma = montar_origem(tmp_path, **{"devices.json": "[uma]"})
    outra = tmp_path / "outra"
    outra.mkdir()
    (outra / "devices.json").write_text("[outra]", encoding="utf-8")
    destino = tmp_path / "sistema"
    monkeypatch.setattr(localtoken, "PASTA_DO_SISTEMA", str(destino))
    avisos = []
    assert localtoken.migrar_estado_uma_vez(
        str(destino), origens=[uma, str(outra)],
        log=lambda nivel, evento, **kw: avisos.append(evento)) is None
    assert avisos == ["estado_nao_migrado"]
    assert not destino.exists()


def test_the_move_only_happens_on_the_system_path(tmp_path):
    """Instalação por linha de comando não muda de casa: ela já está na dela."""
    origem = montar_origem(tmp_path, **{"devices.json": "[]"})
    destino = tmp_path / "do-usuario"
    assert localtoken.migrar_estado_uma_vez(str(destino), origens=[origem]) is None
    assert not destino.exists()
