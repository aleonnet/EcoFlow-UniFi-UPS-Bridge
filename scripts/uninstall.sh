#!/bin/bash
# uninstall.sh — desinstala SÓ o que o manifesto prova que o install.sh criou.
#
# Molde da casa (haos-install --uninstall): fatos → plano → UMA confirmação →
# execução prestando contas. Chave ausente no manifesto lê como preexisting —
# a resposta conservadora: nunca remover o que não provamos ter criado.
# Guarda de caminho POR CLASSE; diretórios de código/venv criados por nós são
# as únicas remoções recursivas, após validar caminho literal e não-symlink.
set -Eeuo pipefail

VERSAO="0.1.0"
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
avisar_estado_daemon() {
  local item achou=0
  for item in "$STATE_DIR/udr7_armed.json" "$STATE_DIR/udr7_runtime.json" \
              "$STATE_DIR/udr7_known_hosts" "$STATE_DIR/ui-api.token" \
              "$USER_HOME/.ssh/river-bridge-udr7" "$USER_HOME/.ssh/river-bridge-udr7.pub"; do
    if [ -e "$item" ]; then
      [ "$achou" = "0" ] && diga "AVISO — estado da proteção do UDR7 criado em runtime (não removido por este script):"
      achou=1; diga "  $item"
    fi
  done
  if [ -f "$PREFIX/etc/bridge.env" ] && grep -q '^PROTECT_DRY_RUN=0' "$PREFIX/etc/bridge.env" 2>/dev/null; then
    [ "$achou" = "0" ] && diga "AVISO — estado da proteção do UDR7:"
    achou=1; diga "  $PREFIX/etc/bridge.env está ARMADO (PROTECT_DRY_RUN=0) — desarme pelo app ou edite antes de reinstalar"
  fi
  if [ "$achou" = "1" ]; then
    diga "  remoção manual (runbook docs/UDR7_PROTECAO_SSH_20260901.md): apague os arquivos acima e a chave pública no console"
  fi
}
avisar_estado_daemon || true

[ -f "$MANIFESTO" ] || { echo "sem manifesto em $MANIFESTO — nada a desinstalar (ou nada foi criado por nós)"; exit 100; }

# Caminho seguro por classe: recusa travessia e lugares fora do nosso domínio.
caminho_seguro() {  # $1=classe $2=caminho
  case "$2" in
    *..*) return 1 ;;
  esac
  [ -L "$2" ] && return 1
  case "$1" in
    plist) case "$2" in "$LDIR"/com.river.*.plist) return 0 ;; esac ;;
    file|dir) case "$2" in "$PREFIX"/*) return 0 ;; esac ;;
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

rm -f "$MANIFESTO" "$PREFIX/last-run.log" 2>/dev/null || true
rmdir "$PREFIX/etc" "$PREFIX/src" "$PREFIX" 2>/dev/null \
  && diga "diretório $PREFIX removido (estava vazio)" \
  || diga "sobras de outra origem em $PREFIX — pasta preservada (nunca rm -rf)"

[ "$FALHA" = "0" ] && exit 0 || exit 1
