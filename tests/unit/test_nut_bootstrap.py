"""A configuração do NUT escrita por quem chegar primeiro — e o que ela não toca.

Nenhum teste escreve na configuração REAL: a pasta é injetada. Foi por não haver
esta cerca que a suíte escreveu quatro arquivos em `/opt/homebrew/etc/nut` da
máquina do dono, em 2026-09-05.
"""

from __future__ import annotations

import os

from river_unifi_bridge import nut_bootstrap


def pastas(tmp_path):
    etc = tmp_path / "nut"
    estado = tmp_path / "estado"
    etc.mkdir()
    estado.mkdir()
    return str(etc), str(estado)


def test_uma_maquina_sem_nada_ganha_tudo_o_que_precisa(tmp_path):
    """É o caminho de quem instala ARRASTANDO: o instalador de linha de comando
    nunca roda, e sem isto o serviço subia sem saber qual é o aparelho."""
    etc, estado = pastas(tmp_path)
    criados = nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    assert set(criados) == {"ups.conf", "upsd.conf", "nut.conf", "upsd.users",
                            "conta riverbridge", "conta homeassistant"}
    ups = open(os.path.join(etc, "ups.conf"), encoding="utf-8").read()
    assert "[river-office]" in ups and "driver = usbhid-ups" in ups
    users = open(os.path.join(etc, "upsd.users"), encoding="utf-8").read()
    assert "[powermanager]" in users and "[riverbridge]" in users
    assert "[homeassistant]" in users and "instcmds = ALL" in users


def test_quem_configurou_a_mao_continua_com_a_dele(tmp_path):
    """A promessa do instalador, palavra por palavra: só se escreve o que falta."""
    etc, estado = pastas(tmp_path)
    meu = "maxretry = 9\n\n[o-meu]\n    driver = usbhid-ups\n"
    open(os.path.join(etc, "ups.conf"), "w", encoding="utf-8").write(meu)
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    assert open(os.path.join(etc, "ups.conf"), encoding="utf-8").read() == meu


def test_rodar_duas_vezes_nao_cria_conta_repetida(tmp_path):
    """Duas contas com o mesmo nome deixariam o servidor usando uma e a ficha
    guardando a outra — e o serviço ouviria "acesso negado" sem explicação."""
    etc, estado = pastas(tmp_path)
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    assert nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado) == []
    users = open(os.path.join(etc, "upsd.users"), encoding="utf-8").read()
    assert users.count("[homeassistant]") == 1
    assert users.count("[riverbridge]") == 1


def test_a_senha_da_conta_e_a_MESMA_da_ficha(tmp_path):
    """São dois lugares que têm de concordar; gerar outra quebra os dois."""
    etc, estado = pastas(tmp_path)
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    users = open(os.path.join(etc, "upsd.users"), encoding="utf-8").read()
    ficha = open(os.path.join(estado, nut_bootstrap.FICHA_HOME_ASSISTANT),
                 encoding="utf-8").read().strip()
    assert ficha and f"password = {ficha}" in users


def test_uma_conta_que_ja_existe_manda_na_ficha(tmp_path):
    """A senha que está no arquivo é a verdade — a ficha é reescrita a partir dela."""
    etc, estado = pastas(tmp_path)
    open(os.path.join(etc, "upsd.users"), "w", encoding="utf-8").write(
        "[homeassistant]\n    password = jaEraMinha\n    instcmds = ALL\n")
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    ficha = open(os.path.join(estado, nut_bootstrap.FICHA_HOME_ASSISTANT),
                 encoding="utf-8").read().strip()
    assert ficha == "jaEraMinha"
    users = open(os.path.join(etc, "upsd.users"), encoding="utf-8").read()
    assert users.count("[homeassistant]") == 1


def test_as_senhas_das_duas_contas_sao_diferentes(tmp_path):
    etc, estado = pastas(tmp_path)
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    admin = open(os.path.join(estado, nut_bootstrap.FICHA_ADMIN), encoding="utf-8").read()
    ha = open(os.path.join(estado, nut_bootstrap.FICHA_HOME_ASSISTANT), encoding="utf-8").read()
    assert admin != ha and len(admin) >= 16 and len(ha) >= 16


def test_o_servidor_nasce_escutando_so_a_propria_maquina(tmp_path):
    """Abrir para a rede é ato do dono, não padrão de instalação."""
    etc, estado = pastas(tmp_path)
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    assert open(os.path.join(etc, "upsd.conf"), encoding="utf-8").read().strip() \
        == "LISTEN 127.0.0.1 3493"


def test_as_fichas_de_senha_nascem_fechadas(tmp_path):
    etc, estado = pastas(tmp_path)
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    modo = oct(os.stat(os.path.join(estado, nut_bootstrap.FICHA_ADMIN)).st_mode)[-3:]
    assert modo == "600"


# -- o servidor na rede, pelo interruptor da tela (0.8.0) -----------------------

def test_abrir_para_a_rede(tmp_path):
    etc, estado = pastas(tmp_path)
    nut_bootstrap.garantir_configuracao(etc=etc, state_dir=estado)
    assert nut_bootstrap.rede_aberta(etc) is False
    assert nut_bootstrap.abrir_para_a_rede(etc, True) is True
    assert nut_bootstrap.rede_aberta(etc) is True
    assert open(os.path.join(etc, "upsd.conf")).read() == "LISTEN 0.0.0.0 3493\n"
    assert nut_bootstrap.abrir_para_a_rede(etc, True) is False      # já estava
    assert nut_bootstrap.abrir_para_a_rede(etc, False) is True
    assert nut_bootstrap.rede_aberta(etc) is False
    # A permissão do arquivo (0640) sobrevive à troca.
    assert oct(os.stat(os.path.join(etc, "upsd.conf")).st_mode & 0o777) == "0o640"


def test_arquivo_do_dono_nao_e_tocado(tmp_path):
    """Quem configurou o servidor à mão continua com o arquivo dele."""
    import pytest

    etc, _estado = pastas(tmp_path)
    proprio = "# meu\nLISTEN 127.0.0.1 3493\nMAXAGE 30\n"
    with open(os.path.join(etc, "upsd.conf"), "w") as fh:
        fh.write(proprio)
    assert nut_bootstrap.rede_aberta(etc) is None
    with pytest.raises(nut_bootstrap.ConfiguracaoDoDono):
        nut_bootstrap.abrir_para_a_rede(etc, True)
    assert open(os.path.join(etc, "upsd.conf")).read() == proprio
    assert nut_bootstrap.rede_aberta(str(tmp_path / "nao-existe")) is None
