---
status: aceito
---

# Validação do estado em disco e programa de frentes — 2026-09-02

Registro da validação pedida pelo dono ("leia os códigos e a verdade em disco e valide tudo")
contra os três objetivos: (1) daemon no Mac mini instalado por uma linha que baixa uma
**release** do app sem clonar; (2) o River 3 Plus chegando ao NUT por USB, BLE e Wi‑Fi;
(3) o app aceitando plugins de dispositivos protegidos. Plano aprovado por revisão fria
amarrada ao hash: `~/.claude/plans/este-foi-o-prompt-binary-sedgewick.md` (banca ao lado,
sufixo `.banca.md`).

Gramática: `[M]` medido no ato com o comando; `[P]` primária; `[S]` secundária;
`[P-estático]` código do fabricante lido sem execução.

## Contexto e problema

O handoff anterior e a memória descreviam um estado que o disco desmentia em parte. Sem uma
validação medida, a próxima frente partiria de premissas caducas.

## O que foi medido (2026-09-02, MacBook e Mac mini por ssh)

| Comando | Resultado | Grau |
|---|---|---|
| `git log -1 --oneline; git status -sb` (antes deste commit) | `e39b436`; `ahead 5`; 2 modificados + 1 novo em `docs/` | `[M]` |
| `git log -1 --format=%h origin/main` | `70e2926` — é o que o one-liner remoto instala | `[M]` |
| `gh release list`; `gh api …/releases`; `…/tags`; `git tag`; `ls .github` | tudo vazio; `.github/` não existe | `[M]` |
| `grep -rn "0\.1\.0"` | versão em 6 lugares: `pyproject.toml:3`, `src/river_unifi_bridge/__init__.py:3`, `scripts/install.sh:20`, `scripts/uninstall.sh:11`, `tools/build-app.sh:11`, `river-bridge-install.sh:30` | `[M]` |
| `grep -oE "\bS[0-9]+[a-z]?\b" tools/gate.sh \| sort -u \| wc -l` | 31 cenas | `[M]` |
| `.venv/bin/pytest` | `221 passed in 22.13s` | `[M]` |
| `grep -n "len(protect.GATES)" tests/unit/test_protect.py` | `747: … len(protect.GATES) == 12` | `[M]` |
| `grep -n "protect.py" tools/gate.sh` | 7 cenas: S4c, S4d, S4f, S4h, S4i, S4k, S4o | `[M]` |
| `grep -rn "PROBE" src/ tests/` | definição em `udr7_ssh.py:75`; 1 import e 1 asserção em `test_plugin_contract.py:211,215`; zero chamadas em produção | `[M]` |
| `find config -type f` | só `river-unifi-bridge.env.example`; nenhum arquivo de configuração do NUT no repo | `[M]` |
| mini: `brew list --versions nut; upsd -V` | `nut 2.8.5`; `upsd 2.8.5 release` | `[M]` |
| mini: `strings …/Cellar/nut/2.8.5/bin/usbhid-ups \| grep -i ecoflow` | `EcoFlow HID 0.01` — o subdriver EcoFlow **existe** na 2.8.5 | `[M]` |
| mini: `ls /opt/homebrew/etc/nut/` | só `*.sample`; `upsd` não roda | `[M]` |
| mini: `lsof -iTCP -sTCP:LISTEN` | `*:3493` = `fake-nut-ups --scenario apagao` (desde 2026-09-01 08:21); `127.0.0.1:35493` = daemon da ponte | `[M]` |
| mini: `cat /usr/local/river-unifi-bridge/last-run.log` | `install.sh v0.1.0 2026-09-01T23:13:07 rc=100`, todas as fases 100 | `[M]` |
| shasum de `src/**/*.py` local × mini | mini == `f0cd86b`; HEAD difere em `config.py`, `protect.py`, `state.py`, `plugins/udr7_ssh.py` | `[M]` |
| mini: `GET /v1/health` com o token local | `nut: ok`, `usb: nao_observavel`, `udr7: desabilitado`, `dry_run: true`, `source: sintetica` | `[M]` |
| mini: `ls /usr/local/river-unifi-bridge` | `etc last-run.log manifest.tsv src venv` — sem `scripts/`; o caminho de desinstalação do `README.md:88-89` não existe | `[M]` |
| mini: `xcode-select -p; swift --version`; `system_profiler SPUSBDataType \| grep -ci ecoflow` | Xcode + Swift 6.3.3; 0 dispositivos EcoFlow no USB | `[M]` |
| `nc -z -G 3 192.168.1.1 22` / `443` | 22 fechada; 443 aberta | `[M]` |
| `curl -fsSL -o q.txt <raw>; xattr -l q.txt` | vazio — `curl` não grava `com.apple.quarantine` | `[M]` |
| `ls .roadworthy` (antes deste commit) | não existia | `[M]` |

## Veredito por objetivo

