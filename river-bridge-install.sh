#!/usr/bin/env bash
# =============================================================================
# river-bridge-install.sh — River Bridge (EcoFlow RIVER 3 Plus → NUT → UniFi) em
# UM comando, sem git clone: baixa o código, instala o serviço (LaunchDaemon),
# compila e instala o app, confere a API — e pede a senha UMA vez.
#
#   Remoto:  curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s -- [opções]
#   Local:   ./river-bridge-install.sh [opções]
#
#   --dry-run        pré-voo e plano; nada é baixado, escrito ou instalado
#   --yes            não pergunta [s/N] (a senha do sudo continua sendo do sudo)
#   --install-deps   autoriza instalar o Homebrew (oficial, NONINTERACTIVE) se faltar
#   --no-app         não compila/instala o River Bridge.app
#   --src DIR        usa uma árvore local do repo em vez de baixar (bancada/gate)
#   --no-anim        sem abertura animada · --demo  só a abertura
#   --lang pt|en     idioma (default: locale do Mac)
#
# Distribuição: um arquivo só. A camada visual (calha + motor de meio-bloco) é a
# dos instaladores irmãos da casa (ont-stick-setup/lib/ont-ui.sh, copiada em
# ABHOME-macmini/macmini-backup.sh) com uma cena própria: o escudo do app.
# O trabalho privilegiado (brew, /usr/local, LaunchDaemon, kickstart) fica TODO
# dentro de `sudo scripts/install.sh`, chamado logo após primar o sudo — por isso
# a senha é pedida uma vez e nenhum keepalive é necessário.
#
# Exit: 0 instalou/atualizou · 100 já estava tudo · 2 uso · 3 validação
#       4 dependência · 10 rede/download · 130 cancelado · 1 falha
# =============================================================================
# shellcheck disable=SC2034  # paleta e glifos são globais da camada visual
set -Eeuo pipefail
RBI_VERSION="0.1.0"
E_USO=2; E_VALID=3; E_DEP=4; E_CONEXAO=10; E_FALHA=1; E_CANCEL=130
_src="${BASH_SOURCE[0]:-$0}"
REPO_SLUG="aleonnet/EcoFlow-UniFi-UPS-Bridge"
RUB_RAW_URL="${RUB_RAW_URL:-https://raw.githubusercontent.com/$REPO_SLUG/main/river-bridge-install.sh}"
RUB_SRC_URL="${RUB_SRC_URL:-https://github.com/$REPO_SLUG/archive/refs/heads/main.tar.gz}"
RUB_SRC_SHA256="${RUB_SRC_SHA256:-}"          # pino opcional do tarball (release)
SRC_DIR="${RUB_SRC_DIR:-}"                      # árvore local (seam do gate / bancada)
CACHE_DIR="${RUB_CACHE_DIR:-$HOME/Library/Caches/river-unifi-bridge}"
STATE_DIR="${RUB_STATE_DIR:-$HOME/Library/Application Support/river-unifi-bridge}"
PREFIX="${RUB_PREFIX:-/usr/local/river-unifi-bridge}"
LABEL_BRIDGE="com.river.unifi-bridge"
APP_DEST="${RUB_APP_DEST:-$HOME/Applications/River Bridge.app}"
API_PORT="${RUB_API_PORT:-35493}"
SUDO_CMD="${RUB_SUDO-sudo}"
SERVICO_VERSAO=""                               # lida de /v1/version na verificação                     # RUB_SUDO="" no gate (stubs, sem root)
TTY_DEV="${TTY_DEV:-/dev/tty}"                  # prompts leem daqui, nunca do stdin (curl | bash)
OP_DRYRUN=0; OP_YES=0; OP_DEPS=0; OP_NOAPP=0; OP_DEMO=0; OP_NOOPEN=0
FEZ=0; PASSOS_FEITOS=""; FASE_ATUAL=""; MAIN_INICIADO=0; PORTOES_ABERTOS=0

# ── idioma: pt-BR/en-US pela locale do Mac; --lang força ─────────────────────
IDIOMA="en"
case "${LANG:-}${LC_ALL:-}" in *pt_BR*|*pt_PT*|*pt*) IDIOMA="pt" ;; esac
case "${LC_ALL:-${LANG:-}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*)
  [ "$IDIOMA" = "en" ] && case "$(defaults read -g AppleLocale 2>/dev/null || true)" in pt*) IDIOMA="pt" ;; esac ;;
