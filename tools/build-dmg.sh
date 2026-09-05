#!/bin/bash
# build-dmg.sh — o River Bridge num disco de instalação, no molde da Apple.
#
# O que o dono vê: abre o .dmg, aparece uma janela com o programa de um lado e um
# atalho para a pasta Aplicativos do outro. Arrasta, e está instalado.
#
# Por que `hdiutil` e não uma ferramenta de terceiros: ele vem no macOS, o
# projeto não ganha dependência, e o formato é o mesmo que a Apple usa.
#
# Uso:  tools/build-dmg.sh            (monta o pacote antes, se não existir)
#       tools/build-dmg.sh --limpo    (monta o pacote do zero de qualquer jeito)
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$RAIZ/macos/RiverBridge"
DIST="$PKG/dist"
APP="$DIST/River Bridge.app"
VERSAO="$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' "$RAIZ/src/river_unifi_bridge/__init__.py")"
DMG="$DIST/River Bridge $VERSAO.dmg"
# O nome do volume é o que aparece na barra de título da janela e no Finder.
VOLUME="River Bridge"

ok()   { printf '[OK]   %s\n' "$1"; }
erro() { printf '[ERRO] %s\n' "$1" >&2; exit 1; }

[ "${1:-}" = "--limpo" ] && rm -rf "$APP"
if [ ! -d "$APP" ]; then
  "$RAIZ/tools/build-app.sh" || erro "não consegui montar o pacote"
fi
[ -d "$APP" ] || erro "não achei $APP"

# Um pacote que não verifica não entra em disco de instalação: o macOS o
# recusaria na máquina do dono, e o erro apareceria lá, não aqui.
codesign --verify --deep --strict "$APP" 2>/dev/null \
  || erro "a assinatura do pacote não verifica — não vou empacotar isso"

PALCO="$(mktemp -d)"
MONTAGEM=""
limpar() {
  [ -n "$MONTAGEM" ] && hdiutil detach -quiet "$MONTAGEM" 2>/dev/null || true
  rm -rf "$PALCO"
}
trap limpar EXIT

cp -R "$APP" "$PALCO/"
# O atalho para /Applications é o que faz o arrastar funcionar. Sem ele a janela
# teria só o programa, e o dono teria de achar a pasta sozinho.
ln -s /Applications "$PALCO/Aplicativos"

rm -f "$DMG"
# UDZO = comprimido e somente leitura, que é o que se distribui.
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$PALCO" \
  -ov -format UDZO "$DMG" || erro "hdiutil não conseguiu criar o disco"

# Prova: o disco monta, tem o programa e o atalho dentro, e o programa continua
# verificando a assinatura DEPOIS de passar pela compressão. Sem esta parte, um
# disco quebrado só apareceria na máquina do dono.
MONTAGEM="$(mktemp -d)/rb"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MONTAGEM" "$DMG" \
  || { MONTAGEM=""; erro "o disco não montou para a conferência"; }
falhou=""
[ -d "$MONTAGEM/River Bridge.app" ] || falhou="o programa não está no disco"
[ -L "$MONTAGEM/Aplicativos" ] || falhou="${falhou:-falta o atalho para Aplicativos}"
codesign --verify --deep --strict "$MONTAGEM/River Bridge.app" 2>/dev/null \
  || falhou="${falhou:-a assinatura não verifica dentro do disco}"
hdiutil detach -quiet "$MONTAGEM" && MONTAGEM=""
[ -z "$falhou" ] || erro "$falhou"

ok "River Bridge $VERSAO.dmg pronto ($(du -sh "$DMG" | cut -f1))"
echo "│ disco: $DMG"
echo "│ abrir: open \"$DMG\" — depois arraste o programa para Aplicativos"
