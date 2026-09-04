#!/bin/bash
# captura-por-janela.sh — fotografa a janela do app SEM ativá-lo.
#
# Por que existe: `tools/captura-focada.sh` chama `activate`, e isso rouba o
# teclado do dono. Aqui a cópia de ensaio roda com OUTRO identificador de pacote
# (montada por --ensaio), aparece na tela e é fotografada por id de janela.
#
# Uso: captura-por-janela.sh SAIDA.png [args do app...]
#   --ensaio: monta/atualiza a cópia de ensaio em /private/tmp a partir do dist.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
ENSAIO="/private/tmp/River Bridge Ensaio.app"
DONO="River Bridge Ensaio"

monta_ensaio() {
    [ -d "$RAIZ/macos/RiverBridge/dist/River Bridge.app" ] || {
        echo "[ERRO] dist ausente: rode tools/build-app.sh" >&2; exit 1; }
    rm -rf "$ENSAIO"
    cp -R "$RAIZ/macos/RiverBridge/dist/River Bridge.app" "$ENSAIO"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.river.bridge-ui-ensaio" \
        -c "Set :CFBundleName $DONO" -c "Set :CFBundleDisplayName $DONO" \
        "$ENSAIO/Contents/Info.plist" >/dev/null
    codesign --force --sign - "$ENSAIO" >/dev/null 2>&1 || true
    echo "[OK] cópia de ensaio: $ENSAIO"
}

[ "${1:-}" = "--ensaio" ] && { monta_ensaio; shift; }
[ $# -ge 1 ] || { echo "uso: captura-por-janela.sh SAIDA.png [args do app...]" >&2; exit 2; }
SAIDA="$1"; shift
[ -d "$ENSAIO" ] || monta_ensaio

pkill -f "River Bridge Ensaio.app/Contents/MacOS/RiverBridge" 2>/dev/null || true
sleep 1
"$ENSAIO/Contents/MacOS/RiverBridge" --abrir-painel "$@" \
    -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
APP_PID=$!
JANELA=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 1
    # A MAIOR janela é a mãe; com uma folha aberta, a folha é janela própria.
    # ALVO=maior (padrão) pega a janela-mãe; ALVO=menor pega a FOLHA, que é uma
    # janela própria — é assim que se fotografa uma folha sem ativar o app.
    if [ "${ALVO:-maior}" = "menor" ]; then
        JANELA="$(swift "$RAIZ/tools/janelas.swift" "$DONO" \
                  | sort -t'	' -k2,2n | head -1 | cut -f1)"
    else
        JANELA="$(swift "$RAIZ/tools/janelas.swift" "$DONO" \
                  | sort -t'	' -k2,2nr | head -1 | cut -f1)"
    fi
    [ -n "$JANELA" ] && break
done
[ -n "$JANELA" ] || { kill "$APP_PID" 2>/dev/null || true; echo "[ERRO] janela não apareceu" >&2; exit 1; }
sleep 2                     # deixa a tela assentar (dados dos seams, animação)
screencapture -x -o -l"$JANELA" "$SAIDA"
kill "$APP_PID" 2>/dev/null || true
echo "[OK] $SAIDA (janela $JANELA)"