esac
msg() { # <chave> [args...] — registros chave|pt|en, formato printf
  local chave="$1"; shift
  local linha pt en
  for linha in "${MSG_DB[@]}"; do
    case "$linha" in "$chave|"*)
      linha="${linha#*|}"; pt="${linha%%|*}"; en="${linha#*|}"
      # `printf --` é obrigatório: mensagem que começa com "--" seria lida como opção
      if [ "$IDIOMA" = "pt" ]; then printf -- "$pt" "$@"; else printf -- "$en" "$@"; fi
      return 0 ;;
    esac
  done
  printf '%s' "$chave"
}
MSG_DB=(
"titulo|River Bridge|River Bridge"
"subtitulo|EcoFlow RIVER 3 Plus → NUT → UniFi, em um comando|EcoFlow RIVER 3 Plus → NUT → UniFi, in one command"
"opcao_desconhecida|opção desconhecida: %s (veja --help)|unknown option: %s (see --help)"
"flag_sem_valor|%s exige um valor|%s requires a value"
"lang_invalido|--lang aceita pt ou en|--lang accepts pt or en"
"fase_prevoo|Pré-voo|Pre-flight"
"fase_fonte|Código-fonte|Source code"
"fase_servico|Serviço (LaunchDaemon)|Service (LaunchDaemon)"
"fase_app|River Bridge.app|River Bridge.app"
"fase_verificacao|Verificação|Verification"
"nao_macos|este instalador é para macOS (launchd, Homebrew, .app)|this installer is for macOS (launchd, Homebrew, .app)"
"macos_ok|macOS %s · %s · v%s|macOS %s · %s · v%s"
"dry_aviso|DRY-RUN: só leitura — nada é baixado, escrito ou instalado|DRY-RUN: read-only — nothing is downloaded, written or installed"
"sem_ferramenta|%s ausente — faz parte do macOS; algo está errado com o sistema|%s missing — it ships with macOS; something is wrong with the system"
"brew_ok|Homebrew em %s|Homebrew at %s"
"brew_falta|Homebrew ausente — o serviço precisa dele (nut, python@3.13)|Homebrew missing — the service needs it (nut, python@3.13)"
"brew_dica|instale-o (https://brew.sh) ou rode de novo com --install-deps (instalador oficial, sem perguntas)|install it (https://brew.sh) or run again with --install-deps (official installer, no questions)"
"brew_instalando|instalando o Homebrew (instalador oficial, NONINTERACTIVE)|installing Homebrew (official installer, NONINTERACTIVE)"
"brew_falhou|o instalador do Homebrew falhou|the Homebrew installer failed"
"swift_ok|Swift %s — o app será compilado aqui|Swift %s — the app will be built here"
"swift_falta|sem Swift/Xcode: o app não será compilado (o serviço instala normalmente); --no-app silencia|no Swift/Xcode: the app will not be built (the service installs normally); --no-app silences this"
"sudo_pede|o sudo vai pedir sua senha UMA vez (quem pergunta é o sudo; o instalador não guarda nem repassa)|sudo will ask for your password ONCE (sudo asks; the installer never stores or forwards it)"
"sudo_sem_tty|sem terminal para o sudo — rode num terminal interativo, ou 'sudo -v' antes|no terminal for sudo — run in an interactive terminal, or 'sudo -v' first"
"sudo_recusado|sudo recusado|sudo refused"
"sem_sudo|sudo ausente|sudo missing"
"fonte_local|árvore local: %s|local tree: %s"
"fonte_local_invalida|%s não parece a árvore do repo (falta scripts/install.sh)|%s does not look like the repo tree (scripts/install.sh missing)"
"fonte_baixando|baixando o código de %s|downloading the code from %s"
"fonte_dry|(dry-run) baixaria %s para %s e extrairia em %s|(dry-run) would download %s to %s and extract it under %s"
"fonte_falhou|download falhou (%s) — repositório privado, sem rede ou URL errada; use --src DIR ou RUB_SRC_URL|download failed (%s) — private repository, no network or wrong URL; use --src DIR or RUB_SRC_URL"
"fonte_sha_div|SHA-256 do tarball diverge do pino RUB_SRC_SHA256 — recusado|tarball SHA-256 differs from the RUB_SRC_SHA256 pin — refused"
"fonte_sha|tarball %s · sha256 %s|tarball %s · sha256 %s"
"fonte_cache|código já no cache (%s)|code already cached (%s)"
"fonte_extraida|código em %s|code at %s"
"fonte_sem_install|o tarball não trouxe scripts/install.sh — árvore inesperada|the tarball has no scripts/install.sh — unexpected tree"
"servico_dry|(dry-run) plano do instalador do serviço:|(dry-run) service installer plan:"
"servico_dry_remoto|scripts/install.sh --dry-run (após baixar o código-fonte)|scripts/install.sh --dry-run (after downloading the source)"
"servico_rodando|sudo scripts/install.sh --consent-homebrew (brew nut + python, código, venv, config, LaunchDaemon)|sudo scripts/install.sh --consent-homebrew (brew nut + python, code, venv, config, LaunchDaemon)"
"servico_ok|serviço instalado/atualizado|service installed/updated"
"servico_ja|serviço já estava atual|service already up to date"
"servico_falhou|scripts/install.sh falhou (exit %s) — cauda:|scripts/install.sh failed (exit %s) — tail:"
"app_dry|(dry-run) compilaria com swift build -c release e instalaria em %s se o binário mudasse|(dry-run) would build with swift build -c release and install to %s if the binary changed"
"app_pulado|app pulado (--no-app)|app skipped (--no-app)"
"app_compilando|swift build -c release (primeira vez pode levar alguns minutos)|swift build -c release (the first time may take a few minutes)"
"app_falhou|compilação do app falhou — cauda:|app build failed — tail:"
"app_ja|app já está atual em %s|app already current at %s"
"app_instalado|app instalado em %s|app installed at %s"
"app_reaberto|app estava aberto: fechado e reaberto com a versão nova|app was open: closed and reopened with the new version"
"verif_dry|(dry-run) aqui eu esperaria a API local em 127.0.0.1:%s e leria /v1/version e /v1/health|(dry-run) here I would wait for the local API on 127.0.0.1:%s and read /v1/version and /v1/health"
"verif_esperando|esperando a API local (127.0.0.1:%s)|waiting for the local API (127.0.0.1:%s)"
"verif_sem_api|a API local não respondeu em %s s — veja %s|the local API did not answer in %s s — see %s"
"verif_sem_token|token da API ainda não existe (%s) — o serviço não subiu?|API token does not exist yet (%s) — did the service start?"
"verif_ok|serviço v%s · NUT %s · UDR7 %s · UniFi %s|service v%s · NUT %s · UDR7 %s · UniFi %s"
"verif_pulada|verificação pulada (RUB_SKIP_HEALTH=1)|verification skipped (RUB_SKIP_HEALTH=1)"
"confirmar|Instalar/atualizar o River Bridge nesta máquina?|Install/update River Bridge on this machine?"
"sn_prompt|[s/N] |[y/N] "
"sem_tty_confirmar|sem terminal para confirmar — use --yes|no terminal to confirm — use --yes"
"cancelado|cancelado; nada foi alterado|cancelled; nothing was changed"
"dry_fim|dry-run concluído — nada foi alterado · %s portão(ões) aberto(s)|dry-run finished — nothing was changed · %s gate(s) open"
"rel_titulo|Feito até aqui|Done so far"
"rel_titulo_ja|Nada a fazer — tudo já estava no lugar|Nothing to do — everything was already in place"
"rel_tempo|concluído em %s|done in %s"
"rel_instalado|O que ficou instalado nesta máquina:|Installed on this machine:"
"rel_i_servico|o serviço river-unifi-bridge%s — LaunchDaemon com.river.unifi-bridge, lendo o NUT em 127.0.0.1|the river-unifi-bridge service%s — LaunchDaemon com.river.unifi-bridge, reading NUT at 127.0.0.1"
"rel_i_app|o app River Bridge — %s|the River Bridge app — %s"
"rel_i_config|sua configuração — %s/etc/bridge.env (edite pelo app → Ajustes)|your configuration — %s/etc/bridge.env (edit via the app → Settings)"
"rel_norte|O River Bridge está na sua barra de menus.|River Bridge is in your menu bar."
"rel_abrindo|abrindo o app…|opening the app…"
"rel_sem_app|o app não foi instalado nesta execução (--no-app ou sem Swift); o serviço já está no ar.|the app was not installed in this run (--no-app or no Swift); the service is already up."
"rel_udr7|a proteção do UDR7 nasce em ENSAIO — nada é enviado ao console até você armar; passo a passo em docs/UDR7_PROTECAO_SSH_20260901.md|UDR7 protection starts in REHEARSAL — nothing is sent to the console until you arm it; step by step in docs/UDR7_PROTECAO_SSH_20260901.md"
"prox_log|relatório desta execução: %s|this run's report: %s"
"interrompido|interrompido na fase: %s (exit %s)|interrupted in phase: %s (exit %s)"
"reexecutar_seguro|reexecutar é seguro: cada fase confere o estado e continua de onde parou|re-running is safe: each phase checks the state and continues where it stopped"
"portao|portão aberto (só avisa em dry-run): %s|gate open (warn-only in dry-run): %s"
)

# =============================================================================
# CAMADA VISUAL — calha e motor de meio-bloco (ont-stick-setup/lib/ont-ui.sh via
# ABHOME-macmini/macmini-backup.sh, prefixo UI_/ui_). Só a CENA é nova.
# =============================================================================
UI_ANIM=1
if [ ! -t 1 ]; then UI_ANIM=0; fi
if [ -n "${NO_COLOR:-}" ]; then UI_ANIM=0; fi
if [ "${UI_NO_ANIM:-0}" = "1" ]; then UI_ANIM=0; fi
# Sob locale C o bash fatia BYTES: ${s:i:1} devolveria um terço de um caractere.
UI_UTF8=0
if [ "$(LC_ALL="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" /bin/bash -c 's=▟▙; printf %s "${#s}"' 2>/dev/null)" = "2" ]; then UI_UTF8=1; fi
if [ "$UI_UTF8" = "0" ]; then UI_ANIM=0; fi
case "${COLORTERM:-}" in
  truecolor|24bit) UI_DEPTH=24 ;;
  *) if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]; then UI_DEPTH=8; else UI_DEPTH=0; fi ;;
esac
if [ ! -t 1 ]; then UI_DEPTH=0; fi
if [ -n "${NO_COLOR:-}" ]; then UI_DEPTH=0; fi
if [ "${TERM:-dumb}" = "dumb" ]; then UI_DEPTH=0; UI_ANIM=0; fi

rgb()   { case "$UI_DEPTH" in 24) printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3" ;; 8) printf '\033[38;5;%dm' $(( 16 + 36*($1*5/255) + 6*($2*5/255) + ($3*5/255) )) ;; *) printf '' ;; esac; }
rgbbg() { case "$UI_DEPTH" in 24) printf '\033[48;2;%d;%d;%dm' "$1" "$2" "$3" ;; 8) printf '\033[48;5;%dm' $(( 16 + 36*($1*5/255) + 6*($2*5/255) + ($3*5/255) )) ;; *) printf '' ;; esac; }
if [ "$UI_DEPTH" = "0" ]; then NC=''; BOLD=''; DIM=''; else NC=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; fi
C_CYAN="$(rgb 34 211 238)";  C_ICE="$(rgb 190 242 255)";  C_DEEP="$(rgb 8 74 90)"
C_AMBER="$(rgb 245 176 0)";  C_GREEN="$(rgb 74 222 128)"; C_RED="$(rgb 244 63 94)"
C_MUTED="$(rgb 100 116 139)"; C_WHITE="$(rgb 255 255 255)"

if [ "$UI_UTF8" = "1" ]; then
  UI_G_OK='✔'; UI_G_INFO='•'; UI_G_WARN='▲'; UI_G_ERR='✖'; UI_G_SKIP='◦'
  UI_G_DOTS='…'; UI_G_REGUA='─'; UI_G_SEP='·'; UI_G_DASH='—'; UI_G_SETA='→'; UI_G_PASSO='▸'
  UI_G_GUT='│'; UI_G_ASK='?'; UI_G_RAMO='├──'; UI_G_FIM='╰'
  UI_G_BON='▰'; UI_G_BOFF='▱'; UI_G_CHEIO='━'; UI_G_VAZIO='╌'
  UI_G_TOPO='▀'; UI_G_BAIXO='▄'
  UI_SPIN_F='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; UI_SPIN_N=10
