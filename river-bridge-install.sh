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
SUDO_CMD="${RUB_SUDO-sudo}"                     # RUB_SUDO="" no gate (stubs, sem root)
TTY_DEV="${TTY_DEV:-/dev/tty}"                  # prompts leem daqui, nunca do stdin (curl | bash)
OP_DRYRUN=0; OP_YES=0; OP_DEPS=0; OP_NOAPP=0; OP_DEMO=0
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
"pronto_fez|pronto: River Bridge instalado/atualizado.|done: River Bridge installed/updated."
"pronto_ja|nada a fazer: tudo já estava instalado e atual.|nothing to do: everything was already installed and current."
"dry_fim|dry-run concluído — nada foi alterado · %s portão(ões) aberto(s)|dry-run finished — nothing was changed · %s gate(s) open"
"prox_app|app: %s (abra pelo Launchpad ou: open \"%s\")|app: %s (open it from Launchpad or: open \"%s\")"
"prox_config|configuração do serviço: %s/etc/bridge.env (edite pelo app → Ajustes)|service config: %s/etc/bridge.env (edit via the app → Settings)"
"prox_runbook|proteção do UDR7 (experimental): docs/UDR7_PROTECAO_SSH_20260901.md — nasce em ensaio|UDR7 protection (experimental): docs/UDR7_PROTECAO_SSH_20260901.md — starts in rehearsal"
"prox_log|relatório desta execução: %s|this run's report: %s"
"idempotente|rode de novo quando quiser: é idempotente|run again whenever you want: it is idempotent"
"interrompido|interrompido na fase: %s (exit %s)|interrupted in phase: %s (exit %s)"
"reexecutar_seguro|reexecutar é seguro: cada fase confere o estado e continua de onde parou|re-running is safe: each phase checks the state and continues where it stopped"
"portao|portão aberto (só avisa em dry-run): %s|gate open (warn-only in dry-run): %s"
"em|em %ss|in %ss"
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

