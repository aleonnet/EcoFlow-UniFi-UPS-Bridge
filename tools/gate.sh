#!/bin/bash
# gate.sh — portão de qualidade (Fase 2 + Fase 3'-EXP; bash 3.2 compat; saída [OK]/[ERRO]).
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

# ── Cenas de mutação (convenção da casa, endurecida na Fase 3'-EXP) ─────────
# cena_mutacao NOME ARQUIVO ÂNCORA MUTANTE NÓ... — três asserções, nunca "qualquer rc≠0":
#   (1) baseline: os MESMOS nós passam na árvore limpa (N passed, N>0);
#   (2) mutante (cópia em mktemp com src/tests/config/tools/pyproject): rc == 1
#       (1 = testes falharam; 2/4/5 = coleta/uso/nada selecionado = cena inválida);
#   (3) cada nó aparece como FAILED no log do mutante.
# O mutante preserva sintaxe (troca de token). PYTHONPATH força o import da cópia.
cena_mutacao() {
    local nome="$1" arq="$2" ancora="$3" mutante="$4"
    shift 4
    if ! (cd "$RAIZ" && "$PY" -m pytest "$@" >"/tmp/gate_base_$nome.log" 2>&1); then
        erro "$nome baseline: os nós não passam na árvore limpa — cauda:"; tail -3 "/tmp/gate_base_$nome.log"; return
    fi
    local n
    n="$(grep -Eo '[0-9]+ passed' "/tmp/gate_base_$nome.log" | head -1 | cut -d' ' -f1)"
    if [ -z "$n" ] || [ "$n" -lt 1 ]; then erro "$nome baseline: nenhum teste selecionado"; return; fi
    local M
    M="$(mktemp -d)"
    cp -R "$RAIZ/src" "$M/src"; cp -R "$RAIZ/tests" "$M/tests"; cp -R "$RAIZ/config" "$M/config"
    cp -R "$RAIZ/tools" "$M/tools"; cp "$RAIZ/pyproject.toml" "$M/"
    if ! GATE_ANC="$ancora" GATE_MUT="$mutante" "$PY" - "$M/$arq" <<'EOF'
import os, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anc, mut = os.environ["GATE_ANC"], os.environ["GATE_MUT"]
if s.count(anc) != 1:
    sys.exit(f"âncora não única ({s.count(anc)}): {anc!r} — atualizar gate.sh")
open(p, "w", encoding="utf-8").write(s.replace(anc, mut, 1))
EOF
    then erro "$nome: âncora da mutação sumiu — atualizar gate.sh"; rm -rf "$M"; return; fi
    (cd "$M" && PYTHONPATH="$M/src" "$PY" -m pytest "$@" >"/tmp/gate_mut_$nome.log" 2>&1)
    local rc=$?
    if [ "$rc" -ne 1 ]; then
        erro "$nome mutação: rc=$rc (esperado 1 = a cerca reprovou o defeito plantado)"; tail -3 "/tmp/gate_mut_$nome.log"; rm -rf "$M"; return
    fi
    local no faltou=0
    for no in "$@"; do
        grep -q "FAILED $no" "/tmp/gate_mut_$nome.log" || { erro "$nome mutação: nó não reprovou: $no"; faltou=1; }
    done
    rm -rf "$M"
    [ "$faltou" -eq 0 ] && ok "$nome mutação: baseline $n verde; cerca reprovou o defeito plantado (rc=1, $# nó(s))"
}

# S4 — obrigatórias desativadas em config.py → test_config TEM de reprovar.
cena_mutacao S4 src/river_unifi_bridge/config.py "if missing:" "if False:" \
    tests/unit/test_config.py::test_missing_required_key_fails
# S4b — bind 127.0.0.1 → 0.0.0.0 em api.py.
cena_mutacao S4b src/river_unifi_bridge/api.py 'BIND_HOST = "127.0.0.1"' 'BIND_HOST = "0.0.0.0"' \
    tests/unit/test_api.py::test_bind_host_is_loopback_constant