else
  UI_G_OK='[OK]'; UI_G_INFO='[i]'; UI_G_WARN='[!]'; UI_G_ERR='[X]'; UI_G_SKIP='[-]'
  UI_G_DOTS='...'; UI_G_REGUA='-'; UI_G_SEP='-'; UI_G_DASH='--'; UI_G_SETA='->'; UI_G_PASSO='>'
  UI_G_GUT='|'; UI_G_ASK='?'; UI_G_RAMO='+--'; UI_G_FIM='+'
  UI_G_BON='#'; UI_G_BOFF='-'; UI_G_CHEIO='#'; UI_G_VAZIO='-'
  UI_G_TOPO='#'; UI_G_BAIXO='#'
  UI_SPIN_F='-\|/'; UI_SPIN_N=4
fi
UI_GUT="${C_MUTED}${UI_G_GUT}${NC} "

_ui_hide() { if [ "$UI_ANIM" = "1" ]; then printf '\033[?25l'; fi; return 0; }
_ui_show() { if [ "$UI_ANIM" = "1" ]; then printf '\033[?25h'; fi; return 0; }
ui_show_cursor() { _ui_show; }

ui_grad() { # <texto> r g b  r g b  [r g b ...]
  local s="$1"; shift
  local n=${#s} np=$(( $# / 3 )) i seg t k r g b out=''
  [ "$n" -eq 0 ] && return 0
  if [ "$UI_DEPTH" = "0" ] || [ "$UI_UTF8" = "0" ] || [ "$np" -lt 2 ]; then printf '%s' "$s"; return 0; fi
  local P=("$@")
  for (( i = 0; i < n; i++ )); do
    t=$(( i * (np - 1) * 100 / (n > 1 ? n - 1 : 1) ))
    seg=$(( t / 100 )); [ "$seg" -ge $(( np - 1 )) ] && seg=$(( np - 2 ))
    k=$(( t - seg * 100 ))
    r=$(( P[seg*3]   + (P[(seg+1)*3]   - P[seg*3])   * k / 100 ))
    g=$(( P[seg*3+1] + (P[(seg+1)*3+1] - P[seg*3+1]) * k / 100 ))
    b=$(( P[seg*3+2] + (P[(seg+1)*3+2] - P[seg*3+2]) * k / 100 ))
    out+="$(rgb "$r" "$g" "$b")${s:$i:1}"
  done
  printf '%s%s' "$out" "$NC"
}
ui_gradient() { ui_grad "$1" 8 74 90  34 211 238  190 242 255; }
ui_shimmer() { # brilho que varre uma vez e assenta no gradiente
  local s="$1" n=${#1} p i out d
  if [ "$UI_ANIM" = "0" ] || [ "$UI_DEPTH" = "0" ]; then printf '%s%s%s\n' "$BOLD" "$s" "$NC"; return 0; fi
  _ui_hide
  for (( p = -6; p <= n + 6; p += 2 )); do
    out=''
    for (( i = 0; i < n; i++ )); do
      d=$(( i > p ? i - p : p - i ))
      if [ "$d" -le 2 ]; then out+="${BOLD}${C_WHITE}${s:$i:1}"
      elif [ "$d" -le 5 ]; then out+="${C_ICE}${s:$i:1}"
      else out+="${C_CYAN}${s:$i:1}"; fi
    done
    printf '\r%s%s' "$out" "$NC"; sleep 0.012
  done
  printf '\r%s%s\n' "$BOLD" "$(ui_gradient "$s")"
  _ui_show
}
ui_rule() {
  local w; w=$(tput cols 2>/dev/null || echo 72); case "$w" in ''|*[!0-9]*) w=72 ;; esac
  [ "$w" -gt 78 ] && w=78
  local line=''; printf -v line '%*s' "$w" ''; line=${line// /$UI_G_REGUA}
  printf '%s\n' "$(ui_gradient "$line")"
}
UI_BAR_TOTAL=0; UI_BAR_N=0; UI_BAR_VISIVEL=0; UI_BAR_SUSPENSA=0
ui_bar_limpa()    { if [ "$UI_BAR_VISIVEL" = "1" ]; then printf '\r\033[2K'; UI_BAR_VISIVEL=0; fi; return 0; }
ui_bar_suspende() { ui_bar_limpa; UI_BAR_SUSPENSA=1; }
ui_bar_retoma()   { UI_BAR_SUSPENSA=0; ui_bar_mostra; }
ui_bar_mostra() {
  [ "${UI_BAR_SUSPENSA:-0}" = "0" ] || return 0
  [ "$UI_ANIM" = "1" ] && [ "$UI_BAR_TOTAL" -gt 0 ] && [ "$UI_BAR_N" -gt 0 ] || return 0
  local w=20 f i out=''
  f=$(( UI_BAR_N * w / UI_BAR_TOTAL ))
  for (( i = 0; i < w; i++ )); do
    if [ "$i" -lt "$f" ]; then out+="${C_CYAN}${UI_G_BON}"; else out+="${C_MUTED}${UI_G_BOFF}"; fi
  done
  printf '%s%s%s %s%s %d/%d%s' "$UI_GUT" "$out" "$NC" "${C_MUTED}" "${UI_BAR_ROTULO:-fase}" "$UI_BAR_N" "$UI_BAR_TOTAL" "$NC"
  UI_BAR_VISIVEL=1
  return 0
}
UI_PHASE_N=0
ui_phase() {
  ui_bar_limpa
  UI_PHASE_N=$(( UI_PHASE_N + 1 ))
  local w cab pad n
  w=$(tput cols 2>/dev/null || echo 72); case "$w" in ''|*[!0-9]*) w=72 ;; esac
  [ "$w" -gt 78 ] && w=78
  printf '%s\n' "$UI_GUT"
  cab="$(printf '%02d %s ' "$UI_PHASE_N" "$1")"
  n=$(( w - ${#cab} - 4 )); [ "$n" -lt 4 ] && n=4
  printf -v pad '%*s' "$n" ''; pad=${pad// /$UI_G_REGUA}
  printf '%s%s%s %s%s\n' "${C_CYAN}" "$UI_G_RAMO" "$NC" "$(ui_gradient "$cab")" "$(ui_gradient "$pad")"
  ui_bar_mostra
}
ui_ok()    { ui_bar_limpa; printf '%s%s%s%s %s\n'  "$UI_GUT" "${C_GREEN}" "$UI_G_OK" "$NC" "$1"; ui_bar_mostra; }
ui_info()  { ui_bar_limpa; printf '%s%s%s%s %s%s%s\n' "$UI_GUT" "${C_CYAN}" "$UI_G_INFO" "$NC" "${C_MUTED}" "$1" "$NC"; ui_bar_mostra; }
ui_warn()  { ui_bar_limpa; printf '%s%s%s%s %s\n'  "$UI_GUT" "${C_AMBER}" "$UI_G_WARN" "$NC" "$1"; ui_bar_mostra; }
ui_err()   { ui_bar_limpa; printf '%s%s%s%s %s\n'  "$UI_GUT" "${C_RED}"  "$UI_G_ERR" "$NC" "$1" >&2; }
ui_skip()  { ui_bar_limpa; printf '%s%s%s%s %s%s%s\n' "$UI_GUT" "${C_MUTED}" "$UI_G_SKIP" "$NC" "$DIM" "$1" "$NC"; ui_bar_mostra; }
ui_ask()   { printf '%s%s%s%s %s' "$UI_GUT" "${C_AMBER}" "$UI_G_ASK" "$NC" "$1"; }
ui_linha() { ui_bar_limpa; printf '%s%s\n' "$UI_GUT" "$1"; ui_bar_mostra; }
ui_spin() { # ui_spin "rótulo" <pid>
  local label="$1" pid="$2" i=0 rc=0
  if [ "$UI_ANIM" = "0" ]; then
    printf '%s%s %s\n' "$UI_GUT" "$UI_G_DOTS" "$label"
    wait "$pid" || rc=$?
    return "$rc"
  fi
  ui_bar_limpa; _ui_hide
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s%s %s' "$UI_GUT" "${C_CYAN}" "${UI_SPIN_F:$(( i % UI_SPIN_N )):1}" "$NC" "$label"; i=$(( i + 1 ))
    sleep 0.07
  done
  wait "$pid" || rc=$?
  printf '\r\033[2K'; _ui_show
  if [ "$rc" = "0" ]; then ui_ok "$label"; else ui_err "$label  (exit $rc)"; fi
  return "$rc"
}

# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────
# Escudo do ícone real (tools/app-icon-render.swift) em 34×34 pixels,
# com 4 px de margem vazia para o halo e o traço não serem cortados.
# LG_MASK: . fora · s escudo (gradiente verde) · r raio (branco).
# As cores vivem no runtime, por LINHA — molde de lib/haos-ui.sh (ha_logo_init).
LG_W=34
LG_H=34
LG_CAMINHO=65
LG_Q_MONTA=21
LG_MASK=(
'..................................'
'..................................'
'..................................'
'..................................'
'..................................'
'.............sssssss..............'
'...........ssssssssssss...........'
'........sssssssssssssssss.........'
'.......sssssssssssrsssssss........'
'.......ssssssssssrrssssssss.......'
'.......sssssssssrrrssssssss.......'
'.......ssssssssrrrsssssssss.......'
'.......ssssssssrrrsssssssss.......'
'.......sssssssrrrrsssssssss.......'
'.......ssssssrrrrssssssssss.......'
'.......sssssrrrrrrrrrrsssss.......'
'.......sssssrrrrrrrrrssssss.......'
'.......ssssrrrrrrrrrsssssss.......'
'.......sssssssssrrrrsssssss.......'
'.......ssssssssrrrrssssssss.......'
'.......ssssssssrrrsssssssss.......'
'.......ssssssssrrsssssssss........'
'.......sssssssrrrsssssssss........'
'........ssssssrrsssssssss.........'
'.........sssssrssssssssss.........'
'..........sssssssssssss...........'
'...........sssssssssss............'
'.............sssssss..............'
'..............sssss...............'
'..................................'
'..................................'
'..................................'
'..................................'
'..................................'
)
LG_TX=(15 14 13 12 11 10 9 8 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 26 26 26 26 26 26 26 26 26 26 26 25 25 24 24 23 22 21 20 19 18 17 16)
LG_TY=(28 28 27 26 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 7 7 6 6 5 5 5 5 5 5 5 6 6 6 7 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 24 25 26 26 27 28 28 28)
LG_AX=(13 14 15 16 17 18 19 11 12 13 14 15 16 17 18 19 20 21 22 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 10 11 12 13 14 15 16 17 18 19 20 21 22 11 12 13 14 15 16 17 18 19 20 21 13 14 15 16 17 18 19 14 15 16 17 18)
LG_AY=(5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 25 25 25 25 25 25 25 25 25 25 25 25 25 26 26 26 26 26 26 26 26 26 26 26 27 27 27 27 27 27 27 28 28 28 28 28)
LG_AOX=(28 31 34 37 40 43 45 25 28 28 31 34 37 40 43 46 49 51 45 15 17 20 22 26 29 33 36 35 38 41 44 47 49 51 53 54 12 14 16 18 21 24 28 32 36 35 38 41 44 47 49 51 53 55 47 10 12 14 16 19 22 26 31 31 35 39 43 46 49 51 53 55 47 48 49 7 9 11 13 16 20 23 27 31 36 41 45 49 51 54 47 48 49 50 51 4 6 8 10 14 17 21 26 31 37 42 47 51 46 48 49 50 51 52 53 1 2 7 8 10 14 18 23 30 37 44 43 46 48 50 51 52 53 53 54 1 2 3 4 6 9 13 19 28 33 40 46 49 51 52 53 53 54 46 46 -1 -1 -1 0 1 3 7 14 21 32 43 49 52 53 53 54 45 46 46 47 -5 -5 -5 -5 -4 0 2 6 14 29 47 53 54 53 45 45 46 46 46 47 -9 -10 -10 -4 -5 -5 -5 -4 -1 13 54 52 43 43 44 44 45 45 46 47 -13 -7 -8 -9 -10 -11 -13 -15 -17 -21 19 33 37 39 40 42 43 44 45 39 -10 -11 -12 -13 -15 -17 -18 -21 -13 -9 5 19 28 33 36 38 40 36 37 38 -13 -14 -16 -17 -19 -20 -13 -14 -13 -9 0 11 20 26 30 30 32 34 35 36 -16 -17 -19 -20 -13 -14 -15 -15 -13 -9 -2 6 13 19 23 26 29 31 33 35 -19 -20 -13 -14 -15 -16 -16 -16 -14 -10 -4 5 11 15 19 23 26 28 31 -21 -13 -14 -15 -16 -16 -16 -16 -13 -10 0 3 8 12 16 20 23 25 28 -13 -14 -15 -16 -16 -16 -15 -13 -10 0 2 6 10 13 17 20 22 -21 -13 -13 -13 -13 -12 -10 -8 -5 -1 5 8 11 14 17 20 -18 -18 -18 -10 -9 -7 -6 -3 0 2 5 8 13 -12 -12 -12 -11 -9 -7 -5 -2 3 6 8 -11 -10 -9 -7 -5 -3 3 -7 -7 -5 -4 -2)
LG_AOY=(-11 -10 -10 -9 -8 -7 -5 -19 -19 -11 -11 -10 -9 -8 -6 -4 -2 0 5 -14 -15 -16 -17 -17 -17 -17 -16 -7 -6 -4 -2 0 2 4 6 9 -13 -14 -15 -16 -17 -17 -17 -17 -16 -7 -5 -3 -1 0 3 6 8 11 14 -13 -15 -16 -17 -18 -19 -19 -18 -9 -8 -6 -4 -1 1 5 8 10 14 16 17 -15 -16 -18 -19 -20 -21 -12 -12 -12 -10 -7 -4 0 3 6 11 14 16 18 20 -16 -17 -19 -21 -13 -14 -15 -15 -14 -12 -8 -4 0 7 11 14 16 19 21 23 -17 -18 -11 -13 -15 -16 -17 -17 -17 -14 -9 0 5 10 14 17 20 22 24 26 -9 -10 -12 -14 -15 -17 -19 -20 -19 -8 -4 2 8 13 18 21 24 26 26 27 -9 -10 -12 -14 -16 -18 -20 -13 -14 -11 -4 5 13 19 24 27 26 28 30 31 -9 -10 -11 -13 -14 -9 -11 -13 -16 -15 -1 13 22 28 28 30 31 33 34 35 -7 -8 -9 -4 -5 -6 -8 -10 -13 -19 13 31 31 33 35 36 37 38 38 39 -6 -1 -1 -1 -2 -2 -1 0 3 20 47 43 42 42 42 42 42 43 43 37 0 0 0 1 2 3 6 10 19 33 47 50 49 48 48 47 47 40 41 41 2 3 3 5 6 9 14 19 27 38 47 52 53 53 53 44 44 44 44 45 4 5 7 9 12 15 19 25 32 40 48 52 55 47 47 48 48 48 48 48 7 8 12 14 16 19 24 29 36 42 49 45 48 49 50 50 51 51 51 10 13 14 17 19 23 27 32 38 44 42 45 48 50 51 52 53 53 53 15 17 19 22 26 30 34 39 44 41 45 47 49 51 52 53 54 20 21 24 27 31 35 39 43 47 50 45 47 49 50 51 52 24 28 31 31 34 37 41 44 47 50 52 54 47 27 30 33 36 40 43 47 50 44 46 48 34 37 40 43 46 49 44 36 39 41 44 47)
LG_ADL=(11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 0 1 2 0 1 2 0 1 2 0 1 2)
LG_HX=(12 13 14 15 16 17 18 19 20 10 11 12 20 21 22 23 7 8 9 10 23 24 25 6 7 25 26 6 26 27 6 27 6 27 6 27 6 27 6 27 6 27 6 27 6 27 6 27 6 27 6 27 6 27 6 26 27 6 26 6 7 25 26 7 8 25 8 9 23 24 25 9 10 22 23 10 11 12 20 21 22 12 13 19 20 13 14 15 16 17 18 19)
LG_HY=(4 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 6 6 6 6 6 6 6 7 7 7 7 8 8 8 9 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 21 22 22 23 23 23 23 24 24 24 25 25 25 25 25 26 26 26 26 27 27 27 27 27 27 28 28 28 28 29 29 29 29 29 29 29)
# =============================================================================
# A ABERTURA — o escudo do app, pixel a pixel. Molde: lib/haos-ui.sh do
# haos-install (mesmas medidas, mesma gramática), com a identidade daqui:
# lá a casa é AZUL com o circuito BRANCO; aqui o escudo é VERDE com o raio
# BRANCO. Nada de azul.
#
# Quatro atos, nas medidas do molde (22 · 34 · 20 quadros, 0,03 s cada):
#   1. CONSTELAÇÃO — cada pixel do escudo é uma partícula que voa de fora da
#      tela em trajetória radial (giro de 40°) e ASSENTA no lugar, de baixo
#      para cima. Trajetórias pré-computadas pelo gerador; o runtime interpola.
#   2. O TRAÇO — a caneta branca contorna o escudo inteiro e se retrai, por
#      posição de arco.
#   3. O CORAÇÃO — o escudo bate: "tum-tum", pausa. A cada batida o verde
#      clareia e o RAIO PISCA; entre as batidas ele volta ao branco.
#   4. Assenta: escudo verde, raio branco parado.
#
# O corpo tem GRADIENTE VERTICAL (mais claro no topo): volume, não sprite —
# como o azul do molde. As cores saem do próprio ícone (app-icon-render.swift):
# glow (0.15,0.90,0.70) = 38,230,178 no topo; fundo (0.10,0.65,0.55) = 26,166,140
# na base. O raio usa o mesmo branco do detalhe do molde (236,242,248).
#
# Sem animação: o quadro final parado. Sem UTF-8 ou sem cor: só o título.
# Desenho: uma máscara mutável (QM, uma string por linha de pixel) e um render
# que pinta as classes. Célula = 2 pixels ("▀": frente em cima, fundo embaixo).
# Classes: . fora · s escudo · r raio · t traço · a partícula · g pisca.
# =============================================================================
LG_ATRASO=0.03; LG_A_DUR=8; LG_Q_TRACO=34; LG_Q_BATE=20
LG_QUADROS=$(( LG_Q_MONTA + LG_Q_TRACO + LG_Q_BATE ))
LG_LINHAS=$(( LG_H / 2 )); LG_MIN_COLS=$(( LG_W + 2 ))
lg_init() {
  [ -n "${LG_PRONTO:-}" ] && return 0
  local y t r g b e
  # Gradiente vertical do escudo: um escape de frente e um de fundo POR LINHA,
  # pré-computados uma vez (molde: ha_logo_init).
  LG_FGA=(); LG_BGA=()
  for (( y = 0; y < LG_H; y++ )); do
    t=$(( y * 100 / (LG_H - 1) ))
    r=$(( 38 + (26 - 38) * t / 100 ))
    g=$(( 230 + (166 - 230) * t / 100 ))
    b=$(( 178 + (140 - 178) * t / 100 ))
    if [ "$UI_DEPTH" = "24" ]; then
      printf -v e '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"; LG_FGA[y]="$e"
      printf -v e '\033[48;2;%d;%d;%dm' "$r" "$g" "$b"; LG_BGA[y]="$e"
    else
      e=$(( 16 + 36*(r*5/255) + 6*(g*5/255) + (b*5/255) ))
      printf -v LG_FGA[y] '\033[38;5;%dm' "$e"; printf -v LG_BGA[y] '\033[48;5;%dm' "$e"
    fi
  done
  LG_FG_BRANCO="$(rgb 236 242 248)"; LG_BG_BRANCO="$(rgbbg 236 242 248)"   # raio
  LG_FG_TRACO="$(rgb 255 255 255)";  LG_BG_TRACO="$(rgbbg 255 255 255)"    # caneta
  LG_FG_A="$(rgb 190 255 232)";      LG_BG_A="$(rgbbg 38 230 178)"         # partícula
  LG_FG_G="$(rgb 38 230 178)";       LG_BG_G="$(rgbbg 38 230 178)"         # pisca
  printf -v LG_QM_VAZIA '%*s' "$LG_W" ''; LG_QM_VAZIA="${LG_QM_VAZIA// /.}"
  LG_PRONTO=1
}
lg_qm_vazio() { local y; QM=(); for (( y = 0; y < LG_H; y++ )); do QM[y]="$LG_QM_VAZIA"; done; }
lg_qm_cheio() { local y; QM=(); for (( y = 0; y < LG_H; y++ )); do QM[y]="${LG_MASK[y]}"; done; }
lg_qm_poe() { # <x> <y> <classe>
  [ "$2" -ge 0 ] && [ "$2" -lt "$LG_H" ] && [ "$1" -ge 0 ] && [ "$1" -lt "$LG_W" ] || return 0
  QM[$2]="${QM[$2]:0:$1}$3${QM[$2]:$(( $1 + 1 ))}"
}
# Pinta o par de classes de uma célula. `y1` dá a linha do gradiente.
lg_render() {
  local y1 y2 x c1 c2 saida fa1 fa2 fa2bg
  for (( y1 = 0; y1 < LG_H; y1 += 2 )); do
    y2=$(( y1 + 1 )); saida='  '
    fa1="${LG_FGA[y1]}"; fa2="${LG_FGA[y2]}"; fa2bg="${LG_BGA[y2]}"
    for (( x = 0; x < LG_W; x++ )); do
      c1="${QM[y1]:x:1}"; c2="${QM[y2]:x:1}"
      case "$c1$c2" in
        '..') saida+="${NC} " ;;
        '.s') saida+="${NC}${fa2}${UI_G_BAIXO}" ;;
        's.') saida+="${NC}${fa1}${UI_G_TOPO}" ;;
        'ss') saida+="${fa1}${fa2bg}${UI_G_TOPO}" ;;
        '.r') saida+="${NC}${LG_FG_BRANCO}${UI_G_BAIXO}" ;;
        'r.') saida+="${NC}${LG_FG_BRANCO}${UI_G_TOPO}" ;;
        'rr') saida+="${LG_FG_BRANCO}${LG_BG_BRANCO}${UI_G_TOPO}" ;;
        'sr') saida+="${fa1}${LG_BG_BRANCO}${UI_G_TOPO}" ;;
        'rs') saida+="${LG_FG_BRANCO}${fa2bg}${UI_G_TOPO}" ;;
        '.t') saida+="${NC}${LG_FG_TRACO}${UI_G_BAIXO}" ;;
        't.') saida+="${NC}${LG_FG_TRACO}${UI_G_TOPO}" ;;
        'tt') saida+="${LG_FG_TRACO}${LG_BG_TRACO}${UI_G_TOPO}" ;;
        'st') saida+="${fa1}${LG_BG_TRACO}${UI_G_TOPO}" ;;
        'ts') saida+="${LG_FG_TRACO}${fa2bg}${UI_G_TOPO}" ;;
        'rt') saida+="${LG_FG_BRANCO}${LG_BG_TRACO}${UI_G_TOPO}" ;;
        'tr') saida+="${LG_FG_TRACO}${LG_BG_BRANCO}${UI_G_TOPO}" ;;
        '.a') saida+="${NC}${LG_FG_A}${UI_G_BAIXO}" ;;
        'a.') saida+="${NC}${LG_FG_A}${UI_G_TOPO}" ;;
        'aa') saida+="${LG_FG_A}${LG_BG_A}${UI_G_TOPO}" ;;
        'as') saida+="${LG_FG_A}${fa2bg}${UI_G_TOPO}" ;;
        'sa') saida+="${fa1}${LG_BG_A}${UI_G_TOPO}" ;;
        'ar') saida+="${LG_FG_A}${LG_BG_BRANCO}${UI_G_TOPO}" ;;
        'ra') saida+="${LG_FG_BRANCO}${LG_BG_A}${UI_G_TOPO}" ;;
        '.g') saida+="${NC}${LG_FG_G}${UI_G_BAIXO}" ;;
        'g.') saida+="${NC}${LG_FG_G}${UI_G_TOPO}" ;;
        'gg') saida+="${LG_FG_G}${LG_BG_G}${UI_G_TOPO}" ;;
        'gs') saida+="${LG_FG_G}${fa2bg}${UI_G_TOPO}" ;;
        'sg') saida+="${fa1}${LG_BG_G}${UI_G_TOPO}" ;;
        'gr') saida+="${LG_FG_G}${LG_BG_BRANCO}${UI_G_TOPO}" ;;
        'rg') saida+="${LG_FG_BRANCO}${LG_BG_G}${UI_G_TOPO}" ;;
        *)    saida+="${NC} " ;;
      esac
    done
    printf '%s%s\n' "$saida" "$NC"
  done
}
# lg_quadro <n> — compõe e imprime o quadro n; n < 0: o quadro final parado.
lg_quadro() {
  local n="$1" i t x y k d total meio cabeca cauda
  lg_init
  if [ "$n" -lt 0 ]; then lg_qm_cheio; lg_render; return 0; fi

  if [ "$n" -lt "$LG_Q_MONTA" ]; then
    # ── ato 1: constelação ──────────────────────────────────────────────────
    lg_qm_vazio
    total=${#LG_AX[@]}
    for (( i = 0; i < total; i++ )); do
      d=${LG_ADL[i]}
      if [ "$n" -ge $(( d + LG_A_DUR )) ]; then
        x=${LG_AX[i]}; y=${LG_AY[i]}
        lg_qm_poe "$x" "$y" "${LG_MASK[y]:x:1}"      # assenta na própria classe
      elif [ "$n" -ge "$d" ]; then
        t=$(( (n - d) * 100 / LG_A_DUR ))
        x=$(( LG_AOX[i] + (LG_AX[i] - LG_AOX[i]) * t / 100 ))
        y=$(( LG_AOY[i] + (LG_AY[i] - LG_AOY[i]) * t / 100 ))
        lg_qm_poe "$x" "$y" a
      fi
    done
    lg_render; return 0
  fi

  if [ "$n" -lt $(( LG_Q_MONTA + LG_Q_TRACO )) ]; then
    # ── ato 2: o traço contorna e retrai, por posição de arco ───────────────
    lg_qm_cheio
    k=$(( n - LG_Q_MONTA )); meio=$(( LG_Q_TRACO / 2 ))
    if [ "$k" -lt "$meio" ]; then cabeca=$(( k * LG_CAMINHO / meio )); cauda=0
    else cabeca=$LG_CAMINHO; cauda=$(( (k - meio) * LG_CAMINHO / meio )); fi
    for (( i = cauda; i < cabeca; i++ )); do lg_qm_poe "${LG_TX[i]}" "${LG_TY[i]}" t; done
    lg_render; return 0
  fi

  # ── ato 3: o coração — tum-tum, pausa; o raio pisca e volta ao branco ────
  k=$(( n - LG_Q_MONTA - LG_Q_TRACO ))
  lg_qm_cheio
  case "$k" in
    0|1|2|4|5|6)
      # batida: o verde clareia e o raio pisca (vira o verde vivo)
      for (( y = 0; y < LG_H; y++ )); do QM[y]="${QM[y]//r/g}"; done
      if [ "$k" = "1" ] || [ "$k" = "5" ]; then          # pico: o halo acende
        total=${#LG_HX[@]}
        for (( i = 0; i < total; i++ )); do lg_qm_poe "${LG_HX[i]}" "${LG_HY[i]}" g; done
      fi
      ;;
  esac
  lg_render
}
ui_banner() {
  local t="${1:-River Bridge}" s="${2:-}" cols n
  cols="$(tput cols 2>/dev/null || echo 0)"; case "$cols" in ''|*[!0-9]*) cols=0 ;; esac
  # Sem UTF-8 os glifos sairiam partidos; sem cor o escudo vira mancha.
  if [ "$UI_UTF8" = "0" ] || [ "$UI_DEPTH" = "0" ]; then printf '  %s\n' "$t"; [ -n "$s" ] && printf '  %s\n' "$s"; printf '\n'; return 0; fi
  # Terminal estreito ou sem animação: UM quadro, tudo assentado. Nunca meia
  # animação, e nada que o movimento mostre existe só nele.
  if [ "$UI_ANIM" = "0" ] || [ "$cols" -lt "$LG_MIN_COLS" ]; then
    lg_quadro -1
    printf '\n  %s%s%s\n' "$BOLD" "$(ui_gradient "$t")" "$NC"; [ -n "$s" ] && printf '  %s%s%s\n' "$C_MUTED" "$s" "$NC"; printf '\n'; return 0
  fi
  _ui_hide
  for (( n = 0; n < LG_QUADROS; n++ )); do [ "$n" -gt 0 ] && { tput cuu "$LG_LINHAS" 2>/dev/null || break; }; lg_quadro "$n"; sleep "$LG_ATRASO"; done
  if tput cuu "$LG_LINHAS" 2>/dev/null; then lg_quadro -1; fi
  _ui_show; printf '\n'; ui_shimmer "  $t"
  [ -n "$s" ] && printf '  %s%s%s\n' "$C_MUTED" "$s" "$NC"; printf '\n'
}

