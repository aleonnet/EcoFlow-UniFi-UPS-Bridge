#!/bin/bash
# release.sh — produz e publica a release vX.Y.Z do River Bridge, na máquina de
# desenvolvimento, sem CI: app ad-hoc zipado + tarball do código NA TAG + SHA256SUMS.
#
#   tools/release.sh --check [vX.Y.Z]   só valida: as 6 versões e o CHANGELOG batem (sem rede)
#   tools/release.sh --dry-run vX.Y.Z   constrói tudo em dist/vX.Y.Z/, não cria tag, não publica
#   tools/release.sh vX.Y.Z             tudo: gate, build, tag, assets, push da tag, gh release
#   opções: --no-gate (pula tools/gate.sh — só quando o gate acabou de rodar verde)
#
# Assets com nome SEM versão, para o instalador baixar por
#   https://github.com/<slug>/releases/latest/download/<asset>
# só com curl (a tag vem do redirect). O SHA256SUMS prova integridade e que os
# dois assets são da MESMA release; não protege contra um GitHub comprometido
# (mesma origem TLS) — dizer isso nos docs, não fingir mais.
#
# Reversão de uma release publicada por engano:
#   gh release delete vX.Y.Z --yes && git push --delete origin vX.Y.Z && git tag -d vX.Y.Z
#
# Exit: 0 ok · 2 uso · 3 validação · 4 dependência · 1 falha
set -Eeuo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SLUG="aleonnet/EcoFlow-UniFi-UPS-Bridge"
APP_SRC="$RAIZ/macos/RiverBridge/dist/River Bridge.app"
ASSET_APP="River-Bridge.app.zip"
ASSET_SRC="river-unifi-bridge-src.tar.gz"
ASSET_SUMS="SHA256SUMS"

MODO="full"; TAG=""; NO_GATE=0
for arg in "$@"; do
  case "$arg" in
    --check) MODO="check" ;;
    --dry-run) MODO="dry" ;;
    --no-gate) NO_GATE=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    v[0-9]*) TAG="$arg" ;;
    *) echo "argumento desconhecido: $arg (uso)"; exit 2 ;;
  esac
done

diga() { printf '│ %s\n' "$1"; }
falha() { echo "[ERRO] $1" >&2; exit "${2:-1}"; }

# ── --check: uma tag amarra as 6 declarações de versão + a seção do CHANGELOG ──
# Sem argumento, a versão de referência é a do pyproject.toml.
versao_pyproject() { sed -n 's/^version = "\([0-9][0-9.]*\)"$/\1/p' "$RAIZ/pyproject.toml" | head -1; }
checar_versoes() { # $1 = X.Y.Z
  local v="$1" ruim=0 f re
  # arquivo|regex (a linha inteira, com a versão no lugar de X)
  local lista="pyproject.toml|^version = \"X\"\$
src/river_unifi_bridge/__init__.py|^__version__ = \"X\"\$
scripts/install.sh|^VERSAO=\"X\"\$
scripts/uninstall.sh|^VERSAO=\"X\"\$
tools/build-app.sh|^VERSAO=\"X\"\$
river-bridge-install.sh|^RBI_VERSION=\"X\"\$
CHANGELOG.md|^## \\[X\\]"
  while IFS='|' read -r f re; do
    [ -n "$f" ] || continue
    re="${re//X/$v}"
    if grep -Eq "$re" "$RAIZ/$f"; then diga "versão $v em $f"
    else echo "[ERRO] $f não declara a versão $v (esperado: $re)"; ruim=1; fi
  done <<< "$lista"
  [ "$ruim" = "0" ] || falha "as declarações de versão divergem — corrija antes de taguear" 3
}

if [ "$MODO" = "check" ]; then
  V="${TAG#v}"; [ -n "$V" ] || V="$(versao_pyproject)"
  [ -n "$V" ] || falha "não achei a versão no pyproject.toml" 3
  checar_versoes "$V"
  echo "[OK] release --check: v$V consistente nos 6 arquivos e no CHANGELOG"
  exit 0
fi

# ── modos dry-run e full ──────────────────────────────────────────────────────
[ -n "$TAG" ] || { echo "informe a tag: tools/release.sh [--dry-run] vX.Y.Z (uso)"; exit 2; }
V="${TAG#v}"
case "$V" in *[!0-9.]*|"") falha "tag inválida: $TAG (esperado vX.Y.Z)" 3 ;; esac
for f in git shasum ditto plutil codesign tar; do command -v "$f" >/dev/null 2>&1 || falha "$f ausente (dependência)" 4; done
[ "$MODO" = "full" ] && { command -v gh >/dev/null 2>&1 || falha "gh ausente — brew install gh (dependência)" 4; }

checar_versoes "$V"
cd "$RAIZ"
[ -z "$(git status --porcelain)" ] || falha "árvore suja — commite ou guarde antes de lançar" 3
if [ "$MODO" = "full" ]; then
  git fetch -q origin
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || falha "HEAD != origin/main — o one-liner é servido de main; publique main antes da tag" 3
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && falha "a tag $TAG já existe localmente" 3
  [ -z "$(git ls-remote --tags origin "$TAG")" ] || falha "a tag $TAG já existe no remoto" 3
  gh auth status >/dev/null 2>&1 || falha "gh não autenticado (gh auth login)" 4
  gh release view "$TAG" >/dev/null 2>&1 && falha "a release $TAG já existe no GitHub" 3
