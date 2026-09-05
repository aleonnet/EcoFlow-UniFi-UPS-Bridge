# Changelog

Formato de [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). A partir da `v0.2.0`
cada versão é uma tag `vX.Y.Z` que amarra as seis declarações de versão (`pyproject.toml`,
`src/river_unifi_bridge/__init__.py`, `scripts/install.sh`, `scripts/uninstall.sh`,
`tools/build-app.sh`, `river-bridge-install.sh`) e a seção correspondente aqui — conferido por
`tools/release.sh --check`, que é quem produz a release. A `0.1.0` não teve tag. O que veio
depois da última versão está em `[Unreleased]`.

## [Unreleased]

## [0.7.0] — 2026-09-05

A ponte passa a ser **também um driver do NUT**. É o que faz o Home Assistant
receber o mesmo que o aplicativo mostra — inclusive os watts por tomada, que o
perfil de no-break do River não publica, e as ordens, que o leitor de fábrica não
oferece.

### Adicionado
- **Um aparelho `river-bridge` no NUT** com tudo o que a ponte sabe do River:
  bateria, autonomia, situação, tensão, potência total, **watts por tomada**
  (120 V, 12 V, USB-A, USB-C), frequência e temperatura. Os nomes são os do
  dicionário oficial do NUT, que é o que o Home Assistant sabe ler.
- **Um aparelho por dispositivo protegido**, com as ordens de desligar e (no
  console UniFi) reiniciar. Só entra no NUT o dispositivo cujo alcance o serviço
  já provou: uma ordem que não chega a lugar nenhum é pior que ordem nenhuma.
- **`DEVICE_CMD_ALLOWED`** — trava de arquivo para as ordens dadas à mão num
  dispositivo protegido, fechada por padrão. Terceira trava da casa, pelo mesmo
  motivo das outras duas. Fechada, a ordem nem é oferecida.
- **Conta `homeassistant`** no servidor do no-break, com senha própria numa ficha
  0600 e permissão de mandar ordens (sem ela, a integração do Home Assistant nem
  chega a perguntar quais comandos existem).
- O serviço mantém no `ups.conf` do NUT um **trecho entre marcas** com os
  aparelhos que publica. Dispositivo que entra ou sai pela tela aparece e some
  sem ninguém reinstalar; o resto do arquivo continua sendo do dono, linha por
  linha.

### Corrigido
- O que a leitura da porta serial já garantia na tela passa a valer na
  publicação: watt vencido **sai** do NUT em vez de congelar.
- **O gráfico parou de apagar e voltar a cada dois segundos.** O serviço
  publicava DUAS leituras por ciclo — a proteção decidia e publicava sem os
  watts, e a porta serial completava e publicava de novo. Entre as duas, a tela
  via um aparelho "sem potência". Agora é uma publicação por volta, e ela é a
  leitura inteira; o histórico também deixa de levar duas amostras por ciclo.
- **A janela abre junto com o programa.** Antes só aparecia o ícone no Dock, e a
  tela exigia um clique que ninguém adivinha.
- **A tela do serviço volta a perguntar o estado.** Ela perguntava uma vez, na
  abertura: quem ligasse a chave nos Ajustes do Sistema voltava e continuava
  lendo "falta aprovar".
- **O aviso do topo pergunta ao sistema**, não à presença de um arquivo. Uma
  ficha órfã de instalação removida o fazia dizer "sem comunicação com o
  serviço" quando a verdade era "o serviço não está instalado".
- **Erro que não impediu o registro deixa de virar queixa** — a tela mostrava
  "falta aprovar" e "operação não permitida" ao mesmo tempo.
- **O empréstimo automático do cabo nasce desligado, e a detecção foi
  corrigida.** Ela procurava o caminho do pacote do fabricante na linha de
  comando de qualquer processo — o que não distingue "o dono abriu o aplicativo"
  de "um ajudante de fundo dele está rodando". E o benefício não está
  demonstrado: com o aplicativo deles aberto, o serviço continuou lendo o River
  normalmente.
- **O aviso não anuncia mais a marca do fabricante no título**, e deixou de
  misturar duas línguas. O detalhe passa a ser o motivo REAL de quem pausou.

### Avisos que faltavam
- Na tela Serviço: **arrastar o programa para o Lixo NÃO remove o serviço** —
  ele continua registrado e rodando, e a chave do console e as senhas ficam no
  disco. Medido na bancada: foi exatamente o que aconteceu.
- Um **LEIA-ME dentro do disco**, ao lado do programa, com as cinco coisas que
  não se adivinham: arrastar, a primeira abertura pelos Ajustes do Sistema, o
  `brew install nut`, instalar o serviço e como remover de verdade.

### Segurança
- O soquete do driver é **0600**, mais estrito que o 0660 dos drivers do NUT — a
  pasta em que ele vive é 0755 com grupo `admin`, e 0660 ali deixaria qualquer
  conta administradora mandar o River desligar sem ficha e sem rastro.
- Quebra de linha e caracteres de controle são neutralizados no que publicamos:
  o modelo e o firmware saem do que o **console** respondeu, e uma quebra ali
  seria uma linha injetada no protocolo.
- A proteção **não pode ler** um aparelho publicado por nós — nem o do River nem
  o de um dispositivo. A regra vale na partida e também no que a tela grava.