# =============================================================================
# INFRA: prompts sob pipe, sudo uma vez, fases, trap único
# =============================================================================
tem_tty() { [ -r "$TTY_DEV" ] && [ -w "$TTY_DEV" ] || return 1; ( : <"$TTY_DEV" ) 2>/dev/null; }
morrer() { local rc="$1"; shift; ui_err "$*"; exit "$rc"; }
portao() { # <mensagem> — em dry-run só avisa e conta; fora dele, morre com E_DEP
  if [ "$OP_DRYRUN" = "1" ]; then ui_warn "$(msg portao "$1")"; PORTOES_ABERTOS=$(( PORTOES_ABERTOS + 1 )); return 0; fi
  morrer "$E_DEP" "$1"
}
confirmar() { # <pergunta> → 0 sim / 1 não
  [ "$OP_YES" = "1" ] && return 0
  tem_tty || morrer "$E_USO" "$(msg sem_tty_confirmar)"
  local ans
  ui_bar_suspende; ui_ask "$1 $(msg sn_prompt)"; IFS= read -r ans <"$TTY_DEV" || ans=""; ui_bar_retoma
  case "$ans" in s|S|y|Y) return 0 ;; *) return 1 ;; esac
}
garantir_sudo() { # a credencial é primada UMA vez, lendo o terminal de verdade
  [ -z "$SUDO_CMD" ] && return 0                 # gate: sem root, com stubs
  [ "$(id -u)" = "0" ] && return 0
  command -v sudo >/dev/null 2>&1 || morrer "$E_DEP" "$(msg sem_sudo)"
  if sudo -n true 2>/dev/null; then return 0; fi
  tem_tty || morrer "$E_USO" "$(msg sudo_sem_tty)"
  ui_bar_suspende; ui_info "$(msg sudo_pede)"
  # shellcheck disable=SC2024  # redirecionamento de ENTRADA, e é o ponto
  sudo -v <"$TTY_DEV" || { ui_bar_retoma; morrer "$E_VALID" "$(msg sudo_recusado)"; }
  ui_bar_retoma
}
ok() { ui_ok "$1"; PASSOS_FEITOS="${PASSOS_FEITOS}${1}"$'\n'; }
fmt_seg() { local t="$1"; if [ "$t" -ge 60 ]; then printf '%dm%02ds' $((t/60)) $((t%60)); else printf '%ds' "$t"; fi; }
# relatorio_final <fez 0|1> <segundos> — molde da casa (haos-install.sh, relatorio_final):
# título com o tempo na mesma linha → caixa do que ficou instalado (✔ por item) →
# o NORTE (a única coisa que o usuário faz agora: o app, aberto sozinho) → avisos → o log.
relatorio_final() {
  local fez="$1" total="$2" corpo linha regua
  ui_bar_limpa; printf '%s\n' "$UI_GUT"; printf '%s' "$UI_G_FIM"
  printf -v regua '%*s' 76 ''; printf '%s\n\n' "$(ui_gradient "${regua// /$UI_G_REGUA}")"
  if [ "$fez" = "1" ]; then ui_shimmer "  $(msg rel_titulo) ${UI_G_SEP} $(msg rel_tempo "$(fmt_seg "$total")")"
  else ui_shimmer "  $(msg rel_titulo_ja) ${UI_G_SEP} $(msg rel_tempo "$(fmt_seg "$total")")"; fi
  corpo="$(msg rel_instalado)"$'\n'
  corpo+="  ${C_GREEN}${UI_G_OK}${NC} $(msg rel_i_servico "${SERVICO_VERSAO:+ v$SERVICO_VERSAO}")"$'\n'
  [ "$OP_NOAPP" = "0" ] && [ -d "$APP_DEST" ] && corpo+="  ${C_GREEN}${UI_G_OK}${NC} $(msg rel_i_app "$APP_DEST")"$'\n'
  corpo+="  ${C_GREEN}${UI_G_OK}${NC} $(msg rel_i_config "$PREFIX")"
  if command -v gum >/dev/null 2>&1 && [ "$UI_DEPTH" != "0" ]; then
    gum style --border rounded --border-foreground "#22D3EE" --padding "0 2" "$corpo" 2>/dev/null || printf '%s\n' "$corpo"
  else
    while IFS= read -r linha; do printf '  %s\n' "$linha"; done <<< "$corpo"
  fi
  printf '\n'
  if [ "$OP_NOAPP" = "0" ] && [ -d "$APP_DEST" ]; then
    # O NORTE: o app na barra de menus — e aberto, para o usuário não procurar.
    ui_shimmer "  $(msg rel_norte)"
    if [ "$OP_NOOPEN" = "0" ] && tem_tty && command -v open >/dev/null 2>&1; then
      printf '  %s%s%s %s\n' "$C_CYAN" "$UI_G_INFO" "$NC" "$(msg rel_abrindo)"
      open "$APP_DEST" 2>/dev/null || true
    fi
  else
    printf '  %s%s%s %s\n' "$C_AMBER" "$UI_G_WARN" "$NC" "$(msg rel_sem_app)"
  fi
  printf '  %s%s%s %s\n' "$C_CYAN" "$UI_G_INFO" "$NC" "$(msg rel_udr7)"
  printf '\n  %s%s%s %s\n\n' "$C_CYAN" "$UI_G_INFO" "$NC" "$(msg prox_log "$LAST_RUN")"
  return 0
}
fase() { FASE_ATUAL="$1"; UI_BAR_N=$(( UI_BAR_N + 1 )); ui_phase "$1"; }
LAST_RUN="$STATE_DIR/installer-last-run.log"
limpar() {
  local rc=$?
  ui_bar_limpa; ui_show_cursor
  if [ "$MAIN_INICIADO" = "1" ] && [ "$OP_DRYRUN" = "0" ]; then
    { mkdir -p "$STATE_DIR" 2>/dev/null && {
        printf 'river-bridge-install.sh %s  %s\nrc=%s · fase=%s\n%s' "$RBI_VERSION" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$rc" "$FASE_ATUAL" "$PASSOS_FEITOS"
      } > "$LAST_RUN"; } 2>/dev/null || true
  fi
  if [ "$rc" != "0" ] && [ "$rc" != "100" ] && [ -n "$FASE_ATUAL" ]; then
    printf '\n' >&2; ui_err "$(msg interrompido "$FASE_ATUAL" "$rc")"; ui_info "$(msg reexecutar_seguro)" >&2
  fi
  exit "$rc"
}

# =============================================================================
# FASES — contrato 0 (fez) · 100 (já estava) · 1 (falhou)
# =============================================================================
BREW=""; SWIFT_OK=0
fase_prevoo() {
  fase "$(msg fase_prevoo)"
  [ "$(uname -s)" = "Darwin" ] || morrer "$E_VALID" "$(msg nao_macos)"
  ok "$(msg macos_ok "$(sw_vers -productVersion 2>/dev/null || echo '?')" "$(uname -m)" "$RBI_VERSION")"
  [ "$OP_DRYRUN" = "1" ] && ui_warn "$(msg dry_aviso)"
  local f
  for f in curl tar shasum; do command -v "$f" >/dev/null 2>&1 || morrer "$E_DEP" "$(msg sem_ferramenta "$f")"; done
  for f in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$f" ] && BREW="$f" && break; done
  [ -z "$BREW" ] && BREW="$(command -v brew 2>/dev/null || true)"
  if [ -n "$BREW" ]; then ok "$(msg brew_ok "$BREW")"
  elif [ "$OP_DEPS" = "1" ] && [ "$OP_DRYRUN" = "0" ]; then
    garantir_sudo
    ui_info "$(msg brew_instalando)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null \
      || morrer "$E_DEP" "$(msg brew_falhou)"
    for f in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$f" ] && BREW="$f" && break; done
    [ -n "$BREW" ] || morrer "$E_DEP" "$(msg brew_falhou)"
    ok "$(msg brew_ok "$BREW")"; FEZ=1
  else
    ui_warn "$(msg brew_falta)"; portao "$(msg brew_dica)"
  fi
  if [ "$OP_NOAPP" = "0" ]; then
    if command -v swift >/dev/null 2>&1 && swift --version >/dev/null 2>&1; then
      SWIFT_OK=1; ok "$(msg swift_ok "$(swift --version 2>&1 | head -1 | grep -Eo 'Swift version [0-9.]+' | cut -d' ' -f3)")"
    else ui_warn "$(msg swift_falta)"; fi
  fi
  return 0
}

fase_fonte() { # define SRC_DIR (árvore com scripts/install.sh)
  fase "$(msg fase_fonte)"
  if [ -n "$SRC_DIR" ]; then
    [ -x "$SRC_DIR/scripts/install.sh" ] || morrer "$E_VALID" "$(msg fonte_local_invalida "$SRC_DIR")"
    ok "$(msg fonte_local "$SRC_DIR")"; return 100
  fi
  local tgz="$CACHE_DIR/src.tar.gz" sha dest
  if [ "$OP_DRYRUN" = "1" ]; then ui_info "$(msg fonte_dry "$RUB_SRC_URL" "$tgz" "$CACHE_DIR")"; SRC_DIR=""; return 0; fi
  mkdir -p "$CACHE_DIR"
  ui_info "$(msg fonte_baixando "$RUB_SRC_URL")"
  # .parcial → mv: um download interrompido nunca é "encontrado" como pronto.
  if ! curl -fsSL --retry 2 --max-time 300 -o "$tgz.parcial" "$RUB_SRC_URL" 2>"$CACHE_DIR/curl.err"; then
    rm -f "$tgz.parcial"; morrer "$E_CONEXAO" "$(msg fonte_falhou "$(tail -1 "$CACHE_DIR/curl.err" 2>/dev/null | cut -c1-120)")"
  fi
  mv "$tgz.parcial" "$tgz"
  sha="$(shasum -a 256 "$tgz" | cut -d' ' -f1)"
  if [ -n "$RUB_SRC_SHA256" ] && [ "$sha" != "$RUB_SRC_SHA256" ]; then rm -f "$tgz"; morrer "$E_VALID" "$(msg fonte_sha_div)"; fi
  ok "$(msg fonte_sha "$(du -h "$tgz" | cut -f1 | tr -d ' ')" "${sha:0:12}")"
  dest="$CACHE_DIR/src-${sha:0:12}"
  if [ -x "$dest/scripts/install.sh" ]; then
    ui_info "$(msg fonte_cache "$dest")"; SRC_DIR="$dest"; return 100
  fi
  rm -rf "$dest.parcial"; mkdir -p "$dest.parcial"
  tar -xzf "$tgz" -C "$dest.parcial" --strip-components=1
  [ -x "$dest.parcial/scripts/install.sh" ] || { rm -rf "$dest.parcial"; morrer "$E_VALID" "$(msg fonte_sem_install)"; }
  rm -rf "$dest"; mv "$dest.parcial" "$dest"
  SRC_DIR="$dest"; ok "$(msg fonte_extraida "$dest")"; FEZ=1; return 0
}

fase_servico() {
  fase "$(msg fase_servico)"
  local log="$CACHE_DIR/install-service.log" rc=0
  if [ "$OP_DRYRUN" = "1" ]; then
    ui_info "$(msg servico_dry)"
    if [ -n "$SRC_DIR" ]; then
      ( cd "$SRC_DIR" && "./scripts/install.sh" --dry-run 2>&1 ) | sed "s/^/$(printf '%s' "$UI_GUT")  /" || true
    else ui_linha "  $(msg servico_dry_remoto)"; fi
    return 0
  fi
  garantir_sudo
  ui_info "$(msg servico_rodando)"
  mkdir -p "$CACHE_DIR"
  # Tudo que exige root vive aqui dentro (brew como o usuário, /usr/local, plist,
  # kickstart). O sudo foi primado agora mesmo: nenhum prompt cai no meio.
  ( cd "$SRC_DIR" && ${SUDO_CMD:+$SUDO_CMD} "./scripts/install.sh" --consent-homebrew ) >"$log" 2>&1 &
  ui_spin "$(msg servico_rodando)" $! || rc=$?
  case "$rc" in
    0)   ok "$(msg servico_ok)"; FEZ=1; return 0 ;;
    100) ui_skip "$(msg servico_ja)"; return 100 ;;
    *)   ui_err "$(msg servico_falhou "$rc")"; tail -8 "$log" | sed 's/^/    /' >&2; exit "$E_FALHA" ;;
  esac
}

