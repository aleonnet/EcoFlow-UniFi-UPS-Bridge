#!/bin/bash
# build-app.sh — compila o River Bridge (release) e monta o bundle .app.
# Saída: macos/RiverBridge/dist/River Bridge.app (assinatura ad-hoc, uso local;
# a decisão Gatekeeper para deploy no mini está ancorada na ordem 7 do plano).
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$RAIZ/macos/RiverBridge"
DIST="$PKG/dist"
APP="$DIST/River Bridge.app"
VERSAO="0.2.0"

echo "│ swift build -c release"
(cd "$PKG" && swift build -c release >/dev/null)
BIN="$PKG/.build/release/RiverBridge"
[ -x "$BIN" ] || { echo "[ERRO] binário não encontrado: $BIN"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RiverBridge"

echo "│ gerando AppIcon.icns"
"$RAIZ/tools/make-app-icon.sh" "$APP/Contents/Resources/AppIcon.icns" >/dev/null

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RiverBridge</string>
    <key>CFBundleIdentifier</key><string>com.river.bridge-ui</string>
    <key>CFBundleName</key><string>River Bridge</string>
    <key>CFBundleDisplayName</key><string>River Bridge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSAO}</string>
    <key>CFBundleVersion</key><string>${VERSAO}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "│ bundle: $APP"
echo "[OK] River Bridge.app montado (v${VERSAO})"
