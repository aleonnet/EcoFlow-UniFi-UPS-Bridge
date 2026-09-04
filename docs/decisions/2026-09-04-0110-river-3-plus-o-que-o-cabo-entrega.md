# River 3 Plus: o que o cabo entrega, o que não entrega, e como conviver com o app da EcoFlow

status: aceito
data: 2026-09-04 (madrugada)
frente: leitura real do River 3 Plus no Mac mini (o aparelho chegou em 2026-09-03, à noite)
origem: o dono ligou o River no mini e exigiu leitura direta; depois exigiu **evidência
documental**, não afirmação. Foi essa insistência que tirou este documento do "não dá" e
levou à descoberta da porta serial. Registrado porque a lição vale mais que o achado:
`[P-estático]` de ontem não vira `[M]` de hoje.

## 1. O aparelho

`[M]` Medido no Mac mini em 2026-09-04, com o River ligado ao USB:

| Campo | Valor |
|---|---|
| Fabricante e modelo | EcoFlow · `EF-UPS-RIVER 3 Plus` |
| Número de série | `R631ZBBAWH270046` |
| Identificadores USB | vendor `0x3746`, product `0xffff` |
| Capacidade (tela da EcoFlow) | 286 Wh / 89600 mAh |
| Limite de carga e descarga (app de celular, 2026-09-04 01h22) | **0% – 100%** |

```
$ ioreg -p IOUSB -w0 -l | grep -iE '"USB Product Name"|idVendor'
    "USB Product Name" = "EF_UPS_RIVER 3 Plus"   "USB Vendor Name" = "EcoFlow"   "idVendor" = 14150
```

## 2. Três interfaces no mesmo cabo

`[M]` `ioreg -w0 -l -c IOUSBHostInterface`:

| Interface | Classe | O que é | Exclusiva? |
|---|---|---|---|
| 0 | 3 (HID) | Perfil de no-break: é o que o NUT lê | **Sim** — um leitor por vez |
| 1 | 2/2/1 (CDC ACM) | Controle da porta serial | Não |
| 2 | 10 (CDC Data) | Dados da porta serial → `/dev/cu.usbmodem102` | Não |

A exclusividade da interface 0 foi medida **nos dois sentidos**: com o serviço da EcoFlow
segurando o cabo, o nosso driver recebe `Got 0 HID objects` e nada publica; com o nosso
driver segurando, uma segunda instância recebe
`failed to claim USB device: Access denied (insufficient permissions)` e o aplicativo deles
mostra *"Connection failed — the power station doesn't support UPS communication"*.

## 3. O que o perfil de no-break entrega — e o que não entrega

`[M]` Descritor despejado com `usbhid-ups -DD` (nosso driver parado por 10 s para outro
processo conseguir abrir o aparelho): **34 caminhos**, todos em `UPS.PowerSummary.*` mais
`UPS.Flow.[4].ConfigActivePower`.

```
$ grep -coE "UPS\.(Input|Output)\." /tmp/rub-dump.log
0
```

Não existem os blocos `UPS.Input` e `UPS.Output`, que é onde o padrão de no-break por USB
guarda consumo, corrente e tensão de saída. Por isso o cabo **não entrega potência**.

`[P]` A documentação disso é o próprio driver do NUT, no GitHub:

- `drivers/ecoflow-hid.c` — a tabela deste fabricante. Busca por consumo: **zero**.
  ```
  $ grep -cE '"ups\.load"|"ups\.realpower"|"output\.|"input\.' ecoflow-hid.c
  0
  ```
  O que ela mapeia: `battery.charge` ← `UPS.PowerSummary.RemainingCapacity`;
  `battery.runtime` ← `RunTimeToEmpty`; `battery.voltage` ← `Voltage`;
  `ups.power.nominal` ← `UPS.Flow.[4].ConfigActivePower` (vale 286 — é a **capacidade em
  Wh**, que o padrão nomeia como potência).
- `drivers/mge-hid.c` — para comparação, um fabricante que publica consumo tem as linhas que
  faltam ali: `ups.load` ← `UPS.PowerSummary.PercentLoad`, `ups.realpower` ←
  `UPS.PowerConverter.Output.ActivePower`, `output.voltage` ← `UPS.PowerConverter.Output.Voltage`.

Conclusão: não é limitação do NUT nem nossa. É o que o aparelho expõe.

Fica publicado pelo cabo, e é o que a nossa ponte lê hoje: carga %, autonomia, tensão da
bateria, situação (`OL`/`OB DISCHRG`), capacidade, aviso de bateria fraca (10%), série,
modelo e fabricante.

## 4. A porta serial entrega o que falta

