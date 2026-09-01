# Changelog

Formato de [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Ainda não há tags
de versão: `0.1.0` é a versão declarada em `pyproject.toml`, `scripts/uninstall.sh` e
`tools/build-app.sh`, e cobre tudo até o commit atual de `main`.

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