# S4c — denylist de fontes sintéticas esvaziada (nome E substrings) → M1 condição 1.
cena_mutacao S4c src/river_unifi_bridge/protect.py \
    '_SYNTHETIC_DRIVERS = ("fake-nut-ups", "dummy-ups", "dummy", "clone", "clone-outlet")
_SYNTHETIC_SUBSTRINGS = ("fake", "sim", "dummy")' \
    '_SYNTHETIC_DRIVERS = ()
_SYNTHETIC_SUBSTRINGS = ()' \
    tests/unit/test_protect.py::test_synthetic_source_blocks_even_when_armed \
    tests/unit/test_protect.py::test_contract_fake_is_caught_by_denylist
# S4d — modo ensaio ignorado → condição 10.
cena_mutacao S4d src/river_unifi_bridge/protect.py '                    if pc.protect_dry_run:
                        self._latched = True
                        self._dryrun_this_outage = True' '                    if False:
                        self._latched = True
                        self._dryrun_this_outage = True' \
    tests/unit/test_protect.py::test_dry_run_never_spawns
# S4f — serial não comparado → condição 3.
cena_mutacao S4f src/river_unifi_bridge/protect.py "if serial != expected_serial:" "if False:" \
    tests/unit/test_protect.py::test_serial_mismatch_blocks
# S4g — autorização do PUT desligada (trava, fonte, .env intacto).
cena_mutacao S4g src/river_unifi_bridge/api.py \
    "refusal = _authorize(parsed, self.holder, snapshot, comm_ok)" \
    "refusal = None and _authorize(parsed, self.holder, snapshot, comm_ok)" \
    tests/unit/test_api.py::test_put_arming_refused_when_lock_closed \
    tests/unit/test_api.py::test_put_refused_leaves_env_intact \
    tests/unit/test_api.py::test_arming_requires_real_source_snapshot
# S4h — loopback do NUT não exigido → condição 2.
cena_mutacao S4h src/river_unifi_bridge/protect.py "if not _is_loopback(pc.nut_host):" "if False:" \
    tests/unit/test_protect.py::test_non_loopback_nut_blocks_when_armed
# S4i — pinos do armed.json não comparados → condição 4.
cena_mutacao S4i src/river_unifi_bridge/protect.py 'if data.get("pins") != pc.pins():' "if False:" \
    tests/unit/test_protect.py::test_armed_file_pin_mismatch_blocks
# S4k — "--" removido do argv (destino poderia virar opção).
cena_mutacao S4k src/river_unifi_bridge/protect.py '        "--",
        f"{pc.udr7_ssh_user}@{pc.udr7_ssh_host}",' '        f"{pc.udr7_ssh_user}@{pc.udr7_ssh_host}",' \
    tests/unit/test_protect.py::test_ssh_argv_is_isolated_and_terminated
# S4l — exceção de desarme removida (o botão de parada).
cena_mutacao S4l src/river_unifi_bridge/api.py "if _is_pure_disarm(changes, pc):" "if False:" \
    tests/unit/test_api.py::test_disarm_is_always_allowed_while_armed

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

# S6 — Swift: build do app + testes do Core (fixtures compartilhados incluídos)
APP_DIR="$RAIZ/macos/RiverBridge"
if [ -d "$APP_DIR" ]; then
    if (cd "$APP_DIR" && swift build >/tmp/gate_swift_build.log 2>&1); then
        ok "S6 swift build"
    else
        erro "S6 swift build — cauda:"
        tail -5 /tmp/gate_swift_build.log
    fi
    if (cd "$APP_DIR" && swift test >/tmp/gate_swift_test.log 2>&1); then
        ok "S7 swift test ($(grep -Eo 'with [0-9]+ tests' /tmp/gate_swift_test.log | tail -1))"
    else
        erro "S7 swift test — cauda:"
        tail -5 /tmp/gate_swift_test.log
    fi
    # S7b — xcodebuild test (mesmos testes, toolchain do Xcode). GATE_SKIP_XCODEBUILD=1 pula
    # (a cena é a mais lenta; o conteúdo já é coberto por S7).
    if [ "${GATE_SKIP_XCODEBUILD:-0}" = "1" ]; then
        ok "S7b xcodebuild test (pulado por GATE_SKIP_XCODEBUILD=1)"
    elif (cd "$APP_DIR" && xcodebuild test -scheme RiverBridge -destination 'platform=macOS' >/tmp/gate_xcb.log 2>&1); then
        ok "S7b xcodebuild test"
    else
        erro "S7b xcodebuild test — cauda:"
        tail -5 /tmp/gate_xcb.log
    fi
