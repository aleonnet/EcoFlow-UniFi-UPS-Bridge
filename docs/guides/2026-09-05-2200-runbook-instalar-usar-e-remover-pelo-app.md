# Runbook — instalar, usar e remover pelo App (sem terminal)

status: aceito
data: 2026-09-05
supera: 2026-09-05-1930-runbook-instalar-usar-e-remover-pelo-app.md

O que mudou na 0.8.1, em uma frase: **a autorização do serviço é pedida na abertura**, sem
botão em Ajustes (o dono abriu a 0.8.0 no Mac mini como usuário e não achou o passo).

O que mudou na 0.8.0, em uma frase: **nada aqui pede terminal**. O NUT vai dentro do
pacote, o disco é assinado e notarizado, as três travas são interruptores na tela, o
Home Assistant pela rede é um interruptor, o cabo do River vai e volta sozinho, e
arrastar o programa para o Lixo remove tudo.

> A seção 1 do runbook de 2026-09-05-1100 (conectar o console pela tela) continua
> valendo palavra por palavra e não é repetida aqui.

## 1. Instalar

1. Baixe o `River-Bridge.dmg` da release e abra-o.
2. Arraste o **River Bridge** para a pasta **Aplicativos**, ao lado.
3. Abra o programa **de Aplicativos**. Ele é assinado com Developer ID e notarizado pela
   Apple: abre sem "Abrir Assim Mesmo". Aberto do disco montado ou de Downloads, ele só
   mostra "Mova o River Bridge para Aplicativos" e não registra nada: um serviço registrado
   dali apontaria para um caminho que some ao ejetar o disco.
4. O macOS pergunta, numa notificação, se o River Bridge pode rodar em segundo plano:
   clique em **Permitir** (pede a sua senha de administrador). Se a notificação passar, o
   aviso no topo da tela Energia diz o mesmo e o botão **Abrir Ajustes do Sistema** leva
   ao interruptor, em **Geral › Itens de Início de Sessão**. Não há botão para instalar:
   o programa registra o serviço sozinho ao abrir. A autorização o macOS cobra de todo
   serviço que sobe com o computador, certificado ou não; é a única senha que você digita.

Pronto. O serviço sobe, cria a configuração do NUT no diretório dele
(`/Library/Application Support/river-unifi-bridge/nut`), lança o leitor e o servidor do
no-break de dentro do pacote (`Contents/Resources/nut`), e a tela Energia passa a mostrar
o River.

**Não há `brew install` em passo nenhum.** Quem já tinha o NUT do Homebrew pode deixá-lo:
o serviço do pacote não o usa nem o toca.

## 2. As travas (Ajustes › Travas)

Cada trava libera um ato que mexe na energia de um equipamento. Fechada, o ato **não
existe**: nem na tela, nem no Home Assistant. Ligar pede confirmação; desligar é direto.

| Interruptor | O que libera | O que continua exigindo |
|---|---|---|
| Permitir armar a proteção | o desligamento **real** de um dispositivo numa queda | River registrado, conexão provada, confirmação ao armar |
| Permitir desligar o River | a ordem `load.off` no aparelho `river-bridge` (tela e Home Assistant) | nenhuma proteção armada, confirmação a cada uso |
| Permitir mandar nos dispositivos | `load.off` e `shutdown.reboot` no aparelho de cada dispositivo protegido | conexão provada nos últimos 30 dias |

Aplicam na hora, sem reinício. Fechar a trava de armamento com uma proteção **armada** é
recusado: desarme primeiro (modo ensaio na folha do dispositivo).

## 3. O Home Assistant (Ajustes › Home Assistant)

1. Ligue **Aceitar o Home Assistant pela rede** e confirme. O servidor do no-break passa a
   escutar na rede local e é reiniciado sozinho (só ele; o leitor do River não é tocado).
   O que a confirmação diz, e é verdade: o protocolo do NUT viaja em texto claro; quem
   estiver na sua rede lê o River sem senha, e quem tiver a senha do Home Assistant manda
   as ordens que as travas abertas permitirem. É uma decisão para a sua rede de casa
   (backlog B47: o conserto de raiz é usuário próprio ou TLS no servidor).
