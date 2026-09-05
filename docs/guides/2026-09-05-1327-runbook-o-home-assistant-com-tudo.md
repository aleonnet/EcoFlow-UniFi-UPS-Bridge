# Runbook — o Home Assistant com tudo o que o aplicativo mostra

status: superado por 2026-09-05-1930-runbook-instalar-usar-e-remover-pelo-app.md
data: 2026-09-05
supera: 2026-09-05-1100-runbook-acesso-ao-console-e-haos.md

O que mudou na 0.7.0: o serviço passou a ser **também um driver do NUT**. Antes o
Home Assistant via só o que o leitor de fábrica publicava — bateria, autonomia,
situação. Agora ele vê o mesmo que o aplicativo, os watts por tomada inclusive, e
pode mandar as ordens que o aplicativo manda.

> A seção 1 do runbook anterior (conectar o console pela tela) **continua valendo
> palavra por palavra** e não é repetida aqui.

## 1. O que o serviço passa a publicar

| Aparelho no NUT | O que é |
|---|---|
| `river-office` | o de fábrica, do `usbhid-ups`. **É ele que a proteção lê** — e o serviço recusa subir se alguém apontar a proteção para um dos nossos |
| `river-bridge` | o River inteiro, como nós o conhecemos |
| `udr7` (um por dispositivo protegido) | o aparelho protegido, publicado como carga própria |

No `river-bridge`: fabricante, modelo, número de série, situação, carga da
bateria, autonomia, tensão da bateria, temperatura, tensão de entrada e de saída,
**potência total**, **watts por tomada** (120 V, 12 V, USB-A, USB-C), potência de
entrada e frequência da linha.

Os watts por tomada só aparecem quando a porta serial do cabo responde — e somem
quando ela cala por mais de dez segundos. Número que parou no tempo, mostrado
como se fosse de agora, é pior que número nenhum.

## 2. Ligar o Home Assistant

