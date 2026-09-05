"""Os aparelhos que publicamos, declarados no `ups.conf` do NUT.

Por que o serviço mexe nesse arquivo: o servidor do no-break só serve aparelho
que esteja declarado ali — ele lê o `ups.conf` para saber quais soquetes procurar
(`server/conf.c`, `upsconf_add`, que monta o nome do arquivo como
`<driver>-<aparelho>`). E os dispositivos protegidos entram e saem **pela tela do
app**, a qualquer hora: se a declaração dependesse de reinstalar, um roteador
adicionado hoje só apareceria no Home Assistant depois de o dono rodar o
instalador de novo.

A promessa que o instalador faz continua valendo: *"a configuração do NUT só é
escrita se ainda não existir; quem já configurou à mão continua com a dele"*.
Por isso aqui:

- **nada é criado.** Arquivo que não existe fica não existindo — quem o cria é o
  instalador, uma vez.
- **só o miolo entre as duas marcas é reescrito.** Fora delas o arquivo é do
  dono, linha por linha, e nunca é tocado.
- **a escrita é atômica** (arquivo temporário e troca), para uma queda no meio
  não deixar o `ups.conf` pela metade — o que tiraria do ar até o leitor de
  fábrica, que é quem a proteção lê.

Nota para quem for mexer: `upsdrvctl` não sabe subir estes aparelhos, porque não
existe binário chamado `river-bridge` — quem serve os soquetes é o próprio
serviço. Isso é de propósito, e o `upsd` não se importa: ele nunca executa
driver, só procura o soquete.
"""

from __future__ import annotations

import os
import tempfile

from .nut_driver import codifica

MARCA_INICIO = "# >>> River Bridge — gerado pelo serviço, não edite até a marca de fim"
MARCA_FIM = "# <<< River Bridge — fim do trecho gerado"


class ConfMalformada(Exception):
    """As marcas do nosso trecho não fecham. Não mexemos num arquivo assim."""


def secao(aparelho: str, descricao: str) -> str:
    """Uma seção do `ups.conf`. `driver` e `port` são obrigatórios para o servidor.

    O `driver` é metade do nome do arquivo do soquete — trocar este nome é o
    servidor procurar num lugar em que ninguém escuta.

    A descrição é escapada com a MESMA função do protocolo do soquete: os dois
    lados são lidos pelo parseconf do NUT, e o texto vem de fora (é o modelo que
    o no-break declarou). Uma aspa ali deixava a linha malformada.
    """
    return (f"[{aparelho}]\n"
            f"    driver = river-bridge\n"
            f"    port = auto\n"
            f'    desc = "{codifica(descricao)}"\n')


def bloco(aparelhos: list[tuple[str, str]]) -> str:
    """O trecho inteiro, marcas incluídas."""
    corpo = "\n".join(secao(nome, desc) for nome, desc in aparelhos)
    return f"{MARCA_INICIO}\n{corpo}{MARCA_FIM}\n"


def _troca_o_bloco(texto: str, novo: str) -> str:
    """Troca o miolo entre as marcas, ou acrescenta o trecho quando não há marca.

    Marca que não fecha é RECUSA, não conserto. A primeira versão disto
    acrescentava o trecho novo no fim e deixava a marca órfã para trás — e a
    volta seguinte do laço (dois segundos depois) tomava a órfã como começo e a
    marca de fim recém-escrita como término, apagando tudo o que estava entre as
    duas: conteúdo do dono, inclusive a seção do leitor de fábrica, que é a que a
    proteção lê. Medido na 2.ª revisão fria da 0.7.0.

    Não mexer num arquivo que não sabemos ler é a única resposta honesta: os
    aparelhos deixam de ser declarados, o registro diz por quê, e o dono conserta
    o arquivo. Perder a configuração dele em silêncio não é opção.
    """
    inicios = texto.count(MARCA_INICIO)
    fins = texto.count(MARCA_FIM)
    if inicios > 1 or fins > 1:
        raise ConfMalformada(
            f"achei {inicios} marca(s) de início e {fins} de fim do trecho do River "
            "Bridge; deveria haver uma de cada. Não mexo num arquivo assim")
    if inicios != fins:
        raise ConfMalformada(
            "o trecho do River Bridge está com uma marca só (a outra foi cortada); "
            "não mexo num arquivo assim para não apagar o que é seu")
    if inicios == 0:
        separador = "" if texto.endswith("\n") or not texto else "\n"
        return f"{texto}{separador}\n{novo}"
    inicio = texto.find(MARCA_INICIO)
    fim = texto.find(MARCA_FIM, inicio)
    if fim < 0:
        raise ConfMalformada(
            "a marca de fim do trecho do River Bridge vem ANTES da de início; "
            "não mexo num arquivo assim")
    fim += len(MARCA_FIM)
    if fim < len(texto) and texto[fim] == "\n":
        fim += 1
    return texto[:inicio] + novo + texto[fim:]


