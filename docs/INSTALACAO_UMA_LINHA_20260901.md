# Instalação em uma linha — `river-bridge-install.sh` (2026-09-01)

Um arquivo, um comando, a senha uma vez. Padrão da casa (haos-install.sh / ont-setup.sh):
`curl … | bash -s -- [opções]`, idempotente (0 fez · 100 já estava), abertura animada
degradável, prompts lidos de `/dev/tty` (funciona pelo cano), trabalho privilegiado
concentrado numa única chamada `sudo scripts/install.sh` logo após primar o `sudo`.

## Remoto (repositório PÚBLICO desde 2026-09-01 — `gh repo edit --visibility public`, ordem do dono)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s --
```

Verificado em 2026-09-01 após a publicação: o script pelo `raw` responde e roda em `--dry-run`;
o tarball `archive/refs/heads/main.tar.gz` baixa, extrai (`--strip-components=1`) e instala o
serviço num prefixo de teste (stubs de brew/launchctl, exit 0). Flags úteis: `--dry-run`
(só o plano), `--no-app` (só o serviço), `--install-deps` (instala o Homebrew se faltar).

## Local (árvore já na máquina — bancada, ou sem rede)

```bash
~/river-bridge-deploy/river-bridge-install.sh --src ~/river-bridge-deploy
```

O mesmo arquivo, o mesmo fluxo; `--src` só troca o download pela árvore indicada.

## O que ele faz (5 fases, barra de fases, calha)

| Fase | Faz | "já estava" |
|---|---|---|
| 01 Pré-voo | macOS, `curl/tar/shasum`, Homebrew (portão; `--install-deps` instala o oficial em `NONINTERACTIVE`), Swift (só avisa) | — |
| 02 Código-fonte | baixa o tarball (`.parcial` → `mv`), `sha256` (pino opcional `RUB_SRC_SHA256`), extrai em `~/Library/Caches/river-unifi-bridge/src-<sha>` | cache com o mesmo sha |
| 03 Serviço | **`sudo scripts/install.sh --consent-homebrew`** — brew `nut` + `python@3.13`, código, venv, `bridge.env` (preservado), LaunchDaemon; **código novo com plist igual → `kickstart`** | `install.sh` devolve 100 |
| 04 App | `tools/build-app.sh` (Swift, no alvo) → `~/Applications/River Bridge.app` se o binário mudou (fecha/reabre se estava aberto) | binário idêntico (`cmp`) |
| 05 Verificação | espera a API local, lê `/v1/version` e `/v1/health` (NUT, UDR7, UniFi) | — |

Saída: 0 (fez algo) · 100 (nada a fazer) · 2 uso · 3 validação · 4 dependência · 10 rede ·
130 cancelado · 1 falha. Relatório em `~/Library/Application Support/river-unifi-bridge/installer-last-run.log`.
Reexecutar é seguro: cada fase confere o estado.

## Senha uma vez — por quê funciona

`garantir_sudo` (molde haos-install.sh:487-504): `sudo -n true` → se não há cache, `sudo -v <
/dev/tty` **uma vez**; em seguida a única chamada privilegiada é `sudo scripts/install.sh`, que
faz tudo que exige root (inclusive o `kickstart`). O app compila e instala como o usuário. Não há
keepalive porque não há segundo `sudo` depois de minutos. O instalador nunca guarda, ecoa ou
repassa a senha.

## Flags

`--dry-run` · `--yes` · `--install-deps` · `--no-app` · `--no-open` · `--src DIR` · `--no-anim` ·
`--demo` · `--demo-frame N` · `--lang pt|en` · `--version` · `--help`. Seams (bancada/gate): `RUB_SRC_URL`, `RUB_SRC_DIR`,
`RUB_SRC_SHA256`, `RUB_CACHE_DIR`, `RUB_STATE_DIR`, `RUB_PREFIX`, `RUB_LAUNCHD_DIR`,
`RUB_SERVICE_USER`, `RUB_PYTHON`, `RUB_SUDO` (vazio = sem sudo, para stubs), `RUB_APP_DEST`,
`RUB_SKIP_HEALTH`, `UI_NO_ANIM`, `NO_COLOR`.

## Abertura — o ícone real do app

`tools/gera-logo.py` roda o mesmo render do AppIcon (`tools/app-icon-render.swift`,
compartilhado com `tools/make-app-icon.sh`), recorta o squircle, reduz a 40×40 pixels com o
`sips` e embute no instalador um bitmap com a cor de cada pixel (meio-bloco: 20 linhas — o
maior que cabe com o título num terminal de 24 linhas). Quatro atos, como a abertura do
`haos-install.sh`: o fundo do squircle sobe como líquido com o escudo vazado enquanto cada
pixel do escudo voa de fora da tela e assenta (constelação); a caneta branca contorna o
escudo e se retrai; o escudo **bate como um coração** — tum-tum, pausa, tum-tum — clareando,
acendendo o raio e soltando um halo ciano no pico; e assenta. Medido num pty (2026-09-01): 95
quadros em 5,5 s. Degrada em três eixos (TTY · NO_COLOR · UTF-8): sem animação = um quadro
parado; sem cor/UTF-8 = só o título. `--demo` mostra só a abertura; `--demo-frame N` um
quadro. O quadro final é snapshot no gate (S14, pty de 80 colunas). Mudou o ícone? Rode o
gerador e cole o fragmento entre os marcadores `GERADO` do instalador.

## Fecho — o relatório do molde da casa

Como o `relatorio_final` do `haos-install.sh`: título com o tempo na mesma linha ("Feito até
aqui · concluído em 43s" ou "Nada a fazer — tudo já estava no lugar"), caixa do que ficou
instalado (✔ serviço com a versão lida de `/v1/version`, ✔ app, ✔ configuração; `gum` se
houver, texto puro se não), o **norte** — "O River Bridge está na sua barra de menus", e o app
é aberto sozinho (`--no-open` desliga) —, o aviso de que a proteção do UDR7 nasce em ensaio,
e o caminho do relatório desta execução.

## Cercas no gate (`tools/gate.sh`)

S11 sintaxe em bash 3.2 + `--help` pelo cano sob locale C (ASCII puro) · S12 contrato 0 → 100 →
`kickstart` com código novo → download por `file://` (stubs de brew/launchctl, sem root, sem
rede) · S13 dry-run pelo cano sai 0 e não escreve nada · S14 snapshot da abertura.
