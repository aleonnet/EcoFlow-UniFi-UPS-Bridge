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
#   --no-open        não abre o app ao terminar
#   --release TAG    instala a release TAG do GitHub (default: latest)
#   --from-main      baixa o tarball do branch main e compila o app (como até a v0.1.0)
#   --src DIR        usa uma árvore local do repo em vez de baixar (bancada/gate)
#   --no-anim        sem abertura animada · --demo  só a abertura
#   --lang pt|en     idioma (default: locale do Mac)
#
# Canal (desde 2026-09-02): por default o instalador lê o SHA256SUMS da release
# (releases/latest/download, só curl; a tag vem do prefixo do tarball) e baixa dali o
# tarball do código e o River Bridge.app pronto, cada um conferido pelo sha.
# Se a release não for alcançável, cai para o tarball de main com aviso, e o
# relatório e o last-run dizem de onde veio o código (fonte=). RUB_SRC_URL
# explícito no ambiente implica canal main (a cena S12 do gate aponta para um
# file:// e não pode ir à rede); RUB_RELEASE_BASE=file://… é o seam da S18.
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
RBI_VERSION="0.8.4"
E_USO=2; E_VALID=3; E_DEP=4; E_CONEXAO=10; E_FALHA=1; E_CANCEL=130
_src="${BASH_SOURCE[0]:-$0}"
REPO_SLUG="aleonnet/EcoFlow-UniFi-UPS-Bridge"
RUB_RAW_URL="${RUB_RAW_URL:-https://raw.githubusercontent.com/$REPO_SLUG/main/river-bridge-install.sh}"
# "Explícito" é detectado com ${VAR+x} ANTES do default de RUB_SRC_URL abaixo (que usa :-).
RUB_SRC_URL_DADO="${RUB_SRC_URL+x}"
RUB_CANAL="${RUB_CANAL:-${RUB_SRC_URL_DADO:+main}}"; RUB_CANAL="${RUB_CANAL:-release}"
RUB_RELEASE="${RUB_RELEASE:-latest}"            # latest | vX.Y.Z
RUB_RELEASE_BASE="${RUB_RELEASE_BASE:-}"        # seam (file://…); default montado em obter_release
RUB_SRC_URL="${RUB_SRC_URL:-https://github.com/$REPO_SLUG/archive/refs/heads/main.tar.gz}"
RUB_SRC_SHA256="${RUB_SRC_SHA256:-}"          # pino do tarball: dado no ambiente ou lido do SHA256SUMS
APP_SHA256=""; APP_URL=""; APP_NOVO=""; RELEASE_TAG=""; FONTE=""
SRC_DIR="${RUB_SRC_DIR:-}"                      # árvore local (seam do gate / bancada)
CACHE_DIR="${RUB_CACHE_DIR:-$HOME/Library/Caches/river-unifi-bridge}"
STATE_DIR="${RUB_STATE_DIR:-$HOME/Library/Application Support/river-unifi-bridge}"
PREFIX="${RUB_PREFIX:-/usr/local/river-unifi-bridge}"
LABEL_BRIDGE="com.river.unifi-bridge"
APP_DEST="${RUB_APP_DEST:-$HOME/Applications/River Bridge.app}"
API_PORT="${RUB_API_PORT:-}"                   # vazio: lida do bridge.env instalado na verificação
SUDO_CMD="${RUB_SUDO-sudo}"
SERVICO_VERSAO=""                               # lida de /v1/version na verificação                     # RUB_SUDO="" no gate (stubs, sem root)
TTY_DEV="${TTY_DEV:-/dev/tty}"                  # prompts leem daqui, nunca do stdin (curl | bash)
OP_DRYRUN=0; OP_YES=0; OP_DEPS=0; OP_NOAPP=0; OP_DEMO=0; OP_NOOPEN=0
FEZ=0; PASSOS_FEITOS=""; FASE_ATUAL=""; MAIN_INICIADO=0; PORTOES_ABERTOS=0; ULTIMA_FALHA=""

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
"fase_servico|Serviço|Service"
"fase_app|River Bridge.app|River Bridge.app"
"fase_verificacao|Verificação|Verification"
"nao_macos|este instalador é para macOS (launchd, Homebrew, .app)|this installer is for macOS (launchd, Homebrew, .app)"
"macos_ok|macOS %s · %s · v%s|macOS %s · %s · v%s"
"dry_aviso|DRY-RUN: só leitura — nada é baixado, escrito ou instalado|DRY-RUN: read-only — nothing is downloaded, written or installed"
"sem_ferramenta|%s ausente — faz parte do macOS; algo está errado com o sistema|%s missing — it ships with macOS; something is wrong with the system"
"brew_ok|Homebrew presente|Homebrew present"
"brew_falta|Homebrew ausente — o serviço precisa dele (nut, python@3.13)|Homebrew missing — the service needs it (nut, python@3.13)"
"brew_dica|instale-o (https://brew.sh) ou rode de novo com --install-deps (instalador oficial, sem perguntas)|install it (https://brew.sh) or run again with --install-deps (official installer, no questions)"
"brew_instalando|instalando o Homebrew (instalador oficial, NONINTERACTIVE)|installing Homebrew (official installer, NONINTERACTIVE)"
"brew_falhou|o instalador do Homebrew falhou|the Homebrew installer failed"
"swift_ok|Swift %s — o app será compilado aqui|Swift %s — the app will be built here"
"swift_falta|sem Swift/Xcode: o app não será compilado (o serviço instala normalmente); --no-app silencia|no Swift/Xcode: the app will not be built (the service installs normally); --no-app silences this"
"rel_buscando|release: %s|release: %s"
"rel_indisponivel|release indisponível (curl %s) — usando o tarball de main|release unavailable (curl %s) — using the main tarball"
"rel_sem_tarball|SHA256SUMS da release sem o tarball do código — usando o tarball de main|release SHA256SUMS lacks the source tarball — using the main tarball"
"rel_ok|release conferida: código e app vêm com assinatura de integridade|release checked: code and app come with an integrity signature"
"rel_fonte|código: %s|code: %s"
"app_baixando|baixando o app pronto de %s|downloading the prebuilt app from %s"
"app_download_falhou|download do app falhou (%s) — compilando localmente, se houver Swift|app download failed (%s) — building locally, if Swift is available"
"app_sha_div|o app baixado não bate com a assinatura de integridade da release — recusado por segurança. Rode de novo; se repetir, avise: a release está corrompida.|the downloaded app does not match the release integrity signature — refused for safety. Run again; if it repeats, report it: the release is corrupted."
"app_zip_invalido|o zip da release não trouxe River Bridge.app — compilando localmente, se houver Swift|the release zip has no River Bridge.app — building locally, if Swift is available"
"app_assinatura|a assinatura do app baixado não verifica (codesign) — seguindo, ad-hoc|the downloaded app signature does not verify (codesign) — continuing, ad-hoc"
"app_da_release|app pronto da release %s|prebuilt app from release %s"
"verif_sem_versao|o código baixado está incompleto (não tem a versão do serviço). Rode a instalação de novo; se repetir, o download está corrompido.|the downloaded code is incomplete (no service version in it). Run the installer again; if it repeats, the download is corrupted."
"verif_outro_processo|quem responde na porta %s não é o serviço instalado (é %s, na versão %s). Feche esse programa e rode a instalação de novo.|what answers on port %s is not the installed service (it is %s, version %s). Close that program and run the installer again."
"sudo_pede|o sudo vai pedir sua senha UMA vez (quem pergunta é o sudo; o instalador não guarda nem repassa)|sudo will ask for your password ONCE (sudo asks; the installer never stores or forwards it)"
"sudo_sem_tty|sem terminal para o sudo — rode num terminal interativo, ou 'sudo -v' antes|no terminal for sudo — run in an interactive terminal, or 'sudo -v' first"
"sudo_recusado|sudo recusado|sudo refused"
"sem_sudo|sudo ausente|sudo missing"
"fonte_local|árvore local: %s|local tree: %s"
"fonte_local_invalida|%s não parece a árvore do repo (falta scripts/install.sh)|%s does not look like the repo tree (scripts/install.sh missing)"
"fonte_baixando|baixando o código de %s|downloading the code from %s"
"fonte_dry|(dry-run) baixaria %s para %s e extrairia em %s|(dry-run) would download %s to %s and extract it under %s"
"fonte_falhou|download falhou (%s) — repositório privado, sem rede ou URL errada; use --src DIR ou RUB_SRC_URL|download failed (%s) — private repository, no network or wrong URL; use --src DIR or RUB_SRC_URL"
"fonte_sha_div|o código baixado não bate com a assinatura de integridade da release — recusado por segurança. Rode de novo; se repetir, avise: a release está corrompida.|the downloaded code does not match the release integrity signature — refused for safety. Run again; if it repeats, report it: the release is corrupted."
"fonte_sha|código baixado (%s)|code downloaded (%s)"
"fonte_cache|código já estava extraído deste download|code already unpacked from this download"
"fonte_extraida|código pronto para instalar|code ready to install"
"fonte_sem_install|o tarball não trouxe scripts/install.sh — árvore inesperada|the tarball has no scripts/install.sh — unexpected tree"
"servico_dry|(dry-run) plano do instalador do serviço:|(dry-run) service installer plan:"
"servico_dry_remoto|o plano do serviço só aparece depois de baixar o código|the service plan only shows after the source is downloaded"
"servico_rodando|o serviço é instalado com sudo: Homebrew (nut e python), código, ambiente, configuração e o serviço do sistema|the service is installed with sudo: Homebrew (nut and python), code, environment, configuration and the system service"
"servico_spin|instalando o serviço|installing the service"
"servico_ok|serviço instalado/atualizado|service installed/updated"
"servico_ja|serviço já estava atual|service already up to date"
"servico_falhou|a instalação do serviço parou:|the service installation stopped:"
"servico_detalhes|detalhes técnicos em %s|technical details in %s"
"app_dry|(dry-run) baixaria o River-Bridge.app.zip da release (ou compilaria com swift build -c release) e instalaria em %s se o binário mudasse|(dry-run) would download River-Bridge.app.zip from the release (or build with swift build -c release) and install to %s if the binary changed"
"app_pulado|app pulado (--no-app)|app skipped (--no-app)"
"app_compilando|swift build -c release (primeira vez pode levar alguns minutos)|swift build -c release (the first time may take a few minutes)"
"app_falhou|a compilação do app falhou (o serviço já está instalado). Detalhes técnicos em %s|the app build failed (the service is already installed). Technical details in %s"
"app_ja|app já está atual em %s|app already current at %s"
"app_instalado|app instalado em %s|app installed at %s"
"app_reaberto|app estava aberto: fechado e reaberto com a versão nova|app was open: closed and reopened with the new version"
"verif_dry|(dry-run) aqui eu esperaria a API local em 127.0.0.1:%s e leria /v1/version e /v1/health|(dry-run) here I would wait for the local API on 127.0.0.1:%s and read /v1/version and /v1/health"
"verif_esperando|esperando a API local (127.0.0.1:%s)|waiting for the local API (127.0.0.1:%s)"
"verif_sem_api|o serviço foi instalado, mas não respondeu em %s segundos. Veja as últimas linhas de %s e rode a instalação de novo.|the service was installed but did not answer within %s seconds. Check the last lines of %s and run the installer again."
"verif_sem_token|o serviço foi instalado, mas não chegou a subir (o arquivo de acesso não foi criado em 30 s). Veja as últimas linhas de %s e rode a instalação de novo.|the service was installed but never came up (its access file was not created within 30 s). Check the last lines of %s and run the installer again."
"verif_ok|serviço v%s no ar · NUT: %s · dispositivos protegidos: %s|service v%s up · NUT: %s · protected devices: %s"
"nut_ok|ok|ok"
"nut_sem|sem dados ainda (o River não está ligado, ou o NUT ainda não respondeu)|no data yet (the River is not plugged in, or NUT has not answered yet)"
"nut_falha|com falha — o NUT não respondeu; veja Saúde no app|failing — NUT did not answer; see Health in the app"
"nut_nao_lido|não lido|not read"
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
"rel_i_servico|o serviço River Bridge%s — sobe sozinho com o Mac e conversa com o NUT local|the River Bridge service%s — starts with the Mac and talks to the local NUT"
"rel_i_app|o app River Bridge — %s|the River Bridge app — %s"
"rel_i_config|sua configuração — %s/etc/bridge.env (edite pelo app → Ajustes)|your configuration — %s/etc/bridge.env (edit via the app → Settings)"
"rel_norte|O River Bridge está na sua barra de menus.|River Bridge is in your menu bar."
"rel_abrindo|abrindo o app…|opening the app…"
"rel_sem_app|o app não foi instalado nesta execução (--no-app ou sem Swift); o serviço já está no ar.|the app was not installed in this run (--no-app or no Swift); the service is already up."
"rel_udr7|cada dispositivo protegido nasce em ensaio — nada é desligado até você armar. Adicione e configure em Ajustes → Dispositivos protegidos.|each protected device starts in rehearsal — nothing is shut down until you arm it. Add and configure under Settings → Protected devices."
"prox_log|relatório desta execução: %s|this run's report: %s"
"interrompido|parou na fase: %s|stopped in phase: %s"
"reexecutar_seguro|rodar de novo é seguro: cada fase confere o que já está feito e continua de onde parou|running again is safe: each phase checks what is already done and continues where it stopped"
"status_feito|Feito até aqui:|Done so far:"
"status_nada|nada ainda|nothing yet"
"status_faltou|Faltou:|Not done:"
"status_proximo|O que fazer agora: %s|What to do now: %s"
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
# Largura REAL da janela. `tput cols` dentro de $( ) com 2>/dev/null não tem terminal
# nenhum para consultar e devolve o padrão da terminfo (80) — medido em 2026-09-02 num
# pty de 40 colunas: era por isso que o corte do spinner nunca agia. Lê pelo terminal de
# controle (/dev/tty, que existe também sob `curl | bash`), com tput sem redirecionar
# o stderr como segunda opção, e 80 quando não há terminal.
ui_cols() { # [fallback sem terminal, default 80]
  local c=""
  c=$( (stty size </dev/tty) 2>/dev/null | awk '{print $2}')
  [ -n "$c" ] || c=$(tput cols 2>/dev/null)
  case "$c" in ''|*[!0-9]*|0) c="${1:-80}" ;; esac
  printf '%s' "$c"
}
ui_lines() { # [fallback sem terminal, default 24] — mesma leitura, para a altura
  local l=""
  l=$( (stty size </dev/tty) 2>/dev/null | awk '{print $1}')
  [ -n "$l" ] || l=$(tput lines 2>/dev/null)
  case "$l" in ''|*[!0-9]*|0) l="${1:-24}" ;; esac
  printf '%s' "$l"
}
ui_rule() {
  local w; w=$(ui_cols)
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
  w=$(ui_cols)
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
  # O quadro é redesenhado com \r. Se ultrapassar a largura da janela ele quebra em duas
  # linhas e o \r só volta ao início da segunda: cada quadro deixa um rastro na primeira
  # ("│ ⠋ sudo scripts/install.sh…│ ⠙ sudo…" — visto no Terminal do Mac mini em 2026-09-02).
  # Por isso o rótulo animado é cortado para caber: calha (2) + spinner (1) + espaço (1).
  local w max quadro="$label"
  w=$(ui_cols)
  max=$(( w - 5 )); [ "$max" -lt 10 ] && max=10
  [ ${#quadro} -gt "$max" ] && quadro="${quadro:0:$(( max - 1 ))}${UI_G_DOTS}"
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s%s %s' "$UI_GUT" "${C_CYAN}" "${UI_SPIN_F:$(( i % UI_SPIN_N )):1}" "$NC" "$quadro"; i=$(( i + 1 ))
    sleep 0.07
  done
  wait "$pid" || rc=$?
  printf '\r\033[2K'; _ui_show
  # 100 é SUCESSO no contrato da casa ("nada a fazer") — a linha 606 já o trata
  # assim. Sem este ramo o passo saía com ✖ e "(exit 100)" na tela, e logo abaixo
  # o chamador imprimia "serviço já estava atual": duas linhas em desacordo, com a
  # errada em vermelho. Visto no Mac mini em 2026-09-01.
  case "$rc" in
    0)   ui_ok "$label" ;;
    100) ui_skip "$label" ;;
    *)   ui_err "$label" ;;   # o código vai ao registro (last-run), não à tela
  esac
  return "$rc"
}

# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────
# Escudo do ícone real (tools/app-icon-render.swift) em 34×40 pixels,
# com 2 px de margem vazia para o halo e o traço não serem cortados.
# LG_MASK: . vazio · b auréola (o fundo do ícone) · s escudo · r raio.
# LG_RGB: a cor REAL de cada pixel do render (índice y*LG_W+x) — é ela que dá
# o volume do ícone; o runtime só monta os escapes uma vez, em lg_init.
LG_W=34
LG_H=40
LG_CAMINHO=90
LG_Q_MONTA=26
LG_RGB=("0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "68;173;162" "70;173;162" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "66;168;158" "63;172;160" "59;174;161" "55;176;162" "58;176;163" "60;176;163" "64;176;163" "66;174;162" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "58;165;156" "55;169;157" "53;174;161" "74;184;170" "116;200;187" "151;212;202" "154;214;204" "125;204;192" "80;189;174" "54;180;165" "55;176;162" "61;174;162" "63;172;160" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "54;158;150" "50;162;152" "45;167;155" "62;176;163" "105;194;182" "162;216;207" "207;232;227" "228;238;236" "231;240;237" "232;239;237" "229;239;236" "212;234;229" "170;219;211" "116;201;188" "67;186;170" "47;177;162" "53;174;160" "57;172;159" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "47;153;146" "40;158;148" "45;167;155" "86;184;172" "146;208;198" "198;228;222" "227;238;235" "232;239;237" "228;238;235" "226;237;234" "226;237;234" "226;237;234" "226;237;234" "227;238;235" "232;239;237" "229;238;236" "205;231;225" "157;215;205" "98;195;181" "54;180;165" "40;175;159" "49;171;158" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "34;151;143" "58;168;157" "120;195;185" "183;220;214" "223;235;232" "234;239;237" "231;237;236" "227;236;234" "227;236;234" "227;236;234" "227;236;234" "227;236;234" "227;236;234" "227;236;234" "233;238;236" "230;237;235" "227;236;234" "230;237;235" "233;238;237" "226;236;234" "194;226;220" "135;207;195" "73;185;170" "38;171;157" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "35;148;142" "124;191;183" "209;230;225" "234;239;237" "233;238;236" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "230;237;235" "166;223;212" "195;229;222" "231;237;235" "229;236;234" "229;236;234" "229;236;234" "232;237;236" "234;238;237" "217;234;230" "146;208;198" "45;172;158" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "21;136;132" "99;177;170" "234;239;237" "233;237;236" "230;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "237;238;237" "160;217;207" "0;189;165" "140;215;202" "237;238;237" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "229;236;234" "231;237;235" "239;240;238" "134;201;191" "22;161;148" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "25;124;124" "2;135;131" "151;199;194" "239;240;238" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "230;235;234" "237;238;237" "188;222;216" "38;179;162" "23;181;162" "191;224;218" "236;237;236" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "237;237;237" "184;219;213" "18;163;150" "27;154;144" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "16;121;121" "0;135;130" "157;202;197" "239;239;238" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "236;237;236" "213;228;226" "60;176;163" "0;164;149" "80;185;172" "230;235;233" "233;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "231;235;234" "237;237;236" "189;220;215" "15;162;149" "23;150;141" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "7;117;118" "0;131;127" "156;201;196" "240;239;238" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "235;236;235" "230;234;233" "91;181;171" "0;152;141" "0;157;143" "146;204;195" "240;238;238" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "233;235;234" "238;237;236" "188;220;215" "1;160;147" "10;147;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;112;114" "0;127;124" "156;200;195" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "240;238;237" "127;192;184" "0;145;135" "0;145;136" "22;159;147" "207;225;221" "238;236;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "189;219;214" "0;156;144" "3;143;135" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;110;112" "0;125;122" "155;199;194" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "243;239;238" "164;205;200" "0;144;135" "0;135;131" "0;138;130" "91;177;168" "238;237;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "189;219;214" "0;155;143" "6;140;134" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "1;107;110" "0;123;120" "155;198;194" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "242;238;237" "196;218;215" "23;148;140" "0;128;125" "0;126;124" "0;133;127" "163;203;198" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;237" "190;218;214" "0;152;141" "0;138;132" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "1;111;112" "0;127;122" "156;200;195" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "238;236;236" "221;230;228" "61;166;156" "0;135;128" "2;127;125" "0;127;124" "44;147;142" "223;229;228" "242;238;237" "239;237;236" "239;237;236" "240;236;236" "240;236;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;237" "189;219;214" "0;155;143" "6;140;134" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;122;119" "0;137;128" "157;204;197" "243;238;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "236;235;235" "235;235;234" "101;189;177" "0;155;141" "4;147;137" "3;143;134" "0;145;135" "43;158;147" "99;183;173" "99;187;175" "100;192;179" "103;196;182" "98;202;185" "164;221;209" "240;236;236" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "190;221;215" "0;162;148" "6;148;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;122;119" "0;137;128" "157;204;197" "243;238;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "242;237;237" "139;204;194" "0;161;146" "4;151;140" "6;144;135" "6;142;134" "6;144;135" "0;147;137" "0;149;138" "0;154;141" "0;160;146" "0;170;152" "0;180;156" "137;213;199" "242;237;236" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "190;221;215" "0;162;148" "1;148;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "2;121;119" "0;137;128" "157;204;197" "243;238;238" "235;235;234" "235;235;234" "235;235;234" "240;236;236" "174;219;210" "0;176;156" "0;162;147" "1;154;142" "3;149;138" "4;147;137" "7;146;136" "7;146;136" "4;147;137" "7;150;139" "4;157;144" "0;167;150" "90;194;179" "230;234;232" "236;235;235" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "190;221;215" "0;162;148" "1;148;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "2;121;118" "0;137;128" "157;204;197" "243;238;238" "235;235;234" "235;235;234" "235;235;234" "240;236;236" "109;205;189" "0;181;159" "6;174;155" "9;167;151" "8;162;147" "11;157;144" "10;151;140" "4;147;137" "7;146;136" "4;151;140" "0;159;145" "51;181;164" "213;228;225" "240;236;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "190;221;215" "0;161;147" "4;147;137" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "7;121;118" "0;137;127" "157;204;197" "243;238;238" "235;235;234" "235;235;234" "235;235;234" "236;235;235" "221;231;229" "199;226;220" "200;225;220" "199;224;219" "201;223;219" "192;219;214" "50;165;152" "0;150;138" "4;151;140" "0;158;144" "10;173;155" "186;220;214" "242;237;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "190;220;215" "0;161;147" "0;146;137" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "2;121;117" "0;137;127" "158;203;197" "243;238;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "237;235;235" "240;236;236" "240;236;236" "239;237;236" "245;239;239" "188;219;213" "0;162;146" "8;156;143" "8;158;145" "0;168;150" "153;211;201" "243;238;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "190;220;215" "0;160;146" "0;146;136" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "7;119;116" "0;135;125" "153;201;194" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "242;237;237" "117;197;185" "0;164;146" "8;162;147" "0;167;149" "116;199;186" "238;237;236" "236;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;237" "186;219;213" "0;158;145" "6;144;135" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;132;123" "132;192;184" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "237;236;235" "220;231;228" "48;182;163" "0;169;151" "0;169;150" "79;190;173" "227;233;231" "237;236;235" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "242;238;237" "169;212;205" "0;155;142" "6;142;134" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;128;120" "90;174;164" "239;237;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "242;237;237" "168;216;207" "0;176;153" "0;173;153" "43;184;164" "207;228;223" "241;237;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "243;238;238" "131;199;189" "0;150;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "5;124;119" "26;150;138" "209;224;221" "239;237;236" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "238;236;236" "99;199;182" "0;178;156" "0;182;159" "179;220;212" "242;237;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "236;235;234" "230;234;233" "68;176;163" "0;146;136" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;134;124" "119;187;177" "243;239;238" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "238;236;235" "209;229;224" "26;190;166" "0;184;159" "146;212;200" "242;237;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "244;238;238" "165;210;203" "0;155;142" "2;141;133" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "2;127;120" "0;146;134" "169;209;202" "244;239;239" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "242;237;237" "149;217;204" "0;191;162" "110;207;189" "236;236;235" "236;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;237" "210;226;223" "47;170;156" "0;147;136" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;133;123" "23;154;141" "176;213;206" "244;239;238" "236;235;234" "235;235;234" "235;235;234" "241;236;236" "148;220;205" "89;209;188" "222;232;230" "238;236;235" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "242;237;237" "215;229;226" "72;178;164" "0;150;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;136;125" "14;154;140" "152;204;195" "238;237;236" "238;236;236" "235;235;234" "235;235;234" "234;235;234" "234;235;234" "237;236;235" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "236;235;234" "243;238;238" "198;223;218" "63;177;162" "0;152;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "2;137;127" "0;151;136" "105;188;175" "216;228;225" "243;238;238" "236;235;234" "235;235;234" "236;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "241;237;236" "236;236;235" "156;209;200" "30;168;152" "0;152;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "9;137;126" "0;148;133" "48;169;154" "162;210;202" "235;236;234" "241;237;237" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "235;235;234" "238;236;235" "242;238;237" "199;225;219" "92;189;174" "0;160;144" "0;150;137" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;145;132" "0;157;140" "90;186;171" "195;222;216" "242;238;237" "238;236;236" "235;235;234" "235;235;234" "237;236;235" "243;238;238" "218;230;227" "130;202;189" "21;171;152" "0;155;140" "10;147;135" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "13;142;130" "0;152;136" "9;167;148" "120;197;184" "213;228;224" "244;238;238" "244;239;238" "225;232;230" "150;208;197" "48;176;159" "0;159;142" "4;151;137" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "4;147;133" "0;155;138" "42;170;153" "130;197;186" "140;201;190" "64;176;160" "0;159;142" "0;153;138" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;146;132" "0;148;133" "0;149;134" "0;148;134" "13;144;132" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0" "0;0;0")
LG_MASK=(
'..................................'
'..................................'
'................bb................'
'.............bbbbbbbb.............'
'...........bbbbbssbbbbbb..........'
'........bbbbbssssssssbbbbb........'
'......bbbbbsssssssssssssbbbb......'
'.....bbbssssssssssssssssssbbb.....'
'....bbssssssssssssssssssssssbb....'
'...bbssssssssssssssrrssssssssbb...'
'..bbssssssssssssssrrssssssssssbb..'
'..bbsssssssssssssrrrssssssssssbb..'
'..bbssssssssssssrrrrssssssssssbb..'
'..bbsssssssssssrrrrsssssssssssbb..'
'..bbsssssssssssrrrrsssssssssssbb..'
'..bbssssssssssrrrrssssssssssssbb..'
'..bbsssssssssrrrrrssssssssssssbb..'
'..bbssssssssrrrrrrrrrrrsssssssbb..'
'..bbsssssssrrrrrrrrrrrrrssssssbb..'
'..bbsssssssrrrrrrrrrrrrsssssssbb..'
'..bbssssssrrrrrrrrrrrrssssssssbb..'
'..bbssssssssssssrrrrrsssssssssbb..'
'..bbssssssssssssrrrrssssssssssbb..'
'..bbsssssssssssrrrrrssssssssssbb..'
'...bbssssssssssrrrrsssssssssssbb..'
'...bbssssssssssrrrsssssssssssbb...'
'...bbsssssssssrrrssssssssssssbb...'
'....bbssssssssrrrssssssssssssbb...'
'....bbsssssssrrrssssssssssssbb....'
'.....bbssssssrrssssssssssssbb.....'
'......bbssssssssssssssssssbb......'
'.......bbbsssssssssssssssbb.......'
'........bbbssssssssssssbbb........'
'..........bbbssssssssbbbb.........'
'...........bbbbsssssbbb...........'
'.............bbbbbbbb.............'
'...............bbbbb..............'
'..................................'
'..................................'
'..................................'
)
LG_TX=(16 15 14 13 12 11 10 9 8 7 6 5 4 4 3 3 3 2 2 2 2 2 2 2 2 2 2 2 2 2 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 31 31 31 31 31 31 31 31 31 31 31 31 31 31 30 30 30 29 28 27 26 25 24 23 22 21 20 19 18 17)
LG_TY=(36 36 35 35 34 34 33 32 32 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 6 5 5 5 4 4 3 3 3 2 2 3 3 3 4 4 4 5 5 6 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 33 34 34 35 36 36 36)
LG_AX=(16 17 13 14 15 16 17 18 19 20 11 12 13 14 15 16 17 18 19 20 21 22 23 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 11 12 13 14 15 16 17 18 19 20 21 22 13 14 15 16 17 18 19 20 15 16 17 18 19)
LG_AY=(2 2 3 3 3 3 3 3 3 3 4 4 4 4 4 4 4 4 4 4 4 4 4 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 6 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 8 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 9 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 11 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 12 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 13 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 14 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 17 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 18 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 19 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 20 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 21 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 22 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 23 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 24 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 25 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 26 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 27 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 28 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 29 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 30 31 31 31 31 31 31 31 31 31 31 31 31 31 31 31 31 31 31 31 31 32 32 32 32 32 32 32 32 32 32 32 32 32 32 32 32 32 32 33 33 33 33 33 33 33 33 33 33 33 33 33 33 33 34 34 34 34 34 34 34 34 34 34 34 34 35 35 35 35 35 35 35 35 36 36 36 36 36)
LG_AOX=(39 41 34 37 39 42 44 47 50 45 29 32 34 37 40 42 45 48 44 46 48 50 52 23 26 28 31 30 33 36 38 41 44 47 49 52 47 49 51 52 54 18 20 22 25 25 28 30 33 36 39 42 45 48 44 47 49 51 53 55 56 58 60 15 16 18 20 23 25 28 31 35 34 37 40 43 46 49 51 54 56 50 51 53 55 56 57 11 13 15 17 19 21 24 26 30 33 37 40 38 41 44 47 50 52 55 57 59 52 53 54 55 56 8 9 11 13 15 17 19 22 25 28 32 36 40 38 42 45 48 51 53 55 57 59 52 53 54 55 56 57 4 5 7 10 11 13 15 18 21 24 27 31 32 36 39 43 47 50 53 56 58 51 53 54 55 56 57 58 59 60 4 5 6 7 9 11 13 15 18 21 24 28 32 36 41 45 49 53 48 51 53 55 56 57 58 59 60 52 53 54 1 2 3 4 6 8 11 13 16 19 23 27 32 37 42 41 45 49 52 54 56 58 59 60 52 53 54 55 56 57 -1 0 0 4 5 6 8 10 13 16 20 25 28 33 39 44 48 52 56 58 60 52 53 54 55 56 57 58 58 59 0 0 0 0 1 3 4 6 9 13 17 21 27 33 40 46 52 56 51 53 54 55 56 57 58 59 59 51 52 52 -4 -3 -3 -3 -2 -1 3 4 6 9 13 18 24 32 41 43 48 52 55 56 57 58 59 60 51 52 53 53 54 54 -7 -7 -7 -2 -2 -1 -1 0 1 4 7 13 19 27 37 46 52 56 58 59 60 52 52 53 53 54 54 55 55 56 -6 -6 -6 -6 -6 -6 -6 -5 -4 1 3 7 13 23 36 49 57 60 52 53 53 53 54 54 54 55 55 48 49 49 -10 -10 -11 -11 -11 -11 -6 -6 -5 -5 -3 -1 3 13 33 47 53 54 54 54 54 54 54 55 47 48 49 49 50 50 -14 -14 -15 -9 -10 -10 -11 -11 -12 -12 -12 -12 -5 -2 13 55 54 52 52 52 53 46 46 47 48 48 49 50 50 51 -11 -12 -13 -13 -14 -15 -16 -17 -18 -12 -13 -15 -17 -20 -23 20 39 44 41 42 43 44 45 46 47 48 49 43 44 45 -15 -16 -17 -18 -19 -20 -14 -15 -16 -18 -20 -22 -24 -25 -20 3 20 29 34 37 40 42 43 45 40 41 42 43 44 45 -19 -20 -21 -14 -16 -17 -18 -20 -21 -23 -25 -26 -18 -17 -12 -1 10 20 27 32 35 34 36 38 39 40 42 43 44 45 -15 -16 -17 -18 -20 -21 -23 -24 -26 -18 -19 -20 -20 -18 -13 -5 4 13 20 24 28 31 33 36 37 39 41 37 38 39 -19 -20 -21 -23 -24 -26 -18 -19 -20 -21 -22 -21 -18 -14 -7 3 9 15 20 24 27 30 33 35 33 34 36 37 38 -22 -23 -24 -25 -18 -19 -20 -21 -22 -23 -23 -21 -19 -8 -4 1 6 11 16 20 24 27 27 29 31 33 34 36 -23 -24 -26 -18 -19 -20 -21 -22 -23 -23 -22 -21 -11 -8 -5 0 4 8 13 17 20 22 25 27 29 31 32 34 -25 -26 -18 -19 -20 -21 -22 -22 -22 -21 -20 -11 -8 -5 -1 2 6 10 14 17 20 22 24 26 28 30 32 -25 -26 -18 -19 -20 -21 -22 -22 -21 -21 -19 -10 -8 -5 -2 0 4 8 11 15 17 20 22 24 26 28 -24 -25 -26 -18 -19 -19 -19 -19 -18 -17 -15 -13 -4 -2 0 3 6 9 12 15 18 20 22 23 -21 -22 -23 -23 -23 -23 -15 -14 -13 -12 -10 -7 -5 -2 0 6 9 11 13 16 18 20 -25 -25 -17 -17 -17 -17 -16 -15 -13 -12 -9 -2 0 2 4 7 9 11 14 16 -17 -17 -18 -17 -17 -16 -15 -14 -12 -5 -3 -1 0 3 5 7 10 12 -15 -15 -15 -14 -13 -12 -11 -9 -7 0 1 3 5 7 9 -19 -19 -18 -10 -9 -8 -7 -5 -3 -1 0 2 -11 -10 -10 -9 -7 -6 -4 -2 -14 -6 -5 -4 -3)
LG_AOY=(-8 -7 -13 -13 -12 -12 -11 -10 -9 -2 -14 -14 -14 -14 -13 -13 -12 -10 -3 -2 -1 0 1 -20 -20 -21 -21 -13 -13 -12 -12 -11 -10 -9 -7 -6 0 1 3 4 6 -20 -21 -22 -23 -14 -15 -15 -15 -14 -14 -13 -11 -10 -2 -1 0 1 3 5 7 8 10 -15 -16 -17 -18 -19 -20 -20 -20 -20 -11 -10 -10 -8 -7 -5 -3 -1 0 6 7 9 11 13 14 -21 -22 -23 -15 -16 -17 -18 -18 -18 -18 -18 -17 -8 -7 -5 -3 -1 0 2 4 7 11 13 14 16 18 -20 -21 -22 -23 -15 -16 -17 -18 -19 -19 -19 -18 -17 -8 -7 -5 -3 0 1 4 6 9 13 14 16 18 19 21 -20 -21 -22 -15 -16 -17 -18 -19 -20 -21 -21 -21 -12 -11 -10 -8 -6 -3 0 2 5 10 12 14 16 18 20 22 23 25 -13 -15 -16 -17 -19 -20 -21 -22 -23 -15 -16 -16 -15 -14 -12 -10 -7 -4 3 6 8 11 14 16 18 20 22 23 25 26 -15 -17 -18 -20 -21 -23 -15 -16 -17 -18 -19 -19 -19 -17 -15 -5 -3 0 3 6 10 13 16 18 21 22 24 26 27 28 -17 -19 -20 -13 -15 -16 -18 -19 -20 -21 -22 -23 -14 -12 -10 -7 -4 0 4 8 12 16 19 21 23 25 27 29 30 32 -11 -12 -14 -15 -16 -18 -20 -21 -23 -15 -16 -17 -17 -16 -13 -9 -4 1 9 13 16 19 22 25 27 29 30 30 31 32 -12 -14 -15 -16 -18 -19 -13 -14 -16 -18 -19 -20 -21 -19 -16 -4 0 6 11 16 20 23 26 29 29 30 32 33 34 35 -13 -15 -16 -10 -11 -12 -14 -16 -18 -20 -22 -23 -15 -15 -12 -6 1 9 16 21 25 27 29 31 33 34 36 37 38 39 -7 -8 -9 -10 -12 -13 -14 -16 -18 -12 -14 -16 -18 -19 -15 -6 5 16 22 27 30 32 34 36 37 39 40 37 38 39 -8 -8 -9 -10 -12 -13 -7 -8 -10 -12 -14 -16 -19 -22 -20 1 16 25 31 34 37 39 40 41 38 39 40 41 42 42 -8 -8 -9 -4 -5 -5 -6 -7 -8 -9 -11 -12 -8 -11 -17 16 34 39 42 43 45 40 41 42 43 44 44 45 46 47 -2 -2 -3 -3 -4 -4 -5 -5 -5 0 0 0 1 5 23 61 56 54 46 46 46 47 47 48 48 49 49 44 44 45 -1 -2 -2 -2 -2 -2 2 2 2 3 5 8 13 23 43 53 56 55 54 54 53 53 53 53 47 47 47 48 48 49 -1 -1 -1 3 3 3 4 5 6 8 11 16 23 32 43 54 59 60 60 60 59 51 51 51 51 52 52 52 53 53 3 4 4 4 5 6 7 8 11 15 18 23 29 38 47 55 61 63 55 56 56 56 56 56 56 56 56 49 50 50 5 6 6 7 9 10 14 16 19 23 28 34 41 49 56 53 56 57 58 59 59 59 59 59 52 52 52 53 53 7 8 9 10 13 15 17 20 23 27 32 38 45 45 50 54 57 59 60 61 62 62 54 54 55 55 55 56 9 10 11 14 16 18 20 23 26 31 35 41 41 46 50 54 57 60 61 62 63 55 56 56 57 57 57 58 13 14 17 18 20 23 26 29 33 38 43 42 46 50 54 57 59 61 62 63 55 56 57 57 58 58 59 15 17 19 21 23 25 28 32 35 39 44 43 46 50 53 56 59 61 62 63 55 56 57 58 58 59 19 21 23 25 27 30 33 36 40 44 48 52 48 51 54 56 58 60 61 62 63 55 56 57 23 25 27 30 33 36 36 39 42 46 49 52 55 58 60 54 56 57 58 59 60 61 27 30 30 32 35 38 41 45 48 51 54 50 52 54 56 58 60 61 62 63 29 32 34 37 40 43 46 49 52 48 50 53 55 57 59 61 62 63 34 37 39 42 45 48 51 53 56 51 53 55 57 58 60 40 43 46 43 45 48 50 53 55 57 59 61 41 44 46 49 51 53 56 58 51 46 49 51 53)
LG_ADL=(17 18 18 16 17 18 16 17 18 16 17 18 16 17 18 16 17 18 16 17 18 16 17 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 15 16 17 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 16 14 15 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 13 14 15 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 12 13 14 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 11 12 13 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 10 11 12 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 9 10 11 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 8 9 10 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 7 8 9 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 8 6 7 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 6 7 5 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 4 5 6 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 4 5 3 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 2 3 4 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 1 2 3 0 1 2 0 1 2 0 1 2 0 1 2 0)
LG_HX=(15 16 17 18 12 13 14 15 18 19 20 21 10 11 12 21 22 23 24 7 8 9 10 24 25 26 5 6 7 26 27 28 4 5 28 29 3 4 29 30 2 3 30 31 1 2 31 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 32 1 2 32 2 31 32 2 31 2 3 31 3 30 31 3 4 29 30 4 5 28 29 5 6 27 28 6 7 26 27 7 8 9 25 26 9 10 23 24 25 10 11 12 21 22 23 12 13 14 20 21 14 15 16 17 18 19 20)
LG_HY=(1 1 1 1 2 2 2 2 2 2 2 2 3 3 3 3 3 3 3 4 4 4 4 4 4 4 5 5 5 5 5 5 6 6 6 6 7 7 7 7 8 8 8 8 9 9 9 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 24 25 25 25 26 26 27 27 27 28 28 28 29 29 29 29 30 30 30 30 31 31 31 31 32 32 32 32 33 33 33 33 33 34 34 34 34 34 35 35 35 35 35 35 36 36 36 36 36 37 37 37 37 37 37 37)
# =============================================================================
# A ABERTURA — o escudo do app, pixel a pixel. Molde: lib/haos-ui.sh do
# haos-install (mesma largura de campo e mesma gramática; a altura é 40 px, não os
# 34 da casa — o escudo é mais alto que largo), com a identidade daqui:
# lá a casa é AZUL com o circuito BRANCO; aqui o escudo é VERDE com o raio
# BRANCO. Nada de azul.
#
# Quatro atos, a 0,03 s por quadro. Os três primeiros duram LG_Q_MONTA (derivado
# pelo gerador do maior atraso de partícula), LG_Q_TRACO e LG_Q_BATE quadros —
# nunca escreva o total à mão aqui: LG_Q_MONTA muda com a altura do canvas.
#   1. CONSTELAÇÃO — cada pixel do escudo é uma partícula que voa de fora da
#      tela em trajetória radial (giro de 40°) e ASSENTA no lugar, de baixo
#      para cima. Trajetórias pré-computadas pelo gerador; o runtime interpola.
#   2. O TRAÇO — a caneta branca contorna a silhueta inteira (com auréola, é a
#      borda dela, que é a que se vê) e se retrai, por posição de arco.
#   3. O CORAÇÃO — o escudo bate: "tum-tum", pausa. A cada batida o RAIO PISCA em
#      branco; entre as batidas ele volta ao verde do ícone.
#   4. Assenta: escudo claro, raio verde parado.
#
# A cor NÃO é calculada aqui: cada pixel usa a sua cor do render, que o gerador
# emite em LG_RGB. É o que dá volume — o gradiente por LINHA do molde borra o raio
# e engrossa a auréola (medido: erro médio de 18,6 por canal, máximo 155). Os
# únicos literais são os da caneta, da partícula e do pisca.
#
# Sem animação: o quadro final parado. Sem UTF-8 ou sem cor: só o título.
# Desenho: uma máscara mutável (QM, uma string por linha de pixel) e um render
# que pinta as classes. Célula = 2 pixels ("▀": frente em cima, fundo embaixo).
# Classes: . fora · s escudo · r raio · t traço · a partícula · g pisca.
# =============================================================================
# LG_Q_TRACO é quadro, não pixel: a caneta percorre LG_CAMINHO pixels nesses 34
# quadros, então a velocidade dela acompanha o tamanho do contorno (88 pixels hoje,
# 65 no canvas menor). Os pixels que sobram no último quadro do ato são apagados
# pelo quadro cheio do ato seguinte.
LG_ATRASO=0.03; LG_A_DUR=8; LG_Q_TRACO=34; LG_Q_BATE=20
LG_QUADROS=$(( LG_Q_MONTA + LG_Q_TRACO + LG_Q_BATE ))
LG_LINHAS=$(( LG_H / 2 )); LG_MIN_COLS=$(( LG_W + 2 ))
# O laço da animação sobe LG_LINHAS a cada quadro (tput cuu). Numa tela mais
# baixa que isso o cuu é grampeado no topo e cada quadro escorrega para baixo —
# por isso o mínimo é derivado do próprio salto, não escolhido.
LG_MIN_LINHAS=$(( LG_LINHAS + 1 ))
lg_init() {
  [ -n "${LG_PRONTO:-}" ] && return 0
  local i y x c r g b e n
  # Um escape de frente e um de fundo POR PIXEL, montados UMA vez a partir de
  # LG_RGB — a cor real do render. É daqui que vem o volume: o escudo claro, o
  # raio vazado no verde do fundo e a auréola que o descola do preto do terminal.
  # Só os pixels do desenho entram; os vazios nunca são consultados.
  LG_FGP=(); LG_BGP=()
  for (( y = 0; y < LG_H; y++ )); do
    for (( x = 0; x < LG_W; x++ )); do
      [ "${LG_MASK[y]:x:1}" = '.' ] && continue
      i=$(( y * LG_W + x )); c="${LG_RGB[i]}"
      r="${c%%;*}"; b="${c##*;}"; g="${c#*;}"; g="${g%;*}"
      if [ "$UI_DEPTH" = "24" ]; then
        printf -v e '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"; LG_FGP[i]="$e"
        printf -v e '\033[48;2;%d;%d;%dm' "$r" "$g" "$b"; LG_BGP[i]="$e"
      else
        # `printf -v nome[i]` NÃO existe no bash 3.2 (o /bin/bash do macOS): ele
        # recusa o alvo com "not a valid identifier". Escreve numa escalar e atribui.
        n=$(( 16 + 36*(r*5/255) + 6*(g*5/255) + (b*5/255) ))
        printf -v e '\033[38;5;%dm' "$n"; LG_FGP[i]="$e"
        printf -v e '\033[48;5;%dm' "$n"; LG_BGP[i]="$e"
      fi
    done
  done
  LG_FG_TRACO="$(rgb 255 255 255)";  LG_BG_TRACO="$(rgbbg 255 255 255)"    # caneta
  LG_FG_A="$(rgb 190 255 232)";      LG_BG_A="$(rgbbg 38 230 178)"         # partícula
  LG_FG_G="$(rgb 236 242 248)";      LG_BG_G="$(rgbbg 236 242 248)"        # pisca do raio
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
  # Cada célula do terminal são DOIS pixels ("▀": frente em cima, fundo embaixo).
  # A cor de cada metade sai da CLASSE: as do desenho (s escudo · r raio · b
  # auréola) usam a cor do próprio pixel; traço, partícula e pisca têm cor fixa.
  local y1 y2 x c1 c2 f g saida i1 i2
  for (( y1 = 0; y1 < LG_H; y1 += 2 )); do
    y2=$(( y1 + 1 )); saida='  '
    for (( x = 0; x < LG_W; x++ )); do
      c1="${QM[y1]:x:1}"; c2="${QM[y2]:x:1}"
      if [ "$c1" = '.' ] && [ "$c2" = '.' ]; then saida+="${NC} "; continue; fi
      i1=$(( y1 * LG_W + x )); i2=$(( y2 * LG_W + x ))
      case "$c1" in
        '.') f='' ;; t) f="$LG_FG_TRACO" ;; a) f="$LG_FG_A" ;; g) f="$LG_FG_G" ;;
        *)   f="${LG_FGP[i1]}" ;;
      esac
      case "$c2" in
        '.') g='' ;; t) g="$LG_BG_TRACO" ;; a) g="$LG_BG_A" ;; g) g="$LG_BG_G" ;;
        *)   g="${LG_BGP[i2]}" ;;
      esac
      if [ "$c1" = '.' ]; then
        case "$c2" in
          t) saida+="${NC}${LG_FG_TRACO}${UI_G_BAIXO}" ;;
          a) saida+="${NC}${LG_FG_A}${UI_G_BAIXO}" ;;
          g) saida+="${NC}${LG_FG_G}${UI_G_BAIXO}" ;;
          *) saida+="${NC}${LG_FGP[i2]}${UI_G_BAIXO}" ;;
        esac
      elif [ "$c2" = '.' ]; then
        saida+="${NC}${f}${UI_G_TOPO}"
      else
        saida+="${f}${g}${UI_G_TOPO}"
      fi
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
  local t="${1:-River Bridge}" s="${2:-}" cols linhas n
  # Tamanho REAL da janela (ui_cols/ui_lines); sem terminal, 0 = um quadro só.
  cols="$(ui_cols 0)"; linhas="$(ui_lines 0)"
  # Sem UTF-8 os glifos sairiam partidos; sem cor o escudo vira mancha.
  if [ "$UI_UTF8" = "0" ] || [ "$UI_DEPTH" = "0" ]; then printf '  %s\n' "$t"; [ -n "$s" ] && printf '  %s\n' "$s"; printf '\n'; return 0; fi
  # Terminal estreito ou sem animação: UM quadro, tudo assentado. Nunca meia
  # animação, e nada que o movimento mostre existe só nele.
  if [ "$UI_ANIM" = "0" ] || [ "$cols" -lt "$LG_MIN_COLS" ] || [ "$linhas" -lt "$LG_MIN_LINHAS" ]; then
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
morrer() { local rc="$1"; shift; ULTIMA_FALHA="$*"; ui_err "$*"; exit "$rc"; }
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
  [ -n "$FONTE" ] && corpo+="  ${C_CYAN}${UI_G_INFO}${NC} $(msg rel_fonte "$FONTE")"$'\n'
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
FASES_TODAS=(); FASES_RESTANTES=()
fase() {
  FASE_ATUAL="$1"; UI_BAR_N=$(( UI_BAR_N + 1 )); ui_phase "$1"
  [ "${#FASES_TODAS[@]}" -gt 0 ] && FASES_RESTANTES=("${FASES_TODAS[@]:$(( UI_BAR_N - 1 ))}") || true
}
LAST_RUN="$STATE_DIR/installer-last-run.log"
limpar() {
  local rc=$?
  ui_bar_limpa; ui_show_cursor
  if [ "$MAIN_INICIADO" = "1" ] && [ "$OP_DRYRUN" = "0" ]; then
    { mkdir -p "$STATE_DIR" 2>/dev/null && {
        printf 'river-bridge-install.sh %s  %s\nrc=%s · fase=%s\nfonte=%s\n%s' "$RBI_VERSION" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$rc" "$FASE_ATUAL" "${FONTE:-?}" "$PASSOS_FEITOS"
      } > "$LAST_RUN"; } 2>/dev/null || true
  fi
  if [ "$rc" != "0" ] && [ "$rc" != "100" ] && [ -n "$FASE_ATUAL" ]; then
    # O status humano ao final de uma falha (dono, 2026-09-03): o que foi feito,
    # o que faltou e a UMA coisa a fazer agora. O código de saída vai ao log.
    UI_BAR_TOTAL=0; ui_bar_limpa   # a barra não é redesenhada depois do status (senão cola no prompt)
    printf '\n' >&2; ui_err "$(msg interrompido "$FASE_ATUAL")"
    ui_linha "$(msg status_feito)" >&2
    if [ -n "$PASSOS_FEITOS" ]; then printf '%s' "$PASSOS_FEITOS" | sed "s/^/$(printf '%s' "$UI_GUT")  ${C_GREEN}${UI_G_OK}${NC} /" >&2
    else ui_linha "  $(msg status_nada)" >&2; fi
    ui_linha "$(msg status_faltou)" >&2
    # bash 3.2 (o /bin/bash do macOS, sob `curl | bash`) trata array vazio como
    # variável indefinida sob `set -u` — medido em 2026-09-03; a guarda ${A[@]+…} evita.
    local f; for f in ${FASES_RESTANTES[@]+"${FASES_RESTANTES[@]}"}; do ui_linha "  ${C_MUTED}${UI_G_SKIP}${NC} $f" >&2; done
    [ -n "$ULTIMA_FALHA" ] && ui_warn "$(msg status_proximo "$ULTIMA_FALHA")" >&2
    ui_info "$(msg reexecutar_seguro)" >&2
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
  if [ -n "$BREW" ]; then ok "$(msg brew_ok)"
  elif [ "$OP_DEPS" = "1" ] && [ "$OP_DRYRUN" = "0" ]; then
    garantir_sudo
    ui_info "$(msg brew_instalando)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null \
      || morrer "$E_DEP" "$(msg brew_falhou)"
    for f in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$f" ] && BREW="$f" && break; done
    [ -n "$BREW" ] || morrer "$E_DEP" "$(msg brew_falhou)"
    ok "$(msg brew_ok)"; FEZ=1
  else
    ui_warn "$(msg brew_falta)"; portao "$(msg brew_dica)"
  fi
  # Swift só entra no pré-voo quando o app vai ser COMPILADO aqui (canal main).
  # No canal release o app vem pronto; se a release não o trouxer, a fase do app
  # checa o Swift na hora (dono, 2026-09-03: "não deveria precisar mais de swift").
  if [ "$OP_NOAPP" = "0" ] && [ "$RUB_CANAL" != "release" ]; then checar_swift || ui_warn "$(msg swift_falta)"; fi
  return 0
}