**Antes:** o servidor do no-break escuta só na própria máquina. A máquina virtual
do Home Assistant é outra máquina na rede, então ela não alcança. A documentação
do NUT sobre essa linha
([`upsd.conf`](https://networkupstools.org/docs/man/upsd.conf.html)):

> *"This parameter will only be read at startup. You'll need to restart (rather
> than merely reload) `upsd` to apply any changes made here."*

| # | Onde | O que fazer |
|---|---|---|
| 1 | `/opt/homebrew/etc/nut/upsd.conf` | `LISTEN 127.0.0.1 3493` → `LISTEN 0.0.0.0 3493` |
| 2 | no Mac mini | reiniciar o serviço da ponte (é ele que mantém o servidor do no-break no ar, e o `upsd` **precisa reiniciar**, não recarregar) |

**Depois**, no Home Assistant (`http://haos.home.arpa/`), pela
[documentação da integração](https://www.home-assistant.io/integrations/nut/):

> *"Go to **Settings > Devices & services**"* e o botão *"**Add Integration**"*;
> escolher *"**Network UPS Tools (NUT)**"*.

- **Host:** o endereço do Mac mini na rede · **Port:** `3493`
- **Username:** `homeassistant` · **Password:** a que o instalador gerou, guardada
  em `<estado>/nut-homeassistant.token`
- Escolher o aparelho **`river-bridge`**
- **Repetir a integração** escolhendo **`udr7`**, para ter o roteador como
  aparelho próprio

A conta `homeassistant` é criada pelo instalador com permissão de mandar ordens.
Ela existe porque, medido no código do Home Assistant em 2026-09-05, sem usuário e
senha ele **nem chega a perguntar** quais comandos existem.

## 3. As ordens: onde elas aparecem de verdade

Aqui vai o que eu havia dito errado e está corrigido. Lendo o código da
integração (`homeassistant/components/nut/`, 2026-09-05):

| O que o Home Assistant cria | De onde |
|---|---|
| **botão** no painel | **só** de `outlet.<n>.load.cycle` |
| **interruptor** no painel | **só** de tomada comandável (`outlet.<n>.switchable = yes`) |
| **ação de dispositivo** | de **cada** comando da lista fechada dele |

As tomadas do River **não** são comandáveis — não há caminho medido para ligar ou
desligar uma saída dele, e dizer que há desenharia um interruptor que não
funciona. Então as nossas ordens aparecem como **ações de dispositivo**: usáveis
em automação ou script, e um script vira botão no painel.

As ordens publicadas:

| Aparelho | Ordem | O que faz |
|---|---|---|
| `river-bridge` | `load.off` | desliga o **River** (corta a energia de tudo o que está nele) |
| `udr7` | `load.off` | desliga o roteador |
| `udr7` | `shutdown.reboot` | reinicia o roteador |

Os nomes não são escolha nossa: o Home Assistant só entende comando cujo nome
está numa lista fechada. Um nome nosso seria aceito pelo NUT e **invisível** lá.

### 3.1 As travas — as mesmas da tela do aplicativo

**Uma ordem que chega pelo Home Assistant não tem menos trava que a mesma ordem
pelo aplicativo.** Com a trava fechada, a ordem **nem é oferecida**.

| Ordem | O que ela exige, no arquivo `bridge.env` |
|---|---|
| desligar o River | `RIVER_POWEROFF_ALLOWED=1` **e** nenhuma proteção armada |
| desligar/reiniciar um dispositivo | `DEVICE_CMD_ALLOWED=1` **e** conexão provada nos últimos 30 dias |

As duas mudam **só no arquivo**, com reinício do serviço — nem a tela nem o Home
Assistant as abrem. É a mesma mecânica da trava de armamento.

O **modo ensaio não vale** para uma ordem dada à mão: ele governa o que a
proteção faz sozinha numa queda. Uma ordem que você dá agora é uma ordem.

Toda ordem, cumprida ou recusada, entra na **linha do tempo do aplicativo** —
quem manda pelo Home Assistant não vê o registro do sistema.

## 4. O cabo indo e voltando sozinho

O River tem **um** cabo, e dois programas o querem. Desde a 0.7.0 isso não tem
botão:

- o **PowerManager da EcoFlow abriu** → o serviço larga o cabo e avisa na tela;
- ele **fechou, travou ou morreu** → o serviço retoma e avisa na tela.

Duas recusas, de propósito:

- **com proteção armada o cabo não é largado** — seria ficar cego para a queda
  justamente com o desligamento automático ligado. O aviso explica, e o cabo
  fica. Desligue a proteção (modo ensaio) se quiser usar o aplicativo deles.
- **o que você emprestou pela tela não é retomado sozinho** — voltou a ser sua
  escolha, e o automático não a desfaz.

Para desligar tudo isso: `RIVER_CABO_AUTOMATICO=0`.

## 5. O que o serviço escreve no `ups.conf` (e o que ele nunca toca)

O servidor do no-break só serve aparelho declarado no `ups.conf`, e os
dispositivos entram e saem **pela tela**. Então o serviço mantém ali um trecho
entre duas marcas:

```
# >>> River Bridge — gerado pelo serviço, não edite até a marca de fim
[river-bridge]
    driver = river-bridge
    port = auto
    desc = "RIVER 3 Plus (River Bridge)"
# <<< River Bridge — fim do trecho gerado
```

Fora das marcas o arquivo é seu, linha por linha. E:

- arquivo que não existe **não é criado** (quem o cria é o instalador, uma vez);
- arquivo **trancado para escrita** fica trancado;
- **link simbólico é seguido**, não substituído;
- marca que **não fecha** faz o serviço não mexer em nada e dizer por quê — em
  vez de adivinhar e apagar o que é seu.

O desinstalador tira esse trecho e deixa o resto do arquivo intacto.

## 6. Bancada — o roteiro, com o resultado esperado

| # | O que fazer | O que tem de aparecer |
|---|---|---|
| 1 | no Mac mini, `upsc -l 127.0.0.1` | `river-office`, `river-bridge` e `udr7` |
| 2 | `upsc river-bridge@127.0.0.1` | `outlet.count: 4` e `outlet.1.realpower` com o watt da tomada de 120 V |
| 3 | `upscmd -l -u homeassistant river-bridge@127.0.0.1` | `load.off` — **ou nada**, se `RIVER_POWEROFF_ALLOWED=0` (que é o padrão) |
| 4 | `upscmd -l -u homeassistant udr7@127.0.0.1` | `load.off` e `shutdown.reboot` — **ou nada**, se `DEVICE_CMD_ALLOWED=0` |
| 5 | no Home Assistant, adicionar a integração NUT em `river-bridge` | os sensores, com os watts por tomada |
| 6 | idem em `udr7` | o roteador como aparelho, com as ações |
| 7 | abrir o PowerManager da EcoFlow | o cabo sai sozinho, com o aviso na tela do River Bridge |
| 8 | fechar o PowerManager | o cabo volta sozinho, com o aviso |
| 9 | armar a proteção e abrir o PowerManager | o cabo **não** sai, e o aviso diz por quê |

**O que ainda não foi medido por mim ponta a ponta:** os passos 1 a 9 dependem de
o serviço 0.7.0 estar instalado no Mac mini, o que exige a senha do dono. Nada
aqui foi provado contra o `upsd` de verdade — o que está provado é o protocolo,
por 22 testes contra um servidor de mentira que fala o protocolo verdadeiro.
