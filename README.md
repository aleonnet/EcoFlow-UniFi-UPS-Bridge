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
| Dispositivos protegidos (desligamento via SSH quando a bateria chega ao limiar), adicionados pela interface | **em ensaio** por dispositivo — nada é enviado até você armar; dois tipos: Console UniFi (UDR7) ([runbook](docs/guides/2026-09-03-1710-runbook-protecao-udr7-por-instancia.md)) e Computador ou servidor via SSH ([runbook](docs/guides/2026-09-03-1720-runbook-host-ssh.md)); várias instâncias do mesmo tipo, cada uma com o nome que você dá |
| Driver NUT do RIVER físico (`usbhid-ups`, NUT ≥ 2.8.4) | pendente do hardware na bancada — o instalador detecta o RIVER no USB e deixa o passo marcado como pendente |
| UDR7 exibir o RIVER como "UniFi UPS" | **sem caminho nativo documentado** — consoles UniFi não consomem UPS de terceiros ([pesquisa](docs/2026-08-31-2345-pesquisa-udr7-ups-terceiros.md)) |

## Requisitos

- macOS 26 em Apple Silicon (medido em 26.6.2 / arm64); o app tem alvo `macOS 26.0`.
- [Homebrew](https://brew.sh) — o instalador instala `nut` e `python@3.13` por ele
  (ou instala o próprio Homebrew com `--install-deps`).
- Swift é **opcional**: o instalador baixa o app pronto da release do GitHub (arm64,
  assinatura ad-hoc). Só precisa de Xcode ou Command Line Tools (`swift`) quem instala
  `--from-main` ou quando a release não está alcançável.
- Senha de administrador **uma vez** (o serviço é um LaunchDaemon).

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s --
```

Em cinco fases: pré-voo → baixa o código da **release** mais recente (tarball da tag e
`River-Bridge.app.zip`, cada um conferido pelo `SHA256SUMS` dela; sem release alcançável, cai
para o tarball do `main` e avisa) → serviço (`sudo scripts/install.sh`: brew, código em
`/usr/local/river-unifi-bridge`, venv, config, LaunchDaemon) → app em
`~/Applications/River Bridge.app` (pronto da release, ou compilado aqui) → verificação pela
API local. Reexecutar é seguro: sai `0` quando fez algo, `100` quando já estava tudo no lugar.
O relatório diz de onde veio o código (`fonte=release vX.Y.Z` ou `fonte=main`).

Flags úteis: `--dry-run` (só mostra o plano), `--no-app`, `--no-open`, `--install-deps`,
`--yes`, `--release TAG`, `--from-main`, `--src DIR` (usar uma árvore local em vez de
baixar), `--lang pt|en`, `--no-anim`.
Detalhes em [docs/INSTALACAO_UMA_LINHA_20260901.md](docs/INSTALACAO_UMA_LINHA_20260901.md).

Já tem o repositório clonado? `sudo scripts/install.sh --consent-homebrew` e
`tools/build-app.sh` fazem o mesmo, por partes. Publicar uma release: `tools/release.sh vX.Y.Z`
(confere as seis declarações de versão, roda o gate, compila, tagueia e sobe os três assets).

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
| River (núcleo da proteção) | `UDR7_EXPECTED_SERIAL`, `UDR7_CUTOFF_PERCENT` | número de série esperado do RIVER e corte físico da saída — valem para todos os dispositivos protegidos (Ajustes → River) |
| Trava de armamento | `UDR7_ARM_ALLOWED` | global e somente arquivo: o app nunca a muda |
| Espelho da instância `udr7` | `PROTECT_UDR7`, `PROTECT_DRY_RUN`, `UDR7_*` restantes, `UDR7_NAME` | desde a 0.3.0 os dispositivos são instâncias em `devices.json`, editadas pelo app; este bloco é lido uma vez na migração e depois só espelha a instância `udr7` |

Cada dispositivo protegido nasce desligado e em ensaio; armar de verdade exige três passos seus
(`UDR7_ARM_ALLOWED=1` no arquivo + reinício, desligar o ensaio na folha do dispositivo,
`UDR7_ARM_ALLOWED=0` + reinício) e só é aceito com o RIVER real no NUT — o simulador nunca
consegue armar. O instalador recusa atualizar o serviço enquanto houver um dispositivo armado.
O passo a passo, as medições que fazer antes e a recuperação estão nos runbooks
([UDR7](docs/guides/2026-09-03-1710-runbook-protecao-udr7-por-instancia.md),
[host SSH](docs/guides/2026-09-03-1720-runbook-host-ssh.md)).

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
- [Runbook da proteção do UDR7 por instância](docs/guides/2026-09-03-1710-runbook-protecao-udr7-por-instancia.md) e [do host SSH](docs/guides/2026-09-03-1720-runbook-host-ssh.md).
- [Instalação em uma linha](docs/INSTALACAO_UMA_LINHA_20260901.md).
- [API local](docs/reference/api-local.md).
- Pesquisas: [UniFi × UPS de terceiros](docs/2026-08-31-2345-pesquisa-udr7-ups-terceiros.md),
  [parâmetros de UPS](docs/PESQUISA_PARAMETROS_UPS_20260831.md),
  [RIVER 3 Plus e Wi-Fi](docs/PESQUISA_ECOFLOW_WIFI_20260901.md),
  [arquitetura de plugins](docs/PESQUISA_ARQUITETURA_PLUGINS_20260901.md); hipóteses e achados em `research/`.
- [Backlog](docs/BACKLOG_20260901.md) · [Changelog](CHANGELOG.md).

Licença MIT.