## [0.6.0] — 2026-09-05

O App passa a preparar o acesso ao console sozinho, e a proteção só arma depois de
**provar** que alcança o aparelho. Provando isso no console de verdade, dois defeitos
apareceram — e eram os que tornavam o desligamento impossível na prática.

### Adicionado
- **"Conectar" e "Testar conexão" na folha do dispositivo.** O serviço cria a chave, confere a
  identidade do aparelho (com a impressão digital na tela) e instala a chave usando a senha do
  console **uma vez**. Nada de terminal, e a senha não é gravada, não é registrada e não volta
  na resposta.
- **A tela diz o que o console respondeu**: modelo e versão do firmware, lidos dele.
- **Aviso de garantia** ao configurar um aparelho por SSH, com o texto do próprio fabricante.

- **Número de série do River num toque.** O aparelho diz o próprio número; agora a tela oferece
  "Usar este" em vez de pedir dezesseis caracteres digitados à mão. O registro continua sendo um
  ato do dono — é ele que a proteção exige para armar.
- **As dicas de Ajustes funcionam no toque.** Cada linha tem um ⓘ que abre a explicação num
  balão; passar o ponteiro continua valendo no Mac.

### Corrigido
- **A chave instalada sobrevive a um salvamento.** Ela entrava na configuração só na partida do
  serviço: qualquer salvamento (ou mudança do núcleo) a descartava, e a proteção armava para
  ficar em "configuração incompleta" — numa queda de energia, nada seria enviado.
- **Mexer no acesso ao console com a proteção armada é recusado.** Trocar a chave ou apagar a
  identidade ali deixava o dispositivo armado e sem como falar com o aparelho, com a tela
  continuando a dizer "armada".
- **A recusa de identidade divergente passa a valer em qualquer porta.** Fora da 22 o OpenSSH
  marca o host de outra forma, e a comparação não pegava — o aparelho trocado era aceito calado.
- **Console inalcançável não é mais reportado como senha errada.** O motivo vinha de procurar a
  palavra "senha" no texto do erro; agora vem do tipo da falha.
- **O selo do cabo, na tela de saúde, passa a medir.** Era uma constante: dizia "não observável"
  acontecesse o que acontecesse, inclusive com o simulador no ar.
- **O desligamento do console nunca teria funcionado em macOS.** O `ssh` divide o valor de
  `UserKnownHostsFile` por espaços, e o diretório de estado é `~/Library/Application
  Support/…`; sem aspas ele procurava dois arquivos inexistentes e recusava a conexão. Medido
  contra o console real.
- **A identidade do console podia ser gravada pela metade.** A varredura de identidades roda um
  tipo de chave por vez, em paralelo e com tempo limite, e **pode voltar incompleta** (medido: a
  mesma máquina devolveu uma linha numa rodada e três noutra). Um arquivo com só a chave RSA faz
  o `ssh` recusar a conexão, porque ele negocia ed25519. Agora todas as linhas que a varredura
  devolve são gravadas, e uma varredura incompleta falha na cara — com o que o `ssh` respondeu
  na mensagem — em vez de virar recusa silenciosa depois.

### Mudado
- **Armar exige prova de alcance recente (30 dias).** Antes, a proteção podia armar sem nunca
  ter falado com o console — o primeiro contato real seria o comando de desligar, numa queda de
  energia. É por isso que os dois defeitos acima sobreviveram meses sem aparecer.
- A chave que o serviço usa é **derivada do dispositivo**, não um campo digitado: o padrão de
  caminho recusa espaços, e o diretório de estado do macOS tem espaços.

## [0.5.1] — 2026-09-04

Três defeitos que só a máquina do dono mostrou, no primeiro uso da 0.5.0.

### Corrigido
- **O serviço vazava um arquivo aberto a cada leitura gravada e morria em minutos.**
  `with sqlite3.connect(...)` **não fecha** a conexão — só encerra a transação; está na
  documentação do Python, e eu tinha escrito o contrário no comentário do código. Medido no
  Mac mini: 78 cópias da base abertas, subindo cerca de duas por segundo, contra o teto de
  256 do sistema — a tela acusava "arquivos demais abertos" no servidor do no-break.
- **O consumo por tomada aparecia e sumia da tela.** Um ciclo em que a porta serial não
  respondia apagava os quatro valores. Agora a última leitura boa vale por alguns segundos;
  passado o prazo, a tela mostra ausência — nunca número velho.
- **Ajustes ganhou dicas de contexto** (passe o ponteiro): cada linha explica, em uma frase, o
  que aquele número faz — inclusive a diferença entre o alerta de bateria baixa DESTE app e o
  aviso gravado dentro do River.

## [0.5.0] — 2026-09-04

O serviço deixa de só **ler** o River e passa a **mandar** nele, com cerca dupla em cada ato
destrutivo, e deixa de depender da senha do dono para o dia a dia: quem cuida do leitor do
no-break agora é o próprio serviço.

### Adicionado
- **O serviço cuida do leitor do River.** O driver e o servidor do no-break passam a ser
  processos filhos do nosso serviço, com nome próprio. Resolve quatro coisas de uma vez:
  sobem no reinício mesmo sem ninguém logado (o Mac mini ficou uma hora sem vigia em
  2026-09-04 por causa disso), param e voltam **sem senha**, somem dos itens de segundo plano,
  e escapam do `pkill -9 usbhid-ups` que o aplicativo da EcoFlow roda com poder de
  administrador ao abrir. Liga e desliga pela chave `RIVER_NUT_MANAGED`, com reinício
  do serviço.
