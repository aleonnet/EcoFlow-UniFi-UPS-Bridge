#!/usr/bin/env bash
# =============================================================================
# ui-demo.sh — demonstração da camada visual do instalador.
#
# Molde: tools/ui-demo.sh do haos-install, e pelos mesmos dois motivos que lá
# custaram caro:
#
#  1. A demo NÃO mora dentro do instalador. A guarda `[[ "${BASH_SOURCE[0]}"
#     == "$0" ]]` erra nos dois modos que o produto usa: concatenada num script
#     autocontido ela vira verdadeira e a demo roda em produção; vinda de stdin
#     (`curl | bash`) o array BASH_SOURCE é vazio e, com `set -u`, aborta o
#     instalador na primeira linha. Aqui carregamos o instalador como
#     biblioteca (RBI_LIB=1) e chamamos as funções.
#
#  2. Demonstração que afirma fato mente para quem lê. Todo valor abaixo é
#     obviamente falso e todo rótulo diz [DEMO] — nada aqui foi medido,
#     instalado ou conferido.
#
#   ./tools/ui-demo.sh              com animação
#   ./tools/ui-demo.sh --no-anim    um quadro estático
#   ./tools/ui-demo.sh --logo       só a abertura (o escudo)
#   ./tools/ui-demo.sh --quadro N   um quadro específico (-1 = o final)
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# O instalador é a camada visual: com RBI_LIB=1 ele define tudo e retorna.
# shellcheck source=../river-bridge-install.sh
RBI_LIB=1 source "$RAIZ/river-bridge-install.sh"

case "${1:-}" in
  --no-anim) UI_ANIM=0 ;;
  --logo)    ;;
  --quadro)  ;;
esac

# A camada não instala trap — quem usa é que cuida do cursor.
demo_cleanup() { ui_show_cursor; }
trap demo_cleanup EXIT INT TERM

if [ "${1:-}" = "--quadro" ]; then
  lg_quadro "${2:--1}"
  exit 0
fi

clear 2>/dev/null || true
ui_banner "River Bridge" "[DEMO] camada visual — nenhum valor abaixo é real"
[ "${1:-}" = "--logo" ] && exit 0

UI_BAR_TOTAL=3
fase "[DEMO] Pré-voo"
ui_ok   "[DEMO] Homebrew em /opt/homebrew/bin/brew"
ui_info "[DEMO] código-fonte X.Y.Z — 000 KiB, sha256 000000000000"
ui_warn "[DEMO] sem Swift/Xcode: o app não seria compilado"
ui_skip "[DEMO] passo que não se aplica a esta plataforma"

fase "[DEMO] Serviço"
( sleep 1.2 ) & ui_spin "[DEMO] instalando o LaunchDaemon" $!
( sleep 0.8 ) & ui_spin "[DEMO] lendo o job de volta para conferir" $!

fase "[DEMO] Verificação"
ui_ok "[DEMO] API local respondeu · NUT sem_dados · UDR7 desabilitado"

printf '\n'; ui_rule
ui_shimmer "  [DEMO] 3 fases · 0 falhas"
printf '\n'
