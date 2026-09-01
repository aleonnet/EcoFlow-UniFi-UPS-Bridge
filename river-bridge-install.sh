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
# Ícone real do app (tools/app-icon-render.swift) reduzido a 40×40 pixels.
# LG_MASK: . fora · b fundo · s escudo · r raio. LG_RGB por pixel (y*LG_W+x).
LG_W=40
LG_H=40
LG_CAMINHO=64
LG_Q_MONTA=21
LG_MASK=(
'........bbbbbbbbbbbbbbbbbbbbbbbb........'
'.....bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.....'
'....bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb....'
'...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...'
'..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..'
'.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.'
'.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.'
'.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.'
'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
'bbbbbbbbbbbbbbbbbssssssbbbbbbbbbbbbbbbbb'
'bbbbbbbbbbbbbbssssssssssssbbbbbbbbbbbbbb'
'bbbbbbbbbbbbssssssssssssssssbbbbbbbbbbbb'
'bbbbbbbbbbsssssssssssrrsssssssbbbbbbbbbb'
'bbbbbbbbbbssssssssssrrssssssssbbbbbbbbbb'
'bbbbbbbbbbsssssssssrrrssssssssbbbbbbbbbb'
'bbbbbbbbbbsssssssssrrrssssssssbbbbbbbbbb'
'bbbbbbbbbbssssssssrrrsssssssssbbbbbbbbbb'
'bbbbbbbbbbsssssssrrrrsssssssssbbbbbbbbbb'
'bbbbbbbbbbssssssrrrrrrrrrsssssbbbbbbbbbb'
'bbbbbbbbbbsssssrrrrrrrrrrsssssbbbbbbbbbb'
'bbbbbbbbbbsssssrrrrrrrrrssssssbbbbbbbbbb'
'bbbbbbbbbbsssssssssrrrrsssssssbbbbbbbbbb'
'bbbbbbbbbbsssssssssrrrssssssssbbbbbbbbbb'
'bbbbbbbbbbssssssssrrrrssssssssbbbbbbbbbb'
'bbbbbbbbbbssssssssrrrsssssssssbbbbbbbbbb'
'bbbbbbbbbbbsssssssrrsssssssssbbbbbbbbbbb'
'bbbbbbbbbbbssssssrrssssssssssbbbbbbbbbbb'
'bbbbbbbbbbbbsssssrssssssssssbbbbbbbbbbbb'
'bbbbbbbbbbbbbssssssssssssssbbbbbbbbbbbbb'
'bbbbbbbbbbbbbbbssssssssssbbbbbbbbbbbbbbb'
'bbbbbbbbbbbbbbbbbsssssssbbbbbbbbbbbbbbbb'
'bbbbbbbbbbbbbbbbbbssssbbbbbbbbbbbbbbbbbb'
'.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.'
'.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.'
'.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.'
'..bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb..'
'...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...'
'....bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb....'
'.....bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.....'
'........bbbbbbbbbbbbbbbbbbbbbbbb........'
)
LG_RGB=("0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "46;86;80" "90;168;158" "103;186;176" "102;185;175" "103;186;176" "102;187;177" "102;188;177" "103;189;178" "102;190;179" "103;191;179" "103;192;180" "104;193;181" "104;193;181" "105;194;182" "105;195;182" "106;196;183" "105;197;184" "106;198;184" "106;199;185" "105;200;186" "106;201;186" "106;204;189" "95;185;170" "49;94;87" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "51;99;93" "87;163;155" "100;186;177" "101;190;180" "99;185;175" "97;184;174" "97;185;175" "98;186;175" "97;187;176" "99;188;177" "98;189;177" "99;190;178" "99;191;178" "100;191;179" "100;192;180" "101;193;180" "100;194;181" "100;195;181" "101;196;182" "100;197;183" "102;198;183" "102;198;184" "103;199;184" "102;200;185" "101;201;185" "104;203;188" "107;211;195" "105;209;192" "92;185;170" "56;112;104" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "81;154;149" "96;186;177" "93;181;172" "92;180;170" "92;180;171" "93;181;171" "92;182;172" "93;183;173" "93;184;173" "94;185;174" "93;186;174" "94;187;175" "94;188;176" "94;188;176" "95;189;177" "94;190;177" "95;191;178" "95;192;179" "96;193;179" "95;194;180" "97;195;180" "97;195;181" "96;196;182" "97;197;182" "97;198;183" "98;199;183" "97;200;184" "98;201;185" "98;202;186" "100;206;189" "103;213;196" "87;179;163" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "80;164;157" "88;177;169" "86;173;165" "87;174;166" "86;175;166" "87;176;167" "87;177;167" "88;178;168" "87;179;169" "87;180;169" "88;181;170" "87;182;171" "89;182;171" "88;183;172" "89;184;173" "89;185;173" "90;186;174" "89;187;174" "90;188;175" "90;189;176" "91;190;176" "91;191;177" "92;192;178" "91;193;178" "91;193;179" "92;194;179" "92;195;180" "93;196;181" "92;197;181" "93;198;182" "93;199;183" "94;200;183" "97;206;189" "89;194;176" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "69;145;139" "82;171;164" "79;167;160" "80;168;160" "80;169;161" "81;170;162" "80;171;162" "81;172;163" "81;173;164" "82;174;164" "81;175;165" "82;176;166" "82;176;166" "83;177;167" "83;178;168" "84;179;168" "83;180;169" "84;181;170" "84;182;170" "85;183;171" "84;184;172" "86;185;172" "85;186;173" "86;187;174" "85;188;174" "87;189;175" "86;190;176" "87;191;176" "86;192;177" "88;193;178" "87;194;178" "88;195;179" "88;196;180" "88;196;180" "90;204;186" "77;174;159" "0;0;0" "0;0;0" "0;0;0" "39;86;83" "77;167;162" "73;160;155" "74;161;156" "75;162;157" "74;163;158" "76;164;157" "75;165;159" "76;166;159" "76;167;159" "77;168;160" "76;169;161" "77;170;161" "77;171;162" "78;172;163" "77;173;163" "78;174;164" "78;175;165" "79;176;165" "78;177;166" "79;178;167" "79;179;167" "80;180;168" "79;181;169" "80;182;170" "80;183;170" "81;184;171" "80;185;172" "81;186;172" "81;187;173" "82;188;174" "81;189;174" "82;190;175" "82;191;176" "83;192;176" "82;193;177" "88;205;186" "45;106;97" "0;0;0" "0;0;0" "62;137;134" "68;156;152" "68;154;151" "69;155;151" "68;157;152" "69;158;153" "68;159;152" "69;160;153" "69;161;155" "70;162;156" "69;163;155" "70;164;156" "70;165;157" "71;166;157" "70;167;158" "71;168;159" "73;169;160" "71;171;161" "72;172;162" "74;173;162" "73;174;163" "73;174;163" "74;175;164" "73;176;164" "75;177;165" "74;178;166" "75;179;167" "74;180;167" "76;181;168" "75;182;169" "76;183;169" "77;184;170" "76;186;171" "77;187;172" "77;188;172" "78;189;173" "79;192;176" "68;173;157" "0;0;0" "0;0;0" "61;150;147" "62;147;145" "61;148;145" "62;149;146" "61;150;147" "62;152;148" "63;153;148" "63;154;149" "64;155;150" "63;156;151" "64;157;150" "64;158;152" "65;159;152" "66;160;153" "66;162;154" "66;165;156" "66;168;158" "64;171;160" "61;172;160" "60;173;161" "64;174;162" "68;173;161" "67;172;161" "67;172;161" "69;172;161" "68;173;161" "69;174;162" "69;175;163" "70;176;164" "69;177;164" "70;178;165" "70;179;166" "70;181;167" "71;182;167" "71;183;168" "72;184;169" "71;185;170" "72;191;175" "0;0;0" "24;64;64" "58;145;144" "55;141;139" "56;142;140" "55;143;141" "56;144;142" "56;145;142" "57;146;143" "56;147;144" "57;148;145" "58;150;145" "57;151;146" "57;153;148" "60;155;148" "59;159;151" "58;163;154" "52;167;156" "58;175;162" "90;189;176" "124;202;190" "124;202;191" "89;190;177" "59;179;165" "53;174;161" "59;172;160" "62;170;159" "63;169;158" "63;169;158" "62;170;159" "64;171;159" "63;172;160" "64;173;161" "64;174;161" "65;175;162" "64;176;163" "64;178;164" "66;179;164" "65;180;165" "68;190;173" "31;84;77" "42;119;119" "48;134;134" "48;134;134" "49;135;135" "48;136;135" "50;137;136" "48;139;137" "49;140;138" "51;141;139" "52;142;140" "52;145;141" "51;148;144" "52;153;146" "45;158;149" "46;166;154" "77;181;169" "131;203;192" "184;223;216" "219;236;232" "229;239;236" "229;239;236" "218;236;231" "182;223;216" "128;205;193" "77;187;173" "48;176;161" "49;171;158" "55;169;157" "57;167;156" "58;166;155" "57;167;156" "58;168;156" "57;169;157" "58;170;158" "58;171;159" "59;172;159" "60;173;160" "58;175;161" "61;177;163" "54;160;148" "40;126;128" "40;126;127" "42;127;128" "43;128;129" "42;129;130" "43;131;131" "42;132;132" "43;133;132" "43;135;134" "45;138;136" "44;144;140" "36;152;144" "58;168;157" "112;192;182" "173;217;210" "216;234;230" "232;239;237" "231;238;236" "227;237;234" "226;237;234" "226;237;234" "229;238;235" "234;239;237" "232;239;236" "214;234;229" "173;219;211" "113;199;186" "61;180;166" "41;169;156" "50;165;154" "51;163;152" "50;162;152" "51;163;152" "53;164;153" "51;166;154" "52;167;155" "52;168;156" "53;169;156" "52;170;157" "53;174;160" "33;117;120" "33;119;121" "34;120;122" "34;121;123" "35;122;124" "36;123;125" "34;125;126" "36;126;127" "38;129;129" "34;137;134" "50;155;147" "143;200;193" "207;229;224" "232;238;236" "234;238;237" "230;237;235" "227;236;234" "227;236;234" "227;236;234" "227;236;234" "231;237;235" "211;233;228" "201;231;225" "230;236;235" "230;237;235" "234;238;237" "232;238;236" "205;230;225" "142;207;196" "52;172;159" "42;161;150" "44;157;147" "44;157;147" "44;159;148" "45;160;149" "44;161;150" "46;162;151" "47;163;152" "45;165;153" "46;166;153" "25;110;114" "27;111;115" "25;112;116" "26;114;117" "27;115;118" "26;116;119" "28;117;120" "28;119;121" "28;124;125" "19;137;133" "153;201;196" "241;242;240" "232;237;235" "230;236;234" "230;236;234" "230;236;234" "230;236;234" "230;236;234" "229;236;234" "232;237;235" "221;233;230" "79;197;179" "122;210;195" "236;238;236" "230;236;234" "230;236;234" "230;236;234" "232;237;235" "240;240;239" "150;207;198" "24;160;147" "35;153;143" "37;151;142" "36;152;143" "36;154;144" "38;155;145" "37;156;146" "37;158;147" "38;159;148" "37;160;148" "18;102;107" "20;103;108" "17;105;109" "19;106;111" "18;107;112" "18;109;113" "20;110;114" "19;111;115" "19;119;120" "22;140;135" "195;220;216" "236;237;236" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "233;235;234" "234;236;235" "111;194;183" "0;172;154" "179;219;212" "237;237;236" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "236;237;236" "191;221;216" "22;161;148" "26;148;139" "27;145;137" "29;146;138" "27;147;140" "28;149;140" "30;150;141" "31;151;142" "29;153;143" "30;154;143" "10;93;100" "6;95;101" "9;97;103" "7;97;104" "7;100;105" "9;101;106" "7;102;107" "7;104;109" "6;113;115" "9;137;133" "195;220;216" "237;237;236" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "239;238;238" "140;200;192" "0;155;142" "63;175;162" "226;233;231" "234;235;235" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "237;237;236" "191;221;216" "8;158;146" "18;142;136" "17;138;133" "17;140;132" "20;141;134" "18;142;134" "18;144;135" "20;145;136" "20;147;137" "19;148;138" "1;86;94" "2;87;95" "0;90;97" "1;90;98" "2;91;99" "0;93;100" "1;94;101" "1;97;103" "0;107;110" "0;133;129" "196;219;215" "238;237;236" "234;235;234" "234;235;234" "234;235;234" "234;235;234" "234;235;234" "243;238;238" "173;210;205" "0;148;138" "0;144;134" "131;195;187" "243;238;238" "234;235;234" "234;235;234" "234;235;234" "234;235;234" "234;235;234" "239;237;236" "193;220;215" "0;154;142" "2;137;130" "5;132;128" "8;133;129" "8;135;130" "6;136;131" "6;138;132" "9;139;132" "10;141;133" "6;142;134" "0;82;91" "1;84;92" "2;85;94" "1;86;95" "0;88;96" "2;90;97" "1;90;98" "0;93;99" "0;103;107" "0;130;126" "196;218;215" "239;237;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "240;238;237" "201;221;218" "31;149;143" "0;131;127" "1;144;136" "198;220;217" "239;237;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "192;220;215" "0;151;140" "2;133;129" "2;129;125" "6;130;126" "8;131;127" "8;133;128" "6;134;129" "6;136;129" "9;137;130" "9;139;131" "2;79;90" "2;81;90" "0;82;91" "1;84;92" "1;86;94" "2;87;95" "2;90;97" "2;91;98" "0;103;106" "0;130;126" "196;218;215" "239;237;236" "235;235;234" "235;235;234" "235;235;234" "238;236;236" "222;231;229" "64;162;154" "0;127;123" "0;123;121" "85;162;158" "243;239;238" "243;238;237" "242;237;237" "242;237;236" "236;235;234" "235;235;234" "235;235;234" "241;237;236" "192;220;215" "0;150;140" "5;132;128" "7;127;124" "5;128;125" "8;129;126" "6;130;127" "8;131;127" "2;133;128" "6;134;129" "6;136;129" "3;76;86" "0;78;87" "0;80;89" "1;84;92" "2;90;96" "2;93;99" "3;97;102" "5;103;106" "2;115;114" "2;141;133" "198;221;216" "239;237;236" "235;235;234" "235;235;234" "236;235;235" "236;236;235" "103;189;177" "0;149;137" "6;142;133" "0;142;133" "70;167;157" "119;192;182" "116;196;184" "117;201;188" "129;211;196" "224;233;231" "236;235;234" "235;235;234" "239;237;236" "192;222;216" "0;159;146" "2;141;133" "6;134;129" "8;133;129" "5;132;128" "5;132;127" "3;131;127" "6;130;126" "8;131;127" "5;132;128" "2;73;83" "2;75;85" "2;77;87" "1;84;91" "2;90;95" "2;93;98" "1;99;102" "5;103;105" "0;116;114" "0;142;133" "198;221;216" "239;237;236" "235;235;234" "235;235;234" "239;237;236" "138;205;194" "0;159;144" "6;148;138" "6;144;134" "6;144;135" "0;146;136" "0;150;138" "0;157;143" "0;168;149" "77;197;178" "229;234;232" "236;235;234" "235;235;234" "239;237;236" "192;222;216" "0;159;146" "2;141;133" "6;134;129" "2;133;128" "5;132;127" "6;130;127" "8;129;126" "7;127;124" "5;128;125" "6;130;126" "2;71;81" "1;72;82" "2;75;84" "2;83;90" "0;88;94" "2;93;98" "3;97;101" "5;103;105" "2;115;114" "0;142;133" "198;221;216" "239;237;236" "235;235;234" "240;236;236" "195;226;219" "0;180;159" "0;166;148" "0;157;143" "0;152;139" "3;149;138" "7;146;136" "6;148;137" "0;156;142" "49;178;162" "211;229;224" "240;236;236" "235;235;234" "235;235;234" "239;237;236" "192;222;216" "0;159;146" "6;140;132" "8;133;128" "8;131;127" "6;130;126" "2;129;126" "5;128;125" "2;125;123" "2;125;123" "4;126;124" "4;67;78" "2;69;79" "2;72;82" "4;82;89" "2;87;93" "4;93;97" "3;97;100" "5;103;104" "2;115;113" "0;142;132" "198;221;216" "239;237;236" "235;235;234" "236;235;235" "223;232;230" "179;220;212" "176;217;210" "176;215;208" "176;212;206" "63;167;156" "0;149;137" "0;153;141" "9;169;152" "185;220;213" "242;237;237" "235;235;234" "235;235;234" "235;235;234" "239;237;236" "193;221;216" "0;158;145" "2;139;132" "5;132;128" "6;130;126" "2;129;125" "5;128;125" "4;126;124" "5;122;121" "5;122;120" "7;123;122" "2;65;76" "2;66;77" "3;70;80" "2;81;88" "4;86;92" "2;91;96" "5;97;99" "3;102;103" "4;114;112" "2;141;131" "198;221;216" "239;237;236" "235;235;234" "235;235;234" "236;235;234" "241;237;236" "242;237;237" "245;239;239" "211;227;224" "29;166;151" "0;157;143" "0;166;148" "154;211;201" "243;238;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "239;237;236" "193;221;216" "0;157;144" "6;138;132" "3;131;127" "8;129;126" "5;128;125" "4;126;123" "2;125;122" "2;119;119" "2;119;118" "5;120;120" "2;62;73" "1;63;74" "4;67;78" "5;79;87" "2;85;91" "4;90;95" "6;95;98" "5;101;102" "2;113;111" "0;137;128" "189;217;212" "241;237;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "243;238;237" "142;207;195" "0;166;148" "0;166;148" "120;200;187" "239;237;236" "236;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;237" "184;218;212" "0;154;141" "2;137;130" "6;130;126" "5;128;125" "4;126;123" "5;124;122" "2;123;121" "4;116;117" "4;116;116" "2;117;117" "3;59;71" "2;60;71" "3;65;75" "3;78;85" "6;83;89" "6;89;93" "5;94;97" "7;100;101" "8;110;109" "0;130;121" "157;202;195" "244;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "236;235;234" "230;234;232" "71;188;171" "0;171;150" "87;191;175" "229;234;232" "237;236;235" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "243;238;238" "154;206;198" "0;148;137" "6;134;129" "5;128;125" "4;126;124" "2;125;122" "2;123;121" "2;121;120" "0;114;115" "2;113;114" "4;114;115" "2;56;68" "3;57;69" "2;62;73" "6;76;83" "4;82;88" "6;87;92" "6;93;96" "5;99;100" "6;107;106" "0;123;116" "87;171;160" "238;237;236" "236;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "188;222;215" "0;180;157" "52;188;168" "213;229;225" "240;236;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "236;235;234" "238;237;236" "88;181;169" "0;142;133" "3;131;127" "2;127;124" "2;125;123" "2;123;121" "2;121;120" "2;119;118" "1;111;113" "2;109;112" "1;111;113" "3;53;65" "5;53;67" "3;59;71" "6;74;82" "3;80;86" "4;86;90" "6;91;95" "7;97;99" "7;104;104" "7;117;113" "0;138;127" "163;206;199" "245;239;239" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "115;208;191" "0;189;163" "188;224;216" "242;237;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "244;239;238" "169;212;205" "0;153;141" "2;137;129" "2;129;125" "7;125;123" "2;123;121" "2;121;120" "2;119;118" "4;116;117" "0;108;111" "3;106;110" "3;108;111" "4;50;63" "3;51;64" "3;57;68" "6;72;80" "6;78;84" "4;84;89" "6;89;93" "6;95;97" "7;102;102" "8;110;108" "0;124;117" "26;150;138" "179;214;208" "244;239;238" "236;235;234" "235;235;234" "234;235;234" "97;210;188" "158;220;207" "242;237;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "244;238;238" "190;220;215" "35;164;150" "0;141;132" "8;131;126" "4;126;123" "7;123;121" "2;121;119" "2;119;118" "4;116;117" "4;114;115" "1;105;109" "1;103;108" "1;105;109" "4;47;60" "4;48;61" "4;54;66" "5;70;78" "7;75;82" "9;81;87" "6;87;91" "6;93;95" "7;100;100" "8;106;104" "12;115;111" "0;129;120" "16;151;138" "153;204;196" "237;237;236" "239;237;236" "235;235;234" "229;234;232" "237;236;235" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "238;236;235" "240;238;237" "169;213;205" "31;165;150" "0;144;133" "6;134;126" "7;127;123" "5;124;121" "7;121;119" "2;119;117" "4;116;116" "4;114;114" "0;112;113" "0;102;107" "0;100;106" "0;102;107" "5;44;58" "4;45;58" "5;51;63" "7;67;75" "7;73;80" "5;79;84" "6;85;89" "6;91;93" "9;97;98" "9;103;102" "10;109;107" "10;118;113" "6;130;121" "0;146;133" "99;185;172" "207;227;222" "243;238;238" "238;236;235" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "236;235;235" "243;238;238" "217;229;227" "115;195;182" "0;158;143" "0;143;132" "11;134;126" "5;128;123" "5;124;121" "5;122;119" "2;119;117" "4;116;115" "4;114;114" "1;111;112" "2;109;111" "1;99;104" "1;97;103" "0;100;106" "3;37;49" "4;42;56" "4;48;61" "5;64;73" "5;70;77" "6;76;82" "7;82;86" "7;88;91" "9;94;95" "11;100;100" "8;106;104" "9;112;109" "10;120;113" "10;130;121" "0;142;129" "35;164;148" "143;204;193" "226;233;231" "243;238;237" "236;235;234" "236;235;234" "243;238;237" "229;234;232" "154;210;199" "47;173;156" "0;151;137" "10;141;131" "8;133;125" "10;128;123" "7;125;120" "5;122;118" "7;119;116" "4;116;115" "4;114;113" "1;111;111" "3;108;110" "3;106;108" "3;96;102" "1;94;101" "2;86;91" "2;17;24" "5;40;56" "4;45;58" "7;60;70" "8;66;74" "7;73;79" "9;79;84" "10;84;88" "8;90;93" "9;97;97" "9;103;101" "12;108;105" "9;114;110" "10;120;114" "13;129;120" "2;139;127" "0;151;135" "64;176;160" "168;212;204" "233;235;233" "232;234;233" "169;214;205" "71;180;164" "0;157;140" "0;146;133" "12;138;128" "11;132;124" "5;128;121" "7;125;120" "5;122;118" "7;119;116" "4;116;114" "6;113;112" "3;110;110" "3;108;109" "1;105;107" "1;103;106" "0;93;99" "1;94;102" "0;43;45" "0;0;0" "5;36;52" "4;42;55" "7;57;67" "6;63;71" "6;69;76" "7;75;81" "9;81;85" "9;87;90" "12;92;94" "9;99;98" "12;104;102" "8;110;106" "12;115;109" "14;120;113" "15;126;118" "11;134;124" "0;143;130" "0;154;138" "72;173;159" "70;173;159" "0;156;140" "0;147;134" "13;140;129" "11;134;125" "10;130;122" "7;127;120" "10;124;119" "7;121;117" "10;118;115" "6;115;113" "6;113;111" "3;110;109" "6;107;108" "3;104;106" "3;102;104" "1;99;103" "2;90;97" "2;90;98" "0;0;0" "0;0;0" "3;29;43" "6;38;53" "7;53;63" "8;59;68" "10;65;73" "6;71;78" "7;77;82" "8;83;86" "11;88;91" "9;94;95" "11;100;99" "10;105;103" "13;110;107" "12;115;109" "12;119;113" "10;124;116" "13;129;120" "8;135;124" "0;138;126" "0;138;127" "9;137;126" "13;133;124" "10;130;121" "13;127;119" "7;125;118" "10;122;116" "10;120;114" "7;117;114" "9;114;112" "3;112;110" "6;109;108" "3;106;106" "5;103;105" "1;101;103" "3;97;101" "3;96;100" "2;87;95" "0;76;84" "0;0;0" "0;0;0" "2;16;24" "6;36;53" "7;48;60" "8;54;65" "8;61;69" "9;67;74" "9;72;78" "10;78;83" "10;84;87" "10;89;91" "13;94;95" "11;100;99" "10;105;103" "13;110;106" "13;114;108" "12;117;112" "12;121;113" "12;123;116" "13;125;117" "10;126;118" "10;126;118" "13;125;117" "10;124;116" "10;122;115" "10;120;114" "10;118;112" "6;115;112" "6;113;110" "8;110;108" "6;107;107" "5;105;105" "3;102;103" "5;99;101" "5;97;100" "2;93;98" "2;91;96" "0;87;95" "1;43;48" "0;0;0" "0;0;0" "0;0;0" "5;27;41" "8;45;57" "8;50;61" "8;56;66" "10;62;70" "8;68;75" "10;73;79" "11;79;83" "10;84;87" "10;89;91" "13;94;95" "11;100;98" "12;104;102" "12;108;105" "11;111;106" "13;114;110" "14;116;111" "14;118;112" "12;119;112" "12;119;112" "12;119;112" "10;118;112" "10;116;112" "9;114;111" "9;112;109" "8;110;108" "7;108;106" "5;105;105" "5;103;103" "7;100;101" "3;97;100" "5;94;98" "2;91;96" "2;90;94" "4;88;95" "0;69;77" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "7;35;49" "9;46;58" "9;51;61" "7;57;66" "9;63;70" "10;68;75" "9;74;79" "11;79;83" "10;84;87" "11;88;90" "10;93;94" "11;97;97" "11;102;100" "10;105;102" "12;108;104" "13;110;106" "11;111;106" "13;112;107" "13;112;109" "13;112;107" "11;111;108" "8;110;107" "10;109;106" "10;107;105" "10;105;104" "5;103;102" "7;100;101" "7;97;99" "5;94;97" "4;93;96" "6;89;94" "2;87;92" "4;86;93" "1;78;85" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "6;34;45" "10;47;59" "10;52;62" "10;57;66" "9;63;70" "10;68;74" "10;73;78" "10;78;82" "10;82;86" "9;87;89" "10;91;92" "13;94;95" "11;97;97" "9;101;99" "9;103;101" "12;104;102" "10;105;103" "12;106;103" "8;106;103" "10;105;103" "7;104;102" "9;103;102" "9;101;101" "9;99;99" "9;97;98" "5;94;97" "4;93;95" "6;89;93" "6;87;92" "4;86;91" "1;86;93" "5;69;76" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "4;22;29" "7;42;51" "10;52;63" "10;59;68" "10;62;70" "9;67;73" "13;71;77" "13;76;81" "10;80;84" "10;84;87" "13;87;89" "12;90;92" "10;93;94" "10;95;95" "13;97;97" "11;97;97" "9;99;98" "9;99;98" "11;97;98" "9;97;97" "10;95;97" "9;94;96" "8;92;95" "8;90;93" "7;88;92" "6;87;91" "6;87;93" "6;83;90" "6;71;77" "2;42;46" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "5;23;28" "9;51;59" "10;62;70" "10;66;73" "11;70;76" "12;74;79" "10;78;82" "11;81;85" "10;84;87" "9;87;89" "10;89;91" "12;90;92" "10;91;93" "8;92;93" "8;92;93" "8;92;93" "6;91;93" "8;90;92" "6;89;91" "6;87;91" "6;85;89" "7;84;89" "5;73;79" "5;36;40" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0")
LG_TX=(19 18 17 16 15 14 13 12 11 11 10 10 10 10 10 10 10 10 10 10 10 10 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 29 29 29 29 29 29 29 29 29 29 29 29 28 28 27 26 25 24 23 22 21 20)
LG_TY=(31 31 30 29 29 28 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 12 11 11 10 10 10 9 9 9 9 9 9 10 10 10 11 11 12 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 28 29 30 30 31 31)
LG_AX=(17 18 19 20 21 22 14 15 16 17 18 19 20 21 22 23 24 25 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 13 14 15 16 17 18 19 20 21 22 23 24 25 26 15 16 17 18 19 20 21 22 23 24 17 18 19 20 21 22 23 18 19 20 21)
LG_AY=(9 9 9 9 9 9 10 10 10 10 10 10 10 10 10 10 10 10 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 28 28 28 28 28 28 28 28 28 28 28 28 28 28 29 29 29 29 29 29 29 29 29 29 30 30 30 30 30 30 30 31 31 31 31)
LG_AOX=(36 39 43 46 49 52 27 30 34 35 39 42 46 50 53 56 59 61 19 21 24 28 32 36 40 45 50 47 50 53 56 58 60 61 11 13 16 19 22 26 30 35 40 45 50 48 51 54 56 58 60 61 62 63 10 11 13 16 19 23 28 33 39 40 45 50 54 57 59 61 62 63 55 56 7 8 10 13 16 20 25 29 35 41 47 52 56 60 62 63 55 56 57 58 3 4 6 8 11 16 21 27 34 42 49 55 60 63 55 56 57 58 59 59 0 0 1 6 8 12 16 23 31 42 52 59 54 56 57 58 59 59 60 60 -5 0 0 1 3 5 9 16 26 41 48 54 57 58 59 59 59 59 60 52 -4 -4 -4 -4 -3 -1 0 5 16 33 52 58 59 59 59 59 59 51 52 52 -8 -9 -9 -10 -10 -10 -4 -3 0 16 59 58 56 56 56 49 50 50 51 51 -12 -13 -14 -15 -9 -10 -12 -14 -17 -20 23 42 47 44 45 46 47 48 49 50 -16 -18 -11 -12 -14 -16 -18 -20 -21 -16 3 23 32 37 40 42 44 46 47 48 -12 -13 -15 -16 -18 -20 -21 -22 -21 -8 2 14 23 29 34 38 40 43 39 41 -15 -17 -18 -20 -21 -22 -23 -14 -13 -8 0 8 16 23 29 33 33 35 37 39 -18 -20 -21 -22 -23 -15 -16 -15 -13 -8 -2 4 11 18 23 26 30 32 35 37 -21 -22 -23 -15 -16 -16 -15 -12 -9 -3 2 8 15 19 23 26 29 32 -21 -22 -23 -15 -15 -15 -14 -11 -8 -4 0 5 12 16 20 23 26 28 -21 -22 -22 -14 -13 -12 -10 -7 -4 0 4 8 14 17 20 23 -19 -19 -18 -18 -16 -7 -5 -2 0 3 7 11 14 18 -12 -12 -11 -9 -7 -4 -1 1 5 10 -9 -8 -6 -4 -1 1 4 -12 -4 -2 0)
LG_AOY=(-12 -11 -10 -8 -6 -4 -21 -21 -21 -12 -11 -10 -8 -6 -3 0 2 5 -15 -16 -17 -18 -18 -17 -16 -14 -11 -3 0 2 5 8 11 13 -22 -23 -15 -16 -17 -18 -18 -18 -16 -14 -11 -2 0 3 7 10 13 16 18 21 -14 -16 -17 -18 -19 -20 -21 -20 -19 -9 -6 -2 1 5 9 12 16 19 21 23 -15 -17 -18 -20 -21 -22 -23 -14 -13 -11 -7 -2 2 7 12 16 19 22 24 26 -16 -17 -19 -21 -23 -15 -16 -17 -16 -13 -8 -1 4 10 16 20 23 26 28 30 -16 -18 -19 -13 -15 -17 -18 -19 -19 -15 -8 0 11 16 21 25 28 30 32 34 -15 -9 -11 -13 -15 -17 -19 -21 -22 -18 -2 7 16 23 27 30 33 35 37 35 -7 -9 -10 -11 -13 -15 -18 -21 -15 -14 0 16 26 31 35 37 39 37 38 39 -6 -7 -8 -9 -10 -11 -6 -8 -12 -18 16 35 40 42 44 40 41 42 43 44 -4 -5 -5 -5 0 0 0 1 5 23 61 56 54 46 46 46 47 47 48 48 -2 -1 2 3 4 5 8 13 23 42 60 55 54 53 53 52 52 52 52 53 4 5 6 7 9 12 16 23 34 42 52 57 58 58 58 57 57 57 49 50 7 8 9 11 14 18 23 28 36 45 53 58 60 61 62 61 53 53 53 53 9 11 13 16 19 23 27 33 40 47 54 59 62 63 55 56 56 56 57 57 14 17 20 23 26 31 36 42 48 54 59 62 55 56 57 58 58 59 18 20 23 26 29 34 38 44 49 54 58 61 55 56 57 58 59 60 23 26 30 31 35 39 44 48 53 56 59 62 55 56 57 58 28 32 35 39 44 43 46 50 53 56 59 61 62 63 35 38 41 45 49 52 55 58 61 54 42 45 48 51 54 57 59 49 46 49 52)
LG_ADL=(11 12 13 11 12 13 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 1 2 0 1 2 0 1 2 0 1 2)
LG_HX=(4 5 6 7 32 33 34 35 3 4 35 36 2 3 36 37 1 2 37 38 0 1 38 39 0 39 0 39 0 39 0 39 0 39 0 39 0 1 38 39 1 2 37 38 2 3 36 37 3 4 35 36 4 5 6 7 32 33 34 35)
LG_HY=(0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 6 6 7 7 32 32 33 33 34 34 35 35 35 35 36 36 36 36 37 37 37 37 38 38 38 38 39 39 39 39 39 39 39 39)
# =============================================================================
# A ABERTURA — o ícone REAL do app, pixel a pixel (tools/gera-logo.py roda o mesmo
# render do AppIcon), em quatro atos, ~5 s (medido num pty em 2026-09-01: 95 quadros
# em 5,5 s). O que cada um é, e por quê:
#   1. CONSTELAÇÃO — o fundo do squircle sobe como líquido, com o escudo vazado;
#      cada pixel do escudo é uma partícula que voa de fora da tela em
#      trajetória radial (giro de 40°) e ASSENTA no lugar, de baixo para cima.
#      Trajetórias pré-computadas pelo gerador; o runtime só interpola.
#   2. O TRAÇO — a caneta branca contorna o escudo inteiro e se retrai, por
#      posição de arco.
#   3. O CORAÇÃO — o escudo bate como um coração: "tum-tum", pausa, "tum-tum".
#      A cada batida o ícone clareia, o raio acende em branco e, no pico, um
#      halo ciano aparece em volta do squircle.
#   4. Assenta no quadro final.
# Sem animação: o quadro final parado. Sem UTF-8 ou sem cor: só o título.
# Runtime: molde do haos-install.sh (ha_logo_*) com uma diferença medida — cada
# pixel tem a própria cor, então o custo por célula no bash é o limite (2026-09-01:
# 177 ms/quadro compondo as 800 células a cada quadro). Por isso os quadros
# estáticos (fundo, final, batida, pico) são compostos UMA vez em lg_init e cada
# quadro só recompõe as células que mudam (partículas, traço).
# Classes do QM (máscara mutável, uma string por linha de pixel): . fora ·
# = pixel com a própria cor · h a própria cor clareada · t traço branco ·
# a partícula em voo · g halo. CEL: uma string pronta por célula (LG_W × LG_H/2).
# =============================================================================
LG_ATRASO=0.03; LG_A_DUR=8; LG_Q_TRACO=30; LG_Q_BATE=44
LG_QUADROS=$(( LG_Q_MONTA + LG_Q_TRACO + LG_Q_BATE ))
LG_LINHAS=$(( LG_H / 2 )); LG_MIN_COLS=$(( LG_W + 8 ))
lg_qm_vazio() { local y; QM=(); for (( y = 0; y < LG_H; y++ )); do QM[y]="$LG_QM_VAZIA"; done; }
lg_qm_cheio() { local y; QM=(); for (( y = 0; y < LG_H; y++ )); do QM[y]="${LG_MASK[y]//[bsr]/=}"; done; }
lg_qm_poe() { # <x> <y> <classe>
  [ "$2" -ge 0 ] && [ "$2" -lt "$LG_H" ] && [ "$1" -ge 0 ] && [ "$1" -lt "$LG_W" ] || return 0
  QM[$2]="${QM[$2]:0:$1}$3${QM[$2]:$(( $1 + 1 ))}"
}
lg_cel() { # <x> <linha de célula> — recompõe CEL[cy*LG_W+x] a partir do QM
  local x="$1" cy="$2" y1 y2 c1 c2 f
  y1=$(( cy * 2 )); y2=$(( y1 + 1 )); c1="${QM[y1]:x:1}"; c2="${QM[y2]:x:1}"
  if [ "$c1" = '.' ]; then
    case "$c2" in
      '.') CEL[cy * LG_W + x]=' ' ;;
      '=') CEL[cy * LG_W + x]="${NC}${LG_FG[y2 * LG_W + x]}${UI_G_BAIXO}" ;;
      h)   CEL[cy * LG_W + x]="${NC}${LG_FGH[y2 * LG_W + x]}${UI_G_BAIXO}" ;;
      t)   CEL[cy * LG_W + x]="${NC}${LG_FG_T}${UI_G_BAIXO}" ;;
      a)   CEL[cy * LG_W + x]="${NC}${LG_FG_A}${UI_G_BAIXO}" ;;
      g)   CEL[cy * LG_W + x]="${NC}${LG_FG_G}${UI_G_BAIXO}" ;;
    esac
    return 0
  fi
  case "$c1" in
    '=') f="${LG_FG[y1 * LG_W + x]}" ;; h) f="${LG_FGH[y1 * LG_W + x]}" ;;
    t) f="$LG_FG_T" ;; a) f="$LG_FG_A" ;; g) f="$LG_FG_G" ;;
  esac
  case "$c2" in
    '.') CEL[cy * LG_W + x]="${NC}${f}${UI_G_TOPO}" ;;
    '=') CEL[cy * LG_W + x]="${f}${LG_BG[y2 * LG_W + x]}${UI_G_TOPO}" ;;
    h)   CEL[cy * LG_W + x]="${f}${LG_BGH[y2 * LG_W + x]}${UI_G_TOPO}" ;;
    t)   CEL[cy * LG_W + x]="${f}${LG_BG_T}${UI_G_TOPO}" ;;
    a)   CEL[cy * LG_W + x]="${f}${LG_BG_A}${UI_G_TOPO}" ;;
    g)   CEL[cy * LG_W + x]="${f}${LG_BG_G}${UI_G_TOPO}" ;;
  esac
}
lg_compor_tudo() { local x cy; for (( cy = 0; cy < LG_LINHAS; cy++ )); do for (( x = 0; x < LG_W; x++ )); do lg_cel "$x" "$cy"; done; done; }
lg_init() {
  [ -n "${LG_PRONTO:-}" ] && return 0
  local i n=$(( LG_W * LG_H )) c r g b e y
  LG_FG=(); LG_BG=(); LG_FGH=(); LG_BGH=()
  for (( i = 0; i < n; i++ )); do
    c="${LG_RGB[i]}"; r="${c%%;*}"; b="${c##*;}"; g="${c#*;}"; g="${g%;*}"
    if [ "$UI_DEPTH" = "24" ]; then
      printf -v e '\033[38;2;%sm' "$c"; LG_FG[i]="$e"
      printf -v e '\033[48;2;%sm' "$c"; LG_BG[i]="$e"
      r=$(( r + (255 - r) * 45 / 100 )); g=$(( g + (255 - g) * 45 / 100 )); b=$(( b + (255 - b) * 45 / 100 ))
      printf -v e '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"; LG_FGH[i]="$e"
      printf -v e '\033[48;2;%d;%d;%dm' "$r" "$g" "$b"; LG_BGH[i]="$e"
    else
      e=$(( 16 + 36*(r*5/255) + 6*(g*5/255) + (b*5/255) ))
      printf -v c '\033[38;5;%dm' "$e"; LG_FG[i]="$c"; printf -v c '\033[48;5;%dm' "$e"; LG_BG[i]="$c"
      r=$(( r + (255 - r) * 45 / 100 )); g=$(( g + (255 - g) * 45 / 100 )); b=$(( b + (255 - b) * 45 / 100 ))
      e=$(( 16 + 36*(r*5/255) + 6*(g*5/255) + (b*5/255) ))
      printf -v c '\033[38;5;%dm' "$e"; LG_FGH[i]="$c"; printf -v c '\033[48;5;%dm' "$e"; LG_BGH[i]="$c"
    fi
  done
  LG_FG_T="$(rgb 255 255 255)"; LG_BG_T="$(rgbbg 255 255 255)"     # traço e raio aceso
  LG_FG_A="$(rgb 190 242 255)"; LG_BG_A="$(rgbbg 34 211 238)"      # partícula em voo
  LG_FG_G="$(rgb 34 211 238)";  LG_BG_G="$(rgbbg 34 211 238)"      # halo (ciano da marca)
  printf -v LG_QM_VAZIA '%*s' "$LG_W" ''; LG_QM_VAZIA="${LG_QM_VAZIA// /.}"
  # Os quadros estáticos, compostos uma vez.
  CEL=(); for (( i = 0; i < LG_W * LG_LINHAS; i++ )); do CEL[i]=' '; done; LG_CEL_VAZIO=("${CEL[@]}")
  QM=(); for (( y = 0; y < LG_H; y++ )); do QM[y]="${LG_MASK[y]//[sr]/.}"; QM[y]="${QM[y]//b/=}"; done
  lg_compor_tudo; LG_CEL_FUNDO=("${CEL[@]}")
  lg_qm_cheio; lg_compor_tudo; LG_CEL_FINAL=("${CEL[@]}")
  QM=(); for (( y = 0; y < LG_H; y++ )); do QM[y]="${LG_MASK[y]//[bs]/h}"; QM[y]="${QM[y]//r/t}"; done
  lg_compor_tudo; LG_CEL_BATE=("${CEL[@]}")
  n=${#LG_HX[@]}
  for (( i = 0; i < n; i++ )); do lg_qm_poe "${LG_HX[i]}" "${LG_HY[i]}" g; lg_cel "${LG_HX[i]}" $(( LG_HY[i] / 2 )); done
  LG_CEL_PICO=("${CEL[@]}")
  LG_PRONTO=1
}
lg_render() { local cy IFS=''; for (( cy = 0; cy < LG_LINHAS; cy++ )); do printf '  %s%s\n' "${CEL[*]:cy * LG_W:LG_W}" "$NC"; done; }
# lg_quadro <n> — compõe e imprime o quadro n; n < 0: quadro final parado.
lg_quadro() {
  local n="$1" i t x y k d total meio cabeca cauda lim cyl
  lg_init
  if [ "$n" -lt 0 ]; then CEL=("${LG_CEL_FINAL[@]}"); lg_render; return 0; fi
  if [ "$n" -lt "$LG_Q_MONTA" ]; then
    # ── ato 1: o fundo sobe como líquido; o escudo voa e assenta ────────────
    lim=$(( LG_H - (n + 1) * LG_H / LG_Q_MONTA )); [ "$lim" -lt 0 ] && lim=0
    for (( y = 0; y < LG_H; y++ )); do
      if [ "$y" -ge "$lim" ]; then QM[y]="${LG_MASK[y]//[sr]/.}"; QM[y]="${QM[y]//b/=}"; else QM[y]="$LG_QM_VAZIA"; fi
    done
    cyl=$(( (lim + 1) / 2 ))
    CEL=("${LG_CEL_VAZIO[@]:0:cyl * LG_W}" "${LG_CEL_FUNDO[@]:cyl * LG_W}")
    if [ $(( lim % 2 )) -eq 1 ]; then for (( x = 0; x < LG_W; x++ )); do lg_cel "$x" $(( lim / 2 )); done; fi
    total=${#LG_AX[@]}
    for (( i = 0; i < total; i++ )); do
      d=${LG_ADL[i]}
      if [ "$n" -ge $(( d + LG_A_DUR )) ]; then
        x=${LG_AX[i]}; y=${LG_AY[i]}; QM[y]="${QM[y]:0:x}=${QM[y]:$(( x + 1 ))}"; lg_cel "$x" $(( y / 2 ))
      elif [ "$n" -ge "$d" ]; then
        t=$(( (n - d) * 100 / LG_A_DUR ))
        x=$(( LG_AOX[i] + (LG_AX[i] - LG_AOX[i]) * t / 100 ))
        y=$(( LG_AOY[i] + (LG_AY[i] - LG_AOY[i]) * t / 100 ))
        if [ "$y" -ge 0 ] && [ "$y" -lt "$LG_H" ] && [ "$x" -ge 0 ] && [ "$x" -lt "$LG_W" ]; then
          QM[y]="${QM[y]:0:x}a${QM[y]:$(( x + 1 ))}"; lg_cel "$x" $(( y / 2 ))
        fi
      fi
    done
    lg_render; return 0
  fi
  if [ "$n" -lt $(( LG_Q_MONTA + LG_Q_TRACO )) ]; then
    # ── ato 2: o traço contorna o escudo e retrai, por posição de arco ──────
    lg_qm_cheio; CEL=("${LG_CEL_FINAL[@]}")
    k=$(( n - LG_Q_MONTA )); meio=$(( LG_Q_TRACO / 2 ))
    if [ "$k" -lt "$meio" ]; then cabeca=$(( k * LG_CAMINHO / meio )); cauda=0
    else cabeca=$LG_CAMINHO; cauda=$(( (k - meio) * LG_CAMINHO / meio )); fi
    for (( i = cauda; i < cabeca; i++ )); do
      x=${LG_TX[i]}; y=${LG_TY[i]}; QM[y]="${QM[y]:0:x}t${QM[y]:$(( x + 1 ))}"; lg_cel "$x" $(( y / 2 ))
    done
    lg_render; return 0
  fi
  # ── ato 3: o coração — tum-tum · pausa · tum-tum (quadros pré-compostos) ─
  k=$(( n - LG_Q_MONTA - LG_Q_TRACO ))
  case "$k" in
    1|7|23|29)            CEL=("${LG_CEL_PICO[@]}") ;;
    0|2|6|8|22|24|28|30)  CEL=("${LG_CEL_BATE[@]}") ;;
    *)                    CEL=("${LG_CEL_FINAL[@]}") ;;
  esac
  lg_render
}
ui_banner() {
  local t="${1:-River Bridge}" s="${2:-}" cols n
  cols="$(tput cols 2>/dev/null || echo 0)"; case "$cols" in ''|*[!0-9]*) cols=0 ;; esac
  # Sem UTF-8 os glifos sairiam partidos; sem cor o ícone vira mancha.
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
