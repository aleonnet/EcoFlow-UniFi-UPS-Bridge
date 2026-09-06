#!/bin/bash
# uninstall.sh — desinstala SÓ o que o manifesto prova que o install.sh criou.
#
# Molde da casa (haos-install --uninstall): fatos → plano → UMA confirmação →
# execução prestando contas. Chave ausente no manifesto lê como preexisting —
# a resposta conservadora: nunca remover o que não provamos ter criado.
# Guarda de caminho POR CLASSE; diretórios de código/venv criados por nós são
# as únicas remoções recursivas, após validar caminho literal e não-symlink.
set -Eeuo pipefail

VERSAO="0.9.0"
PREFIX="${RUB_PREFIX:-/usr/local/river-unifi-bridge}"
LDIR="${RUB_LAUNCHD_DIR:-/Library/LaunchDaemons}"
MANIFESTO="$PREFIX/manifest.tsv"
CONFIRM=0
for arg in "$@"; do
  case "$arg" in
    --confirm) CONFIRM=1 ;;
    --version) echo "$VERSAO"; exit 0 ;;
    -h|--help) echo "uso: uninstall.sh [--confirm]"; exit 0 ;;
    *) echo "argumento desconhecido: $arg"; exit 2 ;;
  esac
done

diga() { printf '│ %s\n' "$1"; }

