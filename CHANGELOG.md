# Changelog

Formato de [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). A partir da `v0.2.0`
cada versão é uma tag `vX.Y.Z` que amarra as seis declarações de versão (`pyproject.toml`,
`src/river_unifi_bridge/__init__.py`, `scripts/install.sh`, `scripts/uninstall.sh`,
`tools/build-app.sh`, `river-bridge-install.sh`) e a seção correspondente aqui — conferido por
`tools/release.sh --check`, que é quem produz a release. A `0.1.0` não teve tag. O que veio
depois da última versão está em `[Unreleased]`.

## [Unreleased]

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