def atualizar(caminho: str, aparelhos: list[tuple[str, str]]) -> bool:
    """Deixa o trecho gerado igual à lista. Devolve True quando o arquivo mudou.

    Só devolve True quando houve mudança de verdade: quem chama usa isso para
    decidir se reinicia o servidor do no-break, e reiniciar sem motivo derrubaria
    a leitura do River a cada volta do laço.
    """
    # Link simbólico é seguido, não destruído. Sem isto, `os.replace` trocava o
    # LINK por um arquivo comum: quem mantém a configuração do NUT num repositório
    # de arquivos pessoais passava a editar um arquivo que o NUT não lê mais, e a
    # edição dele sumia do sistema sem uma linha de registro (2.ª revisão fria).
    caminho = os.path.realpath(caminho)
    try:
        with open(caminho, encoding="utf-8") as arquivo:
            antes = arquivo.read()
    except OSError:
        return False                      # não existe, ou não é nosso: não criamos
    # Arquivo que o dono trancou para escrita fica trancado. A troca atômica passa
    # pela permissão da PASTA, não pela do arquivo, então sem esta conferência o
    # "não mexa" dele seria ignorado em silêncio.
    if not os.access(caminho, os.W_OK):
        raise ConfMalformada(
            f"{caminho} está sem permissão de escrita; respeito isso e não mexo nele")
    depois = _troca_o_bloco(antes, bloco(aparelhos))
    if depois == antes:
        return False
    return _gravar(caminho, depois)


def _gravar(caminho: str, depois: str) -> bool:
    """A troca atômica, com o conteúdo no disco ANTES da troca de nome."""
    pasta = os.path.dirname(caminho) or "."
    modo = os.stat(caminho).st_mode & 0o777
    descritor, temporario = tempfile.mkstemp(dir=pasta, prefix=".ups.conf.")
    try:
        with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
            arquivo.write(depois)
            arquivo.flush()
            # O conteúdo vai para o disco ANTES da troca. `os.replace` garante que
            # ninguém vê o arquivo pela metade; só o `fsync` garante que, depois de
            # uma queda de energia, o que está lá é o novo e não lixo. Num programa
            # que existe por causa de queda de energia, essa diferença é o produto.
            os.fsync(arquivo.fileno())
        os.chmod(temporario, modo)
        os.replace(temporario, caminho)
        # E o diretório também: sem isto, a própria troca de nome pode não ter
        # chegado ao disco.
        try:
            fd_pasta = os.open(pasta, os.O_RDONLY)
            try:
                os.fsync(fd_pasta)
            finally:
                os.close(fd_pasta)
        except OSError:
            pass                          # sistema de arquivos que não permite: segue
    except OSError:
        try:
            os.unlink(temporario)
        except OSError:
            pass
        raise
    return True


def remover(caminho: str) -> bool:
    """Tira o trecho inteiro — marcas incluídas — e deixa o resto intacto.

    É o que a remoção completa pede: um trecho vazio, só com as duas marcas,
    continuaria dizendo ao servidor do no-break que este arquivo é nosso.
    """
    caminho = os.path.realpath(caminho)
    try:
        with open(caminho, encoding="utf-8") as arquivo:
            antes = arquivo.read()
    except OSError:
        return False
    if MARCA_INICIO not in antes:
        return False
    if not os.access(caminho, os.W_OK):
        raise ConfMalformada(
            f"{caminho} está sem permissão de escrita; respeito isso e não mexo nele")
    depois = _troca_o_bloco(antes, "")
    if depois == antes:
        return False
    return _gravar(caminho, depois)
