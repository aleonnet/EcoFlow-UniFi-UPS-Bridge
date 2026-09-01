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
#   ./tools/ui-demo.sh --comparar [ref]   a abertura de hoje, um Enter, e a de
#                                   antes, para escolher olhando as duas
#
# O modo --comparar roda cada abertura num PROCESSO À PARTE (bash <script>
# --demo), nunca duas bibliotecas no mesmo shell. O risco não são as variáveis que
# a versão antiga tem a mais (LG_RGB) — essas nascem no `source` e são inofensivas:
# é o contrário. LG_MIN_LINHAS, LG_FGA e LG_BGA existem só na versão de hoje e
# SOBREVIVERIAM a um `source` da antiga, que não as redefine. Processo à parte não
# deixa nada de pé.
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# As aberturas anteriores, por commit. Não são "versões" do produto: são os três
# desenhos que existiram, guardados para comparação lado a lado.
#   ed44a8e  1ª — o ícone INTEIRO (o quadrado arredondado), 40×40, cada pixel com
#            a sua cor do render: a de maior resolução de cor que já houve.
#   d5a68a3  2ª — só o escudo, 34×40, ainda com cor por pixel.
# A de hoje é o escudo em 34×40 com o gradiente calculado por linha no runtime.
DEMO_REF_PADRAO="ed44a8e"
# O instalador é a camada visual: com RBI_LIB=1 ele define tudo e retorna.
# shellcheck source=../river-bridge-install.sh
RBI_LIB=1 source "$RAIZ/river-bridge-install.sh"

[ "${1:-}" = "--no-anim" ] && UI_ANIM=0

# A camada não instala trap — quem usa é que cuida do cursor.
demo_cleanup() { ui_show_cursor; }
trap demo_cleanup EXIT INT TERM

# --comparar: a de hoje, um Enter, a de antes. Cada uma em processo próprio.
if [ "${1:-}" = "--comparar" ]; then
  ref="${2:-$DEMO_REF_PADRAO}"
  command -v git >/dev/null 2>&1 \
    || { printf 'precisa do git para buscar a abertura de %s\n' "$ref" >&2; exit 1; }
  git -C "$RAIZ" rev-parse --git-dir >/dev/null 2>&1 \
    || { printf '%s não é um repositório git: não há de onde tirar a abertura antiga\n' "$RAIZ" >&2; exit 1; }
  antigo="$(mktemp -t ui-demo-antigo)" \
    || { printf 'não consegui criar o arquivo temporário\n' >&2; exit 1; }

  # O handler de INT/TERM do bash NÃO encerra sozinho: sem o `exit`, o script
  # retomava na linha seguinte com o temporário JÁ APAGADO e tentava executá-lo.
  # Medido em 2026-09-01: no prompt do Enter o processo sobrevivia a dois TERM e
  # só saía com kill -9.
  comparar_limpa() { rm -f "$antigo"; demo_cleanup; }
  trap comparar_limpa EXIT
  trap 'comparar_limpa; exit 130' INT TERM

  # O erro do git é mostrado, não engolido: "ref não existe" e "ref existe mas não
  # tem o arquivo" são coisas diferentes para quem está lendo.
  if ! git_erro="$(git -C "$RAIZ" show "${ref}:river-bridge-install.sh" 2>&1 >"$antigo")"; then
    printf 'não consegui ler a abertura de %s: %s\n' "$ref" "$git_erro" >&2; exit 1
  fi
  # A ref vem da linha de comando: só executo o que para na abertura. Um script sem
  # --demo cairia no main() e começaria a INSTALAR.
  grep -q -- '--demo)' "$antigo" \
    || { printf 'a abertura de %s não tem o modo --demo; não vou executá-la\n' "$ref" >&2; exit 1; }

  # Canvas e paleta lidos do PRÓPRIO script de cada versão — nunca de tabela aqui,
  # que envelheceria calada. Quando o script não declara as medidas, isto DIZ que
  # não sabe: inventar "0 linhas · gradiente por linha" seria a mesma mentira calada
  # com outra fonte.
  medidas() {
    local f="$1" w h paleta
    w="$(sed -n 's/^LG_W=\([0-9]*\)$/\1/p' "$f" | head -1)"
    h="$(sed -n 's/^LG_H=\([0-9]*\)$/\1/p' "$f" | head -1)"
    if [ -z "$w" ] || [ -z "$h" ]; then printf 'sem LG_W/LG_H declarados'; return 0; fi
    if grep -q '^LG_RGB=(' "$f"; then paleta="cor por pixel"; else paleta="gradiente por linha"; fi
    printf '%s×%s px · %s linhas · %s' "$w" "$h" "$(( h / 2 ))" "$paleta"
  }

  clear 2>/dev/null || true
  printf '  [DEMO] a abertura de HOJE — %s\n\n' "$(medidas "$RAIZ/river-bridge-install.sh")"
  bash "$RAIZ/river-bridge-install.sh" --demo; rc_hoje=$?
  # Sem terminal interativo o `read` fica bloqueado enquanto o cano não fechar
  # (medido: num cano sem EOF o processo não voltava em 2 minutos). Aí segue
  # direto — quem lê por cano quer a saída, não a pausa.
  if [ -t 0 ]; then
    printf '  Enter para a abertura de %s — %s ' "$ref" "$(medidas "$antigo")"
    read -r _ || printf '\n'
  else
    printf '  (sem terminal interativo: seguindo direto para a de %s)\n' "$ref"
  fi
  # Aqui NÃO se limpa a tela: o `clear` do macOS emite \033[3J, que apaga o buffer
  # de rolagem — a abertura de hoje sumiria antes da antiga aparecer e não daria
  # nem para rolar de volta. Comparar exige as duas alcançáveis.
  printf '\n  ────────────────────────────────\n\n'
  printf '  [DEMO] a abertura de %s — %s\n\n' "$ref" "$(medidas "$antigo")"
  bash "$antigo" --demo; rc_antiga=$?
  [ "$rc_hoje" -eq 0 ] && [ "$rc_antiga" -eq 0 ] || {
    printf '  uma das aberturas falhou (hoje %s · %s %s)\n' "$rc_hoje" "$ref" "$rc_antiga" >&2
    exit 1
  }
  exit 0
fi

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
