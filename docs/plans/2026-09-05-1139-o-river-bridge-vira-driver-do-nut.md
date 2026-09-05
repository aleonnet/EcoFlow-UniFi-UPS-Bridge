# 0.7.0 — o River Bridge vira driver do NUT, e o App instala arrastando

status: aceito
data: 2026-09-05
frente: ordem do dono — *"o HAOS deve ter tudo que o App tem… também os comandos desligar
reboot etc???"*, *"quero testar um pacote dmg do river bridge, que seja experiência padrão
Apple"*, *"ao fechar o River Bridge ele libera para o App PowerManager usar… não precisa de
botão na UI"*

## 1. Por que esta frente existe

O Home Assistant fala com o servidor do no-break (`upsd`), e o `upsd` só conhece o que algum
**driver** lhe contou. O driver de fábrica (`usbhid-ups`) conta o que o perfil de no-break do
River publica — e esse perfil **não** publica os watts por tomada nem comando nenhum. Resultado
de hoje: o Home Assistant vê bateria e situação, e nada mais.

## 2. Correções de rumo (as duas, minhas)

### 2.1 O `dummy-ups` não serve — e eu o havia proposto como se servisse

Documentação do NUT, literal:

> *"Instant commands are not yet supported in Dummy Mode"*

Ele carregaria as leituras e **nunca** os comandos. Era metade da resposta apresentada como
inteira.

### 2.2 O nome do comando não é livre: o Home Assistant tem uma lista fechada

Eu havia planejado comandos chamados `device.udr7.shutdown` e `device.udr7.reboot`. Lendo o
código do Home Assistant (`homeassistant/components/nut/`, 2026-09-05) **[P-estático]**:

- `INTEGRATION_SUPPORTED_COMMANDS` em `const.py` é uma lista **fechada** de 27 nomes
  (`load.off`, `load.on`, `shutdown.reboot`, `shutdown.return`, `beeper.*`, `test.*`…);
- `__init__.py` filtra o que o servidor oferece por essa lista: `user_available_commands =
  {c for c in await data.async_list_commands() if c in valid_integration_commands}`;
- só entram fora da lista os comandos de tomada `outlet.<n>.load.on|off|cycle`.

Ou seja: um comando com nome nosso seria aceito pelo NUT e **invisível** no Home Assistant.

E mais, medido no mesmo código:

| Plataforma | O que ela cria de verdade |
|---|---|
| `button.py` | **só** `outlet.<n>.load.cycle` |
| `switch.py` | **só** `outlet.<n>.load.poweronoff`, e ainda exige `outlet.<n>.switchable = yes` |
| `device_action.py` | uma ação para **cada** comando da lista fechada |

Então "botão no painel" só existe por tomada. Todo o resto — `load.off` incluído — vira **ação
de dispositivo**, usável em automação ou script (e um script pode virar botão no painel). Dizer
"vai aparecer um botão de desligar" seria enunciado errado meu; o certo é isto.

## 3. O desenho

### 3.1 Nós passamos a ser um driver

Na arquitetura do NUT quem serve o soquete é o driver:

> *"each driver is a server on the Unix socket … and the data server `upsd` is a client which
> knows where to find such sockets, how they are named, and connects to all of them"*
> — `docs/sock-protocol.txt` do projeto NUT

O protocolo é de texto e está documentado inteiro: `SETINFO`, `DELINFO`, `ADDCMD`, `DELCMD`,
`DATAOK`/`DATASTALE`, `DUMPDONE`, `PONG`, `TRACKING <id> <código>` da nossa parte; `PING`,
`DUMPALL`, `DUMPVALUE`, `INSTCMD <cmd> [param] [TRACKING id]`, `SET`, `GETPID`, `LOGOUT` da
parte do servidor. Lido também no código: o nome do arquivo do soquete é `<driver>-<aparelho>`
(`server/conf.c`, `upsconf_add`) e o soquete nasce com `unlink` → `umask(0007)` → `bind` →
`chmod 0660` → `listen` (`drivers/dstate.c`).

### 3.2 Dois (ou mais) aparelhos publicados

| Aparelho no NUT | O que é | Comandos |
|---|---|---|
| `river-office` | o de fábrica, do `usbhid-ups`. **Continua sendo o que a proteção lê** | os do driver de fábrica |
| `river-bridge` | o River completo: bateria, autonomia, situação, tensão, potência total, **watts por tomada**, frequência, temperatura | `load.off` (desliga o River) |
| `udr7` (um por dispositivo protegido) | o aparelho protegido, publicado como carga própria | `load.off` (desliga), `shutdown.reboot` (reinicia, quando o tipo tem o comando) |

O terceiro é a resposta honesta ao "comandos desligar reboot": para o aparelho `udr7`, a carga
**é** o roteador, então `load.off` — *"Turn off the load immediately"* — diz a verdade, e é um
nome que o Home Assistant reconhece.