- **Botão para entregar o River ao aplicativo da EcoFlow, e para tomá-lo de volta.** A
  interface de no-break do aparelho aceita um leitor por vez — a tela diz quem está com ele,
  em vez de esconder a disputa. Rotas `GET`/`POST /v1/river/cabo`.
- **Botão de desligar o próprio River**, com trava dupla: a chave `RIVER_POWEROFF_ALLOWED`,
  que só muda no arquivo do serviço, e a confirmação na tela nomeando o que será cortado.
  Rota `POST /v1/river/desligar`.
- **Aviso de bateria fraca do aparelho, editável na tela** — o "Low battery reminder" do
  aplicativo deles. Gravado no próprio River e conferido lendo de volta. Rota
  `PUT /v1/river/aparelho`.
- **Conta própria para mandar no aparelho.** O instalador cria a conta no servidor do no-break
  e guarda a senha num arquivo 0600 do diretório de estado — fora do arquivo de configuração,
  que a tela lê inteiro. A conta de leitura do aplicativo da EcoFlow continua existindo e
  continua sem poder mandar o River desligar.

### Removido
- **O alerta que comparava o aviso de bateria fraca do aparelho com o corte físico
  configurado.** Os dois números não são a mesma coisa — o aparelho não publica o corte
  físico —, e agora que o aviso é editável pela nossa tela o alerta viraria acusação
  falsa a cada mudança.

### Corrigido
- **Leitor que não sobe não vira mais tempestade de processos.** Com o cabo solto, o serviço
  lançava dois processos a cada volta do laço, sem teto. Agora cada falha seguida espera mais,
  até um minuto, e a tentativa continua acontecendo.
- **Serviço que sai leva o leitor junto.** O pedido de encerramento do sistema virava morte
  súbita, e os dois processos do no-break ficavam órfãos **com o cabo**: o serviço seguinte não
  conseguia abrir o aparelho.
- **A trava do próprio driver volta a fechar mesmo quando o desligamento falha.** Sem isso, uma
  tentativa malsucedida deixava o River desligável por qualquer programa desta máquina, com as
  duas travas do dono fechadas e ele sem saber.
- **Gravação no aparelho que não pode ser conferida falha fechada.** Antes, um leitor que
  caísse entre a escrita e a leitura de volta deixava a tela dizer "salvo" com valor nenhum.
- **Armar deixou de ser possível com o cabo emprestado.** A leitura antiga ainda parece boa por
  alguns segundos depois do empréstimo — armar ali é armar às cegas. Desarmar continua sempre
  aceito.
- **O aviso de bateria fraca só vai ao aparelho quando o dono manda.** Cada passo do arrastar
  virava uma gravação no River.
- **Cada trava é chamada pelo próprio nome** na recusa: a de armamento e a do desligamento do
  River deixam de ser a mesma frase, que mandava a pessoa procurar a linha errada.
- **A desinstalação voltou a terminar limpa.** Ela recusava remover a ficha da senha do
  aparelho (que mora fora do prefixo), saía com falha e deixava a senha no disco.
- **Instalação em máquina nova**: o diretório de estado passa a nascer com o dono certo.
  Criado pelo administrador, o serviço não conseguia escrever nada nele e não subia.
- **Nenhuma ação do River trava mais a tela.** Emprestar o cabo e desligar o aparelho
  esperam segundos por processos e soquetes; isso corria no mesmo laço que atende o app,
  que ficava mudo justamente enquanto o dono acompanha o ato.
- **Se a trava de desligamento do leitor não fechar, isso vira aviso na linha do tempo**,
  não só uma linha de registro que ninguém lê.
- **A leitura do River deixa de ficar sem dono na atualização**: o instalador reconhece e
  encerra também os leitores com o nome próprio novo, não só os de fábrica.

## [0.4.1] — 2026-09-04

Consertos que a segunda rodada da revisão fria do diff encontrou, todos na mesma noite da
0.4.0. Quem instalar a 0.4.0 deve pular direto para esta.

### Corrigido
- **Desarmar deixou de poder ser recusado por falha de disco também no segundo caminho.** O
  pedido passa por duas gravações — o arquivo do serviço e a lista de dispositivos — e só a
  primeira estava protegida. Com o disco cheio, a proteção desarmava por dentro e a resposta
  era um erro cru em inglês, com a tela continuando a mostrar o dispositivo armado.
- **A leitura de potência não fala mais com o aparelho errado.** A série passou a ser cerca, e
  não preferência: só é aceito o quadro cuja série é a mesma que o no-break informou. Sem série
  para comparar, a leitura é recusada em vez de adivinhar. Porta escolhida à mão na
  configuração continua valendo, porque aí a escolha é do dono.
- **A leitura de potência saiu da frente da decisão de desligamento.** Ela acontecia antes da
  proteção decidir e podia atrasar o ciclo em segundos por porta muda. Agora a proteção decide
  primeiro, o consumo entra depois, a espera por porta caiu para 0,6 s e uma máquina sem River
  deixa de varrer todas as portas a cada ciclo.

