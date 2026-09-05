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

MARCA_INICIO = "# >>> River Bridge — gerado pelo serviço, não edite até a marca de fim"
MARCA_FIM = "# <<< River Bridge — fim do trecho gerado"


def secao(aparelho: str, descricao: str) -> str:
    """Uma seção do `ups.conf`. `driver` e `port` são obrigatórios para o servidor.

    O `driver` é metade do nome do arquivo do soquete — trocar este nome é o
    servidor procurar num lugar em que ninguém escuta.
    """
    return (f"[{aparelho}]\n"
            f"    driver = river-bridge\n"
            f"    port = auto\n"
            f'    desc = "{descricao}"\n')


def bloco(aparelhos: list[tuple[str, str]]) -> str:
    """O trecho inteiro, marcas incluídas."""
    corpo = "\n".join(secao(nome, desc) for nome, desc in aparelhos)
    return f"{MARCA_INICIO}\n{corpo}{MARCA_FIM}\n"


def _troca_o_bloco(texto: str, novo: str) -> str:
    inicio = texto.find(MARCA_INICIO)
    if inicio < 0:
        separador = "" if texto.endswith("\n") or not texto else "\n"
        return f"{texto}{separador}\n{novo}"
    fim = texto.find(MARCA_FIM, inicio)
    if fim < 0:
        # Marca de abertura sem a de fechamento: alguém cortou o arquivo no meio.
        # Reescrever daí para a frente apagaria o que viesse depois, então o
        # trecho novo entra no fim e o pedaço órfão fica visível para quem for ver.
        separador = "" if texto.endswith("\n") else "\n"
        return f"{texto}{separador}\n{novo}"
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
    try:
        with open(caminho, encoding="utf-8") as arquivo:
            antes = arquivo.read()
    except OSError:
        return False                      # não existe, ou não é nosso: não criamos
    depois = _troca_o_bloco(antes, bloco(aparelhos))
    if depois == antes:
        return False
    pasta = os.path.dirname(caminho) or "."
    modo = os.stat(caminho).st_mode & 0o777
    descritor, temporario = tempfile.mkstemp(dir=pasta, prefix=".ups.conf.")
    try:
        with os.fdopen(descritor, "w", encoding="utf-8") as arquivo:
            arquivo.write(depois)
        os.chmod(temporario, modo)
        os.replace(temporario, caminho)   # troca atômica: nunca um arquivo pela metade
    except OSError:
        try:
            os.unlink(temporario)
        except OSError:
            pass
        raise
    return True
