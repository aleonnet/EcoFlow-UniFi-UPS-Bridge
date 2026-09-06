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
    assert remocao.no_lixo(vigia.caminho_atual())
    assert vigia.deve_remover() is True
    vigia.fechar()


def test_o_lixo_de_um_volume_externo_tambem_conta(maquina):
    """Num disco externo o Lixo é `/.Trashes/<uid>/`, não `~/.Trash/`."""
    (maquina / ".Trashes" / "501").mkdir(parents=True)
    app = pacote_em(maquina / "Applications")
    vigia = VigiaDoPacote(app)
    os.rename(app, maquina / ".Trashes" / "501" / "River Bridge.app")
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
    assert remocao.no_lixo(vigia.caminho_atual())
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


class FilhoDeMentira:
    """O que o `Popen` injetado devolve. `desregistrar` não espera por ninguém."""

    def __init__(self, argv):
        self.argv = argv


def pacote_com_ajudante(raiz):
    app = raiz / "River Bridge.app"
    (app / "Contents" / "MacOS").mkdir(parents=True)
    ajudante = app / "Contents" / "MacOS" / "river-bridge-servico"
    ajudante.write_text("#!/bin/sh\n")
    ajudante.chmod(0o755)
    return app


def test_o_ajudante_desregistra_antes_do_bootout(tmp_path):
    """O interruptor nos Ajustes do Sistema só se apaga por `SMAppService.unregister()`,
    e só um executável do pacote pode chamá-lo — como o usuário da sessão, que foi
    quem autorizou. O dono viu o programa no Lixo e o interruptor ligado (2026-09-06).
    """
    app = pacote_com_ajudante(tmp_path)
    lancados: list = []
    diario: list = []

    def spawn(argv, **kw):
        filho = FilhoDeMentira(argv)
        lancados.append((argv, kw))
        return filho

    remocao.desregistrar("com.exemplo", pacote=str(app), uid_da_console=lambda: 501,
                         spawn=spawn, log=lambda lvl, ev, **p: diario.append((lvl, ev, p)))
    assert len(lancados) == 2
    argv_ajudante, kw_ajudante = lancados[0]
    assert argv_ajudante == ["/bin/launchctl", "asuser", "501", "/usr/bin/sudo", "-u", "#501",
                             str(app / "Contents" / "MacOS" / "river-bridge-servico"), "unregister"]
    # Sessão nova (sobrevive à morte do serviço) e saída HERDADA (o diário): é o
    # ajudante quem escreve `unregister=ok` lá, e ninguém espera por ele — o
    # `unregister` mata este serviço no instante seguinte.
    assert kw_ajudante["start_new_session"] is True
    assert kw_ajudante.get("stdout") is None and kw_ajudante.get("stderr") is None
    assert lancados[1][0][:2] == ["/bin/launchctl", "bootout"]
    assert any(ev == "ajudante_do_registro_lancado" and p["argv"] == argv_ajudante
               for _l, ev, p in diario)


def test_sem_ninguem_na_sessao_o_ajudante_roda_como_root(tmp_path):
    app = pacote_com_ajudante(tmp_path)
    lancados: list = []
    remocao.desregistrar("com.exemplo", pacote=str(app), uid_da_console=lambda: None,
                         spawn=lambda argv, **kw: lancados.append(argv) or FilhoDeMentira(argv))
    assert lancados[0] == [str(app / "Contents" / "MacOS" / "river-bridge-servico"), "unregister"]


def test_sem_ajudante_no_pacote_so_o_bootout_e_o_diario_diz(tmp_path):
    lancados: list = []
    diario: list = []
    remocao.desregistrar("com.exemplo", pacote=str(tmp_path / "sem-ajudante.app"),
                         uid_da_console=lambda: 501,
                         spawn=lambda argv, **kw: lancados.append(argv) or FilhoDeMentira(argv),
                         log=lambda lvl, ev, **p: diario.append(ev))
    assert [a[:2] for a in lancados] == [["/bin/launchctl", "bootout"]]
    assert "ajudante_do_registro_ausente" in diario


def test_pacote_atual_e_a_raiz_do_pacote(maquina):
    app = pacote_em(maquina / "Applications")
    vigia = VigiaDoPacote(app)
    assert vigia.pacote_atual() == os.path.realpath(app) or vigia.pacote_atual() == str(app)
    vigia.fechar()


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