## [0.4.0] — 2026-09-04

Vinte defeitos que a leitura integral do código achou, mais a leitura real do River 3 Plus.

### Corrigido
- Os dispositivos protegidos aparecem **desde que o serviço sobe** e continuam aparecendo se o
  no-break calar: a lista é configuração, não telemetria. Antes o instalador dizia "nenhum
  dispositivo protegido" e o app nascia com o interruptor desligado.
- Antes da primeira leitura, uma proteção ligada e sem ensaio aparece como "armada, alcance não
  verificado" — nunca mais como "modo ensaio", que era mentira no estado mais sensível.
- A linha do tempo volta a receber eventos **depois do centésimo**: a entrega passou a se
  orientar pela sequência do evento, não pela posição na fila.
- "Bateria baixa" só é avisado com o aparelho **na bateria**, e rearma por histerese, sem
  repetir em rajada.
- Um campo em branco na tela de ajustes é **recusado com explicação**; antes ele derrubava o
  serviço no ciclo seguinte.
- Um dispositivo com defeito **não mata mais o vigia** nem cega os outros: a falha vira registro
  e um campo próprio na saúde, separado do erro do no-break.
- "Manter histórico: N dias" passou a ser verdade: a limpeza roda no boot e a cada hora.
- O número de tentativas de desligamento é **exatamente** o que a tela mostra (3 = 3 tentativas;
  0 = nenhuma, e o modo ensaio continua avisando o que faria).
- Com o serviço fora do ar, a tela mostra "—" em vez de repetir a última leitura como se fosse
  de agora.
- **Limpar eventos limpa mesmo**: banco, memória do serviço e lista da tela.
- Ajustes deixa de mostrar valores de fábrica como se fossem do serviço: sem resposta, avisa e
  desabilita os controles.
- O gráfico distingue "não alcancei o serviço" de "ainda não coletei" e de "este aparelho não
  informa esse dado".
- Exceções previstas ganharam saída: reiniciar sem laço recusa com explicação, falha ao gravar
  a configuração vira erro claro sem aplicar nada, e nenhum `except` fica mudo. Desarmar a
  proteção nunca é recusado, nem por falha de disco.
- A tela não fala mais em nome de chave, arquivo, código de resposta nem tipo cru de evento.
- **Desarmar nunca é recusado**, nem com o disco cheio: um pedido que só desarma é aplicado de
  todo jeito, com aviso. Qualquer outra mudança continua sendo recusada sem aplicar nada.
- Duas linhas de evento do mesmo tipo, no mesmo segundo, de dispositivos diferentes, deixam de
  colidir e sumir da lista.
- Com o serviço vivo e o no-break mudo, os números somem da tela em vez de parecerem atuais.

### Novo
- **Consumo por tomada, lido direto do River.** O perfil de no-break não publica potência; a
  porta serial do mesmo cabo publica, e as duas convivem. O serviço passa a mostrar quanto entra
  da rede e quanto sai por cada tomada (120 V, 12 V, USB-A, USB-C), com a porta descoberta
  sozinha e aceita só quando a série do aparelho bate. Protocolo reimplementado a partir do
  projeto público `greyltc/r3pcomms` (MIT), creditado no cabeçalho do módulo.
- O catálogo de tipos passa a publicar o vocabulário fechado de estados da proteção, e o app
  confere que sabe desenhar todos.

### Removido
- Quatro opções de configuração que não faziam nada (`UNIFI_HOST`, `UNIFI_VERIFY_TLS`,
  `EMULATE_MODEL`, `READ_ONLY`) — a allowlist foi de 33 para 29 chaves; um `.env` com elas só
  gera aviso.
- Código sem consumidor no serviço e no app, com os testes que só existiam para ele.

### Medido com o aparelho real
- O River 3 Plus publica carga, autonomia, tensão, situação e capacidade pelo cabo, e **não
  publica potência nem consumo**; a tela diz isso em vez de fingir histórico vazio
  (`docs/decisions/2026-09-04-0110-river-3-plus-o-que-o-cabo-entrega.md`).

## [0.3.4] — 2026-09-03

### App
- Rodapé de Ajustes mostra as versões do app e do serviço (`GET /v1/version`), com aviso quando
  divergem — o painel "Sobre" do macOS só mostraria a do app.

## [0.3.3] — 2026-09-03

### App — responsividade das folhas na largura mínima (dono: "inadmissível")
- A linha do **comando de desligamento** do host SSH tinha sido escrita à mão, fora do molde
  das linhas de Ajustes: a 414 pontos o rótulo hifenizava ("Shut-down com-mand") e o cartão
  saía vazio. Entra `pickerRow` no molde, com variante estreita (rótulo e legenda em cima,
  seletor na largura inteira), e a folha usa só o molde.
- A **linha de armamento** empilha na largura mínima: o botão "Desligar modo ensaio…" ganha a
  linha de baixo em vez de quebrar em duas (HIG: rótulo de botão nunca quebra).
- A folha de edição do host SSH **abria rolada até o seletor** (o valor da instância chega
  depois do primeiro desenho); a folha passa a ancorar no topo e o seletor sempre contém a
  seleção atual.
- O **nome sugerido** de um dispositivo novo segue o idioma do app ("SSH server" em inglês,
  "Servidor SSH" em português).