fi

if [ "$NO_GATE" = "0" ]; then
  diga "tools/gate.sh (pule só com --no-gate, logo após um gate verde)"
  "$RAIZ/tools/gate.sh" >"$RAIZ/dist/gate-$TAG.log" 2>&1 || falha "gate vermelho — veja dist/gate-$TAG.log" 1
  tail -1 "$RAIZ/dist/gate-$TAG.log"
fi

DIST="$RAIZ/dist/$TAG"
rm -rf "$DIST"; mkdir -p "$DIST"

diga "tools/build-app.sh"
"$RAIZ/tools/build-app.sh" >"$DIST/build-app.log" 2>&1 || falha "build do app falhou — veja $DIST/build-app.log" 1
[ -x "$APP_SRC/Contents/MacOS/RiverBridge" ] || falha "app não montado em $APP_SRC" 1
bundle_v="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_SRC/Contents/Info.plist")"
[ "$bundle_v" = "$V" ] || falha "Info.plist diz $bundle_v, esperado $V" 3
codesign --verify --deep --strict "$APP_SRC" || falha "assinatura (ad-hoc) do app não verifica" 1
file "$APP_SRC/Contents/MacOS/RiverBridge" | grep -q arm64 || falha "binário não é arm64" 3
if xattr -lr "$APP_SRC" 2>/dev/null | grep -q com.apple.quarantine; then
  echo "[AVISO] o app de origem carrega com.apple.quarantine — o zip herdaria; limpe antes (xattr -dr)"
fi

if [ "$MODO" = "full" ]; then
  git tag -a "$TAG" -m "$TAG"
  ARCH_REF="$TAG"
else
  ARCH_REF="HEAD"
fi
diga "git archive $ARCH_REF → $ASSET_SRC (prefixo river-unifi-bridge-$TAG/, casa com --strip-components=1)"
git archive --format=tar.gz --prefix="river-unifi-bridge-$TAG/" -o "$DIST/$ASSET_SRC" "$ARCH_REF"
diga "ditto → $ASSET_APP"
(cd "$(dirname "$APP_SRC")" && ditto -c -k --keepParent "$(basename "$APP_SRC")" "$DIST/$ASSET_APP")
(cd "$DIST" && shasum -a 256 "$ASSET_APP" "$ASSET_SRC" > "$ASSET_SUMS")

# Auto-prova: o zip devolve o mesmo executável; o tarball traz o instalador.
PROVA="$(mktemp -d)"
ditto -xk "$DIST/$ASSET_APP" "$PROVA"
cmp -s "$PROVA/River Bridge.app/Contents/MacOS/RiverBridge" "$APP_SRC/Contents/MacOS/RiverBridge" \
  || falha "o executável extraído do zip difere do original" 1
tar -tzf "$DIST/$ASSET_SRC" | grep -q "^river-unifi-bridge-$TAG/scripts/install.sh$" \
  || falha "o tarball não traz scripts/install.sh" 1
rm -rf "$PROVA"
(cd "$DIST" && shasum -a 256 -c "$ASSET_SUMS" >/dev/null) || falha "SHA256SUMS não confere" 1

# Notas: a seção ## [X.Y.Z] do CHANGELOG até o próximo cabeçalho de versão.
awk -v v="$V" '
  $0 ~ "^## \\[" v "\\]" { on=1; next }
  on && /^## \[/ { exit }
  on { print }
' "$RAIZ/CHANGELOG.md" > "$DIST/notes.md"
[ -s "$DIST/notes.md" ] || falha "CHANGELOG sem conteúdo na seção ## [$V]" 3

diga "assets em $DIST:"; (cd "$DIST" && cat "$ASSET_SUMS")
if [ "$MODO" = "dry" ]; then
  echo "[OK] dry-run: assets prontos em $DIST — nenhuma tag criada, nada publicado"
  exit 0
fi

diga "git push origin $TAG"
git push origin "$TAG"
diga "gh release create $TAG"
gh release create "$TAG" --verify-tag --title "$TAG" --notes-file "$DIST/notes.md" \
  "$DIST/$ASSET_APP" "$DIST/$ASSET_SRC" "$DIST/$ASSET_SUMS"

# Pós-prova pela mesma URL que o instalador usa (propagação pode levar segundos).
URL="https://github.com/$REPO_SLUG/releases/latest/download/$ASSET_SUMS"
for i in 1 2 3; do
  if curl -fsSL -o "$DIST/$ASSET_SUMS.remoto" "$URL" 2>/dev/null \
     && diff -q "$DIST/$ASSET_SUMS" "$DIST/$ASSET_SUMS.remoto" >/dev/null; then
    echo "[OK] release $TAG publicada e conferida em $URL"; exit 0
  fi
  sleep 5
done
falha "a release foi criada, mas $URL ainda não devolve o SHA256SUMS igual — confira à mão" 1