fase_app() {
  fase "$(msg fase_app)"
  if [ "$OP_NOAPP" = "1" ]; then ui_skip "$(msg app_pulado)"; return 100; fi
  if [ "$OP_DRYRUN" = "1" ]; then ui_info "$(msg app_dry "$APP_DEST")"; return 0; fi
  [ "$SWIFT_OK" = "1" ] || { ui_skip "$(msg swift_falta)"; return 100; }
  local log="$CACHE_DIR/build-app.log" rc=0 novo="$SRC_DIR/macos/RiverBridge/dist/River Bridge.app"
  ( cd "$SRC_DIR" && ./tools/build-app.sh ) >"$log" 2>&1 &
  ui_spin "$(msg app_compilando)" $! || rc=$?
  [ "$rc" = "0" ] || { ui_err "$(msg app_falhou)"; tail -8 "$log" | sed 's/^/    /' >&2; exit "$E_FALHA"; }
  if [ -x "$APP_DEST/Contents/MacOS/RiverBridge" ] && cmp -s "$novo/Contents/MacOS/RiverBridge" "$APP_DEST/Contents/MacOS/RiverBridge"; then
    ui_skip "$(msg app_ja "$APP_DEST")"; return 100
  fi
  local estava=0
  pgrep -x RiverBridge >/dev/null 2>&1 && estava=1
  [ "$estava" = "1" ] && { osascript -e 'tell application "River Bridge" to quit' >/dev/null 2>&1 || true; sleep 1; }
  mkdir -p "$(dirname "$APP_DEST")"
  rm -rf "$APP_DEST.parcial"; cp -R "$novo" "$APP_DEST.parcial"
  rm -rf "$APP_DEST"; mv "$APP_DEST.parcial" "$APP_DEST"
  ok "$(msg app_instalado "$APP_DEST")"; FEZ=1
  [ "$estava" = "1" ] && { open "$APP_DEST" >/dev/null 2>&1 || true; ui_info "$(msg app_reaberto)"; }
  return 0
}