# ── motor de campo em meio-bloco (agnóstico de cena) ──────────────────────────
F_w="$(rgb 255 255 255)"; B_w="$(rgbbg 255 255 255)"
F_i="$(rgb 190 242 255)"; B_i="$(rgbbg 190 242 255)"
F_c="$(rgb 34 211 238)";  B_c="$(rgbbg 34 211 238)"
F_a="$(rgb 245 176 0)";   B_a="$(rgbbg 245 176 0)"
F_v="$(rgb 74 222 128)";  B_v="$(rgbbg 74 222 128)"
F_r="$(rgb 244 63 94)";   B_r="$(rgbbg 244 63 94)"
F_m="$(rgb 217 70 239)";  B_m="$(rgbbg 217 70 239)"
F_d="$(rgb 8 74 90)";     B_d="$(rgbbg 8 74 90)"
F_R=(); B_R=()
ui_rampa() { # 3 paradas r g b → intensidades 1..9
  local i t r g b
  for (( i = 1; i <= 9; i++ )); do
    t=$(( (i - 1) * 200 / 8 ))
    if [ "$t" -le 100 ]; then
      r=$(( $1 + ($4-$1)*t/100 )); g=$(( $2 + ($5-$2)*t/100 )); b=$(( $3 + ($6-$3)*t/100 ))
    else
      t=$(( t - 100 ))
      r=$(( $4 + ($7-$4)*t/100 )); g=$(( $5 + ($8-$5)*t/100 )); b=$(( $6 + ($9-$6)*t/100 ))
    fi
    F_R[i]="$(rgb "$r" "$g" "$b")"; B_R[i]="$(rgbbg "$r" "$g" "$b")"
  done
}
# a rampa do escudo do app: azul-profundo → azul → gelo (o ícone do River Bridge)
ui_rampa 10 40 90  40 130 235  190 242 255
UI_H=24
ui_layout() { local cols="$1"; [ "$cols" -gt 92 ] && cols=92; UI_W=$(( cols - 6 )); printf -v UI_ZERO '%*s' "$UI_W" ''; UI_ZERO=${UI_ZERO// /0}; UI_CX=$(( UI_W / 2 )); UI_CY=$(( UI_H / 2 )); }
f_limpa() { local y; for (( y = 0; y < UI_H; y++ )); do CAMPO[y]="$UI_ZERO"; done; }
f_poe() { # <x> <y> <classe>
  [ "$1" -lt 0 ] && return 0; [ "$1" -ge "$UI_W" ] && return 0
  [ "$2" -lt 0 ] && return 0; [ "$2" -ge "$UI_H" ] && return 0
  CAMPO[$2]="${CAMPO[$2]:0:$1}$3${CAMPO[$2]:$(( $1 + 1 ))}"
}
f_soma() { # <x> <y> <dígito> — só sobe; nunca cobre letra
  [ "$1" -lt 0 ] && return 0; [ "$1" -ge "$UI_W" ] && return 0
  [ "$2" -lt 0 ] && return 0; [ "$2" -ge "$UI_H" ] && return 0
  local atual="${CAMPO[$2]:$1:1}"
  case "$atual" in [0-9]) [ "$atual" -ge "$3" ] && return 0 ;; *) return 0 ;; esac
  CAMPO[$2]="${CAMPO[$2]:0:$1}$3${CAMPO[$2]:$(( $1 + 1 ))}"
}
ui_cor() { # <classe> → CF CB
  case "$1" in
    [1-9]) CF="${F_R[$1]}"; CB="${B_R[$1]}" ;;
    w) CF="$F_w"; CB="$B_w" ;;  i) CF="$F_i"; CB="$B_i" ;;  c) CF="$F_c"; CB="$B_c" ;;
    a) CF="$F_a"; CB="$B_a" ;;  v) CF="$F_v"; CB="$B_v" ;;  r) CF="$F_r"; CB="$B_r" ;;
    m) CF="$F_m"; CB="$B_m" ;;  d) CF="$F_d"; CB="$B_d" ;;
    *) CF=""; CB="" ;;
  esac
}
ui_render() {
  local y x c1 c2 out l1 l2 fg
  for (( y = 0; y < UI_H; y += 2 )); do
    l1="${CAMPO[$y]}"; l2="${CAMPO[$(( y + 1 ))]}"; out='  '
    for (( x = 0; x < UI_W; x++ )); do
      c1="${l1:$x:1}"; c2="${l2:$x:1}"
      if [ "$c1" = '0' ] && [ "$c2" = '0' ]; then out+=' '; continue; fi
      if [ "$c1" = '0' ]; then ui_cor "$c2"; out+="${NC}${CF}${UI_G_BAIXO}"; continue; fi
      ui_cor "$c1"; fg="$CF"
      if [ "$c2" = '0' ]; then out+="${NC}${fg}${UI_G_TOPO}"; continue; fi
      ui_cor "$c2"; out+="${fg}${CB}${UI_G_TOPO}"
    done
    printf '%s%s\n' "$out" "$NC"
  done
}