fi

# S8..S10 — instalador (ordem 7): dry-run inócuo, idempotência 0→100,
# uninstall preserva o alheio. Tudo em scratch com stubs de brew/launchctl.
INST="$(mktemp -d)"
mkdir -p "$INST/bin" "$INST/ld" "$INST/prefix"
cat > "$INST/bin/brew" <<EOF
#!/bin/bash
case "\$1" in
  list) exit 0 ;;
  --prefix) echo "$INST/brewprefix" ;;
esac
exit 0
EOF
cat > "$INST/bin/launchctl" <<EOF
#!/bin/bash
case "\$1" in
  print) [ -f "$INST/ld/.carregado" ] && exit 0 || exit 1 ;;
  bootstrap) touch "$INST/ld/.carregado"; exit 0 ;;
  bootout) rm -f "$INST/ld/.carregado"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$INST/bin/brew" "$INST/bin/launchctl"
INSTALL_ENV="PATH=$INST/bin:/usr/bin:/bin RUB_BREW=$INST/bin/brew RUB_PREFIX=$INST/prefix RUB_LAUNCHD_DIR=$INST/ld RUB_SERVICE_USER=$(id -un) RUB_PYTHON=$RAIZ/.venv/bin/python"

# S8 — dry-run não escreve nada
env $INSTALL_ENV "$RAIZ/scripts/install.sh" --dry-run >/tmp/gate_inst_dry.log 2>&1
if [ -z "$(find "$INST/prefix" "$INST/ld" -type f 2>/dev/null | grep -v last-run)" ]; then
    ok "S8 install --dry-run não escreve"
else
    erro "S8 dry-run escreveu arquivos:"; find "$INST/prefix" "$INST/ld" -type f | head -5
fi

# S9 — 1ª execução faz (exit 0); 2ª reporta que já estava (exit 100)
env $INSTALL_ENV "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_1.log 2>&1
RC1=$?
env $INSTALL_ENV "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_2.log 2>&1
RC2=$?
if [ "$RC1" = "0" ] && [ "$RC2" = "100" ]; then
    ok "S9 idempotência do instalador (1ª=0, 2ª=100)"
else
    erro "S9 idempotência: rc1=$RC1 rc2=$RC2 — caudas:"
    tail -3 /tmp/gate_inst_1.log /tmp/gate_inst_2.log
fi

# S10 — uninstall remove o criado e PRESERVA arquivo alheio
echo alheio > "$INST/prefix/arquivo-do-dono.txt"
env $INSTALL_ENV "$RAIZ/scripts/uninstall.sh" --confirm >/tmp/gate_inst_un.log 2>&1
if [ -f "$INST/prefix/arquivo-do-dono.txt" ] \
   && [ ! -d "$INST/prefix/src" ] && [ ! -d "$INST/prefix/venv" ] \
   && [ ! -f "$INST/ld/com.river.unifi-bridge.plist" ] \
   && [ ! -f "$INST/ld/.carregado" ]; then
    ok "S10 uninstall: só o nosso saiu; o alheio ficou"
else
    erro "S10 uninstall — estado final inesperado:"; find "$INST/prefix" "$INST/ld" 2>/dev/null | head -8
fi
rm -rf "$INST"

