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
# DUAS VOZES na saída (2026-09-03, dono: "isso para usuário final que merda é
# essa"): as linhas `│ …` são para a PESSOA — o que aconteceu, o que foi feito
# por ela, o que falta — sem PID, sem caminho interno, sem sigla. As linhas
# `#  …` são o REGISTRO técnico (PIDs, comandos, códigos), lidas por quem
# depura. O one-liner mostra à pessoa só as linhas `│` e, numa falha, a linha
# `✖`; tudo vai para install-service.log.
#
# TODA checagem que pode recusar a instalação roda ANTES da primeira mutação
# (código, venv, config, plist): recusar no meio deixava metade da atualização
# em disco (medido em 2026-09-03). Cenários tratados, na ordem em que rodam:
#   1. não é macOS → 3 · 2. sem root no domínio system → 3 · 3. sem Homebrew → 4
#   4. um dispositivo protegido ARMADO com o serviço carregado → 3 (desarme no app)
#   5. a porta da API está com OUTRO processo:
#      a) o nosso próprio serviço rodando fora do launchd (resto de sessão de
#         desenvolvimento, ou serviço de outra instalação) → o instalador o
#         ENCERRA e segue (é o nosso daemon; o dono da porta é o job do launchd);
#      b) um programa alheio → 3, nomeando o programa e a saída (fechar ou
#         trocar UI_API_PORT no bridge.env).
#   6. nut abaixo de 2.8.4 → 4.
# Depois da mutação, o serviço só é declarado NO AR quando o PID que escuta a
# porta da API é o PID do job (15 s de espera) — `launchctl print` prova job
# carregado, não serviço vivo: um daemon que parou de propósito sai 0 e o
# KeepAlive não o relança (service.py, parada_deliberada).
#
# Seams de teste (gate.sh, documentados de propósito): RUB_PREFIX,
# RUB_LAUNCHD_DIR, RUB_LAUNCHD_DOMAIN (system | gui/<uid>: o gate prova o ciclo
# real do launchd no domínio do usuário, sem root), RUB_LAUNCHD_LABEL (rótulo
# próprio do gate, para não consultar o serviço real da máquina), RUB_SERVICE_USER,
# RUB_PYTHON, RUB_STATE_DIR, RUB_LOG_FILE, RUB_SKIP_HEALTH=1 (pula a prova
# "serviço na porta"; só com stubs) e stubs de brew/launchctl no PATH.
# Fora do gate, os defaults valem.
set -Eeuo pipefail

VERSAO="0.7.0"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${RUB_PREFIX:-/usr/local/river-unifi-bridge}"
LDIR="${RUB_LAUNCHD_DIR:-/Library/LaunchDaemons}"
DOMINIO="${RUB_LAUNCHD_DOMAIN:-system}"
SERVICE_USER="${RUB_SERVICE_USER:-${SUDO_USER:-$(id -un)}}"
USER_HOME="$(eval echo "~$SERVICE_USER")"
MANIFESTO="$PREFIX/manifest.tsv"
LABEL_BRIDGE="${RUB_LAUNCHD_LABEL:-com.river.unifi-bridge}"   # seam: o gate não pode colidir com o serviço real desta máquina
ALVO_LAUNCHD="$DOMINIO/$LABEL_BRIDGE"
LOG_AGENTE="${RUB_LOG_FILE:-$USER_HOME/Library/Logs/river-unifi-bridge.log}"
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

# ── as duas vozes ────────────────────────────────────────────────────────────
diga() { printf '│ %s\n' "$1"; }                      # para a pessoa
nota() { printf '#  %s\n' "$1"; }                     # registro técnico
# falha <código> <frase para a pessoa> [detalhe técnico…]: a última linha `✖` é
# a que o one-liner mostra; os detalhes vão só ao registro.
falha() {
  local rc="$1" humano="$2"; shift 2
  local d; for d in "$@"; do nota "$d"; done
  printf '✖ %s\n' "$humano"
  exit "$rc"
}
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

# ── validações (cenários 1 e 2) ──────────────────────────────────────────────
[ "$(uname -s)" = "Darwin" ] || falha 3 "este instalador é para macOS."
if [ "$DRYRUN" = "0" ] && [ "$DOMINIO" = "system" ] && [ "$LDIR" = "/Library/LaunchDaemons" ] && [ "$(id -u)" != "0" ]; then
  falha 3 "o serviço sobe no boot da máquina e por isso a instalação precisa de sudo." "id -u = $(id -u); domínio $DOMINIO"
fi

diga "river-unifi-bridge install v$VERSAO  (usuário de serviço: $SERVICE_USER)"
[ "$DRYRUN" = "1" ] && diga "DRY-RUN: nada será escrito"

# ── Homebrew (cenário 3) ─────────────────────────────────────────────────────
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
  || falha 4 "o Homebrew não está instalado — instale-o (https://brew.sh) e rode de novo." "procurei /opt/homebrew/bin/brew, /usr/local/bin/brew e o PATH"

brew_do_usuario() {
  # -H: brew exige HOME do usuário real, não o do root.
  if [ "$(id -u)" = "0" ]; then sudo -H -u "$SERVICE_USER" "$BREW" "$@"; else "$BREW" "$@"; fi
}