checar_swift() { # SWIFT_OK=1 e a linha do pré-voo quando há Swift utilizável; 1 quando não há
  command -v swift >/dev/null 2>&1 && swift --version >/dev/null 2>&1 || return 1
  SWIFT_OK=1
  local sv; sv="$(swift --version 2>&1 | head -1 | grep -Eo 'Swift version [0-9.]+' | cut -d' ' -f3)"
  ok "$(msg swift_ok "$sv")"
}

obter_release() { # canal release: lê o SHA256SUMS; deriva URL e pinos do tarball e do app.
  # Qualquer falha → canal main com aviso (decisão ratificada no plano de 2026-09-02;
  # a alternativa era morrer com E_CONEXAO). O relatório e o last-run dizem a fonte.
  local base sums="$CACHE_DIR/SHA256SUMS" efetiva rc=0
  if [ -n "$RUB_RELEASE_BASE" ]; then base="$RUB_RELEASE_BASE"
  elif [ "$RUB_RELEASE" = "latest" ]; then base="https://github.com/$REPO_SLUG/releases/latest/download"
  else base="https://github.com/$REPO_SLUG/releases/download/$RUB_RELEASE"; fi
  ui_info "$(msg rel_buscando "$base")"
  curl -fsSL --retry 2 --max-time 60 -o "$sums.parcial" "$base/SHA256SUMS" 2>"$CACHE_DIR/curl.err" || rc=$?
  if [ "$rc" != "0" ]; then rm -f "$sums.parcial"; ui_warn "$(msg rel_indisponivel "$rc")"; RUB_CANAL=main; return 1; fi
  mv "$sums.parcial" "$sums"
  # A tag NÃO vem do redirect: medido em 2026-09-02, latest/download redireciona para a CDN
  # de assets (release-assets.githubusercontent.com/…), sem a tag no caminho. Ela vem do
  # prefixo do próprio tarball (river-unifi-bridge-<tag>/), lido em fase_fonte após o download.
  RUB_SRC_SHA256="$(awk '$2=="river-unifi-bridge-src.tar.gz"{print $1}' "$sums")"
  APP_SHA256="$(awk '$2=="River-Bridge.app.zip"{print $1}' "$sums")"
  [ -n "$RUB_SRC_SHA256" ] || { ui_warn "$(msg rel_sem_tarball)"; RUB_CANAL=main; return 1; }
  RUB_SRC_URL="$base/river-unifi-bridge-src.tar.gz"
  APP_URL="$base/River-Bridge.app.zip"
  ok "$(msg rel_ok)"
  return 0
}