2. No Home Assistant: **Ajustes › Dispositivos e serviços › Adicionar integração › Network
   UPS Tools (NUT)**, com os quatro valores que a tela mostra (servidor, porta 3493, usuário
   `homeassistant`, senha — o botão de copiar existe para isso).
3. Escolha o aparelho **`river-bridge`** (sensores: bateria, autonomia, situação, potência
   total, **watts por tomada**, frequência, temperatura). Repita a integração escolhendo o
   aparelho do dispositivo protegido (por exemplo `udr7`) para ter as ordens dele.

As ordens aparecem como **ações de dispositivo** (automação, script; um script vira botão no
painel) — o Home Assistant só cria botão de painel para tomada comandável, e as do River não
são. O Home Assistant lê as ordens **ao carregar a integração**: depois de mudar uma trava,
recarregue a integração lá.

Se a configuração do servidor do no-break foi escrita à mão por você (não é a que o serviço
escreveu), o interruptor fica desligado e explica: ele não reescreve o que é seu.

## 4. O cabo do River e o aplicativo da EcoFlow

O River tem um cabo, e o aplicativo da EcoFlow (PowerManager) tem dois modos, gravados por
ele em `Communication mode`:

- **Remoto** (`Remote`): ele lê pelo **nosso** servidor do no-break — a cada segundo, com a
  conta `powermanager` / `river-local` que o serviço cria (medido no Mac mini em
  2026-09-06: o registro dele mostra `upsc river-office@127.0.0.1:3493` a cada 1 s). Ele não
  toca no cabo, e **os dois leem ao mesmo tempo**. Para ele mostrar os watts por tomada,
  aponte-o para o aparelho `river-bridge` em vez de `river-office` (é o nosso aparelho que
  tem `outlet.N.realpower`); a mesma conta serve.
- **Local**: ele mata o nosso leitor (`pkill -9 usbhid-ups`, lido no pacote dele) e sobe o
  NUT que ele traz. O serviço percebe a queda do leitor com o aplicativo aberto e **cede** o
  cabo (leitor e servidor param), com o aviso na linha do tempo; quando o aplicativo fecha, o
  serviço retoma sozinho. O compromisso: qualquer queda do leitor com o aplicativo aberto
  conta como pedido — inclusive o River desligado com o aplicativo aberto em Remoto; nesse caso
  o serviço cede até ele fechar e volta sozinho. Tempo até ceder, pela leitura do código, ≈ 8 s
  no pior caso (a queda é vista em 2 s; o vigia olha a cada 5 s).

Até a 0.8.4 o cabo era cedido só porque o aplicativo abriu — e em modo Remoto isso deixava
os dois sem leitura (o dono perguntou "por que não permitimos ambos?", 2026-09-06).

Com **proteção armada** o cabo não é cedido (seria ficar cego para a queda justamente com
o desligamento automático ligado); a linha do tempo diz por quê. O topo da tela Energia mostra
quem está com o cabo. Para desligar o automático: `RIVER_CABO_AUTOMATICO=0` no arquivo do
serviço (pede reinício).

## 4b. A folha do River e o Compartilhar… (0.9.0)

**Clique no anel de autonomia** da tela Energia: abre a folha com tudo o que o River publica —
modelo, série e capacidade de projeto; entrada da rede e solar/DC, cada tomada e o total; nível,
autonomia, tempo para carga completa (só aparece enquanto carrega), temperatura da bateria e do
sistema; frequência e situação. Traço é ausência de leitura, nunca zero.

**Compartilhar…**, na barra de Eventos ao lado do recorte (Hoje / 7 d / 30 d / Tudo / Datas):
monta um `.zip` com `eventos.csv`, `amostras.csv` e `diario.log` do recorte escolhido e abre
**Salvar como…** ou o painel de compartilhar do macOS (Mail, Mensagens, AirDrop…). Os CSV abrem
no Numbers e no Excel com os acentos certos. Quando o diário do serviço não estiver legível
nesta conta, o pacote vai sem ele e o rodapé do botão diz isso.

## 4c. O widget (0.10.0)

