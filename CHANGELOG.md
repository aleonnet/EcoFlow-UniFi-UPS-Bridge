# Changelog

Formato de [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Ainda não há tags
de versão: `0.1.0` é a versão declarada em `pyproject.toml`, `scripts/uninstall.sh` e
`tools/build-app.sh`. O que veio depois dela está em `[Unreleased]`.

## [Unreleased]

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