fase_fonte() { # define SRC_DIR (árvore com scripts/install.sh)
  fase "$(msg fase_fonte)"
  if [ -n "$SRC_DIR" ]; then
    [ -x "$SRC_DIR/scripts/install.sh" ] || morrer "$E_VALID" "$(msg fonte_local_invalida "$SRC_DIR")"
    FONTE="local $SRC_DIR"; ok "$(msg fonte_local "$SRC_DIR")"; return 100
  fi
  local tgz="$CACHE_DIR/src.tar.gz" sha dest
  if [ "$OP_DRYRUN" = "1" ]; then ui_info "$(msg fonte_dry "$RUB_SRC_URL" "$tgz" "$CACHE_DIR")"; SRC_DIR=""; return 0; fi
  mkdir -p "$CACHE_DIR"
  if [ "$RUB_CANAL" = "release" ]; then obter_release || true; fi
  ui_info "$(msg fonte_baixando "$RUB_SRC_URL")"
  # .parcial → mv: um download interrompido nunca é "encontrado" como pronto.
  if ! curl -fsSL --retry 2 --max-time 300 -o "$tgz.parcial" "$RUB_SRC_URL" 2>"$CACHE_DIR/curl.err"; then
    rm -f "$tgz.parcial"; morrer "$E_CONEXAO" "$(msg fonte_falhou "$(tail -1 "$CACHE_DIR/curl.err" 2>/dev/null | cut -c1-120)")"
  fi
  mv "$tgz.parcial" "$tgz"
  sha="$(shasum -a 256 "$tgz" | cut -d' ' -f1)"
  if [ -n "$RUB_SRC_SHA256" ] && [ "$sha" != "$RUB_SRC_SHA256" ]; then rm -f "$tgz"; morrer "$E_VALID" "$(msg fonte_sha_div)"; fi
  if [ "$RUB_CANAL" = "release" ]; then
    # Primeira entrada que casa com o prefixo — não a primeira do tarball: um tar feito de "."
    # lista "./" antes (medido no gate), e o git archive lista a pasta do prefixo.
    RELEASE_TAG="$(tar -tzf "$tgz" 2>/dev/null | sed -n 's|^river-unifi-bridge-\(v[^/]*\)/.*|\1|p' | head -1)"
    FONTE="release ${RELEASE_TAG:-?}"
  else FONTE="main ${sha:0:12}"; fi
  ok "$(msg fonte_sha "$(du -h "$tgz" | cut -f1 | tr -d ' ')")"
  dest="$CACHE_DIR/src-${sha:0:12}"
  if [ -x "$dest/scripts/install.sh" ]; then
    ui_info "$(msg fonte_cache)"; SRC_DIR="$dest"; return 100
  fi
  rm -rf "$dest.parcial"; mkdir -p "$dest.parcial"
  tar -xzf "$tgz" -C "$dest.parcial" --strip-components=1
  [ -x "$dest.parcial/scripts/install.sh" ] || { rm -rf "$dest.parcial"; morrer "$E_VALID" "$(msg fonte_sem_install)"; }
  rm -rf "$dest"; mv "$dest.parcial" "$dest"
  SRC_DIR="$dest"; ok "$(msg fonte_extraida)"; FEZ=1; return 0
}

