"""O serviço se retira sozinho quando o pacote vai para o Lixo — e SÓ aí.

Os `mv` aqui são de verdade (o sistema de arquivos desta máquina): é o
`F_GETPATH` real respondendo, não um dublê. O que é dublê é o `launchctl`.
"""

from __future__ import annotations

import os

import pytest

from river_unifi_bridge import remocao
from river_unifi_bridge.remocao import VigiaDoPacote


def pacote_em(pasta) -> str:
    """Um pacote de mentira com a única coisa que o vigia abre: o Info.plist."""
    app = pasta / "River Bridge.app"
    (app / "Contents").mkdir(parents=True)
    (app / "Contents" / "Info.plist").write_text("<plist/>")
    return str(app)


@pytest.fixture
def maquina(tmp_path):
    (tmp_path / "Applications").mkdir()
    (tmp_path / ".Trash").mkdir()
    (tmp_path / "Outra").mkdir()
    return tmp_path


def test_no_lixo_dispara(maquina):
    app = pacote_em(maquina / "Applications")
    vigia = VigiaDoPacote(app)
    assert vigia.deve_remover() is False          # em Aplicativos, nada acontece
    os.rename(app, maquina / ".Trash" / "River Bridge.app")
    assert remocao.LIXO in (vigia.caminho_atual() or "")
    assert vigia.deve_remover() is True
    vigia.fechar()


def test_mover_fora_do_lixo_nao_remove(maquina):
    """Mudar o pacote de pasta não é jogá-lo fora."""
    app = pacote_em(maquina / "Applications")
    vigia = VigiaDoPacote(app)
    os.rename(app, maquina / "Outra" / "River Bridge.app")
    assert "/Outra/" in (vigia.caminho_atual() or "")
    assert vigia.deve_remover() is False
    vigia.fechar()


def test_substituido_no_lugar_nao_remove(maquina):
    """Atualizar pelo Finder pode pôr o pacote antigo no Lixo com o novo no
    lugar dele. Isso é atualização, não remoção: nada pode ser apagado."""
    app = pacote_em(maquina / "Applications")
    vigia = VigiaDoPacote(app)
    os.rename(app, maquina / ".Trash" / "River Bridge.app")
    pacote_em(maquina / "Applications")           # o novo ocupa o caminho original
    assert remocao.LIXO in (vigia.caminho_atual() or "")
    assert vigia.deve_remover() is False
    vigia.fechar()


def test_arquivo_apagado_nao_dispara(maquina):
    """Apagado não é Lixo: sumir não dispara nada."""
    app = pacote_em(maquina / "Applications")
    vigia = VigiaDoPacote(app)
    os.remove(os.path.join(app, "Contents", "Info.plist"))
    os.rmdir(os.path.join(app, "Contents"))
    os.rmdir(app)
    assert vigia.deve_remover() is False
    vigia.fechar()


def test_partida_dentro_do_lixo_dispara(maquina):
    """Relançado pelo launchd com o pacote já no Lixo: remove na primeira volta."""
    app = pacote_em(maquina / ".Trash")
    vigia = VigiaDoPacote(app)
    assert vigia.deve_remover() is True
    vigia.fechar()


def test_bootout_nasce_em_sessao_nova():
    lancados: list[tuple] = []
    remocao.desregistrar("com.exemplo", spawn=lambda argv, **kw: lancados.append((argv, kw)))
    assert len(lancados) == 1
    argv, kw = lancados[0]
    assert argv[:2] == ["/bin/launchctl", "bootout"] and argv[2] == "system/com.exemplo"
    assert kw["start_new_session"] is True, "no mesmo grupo o launchctl morre com o serviço"


def test_retirar_apaga_antes_de_desregistrar(tmp_path):
    ordem: list[str] = []
    remocao.retirar(str(tmp_path), str(tmp_path / "ups.conf"), "x",
                    apagar=lambda *_a: ordem.append("apagar") or [],
                    desregistrar_=lambda *_a, **_k: ordem.append("desregistrar"))
    assert ordem == ["apagar", "desregistrar"]


def test_apagar_tudo_leva_o_estado_inteiro_e_o_trecho_do_ups_conf(tmp_path):
    estado = tmp_path / "estado"
    (estado / "nut").mkdir(parents=True)
    (estado / "nut" / "upsd.users").write_text("[x]\n")
    (estado / "udr7_key").write_text("chave")
    (estado / "history.sqlite").write_text("")
    ups_conf = tmp_path / "ups.conf"
    ups_conf.write_text("[river-office]\n    driver = usbhid-ups\n"
                        "# >>> River Bridge — gerado pelo serviço, não edite até a marca de fim\n"
                        "[river-bridge]\n    driver = river-bridge\n"
                        "# <<< River Bridge — fim do trecho gerado\n")
    apagados = remocao.apagar_tudo(str(estado), str(ups_conf))
    assert not estado.exists()
    assert set(apagados) == {"history.sqlite", "nut", "udr7_key", "ups.conf (o nosso trecho)"}
    assert "River Bridge" not in ups_conf.read_text()
    assert "[river-office]" in ups_conf.read_text()   # o que é do dono fica