# =============================================================================
# A CENA — "o escudo acende": o raio se desenha de cima para baixo (branco), o
# escudo do app cresce ao redor dele, e passa a PULSAR ao ritmo dos dados que
# correm do River (esquerda) ao UDR7 (direita) — o mesmo batimento do logo no
# app. Clarão, e o escudo assenta aceso. Quadro final (sem animação): o escudo.
# =============================================================================
UI_Q_RAIO=14; UI_Q_ESCUDO=18; UI_Q_PULSO=36; UI_Q_CLARAO=6
UI_QUADROS=$(( UI_Q_RAIO + UI_Q_ESCUDO + UI_Q_PULSO + UI_Q_CLARAO ))   # 74
UI_ATRASO=0.03
ESC_TOP=1; ESC_ALT=21; ESC_HW=10     # topo, altura e meia-largura do escudo em pixels
esc_hw() { # <linha 0..ESC_ALT> <escala 0..100> → EHW (meia-largura naquela linha)
  local l="$1" s="$2" hw
  if [ "$l" -le 0 ]; then hw=$(( ESC_HW - 2 ))
  elif [ "$l" -le 1 ]; then hw=$(( ESC_HW - 1 ))
  elif [ "$l" -le 11 ]; then hw="$ESC_HW"
  else hw=$(( ESC_HW - (l - 11) * ESC_HW / (ESC_ALT - 11) )); fi
  [ "$hw" -lt 0 ] && hw=0
  EHW=$(( hw * s / 100 ))
}
f_escudo() { # <escala 0..100> <borda> <corpo>
  local s="$1" b="$2" c="$3" l y x alt yc dy
  alt=$(( ESC_ALT * s / 100 )); [ "$alt" -lt 1 ] && return 0
  yc=$(( ESC_TOP + ESC_ALT / 2 ))
  for (( l = 0; l <= ESC_ALT; l++ )); do
    dy=$(( (l - ESC_ALT / 2) * s / 100 )); y=$(( yc + dy ))
    esc_hw "$l" "$s"
    for (( x = UI_CX - EHW; x <= UI_CX + EHW; x++ )); do
      if [ "$x" -eq $(( UI_CX - EHW )) ] || [ "$x" -eq $(( UI_CX + EHW )) ] || [ "$l" -eq 0 ] || [ "$l" -eq "$ESC_ALT" ]; then
        f_poe "$x" "$y" "$b"
      else
        case "$c" in [0-9]) f_soma "$x" "$y" "$c" ;; *) f_poe "$x" "$y" "$c" ;; esac
      fi
    done
  done
}
# O raio: traço superior desce da direita para o centro, degrau, traço inferior
# desce até a ponta. 2 px de largura para ler como raio e não como fio.
RAIO_PTS="4,4 3,5 3,6 2,7 2,8 1,9 1,10 0,11 -1,12 -2,12 -1,12 0,12 1,12 2,12 1,13 1,14 0,15 0,16 -1,17 -1,18 -2,19 -3,20"
f_raio() { # <fração 0..100> <classe>
  local frac="$1" c="$2" n=0 total=22 lim p dx dy
  lim=$(( total * frac / 100 ))
  for p in $RAIO_PTS; do
    n=$(( n + 1 )); [ "$n" -gt "$lim" ] && break
    dx="${p%,*}"; dy="${p#*,}"
    f_poe $(( UI_CX + dx )) $(( ESC_TOP + dy )) "$c"; f_poe $(( UI_CX + dx + 1 )) $(( ESC_TOP + dy )) "$c"
  done
}
f_linhas() { # <fase 0..99> — as linhas de dados River → escudo → UDR7, com pulsos
  local y=$(( ESC_TOP + ESC_ALT / 2 )) x0 x1 x k fase="$1"
  x0=$(( UI_CX - ESC_HW - 22 )); x1=$(( UI_CX - ESC_HW - 2 ))
  for (( x = x0; x <= x1; x++ )); do f_soma "$x" "$y" 2; done
  for (( x = UI_CX + ESC_HW + 2; x <= UI_CX + ESC_HW + 22; x++ )); do f_soma "$x" "$y" 2; done
  for (( k = 0; k < 3; k++ )); do          # três pulsos por lado, defasados
    x=$(( x0 + (fase + k * 33) % 100 * 20 / 100 )); f_poe "$x" "$y" v; f_poe $(( x + 1 )) "$y" v
    x=$(( UI_CX + ESC_HW + 2 + (fase + k * 33 + 50) % 100 * 20 / 100 )); f_poe "$x" "$y" v; f_poe $(( x + 1 )) "$y" v
  done
  # os dois nós: River (esquerda) e UDR7 (direita), quadrados 4x4
  local nx ny
  for (( ny = y - 2; ny <= y + 1; ny++ )); do
    for (( nx = x0 - 5; nx <= x0 - 2; nx++ )); do f_poe "$nx" "$ny" c; done
    for (( nx = UI_CX + ESC_HW + 23; nx <= UI_CX + ESC_HW + 26; nx++ )); do f_poe "$nx" "$ny" c; done
  done
}
ui_quadro() { # <n> (n<0 = final)
  local n="$1" t k corpo borda
  f_limpa
  if [ "$n" -lt 0 ]; then
    f_linhas 0; f_escudo 100 i 5; f_raio 100 w; ui_render; return 0
  fi
  if [ "$n" -lt "$UI_Q_RAIO" ]; then                                   # o raio se desenha
    f_raio $(( (n + 1) * 100 / UI_Q_RAIO )) w
  elif [ "$n" -lt $(( UI_Q_RAIO + UI_Q_ESCUDO )) ]; then                # o escudo cresce
    t=$(( (n - UI_Q_RAIO + 1) * 100 / UI_Q_ESCUDO ))
    f_escudo "$t" c 3; f_raio 100 w
  elif [ "$n" -lt $(( UI_Q_RAIO + UI_Q_ESCUDO + UI_Q_PULSO )) ]; then   # pulsa ao ritmo dos dados
    t=$(( n - UI_Q_RAIO - UI_Q_ESCUDO ))
    k=$(( t % 12 )); [ "$k" -gt 6 ] && k=$(( 12 - k ))                 # 0..6..0
    corpo=$(( 2 + k )); borda=c; [ "$k" -ge 5 ] && borda=i
    f_linhas $(( t * 100 / UI_Q_PULSO * 3 % 100 )); f_escudo 100 "$borda" "$corpo"; f_raio 100 w
  else                                                                 # clarão e assenta
    t=$(( n - UI_Q_RAIO - UI_Q_ESCUDO - UI_Q_PULSO ))
    f_linhas 0
    if [ "$t" -lt 2 ]; then f_escudo 100 w 9; f_raio 100 w
    else f_escudo 100 i $(( 9 - (t - 2) )); f_raio 100 w; fi
  fi
  ui_render
}
ui_banner() {
  local t="${1:-River Bridge}" s="${2:-}" cols n linhas
  cols="$(tput cols 2>/dev/null || echo 0)"; case "$cols" in ''|*[!0-9]*) cols=0 ;; esac
  if [ "$UI_UTF8" = "0" ] || [ "$UI_DEPTH" = "0" ]; then printf '  %s\n' "$t"; [ -n "$s" ] && printf '  %s\n' "$s"; printf '\n'; return 0; fi
  if [ "$UI_ANIM" = "0" ] || [ "$cols" -lt 60 ]; then
    ui_layout "$(( cols < 60 ? 60 : cols ))"; ui_quadro -1
    printf '\n  %s%s%s\n' "$BOLD" "$(ui_gradient "$t")" "$NC"; [ -n "$s" ] && printf '  %s%s%s\n' "$C_MUTED" "$s" "$NC"; printf '\n'; return 0
  fi
  ui_layout "$cols"; linhas=$(( UI_H / 2 )); _ui_hide
  for (( n = 0; n < UI_QUADROS; n++ )); do [ "$n" -gt 0 ] && { tput cuu "$linhas" 2>/dev/null || break; }; ui_quadro "$n"; sleep "$UI_ATRASO"; done
  if tput cuu "$linhas" 2>/dev/null; then ui_quadro -1; fi
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
    else ui_linha "  scripts/install.sh --dry-run ($(msg fonte_dry "$RUB_SRC_URL" "$CACHE_DIR/src.tar.gz" "$CACHE_DIR"))"; fi
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
  ok "$(msg verif_ok \
      "$(printf '%s' "$ver" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')" \
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
      --no-anim) UI_NO_ANIM=1; UI_ANIM=0 ;; --demo) OP_DEMO=1 ;;
      --demo-frame) [ -n "${2:-}" ] || morrer "$E_USO" "$(msg flag_sem_valor --demo-frame)"; UI_NO_ANIM=1; UI_ANIM=0; ui_layout "$(tput cols 2>/dev/null || echo 80)"; ui_quadro "$2"; exit 0 ;;
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
  ui_bar_limpa; printf '%s\n' "$UI_GUT"; printf '%s' "$UI_G_FIM"; printf '%s\n\n' "$(ui_gradient "$(printf '%*s' 76 '' | tr ' ' "$UI_G_REGUA")")"
  if [ "$OP_DRYRUN" = "1" ]; then printf '  %s\n\n' "$(msg dry_fim "$PORTOES_ABERTOS")"; FASE_ATUAL=""; exit 0; fi
  if [ "$FEZ" = "1" ]; then ui_shimmer "  $(msg pronto_fez)"; rc=0; else ui_shimmer "  $(msg pronto_ja)"; rc=100; fi
  [ "$OP_NOAPP" = "0" ] && [ -d "$APP_DEST" ] && printf '  %s\n' "$(msg prox_app "$APP_DEST" "$APP_DEST")"
  printf '  %s\n  %s\n  %s\n  %s\n  %s\n\n' "$(msg prox_config "$PREFIX")" "$(msg prox_runbook)" "$(msg prox_log "$LAST_RUN")" "$(msg idempotente)" "$(msg em $(( SECONDS - t0 )))"
  FASE_ATUAL=""
  exit "$rc"
}
main "$@"