fase_servico() {
  fase "$(msg fase_servico)"
  local log="$CACHE_DIR/install-service.log" rc=0
  if [ "$OP_DRYRUN" = "1" ]; then
    ui_info "$(msg servico_dry)"
    if [ -n "$SRC_DIR" ]; then
      ( cd "$SRC_DIR" && "./scripts/install.sh" --dry-run 2>&1 ) | grep -E '^(│|✖)' | sed "s/^/$(printf '%s' "$UI_GUT")  /" || true
    else ui_linha "  $(msg servico_dry_remoto)"; fi
    return 0
  fi
  garantir_sudo
  ui_info "$(msg servico_rodando)"
  mkdir -p "$CACHE_DIR"
  # Tudo que exige root vive aqui dentro (brew como o usuário, /usr/local, plist,
  # kickstart). O sudo foi primado agora mesmo: nenhum prompt cai no meio.
  ( cd "$SRC_DIR" && ${SUDO_CMD:+$SUDO_CMD} "./scripts/install.sh" --consent-homebrew ) >"$log" 2>&1 &
  ui_spin "$(msg servico_spin)" $! || rc=$?
  case "$rc" in
    0)   ok "$(msg servico_ok)"; FEZ=1; return 0 ;;
    100) ui_skip "$(msg servico_ja)"; return 100 ;;
    *)
      # A pessoa vê a frase `✖` do instalador (humana); o resto fica no log.
      # Recusas de validação (3) e dependência (4) mantêm o código; o resto é 1.
      local motivo; motivo="$(grep '^✖ ' "$log" 2>/dev/null | tail -1 | sed 's/^✖ //')"
      ui_err "$(msg servico_falhou)"
      if [ -n "$motivo" ]; then ui_err "  $motivo"; ULTIMA_FALHA="$motivo"; else tail -3 "$log" | sed 's/^/    /' >&2; fi
      ui_info "$(msg servico_detalhes "$log")"
      case "$rc" in 3|4) exit "$rc" ;; *) exit "$E_FALHA" ;; esac ;;
  esac
}

