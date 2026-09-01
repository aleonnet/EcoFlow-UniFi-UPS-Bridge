#!/bin/bash
# make-app-icon.sh — gera o AppIcon.icns do River Bridge por código (estilo
# novo da Apple: squircle com gradiente profundo, escudo-raio translúcido com
# highlight especular — o mesmo motivo do ícone da barra de menu). O desenho mora
# em tools/app-icon-render.swift, compartilhado com tools/gera-logo.py.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$RAIZ/macos/RiverBridge/dist/AppIcon.icns}"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

swift "$RAIZ/tools/app-icon-render.swift" "$WORK/master.png"

# iconset em todas as resoluções exigidas pelo iconutil.
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    px="${spec%% *}"; name="${spec##* }"
    sips -z "$px" "$px" "$WORK/master.png" --out "$ICONSET/$name.png" >/dev/null
done
mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$WORK"
echo "[OK] ícone gerado: $OUT"