- **A folha nunca passa da janela.** A largura da janela-mãe era medida na própria rolagem de
  Ajustes, que a 414 pontos media 563 (as linhas largas do primeiro desenho a empurravam para
  fora da janela); a folha "cabia" em 523 e vazava. Agora a medida vem do espaço oferecido
  (GeometryReader), e a folha tem tamanho fixo: o espaço do painel menos a margem, entre o mínimo e o
  máximo da folha — o macOS ignora a
  largura ideal de uma folha flexível e a dimensiona pelo conteúdo (470 pontos, medido em janelas
  de 414 e de 600). Cada linha decide empilhar ou não pela largura em que a folha foi de fato
  desenhada. O corte entre empilhar e lado a lado sobe de 420 para 560 pontos de largura da
  folha: a 420 o rótulo da chave privada ainda quebrava em duas linhas (captura).
- A folha aberta por linha de comando de desenvolvimento (`--seam-folha novo:…`) abre antes
  das chamadas ao serviço, para a captura não fotografar a tela sem ela.
- Verificado por captura lida contra o defeito e por geometria de janela (folha contida na
  janela-mãe, medida pela moldura da janela: 374×380 em 414×512, 560×556 em 600×700, 600×640 em
  1000×880): folhas de edição
  e de novo dispositivo dos dois tipos, lista de tipos, em português e inglês.

### Instalador de uma linha
- Após baixar o código, a linha dizia "código já estava baixado" quando o que já existia era a
  pasta extraída deste mesmo download; agora diz isso.

## [0.3.2] — 2026-09-03

### Instalação — revisão inteira dos dois instaladores (dono: "trate TUDO")
- **Toda checagem que pode recusar roda antes da primeira mutação** (`scripts/install.sh`):
  macOS, sudo, Homebrew, dispositivo armado, **quem está na porta da API**, versão do NUT. Recusar
  no meio deixava metade da atualização em disco (medido em 2026-09-03).
- **Uma cópia do nosso serviço rodando fora do launchd** (resto de sessão de desenvolvimento) é
  **encerrada pelo próprio instalador**, que segue e prova o serviço instalado na porta; antes,
  o serviço novo morria de porta ocupada e a pessoa era mandada matar processos na mão.
- **Um programa alheio na porta** é recusado (código 3) com o nome do programa e a saída
  (fechar, ou trocar `UI_API_PORT` no `bridge.env`) — sem PID nem linha de comando na tela.
- **Duas vozes na saída**: as linhas `│` são para a pessoa (o que aconteceu, o que foi feito, o
  que falta); as linhas `#` são o registro técnico. O one-liner mostra à pessoa a frase da
  falha e onde estão os detalhes, em vez da cauda crua do log. `manifesto`, `COMM_LOST`, `PID`,
  `kickstart`, `(exit N)` saem da tela.
- **Ao final de qualquer falha**: *Feito até aqui* (o que ficou), *Faltou* (as fases não
  concluídas) e *O que fazer agora* (uma frase). A verificação final fecha: serviço que não
  sobe ou não responde é falha (código 1), não aviso com ✔.
- **Prova com launchd real, sem root**: seam `RUB_LAUNCHD_DOMAIN=gui/<uid>` (e `RUB_LOG_FILE`);
  cena **S9g** do gate instala de verdade no domínio do usuário e prova (1) o PID do job na
  porta, (2) o serviço antigo fora do launchd encerrado e substituído, (3) o programa alheio
  recusado antes de tocar em nada.

## [0.3.1] — 2026-09-03

### Instalação
- **Conserto de produção:** o instalador declarava "serviço reiniciado e provado" olhando só o
  `launchctl print` (job carregado), e a verificação final aceitava com aviso e ✔ uma versão que
  não era a instalada. Medido em 2026-09-03: um daemon de desenvolvimento ocupava a porta
  35493, o serviço novo morria ("API local não subiu após 3 tentativas") e o relatório dizia
  "service v0.1.0" com ✔. Agora `scripts/install.sh` só declara "provado" quando o PID que
  escuta a porta da API é o PID do job do launchd (15 s de espera; falha nomeando o PID e o
  comando que ocupa a porta), e o one-liner falha (código 1) quando a versão que responde não é
  a do código instalado, nomeando quem escuta. Cena nova **S9e** no gate (processo alheio na porta).
- O pré-voo deixa de anunciar o Swift no canal release: o app vem pronto; o Swift só é
  checado se a compilação local for necessária (canal `main`, ou release sem app).

## [0.3.0] — 2026-09-03

### Dispositivos protegidos por instância
- **Escolher e adicionar dispositivos pela interface.** Em Ajustes → Dispositivos protegidos,
  "Adicionar dispositivo…" abre uma folha em duas etapas: o tipo (Console UniFi (UDR7) ou
  Computador ou servidor via SSH) e o formulário do tipo, com nome sugerido único. Cada
  instância tem folha própria (nome, armamento, máquina e chave, limiares), interruptor,
  badge de estado, cartão em Saúde, chip de filtro nos eventos e entrada na legenda do
  gráfico. Remover é pelo rodapé da folha, com confirmação; uma instância armada não é removida.
