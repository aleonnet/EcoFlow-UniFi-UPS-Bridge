#!/bin/bash
# build-app.sh — compila o River Bridge (release) e monta o bundle .app.
# Saída: macos/RiverBridge/dist/River Bridge.app (assinatura ad-hoc, uso local;
# a decisão Gatekeeper para deploy no mini está ancorada na ordem 7 do plano).
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$RAIZ/macos/RiverBridge"
DIST="$PKG/dist"
APP="$DIST/River Bridge.app"
VERSAO="0.6.0"

# ── o serviço dentro do pacote (0.7.0) ────────────────────────────────────────
# Por que o interpretador vem junto: medido em 2026-09-05 neste macOS 26.6.2 —
# NÃO existe `/System/Library/Frameworks/Python.framework`; todo `python3` do
# disco vem das ferramentas de desenvolvedor ou do Homebrew, e `/usr/bin/python3`
# é só um atalho do `xcode-select` (o binário se identifica como
# `com.apple.dt.xcode_select.tool-shim-public`). A própria Apple recomenda:
# "If your software depends on scripting languages, it's recommended that you
# bundle the runtime within the app" (macOS Catalina 10.15 Release Notes, 49764202).
#
# Versão e soma FIXADAS: baixar "o mais novo" na hora do empacotamento faria dois
# pacotes com o mesmo número de versão terem interpretadores diferentes.
PY_VERSAO="3.13.15"
PY_CARIMBO="20260901"
PY_ALVO="aarch64-apple-darwin"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_CARIMBO}/cpython-${PY_VERSAO}+${PY_CARIMBO}-${PY_ALVO}-install_only.tar.gz"
PY_SHA256="b9054a9d3d54f4cb5573d44907fddb29874b08909bde73f29f2868cf872223ee"

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

# ── o serviço vai DENTRO do pacote ───────────────────────────────────────────
# Assim, jogar o App no Lixo leva o serviço junto — hoje ele mora em
# /usr/local e sobrevive à Lixeira.
RES="$APP/Contents/Resources"
CACHE="$DIST/.cache"
mkdir -p "$CACHE" "$RES" "$APP/Contents/Library/LaunchDaemons"

TARBALL="$CACHE/cpython-${PY_VERSAO}-${PY_CARIMBO}-${PY_ALVO}.tar.gz"
if [ ! -f "$TARBALL" ]; then
  echo "│ baixando o interpretador (uma vez; fica em cache)"
  curl -fsSL "$PY_URL" -o "$TARBALL.parcial" || { echo "[ERRO] não consegui baixar o Python embutido"; exit 1; }
  mv "$TARBALL.parcial" "$TARBALL"
fi
SOMA="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
[ "$SOMA" = "$PY_SHA256" ] || { echo "[ERRO] soma do Python embutido não confere"; echo "  esperada: $PY_SHA256"; echo "  obtida:   $SOMA"; exit 3; }

echo "│ embutindo Python ${PY_VERSAO}"
tar xzf "$TARBALL" -C "$RES"          # cria $RES/python

echo "│ embutindo dependências e o nosso código"
# `--no-compile`: o pip compila os `.pyc` por padrão, e eles não podem estar aqui.
# Não é economia de espaço — é que o pacote assinado não pode ganhar arquivo
# nenhum depois de assinado, e a prova de arranque lá embaixo conta exatamente
# isso. Com os `.pyc` do pip dentro, ela acusava 645 arquivos "deixados pelo
# serviço" que na verdade eram do próprio empacotamento (medido em 2026-09-05).
"$RES/python/bin/python3" -m pip -q install --no-compile --target "$RES/libs" "aiohttp>=3.12" \
  || { echo "[ERRO] não consegui instalar as dependências no pacote"; exit 1; }
cp -R "$RAIZ/src/river_unifi_bridge" "$RES/src-river_unifi_bridge"
mkdir -p "$RES/src" && rm -rf "$RES/src/river_unifi_bridge" 2>/dev/null || true
mv "$RES/src-river_unifi_bridge" "$RES/src/river_unifi_bridge"
# E o que veio junto da árvore de trabalho (o `__pycache__` de quem roda a
# suíte) também sai: ele entraria assinado e voltaria a divergir na primeira
# atualização do código.
find "$RES/src" "$RES/libs" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
cp "$RAIZ/config/river-unifi-bridge.env.example" "$RES/bridge.env.exemplo"