fase_verificacao() {
  fase "$(msg fase_verificacao)"
  if [ "$OP_DRYRUN" = "1" ]; then ui_info "$(msg verif_dry "$API_PORT")"; return 0; fi
  if [ "${RUB_SKIP_HEALTH:-0}" = "1" ]; then ui_skip "$(msg verif_pulada)"; return 100; fi
  local token_f="$STATE_DIR/ui-api.token" i T ver health
  for i in $(seq 1 30); do [ -s "$token_f" ] && break; sleep 1; done
  [ -s "$token_f" ] || { ui_warn "$(msg verif_sem_token "$token_f")"; return 100; }
  T="$(cat "$token_f")"
  ui_info "$(msg verif_esperando "$API_PORT")"
  for i in $(seq 1 30); do
    ver="$(curl -sf -m 2 -H "Authorization: Bearer $T" "http://127.0.0.1:$API_PORT/v1/version" 2>/dev/null || true)"
    [ -n "$ver" ] && break; sleep 1
  done
  [ -n "$ver" ] || { ui_warn "$(msg verif_sem_api 30 "$HOME/Library/Logs/river-unifi-bridge.log")"; return 100; }
  health="$(curl -sf -m 2 -H "Authorization: Bearer $T" "http://127.0.0.1:$API_PORT/v1/health" 2>/dev/null || true)"
  SERVICO_VERSAO="$(printf '%s' "$ver" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')"
  ok "$(msg verif_ok \
      "$SERVICO_VERSAO" \
      "$(printf '%s' "$health" | sed -n 's/.*"nut": *"\([^"]*\)".*/\1/p')" \
      "$(printf '%s' "$health" | sed -n 's/.*"udr7": *"\([^"]*\)".*/\1/p')" \
      "$(printf '%s' "$health" | sed -n 's/.*"unifi": *"\([^"]*\)".*/\1/p')")"
  return 0
}