`[M]` Prova de conceito rodada no mini em 2026-09-04, só com biblioteca padrão do Python,
**com o nosso driver do NUT segurando a interface de no-break ao mesmo tempo**:

```
porta aberta: /dev/cu.usbmodem102
bytes recebidos: 197
  Carga total: 82.1 W        (o dono tinha 80 W ligados)
  Entrada total: 82.1 W
  Entrada AC: 82.1 W
  Entrada solar/DC: 0.0 W
  Carga na tomada AC: 82.1 W
  Carga DC / USB-A / USB-C: 0.0 W
  Capacidade de projeto: 12800 (unidade NÃO confirmada)
```

Três leituras seguidas: 76,4 W · 83,6 W · 87,4 W — varia como consumo real varia. E o NUT
continuou lendo bateria e situação durante todas elas: **as duas interfaces convivem**.

### O que aproveitamos de `greyltc/r3pcomms`

`[P]` Fonte: <https://github.com/greyltc/r3pcomms>, licença **MIT**, Python, 47 estrelas,
atualizado em 2026-08-23. Descrição do autor: *"Local communication with a River 3 Plus over
USB HID and/or CDC(ACM)"*.

O que dele usamos — **conhecimento de protocolo**, reimplementado por nós, com crédito:

| O que | Detalhe |
|---|---|
| Enquadramento | preâmbulo `0x03AA`, 2 bytes de comprimento, corpo, 2 bytes de verificação |
| Verificação | CRC-16/ARC (polinômio refletido `0xA001`), calculada sobre o quadro inteiro |
| Sequência | 4 bytes a partir do deslocamento 6, incrementada a cada pedido |
| Ofuscação | XOR de cada byte após o deslocamento 18 com o byte baixo da sequência |
| Pedido de métricas | `de2d00000000ffff220201016602` |
| Pedido do número de série | `f40d00000000ffff2202010166031600` |
| Segmentação | `<tipo:u16><tam:u8><dados>`, a partir do deslocamento 22 da resposta |
| Tipos usados | 3 capacidade · 4 temperaturas · 7 carga total · 8 entrada total · 9 entrada AC · 12 entrada solar/DC · 13 e 15 frequência · 14 carga AC · 16 carga DC · 17 USB-A · 18 USB-C · 22 série · 23 tempo restante |

Sinais 14, 16, 17 e 18 vêm negativos e são invertidos, como o autor faz.

Também está registrada, no NUT, a discussão oficial do suporte a este modelo:
<https://github.com/networkupstools/nut/issues/2735>.

**Obrigação nossa:** ao reimplementar, manter o aviso de licença MIT e o crédito ao autor no
cabeçalho do módulo, e nunca apresentar o protocolo como descoberta própria.

## 5. O aplicativo da EcoFlow: o que ele faz na máquina

`[M]` Lido dentro do pacote em `/Applications/PowerManager.app`:

- Ao abrir, pede a senha de administrador por `osascript`
  (`do shell script "sudo %1" with administrator privileges`) e executa dois scripts próprios.
- `mac/kill_processes.sh` é literalmente `pkill -9 usbhid-ups` seguido de `pkill -9 upsd`:
  **ele mata qualquer leitor de no-break da máquina**, inclusive o nosso, pelo nome do processo.
- `mac/start_upsdrvctl.sh` sobe o driver deles.
- O serviço de fundo é um daemon do sistema (`/Library/LaunchDaemons/com.ecoflow.PowerManagerService.plist`),
  dono `root`, e só para com `sudo`.
- O desligamento do computador, na configuração deles, é `/sbin/shutdown -h +0` (`upsmon.conf`).

Consequência de desenho: enquanto o nosso leitor se chamar `usbhid-ups`, ele é alvo por
acidente. Dar **nome próprio** ao nosso processo é item da frente seguinte.

## 6. Conviver sem travar

Três modos, todos medidos:

| Modo | Quem tem o cabo | Como |
|---|---|---|
| Normal | nós | padrão |
| Comparação | aplicativo da EcoFlow | `tools/river-cabo.sh liberar` — e a nossa leitura de potência **continua**, pela serial |
| Convivência | nós | o aplicativo deles em **Remote**, lendo do nosso servidor NUT |

`[M]` A convivência foi testada com a conversa completa do protocolo NUT:

```
USERNAME powermanager   → OK
PASSWORD river-local    → OK
LOGIN river-office      → OK
GET VAR river-office battery.charge → VAR river-office battery.charge "100"
```

E o registro do nosso servidor confirma: `User powermanager@127.0.0.1 logged into UPS [river-office]`.

A conta é `upsmon secondary` **de propósito**: acompanha e recebe aviso de desligamento, e
**não** pode mandar o River desligar. Quem desliga é a nossa ponte, com as travas dela.