# O que o launchd executa. Script porque o `BundleProgram` aponta para UM
# arquivo, e o serviço precisa de PYTHONPATH e do arquivo de configuração.
cat > "$RES/servico.sh" <<'SH'
#!/bin/sh
# Lançador do serviço, dentro do pacote. `dirname $0` resolve para
# .../River Bridge.app/Contents/Resources, onde quer que o App esteja.
set -eu
AQUI="$(cd "$(dirname "$0")" && pwd)"
ESTADO="${RUB_STATE_DIR:-/Library/Application Support/river-unifi-bridge}"
mkdir -p "$ESTADO"; chmod 700 "$ESTADO"
CONFIG="$ESTADO/bridge.env"
[ -f "$CONFIG" ] || { cp "$AQUI/bridge.env.exemplo" "$CONFIG"; chmod 600 "$CONFIG"; }
export PYTHONPATH="$AQUI/src:$AQUI/libs"
export RUB_STATE_DIR="$ESTADO"
export RUB_LAUNCHD=1
# NADA é escrito dentro do pacote em tempo de execução: o Python grava `.pyc`
# ao lado do código, e isso QUEBRA a assinatura do pacote (medido em
# 2026-09-05: 671 arquivos criados na primeira execução, e o
# `codesign --verify` passou a acusar "a sealed resource is missing or
# invalid"). Um pacote com assinatura quebrada é um pacote que o sistema pode
# recusar a carregar.
export PYTHONDONTWRITEBYTECODE=1
# "$@" no fim: sem isso o lançador ignorava os argumentos e `--version` subia o
# serviço inteiro em vez de responder e sair — o que travou o próprio
# empacotamento (medido em 2026-09-05). O launchd chama sem argumento nenhum, e
# aí o comportamento é o mesmo de antes.
exec "$AQUI/python/bin/python3" -m river_unifi_bridge.service --env "$CONFIG" "$@"
SH
chmod +x "$RES/servico.sh"

cat > "$APP/Contents/Library/LaunchDaemons/com.river.unifi-bridge.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.river.unifi-bridge</string>
    <!-- BundleProgram: caminho RELATIVO ao pacote. É o que permite ao serviço
         morar dentro do App e ir junto para o Lixo. -->
    <key>BundleProgram</key><string>Contents/Resources/servico.sh</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ExitTimeOut</key><integer>30</integer>
    <key>AssociatedBundleIdentifiers</key><array><string>com.river.bridge-ui</string></array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string>
        <!-- cinto e suspensório: o lançador também define, e nada dentro do
             pacote assinado pode ser escrito em tempo de execução -->
        <key>PYTHONDONTWRITEBYTECODE</key><string>1</string>
    </dict>
    <key>StandardErrorPath</key><string>/Library/Logs/river-unifi-bridge.log</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
codesign --verify --deep --strict "$APP" 2>/dev/null \
  || { echo "[ERRO] a assinatura do pacote não verifica depois de embutir o serviço"; exit 1; }

# Arranque de prova: o serviço tem de rodar do pacote E não deixar rastro nele.
# Sem isto, o defeito só apareceria na máquina de quem instalou.
#
# A marca de tempo é tirada AGORA, imediatamente antes de rodar — não do
# Info.plist. Comparando com o Info.plist, tudo o que o empacotamento escreveu
# depois dele (as dependências, o nosso código) contava como "deixado pelo
# serviço", e a prova acusava um defeito que não existia enquanto poderia deixar
# passar o que existe.
MARCA="$(mktemp)"
PROVA="$(mktemp -d)"
RUB_STATE_DIR="$PROVA" "$RES/servico.sh" --version >/dev/null 2>&1 || true
RESTOS="$(find "$APP" -newer "$MARCA" | wc -l | tr -d ' ')"
rm -rf "$PROVA" "$MARCA"
[ "$RESTOS" = "0" ] || { echo "[ERRO] rodar o serviço deixou $RESTOS arquivos novos dentro do pacote (quebra a assinatura)"; exit 1; }
codesign --verify --deep --strict "$APP" 2>/dev/null \
  || { echo "[ERRO] a assinatura não verifica DEPOIS de o serviço rodar"; exit 1; }
echo "│ bundle: $APP ($(du -sh "$APP" | cut -f1))"
echo "[OK] River Bridge.app montado (v${VERSAO}) com o serviço dentro"
