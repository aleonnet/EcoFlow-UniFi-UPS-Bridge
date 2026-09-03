#!/bin/bash
# Captura de validação COM FOCO GARANTIDO (cerca de método, 2026-08-31):
# sem foco o Liquid Glass não renderiza o backdrop pleno e a validação mente.
# Uso: captura-focada.sh SAIDA.png [args do app...]
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SAIDA="$1"; shift
osascript -e 'tell application "River Bridge" to quit' 2>/dev/null || true
# Com uma folha aberta o quit por AppleScript é ignorado: encerra pelo processo.
pkill -x RiverBridge 2>/dev/null || true
sleep 1.5
"$RAIZ/macos/RiverBridge/dist/River Bridge.app/Contents/MacOS/RiverBridge" \
  --abrir-painel "$@" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
sleep 4
osascript -e 'tell application "River Bridge" to activate'
sleep 1.5
FRENTE=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true')
if [ "$FRENTE" != "RiverBridge" ] && [ "$FRENTE" != "River Bridge" ]; then
  echo "FALHA: janela sem foco (frontmost=$FRENTE) — captura inválida" >&2
  exit 1
fi
# A janela-MÃE é a de maior área (com uma folha aberta, a folha é uma janela
# própria, menor). Captura-se a REGIÃO dela, para a folha sair por cima —
# `-l` fotografaria uma janela só, sem a folha (2026-09-03).
REGIAO=$(swift -e 'import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: [String: Double]? = nil
for w in list {
  if let owner = w["kCGWindowOwnerName"] as? String, owner == "River Bridge",
     let b = w["kCGWindowBounds"] as? [String: Double], b["Height"]! > 300 {
    if best == nil || b["Width"]! * b["Height"]! > best!["Width"]! * best!["Height"]! { best = b }
  }
}
if let b = best { print("\(Int(b["X"]!)),\(Int(b["Y"]!)),\(Int(b["Width"]!)),\(Int(b["Height"]!))") }' 2>/dev/null)
[ -n "$REGIAO" ] || { echo "FALHA: janela não encontrada" >&2; exit 1; }
screencapture -x -R "$REGIAO" "$SAIDA"
echo "[OK] captura com foco: $SAIDA ($REGIAO)"