# ── S11..S14 — o instalador em uma linha (river-bridge-install.sh) ──────────
ONE="$RAIZ/river-bridge-install.sh"
# S11 — sintaxe em /bin/bash 3.2 + --help pelo CANO (curl | bash) sob locale C = ASCII puro
if /bin/bash -n "$ONE" 2>/dev/null \
   && [ "$(cat "$ONE" | LC_ALL=C LANG=C /bin/bash -s -- --help 2>&1 | LC_ALL=C tr -d '[:print:][:space:]' | wc -c | tr -d ' ')" = "0" ] \
   && cat "$ONE" | LC_ALL=C /bin/bash -s -- --help 2>/dev/null | grep -q -- '--dry-run'; then
    ok "S11 one-liner: bash -n + --help pelo cano sob locale C (ASCII puro)"
else
    erro "S11 one-liner: sintaxe ou --help pelo cano"
fi

# S12 — contrato 0 → 100 → kickstart com código novo → download por file:// (stubs, sem root, sem rede)
OL="$(mktemp -d)"
mkdir -p "$OL/bin" "$OL/ld" "$OL/prefix" "$OL/state" "$OL/cache" "$OL/apps"
cat > "$OL/bin/brew" <<EOF
#!/bin/bash
case "\$1" in list) exit 0 ;; --prefix) echo "$OL/brewprefix" ;; esac
exit 0
EOF
cat > "$OL/bin/launchctl" <<EOF
#!/bin/bash
case "\$1" in
  print) [ -f "$OL/ld/.carregado" ] && exit 0 || exit 1 ;;
  bootstrap) touch "$OL/ld/.carregado"; exit 0 ;;
  bootout) rm -f "$OL/ld/.carregado"; exit 0 ;;
  kickstart) echo kick >> "$OL/ld/.kicks"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$OL/bin/brew" "$OL/bin/launchctl"
OL_ENV="PATH=$OL/bin:/usr/bin:/bin RUB_BREW=$OL/bin/brew RUB_PREFIX=$OL/prefix RUB_LAUNCHD_DIR=$OL/ld RUB_SERVICE_USER=$(id -un) RUB_PYTHON=$PY RUB_SUDO= RUB_STATE_DIR=$OL/state RUB_CACHE_DIR=$OL/cache RUB_APP_DEST=$OL/apps/app RUB_SKIP_HEALTH=1 NO_COLOR=1"
env $OL_ENV "$ONE" --yes --no-anim --no-app --src "$RAIZ" >"$OL/r1.log" 2>&1; OL_RC1=$?
env $OL_ENV "$ONE" --yes --no-anim --no-app --src "$RAIZ" >"$OL/r2.log" 2>&1; OL_RC2=$?
echo "# gate" >> "$OL/prefix/src/river_unifi_bridge/__init__.py"
env $OL_ENV "$ONE" --yes --no-anim --no-app --src "$RAIZ" >"$OL/r3.log" 2>&1; OL_RC3=$?
OL_KICKS="$(grep -c kick "$OL/ld/.kicks" 2>/dev/null || echo 0)"
(cd "$RAIZ" && tar -czf "$OL/repo.tgz" --exclude .git --exclude .venv --exclude .build --exclude __pycache__ --exclude 'macos/RiverBridge/dist' -s '|^\./|repo-main/|' . 2>/dev/null)
env $OL_ENV RUB_SRC_URL="file://$OL/repo.tgz" "$ONE" --yes --no-anim --no-app >"$OL/r4.log" 2>&1; OL_RC4=$?
# O fecho segue o molde da casa (relatorio_final): 1ª execução "Feito até aqui", 2ª "Nada a fazer".
if [ "$OL_RC1" = "0" ] && [ "$OL_RC2" = "100" ] && [ "$OL_RC3" = "0" ] && [ "$OL_KICKS" = "1" ] \
   && [ "$OL_RC4" = "0" ] && [ -x "$OL"/cache/src-*/scripts/install.sh ] && [ -f "$OL/state/installer-last-run.log" ] \
   && grep -qE "Feito até aqui|Done so far" "$OL/r1.log" && grep -qE "Nada a fazer|Nothing to do" "$OL/r2.log" \
   && grep -qE "O que ficou instalado|Installed on this machine" "$OL/r2.log"; then
    ok "S12 one-liner: 0 → 100 → kickstart (1) → download file:// extraído e instalado · fecho no molde (Feito até aqui / Nada a fazer)"
