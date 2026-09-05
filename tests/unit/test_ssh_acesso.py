"""Preparar o acesso ao console: chave, identidade e prova de alcance.

Nenhum teste fala com máquina de verdade: o executor e o terminal são injetados.
A cerca da casa (`tests/unit/conftest.py`) já proíbe spawn, e a razão aqui é a
mesma — um teste que abrisse SSH falaria com o roteador de quem roda a suíte.

O que estes testes protegem, acima de tudo, são duas promessas do produto:
a **chave privada nunca sai** e a **senha do console é de passagem**.
"""

from __future__ import annotations

import os
import subprocess

import pytest

from river_unifi_bridge import ssh_acesso as sa

PUB = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExemploDeChavePublica river-bridge"
IMPRESSAO = "SHA256:9k3xEXEMPLOxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"


def executor(respostas):
    """Um executor falso: devolve as respostas na ordem e guarda os comandos."""
    vistos: list[list[str]] = []

    def _rodar(argv, *, tempo=None, entrada=None):
        vistos.append(list(argv))
        rc, saida = respostas.pop(0)
        return subprocess.CompletedProcess(argv, rc, saida.encode(), b"")

    _rodar.vistos = vistos
    return _rodar


def test_the_key_is_created_once_and_only_the_public_half_comes_out(tmp_path):
    """O serviço cria a chave sozinho — o dono não abre terminal nenhum."""
    caminho = str(tmp_path / "udr7_key")

    def rodar(argv, *, tempo=None, entrada=None):
        if argv[0] == sa.SSH_KEYGEN and "-t" in argv:
            open(caminho, "w").write("PRIVADA")
            open(caminho + ".pub", "w").write(PUB)
            return subprocess.CompletedProcess(argv, 0, b"", b"")
        return subprocess.CompletedProcess(argv, 0, f"256 {IMPRESSAO} x (ED25519)".encode(), b"")

    chave = sa.garantir_chave(caminho, rodar=rodar)
    assert chave.publica == PUB
    assert chave.impressao == IMPRESSAO
    assert "PRIVADA" not in chave.publica and "PRIVADA" not in chave.impressao
    assert oct(os.stat(caminho).st_mode)[-3:] == "600"


def test_an_existing_key_is_never_recreated(tmp_path):
    """Recriar seria pior que não ter: a antiga já pode estar no console."""
    caminho = str(tmp_path / "udr7_key")
    open(caminho, "w").write("PRIVADA ANTIGA")
    open(caminho + ".pub", "w").write(PUB)
    rodar = executor([(0, f"256 {IMPRESSAO} x (ED25519)")])
    sa.garantir_chave(caminho, rodar=rodar)
    assert open(caminho).read() == "PRIVADA ANTIGA"
    assert all(a[0] != sa.SSH_KEYGEN or "-t" not in a for a in rodar.vistos)


def test_a_console_that_changes_identity_is_refused_not_overwritten(tmp_path):
    """Identidade nova em host conhecido é RECUSA — é o passo de um ataque."""
    arquivo = str(tmp_path / "known_hosts")
    sa.gravar_identidade(arquivo, "192.168.1.1", ["192.168.1.1 ssh-ed25519 AAAAPRIMEIRA"])
    with pytest.raises(sa.IdentidadeDivergente, match="identidade diferente"):
        sa.gravar_identidade(arquivo, "192.168.1.1", ["192.168.1.1 ssh-ed25519 AAAAOUTRA"])
    assert "AAAAPRIMEIRA" in open(arquivo).read()   # o arquivo ficou intacto


def test_another_host_does_not_disturb_the_first(tmp_path):
    arquivo = str(tmp_path / "known_hosts")
    sa.gravar_identidade(arquivo, "192.168.1.1", ["192.168.1.1 ssh-ed25519 AAAAUM"])
    sa.gravar_identidade(arquivo, "192.168.1.2", ["192.168.1.2 ssh-ed25519 AAAADOIS"])
    texto = open(arquivo).read()
    assert "AAAAUM" in texto and "AAAADOIS" in texto


