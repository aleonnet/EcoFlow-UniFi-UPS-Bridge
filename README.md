# River Bridge — EcoFlow RIVER 3 Plus → NUT → UniFi

Um EcoFlow RIVER 3 Plus ligado por USB a um Mac mini vira um no-break gerenciável na rede:
o [NUT](https://networkupstools.org) lê a bateria, um daemon Python acompanha o estado
(rede, bateria, autonomia, eventos), um app nativo de macOS mostra tudo na barra de menus,
e — em fase experimental, nascendo em modo ensaio — o daemon pode desligar o console UniFi
(UDR7) com dignidade antes de a bateria acabar.

Tudo roda local: a API do daemon só escuta em `127.0.0.1`, nada sai para a Internet, nenhum
segredo entra no repositório.

## O que funciona hoje (2026-09-01)

| Peça | Estado |
|---|---|
| Daemon `river-unifi-bridge` (LaunchDaemon, lê o NUT, API local HTTP+SSE, histórico SQLite) | pronto |
| App **River Bridge** (macOS 26, barra de menus + painel: energia, gráficos, eventos, saúde, ajustes) | pronto |
| Simulador de UPS (`tools/fake-nut-ups`) para desenvolver sem o hardware | pronto |
| Proteção do UDR7 (desligamento via SSH quando a bateria chega ao limiar) | **em ensaio** — nada é enviado ao console até você armar (ver [runbook](docs/UDR7_PROTECAO_SSH_20260901.md)) |
| Driver NUT do RIVER físico (`usbhid-ups`, NUT ≥ 2.8.4) | pendente do hardware na bancada — o instalador detecta o RIVER no USB e deixa o passo marcado como pendente |
| UDR7 exibir o RIVER como "UniFi UPS" | **sem caminho nativo documentado** — consoles UniFi não consomem UPS de terceiros ([pesquisa](docs/PESQUISA_UDR7_UPS_TERCEIROS_20260831.md)) |

## Requisitos

- macOS 26 em Apple Silicon (medido em 26.6.2 / arm64); o app tem alvo `macOS 26.0`.
- [Homebrew](https://brew.sh) — o instalador instala `nut` e `python@3.13` por ele
  (ou instala o próprio Homebrew com `--install-deps`).
- Para compilar o app: Xcode ou Command Line Tools (`swift`). Sem Swift, o instalador
  instala só o serviço e avisa.
- Senha de administrador **uma vez** (o serviço é um LaunchDaemon).

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s --
```

Em cinco fases: pré-voo → baixa o código (tarball do `main`, sha256 conferido) → serviço
(`sudo scripts/install.sh`: brew, código em `/usr/local/river-unifi-bridge`, venv, config,
LaunchDaemon) → app em `~/Applications/River Bridge.app` → verificação pela API local.
Reexecutar é seguro: sai `0` quando fez algo, `100` quando já estava tudo no lugar.

Flags úteis: `--dry-run` (só mostra o plano), `--no-app`, `--no-open`, `--install-deps`,
`--yes`, `--src DIR` (usar uma árvore local em vez de baixar), `--lang pt|en`, `--no-anim`.
Detalhes em [docs/INSTALACAO_UMA_LINHA_20260901.md](docs/INSTALACAO_UMA_LINHA_20260901.md).

Já tem o repositório clonado? `sudo scripts/install.sh --consent-homebrew` e
`tools/build-app.sh` fazem o mesmo, por partes.

## Configurar

A configuração é um único arquivo, `/usr/local/river-unifi-bridge/etc/bridge.env` (0600,
do usuário do serviço). O jeito normal de editar é pelo app → **Ajustes**; mudanças
"a quente" valem na hora, as demais pedem reinício (o app oferece). Modelo comentado em
[`config/river-unifi-bridge.env.example`](config/river-unifi-bridge.env.example).

| Grupo | Chaves | Para quê |
|---|---|---|
| River / NUT | `RIVER_NAME`, `NUT_HOST`, `NUT_PORT`, `NUT_UPS` | onde o daemon lê o UPS (por padrão o NUT local, porta 3493) |
| Bridge | `POLL_INTERVAL_SECONDS`, `EMULATE_MODEL`, `READ_ONLY` | ritmo de leitura |
| Alarmes | `POWER_LOSS_DELAY_SECONDS`, `RESTORE_DELAY_SECONDS`, `COMM_LOSS_DELAY_SECONDS`, `LOW_BATTERY_PERCENT` | quando os eventos disparam (defaults com fonte em [docs/PESQUISA_PARAMETROS_UPS_20260831.md](docs/PESQUISA_PARAMETROS_UPS_20260831.md)) |
| API local | `UI_API_ENABLED`, `UI_API_PORT`, `HISTORY_RETENTION_DAYS` | porta da API (35493) e retenção do histórico |
| Proteção do UDR7 | `PROTECT_UDR7`, `PROTECT_DRY_RUN`, `UDR7_ARM_ALLOWED`, `UDR7_*` | host/porta/usuário/chave SSH do console, número de série esperado do RIVER, percentual de corte e de desligamento, confirmação, tentativas, MAC para Wake-on-LAN |

A proteção do UDR7 nasce desligada e em ensaio (`PROTECT_DRY_RUN=1`); armar de verdade exige
três passos seus (`UDR7_ARM_ALLOWED=1` no arquivo + reinício, desligar o ensaio no app,
`UDR7_ARM_ALLOWED=0` + reinício) e só é aceito com o RIVER real no NUT — o simulador nunca
consegue armar. O passo a passo, as medições que fazer antes e a recuperação estão no
[runbook](docs/UDR7_PROTECAO_SSH_20260901.md).

## Operar

- Serviço: `sudo launchctl print system/com.river.unifi-bridge` (estado),
  `sudo launchctl kickstart -k system/com.river.unifi-bridge` (reiniciar).
- Log do serviço: `~/Library/Logs/river-unifi-bridge.log`.
- Estado do daemon (token da API, histórico, arquivos da proteção):
  `~/Library/Application Support/river-unifi-bridge/`.
- API local (token em `ui-api.token`): `GET /v1/state`, `/v1/health`, `/v1/events` (SSE),
  `/v1/events/log`, `/v1/history`, `GET|PUT /v1/config`, `POST /v1/service/restart`,
  `/v1/version` — contrato em [docs/API_LOCAL_20260831.md](docs/API_LOCAL_20260831.md).
- Diagnóstico de uma leitura só: `/usr/local/river-unifi-bridge/venv/bin/python -m river_unifi_bridge.service --env /usr/local/river-unifi-bridge/etc/bridge.env --once`.

## Desinstalar

```bash
sudo /usr/local/river-unifi-bridge/scripts/uninstall.sh            # mostra o plano
sudo /usr/local/river-unifi-bridge/scripts/uninstall.sh --confirm  # executa
```

Remove **só** o que o manifesto prova que o instalador criou (código, venv, LaunchDaemon);
o que já existia (Homebrew, `nut`, `python@3.13`) fica. Arquivos criados pelo daemon em
runtime — token da API, estado da proteção, chave SSH dedicada — são listados com aviso, não
apagados; a chave pública instalada no console UniFi se remove à mão. O app é só arrastar
`~/Applications/River Bridge.app` para o Lixo.

## Desenvolver

```bash
python3.13 -m venv .venv && .venv/bin/pip install -e '.[dev]'
tools/fake-nut-ups --scenario apagao      # UPS de mentira na porta 3493 (cenários: online, power-loss, apagao, …)
.venv/bin/pytest                          # testes Python (unit + integração)
(cd macos/RiverBridge && swift test)      # testes do app
tools/gate.sh                             # portão completo: testes, mutação das cercas, instalador, app
```

O `gate.sh` é o critério de "pronto": além dos testes, ele planta defeitos nas cercas de
segurança e exige que os testes reprovem, prova o contrato do instalador (0/100, dry-run que
não escreve, desinstalação que só remove o nosso) e compara a abertura do instalador com um
snapshot.

## Documentos

- [Especificação](RIVER3PLUS_UNIFI_BRIDGE_SPEC_20260831.md) — a fonte de verdade das decisões.
- [Runbook da proteção do UDR7](docs/UDR7_PROTECAO_SSH_20260901.md).
- [Instalação em uma linha](docs/INSTALACAO_UMA_LINHA_20260901.md).
- [API local](docs/API_LOCAL_20260831.md).
- Pesquisas: [UniFi × UPS de terceiros](docs/PESQUISA_UDR7_UPS_TERCEIROS_20260831.md),
  [parâmetros de UPS](docs/PESQUISA_PARAMETROS_UPS_20260831.md),
  [RIVER 3 Plus e Wi-Fi](docs/PESQUISA_ECOFLOW_WIFI_20260901.md); hipóteses e achados em `research/`.
- [Backlog](docs/BACKLOG_20260901.md) · [Changelog](CHANGELOG.md).

Licença MIT.