- **Segundo tipo: computador ou servidor via SSH.** Roda um comando de desligamento de uma
  lista fechada (`shutdown -h now`, `poweroff`, `systemctl poweroff`, com e sem `sudo -n`,
  cada um com fonte); nunca texto livre, nunca shell local.
- **Várias instâncias do mesmo tipo**, cada uma com seus arquivos de estado
  (`<id>_known_hosts`, `<id>_armed.json`, `<id>_runtime.json`), eventos com o dono no
  payload (`device`, `device_name`) e coluna `device` no histórico.
- **Migração sem toque:** no primeiro boot, o bloco `PROTECT_*`/`UDR7_*` do `.env` vira a
  instância `udr7` em `<estado>/devices.json` (0600). O `.env` nunca é escrito no boot; os PUTs
  pelo app (ou pelo app 0.2.0, via `/v1/config`) gravam nos dois. A trava `UDR7_ARM_ALLOWED`
  continua global e somente arquivo; o ensaio passa a ser por instância. A série esperada e o
  corte físico do River são do núcleo (valem para todas as instâncias) e ficam em Ajustes → River.
- **API local:** `GET /v1/device-types`, `GET/POST /v1/devices`, `GET/PUT/DELETE /v1/devices/{id}`,
  `GET /v1/events/log?device=`; recusas `{erro, motivo}` novas (`validacao`, `tipo_desconhecido`,
  `armar_no_post`, `nome_duplicado`, `dispositivo_ausente`, `sem_loja`).
- **Instalador:** recusa atualizar (código 3, sem reiniciar o serviço) enquanto existir uma
  instância armada (`*_armed.json`) — o mesmo veto do `POST /v1/service/restart`. O
  desinstalador lista o estado por padrão de nome e diz qual instância está armada.
- Reversão para a 0.2.0: `--release v0.2.0`; o `.env` está sempre fiel à instância `udr7`.
  Instâncias além dela ficam sem proteção até voltar à 0.3.0 (o `devices.json` fica intacto).