def test_the_password_never_travels_as_a_process_argument(tmp_path):
    """Argumento de processo é visível para a máquina inteira.

    A senha entra pelo terminal do `ssh`, que é o único lugar em que ela não
    aparece em `ps`.
    """
    escrito: list[bytes] = []
    lidos = [b"root@192.168.1.1's password: ", b""]

    def spawn_falso():
        leitor, escritor = os.pipe()          # o descritor precisa ser real
        os.close(escritor)
        return 4242, leitor

    def read_falso(_fd, _n):
        return lidos.pop(0) if lidos else b""

    def write_falso(_fd, dados):
        escrito.append(dados)
        return len(dados)

    argv_visto: list[list[str]] = []

    def execvp_falso(prog, argv):
        argv_visto.append(argv)
        raise SystemExit(0)

    import river_unifi_bridge.ssh_acesso as mod
    original = (mod.os.read, mod.os.write, mod.os.waitpid, mod.select.select)
    mod.os.read, mod.os.write = read_falso, write_falso
    mod.os.waitpid = lambda *_a: (4242, 0)
    mod.select.select = lambda r, w, x, t: (r, [], [])
    try:
        sa.instalar_chave_com_senha("192.168.1.1", 22, "root", "s3nh4", PUB,
                                    str(tmp_path / "kh"), spawn=spawn_falso)
    finally:
        mod.os.read, mod.os.write, mod.os.waitpid, mod.select.select = original
    assert escrito == [b"s3nh4\n"]            # foi pelo terminal, e uma vez só


def test_a_refused_password_speaks_portuguese(tmp_path):
    lidos = [b"Permission denied, please try again.", b""]

    def spawn_falso():
        leitor, escritor = os.pipe()
        os.close(escritor)
        return 4242, leitor

    import river_unifi_bridge.ssh_acesso as mod
    original = (mod.os.read, mod.os.write, mod.os.waitpid, mod.select.select)
    mod.os.read = lambda *_a: lidos.pop(0) if lidos else b""
    mod.os.write = lambda *_a: 0
    mod.os.waitpid = lambda *_a: (4242, 256)
    mod.select.select = lambda r, w, x, t: (r, [], [])
    try:
        with pytest.raises(sa.AcessoError, match="recusou a senha"):
            sa.instalar_chave_com_senha("192.168.1.1", 22, "root", "errada", PUB,
                                        str(tmp_path / "kh"), spawn=spawn_falso)
    finally:
        mod.os.read, mod.os.write, mod.os.waitpid, mod.select.select = original


def test_reach_is_proven_through_the_same_path_that_shuts_down():
    """A prova de alcance usa o MESMO `ssh` do comando que desliga.

    Provar por outro caminho (a API do console, por exemplo) não diria nada
    sobre este — e é este que corta a energia do roteador.
    """
    vistos: list[list[str]] = []

    def argv_para(comando):
        return ["ssh", "-o", "BatchMode=yes", "--", "root@192.168.1.1", comando]

    def rodar(argv, *, tempo=None, entrada=None):
        vistos.append(argv)
        resposta = {"ubnt-device-info model": "UDR7",
                    "ubnt-device-info firmware": "5.1.31"}.get(argv[-1], "/usr/bin/ubnt-systool")
        return subprocess.CompletedProcess(argv, 0, resposta.encode(), b"")

    saida = sa.testar_alcance(argv_para, {
        "presenca": "command -v ubnt-systool",
        "modelo": "ubnt-device-info model",
        "firmware": "ubnt-device-info firmware",
    }, rodar=rodar)
    assert saida == {"presenca": "/usr/bin/ubnt-systool", "modelo": "UDR7",
                     "firmware": "5.1.31"}
    assert all("BatchMode=yes" in a for a in vistos)


def test_a_command_that_fails_is_reported_as_absent_not_invented():
    def rodar(argv, *, tempo=None, entrada=None):
        return subprocess.CompletedProcess(argv, 255, b"", b"ssh: connect failed")

    saida = sa.testar_alcance(lambda c: ["ssh", c], {"modelo": "ubnt-device-info model"},
                              rodar=rodar)
    assert saida == {"modelo": None}