else
    erro "S12 one-liner: rc1=$OL_RC1 rc2=$OL_RC2 rc3=$OL_RC3 kicks=$OL_KICKS rc4=$OL_RC4 — caudas:"
    tail -3 "$OL/r1.log" "$OL/r2.log" "$OL/r3.log" "$OL/r4.log" 2>/dev/null
fi
# S13 — dry-run pelo cano não escreve NADA (nem estado, nem cache)
OL2="$(mktemp -d)"
cat "$ONE" | env RUB_STATE_DIR="$OL2/state" RUB_CACHE_DIR="$OL2/cache" NO_COLOR=1 LC_ALL=C /bin/bash -s -- --dry-run --src "$RAIZ" >"$OL2/dry.log" 2>&1; OL_RC5=$?
if [ "$OL_RC5" = "0" ] && [ ! -e "$OL2/state" ] && [ ! -e "$OL2/cache" ] && grep -q "dry-run" "$OL2/dry.log"; then
    ok "S13 one-liner: dry-run pelo cano sai 0 e não escreve nada"
else
    erro "S13 one-liner: dry-run rc=$OL_RC5 ou escreveu (state/cache)"; tail -3 "$OL2/dry.log"
fi
rm -rf "$OL" "$OL2"

# S14 — snapshot da abertura (quadro final) num pty de 80 colunas, escapes removidos.
# Só num pty a camada visual vê TTY; sem ele degrada para texto e o snapshot não diria nada.
SNAP_DIR="$RAIZ/tests/snapshots"; mkdir -p "$SNAP_DIR"
SNAP_OUT="$(mktemp)"
"$PY" - "$ONE" > "$SNAP_OUT" <<'EOF'
import os, pty, re, sys, fcntl, termios, struct
script = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update({"TERM": "xterm-256color", "COLORTERM": "truecolor", "COLUMNS": "80",
                       "LC_ALL": "en_US.UTF-8", "LANG": "en_US.UTF-8", "UI_NO_ANIM": "1"})
    os.execv("/bin/bash", ["/bin/bash", script, "--demo-frame", "-1"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 80, 0, 0))
out = b""
while True:
    try:
        chunk = os.read(fd, 65536)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
os.waitpid(pid, 0)
text = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", out).decode("utf-8", "replace").replace("\r", "")
print("\n".join(l.rstrip() for l in text.splitlines()).rstrip())
EOF
if [ "${GATE_UPDATE:-0}" = "1" ] || [ ! -f "$SNAP_DIR/abertura-80-utf8.txt" ]; then
    cp "$SNAP_OUT" "$SNAP_DIR/abertura-80-utf8.txt"
    ok "S14 abertura: snapshot (re)gravado em tests/snapshots/abertura-80-utf8.txt"
elif diff -q "$SNAP_OUT" "$SNAP_DIR/abertura-80-utf8.txt" >/dev/null; then
    ok "S14 abertura: quadro final idêntico ao snapshot (pty 80 col)"
else
    erro "S14 abertura: quadro final divergiu do snapshot (GATE_UPDATE=1 regrava se a mudança for intencional)"
    diff "$SNAP_OUT" "$SNAP_DIR/abertura-80-utf8.txt" | head -6
fi
rm -f "$SNAP_OUT"

if [ "$FALHAS" -eq 0 ]; then
    printf 'GATE: VERDE\n'
    exit 0
fi
printf 'GATE: VERMELHO (%d falhas)\n' "$FALHAS"
exit 1