baixar_app_release() { # define APP_NOVO com o River Bridge.app extraído do zip da release.
  # Sha divergente do SHA256SUMS = E_VALID (nunca instala). Download/zip inválido = volta 1
  # (o chamador cai para o build local). A extração é por ditto -xk, do próprio macOS.
  local zip="$CACHE_DIR/River-Bridge.app.zip" sha="" dest
  [ -f "$zip" ] && sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
  if [ "$sha" != "$APP_SHA256" ]; then
    ui_info "$(msg app_baixando "$APP_URL")"
    if ! curl -fsSL --retry 2 --max-time 300 -o "$zip.parcial" "$APP_URL" 2>"$CACHE_DIR/curl.err"; then
      rm -f "$zip.parcial"; ui_warn "$(msg app_download_falhou "$(tail -1 "$CACHE_DIR/curl.err" 2>/dev/null | cut -c1-120)")"; return 1
    fi
    mv "$zip.parcial" "$zip"
    sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
    if [ "$sha" != "$APP_SHA256" ]; then rm -f "$zip"; morrer "$E_VALID" "$(msg app_sha_div)"; fi
  fi
  dest="$CACHE_DIR/app-${sha:0:12}"
  if [ ! -x "$dest/River Bridge.app/Contents/MacOS/RiverBridge" ]; then
    rm -rf "$dest.parcial"; mkdir -p "$dest.parcial"
    if ! ditto -xk "$zip" "$dest.parcial" 2>/dev/null || [ ! -x "$dest.parcial/River Bridge.app/Contents/MacOS/RiverBridge" ]; then
      rm -rf "$dest.parcial"; ui_warn "$(msg app_zip_invalido)"; return 1
    fi
    rm -rf "$dest"; mv "$dest.parcial" "$dest"
  fi
  codesign --verify --deep --strict "$dest/River Bridge.app" >/dev/null 2>&1 || ui_warn "$(msg app_assinatura)"
  APP_NOVO="$dest/River Bridge.app"
  ok "$(msg app_da_release "${RELEASE_TAG:-?}")"
  return 0
}