# =============================================================================
uso() { # texto próprio: sob `curl | bash` não há arquivo em disco para ler o cabeçalho
  if [ "$IDIOMA" = "pt" ]; then cat <<'EOF_USO'
river-bridge-install.sh — River Bridge (EcoFlow RIVER 3 Plus → NUT → UniFi) em UM comando.
  Remoto:  curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s -- [opções]
  Local:   ./river-bridge-install.sh [opções]
  --dry-run        pré-voo e plano; nada é baixado, escrito ou instalado
  --yes            não pergunta [s/N] (a senha do sudo continua sendo do sudo)
  --install-deps   autoriza instalar o Homebrew (oficial, NONINTERACTIVE) se faltar
  --no-app         não compila/instala o River Bridge.app
  --no-open        não abre o app ao terminar
  --src DIR        usa uma árvore local do repo em vez de baixar (bancada/gate)
  --no-anim        sem abertura animada · --demo  só a abertura
  --lang pt|en     idioma (default: locale do Mac)
  Exit: 0 instalou/atualizou · 100 já estava tudo · 2 uso · 3 validação · 4 dependência · 10 rede · 130 cancelado · 1 falha
EOF_USO
  else cat <<'EOF_USO'
river-bridge-install.sh - River Bridge (EcoFlow RIVER 3 Plus -> NUT -> UniFi) in ONE command.
  Remote:  curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s -- [options]
  Local:   ./river-bridge-install.sh [options]
  --dry-run        pre-flight and plan; nothing is downloaded, written or installed
  --yes            do not ask [y/N] (the sudo password is still sudo's)
  --install-deps   allow installing Homebrew (official, NONINTERACTIVE) if missing
  --no-app         do not build/install River Bridge.app
  --no-open        do not open the app when done
  --src DIR        use a local repo tree instead of downloading (bench/gate)
  --no-anim        no animated opening - --demo  opening only
  --lang pt|en     language (default: the Mac's locale)
  Exit: 0 installed/updated - 100 nothing to do - 2 usage - 3 validation - 4 dependency - 10 network - 130 cancelled - 1 failure
EOF_USO
  fi
}
ler_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run|-n) OP_DRYRUN=1 ;; --yes|-y) OP_YES=1 ;; --install-deps) OP_DEPS=1 ;; --no-app) OP_NOAPP=1 ;;
      --src) [ -n "${2:-}" ] || morrer "$E_USO" "$(msg flag_sem_valor --src)"; SRC_DIR="$2"; shift ;;
      --lang) case "${2:-}" in pt|en) IDIOMA="$2"; shift ;; *) morrer "$E_USO" "$(msg lang_invalido)" ;; esac ;;
      --no-anim) UI_NO_ANIM=1; UI_ANIM=0 ;; --demo) OP_DEMO=1 ;; --no-open) OP_NOOPEN=1 ;;
      --demo-frame) [ -n "${2:-}" ] || morrer "$E_USO" "$(msg flag_sem_valor --demo-frame)"; UI_NO_ANIM=1; UI_ANIM=0; lg_quadro "$2"; exit 0 ;;
      -h|--help) uso; exit 0 ;; --version) printf 'river-bridge-install.sh %s\n' "$RBI_VERSION"; exit 0 ;;
      *) morrer "$E_USO" "$(msg opcao_desconhecida "$1")" ;;
    esac; shift
  done
}
if [ "${RBI_LIB:-0}" = "1" ]; then return 0 2>/dev/null || exit 0; fi
main() {
  ler_args "$@"
  if [ "$OP_DEMO" = "1" ]; then trap 'ui_show_cursor' EXIT; ui_banner "$(msg titulo)" "$(msg subtitulo) ${UI_G_SEP} v${RBI_VERSION}"; exit 0; fi
  trap limpar EXIT INT TERM
  MAIN_INICIADO=1
  local t0=$SECONDS rc r
  UI_BAR_TOTAL=5; UI_BAR_N=0
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    ui_banner "$(msg titulo)" "$(msg subtitulo) ${UI_G_SEP} v${RBI_VERSION}"
  else
    printf '\n  %s v%s\n\n' "$(msg titulo)" "$RBI_VERSION"
  fi
  fase_prevoo
  if [ "$OP_DRYRUN" = "0" ]; then
    confirmar "$(msg confirmar)" || { ui_info "$(msg cancelado)"; FASE_ATUAL=""; exit "$E_CANCEL"; }
  fi
  fase_fonte || true
  fase_servico || true
  fase_app || true
  fase_verificacao || true
  if [ "$OP_DRYRUN" = "1" ]; then
    ui_bar_limpa; printf '%s\n' "$UI_GUT"; printf '%s' "$UI_G_FIM"; printf '%s\n\n' "$(ui_gradient "$(printf '%*s' 76 '' | tr ' ' "$UI_G_REGUA")")"
    printf '  %s\n\n' "$(msg dry_fim "$PORTOES_ABERTOS")"; FASE_ATUAL=""; exit 0
  fi
  if [ "$FEZ" = "1" ]; then rc=0; else rc=100; fi
  relatorio_final "$FEZ" $(( SECONDS - t0 ))
  FASE_ATUAL=""
  exit "$rc"
}
main "$@"