def test_a_public_key_with_a_quote_is_refused_before_any_command_is_built(tmp_path):
    """A conferência vem antes de montar o comando remoto, não depois."""
    with pytest.raises(sa.AcessoError, match="caractere inesperado"):
        sa.instalar_chave_com_senha("192.168.1.1", 22, "root", "x",
                                    "ssh-ed25519 AAAA'; rm -rf / #", str(tmp_path / "kh"))


def test_the_scan_keeps_every_key_type_the_console_offers():
    """Todas as identidades que o console oferece são guardadas.

    O `ssh` escolhe o tipo na negociação: um arquivo com só uma delas o faz
    recusar a conexão com "No ED25519 host key is known" — foi o que aconteceu no
    console do dono em 2026-09-04, com um arquivo que só tinha a RSA.
    """
    linhas_do_console = (
        "# 192.168.1.1:22 SSH-2.0-OpenSSH_8.4p1\n"
        "192.168.1.1 ssh-rsa AAAARSA\n"
        "192.168.1.1 ecdsa-sha2-nistp256 AAAAECDSA\n"
        "192.168.1.1 ssh-ed25519 AAAAED\n"
    )
    vistos: list[list[str]] = []

    def rodar(argv, *, tempo=None, entrada=None):
        vistos.append(list(argv))
        if argv[0] == sa.SSH_KEYSCAN:
            return subprocess.CompletedProcess(argv, 0, linhas_do_console.encode(), b"")
        return subprocess.CompletedProcess(argv, 0, f"256 {IMPRESSAO} x (ED25519)".encode(), b"")

    linhas, impressao = sa.identidade_do_host("192.168.1.1", rodar=rodar)
    assert len(linhas) == 3, "as três identidades do console têm de ser guardadas"
    assert impressao == IMPRESSAO           # a impressão mostrada é a da ed25519


def test_an_address_starting_with_a_dash_is_refused():
    """O que o `--` protegia continua protegido, de forma explícita."""
    with pytest.raises(sa.AcessoError, match="endereço de console inválido"):
        sa.identidade_do_host("-oProxyCommand=rm -rf /")


def test_identity_is_checked_on_any_port(tmp_path):
    """Porta diferente de 22 também tem identidade — e também tem recusa.

    O OpenSSH marca o host como `[endereço]:porta` fora da 22. Comparando com o
    endereço puro, a recusa de identidade divergente simplesmente NÃO EXISTIA em
    porta não padrão: o aparelho trocado era aceito em silêncio (revisão fria).
    """
    arquivo = str(tmp_path / "known_hosts")
    sa.gravar_identidade(arquivo, "192.168.1.1", ["[192.168.1.1]:2222 ssh-ed25519 AAAAUM"],
                         porta=2222)
    with pytest.raises(sa.IdentidadeDivergente):
        sa.gravar_identidade(arquivo, "192.168.1.1", ["[192.168.1.1]:2222 ssh-ed25519 AAAAOUTRA"],
                             porta=2222)
    assert "AAAAUM" in open(arquivo).read()


def test_a_missing_public_half_is_derived_not_regenerated(tmp_path):
    """Se só a metade pública sumir, ela se deriva da privada.

    Apagar as duas e gerar outra chave tiraria o acesso que já está instalado no
    console — e a prova de alcance continuaria valendo por 30 dias, mentindo
    (revisão fria da 0.6.0).
    """
    caminho = str(tmp_path / "udr7_key")
    open(caminho, "w").write("PRIVADA ORIGINAL")

    def rodar(argv, *, tempo=None, entrada=None):
        if "-y" in argv:                       # derivar a pública da privada
            return subprocess.CompletedProcess(argv, 0, b"ssh-ed25519 AAAADERIVADA", b"")
        if "-t" in argv:
            raise AssertionError("não pode gerar chave nova")
        return subprocess.CompletedProcess(argv, 0, f"256 {IMPRESSAO} x (ED25519)".encode(), b"")

    chave = sa.garantir_chave(caminho, rodar=rodar)
    assert open(caminho).read() == "PRIVADA ORIGINAL"
    assert "AAAADERIVADA" in chave.publica
