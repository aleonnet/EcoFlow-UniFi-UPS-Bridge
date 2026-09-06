#!/bin/bash
# build-app.sh — compila o River Bridge (release) e monta o bundle .app.
# Saída: macos/RiverBridge/dist/River Bridge.app (assinatura ad-hoc, uso local;
# a decisão Gatekeeper para deploy no mini está ancorada na ordem 7 do plano).
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$RAIZ/macos/RiverBridge"
DIST="$PKG/dist"
APP="$DIST/River Bridge.app"
VERSAO="0.8.3"

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
# A mão do serviço sobre o próprio registro (0.8.3): só um executável DESTE
# pacote pode chamar `SMAppService.unregister()`; o serviço o chama quando o
# pacote vai para o Lixo (remocao.py). Mora em Contents/MacOS, como o programa.
AJUDANTE="$PKG/.build/release/river-bridge-servico"
[ -x "$AJUDANTE" ] || { echo "[ERRO] binário não encontrado: $AJUDANTE"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RiverBridge"
cp "$AJUDANTE" "$APP/Contents/MacOS/river-bridge-servico"

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

# ── o NUT vai DENTRO do pacote (0.8.0) ────────────────────────────────────────
# Até a 0.7.0 o LEIA-ME mandava rodar `brew install nut` no terminal — o oposto
# da experiência que o dono determinou ("arrastar e usar"). Os dois binários que
# o serviço lança (o leitor `usbhid-ups` e o servidor `upsd`) e as bibliotecas
# que eles carregam vêm do Homebrew DESTA máquina, com a versão fixada: dois
# pacotes com o mesmo número de versão não podem trazer NUTs diferentes.
#
# Medido em 2026-09-05 (`otool -L`): `usbhid-ups` depende só de libusb;
# `upsd` de libssl e libcrypto; as três só do sistema. Depois de copiar, cada
# referência a /opt/homebrew é reescrita para dentro do pacote
# (`install_name_tool`), e a prova é dupla: zero referência a /opt/homebrew
# sobrando, e os dois binários RODANDO de dentro do pacote (`-V`).
#
# Onde o NUT lê configuração e guarda estado deixa de ser /opt/homebrew: o
# lançador (servico.sh, abaixo) aponta as variáveis que o próprio NUT documenta
# (NUT_CONFPATH, NUT_STATEPATH — upsd(8), nutupsdrv(8)) para o nosso diretório.
#
# Licença: o NUT é GPL-2.0-or-later. Vai como programa separado (processos
# próprios, conversa por soquete), com o texto da licença e a fonte ao lado.
NUT_VERSAO="2.8.5"
NUT_ORIGEM="${RUB_NUT_ORIGEM:-/opt/homebrew/opt/nut}"
NUT_DEST="$RES/nut"
echo "│ embutindo o NUT ${NUT_VERSAO}"
[ -x "$NUT_ORIGEM/sbin/upsd" ] || { echo "[ERRO] NUT não encontrado em $NUT_ORIGEM (brew install nut)"; exit 4; }
NUT_AQUI="$("$NUT_ORIGEM/sbin/upsd" -V 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ "$NUT_AQUI" = "$NUT_VERSAO" ] || { echo "[ERRO] o NUT desta máquina é $NUT_AQUI; o pacote fixa $NUT_VERSAO"; exit 3; }
mkdir -p "$NUT_DEST/bin" "$NUT_DEST/sbin" "$NUT_DEST/lib"
cp "$NUT_ORIGEM/bin/usbhid-ups" "$NUT_DEST/bin/"
cp "$NUT_ORIGEM/sbin/upsd" "$NUT_DEST/sbin/"
cp "$NUT_ORIGEM/LICENSE-GPL2" "$NUT_DEST/LICENSE-GPL2"
cat > "$NUT_DEST/NOTICE-NUT.txt" <<TXT
Network UPS Tools (NUT) ${NUT_VERSAO} — https://networkupstools.org/
Licença: GPL-2.0-or-later (LICENSE-GPL2 ao lado).
Código-fonte: https://github.com/networkupstools/nut/releases/tag/v${NUT_VERSAO}
Binários: os do Homebrew (fórmula nut ${NUT_VERSAO}), com as referências às
bibliotecas reescritas para dentro deste pacote. O River Bridge os executa como
programas separados; nada do NUT é ligado ao código do River Bridge.
TXT
# `relocar ARQUIVO BASE`: cada dependência do Homebrew é copiada para lib/ (uma
# vez, seguindo a cadeia — libssl carrega libcrypto) e a referência é reescrita
# para BASE/<nome>: `@executable_path/../lib` para os binários, `@loader_path`
# para uma biblioteca que carrega outra. O `install_name_tool` invalida a
# assinatura; a ad-hoc volta aqui mesmo, porque um Mach-O arm64 sem assinatura
# não executa. A assinatura de distribuição vem no fim, sobre o pacote inteiro.
relocar() {
  local alvo="$1" base="$2" dep nome
  chmod u+w "$alvo"
  for dep in $(otool -L "$alvo" | awk 'NR>1 {print $1}' | grep '^/opt/homebrew' || true); do
    nome="$(basename "$dep")"
    [ "$nome" = "$(basename "$alvo")" ] && { install_name_tool -id "$nome" "$alvo" 2>/dev/null; continue; }
    if [ ! -f "$NUT_DEST/lib/$nome" ]; then
      cp "$dep" "$NUT_DEST/lib/$nome"
      relocar "$NUT_DEST/lib/$nome" "@loader_path"
    fi
    # O aviso "will invalidate the code signature" é o esperado: a assinatura
    # volta na linha seguinte. Silenciado para não parecer erro.
    install_name_tool -change "$dep" "$base/$nome" "$alvo" 2>/dev/null
  done
  codesign --force --sign - "$alvo" >/dev/null 2>&1
}
relocar "$NUT_DEST/bin/usbhid-ups" "@executable_path/../lib"
relocar "$NUT_DEST/sbin/upsd" "@executable_path/../lib"
# Prova 1: nenhuma referência ao Homebrew sobrou em binário nenhum.
SOBRAS_NUT="$(find "$NUT_DEST" -type f \( -perm -u+x -o -name '*.dylib' \) -exec otool -L {} \; 2>/dev/null | grep -c '/opt/homebrew' || true)"
[ "$SOBRAS_NUT" = "0" ] || { echo "[ERRO] $SOBRAS_NUT referência(s) a /opt/homebrew sobraram no NUT embutido"; exit 1; }
# Prova 2: os dois rodam DE DENTRO do pacote (carregam as bibliotecas de lá).
[ "$("$NUT_DEST/sbin/upsd" -V 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" = "$NUT_VERSAO" ] \
  || { echo "[ERRO] o upsd embutido não roda de dentro do pacote"; exit 1; }
"$NUT_DEST/bin/usbhid-ups" -V >/dev/null 2>&1 || { echo "[ERRO] o usbhid-ups embutido não roda de dentro do pacote"; exit 1; }

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
export PYTHONPATH="$AQUI/src:$AQUI/libs"
# ANTES de criar a configuração de exemplo: se houver uma instalação anterior na
# pasta de um usuário desta máquina, o estado dela (chave do console, histórico,
# dispositivos e a configuração ajustada) vem para cá, uma vez. Depois do exemplo
# no lugar, não daria mais: a configuração do dono perderia para ele.
PYTHONDONTWRITEBYTECODE=1 "$AQUI/python/bin/python3" -m river_unifi_bridge.localtoken \
  "$ESTADO" 2>/dev/null || true
[ -f "$CONFIG" ] || { cp "$AQUI/bridge.env.exemplo" "$CONFIG"; chmod 600 "$CONFIG"; }
export RUB_STATE_DIR="$ESTADO"
export RUB_LAUNCHD=1
# O NUT mora dentro do pacote (0.8.0), e a configuração e o estado dele no
# NOSSO diretório: são as mesmas costuras que o serviço, o supervisor e o
# instalador já respeitam. O supervisor traduz as duas em NUT_CONFPATH e
# NUT_STATEPATH para o leitor e o servidor. O caminho do estado é curto de
# propósito: o nome de um soquete Unix cabe em 104 bytes no macOS.
export RUB_NUT_PREFIX="$AQUI/nut"
export RUB_NUT_ETC="$ESTADO/nut"
export RUB_NUT_STATE="$ESTADO/nut-state"
mkdir -p "$RUB_NUT_ETC" "$RUB_NUT_STATE"; chmod 700 "$RUB_NUT_ETC" "$RUB_NUT_STATE"
# Onde o pacote está: é o que o serviço vigia para se retirar quando o dono o
# arrasta para o Lixo (remocao.py).
export RUB_PACOTE="$(cd "$AQUI/../.." && pwd)"
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
    <!-- O serviço escreve o diário na saída PADRÃO (service.py, _log). Sem esta
         chave o diário ia para o nada: no Mac mini, em 2026-09-05, o arquivo
         tinha zero bytes enquanto o leitor do no-break morria na partida. -->
    <key>StandardOutPath</key><string>/Library/Logs/river-unifi-bridge.log</string>
    <key>StandardErrorPath</key><string>/Library/Logs/river-unifi-bridge.log</string>
</dict>
</plist>
PLIST

# ── assinatura: de dentro para fora (0.8.0) ───────────────────────────────────
# Com `RUB_SIGN_IDENTITY` (um "Developer ID Application: …"), cada Mach-O do
# pacote — o interpretador e as extensões do Python, as dependências, o NUT e
# as bibliotecas dele, o executável do App — é assinado com o runtime endurecido
# e carimbo de tempo, e só depois o pacote. É o que a notarização exige de todo
# código aninhado; `--deep` não alcança os Mach-O soltos em Resources (medido:
# 24 arquivos, 2026-09-05) e a Apple o desaconselha. Sem identidade (gate,
# desenvolvimento), a assinatura é ad-hoc e o pacote roda só nesta máquina.
#
# codesign(1): "runtime — On macOS versions >= 10.14.0, opts signed processes
# into a hardened runtime environment which includes runtime code signing
# enforcement, library validation, hard, kill, and debugging restrictions."
# O carimbo de tempo (`--timestamp`) exige rede; ad-hoc não o aceita.
IDENTIDADE="${RUB_SIGN_IDENTITY:--}"
assinar() {
  if [ "$IDENTIDADE" = "-" ]; then
    codesign --force --sign - "$1" >/dev/null 2>&1
  else
    codesign --force --options runtime --timestamp --sign "$IDENTIDADE" "$1" >/dev/null 2>&1
  fi
}
assinar_de_dentro_para_fora() {
  local arquivo assinados=0
  while IFS= read -r -d '' arquivo; do
    file -b "$arquivo" | grep -q 'Mach-O' || continue
    assinar "$arquivo" || { echo "[ERRO] não consegui assinar $arquivo"; return 1; }
    assinados=$((assinados + 1))
  done < <(find "$RES/python" "$RES/libs" "$RES/nut" -type f \
             \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0)
  assinar "$APP/Contents/MacOS/river-bridge-servico" || { echo "[ERRO] não consegui assinar o ajudante do registro"; return 1; }
  assinar "$APP/Contents/MacOS/RiverBridge" || { echo "[ERRO] não consegui assinar o executável"; return 1; }
  assinar "$APP" || { echo "[ERRO] não consegui assinar o pacote"; return 1; }
  echo "│ assinados $assinados Mach-O aninhados + ajudante + executável + pacote ($([ "$IDENTIDADE" = "-" ] && echo ad-hoc || echo "$IDENTIDADE"))"
}
assinar_de_dentro_para_fora || exit 1
codesign --verify --deep --strict "$APP" 2>/dev/null \
  || { echo "[ERRO] a assinatura do pacote não verifica depois de embutir o serviço"; exit 1; }
if [ "$IDENTIDADE" != "-" ]; then
  # Prova: o executável e um Mach-O aninhado saíram com o runtime endurecido e
  # a autoridade certa — é o que a notarização vai conferir, arquivo a arquivo.
  # A saída é capturada ANTES de procurar: `grep -q` fecha o cano ao achar, o
  # `codesign` morre de SIGPIPE e o `pipefail` acusava erro numa assinatura boa
  # (medido em 2026-09-05, na primeira execução com o certificado de verdade).
  for prova in "$APP/Contents/MacOS/RiverBridge" "$APP/Contents/MacOS/river-bridge-servico" "$RES/nut/sbin/upsd" "$RES/python/bin/python3.13"; do
    LAUDO="$(codesign -dv --verbose=2 "$prova" 2>&1 || true)"
    grep -q 'flags=.*runtime' <<< "$LAUDO" \
      || { echo "[ERRO] sem runtime endurecido: $prova"; exit 1; }
    grep -q 'Authority=Developer ID Application' <<< "$LAUDO" \
      || { echo "[ERRO] não é Developer ID: $prova"; exit 1; }
  done
fi

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