## 4. Decisões

| # | Decisão | Fundamento |
|---|---|---|
| D1 | Driver próprio em Python (`nut_driver.py`), só biblioteca padrão, um soquete Unix por aparelho. | Protocolo documentado; sem dependência nova. |
| D2 | **Dentro do processo do serviço**, numa linha de execução própria — não um processo à parte, como o plano anterior dizia. | As cercas dos comandos vivem no serviço (política, instâncias, travas). Um processo separado exigiria uma segunda implementação delas ou um salto de processo a mais no caminho que desliga um roteador. |
| D3 | A **proteção continua lendo `river-office`**, e o serviço **recusa subir** se a configuração apontar o leitor da política para um aparelho nosso. | Ler o próprio eco fecharia um laço: o vigia decidiria com dados que ele mesmo escreveu. |
| D4 | Nomes de variável **do dicionário do NUT** (`docs/nut-names.txt`): `ups.realpower`, `input.realpower`, `input.frequency`, `outlet.count`, `outlet.n.desc`, `outlet.n.realpower`. Tomadas com `switchable = no`. | É o que o Home Assistant mapeia. E não declaramos o que não sabemos fazer: não há caminho medido para ligar/desligar uma saída do River. |
| D5 | Comandos **só com nomes da lista fechada do Home Assistant**: `load.off` no `river-bridge`; `load.off` e `shutdown.reboot` em cada dispositivo protegido. | §2.2. |
| D6 | As cercas dos comandos são **as mesmas da tela**: `load.off` do River exige `RIVER_POWEROFF_ALLOWED` aberta e nenhuma proteção armada; mandar num dispositivo exige `DEVICE_CMD_ALLOWED` aberta **e** alcance provado. A recusa volta como `TRACKING <id> <código>` e vira linha no registro. | Um comando pelo NUT não pode ter menos cerca que o mesmo comando pelo App. |
| D6b | **Trava de arquivo nova, `DEVICE_CMD_ALLOWED`**, fechada por padrão. Fechada, a ordem nem é anunciada. *(Decidida depois da 1.ª revisão fria: mandar num roteador à mão era o único ato destrutivo do sistema sem trava.)* | Molde da casa: todo ato destrutivo tem uma trava que só o arquivo abre. |
| D6c | O soquete do driver é **0600**, mais estrito que o 0660 dos drivers do NUT. | Medido: a pasta de estado do NUT nesta máquina é 0755 com grupo `admin`; com 0660, qualquer conta administradora mandaria desligar o River sem ficha e sem rastro. |
| D7 | Conta `homeassistant` no `upsd.users` com `instcmds = ALL`; `powermanager` continua só de leitura. | Medido no código do Home Assistant: sem usuário e senha ele nem lista comandos. |
| D8 | **Empréstimo automático do cabo**: o serviço observa o processo do aplicativo da EcoFlow; apareceu, larga; sumiu, retoma. **Nunca larga com proteção armada** — avisa e mantém. Cada troca vira evento e aviso no App, sem botão novo. | Ordem do dono, com a cerca que o empréstimo manual já tem. |
| D9 | O App instala arrastando (DMG), com o serviço dentro do pacote e "Remover completamente" na tela. O instalador de linha de comando continua. | Plano `2026-09-05-1730-instalar-arrastando-o-app.md`, incorporado a esta versão. |
| D10 | Versão **0.7.0**. | Aparelhos novos no NUT, comandos novos, forma nova de instalar. |

## 5. Arquivos

**Serviço**
- `nut_driver.py` (**novo, feito**): soquete e protocolo, sem regra de negócio.
- `nut_comandos.py` (**novo, feito**): as ordens e as travas de cada uma.
- `nut_conf.py` (**novo, feito**): o trecho do `ups.conf` que declara os aparelhos
  que publicamos — entre marcas, e só ele; o resto do arquivo continua do dono.
- `nut_publicacao.py` (**novo, feito**): a leitura do ciclo → variáveis do NUT. Fonte única:
  `snap.outlets`, o mesmo que a tela mostra.
- `model.py`: `UpsSnapshot.status_raw` (**feito**) — o `ups.status` como o NUT o escreveu.
- `service.py`: publica logo depois de `_process_snapshot` e da leitura serial; atende comando
  fora do laço; recusa subir com a configuração de D3.
- `config.py`: nome do aparelho composto, empréstimo automático, processo do aplicativo.
- `api.py`: estado do empréstimo automático; rota de comando por dispositivo (o mesmo que o NUT
  executa, para o App ter o que o Home Assistant tem).

**Instalador**: seções novas no `ups.conf` e a conta `homeassistant` no `upsd.users` —
acrescentadas mesmo em máquina já instalada (o `escreve_se_faltar` só escreve arquivo ausente).