# ── o job do launchd e a porta da API (helpers das checagens) ────────────────
# Todos devolvem 0 SEMPRE (saída vazia quando não há o que dizer): sob `set -e`
# + `pipefail`, um `lsof` sem ouvinte (1) ou um `launchctl print` sem job (113)
# numa atribuição derrubava o script — medido no extrato do gate, 2026-09-03.
# A porta lida como o daemon a lê (config.py: strip da chave e do valor).
# A porta do serviço. `RUB_API_PORT` é seam do gate e vem PRIMEIRO de propósito:
# na primeira instalação o bridge.env ainda não existe, e sem isto a guarda de
# porta caía no padrão 35493 — que é a porta do serviço REAL da máquina. O gate
# então encerrava o serviço do dono achando que era uma cópia solta (medido em
# 2026-09-04, no MacBook, com o serviço dele no ar).
porta_api() {
  [ -n "${RUB_API_PORT:-}" ] && { printf '%s' "$RUB_API_PORT"; return 0; }
  { sed -n 's/^[[:space:]]*UI_API_PORT[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$PREFIX/etc/bridge.env" 2>/dev/null | head -1 | grep . ; } || echo 35493
}
job_carregado() { launchctl print "$ALVO_LAUNCHD" >/dev/null 2>&1; }
pid_do_job() { { launchctl print "$ALVO_LAUNCHD" 2>/dev/null | sed -n 's/^[[:space:]]*pid = \([0-9]*\).*/\1/p' | head -1; } || true; }
ouvinte_da_porta() { { /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1; } || true; }
comando_do_pid() { { ps -o command= -p "$1" 2>/dev/null | head -1; } || true; }   # inteiro: as comparações precisam do fim (--env …)
comando_curto() { comando_do_pid "$1" | cut -c1-160; }                            # só para as notas do registro
nome_do_pid() { local c; c="$(ps -o comm= -p "$1" 2>/dev/null | head -1)"; printf '%s' "${c##*/}"; }
e_nosso_daemon() { comando_do_pid "$1" | grep -q "river_unifi_bridge.service"; }
# O serviço INSTALADO (o que o plist lança): o python do venv do prefixo com o
# bridge.env do prefixo. Sem ver o launchd (dry-run sem sudo → rc 113; ou o PID
# do job trocando num relançamento), é por este comando que se reconhece que
# quem está na porta é o próprio serviço, e não uma cópia de outro lugar.
e_o_servico_instalado() { comando_do_pid "$1" | grep -qF "$PREFIX/venv/bin/python" && comando_do_pid "$1" | grep -qF -- "--env $PREFIX/etc/bridge.env"; }
# A resposta do launchd só é confiável com privilégio: sem root, `launchctl
# print system/…` pode devolver 113 sem distinguir "sem permissão" de "não
# existe" (medido em 2026-09-03 para alguns serviços). Com root, ou fora do
# domínio system, ela é a verdade.
launchd_visivel() { [ "$(id -u)" = "0" ] || [ "$DOMINIO" != "system" ]; }

# ── guarda: dispositivo armado (cenário 4) ───────────────────────────────────
# Com o serviço carregado e uma instância ARMADA (<id>_armed.json no estado do
# usuário do serviço), NADA desta instalação acontece: nem código, nem venv,
# nem plist, nem reinício. O POST /v1/service/restart já recusa reinício armado
# e o instalador contornava esse veto. Sai 3; no dry-run só informa. O dry-run
# corre sem sudo, e sem sudo o `launchctl print system/…` pode falhar por
# privilégio (rc 113 medido para alguns serviços em 2026-09-03; para outros
# responde): a informação não depende dele.
guarda_armado() {
  local armado carregado=0 nome
  job_carregado && carregado=1
  for armado in "$STATE_DIR"/*_armed.json; do
    [ -e "$armado" ] || continue
    nome="$(basename "$armado" _armed.json)"
    if [ "$DRYRUN" = "1" ]; then diga "atenção: o dispositivo protegido \"$nome\" está ARMADO — fora do dry-run, a atualização seria recusada até você ligar o modo ensaio no app"; return 0; fi
    [ "$carregado" = "1" ] || return 0
    falha 3 "o dispositivo protegido \"$nome\" está ARMADO. Abra o app, ligue o modo ensaio dele e rode a instalação de novo — atualizar com a proteção armada é recusado de propósito." "arquivo: $armado"
  done
}
guarda_armado

# ── guarda: quem está na porta da API (cenário 5) ────────────────────────────
# Antes de qualquer mutação. Só o job do launchd pode ser dono da porta:
#  - ninguém, ou o próprio job → segue;
#  - o NOSSO daemon fora do launchd → é encerrado aqui (TERM, até 5 s, depois
#    KILL) — sem isso o job novo morre de porta ocupada e o KeepAlive não o
#    relança (medido em 2026-09-03: um daemon de desenvolvimento em 35493);
#  - um programa alheio → recusa (3), com o nome do programa e a saída.
guarda_porta() {
  local porta ouvinte jobpid nome i
  porta="$(porta_api)"
  ouvinte="$(ouvinte_da_porta "$porta")"
  [ -n "$ouvinte" ] || return 0
  jobpid="$(pid_do_job)"
  [ "$ouvinte" = "$jobpid" ] && return 0
  if [ -z "$jobpid" ] && ! launchd_visivel && e_o_servico_instalado "$ouvinte"; then
    # Sem privilégio não enxergo o job (dry-run sem sudo), mas quem escuta é o
    # próprio serviço instalado — é ele o dono da porta. Com o launchd visível
    # e sem job, uma cópia do mesmo caminho é só uma cópia: cai no encerramento.
    nota "porta $porta: PID $ouvinte é o serviço instalado (launchd não consultável com segurança sem sudo)"; return 0
  fi
  if e_nosso_daemon "$ouvinte"; then
    if [ "$DRYRUN" = "1" ]; then
      diga "atenção: uma cópia antiga do serviço está rodando por fora — fora do dry-run ela seria encerrada para o serviço instalado assumir"
      nota "porta $porta: PID $ouvinte ($(comando_curto "$ouvinte"))"; return 0
    fi
    nota "porta $porta ocupada pelo nosso daemon fora do launchd: PID $ouvinte ($(comando_curto "$ouvinte")) — encerrando"
    kill "$ouvinte" 2>/dev/null || true
    for i in 1 2 3 4 5; do kill -0 "$ouvinte" 2>/dev/null || break; sleep 1; done
    kill -0 "$ouvinte" 2>/dev/null && { kill -9 "$ouvinte" 2>/dev/null || true; sleep 1; }
    if kill -0 "$ouvinte" 2>/dev/null; then
      falha 1 "uma cópia antiga do serviço estava rodando por fora e não conseguiu ser encerrada. Reinicie o Mac e rode a instalação de novo." "PID $ouvinte sobreviveu a TERM e KILL"
    fi
    diga "uma cópia antiga do serviço estava rodando por fora — foi encerrada; o serviço instalado assume a porta"
    return 0
  fi
  nome="$(nome_do_pid "$ouvinte")"
  if [ "$DRYRUN" = "1" ]; then
    diga "atenção: a porta $porta já está em uso por outro programa (${nome:-desconhecido}) — fora do dry-run a instalação pararia aqui"
    nota "porta $porta: PID $ouvinte ($(comando_curto "$ouvinte"))"; return 0
  fi
  falha 3 "a porta $porta já está em uso por outro programa (${nome:-desconhecido}). Feche esse programa, ou troque a porta do serviço (UI_API_PORT no arquivo de configuração $PREFIX/etc/bridge.env), e rode a instalação de novo." "porta $porta: PID $ouvinte ($(comando_curto "$ouvinte")); job do launchd: PID ${jobpid:-nenhum}"
}
guarda_porta

# ── fase: Homebrew + pacotes (cenário 6) ─────────────────────────────────────
garantir_brew_pacote() {  # $1=formula  $2=rotulo(registro)  $3=nome para a pessoa
  jp "$2" "checando"
  if brew_do_usuario list --versions "$1" >/dev/null 2>&1; then
    diga "$3: já instalado"; jp "$2" "ja_estava"; passo "$2" 100; return 100
  fi
  if [ "$DRYRUN" = "1" ]; then diga "$3: seria instalado pelo Homebrew"; passo "$2" plano; return 0; fi
  if [ "$CONSENT_BREW" != "1" ]; then
    jp "$2" "sem_consentimento"
    falha 4 "instalar $1 pelo Homebrew exige o seu consentimento (--consent-homebrew)."
  fi
  man_set "brew:$1" pending
  diga "$3: instalando pelo Homebrew"
  brew_do_usuario install -q "$1" >"$PREFIX/brew-$1.log" 2>&1 \
    || falha 1 "o Homebrew não conseguiu instalar $1 (sem internet, ou o próprio Homebrew com problema). Rode 'brew install $1' num terminal para ver o motivo e depois rode a instalação de novo." "brew install $1 falhou; saída em $PREFIX/brew-$1.log"
  man_set "brew:$1" created
  jp "$2" "ok"; passo "$2" 0; FEZ=1; return 0
}

garantir_brew_pacote nut "nut" "NUT (o programa que conversa com o River)" || true
if [ "$DRYRUN" = "0" ]; then
  UPSD_BIN="$({ brew_do_usuario --prefix 2>/dev/null || true; })/sbin/upsd"
  if [ -x "$UPSD_BIN" ]; then
    NUT_VER=$({ "$UPSD_BIN" -V 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1; } || true)
    nota "nut versão: ${NUT_VER:-desconhecida} (piso 2.8.4 — spec §3.2)"
    # Piso do suporte EcoFlow (networkupstools/nut#2735).
    [ -n "$NUT_VER" ] && [ "$(printf '%s\n2.8.4\n' "$NUT_VER" | sort -V | head -1)" != "2.8.4" ] \
      && falha 4 "o NUT instalado ($NUT_VER) é anterior ao 2.8.4, o primeiro que conhece o River — atualize com 'brew upgrade nut' e rode de novo."
  fi
fi
garantir_brew_pacote python@3.13 "python313" "Python 3.13" || true

# ── fase: código + venv ──────────────────────────────────────────────────────
CODIGO_MUDOU=0
instalar_codigo() {
  jp codigo checando
  if [ "$DRYRUN" = "1" ]; then diga "programa do serviço: seria instalado"; nota "src/ → $PREFIX/src"; passo codigo plano; return 0; fi
  if [ -d "$PREFIX/src/river_unifi_bridge" ] \
     && diff -rq -x '__pycache__' "$RAIZ/src/river_unifi_bridge" "$PREFIX/src/river_unifi_bridge" >/dev/null 2>&1; then
    diga "programa do serviço: já está atual"; jp codigo ja_estava; passo codigo 100; return 100
  fi
  man_set "dir:$PREFIX/src" pending
  { mkdir -p "$PREFIX/src" && rm -rf "$PREFIX/src/river_unifi_bridge" && cp -R "$RAIZ/src/river_unifi_bridge" "$PREFIX/src/"; } \
    || falha 1 "não consegui copiar o programa do serviço para $PREFIX (disco cheio, ou pasta sem permissão). Veja o registro e rode a instalação de novo." "cp -R $RAIZ/src/river_unifi_bridge → $PREFIX/src falhou"
  find "$PREFIX/src" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
  man_set "dir:$PREFIX/src" created
  CODIGO_MUDOU=1
  diga "programa do serviço: instalado"; nota "código em $PREFIX/src"; jp codigo ok; passo codigo 0; FEZ=1
}
instalar_codigo || true

# O README manda desinstalar por $PREFIX/scripts/uninstall.sh — mas até
# 2026-09-02 ninguém copiava o script para lá (medido no mini: prefixo sem
# scripts/). Classe file: do manifesto; não é código do serviço, logo não
# mexe em CODIGO_MUDOU nem pede kickstart.
instalar_desinstalador() {
  jp desinstalador checando
  local alvo="$PREFIX/scripts/uninstall.sh"
  if [ "$DRYRUN" = "1" ]; then diga "desinstalador: seria instalado"; nota "scripts/uninstall.sh → $alvo"; passo desinstalador plano; return 0; fi
  if [ -f "$alvo" ] && cmp -s "$RAIZ/scripts/uninstall.sh" "$alvo"; then
    diga "desinstalador: já está atual"; jp desinstalador ja_estava; passo desinstalador 100; return 100
  fi
  man_set "file:$alvo" pending
  { mkdir -p "$PREFIX/scripts" && install -m 0755 "$RAIZ/scripts/uninstall.sh" "$alvo"; } \
    || falha 1 "não consegui gravar o desinstalador em $PREFIX. Veja o registro e rode a instalação de novo." "install -m 0755 → $alvo falhou"
  man_set "file:$alvo" created
  diga "desinstalador: instalado"; nota "em $alvo"; jp desinstalador ok; passo desinstalador 0; FEZ=1
}
instalar_desinstalador || true

criar_venv() {
  jp venv checando
  if [ "$DRYRUN" = "1" ]; then diga "ambiente Python do serviço: seria criado"; nota "$PREFIX/venv (python3.13 + aiohttp)"; passo venv plano; return 0; fi
  if [ -x "$PREFIX/venv/bin/python" ] \
     && "$PREFIX/venv/bin/python" -c "import aiohttp" >/dev/null 2>&1; then
    diga "ambiente Python do serviço: já está pronto"; jp venv ja_estava; passo venv 100; return 100
  fi
  local py="${RUB_PYTHON:-$(brew_do_usuario --prefix python@3.13 2>/dev/null)/bin/python3.13}"
  [ -x "$py" ] || falha 4 "o Python 3.13 do Homebrew não foi encontrado — rode 'brew install python@3.13' e tente de novo." "procurado em $py"
  man_set "dir:$PREFIX/venv" pending
  "$py" -m venv "$PREFIX/venv" >"$PREFIX/venv.log" 2>&1 \
    || falha 1 "não consegui criar o ambiente Python do serviço. Veja o registro e rode a instalação de novo." "$py -m venv $PREFIX/venv falhou; saída em $PREFIX/venv.log"
  "$PREFIX/venv/bin/pip" -q install "aiohttp>=3.12" >>"$PREFIX/venv.log" 2>&1 \
    || falha 1 "não consegui baixar as dependências do serviço (aiohttp) — confira a conexão com a internet e rode de novo." "pip install aiohttp falhou; saída em $PREFIX/venv.log"
  man_set "dir:$PREFIX/venv" created
  CODIGO_MUDOU=1
  diga "ambiente Python do serviço: criado"; jp venv ok; passo venv 0; FEZ=1
}
criar_venv || true

gerar_env() {
  jp config checando
  local alvo="$PREFIX/etc/bridge.env"
  if [ "$DRYRUN" = "1" ]; then diga "configuração: seria criada"; nota "$alvo (0600, dono $SERVICE_USER; etc/ do mesmo dono)"; passo config plano; return 0; fi
  # A pasta etc/ tem de ser do usuário do serviço, não do root: o daemon grava
  # bridge.env.bak e troca o arquivo ao salvar Ajustes pelo app. Com a pasta do
  # root, todo PUT /v1/config morria em 500 (medido no Mac mini em 2026-09-02).
  # Corrigido também na reexecução, para consertar instalações antigas.
  mkdir -p "$PREFIX/etc"
  chown "$SERVICE_USER" "$PREFIX/etc" 2>/dev/null || true
  if [ -f "$alvo" ]; then diga "configuração: já existe (preservada)"; jp config ja_estava; passo config 100; return 100; fi
  man_set "file:$alvo" pending
  cp "$RAIZ/config/river-unifi-bridge.env.example" "$alvo" \
    || falha 1 "não consegui criar a configuração do serviço em $PREFIX. Veja o registro e rode a instalação de novo." "cp env.example → $alvo falhou"
  # Seam do gate (RUB_API_PORT): as cenas precisam de uma porta que não seja a do
  # serviço REAL da máquina que roda o portão — senão elas veem o serviço do dono
  # e reprovam por contaminação. Fora do gate a variável não existe e nada muda.
  if [ -n "${RUB_API_PORT:-}" ]; then
    sed -i '' "s/^UI_API_PORT=.*/UI_API_PORT=$RUB_API_PORT/" "$alvo"
  fi
  chmod 600 "$alvo"; chown "$SERVICE_USER" "$alvo" 2>/dev/null || true
  man_set "file:$alvo" created
  diga "configuração: criada"; nota "em $alvo"; jp config ok; passo config 0; FEZ=1
}
gerar_env || true

# ── fase: RIVER presente? (T02: boot sem River é caminho de 1ª classe) ──────
detectar_river() {
  jp river checando
  if system_profiler SPUSBDataType 2>/dev/null | grep -qi "ecoflow\|river 3"; then
    diga "River: detectado no USB"
    nota "fase driver do NUT: próxima execução com hardware validado"
    jp river detectado; passo river 0
  else
    diga "River: ainda não ligado no USB — o serviço sobe assim mesmo e passa a monitorar quando o aparelho for conectado"
    nota "svc:nut-driver fica pending no manifesto; o daemon reporta COMM_LOST até o NUT responder"
    [ "$DRYRUN" = "1" ] || man_set "svc:nut-driver" pending
    jp river ausente; passo river 100
  fi
}
detectar_river || true

# ── fase: leitura do River pelo NUT, como serviço do SISTEMA ───────────────
# Por que esta fase existe (medido no Mac mini em 2026-09-04): registrar o driver
# do NUT como agente do USUÁRIO deixa a leitura parada até alguém logar — o mini
# reiniciou às 01h17, ninguém logou, e o no-break ficou sem vigia por uma hora.
# Serviço do sistema sobe no boot, sem sessão.
#
# Dois cuidados que vêm de medição, não de gosto:
#  · O aplicativo da EcoFlow, ao abrir, roda `pkill -9 usbhid-ups` e `pkill -9 upsd`
#    como root (lido dentro do pacote dele). Por isso os nossos processos nascem
#    com NOME PRÓPRIO, via `exec -a`: o pkill dele casa por nome e não nos alcança.
#  · A configuração do NUT só é ESCRITA se ainda não existir. Quem já configurou à
#    mão continua com a dele; o instalador nunca sobrescreve essa escolha.
NUT_PREFIX="${RUB_NUT_PREFIX:-/opt/homebrew/opt/nut}"
NUT_ETC="${RUB_NUT_ETC:-/opt/homebrew/etc/nut}"
LABEL_NUT_DRIVER="${RUB_LABEL_NUT_DRIVER:-com.river.nut-driver}"
LABEL_NUT_SERVER="${RUB_LABEL_NUT_SERVER:-com.river.nut-upsd}"

nut_ups_do_env() {   # o nome do aparelho é o que o serviço já espera
  sed -n 's/^NUT_UPS=\(.*\)$/\1/p' "$PREFIX/etc/bridge.env" 2>/dev/null | head -1
}

escreve_se_faltar() {   # 1=caminho 2=modo 3=conteúdo
  [ -e "$1" ] && return 1
  man_set "file:$1" pending
  printf '%s' "$3" > "$1"
  chmod "$2" "$1"
  [ "$(id -u)" = "0" ] && chown "$SERVICE_USER" "$1" || true
  man_set "file:$1" created
  return 0
}

# A conta com que o NOSSO serviço manda no River (mudar o lembrete de bateria
# baixa, desligar o aparelho). É diferente da conta de leitura: aquela é
# `upsmon secondary` e o servidor do no-break lhe recusa qualquer comando.
#
# A senha nasce aqui, aleatória, e mora em DOIS lugares que têm de concordar: a
# conta no `upsd.users` e um arquivo 0600 do diretório de estado, que só o
# serviço lê. Fora do `.env` de propósito — a rota de configuração devolve o
# `.env` inteiro para o aplicativo.
garantir_conta_do_upsd() {   # 1=seção 2=ficha 3=linhas de permissão 4=para que serve
  local secao="$1" ficha="$2" permissoes="$3" proposito="$4"
  local arquivo="$NUT_ETC/upsd.users" senha=""
  # Conta já existente manda: a senha dela é a verdade, e a ficha é reescrita a
  # partir dela. Gerar outra deixaria os dois lados divergentes, e o serviço
  # ouviria "acesso negado" sem ninguém entender por quê.
  if [ -f "$arquivo" ] && grep -q "^\[$secao\]" "$arquivo" 2>/dev/null; then
    senha="$(awk -v s="[$secao]" '$0==s{d=1;next} /^\[/{d=0}
                  d && tolower($0) ~ /^[[:space:]]*password[[:space:]]*=/ {
                    sub(/^[^=]*=[[:space:]]*/, "", $0); gsub(/^"|"$/, "", $0); print; exit }' "$arquivo")"
    if [ -z "$senha" ]; then
      # Seção existe e a senha não é legível: acrescentar outra deixaria duas
      # contas com o mesmo nome e a ficha guardando a que o servidor não usa.
      nota "conta $secao: a seção existe em $arquivo mas não consegui ler a senha; ajuste-a à mão"
      return 1
    fi
  fi
  if [ -z "$senha" ]; then
    senha="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
    man_set "file:$arquivo#$secao" pending
    cat >> "$arquivo" <<EOF

# $proposito
# Senha gerada na instalação; ela também está em $ficha.
[$secao]
    password = $senha
$permissoes
EOF
    chmod 0640 "$arquivo"
    [ "$(id -u)" = "0" ] && chown "$SERVICE_USER" "$arquivo" || true
    man_set "file:$arquivo#$secao" created
  fi
  # ESTE é o primeiro ponto do instalador que cria o diretório de estado — e ele
  # roda como root. Criado sem dono, o serviço (que roda como o usuário) não
  # conseguia escrever nada lá e morria no primeiro ciclo, em máquina nova
  # (revisão fria da 0.5.0, 2.ª rodada). 0700 porque guarda senha e estado.
  if [ ! -d "$STATE_DIR" ]; then
    mkdir -p "$STATE_DIR"
    chmod 0700 "$STATE_DIR"
    [ "$(id -u)" = "0" ] && chown "$SERVICE_USER" "$STATE_DIR" || true
  fi
  # A ficha é reescrita sempre que divergir: é ela que o serviço (e a tela) leem.
  if [ ! -f "$ficha" ] || [ "$(cat "$ficha" 2>/dev/null)" != "$senha" ]; then
    man_set "file:$ficha" pending
    printf '%s' "$senha" > "$ficha"
    chmod 0600 "$ficha"
    [ "$(id -u)" = "0" ] && chown "$SERVICE_USER" "$ficha" || true
    man_set "file:$ficha" created
    return 0
  fi
  return 1
}

garantir_conta_do_aparelho() {
  garantir_conta_do_upsd riverbridge "$STATE_DIR/nut-admin.token" \
    "    actions = SET
    instcmds = ALL" \
    "Conta com que o SERVIÇO manda no aparelho (lembrete de bateria baixa, desligamento). Não a use noutro programa."
}

# A conta do Home Assistant. Ela precisa de instcmds porque é o que faz a
# integração NUT dele oferecer as ordens: medido no código do Home Assistant em
# 2026-09-05, sem usuário e senha ele nem chega a perguntar quais comandos
# existem. É diferente da conta do aplicativo da EcoFlow, que é só de leitura, e
# da nossa, que manda no leitor de fábrica.
garantir_conta_do_home_assistant() {
  garantir_conta_do_upsd homeassistant "$STATE_DIR/nut-homeassistant.token" \
    "    instcmds = ALL" \
    "Conta do Home Assistant: acompanha o River e pode mandar as ordens que a ponte publica (desligar o River, desligar/reiniciar um dispositivo protegido). Cada ordem passa pelas mesmas travas da tela do aplicativo."
}

instalar_leitura_river() {
  jp nut checando
  local ups; ups="$(nut_ups_do_env)"; ups="${ups:-river-office}"
  if [ ! -x "$NUT_PREFIX/bin/usbhid-ups" ]; then
    diga "leitura do River: o NUT ainda não está instalado nesta máquina"
    nota "sem $NUT_PREFIX/bin/usbhid-ups; instale com 'brew install nut' e rode de novo"
    [ "$DRYRUN" = "1" ] || man_set "svc:nut-driver" pending
    jp nut ausente; passo nut 100; return 0
  fi
  if [ "$DRYRUN" = "1" ]; then
    diga "leitura do River: seria registrada como serviço do sistema ($ups)"
    nota "configuração em $NUT_ETC; quem mantém os processos é o serviço"
    jp nut plano; passo nut plano; return 0
  fi

  mkdir -p "$NUT_ETC"
  local mudou=0
  escreve_se_faltar "$NUT_ETC/ups.conf" 0644 "maxretry = 3

[$ups]
    driver = usbhid-ups
    port = auto
    vendorid = 3746
    productid = ffff
    ignorelb
    override.battery.runtime.low = -1
    pollfreq = 1
    pollinterval = 2
    desc = \"EcoFlow RIVER 3 Plus\"
" && mudou=1
  escreve_se_faltar "$NUT_ETC/upsd.conf" 0640 "LISTEN 127.0.0.1 3493
" && mudou=1
  escreve_se_faltar "$NUT_ETC/nut.conf" 0644 "MODE=standalone
" && mudou=1
  escreve_se_faltar "$NUT_ETC/upsd.users" 0640 "# Conta de LEITURA para outros programas desta máquina (o Power Manager da
# EcoFlow aceita apontar para um servidor NUT: Communication mode -> Remote).
# 'secondary' de propósito: acompanha e NÃO pode mandar o River desligar.
[powermanager]
    password = river-local
    upsmon secondary
" && mudou=1
  garantir_conta_do_aparelho && mudou=1
  garantir_conta_do_home_assistant && mudou=1

  # Quem sobe, vigia e para o driver e o servidor do NUT é o NOSSO SERVIÇO
  # (src/river_unifi_bridge/nut_supervisor.py), não o launchd. Três motivos
  # medidos no Mac mini em 2026-09-04: programa de usuário não sobe sem alguém
  # logado; serviço do sistema só o root pausa, e pausar é preciso para emprestar
  # o cabo ao aplicativo da EcoFlow; e o nome próprio dos processos os tira da
  # mira do `pkill -9 usbhid-ups` que aquele aplicativo roda como root.
  #
  # Os registros que a 0.4.1 chegou a criar são removidos aqui, para não existirem
  # dois donos do mesmo cabo.
  local rotulo alvo
  for rotulo in "$LABEL_NUT_DRIVER" "$LABEL_NUT_SERVER"; do
    alvo="$LDIR/$rotulo.plist"
    # Só descarrega o que EXISTE. Pedir ao launchd para descarregar um serviço
    # que nunca foi registrado não é inócuo: além de ruído, o duplê do portão
    # tratava a descarga como global e derrubava o registro do nosso serviço.
    [ -f "$alvo" ] || continue
    launchctl bootout "gui/$(id -u "$SERVICE_USER" 2>/dev/null || echo 501)/$rotulo" 2>/dev/null || true
    launchctl bootout "$DOMINIO/$rotulo" 2>/dev/null || true
    rm -f "$alvo"; man_set "plist:$alvo" removido; mudou=1
  done
  # Leitor solto continua com o cabo, e o serviço não conseguiria abrir o
  # aparelho. São dois casos, e antes só o primeiro era coberto:
  #   1. sessão manual ou instalação antiga, com o nome de fábrica do NUT;
  #   2. FILHO ÓRFÃO de um serviço nosso que morreu sem levá-los junto — esse
  #      nasce com o nome próprio do `exec -a` e escapava do filtro antigo.
  pkill -f "usbhid-ups -a $ups" 2>/dev/null || true
  pkill -f "upsd -u $SERVICE_USER -F" 2>/dev/null || true
  pkill -f "river-bridge-ups -a $ups" 2>/dev/null || true
  pkill -f "river-bridge-upsd -u $SERVICE_USER" 2>/dev/null || true

  if [ "$mudou" = "1" ]; then
    diga "leitura do River: configurada; quem a mantém no ar é o próprio serviço (aparelho $ups)"
    jp nut instalado; passo nut 0
  else
    diga "leitura do River: já estava configurada"
    jp nut ok; passo nut 100
  fi
}
instalar_leitura_river || true

# ── fase: LaunchDaemon do bridge (molde haos-install: cmp + print prova) ────
# 0 quando o PID do job é quem escuta a porta AGORA (sem espera). Com
# RUB_SKIP_HEALTH=1 responde 0 (gate com stubs, sem daemon real).
servico_na_porta() {
  [ "${RUB_SKIP_HEALTH:-0}" = "1" ] && return 0
  local porta jobpid ouvinte; porta="$(porta_api)"; jobpid="$(pid_do_job)"; ouvinte="$(ouvinte_da_porta "$porta")"
  [ -n "$ouvinte" ] && [ "$ouvinte" = "$jobpid" ]
}
# Só declara "no ar" quando o PID que escuta a porta é o PID do job (15 s).
# Um ouvinte que não é o job a esta altura é um programa alheio que entrou
# depois da guarda — recusa nomeando-o. Ninguém na porta em 15 s: o daemon
# não subiu; a causa está no registro dele.
provar_servico_no_ar() {
  [ "${RUB_SKIP_HEALTH:-0}" = "1" ] && return 0
  local porta jobpid="" ouvinte="" i
  porta="$(porta_api)"
  for i in $(seq 1 15); do
    jobpid="$(pid_do_job)"
    ouvinte="$(ouvinte_da_porta "$porta")"
    if [ -n "$ouvinte" ]; then
      [ "$ouvinte" = "$jobpid" ] && return 0
      # PID diferente mas é o serviço instalado: o launchd o relançou entre as
      # duas leituras (KeepAlive). Espera a próxima volta, não acusa ninguém.
      if e_o_servico_instalado "$ouvinte"; then sleep 1; continue; fi
      falha 1 "a porta $porta foi tomada por outro programa ($(nome_do_pid "$ouvinte")) enquanto o serviço subia. Feche esse programa e rode a instalação de novo." \
        "porta $porta: PID $ouvinte ($(comando_curto "$ouvinte")); job: PID ${jobpid:-nenhum}"
    fi
    sleep 1
  done
  falha 1 "o serviço foi instalado, mas não respondeu na porta $porta em 15 segundos. O registro dele está em $LOG_AGENTE — rode a instalação de novo depois de olhar as últimas linhas." \
    "job: PID ${jobpid:-nenhum}; últimas linhas de $LOG_AGENTE:" "$(tail -3 "$LOG_AGENTE" 2>/dev/null | tr '\n' ' ' | cut -c1-400)"
}

instalar_plist_bridge() {
  jp plist checando
  local plist="$LDIR/$LABEL_BRIDGE.plist"
  local tmp; tmp=$(mktemp)
  # UserName só existe no domínio system (LaunchDaemon); num agente do usuário
  # (seam do gate) o launchd o recusa.
  local username_xml=""
  [ "$DOMINIO" = "system" ] && username_xml="    <key>UserName</key><string>$SERVICE_USER</string>"
  {
    cat <<EOF
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
EOF
    [ -n "$username_xml" ] && printf '%s\n' "$username_xml"
    cat <<EOF
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
  } > "$tmp"
  if [ "$DRYRUN" = "1" ]; then diga "serviço do sistema: seria registrado e iniciado"; nota "$plist → $ALVO_LAUNCHD"; rm -f "$tmp"; passo plist plano; return 0; fi

  local mudou=1
  if [ -f "$plist" ] && cmp -s "$tmp" "$plist"; then mudou=0; fi
  if [ "$mudou" = "1" ]; then
    man_set "plist:$plist" pending
    install -m 0644 "$tmp" "$plist" \
      || { rm -f "$tmp"; falha 1 "não consegui gravar o registro do serviço do sistema. Veja o registro e rode a instalação de novo." "install → $plist falhou"; }
    [ "$(id -u)" = "0" ] && chown root:wheel "$plist" || true
    man_set "plist:$plist" created
  fi
  rm -f "$tmp"

  # Arquivo igual NÃO prova job carregado (lição da casa) — provar com print.
  if job_carregado; then
    if [ "$mudou" = "1" ]; then
      launchctl bootout "$ALVO_LAUNCHD" 2>/dev/null || true
      # Corrida real medida (mini, 17:22): bootstrap logo após bootout pode
      # falhar com "5: Input/output error" enquanto o job antigo morre —
      # tentar 3x. E NUNCA declarar sucesso sem o print provar (o set -e
      # fica suprimido dentro desta função; checagem explícita obrigatória).
      local tent=0
      until launchctl bootstrap "$DOMINIO" "$plist" 2>/dev/null; do
        tent=$((tent + 1))
        [ "$tent" -ge 3 ] && break
        sleep 1
      done
      job_carregado || falha 1 "o sistema não aceitou recarregar o serviço. Reinicie o Mac e rode a instalação de novo." "launchctl bootstrap $DOMINIO $plist falhou $tent vez(es)"
      provar_servico_no_ar
      diga "serviço: configuração atualizada, recarregado e no ar"; nota "plist mudou; bootout+bootstrap; PID do job na porta"; jp plist ok; passo plist 0; FEZ=1
    elif [ "$CODIGO_MUDOU" = "1" ]; then
      # Plist igual mas código/venv novos: o job carregado ainda roda o código
      # antigo (medido no mini, 2026-09-01). kickstart -k reinicia no ato.
      launchctl kickstart -k "$ALVO_LAUNCHD" 2>/dev/null || true
      job_carregado || falha 1 "o sistema perdeu o serviço ao reiniciá-lo. Reinicie o Mac e rode a instalação de novo." "kickstart -k $ALVO_LAUNCHD; launchctl print falhou depois"
      provar_servico_no_ar
      diga "serviço: código novo → reiniciado e no ar"; nota "plist igual; kickstart -k; PID do job na porta"; jp plist ok; passo plist 0; FEZ=1
    elif servico_na_porta; then
      diga "serviço: já instalado e no ar"; jp plist ja_estava; passo plist 100; return 100
    else
      # Nada mudou, mas o serviço NÃO está na porta: um daemon que parou de
      # propósito (sai 0 sob launchd; KeepAlive não o relança) ficaria morto
      # com "já instalado" (revisão fria, 2026-09-03). Relança e prova.
      launchctl kickstart -k "$ALVO_LAUNCHD" 2>/dev/null || true
      provar_servico_no_ar
      diga "serviço: estava parado → reiniciado e no ar"; nota "plist e código iguais; job carregado sem ouvinte na porta; kickstart -k"; jp plist ok; passo plist 0; FEZ=1
    fi
  else
    launchctl bootstrap "$DOMINIO" "$plist" 2>/dev/null || launchctl load -w "$plist" 2>/dev/null || true
    job_carregado || falha 1 "o sistema não aceitou iniciar o serviço. Reinicie o Mac e rode a instalação de novo." "launchctl bootstrap $DOMINIO $plist e load -w falharam"
    provar_servico_no_ar
    diga "serviço: instalado, carregado e no ar"; nota "bootstrap $DOMINIO; PID do job na porta"; jp plist ok; passo plist 0; FEZ=1
  fi
}
instalar_plist_bridge || true

diga "concluído."
if [ "$DRYRUN" = "1" ]; then exit 0; fi
[ "$FEZ" = "1" ] && exit 0 || exit 100