Valores para a tela "Communication mode → Remote" deles: aparelho `river-office`, endereço
`127.0.0.1`, porta `3493`, usuário `powermanager`, senha `river-local`.

## 7. O que o River aceita RECEBER

`[M]` `upsrw` e `upscmd -l` no aparelho:

| Item | Situação |
|---|---|
| `battery.charge.low` (o "Low battery reminder" deles) | **gravável**, hoje em 0 |
| Limite de descarga (5%) | não gravável por aqui; a própria tela deles manda ajustar no app de celular |
| `driver.killpower` (desligar o River) | existe, **trancado** por `driver.flag.allow_killpower` |

O desligamento do próprio River corta a energia dos equipamentos: só entra com trava
explícita e confirmação, no mesmo rigor da proteção do console.

## 8. Decisões

| # | Decisão | Motivo |
|---|---|---|
| D1 | Potência, entrada e tomadas vêm da **porta serial**; bateria, autonomia e situação continuam vindo do perfil de no-break | é o único caminho que entrega os dois conjuntos, e eles convivem |
| D2 | **Não implementar estimativa** de potência por capacidade ÷ autonomia | número calculado que discorda de número medido só confunde; a conta fica registrada na seção 9 caso um aparelho sem serial precise dela |
| D3 | O nosso app terá **tudo o que o deles tem** mais o que só nós temos | ordem do dono, 2026-09-04 |
| D4 | O instalador passa a instalar a leitura do River como **serviço do sistema**, com nome próprio | agentes de usuário param quando ninguém está logado, e o nome genérico é morto pelo script deles |
| D5 | Botão no app para **liberar e retomar o cabo**, com a tela dizendo quem está com ele | a exclusividade é física; esconder isso seria mentir |
| D6 | Reimplementar o protocolo serial com crédito e aviso MIT no módulo | licença e honestidade |

## 9. A conta que NÃO vamos usar (registrada por completude)

Com capacidade e autonomia dá para estimar a potência tirada da bateria:

```
potência (W) = 286 Wh × (carga% ÷ 100) ÷ (autonomia_s ÷ 3600)
```

`[M]` Com 80 W ligados, medi 99% e 11220 s → 90,8 W; e 97% e 11040 s → 90,5 W. Cerca de 13%
acima dos 80 W da tomada, diferença compatível com a perda do inversor. Só vale **na
bateria**: na tomada a autonomia publicada é projeção ociosa (42 h).

## 9b. Correção de um número meu

Na primeira versão deste documento eu registrei o limite de descarga do River como **5%**,
lendo da tela do Power Manager no Mac. Errado: ali os 5% eram o **lembrete** de bateria baixa,
e "Discharge limit" era o rótulo da ponta esquerda da régua. A tela de configurações do
aplicativo de celular mostra o valor real, medido em 2026-09-04 01h22: **0% a 100%**.

Consequência para a proteção: a bateria vai até o fim, e quem escolhe a hora de desligar os
equipamentos somos nós. Não existe piso de 5% para respeitar.

## 10. Em aberto

- Unidade do campo de capacidade da serial (`12800`): não confirmada, **não vai para a tela**.
- **BLE e nuvem**: em 2026-09-04, 01h09, o dono pareou o River pelo Bluetooth no aplicativo
  de celular e o levou até "Configurações de rede enviadas → conectando à rede → vinculado à
  conta". Isso abre um TERCEIRO caminho de leitura, pela nuvem da EcoFlow, e **muda o veredito
  de 2026-09-02** (`decisions/2026-09-02-2124-wifi-do-river-fechado.md`), que fechou o Wi-Fi
  por não existir caminho local: o caminho continua não sendo local, mas agora existe e está
  ligado. Vira frente própria, com duas trilhas: a API de desenvolvedor da EcoFlow (nuvem, boa
  para visibilidade, **inútil para proteção** porque depende da internet) e o BLE local
  (`nielsole/ecoflow-bt-reverse-engineering` como ponto de partida `[S]`).
  As telas de escolha de estilo do aplicativo de celular mostram números (179 W, 61 W, 20 W,
  74%) que são **ilustração da tela, não leitura** — não entram como medição.
- Nome próprio para o nosso processo leitor, para deixar de ser alvo do `pkill` deles.

## 11. Confirmação

Todas as linhas `[M]` deste documento vieram de comandos rodados no Mac mini em 2026-09-04,
entre 00h e 01h, com o River conectado: `ioreg`, `usbhid-ups -DD`, `upsc`, `upsrw`,
`upscmd -l`, a prova de conceito da serial em Python e a sessão manual do protocolo NUT. As
linhas `[P]` são arquivos do repositório do NUT e do `r3pcomms`, baixados no ato e citados
com o comando de busca ao lado.