Com o River Bridge em Aplicativos e aberto ao menos uma vez, o widget aparece na galeria: botão
direito na mesa › **Editar widgets** › procure **River Bridge** (dois tamanhos). O pequeno mostra o
anel de carga, a porcentagem, a fonte e a autonomia; o médio acrescenta a entrada da rede e o
consumo. O widget lê o retrato que o app grava a cada mudança (e a cada 2 min, para a hora ser a
da última leitura); com o app aberto, atualiza sozinho em até 30 min e na hora quando a fonte
muda, a bateria fica baixa, o serviço cai ou o idioma troca. Se o retrato tem mais de 2 min,
aparece a hora em que foi lido; com mais de 30 min sem retrato novo (o app fechado, ou o sistema
adiando a recarga do widget), aparece traço e "abra o River Bridge".

## 5. Remover

**Arraste o programa para o Lixo.** O serviço percebe (em até uma volta do laço), para o
leitor, apaga a chave do console, as senhas, o histórico, a lista de dispositivos e a
configuração do NUT, se desregistra do sistema e sai. Fica só o diário em
`/Library/Logs/river-unifi-bridge.log`, de propósito: é a única pista de por que o serviço
sumiu.

Duas coisas que **não** disparam a remoção, de propósito: mover o programa para outra pasta,
e atualizar (o pacote novo no lugar do antigo, mesmo que o antigo vá para o Lixo).

**Ajustes › Serviço › Remover completamente** faz o mesmo sem jogar o programa fora.

O item na lista de Itens de Início de Sessão é do macOS: o que ele faz com o item depois do
Lixo é medido na bancada, não afirmado aqui.

## 6. Bancada — o roteiro, com o resultado esperado

| # | O que fazer | O que tem de aparecer |
|---|---|---|
| 0a | abrir o programa direto do disco montado | o aviso "Mova o River Bridge para Aplicativos" no topo, sem botão; nada registrado (`launchctl print system/com.river.unifi-bridge` não encontra) |
| 0b | arrastar para Aplicativos e abrir de lá | a notificação do macOS "River Bridge can run in the background…" e, no topo, "Autorize o River Bridge no macOS" com o botão **Abrir Ajustes do Sistema**; sem botão de instalar em lugar nenhum |
| 0c | Permitir (senha de administrador) | em até 2 s o aviso some e a tela Energia passa a mostrar o River |
| 1 | no Mac, `printf 'LIST UPS\n' \| nc 127.0.0.1 3493` | `river-office`, `river-bridge` e `udr7` |
| 2 | `printf 'LIST VAR river-bridge\n' \| nc 127.0.0.1 3493` | `outlet.count "4"` e `outlet.1.realpower` com o watt da tomada de 120 V |
| 3 | ligar "Permitir desligar o River"; `LIST CMD river-bridge` com a conta `homeassistant` | `load.off` |
| 4 | ligar "Permitir mandar nos dispositivos"; `LIST CMD udr7` | `load.off` e `shutdown.reboot` |
| 5 | ligar "Aceitar o Home Assistant pela rede"; de outra máquina, `nc <mac> 3493` | `LIST UPS` responde |
| 6 | no Home Assistant, adicionar a integração NUT em `river-bridge` e em `udr7` | sensores com os watts por tomada; o roteador como aparelho com as ações |
| 7 | abrir o PowerManager em modo **Remoto** | o cabo fica: leitor e servidor seguem, o PowerManager lê pelo nosso servidor (o registro dele: `upsc … 127.0.0.1:3493`), nenhum aviso |
| 7b | abrir o PowerManager em modo **Local** | ele mata o leitor; o serviço cede o cabo na olhada seguinte (≈ 8 s no pior caso pela leitura do código: 2 s para ver a queda + até 5 s do vigia; a bancada mede), com o aviso na linha do tempo |
| 8 | fechar o PowerManager (modo Local) | o cabo volta sozinho, com o aviso |
| 9 | armar a proteção e abrir o PowerManager em modo **Local** | o cabo **não** sai, e o aviso diz por quê (em Remoto não há aviso: ele não pediu o cabo) |
| 10 | arrastar o programa para o Lixo | nenhum processo, nenhuma pasta de estado, job desregistrado, e o interruptor "River Bridge" desligado em Ajustes do Sistema › Itens de Início de Sessão (diário: `ajudante_do_registro … unregister=ok`) |