# ── Fase 3'-EXP — estado do daemon (spec §2.4 adendo): arquivos criados em runtime
# pelo serviço (NÃO pelo instalador) ficam fora do manifesto e por isso NÃO são
# removidos aqui — só listados. Registrar no manifesto é dívida (docs/BACKLOG_20260901.md).
SERVICE_USER="${RUB_SERVICE_USER:-${SUDO_USER:-$(id -un)}}"
USER_HOME="$(eval echo "~$SERVICE_USER")"
STATE_DIR="${RUB_STATE_DIR:-$USER_HOME/Library/Application Support/river-unifi-bridge}"
# Desde a 0.3.0 os dispositivos são INSTÂNCIAS, cada uma com os seus arquivos
# (<id>_known_hosts, <id>_armed.json, <id>_runtime.json) e a loja devices.json:
# a lista é por PADRÃO de nome, não por literal. "Está armado" = existe um
# <id>_armed.json (o .env é só espelho da instância migrada e não decide mais).
avisar_estado_daemon() {
  local item achou=0
  for item in "$STATE_DIR"/*_armed.json "$STATE_DIR"/*_runtime.json "$STATE_DIR"/*_known_hosts \
              "$STATE_DIR"/*_key "$STATE_DIR"/*_key.pub "$STATE_DIR"/*_acesso.json \
              "$STATE_DIR/devices.json" "$STATE_DIR/ui-api.token" "$STATE_DIR/history.sqlite" \
              "$USER_HOME"/.ssh/river-bridge-*; do
    [ -e "$item" ] || continue
    [ "$achou" = "0" ] && diga "AVISO — estado dos dispositivos protegidos criado em runtime (não removido por este script):"
    achou=1; diga "  $item"
  done
  for item in "$STATE_DIR"/*_armed.json; do
    [ -e "$item" ] || continue
    diga "  $(basename "$item" _armed.json) está ARMADO — desarme pelo app (ligar modo ensaio) antes de reinstalar"
  done
  if [ "$achou" = "1" ]; then
    diga "  remoção manual (runbook docs/guides/2026-09-03-1710-runbook-protecao-udr7-por-instancia.md): apague os arquivos acima e a chave pública em cada máquina"
  fi
}
avisar_estado_daemon || true

[ -f "$MANIFESTO" ] || { echo "sem manifesto em $MANIFESTO — nada a desinstalar (ou nada foi criado por nós)"; exit 100; }

# Caminho seguro por classe: recusa travessia e lugares fora do nosso domínio.
NUT_ETC="${RUB_NUT_ETC:-/opt/homebrew/etc/nut}"

caminho_seguro() {  # $1=classe $2=caminho
  case "$2" in
    *..*) return 1 ;;
  esac
  [ -L "$2" ] && return 1
  case "$1" in
    plist) case "$2" in "$LDIR"/com.river.*.plist) return 0 ;; esac ;;
    # A configuração do NUT que o instalador escreve (só quando ela não existia)
    # mora fora do prefixo, no diretório do Homebrew. Sem esta linha o desinstalador
    # recusaria remover o que ele próprio criou, e sairia com falha.
    # A ficha da senha da conta que manda no aparelho mora no diretório de
    # estado (é lá que o serviço a lê). Sem esta linha, toda desinstalação
    # feita depois de uma instalação 0.5.0 saía com falha e deixava a senha
    # no disco (revisão fria da 0.5.0, 2.ª rodada).
    file|dir) case "$2" in "$PREFIX"/*) return 0 ;; "$NUT_ETC"/*) return 0 ;;
                 "$STATE_DIR"/nut-admin.token) return 0 ;;
                 "$STATE_DIR"/nut-homeassistant.token) return 0 ;; esac ;;
  esac
  return 1
}

diga "plano de remoção (só entradas 'created' do manifesto):"
PLANO=""
while IFS=$'\t' read -r chave estado; do
  [ "$estado" = "created" ] || continue
  diga "  $chave"
  PLANO="$PLANO$chave\n"
done < "$MANIFESTO"
[ -n "$PLANO" ] || { echo "manifesto sem entradas 'created' — nada nosso para remover"; exit 100; }

if [ "$CONFIRM" != "1" ]; then
  printf 'Remover os itens acima? [s/N] '
  read -r resp
  case "$resp" in s|S) ;; *) echo "cancelado"; exit 130 ;; esac
fi

FALHA=0
while IFS=$'\t' read -r chave estado; do
  [ "$estado" = "created" ] || continue
  classe="${chave%%:*}"; alvo="${chave#*:}"
  case "$classe" in
    plist)
      caminho_seguro plist "$alvo" || { echo "RECUSADO (guarda): $alvo"; FALHA=1; continue; }
      rotulo="$(basename "$alvo" .plist)"
      launchctl bootout "system/$rotulo" 2>/dev/null || true
      rm -f "$alvo" && diga "removido plist + job: $alvo" ;;
    file)
      caminho_seguro file "$alvo" || { echo "RECUSADO (guarda): $alvo"; FALHA=1; continue; }
      rm -f "$alvo" && diga "removido: $alvo" ;;
    dir)
      caminho_seguro dir "$alvo" || { echo "RECUSADO (guarda): $alvo"; FALHA=1; continue; }
      rm -r "$alvo" && diga "removido diretório criado por nós: $alvo" ;;
    brew)
      diga "brew $alvo: instalado por nós, mas NÃO removido automaticamente (outros usos possíveis) — 'brew uninstall $alvo' é decisão do dono" ;;
    svc)
      diga "$chave: estava pendente/registrado, nada físico a remover" ;;
    *)
      echo "classe desconhecida no manifesto: $chave (ignorada por segurança)" ;;
  esac
done < "$MANIFESTO"

# O trecho que o SERVIÇO escreve no ups.conf do NUT (os aparelhos que ele
# publicava) não está no manifesto: quem o escreveu foi o daemon, em tempo de
# execução, não o instalador. Deixá-lo para trás faria o servidor do no-break
# procurar para sempre soquetes de um driver que não existe mais. Só o miolo
# entre as marcas sai; o resto do arquivo é do dono, e continua sendo.
tirar_trecho_do_ups_conf() {
  local arquivo="$NUT_ETC/ups.conf"
  [ -f "$arquivo" ] || return 0
  grep -q '^# >>> River Bridge' "$arquivo" 2>/dev/null || return 0
  local novo; novo="$(mktemp)"
  awk '/^# >>> River Bridge/{pula=1} !pula{print} /^# <<< River Bridge/{pula=0}' \
    "$arquivo" > "$novo" || { rm -f "$novo"; return 1; }
  # Sem a marca de fim, o awk teria comido o arquivo daí para baixo: recusa.
  if grep -q '^# <<< River Bridge' "$arquivo" 2>/dev/null; then
    cat "$novo" > "$arquivo" && diga "trecho do River Bridge removido de $arquivo"
  else
    diga "AVISO — $arquivo tem a marca de início do River Bridge sem a de fim; não mexi"
  fi
  rm -f "$novo"
}
tirar_trecho_do_ups_conf || true

rm -f "$MANIFESTO" "$PREFIX/last-run.log" 2>/dev/null || true
# O próprio uninstall.sh mora em $PREFIX/scripts (classe file: do manifesto):
# o rm -f acima não afeta o processo em curso, que já tem o arquivo aberto.
rmdir "$PREFIX/etc" "$PREFIX/src" "$PREFIX/scripts" "$PREFIX" 2>/dev/null \
  && diga "diretório $PREFIX removido (estava vazio)" \
  || diga "sobras de outra origem em $PREFIX — pasta preservada (nunca rm -rf)"

[ "$FALHA" = "0" ] && exit 0 || exit 1
