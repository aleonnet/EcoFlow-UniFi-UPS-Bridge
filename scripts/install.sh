#!/bin/bash
# install.sh — instalador do river-unifi-bridge no Mac mini (ordem 7).
#
# Moldes da casa (ABHOME): manifesto created/preexisting/pending com as três
# regras (pending ANTES do ato; created nunca rebaixa; ausente lê preexisting),
# contrato de fase 0=fez/100=já estava, launchd idempotente (tmp + cmp -s +
# launchctl print prova job), last-run.log escrito no trap EXIT.
#
# Exit codes: 0 fez · 100 tudo já estava · 1 falha · 2 uso · 3 validação ·
# 4 dependência (sem consentimento) · 130 cancelado.
#
# Domínio (decisão do dono 2026-08-31, spec §7A.6/§16): LaunchDaemon (system),
# plists com UserName — o serviço sobe no boot SEM login. Requer sudo.
#
# Seams de teste (gate.sh, documentados de propósito): RUB_PREFIX,
# RUB_LAUNCHD_DIR, RUB_SERVICE_USER, RUB_PYTHON e stubs de brew/launchctl no
# PATH. Fora do gate, os defaults valem.
set -Eeuo pipefail

VERSAO="0.3.0"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${RUB_PREFIX:-/usr/local/river-unifi-bridge}"
LDIR="${RUB_LAUNCHD_DIR:-/Library/LaunchDaemons}"
SERVICE_USER="${RUB_SERVICE_USER:-${SUDO_USER:-$(id -un)}}"
USER_HOME="$(eval echo "~$SERVICE_USER")"
MANIFESTO="$PREFIX/manifest.tsv"
LABEL_BRIDGE="com.river.unifi-bridge"
LOG_AGENTE="$USER_HOME/Library/Logs/river-unifi-bridge.log"
STATE_DIR="${RUB_STATE_DIR:-$USER_HOME/Library/Application Support/river-unifi-bridge}"

DRYRUN=0; JSONPROG=0; CONSENT_BREW=0; FEZ=0
INICIO=$(date +%s); PASSOS=""

uso() {
  cat <<EOF
uso: install.sh [--dry-run] [--json-progress] [--consent-homebrew]
  --dry-run           imprime o plano e sai; nada é escrito
  --json-progress     emite linhas @PROGRESS para a UI de onboarding
  --consent-homebrew  autoriza 'brew install' (sem isto, passo brew = exit 4)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRYRUN=1 ;;
    --json-progress) JSONPROG=1 ;;
    --consent-homebrew) CONSENT_BREW=1 ;;
    --version) echo "$VERSAO"; exit 0 ;;
    -h|--help) uso; exit 0 ;;
    *) echo "argumento desconhecido: $arg"; uso; exit 2 ;;
  esac
done

diga() { printf '│ %s\n' "$1"; }
jp() { [ "$JSONPROG" = "1" ] && printf '@PROGRESS {"step":"%s","status":"%s"}\n' "$1" "$2" || true; }
passo() { PASSOS="$PASSOS$1=$2\n"; }

# last-run.log no trap EXIT: a execução que morre no meio é a que mais precisa
# de registro. Best-effort — nunca derruba a instalação.
escrever_last_run() {
  local rc=$?
  # Regra da casa: dry-run é só leitura — nunca escreve nem o last-run.log.
  [ "$DRYRUN" = "1" ] && return 0
  { mkdir -p "$PREFIX" 2>/dev/null && {
      echo "install.sh v$VERSAO  $(date '+%Y-%m-%dT%H:%M:%S%z')  rc=$rc  dry=$DRYRUN"
      printf '%b' "$PASSOS"
      echo "duração=$(( $(date +%s) - INICIO ))s"
    } > "$PREFIX/last-run.log"; } 2>/dev/null || true
}
trap escrever_last_run EXIT

# ── manifesto ────────────────────────────────────────────────────────────────
man_get() { [ -f "$MANIFESTO" ] && grep -m1 "^$1	" "$MANIFESTO" | cut -f2 || true; }
man_set() {
  mkdir -p "$PREFIX"
  local atual; atual=$(man_get "$1")
  # created NUNCA é rebaixado numa reexecução.
  [ "$atual" = "created" ] && return 0
  if [ -f "$MANIFESTO" ] && grep -q "^$1	" "$MANIFESTO"; then
    local tmp; tmp=$(mktemp); grep -v "^$1	" "$MANIFESTO" > "$tmp" || true
    mv "$tmp" "$MANIFESTO"
  fi
  printf '%s\t%s\n' "$1" "$2" >> "$MANIFESTO"
}