**App**: aviso do cabo indo e voltando; botão de desligar/reiniciar o dispositivo protegido;
tela "Serviço" do instalador arrastável.

**Empacotamento**: `tools/build-app.sh` (feito) e `tools/build-dmg.sh` (novo).

## 6. Cercas novas (cada uma com o defeito plantado que a reprova)

| Cena | O mutante quebra |
|---|---|
| S31 | a proteção passando a ler um aparelho publicado por nós (o vigia virando espelho) |
| S32 | desligar o River pelo NUT sem a trava de arquivo aberta |
| S33 | desligar o River pelo NUT com proteção armada |
| S34 | desligar um dispositivo pelo NUT sem alcance provado |
| S35 | publicar watt de uma leitura serial vencida |
| S36 | o empréstimo automático largando o cabo com proteção armada |
| S37 | o empréstimo automático não retomando quando o aplicativo da EcoFlow some |
| S38 | o pacote sem o Python embutido, ou com assinatura quebrada depois de rodar |

## 7. Ordem

| # | Commit | Estado |
|---|---|---|
| C1 | driver + publicação + testes | **feito** |
| C2 | o serviço publicando, e a recusa de D3 | **feito** |
| C3 | comandos com as cercas do serviço | **feito** |
| C4 | validade da leitura serial na publicação | **feito** |
| — | **1.ª revisão fria: REPROVADA, 7 bloqueadores — corrigidos** | **feito** |
| C6 | `ups.conf` mantido pelo serviço e conta `homeassistant` no instalador | **feito** |
| C5 | empréstimo automático do cabo + aviso no App | |
| C7 | tela "Serviço", DMG, versão 0.7.0 | |
| C8 | bancada do dono | |

### O que a 1.ª revisão fria achou (e onde cada conserto ficou)

| # | O defeito | Cerca |
|---|---|---|
| 1 | a resposta de um comando ia como aviso geral: chegava a quem não pediu e **não** chegava a quem tinha desligado os avisos — o River desligava e o Home Assistant não sabia | S36 |
| 2 | quebra de linha não era neutralizada: o que o console responde (modelo, firmware) podia injetar uma linha no protocolo | S37 |
| 3 | soquete 0660 numa pasta 0755 de grupo `admin`: qualquer conta administradora mandava desligar o River | S38 |
| 4 | a chave da publicação anunciada como "aplica a quente" sem aplicar | S42 |
| 5 | a cerca do vigia espelho não cobria o nome de um dispositivo protegido (`NUT_UPS=udr7`) | S40 |
| 6 | a regra cruzada não valia no PUT: a tela gravava e o serviço parava para sempre no reinício | S41 |
| 7 | o cutucão do laço de rede fora da trava podia escrever num descritor já fechado | — |

Numeração das cenas: S31–S35 são as do plano original; S36–S43 saíram desta revisão.

Revisão fria sobre o diff depois de C4 (feita) e depois de C7.

## 8. Como o Home Assistant fica configurado

- **Ajustes → Dispositivos e serviços → Adicionar integração → Network UPS Tools (NUT)**
- **Host:** o endereço do Mac mini · **Porta:** `3493`
- **Usuário:** `homeassistant` · **Senha:** a gerada na instalação, guardada em
  `<estado>/nut-homeassistant.token` (a tela vai mostrá-la)
- Escolher o aparelho **`river-bridge`** — e repetir a integração escolhendo **`udr7`** para ter
  o roteador como aparelho próprio (o nome não é `river` de propósito: esse já é usado por quem
  instalou o leitor de fábrica à mão, e o serviço recusa subir se os dois coincidirem)
- Aparecem: bateria, autonomia, situação, tensão, **potência total**, **watts por tomada**
  (120 V, 12 V, USB-A, USB-C), frequência e temperatura
- As ordens (desligar o River, desligar/reiniciar o roteador) aparecem como **ações de
  dispositivo** — em automação ou script; um script vira botão no painel. Todas passam pelas
  travas do App: o serviço recusa e explica, em vez de obedecer cego.

## 9. Verificação

- `tools/gate.sh`, `.venv/bin/pytest`, `swift test`.
- **Contra o NUT de verdade**, no Mac mini: `upsc river-bridge@127.0.0.1` listando os watts por
  tomada e `upscmd -l river-bridge@127.0.0.1` listando os comandos.
- **No Home Assistant** (`http://haos.home.arpa/`): os sensores e as ações.
- **Empréstimo automático**: abrir o aplicativo da EcoFlow e ver o cabo sair e voltar sozinho,
  com o aviso no App — e, com proteção armada, ver a recusa.
- **DMG**: arrastar, aprovar em Ajustes do Sistema, usar, e remover completamente.
