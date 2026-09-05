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
# Um LEIA-ME ao lado do programa, na janela do disco: as três coisas que o dono
# não tem como adivinhar. Desde a 0.8.0 nada aqui pede terminal: o NUT vai
# dentro do pacote, o disco é assinado e notarizado, e o Lixo remove tudo.
cat > "$PALCO/LEIA-ME.txt" <<'TXT'
River Bridge — o que saber antes de arrastar
============================================

1. ARRASTE o River Bridge para a pasta Aplicativos, ao lado.

2. DEPOIS DE ABRIR: Ajustes > Servico > Instalar o servico, e aprove em
       Ajustes do Sistema > Geral > Itens de Inicio de Sessao
   O macOS pede isso para todo servico que sobe com o computador. Tudo o que o
   River Bridge precisa ja esta dentro dele — nada mais para instalar.

3. PARA REMOVER, arraste o programa para o Lixo. O servico percebe, para de
   vigiar, apaga a chave do console, as senhas e o historico, e se desregistra
   sozinho. (Em Ajustes > Servico, "Remover completamente" faz o mesmo sem
   jogar o programa fora.)
TXT
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
[ -f "$MONTAGEM/LEIA-ME.txt" ] || falhou="${falhou:-falta o LEIA-ME}"
codesign --verify --deep --strict "$MONTAGEM/River Bridge.app" 2>/dev/null \
  || falhou="${falhou:-a assinatura não verifica dentro do disco}"
hdiutil detach -quiet "$MONTAGEM" && MONTAGEM=""
[ -z "$falhou" ] || erro "$falhou"

ok "River Bridge $VERSAO.dmg pronto ($(du -sh "$DMG" | cut -f1))"
echo "│ disco: $DMG"
echo "│ abrir: open \"$DMG\" — depois arraste o programa para Aplicativos"
