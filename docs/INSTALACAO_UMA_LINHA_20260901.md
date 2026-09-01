# Instalação em uma linha — `river-bridge-install.sh` (2026-09-01)

Um arquivo, um comando, a senha uma vez. Padrão da casa (haos-install.sh / ont-setup.sh):
`curl … | bash -s -- [opções]`, idempotente (0 fez · 100 já estava), abertura animada
degradável, prompts lidos de `/dev/tty` (funciona pelo cano), trabalho privilegiado
concentrado numa única chamada `sudo scripts/install.sh` logo após primar o `sudo`.

## Remoto (quando o repositório estiver PÚBLICO)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s --
```

**Medido em 2026-09-01 (`gh repo view`): o repositório está PRIVADO.** `raw.githubusercontent.com`
e o tarball `archive/refs/heads/main.tar.gz` respondem 404 sem token — o comando acima só
funciona depois de o dono publicar o repo (ou apontar `RUB_SRC_URL` para um tarball acessível).
Até lá, use a forma local.

## Local (árvore já na máquina — é o caso do Mac mini hoje)

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

`--dry-run` · `--yes` · `--install-deps` · `--no-app` · `--src DIR` · `--no-anim` · `--demo` ·
`--lang pt|en` · `--version` · `--help`. Seams (bancada/gate): `RUB_SRC_URL`, `RUB_SRC_DIR`,
`RUB_SRC_SHA256`, `RUB_CACHE_DIR`, `RUB_STATE_DIR`, `RUB_PREFIX`, `RUB_LAUNCHD_DIR`,
`RUB_SERVICE_USER`, `RUB_PYTHON`, `RUB_SUDO` (vazio = sem sudo, para stubs), `RUB_APP_DEST`,
`RUB_SKIP_HEALTH`, `UI_NO_ANIM`, `NO_COLOR`.

## Abertura

Motor de meio-bloco da casa (ont-ui.sh, via macmini-backup.sh) com a cena do app: o raio se
desenha, o escudo cresce em volta, pulsa ao ritmo dos dados que correm do River ao UDR7,
clarão, e assenta aceso. Degrada em três eixos (TTY · NO_COLOR · UTF-8): sem animação = um
quadro parado; sem cor/UTF-8 = só o título. `--demo` mostra só a abertura. O quadro final é
snapshot no gate (S14, pty de 80 colunas).

## Cercas no gate (`tools/gate.sh`)

S11 sintaxe em bash 3.2 + `--help` pelo cano sob locale C (ASCII puro) · S12 contrato 0 → 100 →
`kickstart` com código novo → download por `file://` (stubs de brew/launchctl, sem root, sem
rede) · S13 dry-run pelo cano sai 0 e não escreve nada · S14 snapshot da abertura.