**Objetivo 1 — one-liner e release.** O one-liner existe, é público e funciona
(`README.md:36`; contrato 0/100 em `INSTALACAO_UMA_LINHA_20260901.md`). Ele não clona: baixa o
tarball do **branch `main`** (`river-bridge-install.sh:35, 653-679`). Não existe release: o app
é compilado na máquina alvo (`fase_app`, `:706-727` → `tools/build-app.sh`, assinatura ad-hoc);
sem Swift o app é pulado (`:710`). Defeito colateral: `scripts/uninstall.sh` não é copiado ao
prefixo. **Lacuna real: release e consumo da release pelo instalador** (frente F1).

**Objetivo 2 — River por USB, BLE e Wi‑Fi.** Hoje nada chega ao NUT: o `upsd` real não roda no
mini e a porta 3493 é do simulador. USB: driver escolhido (`usbhid-ups` com o subdriver
EcoFlow, presente na 2.8.5 — a afirmação "só na 2.8.6" em `2026-09-01-2243-…` estava errada),
sem configuração de NUT no repo; o instalador só marca `svc:nut-driver pending`
(`scripts/install.sh:196-208`). Depende do aparelho, que não chegou. BLE: zero código, só
pesquisa de terceiros (`PESQUISA_ECOFLOW_WIFI_20260901.md:23, 49-53`). Wi‑Fi: não foi
dificuldade de implementação; o rádio só fala com a nuvem EcoFlow (decisão registrada em
`2026-09-02-2124-wifi-do-river-fechado.md`).

**Objetivo 3 — plugins.** O contrato existe e está fiado no daemon (`plugins/base.py`,
`plugins/__init__.py:13`, `plugins/udr7_ssh.py`) e no app (`DevicePlugins.swift`,
`DevicePluginUI.swift`, grupo "Dispositivos protegidos"). O que falta para um 2º dispositivo é
`BACKLOG_20260901.md` B10–B16. **Defeito central aberto:** a proteção pode se declarar armada
sem nunca ter falado com o console — os 12 portões são locais (`protect.py:396-435`) e o probe
existe sem chamada. Frente F2 (plano v2 em `~/.claude/plans/piped-seeking-toast.md`).

**Roadworthy.** Estava instalado no usuário e não inicializado no repositório; este commit cria
`.roadworthy/docs.json` (papéis e vocabulário em português), `.roadworthy/gates` e o escopo.

## Correções de registro

1. "Deploy no mini aguarda sudo" caducou: o instalador rodou no mini em 2026-09-01 23:13 com
   todas as fases em 100 (código `f0cd86b`). Pendente é sincronizar o mini com HEAD e ligar o
   ensaio (`pos-install-fase3exp.sh`): a proteção lá está `desabilitado`.
2. NUT 2.8.5 tem o subdriver EcoFlow (`strings` acima). O documento que dizia o contrário já
   está superado e não é reescrito.
3. Runbook §9 registra 217 testes; hoje são 221 (`.venv/bin/pytest`, saída acima).
4. O caminho de desinstalação do README será verdadeiro após F1 (o instalador passa a copiar o
   desinstalador ao prefixo).

## Decisão — o programa de frentes

| # | Frente | Depende de | Quando |
|---|---|---|---|
| F0 | Higiene, bootstrap do Roadworthy, estas correções | — | este commit |
| F1 | Release + one-liner consome release + desinstalador no prefixo | F0 | agora |
| F2 | Prova de alcance ao UDR7 pela API local do console (plano v2) | banca do v2; conta local no UDR7 criada pelo dono | após F1 |
| F3 | NUT real no mini (subdriver EcoFlow, `ignorelb` + `override.battery.charge.low`, `upsd` só loopback) | River na bancada | plano próprio quando o aparelho chegar |
| F4 | Wi‑Fi fechado | — | decisão ao lado |
| F5 | Nuvem EcoFlow só para visibilidade | conta de desenvolvedor EcoFlow | amanhã; plano próprio |
| F6 | BLE (protocolo revertido por terceiros) | River perto do mini | amanhã; plano próprio |

Decisões de política ratificadas pela aprovação do plano: fallback do instalador para o
tarball de `main` quando a release não é alcançável (com aviso e `fonte=` no log); primeira tag
`v0.2.0`; alvo só Apple Silicon; assinatura ad-hoc mantida; sem CI nesta etapa.

## Consequências

- Bom: o próximo trabalho parte de estado medido; o mini deixa de ser descrito como "não
  instalado"; a lacuna de release fica nomeada e planejada.
- Ruim: o mini continua com telemetria sintética e proteção desabilitada até F1/F3; o defeito
  central da proteção continua aberto até F2.

## Confirmação

Esta decisão está em vigor enquanto `docs-check.sh docs --since 2026-09-01` passa e o plano
citado tem banca `VERDICT: APPROVED` amarrada ao seu SHA-256; deixa de valer quando uma frente
listada mudar de dependência ou de ordem — nesse caso, novo arquivo, este marcado
`superado por`.
