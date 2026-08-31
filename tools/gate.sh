#!/bin/bash
# gate.sh — portão de qualidade da Fase 2 (bash 3.2 compat; saída [OK]/[ERRO]).
# Cenas: sintaxe, unit, integração, mutação de cerca (a cerca TEM de reprovar
# quando o defeito é plantado — convenção da casa).
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PY="${GATE_PYTHON:-$RAIZ/.venv/bin/python}"
FALHAS=0

ok()   { printf '[OK]   %s\n' "$1"; }
erro() { printf '[ERRO] %s\n' "$1"; FALHAS=$((FALHAS + 1)); }

# S0 — interpretador exigido pela spec (>= 3.13)
if "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 13) else 1)' 2>/dev/null; then
    ok "S0 python $("$PY" -c 'import platform; print(platform.python_version())') >= 3.13"
else
    erro "S0 python >= 3.13 ausente (use GATE_PYTHON ou crie .venv)"
    printf 'Gate abortado: sem interpretador não há cenas válidas.\n'
    exit 1
fi

# S1 — sintaxe de todos os fontes (inclui o simulador, que não tem .py)
if "$PY" -m py_compile "$RAIZ"/src/river_unifi_bridge/*.py "$RAIZ/tools/fake-nut-ups" 2>/dev/null; then
    ok "S1 py_compile"
else
    erro "S1 py_compile"
fi

# S2 — unit (addopts do pyproject já traz -q; não duplicar, senão o sumário some)
if (cd "$RAIZ" && "$PY" -m pytest tests/unit >/tmp/gate_unit.log 2>&1); then
    ok "S2 unit ($(grep -Eo '[0-9]+ passed' /tmp/gate_unit.log | head -1))"
else
    erro "S2 unit — cauda do log:"
    tail -5 /tmp/gate_unit.log
fi

# S3 — integração contra fake-nut-ups
if (cd "$RAIZ" && "$PY" -m pytest tests/integration >/tmp/gate_int.log 2>&1); then
    ok "S3 integração ($(grep -Eo '[0-9]+ passed' /tmp/gate_int.log | head -1))"
else
    erro "S3 integração — cauda do log:"
    tail -5 /tmp/gate_int.log
fi

# S4 — MUTAÇÃO: remover a checagem de chave obrigatória de config.py.
# Com o defeito plantado, tests/unit/test_config.py TEM de reprovar.
MUT="$(mktemp -d)"
cp -R "$RAIZ/src" "$MUT/src"
cp -R "$RAIZ/tests" "$MUT/tests"
cp -R "$RAIZ/config" "$MUT/config"
cp "$RAIZ/pyproject.toml" "$MUT/"
# Planta o defeito: a lista de obrigatórias vira sempre-vazia.
"$PY" - "$MUT/src/river_unifi_bridge/config.py" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
alvo = "if missing:"
assert alvo in s, "âncora da mutação sumiu — atualizar gate.sh"
open(p, "w", encoding="utf-8").write(s.replace(alvo, "if False:"))
EOF
# PYTHONPATH força o import do MUTANTE — o venv tem o pacote em editable
# apontando para o src original, que venceria em silêncio sem isto.
if (cd "$MUT" && PYTHONPATH="$MUT/src" "$PY" -m pytest tests/unit/test_config.py >/tmp/gate_mut.log 2>&1); then
    erro "S4 mutação: cerca NÃO detectou defeito plantado (obrigatórias desativadas)"
else
    ok "S4 mutação: cerca reprovou o defeito plantado"
fi
rm -rf "$MUT"

# S4b — MUTAÇÃO do bind: 127.0.0.1 → 0.0.0.0 em api.py.
# test_api.py::test_bind_host_is_loopback_constant TEM de reprovar.
MUT2="$(mktemp -d)"
cp -R "$RAIZ/src" "$MUT2/src"
cp -R "$RAIZ/tests" "$MUT2/tests"
cp "$RAIZ/pyproject.toml" "$MUT2/"
"$PY" - "$MUT2/src/river_unifi_bridge/api.py" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
alvo = 'BIND_HOST = "127.0.0.1"'
assert alvo in s, "âncora da mutação S4b sumiu — atualizar gate.sh"
open(p, "w", encoding="utf-8").write(s.replace(alvo, 'BIND_HOST = "0.0.0.0"'))
EOF
if (cd "$MUT2" && PYTHONPATH="$MUT2/src" "$PY" -m pytest tests/unit/test_api.py -k bind >/tmp/gate_mut2.log 2>&1); then
    erro "S4b mutação bind: cerca NÃO detectou bind 0.0.0.0"
else
    ok "S4b mutação bind: cerca reprovou o defeito plantado"
fi
rm -rf "$MUT2"

# S5 — exemplo de config do repo parseia limpo
if (cd "$RAIZ" && "$PY" - <<'EOF' >/dev/null 2>&1
import sys
sys.path.insert(0, "src")
from river_unifi_bridge.config import load_config
cfg = load_config("config/river-unifi-bridge.env.example")
assert cfg.warnings == []
EOF
); then
    ok "S5 env.example parseia sem avisos"
else
    erro "S5 env.example"
fi

if [ "$FALHAS" -eq 0 ]; then
    printf 'GATE: VERDE\n'
    exit 0
fi
printf 'GATE: VERMELHO (%d falhas)\n' "$FALHAS"
exit 1