# ── validações ───────────────────────────────────────────────────────────────
[ "$(uname -s)" = "Darwin" ] || { echo "só macOS (validação)"; exit 3; }
if [ "$DRYRUN" = "0" ] && [ "$LDIR" = "/Library/LaunchDaemons" ] && [ "$(id -u)" != "0" ]; then
  echo "LaunchDaemon exige root: rode com sudo (validação)"; exit 3
fi

diga "river-unifi-bridge install v$VERSAO  (usuário de serviço: $SERVICE_USER)"
[ "$DRYRUN" = "1" ] && diga "DRY-RUN: nada será escrito"

# ── fase: Homebrew + pacote ──────────────────────────────────────────────────
# O PATH do root NÃO contém o Homebrew (defeito real de 2026-08-31 17:14 no
# mini: morte em 0 s com 'brew: command not found') — resolver o binário
# explicitamente, nunca confiar no PATH do chamador.
BREW="${RUB_BREW:-}"
if [ -z "$BREW" ]; then
  for cand in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$cand" ] && BREW="$cand" && break
  done
  [ -z "$BREW" ] && BREW="$(command -v brew 2>/dev/null || true)"
fi
[ -n "$BREW" ] && [ -x "$BREW" ] \
  || { echo "Homebrew não encontrado (procurei /opt/homebrew e /usr/local) — instale-o primeiro (dependência)"; exit 4; }

brew_do_usuario() {
  # -H: brew exige HOME do usuário real, não o do root.
  if [ "$(id -u)" = "0" ]; then sudo -H -u "$SERVICE_USER" "$BREW" "$@"; else "$BREW" "$@"; fi
}

garantir_brew_pacote() {  # $1=formula  $2=rotulo
  jp "$2" "checando"
  if brew_do_usuario list --versions "$1" >/dev/null 2>&1; then
    diga "$2: já instalado"; jp "$2" "ja_estava"; passo "$2" 100; return 100
  fi
  if [ "$DRYRUN" = "1" ]; then diga "$2: instalaria via brew ($1)"; passo "$2" plano; return 0; fi
  if [ "$CONSENT_BREW" != "1" ]; then
    echo "$2: exige consentimento explícito (--consent-homebrew) para: brew install $1"
    jp "$2" "sem_consentimento"; exit 4
  fi
  man_set "brew:$1" pending
  diga "$2: brew install $1 (consentido)"
  brew_do_usuario install -q "$1"
  man_set "brew:$1" created
  jp "$2" "ok"; passo "$2" 0; FEZ=1; return 0
}