### Instalação
- **Conserto de produção:** ao salvar Ajustes pelo app, o daemon respondia 500 ("Server got
  itself in trouble"): `$PREFIX/etc` era do root e o daemon, rodando como o usuário do
  serviço, não conseguia criar o `bridge.env.bak`. O instalador passa a deixar a pasta com o
  dono do serviço, também na reexecução (medido no Mac mini em 2026-09-02).
- **Conserto de produção:** numa janela mais estreita que o rótulo, o spinner deixava um rastro
  a cada quadro (`│ ⠋ sudo scripts/install.sh…│ ⠙ sudo…`). O rótulo animado agora é cortado na
  largura da janela, o rótulo da fase do serviço ficou curto, e a causa de fundo foi
  consertada na classe: `tput cols` dentro de `$( )` com o stderr redirecionado devolvia sempre
  80, para o spinner, a régua, os cabeçalhos e a guarda de tamanho da abertura; todos passam a
  ler a janela real por `/dev/tty`. Nova cena **S20** (pty de 40 colunas), refutada.
- O pré-voo deixa de dizer "o app será compilado aqui" quando o app vem pronto da release.

## [0.2.0] — 2026-09-02

### Instalação e release
- **Release no GitHub, produzida na máquina de desenvolvimento** por `tools/release.sh`:
  gate, build do app, tag anotada, tarball do código **na tag**, `River-Bridge.app.zip` (ad-hoc,
  arm64, por `ditto`) e `SHA256SUMS`, publicados com `gh release create` e conferidos pela mesma
  URL que o instalador usa. `--check` exige as seis declarações de versão iguais e a seção do
  CHANGELOG; `--dry-run` monta os assets sem taguear. Sem CI: não há `.github/`, e o runner
  com macOS 26 não foi verificado.
- **O one-liner passa a consumir a release** (canal `release`, default): lê o `SHA256SUMS` em
  `releases/latest/download` só com `curl` (a tag vem do prefixo do tarball), pina o tarball e o app,
  baixa o app pronto (sha divergente = exit 3, nada instalado; sem Swift o app continua
  chegando) e cai para o tarball de `main` com aviso quando a release não é alcançável. O
  relatório e o `installer-last-run.log` dizem de onde veio o código (`fonte=`). Flags
  `--release TAG` e `--from-main`. `RUB_SRC_URL` explícito implica canal `main`.
- **Conserto de produção:** o desinstalador nunca era copiado para o prefixo, e o comando de
  desinstalação do README apontava para um arquivo inexistente (medido no Mac mini em
  2026-09-02). `scripts/install.sh` passa a instalá-lo em `$PREFIX/scripts` (classe `file:` do
  manifesto) e o desinstalador remove também o próprio diretório.
- Cercas: **S18** (canal release por `file://`, cinco rodadas, refutada com uma mutação por
  rodada), **S19** (`release.sh --check` reprova um mutante com versão divergente citando o
  arquivo), **S9/S10** passam a exigir o desinstalador no prefixo e a rodar a cópia instalada.
- **Roadworthy no repositório:** `.roadworthy/docs.json` (árvore de documentos por papel e o
  vocabulário de `status:` em português), `.roadworthy/gates` (os gates que o `close.sh` roda
  numa árvore limpa) e `docs/decisions/` com a validação medida de 2026-09-02 e a decisão que
  fecha a frente Wi‑Fi do River.

### App
- Ajustes ganha o grupo **Dispositivos protegidos**: uma linha por aparelho, com o nome que
  você deu, o estado, um interruptor e uma **folha** própria de configuração — o campo *Nome*
  no topo. A lista sai do registro, então um segundo dispositivo aparece sem mexer na tela.
- O nome do usuário chega aos **chips de filtro**, à **legenda do gráfico**, aos **rótulos da
  timeline** e ao **cartão de saúde**. O vocabulário de evento (símbolo, cor e texto dos dez
  eventos) saiu das telas e passou a viver no registro.
- Ligar a proteção com o modo ensaio desligado — ou desconhecido — passa a **pedir confirmação
  antes de escrever qualquer coisa**; desligar continua direto, porque desarmar é sempre aceito.
- Na timeline, *armado*/*desarmado* passam de roxo a índigo e o religamento a menta: agora
  iguais à legenda do gráfico, que divergia da lista para os mesmos eventos.

### Daemon
- **Arquitetura de plugins**: o daemon passa a ter um contrato de *dispositivo
  protegido* (`plugins/base.py`), com registro **estático** (`PLUGINS`) e o UDR7 como primeiro
  deles — um adaptador fino sobre a política, que não mudou de lugar. A API, o laço e o health
  falam com o registro: `GET /v1/health` ganha `plugins: [{id, name, state, detail}]`, e
  `udr7`/`udr7_detail` continuam no topo como alias permanente da entrada do UDR7 (o instalador
  os lê com `sed`). Um segundo dispositivo é um módulo novo mais uma linha no registro.
- Nova chave **`UDR7_NAME`**: o nome que você dá ao dispositivo, que vai aparecer nos relatórios
  e gráficos do app (1–32 caracteres). Aplica a quente e, apesar do prefixo `UDR7_`, **não** é
  congelada com a proteção armada nem entra nos pinos do arquivo de armamento — renomear o
  aparelho não desarma nada e não bloqueia a queda seguinte. `GET /v1/health` passa a trazer
  `udr7_detail.name`; com o nome vazio, o próprio daemon repõe `"UDR7"`, num lugar só.
  A forma barra o que faria um nome "parecer UDR7" sem ser: controle, `~`, hífen suave,
  zero-width, BOM, bidi, preenchedores Hangul, braille em branco, variation selectors e tags
  (medido: 7 nomes aceitos, 21 recusados). Duas cenas de gate novas — S4m (o nome fora do
  congelamento) e S4o (o nome fora dos pinos), ambas provadas por mutação.

### Instalação
- A abertura passa a mostrar **só o escudo** do ícone (antes era o quadrado arredondado
  inteiro, que encostava nas bordas e cortava o halo e o traço), no campo do molde
  `lib/haos-ui.sh`: 34 colunas e 0,03 s por quadro, num canvas 34×40 — o escudo é mais alto que
  largo, e no canvas quadrado da casa ele sairia bem menor. A largura vem da razão real do
  símbolo, 0,825.
- O desenho leva a **cor real de cada pixel** do render (`LG_RGB`, 1 360 entradas, 15,1 KiB) e
  uma **auréola** de 2 px do fundo do ícone seguindo a forma do escudo. É o volume do primeiro
  desenho com o escudo grande do segundo: escudo claro, raio vazado no verde, auréola que o
  descola do preto do terminal — o AppIcon, não a inversão dele. O gradiente por linha do molde
  foi medido e descartado: borra o raio e engrossa a auréola num verde chapado (erro médio de
  18,6 por canal, máximo 155). O pisca da batida acompanha — o raio é verde e pisca em branco.
  Mediana de 5,51 s em 7 execuções num pty de 80×40 (faixa 5,47–5,54).
- Novo `tools/ui-demo.sh` mostra a camada visual sem instalar nada, e `--comparar [ref]` põe a
  abertura de um commit anterior e a de hoje em sequência, separadas por um Enter — nesta ordem,
  para o desenho novo ser o que fica parado na tela no fim.
- A abertura passa a exigir tela alta o bastante: o laço sobe `LG_LINHAS` linhas por quadro e,
  numa tela mais baixa, o salto é grampeado no topo e os quadros escorregam. Abaixo de
  `LG_LINHAS + 1` cai para o quadro único, como já fazia com terminal estreito. Medido: 21
  linhas anima, 20 não; antes, uma tela de 15 linhas fazia 75 saltos de cursor às cegas.
- **Conserto de produção:** numa reexecução, o passo do serviço aparecia como **falha** —
  `✖ sudo scripts/install.sh … (exit 100)` em vermelho — com a linha de sucesso logo abaixo
  ("serviço já estava atual"). 100 é sucesso no contrato da casa ("nada a fazer"), mas o
  `ui_spin` rotulava todo código diferente de zero como erro, antes de o chamador classificar.
  Nova cena S17 roda a reexecução num pty COM animação e exige que a tela não mostre `✖` nem
  `(exit 100)` — precisa das duas coisas: com `--no-anim`, que é como S9 e S12 rodam, o
  `ui_spin` devolve antes de rotular e o defeito não aparece.
- **Conserto de produção:** num terminal de 256 cores — o Terminal.app de fábrica, que não
  define `COLORTERM` — a abertura saía **sem cor nenhuma** e imprimia `printf: 'LG_FGA[y]': not
  a valid identifier`. O `/bin/bash` do macOS é 3.2 e não aceita alvo indexado em `printf -v`;
  o ramo de 256 cores era o único que usava essa forma. Nova cena S16 roda a abertura nesse
  exato cenário (bash 3.2, sem `COLORTERM`) e exige cor e stderr limpo.
- Cercas: S14 exige as bordas da máscara vazias (o caso extremo do desenho colado na borda) e
  confere o render contra a máscara; S15 exige que o bloco gerado dentro do instalador seja
  idêntico à saída do gerador — é ela que garante a margem publicada. E `conferir()`, no
  gerador, passou a exigir que a folga entregue seja ao menos a margem pedida nos quatro lados:
  só "bordas vazias" passava até com margem zero, porque o anti-aliasing sempre esvazia a borda.

## [0.1.0] — 2026-09-01

### Instalação
- Instalador em uma linha `river-bridge-install.sh` (`curl … | bash -s --`): sem `git clone`,
  senha de administrador uma vez, tarball do `main` com sha256 conferido e cache, cinco fases
  com barra de progresso, abertura animada que degrada sem TTY/cor/UTF-8, contrato `0`/`100`,
  relatório em `installer-last-run.log`.
- Repositório tornado público; instalação remota verificada (dry-run `0`, instalação `0`,
  reexecução `100`).
- Abertura com o **ícone real do app** (`tools/gera-logo.py` roda o mesmo render do AppIcon;
  40×40 pixels, cada um com a própria cor) em quatro atos — constelação, traço, batimento
  cardíaco, assenta — e fecho no molde da casa (`relatorio_final`: título com o tempo, caixa
  do que ficou instalado, o app aberto como norte, `--no-open`).
- `scripts/install.sh`: manifesto do que criou (created/preexisting/pending), `--dry-run`
  inócuo, `--consent-homebrew` obrigatório para `brew install`, LaunchDaemon provado com
  `launchctl print` (com retry na corrida bootstrap/bootout medida no mini), resolução
  explícita do binário do brew para o PATH do root, código novo com plist igual reinicia o
  serviço (`kickstart`), piso NUT 2.8.4.
- `scripts/uninstall.sh`: remove só o que o manifesto prova; uma confirmação; lista os
  arquivos de runtime da proteção sem apagá-los.

### Daemon
- Leitura do NUT com config em allowlist, modelo normalizado, transições com debounce
  (queda/volta de energia, bateria baixa, perda/volta de comunicação) e defaults de alarme
  ancorados em fonte (6/0/15/30).
- API local HTTP+SSE em `127.0.0.1` com token 0600; histórico SQLite com consulta, busca e
  limpeza por faixa; `PUT /v1/config` que valida pela mesma allowlist do parser e preserva
  comentários do `.env`; reinício pela API.
- Sob launchd, erro de configuração é parada deliberada (exit 0) — o CLI mantém os códigos.
- Proteção do UDR7 (fase experimental, nasce em ensaio): política com dez condições para agir
  (telemetria não sintética, NUT local, número de série registrado, configuração pinada no
  armamento, `known_hosts` dedicado com `StrictHostKeyChecking=yes`, corte e limiar do dono,
  chave 0600, não calibrando, sem envio pendente, ensaio desligado); trava de armamento
  somente por arquivo; desarme sempre aceito; `argv` do ssh isolado; Wake-on-LAN opcional
  ao voltar a energia; elo `udr7` no health com detalhe e avisos; dez eventos `UDR7_*`.

### App River Bridge (macOS 26)
- Barra de menus viva com popover na anatomia do menu de Bateria do sistema; painel com
  Energia (anel de autonomia, fluxo de energia, eventos com detalhe inline), Gráficos
  (escala de tempo com pan/pinch, eixos validados por captura, callouts), Saúde (cadeia
  USB → NUT → bridge → UniFi → UDR7, headers pregados) e Ajustes (autosave silencioso;
  grupo de proteção com botão Salvar e diálogo para sair do ensaio; grupo Aparência e
  idioma no topo).
- Liquid Glass: janela translúcida real, materiais, tema claro/escuro/auto, l10n pt-BR/en-US,
  modo compacto até 414 pt, reabertura pelo Dock, ícone da barra com contraste real.

### Ferramentas e qualidade
- Simulador `tools/fake-nut-ups` (cenários `online`, `power-loss`, `apagao`, `--die-after`,
  `LIST UPS`, `--host`), sintético por construção — a proteção nunca age sobre ele.
- `tools/gate.sh`: testes Python e Swift (incl. `xcodebuild`), mutação das cercas (a cerca
  tem de reprovar o defeito plantado), contrato do instalador e do desinstalador, cenas do
  instalador em uma linha, snapshot da abertura.
- Capturas focadas com verificação de mancha para validar UI.

### Documentação e pesquisa
- Especificação com emendas (UI nativa, API local, fase experimental do UDR7, exceções e
  testes), pesquisa pública sobre UniFi × UPS de terceiros (sem caminho nativo documentado),
  parâmetros de UPS com fonte, RIVER 3 Plus sem Wi-Fi local, hipóteses H01–H17, runbook da
  proteção do UDR7, contrato da API, instalação em uma linha, backlog.

[0.1.0]: https://github.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/commits/main