instalar_app_bundle() { # <.app novo> — igual ao instalado: 100; senão fecha, copia .parcial, mv atômico, reabre
  local novo="$1"
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

fase_app() {
  fase "$(msg fase_app)"
  if [ "$OP_NOAPP" = "1" ]; then ui_skip "$(msg app_pulado)"; return 100; fi
  if [ "$OP_DRYRUN" = "1" ]; then ui_info "$(msg app_dry "$APP_DEST")"; return 0; fi
  # 1º o app pronto da release (só arm64: é o que a release traz); senão o build local.
  APP_NOVO=""
  if [ -n "$APP_SHA256" ] && [ "$(uname -m)" = "arm64" ]; then baixar_app_release || APP_NOVO=""; fi
  if [ -z "$APP_NOVO" ]; then
    if [ "$SWIFT_OK" != "1" ]; then checar_swift || { ui_skip "$(msg swift_falta)"; return 100; }; fi
    local log="$CACHE_DIR/build-app.log" rc=0
    ( cd "$SRC_DIR" && ./tools/build-app.sh ) >"$log" 2>&1 &
    ui_spin "$(msg app_compilando)" $! || rc=$?
    [ "$rc" = "0" ] || morrer "$E_FALHA" "$(msg app_falhou "$log")"
    APP_NOVO="$SRC_DIR/macos/RiverBridge/dist/River Bridge.app"
  fi
  instalar_app_bundle "$APP_NOVO"
}

# A porta é a do bridge.env INSTALADO (a pessoa pode ter trocado UI_API_PORT a
# pedido do instalador): lida como o daemon a lê (strip); 35493 sem o arquivo.
porta_instalada() {
  [ -n "$API_PORT" ] && { printf '%s' "$API_PORT"; return 0; }
  { sed -n 's/^[[:space:]]*UI_API_PORT[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$PREFIX/etc/bridge.env" 2>/dev/null | head -1 | grep . ; } || echo 35493
}
fase_verificacao() {
  fase "$(msg fase_verificacao)"
  if [ "$OP_DRYRUN" = "1" ]; then ui_info "$(msg verif_dry "$(porta_instalada)")"; return 0; fi
  if [ "${RUB_SKIP_HEALTH:-0}" = "1" ]; then ui_skip "$(msg verif_pulada)"; return 100; fi
  API_PORT="$(porta_instalada)"
  local token_f="$STATE_DIR/ui-api.token" i T ver health
  for i in $(seq 1 30); do [ -s "$token_f" ] && break; sleep 1; done
  [ -s "$token_f" ] || morrer "$E_FALHA" "$(msg verif_sem_token "$HOME/Library/Logs/river-unifi-bridge.log")"
  T="$(cat "$token_f")"
  ui_info "$(msg verif_esperando "$API_PORT")"
  for i in $(seq 1 30); do
    ver="$(curl -sf -m 2 -H "Authorization: Bearer $T" "http://127.0.0.1:$API_PORT/v1/version" 2>/dev/null || true)"
    [ -n "$ver" ] && break; sleep 1
  done
  [ -n "$ver" ] || morrer "$E_FALHA" "$(msg verif_sem_api 30 "$HOME/Library/Logs/river-unifi-bridge.log")"
  health="$(curl -sf -m 2 -H "Authorization: Bearer $T" "http://127.0.0.1:$API_PORT/v1/health" 2>/dev/null || true)"
  SERVICO_VERSAO="$(printf '%s' "$ver" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')"
  # Quem responde tem de ser o serviço que acabou de ser instalado — versão do
  # CÓDIGO instalado, nos dois canais. Em 2026-09-03 um daemon alheio na porta
  # respondia v0.1.0, o instalado morria ("API local não subiu") e isto era só
  # um aviso seguido de ✔. Agora é falha, nomeando quem ocupa a porta.
  local instalada; instalada="$(sed -n 's/^__version__ = "\([^"]*\)"$/\1/p' "$SRC_DIR/src/river_unifi_bridge/__init__.py" 2>/dev/null | head -1)"
  [ -n "$instalada" ] || morrer "$E_FALHA" "$(msg verif_sem_versao)"
  if [ "$SERVICO_VERSAO" != "$instalada" ]; then
    local opid onome=""; opid="$({ /usr/sbin/lsof -nP -iTCP:"$API_PORT" -sTCP:LISTEN -t 2>/dev/null | head -1; } || true)"
    [ -n "$opid" ] && { onome="$(ps -o comm= -p "$opid" 2>/dev/null | head -1)"; onome="${onome##*/}"; }
    morrer "$E_FALHA" "$(msg verif_outro_processo "$API_PORT" "${onome:-desconhecido}" "$SERVICO_VERSAO")"
  fi
  local nut; nut="$(printf '%s' "$health" | sed -n 's/.*"nut": *"\([^"]*\)".*/\1/p')"
  case "$nut" in ok) nut="$(msg nut_ok)" ;; sem_dados) nut="$(msg nut_sem)" ;; falha) nut="$(msg nut_falha)" ;; *) nut="$(msg nut_nao_lido)" ;; esac
  ok "$(msg verif_ok "$SERVICO_VERSAO" "$nut" "$(printf '%s' "$health" | grep -o '"type": *"' | wc -l | tr -d ' ')")"
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
  --release TAG    instala a release TAG do GitHub (default: latest)
  --from-main      baixa o tarball do branch main e compila o app aqui
  --src DIR        usa uma árvore local do repo em vez de baixar (bancada/gate)
  --no-anim        sem abertura animada · --demo  só a abertura
  --demo-frame T   imprime um quadro com o texto T e sai (captura/validação)
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
  --release TAG    install GitHub release TAG (default: latest)
  --from-main      download the main branch tarball and build the app here
  --src DIR        use a local repo tree instead of downloading (bench/gate)
  --no-anim        no animated opening - --demo  opening only
  --demo-frame T   print one frame with text T and exit (capture/validation)
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
      --release) [ -n "${2:-}" ] || morrer "$E_USO" "$(msg flag_sem_valor --release)"; RUB_RELEASE="$2"; RUB_CANAL=release; shift ;;
      --from-main) RUB_CANAL=main ;;
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
  FASES_TODAS=("$(msg fase_prevoo)" "$(msg fase_fonte)" "$(msg fase_servico)" "$(msg fase_app)" "$(msg fase_verificacao)")
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