garantir_brew_pacote nut "nut" || true
if [ "$DRYRUN" = "0" ]; then
  UPSD_BIN="$(brew_do_usuario --prefix 2>/dev/null)/sbin/upsd"
  if [ -x "$UPSD_BIN" ]; then
    NUT_VER=$("$UPSD_BIN" -V 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    diga "nut versão: ${NUT_VER:-desconhecida} (piso 2.8.4 — spec §3.2)"
    # Piso do suporte EcoFlow (networkupstools/nut#2735).
    [ -n "$NUT_VER" ] && [ "$(printf '%s\n2.8.4\n' "$NUT_VER" | sort -V | head -1)" != "2.8.4" ] \
      && { echo "nut $NUT_VER < 2.8.4 (dependência)"; exit 4; }
  fi
fi
garantir_brew_pacote python@3.13 "python313" || true

# ── fase: código + venv ──────────────────────────────────────────────────────
CODIGO_MUDOU=0
instalar_codigo() {
  jp codigo checando
  if [ "$DRYRUN" = "1" ]; then diga "código: copiaria src/ para $PREFIX/src"; passo codigo plano; return 0; fi
  if [ -d "$PREFIX/src/river_unifi_bridge" ] \
     && diff -rq -x '__pycache__' "$RAIZ/src/river_unifi_bridge" "$PREFIX/src/river_unifi_bridge" >/dev/null 2>&1; then
    diga "código: já está atual"; jp codigo ja_estava; passo codigo 100; return 100
  fi
  man_set "dir:$PREFIX/src" pending
  mkdir -p "$PREFIX/src"
  rm -rf "$PREFIX/src/river_unifi_bridge"
  cp -R "$RAIZ/src/river_unifi_bridge" "$PREFIX/src/"
  find "$PREFIX/src" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
  man_set "dir:$PREFIX/src" created
  CODIGO_MUDOU=1
  diga "código: instalado em $PREFIX/src"; jp codigo ok; passo codigo 0; FEZ=1
}
instalar_codigo || true

# O README manda desinstalar por $PREFIX/scripts/uninstall.sh — mas até
# 2026-09-02 ninguém copiava o script para lá (medido no mini: prefixo sem
# scripts/). Classe file: do manifesto; não é código do serviço, logo não
# mexe em CODIGO_MUDOU nem pede kickstart.
instalar_desinstalador() {
  jp desinstalador checando
  local alvo="$PREFIX/scripts/uninstall.sh"
  if [ "$DRYRUN" = "1" ]; then diga "desinstalador: copiaria scripts/uninstall.sh para $alvo"; passo desinstalador plano; return 0; fi
  if [ -f "$alvo" ] && cmp -s "$RAIZ/scripts/uninstall.sh" "$alvo"; then
    diga "desinstalador: já está atual"; jp desinstalador ja_estava; passo desinstalador 100; return 100
  fi
  man_set "file:$alvo" pending
  mkdir -p "$PREFIX/scripts"
  install -m 0755 "$RAIZ/scripts/uninstall.sh" "$alvo"
  man_set "file:$alvo" created
  diga "desinstalador: instalado em $alvo"; jp desinstalador ok; passo desinstalador 0; FEZ=1
}
instalar_desinstalador || true

criar_venv() {
  jp venv checando
  if [ "$DRYRUN" = "1" ]; then diga "venv: criaria em $PREFIX/venv (python3.13 + aiohttp)"; passo venv plano; return 0; fi
  if [ -x "$PREFIX/venv/bin/python" ] \
     && "$PREFIX/venv/bin/python" -c "import aiohttp" >/dev/null 2>&1; then
    diga "venv: já está pronto"; jp venv ja_estava; passo venv 100; return 100
  fi
  local py="${RUB_PYTHON:-$(brew_do_usuario --prefix python@3.13 2>/dev/null)/bin/python3.13}"
  [ -x "$py" ] || { echo "python3.13 não encontrado ($py) (dependência)"; exit 4; }
  man_set "dir:$PREFIX/venv" pending
  "$py" -m venv "$PREFIX/venv"
  "$PREFIX/venv/bin/pip" -q install "aiohttp>=3.12"
  man_set "dir:$PREFIX/venv" created
  CODIGO_MUDOU=1
  diga "venv: criado"; jp venv ok; passo venv 0; FEZ=1
}
criar_venv || true

gerar_env() {
  jp config checando
  local alvo="$PREFIX/etc/bridge.env"
  if [ "$DRYRUN" = "1" ]; then diga "config: geraria $alvo (0600, dono $SERVICE_USER; etc/ do mesmo dono)"; passo config plano; return 0; fi
  # A pasta etc/ tem de ser do usuário do serviço, não do root: o daemon grava
  # bridge.env.bak e troca o arquivo ao salvar Ajustes pelo app. Com a pasta do
  # root, todo PUT /v1/config morria em 500 (medido no Mac mini em 2026-09-02).
  # Corrigido também na reexecução, para consertar instalações antigas.
  mkdir -p "$PREFIX/etc"
  chown "$SERVICE_USER" "$PREFIX/etc" 2>/dev/null || true
  if [ -f "$alvo" ]; then diga "config: já existe (preservado)"; jp config ja_estava; passo config 100; return 100; fi
  man_set "file:$alvo" pending
  cp "$RAIZ/config/river-unifi-bridge.env.example" "$alvo"
  chmod 600 "$alvo"; chown "$SERVICE_USER" "$alvo" 2>/dev/null || true
  man_set "file:$alvo" created
  diga "config: gerado ($alvo)"; jp config ok; passo config 0; FEZ=1
}
gerar_env || true

# ── fase: RIVER presente? (T02: boot sem River é caminho de 1ª classe) ──────
detectar_river() {
  jp river checando
  if system_profiler SPUSBDataType 2>/dev/null | grep -qi "ecoflow\|river 3"; then
    diga "RIVER: detectado no USB — configure o NUT (fase driver, próxima execução com hardware validado)"
    jp river detectado; passo river 0
  else
    diga "RIVER: não conectado — serviços NUT ficam PENDENTES no manifesto (o bridge sobe e reporta COMM_LOST honesto)"
    [ "$DRYRUN" = "1" ] || man_set "svc:nut-driver" pending
    jp river ausente; passo river 100
  fi
}
detectar_river || true

# ── fase: LaunchDaemon do bridge (molde haos-install: cmp + print prova) ────
instalar_plist_bridge() {
  jp plist checando
  local plist="$LDIR/$LABEL_BRIDGE.plist"
  local tmp; tmp=$(mktemp)
  cat > "$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL_BRIDGE</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PREFIX/venv/bin/python</string>
        <string>-m</string><string>river_unifi_bridge.service</string>
        <string>--env</string><string>$PREFIX/etc/bridge.env</string>
    </array>
    <key>UserName</key><string>$SERVICE_USER</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ExitTimeOut</key><integer>30</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PYTHONPATH</key><string>$PREFIX/src</string>
        <key>HOME</key><string>$USER_HOME</string>
        <key>RUB_STATE_DIR</key><string>$STATE_DIR</string>
        <key>RUB_LAUNCHD</key><string>1</string>
        <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StandardOutPath</key><string>$LOG_AGENTE</string>
    <key>StandardErrorPath</key><string>$LOG_AGENTE</string>
</dict>
</plist>
EOF
  if [ "$DRYRUN" = "1" ]; then diga "plist: escreveria $plist e faria bootstrap system/$LABEL_BRIDGE"; rm -f "$tmp"; passo plist plano; return 0; fi

  local mudou=1
  if [ -f "$plist" ] && cmp -s "$tmp" "$plist"; then mudou=0; fi
  # Guarda pré-atualização (D12, 2026-09-03): com o serviço carregado e uma
  # instância ARMADA (<id>_armed.json no estado do usuário do serviço), nem
  # reescrever o plist nem reiniciar — o POST /v1/service/restart já recusa
  # reinício armado e o kickstart daqui contornava esse veto. Sai 3 (validação),
  # antes de tocar em qualquer arquivo desta fase.
  if { [ "$mudou" = "1" ] || [ "$CODIGO_MUDOU" = "1" ]; } \
     && launchctl print "system/$LABEL_BRIDGE" >/dev/null 2>&1; then
    local armado
    for armado in "$STATE_DIR"/*_armed.json; do
      if [ -e "$armado" ]; then
        rm -f "$tmp"
        echo "instância ARMADA ($armado): desarme pelo app (ligar modo ensaio) antes de atualizar (validação)"; exit 3
      fi
    done
  fi
  if [ "$mudou" = "1" ]; then
    man_set "plist:$plist" pending
    install -m 0644 "$tmp" "$plist"
    [ "$(id -u)" = "0" ] && chown root:wheel "$plist" || true
    man_set "plist:$plist" created
  fi
  rm -f "$tmp"

  # Arquivo igual NÃO prova job carregado (lição da casa) — provar com print.
  if launchctl print "system/$LABEL_BRIDGE" >/dev/null 2>&1; then
    if [ "$mudou" = "1" ]; then
      launchctl bootout "system/$LABEL_BRIDGE" 2>/dev/null || true
      # Corrida real medida (mini, 17:22): bootstrap logo após bootout pode
      # falhar com "5: Input/output error" enquanto o job antigo morre —
      # tentar 3x. E NUNCA declarar sucesso sem o print provar (o set -e
      # fica suprimido dentro desta função; checagem explícita obrigatória).
      local tent=0
      until launchctl bootstrap system "$plist" 2>/dev/null; do
        tent=$((tent + 1))
        [ "$tent" -ge 3 ] && break
        sleep 1
      done
      launchctl print "system/$LABEL_BRIDGE" >/dev/null 2>&1 \
        || { echo "bridge: recarga NÃO provada por launchctl print após $tent tentativas (falha)"; exit 1; }
      diga "plist: atualizado, recarregado e provado (launchctl print)"; jp plist ok; passo plist 0; FEZ=1
    elif [ "$CODIGO_MUDOU" = "1" ]; then
      # Plist igual mas código/venv novos: o job carregado ainda roda o código
      # antigo (medido no mini, 2026-09-01). kickstart -k reinicia no ato; o
      # print prova que voltou.
      launchctl kickstart -k "system/$LABEL_BRIDGE" 2>/dev/null || true
      launchctl print "system/$LABEL_BRIDGE" >/dev/null 2>&1 \
        || { echo "bridge: job não provado após kickstart (falha)"; exit 1; }
      diga "plist: igual; código novo → serviço reiniciado (kickstart) e provado"; jp plist ok; passo plist 0; FEZ=1
    else
      diga "plist: já instalado e carregado"; jp plist ja_estava; passo plist 100; return 100
    fi
  else
    launchctl bootstrap system "$plist" 2>/dev/null || launchctl load -w "$plist" 2>/dev/null || true
    launchctl print "system/$LABEL_BRIDGE" >/dev/null 2>&1 \
      || { echo "bridge: launchctl print NÃO prova o job carregado (falha)"; exit 1; }
    diga "plist: instalado e job provado carregado (launchctl print)"; jp plist ok; passo plist 0; FEZ=1
  fi
}
instalar_plist_bridge || true

diga "concluído."
if [ "$DRYRUN" = "1" ]; then exit 0; fi
[ "$FEZ" = "1" ] && exit 0 || exit 100
