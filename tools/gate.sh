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
# compileall é RECURSIVO: o glob *.py não entrava em plugins/ e um erro de
# sintaxe dentro do pacote passava batido. O fake-nut-ups não tem extensão .py,
# então continua indo por py_compile (bash 3.2 aqui não tem globstar).
if "$PY" -m compileall -q "$RAIZ/src/river_unifi_bridge" >/dev/null 2>&1 \
   && "$PY" -m py_compile "$RAIZ/tools/fake-nut-ups" 2>/dev/null; then
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
    "refusal = _authorize(parsed, self.plugins, snapshot, comm_ok)" \
    "refusal = None and _authorize(parsed, self.plugins, snapshot, comm_ok)" \
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
# S4l migrou de api.py para o adaptador do UDR7 e, em 2026-09-03, para o motor SSH
# comum (ssh_motor.py) — o texto da âncora é o mesmo; o PUT legado e o PUT de
# instância passam pelo mesmo authorize_update.
cena_mutacao S4l src/river_unifi_bridge/plugins/ssh_motor.py "if _is_pure_disarm(changes, pc):" "if False:" \
    tests/unit/test_api.py::test_disarm_is_always_allowed_while_armed

# P6 — o alias udr7/udr7_detail do health deriva da entrada certa da lista.
cena_mutacao S4n src/river_unifi_bridge/state.py 'if p["id"] == UDR7_ALIAS_ID' "if False" \
    tests/unit/test_fixtures_contract.py::test_health_udr7_fixture_matches_code \
    tests/unit/test_service_loop.py::test_process_snapshot_drives_policy_state_and_history

# P1 — o nome do dispositivo: prefixo UDR7_ mas NÃO é configuração de proteção.
# Desde 2026-09-03 a regra "renomear armado é permitido" vive no MOTOR, sobre o
# patch da instância (S4x); em config.py a cerca guarda o conjunto congelado do
# .env (PROTECTION_KEYS sem o nome), que o PUT legado do núcleo ainda consulta.
cena_mutacao S4m src/river_unifi_bridge/config.py "    - DEVICE_NAME_KEYS" "    | DEVICE_NAME_KEYS" \
    tests/unit/test_config.py::test_protection_key_sets_are_consistent
cena_mutacao S4x src/river_unifi_bridge/plugins/ssh_motor.py \
    'touched = sorted(set(changes) - {"name"})' 'touched = sorted(set(changes))' \
    tests/unit/test_api.py::test_rename_allowed_while_armed
cena_mutacao S4o src/river_unifi_bridge/protect.py '"udr7_arm_allowed", "udr7_name")' '"udr7_arm_allowed")' \
    tests/unit/test_protect.py::test_rename_while_armed_keeps_pins

# Dispositivos por instância (2026-09-03).
# S4p — o comando de desligamento fora dos pinos: trocar o comando de uma instância
# armada deixaria de virar config_trocada e o envio divergiria do pinado.
cena_mutacao S4p src/river_unifi_bridge/protect.py \
    'return {k: v for k, v in asdict(self).items() if k not in _PIN_EXCLUDED}' \
    'return {k: v for k, v in asdict(self).items() if k not in _PIN_EXCLUDED and k != "shutdown_command"}' \
    tests/unit/test_protect.py::test_shutdown_command_is_pinned
# S4w — o spawn do ssh passa por shell: o comando de um host genérico viraria
# superfície de injeção. O argv tem de chegar ao runner como LISTA, sem `shell`.
cena_mutacao S4w src/river_unifi_bridge/protect.py \
    'argv, capture_output=True, timeout=SUBPROCESS_TIMEOUT_SECONDS, check=False,' \
    '" ".join(argv), shell=True, capture_output=True, timeout=SUBPROCESS_TIMEOUT_SECONDS, check=False,' \
    tests/unit/test_protect.py::test_ssh_spawn_is_argv_list_without_shell
# S4s — nome repetido aceito: dois dispositivos com o mesmo nome (casefold) colidiriam
# em chips, legenda e cartões (B14). A loja recusa com nome_duplicado.
cena_mutacao S4s src/river_unifi_bridge/devices.py \
    'if other.name.strip().casefold() == wanted:' 'if False:' \
    tests/unit/test_devices.py::test_store_rejects_duplicate_name_casefold
# S4t — loja presente re-migrada: cada boot recriaria o udr7 do .env, duplicando
# e ressuscitando o que o dono apagou.
cena_mutacao S4t src/river_unifi_bridge/devices.py \
    'if self.exists():   # arquivo presente: nunca re-migra' 'if False:   # arquivo presente: nunca re-migra' \
    tests/unit/test_devices.py::test_migration_runs_once_in_ten_boots \
    tests/unit/test_devices.py::test_deleted_udr7_is_not_resurrected
# S4r — comando do host SSH fora da lista fechada aceito: texto livre viraria o
# último elemento do argv do ssh (defesa em profundidade além do validate_fields).
cena_mutacao S4r src/river_unifi_bridge/plugins/ssh_host.py \
    'if value not in SHUTDOWN_COMMANDS:' 'if False:' \
    tests/unit/test_plugin_contract.py::test_ssh_host_rejects_command_outside_allowlist
# S4q — DELETE de instância armada aceito: a proteção sumiria com um clique, sem os
# passos do dono, e o armed.json ficaria órfão.
cena_mutacao S4q src/river_unifi_bridge/api.py \
    'if plugin.armed:  # DELETE nunca remove um dispositivo armado' 'if False:  # DELETE nunca remove um dispositivo armado' \
    tests/unit/test_api.py::test_devices_delete_refused_while_armed
# S4v — POST criando já armado: armar é só pelo PUT (trava + fonte real + confirmação).
cena_mutacao S4v src/river_unifi_bridge/api.py \
    'if enabled and not dry_run:' 'if False:' \
    tests/unit/test_api.py::test_devices_post_cannot_create_armed
# S4u — a loja (e o armed.json) gravados com permissão aberta: _read_private_json
# recusaria o próprio arquivo, e qualquer usuário local leria os pinos.
cena_mutacao S4u src/river_unifi_bridge/protect.py 'os.chmod(tmp, 0o600)' 'os.chmod(tmp, 0o644)' \
    tests/unit/test_devices.py::test_store_is_private_0600

# S4y — o health tem de listar os dispositivos ANTES da primeira leitura do UPS.
# Sem a linha do boot, o app e a contagem do instalador dizem "nenhum dispositivo
# protegido" enquanto o River estiver desligado (medido no Mac mini, 2026-09-03).
cena_mutacao S4y src/river_unifi_bridge/service.py \
    'shared.set_plugins(plugin_statuses(plugins))  # desde o boot' \
    'pass  # desde o boot' \
    tests/unit/test_service_loop.py::test_health_lists_devices_before_first_poll

# S4z — o envio por SSE tem de se orientar pela sequência, não por índice: com a
# fila cheia (100) o índice congela e a linha do tempo para de receber eventos.
cena_mutacao S4z src/river_unifi_bridge/api.py \
    'for event in self.state.events(after=last_seq):' \
    'for event in self.state.events()[last_seq + 1:]:' \
    tests/unit/test_api.py::test_sse_delivers_past_the_hundredth_event

# S4aa — bateria baixa só na bateria: sem a condição de estado, carga baixa
# carregando na tomada vira alerta (B01) na timeline, no SSE e no Home Assistant.
cena_mutacao S4aa src/river_unifi_bridge/service.py \
    'low = snap.state == "ON_BATTERY" and (' \
    'low = True and (' \
    tests/unit/test_transitions.py::test_low_battery_needs_on_battery

# S4ab — vazio em chave numérica/booleana tem de ser recusado no PUT: aceito, ele
# era gravado a quente e o tick seguinte comparava texto com número (daemon morto).
cena_mutacao S4ab src/river_unifi_bridge/config.py \
    'raise ConfigError(f"{key}: valor vazio")' \
    'return ""' \
    tests/unit/test_config.py::test_put_empty_value_is_refused_on_non_string_keys

# S4ac — um dispositivo doente não pode matar o vigia: sem a rede que apara
# `Exception` em volta de cada plugin, uma exceção no tick derruba o serviço que
# vigia a bateria (o launchd relança, mas o ciclo se perde).
cena_mutacao S4ac src/river_unifi_bridge/service.py \
    'except Exception as exc:  # tick_failed: o vigia continua' \
    'except NutError as exc:  # tick_failed: o vigia continua' \
    tests/unit/test_service_loop.py::test_loop_survives_plugin_exception \
    tests/unit/test_service_loop.py::test_loop_survives_plugin_exception_on_the_failure_path

# S4ad — "manter histórico: N dias" só é verdade se a limpeza rodar: a função
# existia desde a 0.1.0 e nunca era chamada em produção (base crescia sem fim).
cena_mutacao S4ad src/river_unifi_bridge/service.py \
    'history.prune()  # retenção' \
    'pass  # retenção' \
    tests/unit/test_service_loop.py::test_loop_prunes_history_hourly

# S4ae — `retry_max` é o NÚMERO de tentativas, contado num lugar só. Com `>`, o
# zero ainda dispara uma vez e o três dispara quatro: a tela mentiria sobre o
# que o serviço faz com o aparelho.
cena_mutacao S4ae src/river_unifi_bridge/protect.py \
    'elif self._attempts >= pc.udr7_retry_max:  # tentativas esgotadas' \
    'elif self._attempts > pc.udr7_retry_max:  # tentativas esgotadas' \
    tests/unit/test_protect.py::test_retry_max_zero_never_spawns \
    tests/unit/test_protect.py::test_retry_max_is_the_number_of_attempts

# S4af — limpar eventos tem de valer também para a fila da memória, que é o que
# o SSE entrega a quem conecta: sem isso os eventos apagados voltavam à tela na
# reconexão seguinte (o dono limpava e eles reapareciam).
cena_mutacao S4af src/river_unifi_bridge/api.py \
    'self.state.clear_events(ts_to)' \
    'pass  # clear_events' \
    tests/unit/test_api.py::test_clearing_events_also_forgets_them_in_memory

# S4ag — a leitura da porta serial do River tem de CONFERIR o quadro. Sem a
# verificação de integridade, ruído na porta vira watt na tela do dono.
cena_mutacao S4ag src/river_unifi_bridge/river_serial.py \
    'if crc16(quadro) != 0:' \
    'if False:' \
    tests/unit/test_river_serial.py::test_a_corrupted_frame_is_refused_not_guessed

# S4ah — a potência lida pela serial tem de chegar ao estado publicado; sem a
# fusão, o app continuaria mostrando "—" com o dado na mão.
cena_mutacao S4ah src/river_unifi_bridge/service.py \
    'snap.outlets = leitura.to_dict()' \
    'snap.outlets = None' \
    tests/unit/test_service_loop.py::test_serial_reading_fills_power_and_outlets

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
  print) [ -f "$INST/ld/.carregado" ] && { printf '\tpid = 4242\n'; exit 0; } || exit 1 ;;
  bootstrap) touch "$INST/ld/.carregado"; exit 0 ;;
  bootout) rm -f "$INST/ld/.carregado"; exit 0 ;;
  kickstart) echo kick >> "$INST/ld/.kicks"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$INST/bin/brew" "$INST/bin/launchctl"
INSTALL_ENV="PATH=$INST/bin:/usr/bin:/bin RUB_BREW=$INST/bin/brew RUB_PREFIX=$INST/prefix RUB_LAUNCHD_DIR=$INST/ld RUB_SERVICE_USER=$(id -un) RUB_PYTHON=$RAIZ/.venv/bin/python RUB_SKIP_HEALTH=1"

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
# O desinstalador tem de sair instalado no prefixo (o README aponta para lá) e
# registrado como created — refutado em 2026-09-02 comentando o install -m 0755.
if [ "$RC1" = "0" ] && [ "$RC2" = "100" ] \
   && [ -x "$INST/prefix/scripts/uninstall.sh" ] \
   && grep -q "^file:$INST/prefix/scripts/uninstall.sh	created$" "$INST/prefix/manifest.tsv"; then
    ok "S9 idempotência do instalador (1ª=0, 2ª=100) + desinstalador no prefixo"
else
    erro "S9 idempotência: rc1=$RC1 rc2=$RC2 desinstalador=$([ -x "$INST/prefix/scripts/uninstall.sh" ] && echo ok || echo ausente) — caudas:"
    tail -3 /tmp/gate_inst_1.log /tmp/gate_inst_2.log
fi

# S9b — guarda pré-atualização (D12, 2026-09-03): serviço carregado + uma
# instância ARMADA (<id>_armed.json no estado) → o instalador sai 3 ANTES da
# primeira mutação: o código instalado (marcado aqui com uma linha a mais) fica
# intocado e o plist também; sem o arquivo, a mesma atualização passa (rc 0),
# substitui o código (a marca some) e reinicia o serviço. O estado entra por
# RUB_STATE_DIR, que também muda o plist. A 1ª versão da guarda ficava na fase
# do plist e deixava o código já trocado (revisão fria de 2026-09-03).
mkdir -p "$INST/state"; : > "$INST/state/udr7_armed.json"
MARCA="$INST/prefix/src/river_unifi_bridge/__init__.py"
echo "# marca S9b" >> "$MARCA"
cp "$INST/ld/com.river.unifi-bridge.plist" /tmp/gate_plist_antes 2>/dev/null || : > /tmp/gate_plist_antes
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9b.log 2>&1
RC9B=$?
PLIST_INTACTO=$(cmp -s /tmp/gate_plist_antes "$INST/ld/com.river.unifi-bridge.plist" && echo 1 || echo 0)
CODIGO_INTACTO=$(grep -q "^# marca S9b$" "$MARCA" && echo 1 || echo 0)
rm -f "$INST/state/udr7_armed.json"
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9c.log 2>&1
RC9C=$?
CODIGO_TROCADO=$(grep -q "^# marca S9b$" "$MARCA" && echo 0 || echo 1)
REINICIOU=$(grep -Eq "recarregado|kickstart" /tmp/gate_inst_9c.log && echo 1 || echo 0)
if [ "$RC9B" = "3" ] && [ "$PLIST_INTACTO" = "1" ] && [ "$CODIGO_INTACTO" = "1" ] && grep -q "ARMADO" /tmp/gate_inst_9b.log \
   && [ "$RC9C" = "0" ] && [ "$CODIGO_TROCADO" = "1" ] && [ "$REINICIOU" = "1" ]; then
    ok "S9b guarda pré-atualização: armado → rc 3, código e plist intactos; desarmado → rc 0, código trocado, serviço reiniciado"
else
    erro "S9b guarda pré-atualização: rc armado=$RC9B plist_intacto=$PLIST_INTACTO codigo_intacto=$CODIGO_INTACTO rc desarmado=$RC9C codigo_trocado=$CODIGO_TROCADO reiniciou=$REINICIOU — caudas:"
    tail -3 /tmp/gate_inst_9b.log /tmp/gate_inst_9c.log
fi

# S9d — a guarda INFORMA no dry-run mesmo sem o serviço visível: sem sudo o
# `launchctl print system/…` pode falhar por privilégio (113 para alguns
# serviços, medido 2026-09-03), e o aviso não depende dele — o arquivo basta.
: > "$INST/state/udr7_armed.json"; rm -f "$INST/ld/.carregado"
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" "$RAIZ/scripts/install.sh" --dry-run >/tmp/gate_inst_9d.log 2>&1
RC9D=$?
rm -f "$INST/state/udr7_armed.json"; : > "$INST/ld/.carregado"
if [ "$RC9D" = "0" ] && grep -q "^│ atenção: .*ARMADO.*seria recusada" /tmp/gate_inst_9d.log; then
    ok "S9d dry-run sem serviço visível informa a instância armada"
else
    erro "S9d dry-run: rc=$RC9D — cauda:"; tail -3 /tmp/gate_inst_9d.log
fi

# Espera até 10 s por um ouvinte TCP na porta (o python de mentira e o daemon
# manual partem a frio; com a máquina carregada, 1 s não bastava — 2026-09-03).
esperar_ouvinte() { local i; for i in $(seq 1 10); do [ -n "$(/usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1)" ] && return 0; sleep 1; done; return 1; }

# S9e — programa ALHEIO na porta da API: a guarda recusa (3) ANTES de qualquer
# mutação, com a frase humana nomeando o programa (sem PID) e o PID no registro
# `#`. O código instalado (marcado) fica intacto. Porta livre 35997 no
# bridge.env do prefixo; ouvinte python de mentira.
sed -i '' 's/^UI_API_PORT=.*/UI_API_PORT=35997/' "$INST/prefix/etc/bridge.env"
python3 -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1",35997)); s.listen(1); time.sleep(90)' &
OUVINTE_PID=$!
esperar_ouvinte 35997 || erro "S9e o ouvinte de mentira não abriu a porta 35997 em 10 s"
echo "# marca S9e" >> "$MARCA"
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" RUB_SKIP_HEALTH=0 "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9e.log 2>&1
RC9E=$?
kill "$OUVINTE_PID" 2>/dev/null; wait "$OUVINTE_PID" 2>/dev/null
if [ "$RC9E" = "3" ] && grep -q "^✖ a porta 35997 já está em uso por outro programa" /tmp/gate_inst_9e.log \
   && grep -q "^#  porta 35997: PID $OUVINTE_PID" /tmp/gate_inst_9e.log && grep -q "^# marca S9e$" "$MARCA"; then
    ok "S9e programa alheio na porta → recusa 3 antes de tocar no código, frase humana + PID só no registro"
else
    erro "S9e programa alheio na porta: rc=$RC9E marca=$(grep -c '^# marca S9e$' "$MARCA") — cauda:"; tail -3 /tmp/gate_inst_9e.log
fi
# resincroniza o código (a marca some) para a S9f ver "código igual"
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9e2.log 2>&1 || true

# S9f — nada mudou, job "carregado" (stub) mas NINGUÉM na porta: o instalador
# relança (kickstart) e, sem daemon real, a prova falha em 15 s com a frase
# humana — nunca "já instalado" com o serviço morto (revisão fria, 2026-09-03:
# a parada deliberada sai 0 e o KeepAlive não relança).
rm -f "$INST/ld/.kicks"
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" RUB_SKIP_HEALTH=0 "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9f.log 2>&1
RC9F=$?
if [ "$RC9F" = "1" ] && [ -f "$INST/ld/.kicks" ] && grep -q "^✖ o serviço foi instalado, mas não respondeu na porta 35997" /tmp/gate_inst_9f.log && ! grep -q "serviço: já instalado" /tmp/gate_inst_9f.log; then
    ok "S9f serviço fora da porta com código igual → kickstart e falha humana (nunca 'já instalado')"
else
    erro "S9f serviço fora da porta: rc=$RC9F kicks=$([ -f "$INST/ld/.kicks" ] && echo sim || echo nao) — cauda:"; tail -3 /tmp/gate_inst_9f.log
fi

# S9g — o ciclo REAL do launchd, sem root: domínio gui/<uid> (seam
# RUB_LAUNCHD_DOMAIN), venv de verdade, o daemon de verdade na porta 35998
# (bridge.env pré-criado com a porta, porque a real 35493 pode estar em uso).
# Prova: (1) instalação nova → o PID que escuta é o PID do job; (2) o NOSSO
# daemon rodando fora do launchd na porta → o instalador o encerra sozinho e o
# job assume (o caso de 2026-09-03 no MacBook do dono); (3) um programa alheio
# → recusa 3 antes de tocar em nada. O job é removido ao fim.
G9="$(mktemp -d)"; mkdir -p "$G9/bin" "$G9/prefix/etc" "$G9/ld" "$G9/state"; cp "$INST/bin/brew" "$G9/bin/brew"
sed 's/^UI_API_PORT=.*/UI_API_PORT=35998/' "$RAIZ/config/river-unifi-bridge.env.example" > "$G9/prefix/etc/bridge.env"; chmod 600 "$G9/prefix/etc/bridge.env"
G9_ENV="PATH=$G9/bin:/usr/bin:/bin:/usr/sbin:/sbin RUB_BREW=$G9/bin/brew RUB_PREFIX=$G9/prefix RUB_LAUNCHD_DIR=$G9/ld RUB_LAUNCHD_DOMAIN=gui/$(id -u) RUB_SERVICE_USER=$(id -un) RUB_PYTHON=$RAIZ/.venv/bin/python RUB_STATE_DIR=$G9/state RUB_LOG_FILE=$G9/daemon.log"
G9_ALVO="gui/$(id -u)/com.river.unifi-bridge"
g9_pid_job() { launchctl print "$G9_ALVO" 2>/dev/null | sed -n 's/^[[:space:]]*pid = \([0-9]*\).*/\1/p' | head -1; }
g9_ouvinte() { /usr/sbin/lsof -nP -iTCP:35998 -sTCP:LISTEN -t 2>/dev/null | head -1; }
launchctl bootout "$G9_ALVO" 2>/dev/null || true
env $G9_ENV "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9g1.log 2>&1; RC9G1=$?
J1="$(g9_pid_job)"; O1="$(g9_ouvinte)"
if [ "$RC9G1" = "0" ] && [ -n "$J1" ] && [ "$J1" = "$O1" ] && grep -q "^│ serviço: instalado, carregado e no ar" /tmp/gate_inst_9g1.log; then
    ok "S9g.1 launchd real (gui): instalação nova → o PID do job é quem escuta a porta"
else
    erro "S9g.1 launchd real: rc=$RC9G1 job=$J1 ouvinte=$O1 — cauda:"; tail -3 /tmp/gate_inst_9g1.log; tail -3 "$G9/daemon.log" 2>/dev/null
fi
# (2) o nosso daemon fora do launchd
launchctl bootout "$G9_ALVO" 2>/dev/null || true; sleep 1
( cd "$G9" && env RUB_STATE_DIR="$G9/state" PYTHONPATH="$G9/prefix/src" HOME="$HOME" "$G9/prefix/venv/bin/python" -m river_unifi_bridge.service --env "$G9/prefix/etc/bridge.env" >"$G9/manual.log" 2>&1 ) &
MANUAL_PID=$!
for i in $(seq 1 15); do [ -n "$(g9_ouvinte)" ] && break; sleep 1; done
O_ANTES="$(g9_ouvinte)"
env $G9_ENV "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9g2.log 2>&1; RC9G2=$?
J2="$(g9_pid_job)"; O2="$(g9_ouvinte)"
if [ "$RC9G2" = "0" ] && [ -n "$O_ANTES" ] && [ -n "$J2" ] && [ "$J2" = "$O2" ] && [ "$O2" != "$O_ANTES" ] \
   && grep -q "^│ uma cópia antiga do serviço estava rodando por fora — foi encerrada" /tmp/gate_inst_9g2.log \
   && ! grep -q "PID" <(grep '^│' /tmp/gate_inst_9g2.log); then
    ok "S9g.2 launchd real: o nosso daemon fora do launchd é encerrado pelo instalador e o job assume a porta (frase humana sem PID)"
else
    erro "S9g.2 launchd real: rc=$RC9G2 antes=$O_ANTES job=$J2 ouvinte=$O2 — cauda:"; tail -4 /tmp/gate_inst_9g2.log
fi
kill "$MANUAL_PID" 2>/dev/null; wait "$MANUAL_PID" 2>/dev/null
# (3) programa alheio
launchctl bootout "$G9_ALVO" 2>/dev/null || true; sleep 1
python3 -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1",35998)); s.listen(1); time.sleep(90)' &
ALHEIO_PID=$!; esperar_ouvinte 35998 || erro "S9g.3 o ouvinte de mentira não abriu a porta 35998 em 10 s"
env $G9_ENV "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9g3.log 2>&1; RC9G3=$?
kill "$ALHEIO_PID" 2>/dev/null; wait "$ALHEIO_PID" 2>/dev/null
if [ "$RC9G3" = "3" ] && grep -q "^✖ a porta 35998 já está em uso por outro programa" /tmp/gate_inst_9g3.log && ! launchctl print "$G9_ALVO" >/dev/null 2>&1; then
    ok "S9g.3 launchd real: programa alheio na porta → recusa 3 antes de carregar o serviço"
else
    erro "S9g.3 launchd real: rc=$RC9G3 — cauda:"; tail -3 /tmp/gate_inst_9g3.log
fi
launchctl bootout "$G9_ALVO" 2>/dev/null || true
# S9j — dry-run SEM sudo no domínio system (launchd não consultável com
# segurança): quem escuta a porta é o serviço INSTALADO (python do venv do
# prefixo + --env do prefixo, prefixo LONGO como o do gate) → o dry-run diz que
# está tudo no lugar, não "cópia antiga … seria encerrada" (revisão fria B-1:
# o corte de 160 colunas no comando escondia o "--env" e o ramo nunca casava).
sleep 2   # o job da S9g.3 acabou de sair; a porta pode levar um instante para ficar livre
( cd "$G9" && env RUB_STATE_DIR="$G9/state" PYTHONPATH="$G9/prefix/src" HOME="$HOME" "$G9/prefix/venv/bin/python" -m river_unifi_bridge.service --env "$G9/prefix/etc/bridge.env" >"$G9/manual2.log" 2>&1 ) &
MANUAL2_PID=$!
# A cena só faz sentido COM o daemon manual na porta: se ele não abrir em 30 s,
# a cena falha dizendo isso (no gate completo ele parte a frio; 15 s não bastaram
# em 2026-09-03 e a cena seguia sem ouvinte, escondendo o que devia provar).
for i in $(seq 1 30); do [ -n "$(g9_ouvinte)" ] && break; sleep 1; done
if [ -z "$(g9_ouvinte)" ]; then
    erro "S9j o daemon manual não abriu a porta 35998 em 30 s — cauda do registro dele:"; tail -3 "$G9/manual2.log" 2>/dev/null
else
    # RUB_LAUNCHD_LABEL próprio: no domínio system sem sudo, `launchctl print` de
    # um rótulo INEXISTENTE é o caso "não consultável"; com o rótulo real a cena
    # consultava o serviço de verdade deste Mac (que hoje responde com PID).
    env PATH="$G9/bin:/usr/bin:/bin:/usr/sbin:/sbin" RUB_BREW="$G9/bin/brew" RUB_PREFIX="$G9/prefix" RUB_LAUNCHD_DIR="$G9/ld" RUB_LAUNCHD_LABEL="com.river.unifi-bridge.gate" RUB_SERVICE_USER="$(id -un)" RUB_STATE_DIR="$G9/state" RUB_LOG_FILE="$G9/daemon.log" \
      "$RAIZ/scripts/install.sh" --dry-run >/tmp/gate_inst_9j.log 2>&1; RC9J=$?
    if [ "$RC9J" = "0" ] && grep -q "é o serviço instalado" /tmp/gate_inst_9j.log && ! grep -q "cópia antiga" /tmp/gate_inst_9j.log && ! grep -q "em uso por outro programa" /tmp/gate_inst_9j.log; then
        ok "S9j dry-run sem sudo com o serviço instalado na porta (prefixo longo) → reconhecido, sem acusar cópia nem programa alheio"
    else
        erro "S9j dry-run com o serviço instalado na porta: rc=$RC9J — cauda:"; tail -4 /tmp/gate_inst_9j.log
    fi
fi
kill "$MANUAL2_PID" 2>/dev/null; wait "$MANUAL2_PID" 2>/dev/null

# S9h — o ONE-LINER inteiro, com launchd real (gui) e a verificação REAL, nos
# três desfechos: (1) instala → "serviço v… no ar" e rc 0; (2) reexecução → 100
# ("Nada a fazer"); (3) programa alheio na porta → rc 3, frase humana, e o bloco
# final "Feito até aqui / Faltou / O que fazer agora" sem "(exit" na tela.
# Porta 35994 pré-gravada no bridge.env do prefixo; RUB_SUDO vazio (sem root).
H9="$(mktemp -d)"; mkdir -p "$H9/bin" "$H9/prefix/etc" "$H9/ld" "$H9/state" "$H9/cache"; cp "$INST/bin/brew" "$H9/bin/brew"
sed 's/^UI_API_PORT=.*/UI_API_PORT=35994/' "$RAIZ/config/river-unifi-bridge.env.example" > "$H9/prefix/etc/bridge.env"; chmod 600 "$H9/prefix/etc/bridge.env"
H9_ENV="PATH=$H9/bin:/usr/bin:/bin:/usr/sbin:/sbin RUB_SUDO= RUB_BREW=$H9/bin/brew RUB_PREFIX=$H9/prefix RUB_LAUNCHD_DIR=$H9/ld RUB_LAUNCHD_DOMAIN=gui/$(id -u) RUB_STATE_DIR=$H9/state RUB_CACHE_DIR=$H9/cache RUB_LOG_FILE=$H9/daemon.log RUB_PYTHON=$RAIZ/.venv/bin/python NO_COLOR=1 LANG=pt_BR.UTF-8"
launchctl bootout "$G9_ALVO" 2>/dev/null || true
env $H9_ENV /bin/bash "$RAIZ/river-bridge-install.sh" --src "$RAIZ" --no-app --no-anim --yes >"$H9/r1.log" 2>&1; RH1=$?
env $H9_ENV /bin/bash "$RAIZ/river-bridge-install.sh" --src "$RAIZ" --no-app --no-anim --yes >"$H9/r2.log" 2>&1; RH2=$?
launchctl bootout "$G9_ALVO" 2>/dev/null || true; sleep 1
python3 -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1",35994)); s.listen(1); time.sleep(90)' &
H9_ALHEIO=$!; esperar_ouvinte 35994 || erro "S9h o ouvinte de mentira não abriu a porta 35994 em 10 s"
env $H9_ENV /bin/bash "$RAIZ/river-bridge-install.sh" --src "$RAIZ" --no-app --no-anim --yes >"$H9/r3.log" 2>&1; RH3=$?
kill "$H9_ALHEIO" 2>/dev/null; wait "$H9_ALHEIO" 2>/dev/null
launchctl bootout "$G9_ALVO" 2>/dev/null || true
if [ "$RH1" = "0" ] && grep -q "serviço v[0-9.]* no ar" "$H9/r1.log" && [ "$RH2" = "100" ] && grep -q "Nada a fazer" "$H9/r2.log" \
   && [ "$RH3" = "3" ] && grep -q "já está em uso por outro programa (python" "$H9/r3.log" && grep -q "O que fazer agora:" "$H9/r3.log" \
   && grep -q "Feito até aqui:" "$H9/r3.log" && ! grep -q "(exit" "$H9/r3.log" && ! grep -E "^│.*PID [0-9]" "$H9/r3.log" >/dev/null; then
    ok "S9h one-liner com launchd e verificação reais: instala (0) · reexecuta (100) · programa alheio (3) com o status humano"
else
    erro "S9h one-liner real: rc1=$RH1 rc2=$RH2 rc3=$RH3 — caudas:"; tail -4 "$H9/r1.log"; tail -3 "$H9/r3.log"
fi

# S9i — falha de MUTAÇÃO com frase humana (revisão fria B3, 2026-09-03): um
# `brew install` que falha (rede, Homebrew quebrado) tem de sair 1 com a linha
# `✖` para a pessoa e o motivo no registro — não morrer mudo pelo set -e.
I9="$(mktemp -d)"; mkdir -p "$I9/bin" "$I9/prefix" "$I9/ld" "$I9/state"
printf '#!/bin/bash\ncase "$1" in list) exit 1;; install) echo "Error: rede" >&2; exit 1;; --prefix) echo "%s/brewprefix";; esac; exit 0\n' "$I9" > "$I9/bin/brew"; chmod +x "$I9/bin/brew"
cp "$INST/bin/launchctl" "$I9/bin/launchctl" 2>/dev/null || true
env PATH="$I9/bin:/usr/bin:/bin" RUB_BREW="$I9/bin/brew" RUB_PREFIX="$I9/prefix" RUB_LAUNCHD_DIR="$I9/ld" RUB_SERVICE_USER="$(id -un)" RUB_STATE_DIR="$I9/state" RUB_SKIP_HEALTH=1 \
  "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9i.log 2>&1; RC9I=$?
if [ "$RC9I" = "1" ] && grep -q "^✖ o Homebrew não conseguiu instalar nut" /tmp/gate_inst_9i.log && grep -q "^#  brew install nut falhou" /tmp/gate_inst_9i.log && [ ! -d "$I9/prefix/src" ]; then
    ok "S9i brew install falhando → código 1, frase humana, motivo no registro, nada instalado depois"
else
    erro "S9i brew install falhando: rc=$RC9I — cauda:"; tail -3 /tmp/gate_inst_9i.log
fi

# S10 — uninstall (a CÓPIA INSTALADA, o caminho do README) remove o criado,
# inclusive a si mesmo e o scripts/, e PRESERVA arquivo alheio.
echo alheio > "$INST/prefix/arquivo-do-dono.txt"
env $INSTALL_ENV "$INST/prefix/scripts/uninstall.sh" --confirm >/tmp/gate_inst_un.log 2>&1
if [ -f "$INST/prefix/arquivo-do-dono.txt" ] \
   && [ ! -d "$INST/prefix/src" ] && [ ! -d "$INST/prefix/venv" ] \
   && [ ! -e "$INST/prefix/scripts" ] \
   && [ ! -f "$INST/ld/com.river.unifi-bridge.plist" ] \
   && [ ! -f "$INST/ld/.carregado" ]; then
    ok "S10 uninstall (cópia instalada): só o nosso saiu, scripts/ inclusive; o alheio ficou"
else
    erro "S10 uninstall — estado final inesperado:"; find "$INST/prefix" "$INST/ld" 2>/dev/null | head -8
fi
rm -rf "$INST"

# ── S11..S15 — o instalador em uma linha (river-bridge-install.sh) ──────────
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
# S17 — reexecução (rc 100) num PTY COM animação: o passo não pode aparecer como
# falha. 100 é sucesso no contrato da casa, mas ui_spin rotulava todo rc != 0 como
# erro, e a tela mostrava "✖ … (exit 100)" seguido de "serviço já estava atual" —
# dois rótulos em desacordo, com o errado em vermelho (visto no Mac mini em
# 2026-09-01). Precisa de pty E de animação: com --no-anim (como em S9 e S12)
# ui_spin devolve antes de rotular, e a cena não tocaria o defeito.
if [ -d "$OL/state" ]; then
    if OL_ENV_PTY="$OL_ENV" ONE_PTY="$ONE" RAIZ_PTY="$RAIZ" "$PY" - <<'EOF'
import os, pty, re, sys, fcntl, termios, struct
env = dict(p.split("=", 1) for p in os.environ["OL_ENV_PTY"].split() if "=" in p)
env.pop("NO_COLOR", None)                      # NO_COLOR desligaria a animação
# Lidos ANTES do clear: depois dele o os.environ não tem mais nada, e o execv
# receberia caminho vazio (rc 127 em vez do 100 que a cena espera).
script, raiz = os.environ["ONE_PTY"], os.environ["RAIZ_PTY"]
lar = os.environ.get("HOME", "/tmp")
pid, fd = pty.fork()
if pid == 0:
    base = {"TERM": "xterm-256color", "COLORTERM": "truecolor", "LC_ALL": "en_US.UTF-8",
            "LANG": "en_US.UTF-8", "HOME": lar}
    base.update(env)
    os.environ.clear(); os.environ.update(base)
    os.execv("/bin/bash", ["/bin/bash", script, "--yes", "--no-app", "--src", raiz])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 100, 0, 0))
out = b""
while True:
    try:
        chunk = os.read(fd, 65536)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
_, st = os.waitpid(pid, 0)
texto = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", out).decode("utf-8", "replace")
rc = os.waitstatus_to_exitcode(st)
assert rc == 100, f"reexecução devia sair 100, saiu {rc}"
assert "(exit 100)" not in texto, "o passo mostrou \"(exit 100)\" na tela"
assert "✖" not in texto, "o passo apareceu com ✖ numa reexecução bem-sucedida"
EOF
    then
        ok "S17 reexecução num pty com animação: rc 100 sem ✖ e sem \"(exit 100)\" na tela"
    else
        erro "S17 reexecução num pty: o passo de sucesso apareceu como falha"
    fi
else
    erro "S17 reexecução num pty: o ambiente de stubs da S12 não existe"
fi

# S20 — spinner num terminal ESTREITO (40 colunas), com animação: cada quadro do
# spinner tem de caber na largura, senão a linha quebra e o \r deixa rastro
# ("│ ⠋ sudo scripts/install.sh…│ ⠙ sudo…", visto no Terminal do Mac mini em
# 2026-09-02, janela menor que o rótulo). A S17 roda em 100 colunas e era cega a isso.
# O pty não quebra bytes — a asserção é sobre o comprimento de cada quadro.
# Refutado em 2026-09-02 removendo o corte do rótulo em ui_spin.
if [ -d "$OL/state" ]; then
    if OL_ENV_PTY="$OL_ENV" ONE_PTY="$ONE" RAIZ_PTY="$RAIZ" "$PY" - <<'EOF'
import os, pty, re, sys, fcntl, termios, struct
env = dict(p.split("=", 1) for p in os.environ["OL_ENV_PTY"].split() if "=" in p)
env.pop("NO_COLOR", None)
script, raiz = os.environ["ONE_PTY"], os.environ["RAIZ_PTY"]
lar = os.environ.get("HOME", "/tmp")
COLS = 40
pid, fd = pty.fork()
if pid == 0:
    base = {"TERM": "xterm-256color", "COLORTERM": "truecolor", "LC_ALL": "en_US.UTF-8",
            "LANG": "en_US.UTF-8", "HOME": lar}
    base.update(env)
    os.environ.clear(); os.environ.update(base)
    os.execv("/bin/bash", ["/bin/bash", script, "--yes", "--no-app", "--src", raiz])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, COLS, 0, 0))
out = b""
while True:
    try:
        chunk = os.read(fd, 65536)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
_, st = os.waitpid(pid, 0)
texto = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", out).decode("utf-8", "replace")
rc = os.waitstatus_to_exitcode(st)
assert rc == 100, f"reexecução devia sair 100, saiu {rc}"
quadros = [q for q in re.split(r"[\r\n]", texto) if re.match(r"│ [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ", q)]
assert quadros, "nenhum quadro de spinner capturado"
longo = max(quadros, key=len)
assert len(longo) <= COLS, f"quadro do spinner com {len(longo)} colunas em terminal de {COLS}: {longo!r}"
EOF
    then
        ok "S20 spinner em terminal de 40 colunas: todo quadro cabe na largura (sem rastro)"
    else
        erro "S20 spinner em terminal estreito: um quadro ultrapassou a largura (rastro na tela)"
    fi
else
    erro "S20 spinner em terminal estreito: o ambiente de stubs da S12 não existe"
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

# S18 — canal release por file:// (stubs, sem root, sem rede). Cinco rodadas:
#   r1 instala o app PRONTO do zip da release (sha conferido) e registra fonte=release;
#   r2 reexecuta em 100; r3 sha do zip adulterado → rc 3 e nenhum app instalado;
#   r4 release inexistente → aviso e fallback para o tarball de main (fonte=main);
#   r5 sha do tarball adulterado → rc 3 e nenhum cache/src-* extraído.
# Refutado em 2026-09-02 com cinco mutações (uma por rodada), ver o doc da release.
OL3="$(mktemp -d)"
mkdir -p "$OL3/bin" "$OL3/rel" "$OL3/rel-app-ruim" "$OL3/rel-src-ruim" "$OL3/vazio" "$OL3/fake/River Bridge.app/Contents/MacOS"
cat > "$OL3/bin/brew" <<EOF
#!/bin/bash
case "\$1" in list) exit 0 ;; --prefix) echo "$OL3/brewprefix" ;; esac
exit 0
EOF
cat > "$OL3/bin/launchctl" <<'EOF'
#!/bin/bash
case "$1" in
  print) [ -f "$RUB_LAUNCHD_DIR/.carregado" ] && exit 0 || exit 1 ;;
  bootstrap) touch "$RUB_LAUNCHD_DIR/.carregado"; exit 0 ;;
  bootout) rm -f "$RUB_LAUNCHD_DIR/.carregado"; exit 0 ;;
  kickstart) exit 0 ;;
esac
exit 0
EOF
chmod +x "$OL3/bin/brew" "$OL3/bin/launchctl"
printf '#!/bin/sh\nexit 0\n' > "$OL3/fake/River Bridge.app/Contents/MacOS/RiverBridge"
chmod +x "$OL3/fake/River Bridge.app/Contents/MacOS/RiverBridge"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleExecutable</key><string>RiverBridge</string></dict></plist>\n' > "$OL3/fake/River Bridge.app/Contents/Info.plist"
(cd "$OL3/fake" && ditto -c -k --keepParent "River Bridge.app" "$OL3/rel/River-Bridge.app.zip")
(cd "$RAIZ" && tar -czf "$OL3/rel/river-unifi-bridge-src.tar.gz" --exclude .git --exclude .venv --exclude .build --exclude __pycache__ --exclude 'macos/RiverBridge/dist' --exclude dist -s '|^\./|river-unifi-bridge-vtest/|' . 2>/dev/null)
(cd "$OL3/rel" && shasum -a 256 River-Bridge.app.zip river-unifi-bridge-src.tar.gz > SHA256SUMS)
cp "$OL3/rel/"* "$OL3/rel-app-ruim/"; cp "$OL3/rel/"* "$OL3/rel-src-ruim/"
S18_ZERO="0000000000000000000000000000000000000000000000000000000000000000"
sed -i '' "/River-Bridge.app.zip\$/s/^[0-9a-f]*/$S18_ZERO/" "$OL3/rel-app-ruim/SHA256SUMS"
sed -i '' "/river-unifi-bridge-src.tar.gz\$/s/^[0-9a-f]*/$S18_ZERO/" "$OL3/rel-src-ruim/SHA256SUMS"
s18_env() { # <rodada> — prefixo, launchd, estado, cache e apps novos por rodada
    mkdir -p "$OL3/$1/ld" "$OL3/$1/prefix" "$OL3/$1/state" "$OL3/$1/cache" "$OL3/$1/apps"
    printf 'PATH=%s/bin:/usr/bin:/bin RUB_BREW=%s/bin/brew RUB_PREFIX=%s/%s/prefix RUB_LAUNCHD_DIR=%s/%s/ld RUB_SERVICE_USER=%s RUB_PYTHON=%s RUB_SUDO= RUB_STATE_DIR=%s/%s/state RUB_CACHE_DIR=%s/%s/cache RUB_APP_DEST=%s/%s/apps/app RUB_SKIP_HEALTH=1 NO_COLOR=1' \
        "$OL3" "$OL3" "$OL3" "$1" "$OL3" "$1" "$(id -un)" "$PY" "$OL3" "$1" "$OL3" "$1" "$OL3" "$1"
}
S18_E="$(s18_env a)"
env $S18_E RUB_RELEASE_BASE="file://$OL3/rel" "$ONE" --yes --no-anim >"$OL3/r1.log" 2>&1; S18_RC1=$?
env $S18_E RUB_RELEASE_BASE="file://$OL3/rel" "$ONE" --yes --no-anim >"$OL3/r2.log" 2>&1; S18_RC2=$?
S18_E="$(s18_env b)"
env $S18_E RUB_RELEASE_BASE="file://$OL3/rel-app-ruim" "$ONE" --yes --no-anim >"$OL3/r3.log" 2>&1; S18_RC3=$?
S18_E="$(s18_env c)"
env $S18_E RUB_CANAL=release RUB_RELEASE_BASE="file://$OL3/vazio" RUB_SRC_URL="file://$OL3/rel/river-unifi-bridge-src.tar.gz" "$ONE" --yes --no-anim --no-app >"$OL3/r4.log" 2>&1; S18_RC4=$?
S18_E="$(s18_env d)"
env $S18_E RUB_RELEASE_BASE="file://$OL3/rel-src-ruim" "$ONE" --yes --no-anim --no-app >"$OL3/r5.log" 2>&1; S18_RC5=$?
S18_DET=""
[ "$S18_RC1" = "0" ] && cmp -s "$OL3/a/apps/app/Contents/MacOS/RiverBridge" "$OL3/fake/River Bridge.app/Contents/MacOS/RiverBridge" \
    && grep -q "^fonte=release vtest$" "$OL3/a/state/installer-last-run.log" || S18_DET="$S18_DET r1(rc=$S18_RC1)"
[ "$S18_RC2" = "100" ] || S18_DET="$S18_DET r2(rc=$S18_RC2)"
[ "$S18_RC3" = "3" ] && [ ! -e "$OL3/b/apps/app" ] || S18_DET="$S18_DET r3(rc=$S18_RC3)"
[ "$S18_RC4" = "0" ] && grep -qE "release indisponível|release unavailable" "$OL3/r4.log" \
    && [ -x "$OL3"/c/cache/src-*/scripts/install.sh ] && grep -q "^fonte=main" "$OL3/c/state/installer-last-run.log" || S18_DET="$S18_DET r4(rc=$S18_RC4)"
[ "$S18_RC5" = "3" ] && [ -z "$(ls -d "$OL3"/d/cache/src-* 2>/dev/null)" ] || S18_DET="$S18_DET r5(rc=$S18_RC5)"
if [ -z "$S18_DET" ]; then
    ok "S18 one-liner canal release: app pronto do zip (sha) → 100 → sha do zip ruim rc 3 sem app → fallback main com aviso → sha do tarball ruim rc 3 sem extração"
else
    erro "S18 one-liner canal release — rodadas com defeito:$S18_DET — caudas:"
    tail -4 "$OL3"/r?.log 2>/dev/null
fi
rm -rf "$OL3"

# S19 — tools/release.sh --check: a tag amarra as 6 declarações de versão + CHANGELOG.
# Na árvore: rc 0. Numa cópia com pyproject.toml em 9.9.9, conferida contra a
# versão de scripts/install.sh: rc 3 E a saída cita pyproject.toml (não "qualquer rc≠0").
# Refutado em 2026-09-02 removendo a linha do pyproject da lista do --check → mutante rc 0.
REL="$(mktemp -d)"
mkdir -p "$REL/src/river_unifi_bridge"
cp "$RAIZ/pyproject.toml" "$RAIZ/CHANGELOG.md" "$RAIZ/river-bridge-install.sh" "$REL/"
cp "$RAIZ/src/river_unifi_bridge/__init__.py" "$REL/src/river_unifi_bridge/"
cp -R "$RAIZ/scripts" "$RAIZ/tools" "$REL/"
sed -i '' 's/^version = ".*"$/version = "9.9.9"/' "$REL/pyproject.toml"
REL_V="$(sed -n 's/^VERSAO="\(.*\)"$/\1/p' "$RAIZ/scripts/install.sh")"
"$RAIZ/tools/release.sh" --check >"$REL/limpo.log" 2>&1; REL_RC0=$?
"$REL/tools/release.sh" --check "v$REL_V" >"$REL/mutante.log" 2>&1; REL_RC1=$?
if [ "$REL_RC0" = "0" ] && [ "$REL_RC1" = "3" ] && grep -q "pyproject.toml não declara" "$REL/mutante.log"; then
    ok "S19 release --check: rc 0 na árvore (v$REL_V); rc 3 citando pyproject.toml no mutante 9.9.9"
else
    erro "S19 release --check: limpo rc=$REL_RC0 (esperado 0), mutante rc=$REL_RC1 (esperado 3) — caudas:"
    tail -3 "$REL/limpo.log" "$REL/mutante.log"
fi
rm -rf "$REL"

# S21 — a tela do app não fala em chave, arquivo nem código. Duas buscas, as duas
# exigindo ZERO, sobre macos/RiverBridge/Sources:
#   (a) os quatro termos que são jargão puro e não têm razão de existir no app;
#   (b) frase de tela escrita fora do tradutor (o app é bilíngue: texto solto
#       aparece em português para quem escolheu inglês).
# A própria cena é refutada a cada rodada: numa CÓPIA com o jargão replantado, as
# mesmas buscas têm de acusar — busca que nunca acusaria não é cerca.
JARG_DIR="$RAIZ/macos/RiverBridge/Sources"
JARG_TERMOS="UDR7_ARM_ALLOWED|known_hosts|upsc device.serial|(202)"
conta_jargao() {   # 1 = diretório a varrer; imprime o total das duas buscas
    local dir="$1" total=0 termo antigo_ifs="$IFS"
    IFS='|'
    for termo in $JARG_TERMOS; do
        total=$((total + $(/usr/bin/grep -rF -o -- "$termo" "$dir" 2>/dev/null | wc -l)))
    done
    IFS="$antigo_ifs"
    total=$((total + $(/usr/bin/grep -rnE '\.serviceDown\("' "$dir" 2>/dev/null | wc -l)))
    printf '%s' "$total"
}
JARG_LIMPO="$(conta_jargao "$JARG_DIR")"
JARG_M="$(mktemp -d)"
cp -R "$JARG_DIR" "$JARG_M/Sources"
cat > "$JARG_M/Sources/JargaoPlantado.swift" <<'EOF'
// Arquivo do mutante da cena S21 — nunca existe na árvore.
enum JargaoPlantado {
    static let trava = "Trava UDR7_ARM_ALLOWED=1 no arquivo do serviço"
    static let host = "console fora do known_hosts"
    static let serial = "Número de série (upsc device.serial)"
    static let reinicio = "Reinício agendado (202)."
    static func cai(_ store: Qualquer) { store.phase = .serviceDown("Sem comunicação") }
}
EOF
JARG_MUT="$(conta_jargao "$JARG_M/Sources")"
if [ "$JARG_LIMPO" = "0" ] && [ "$JARG_MUT" -ge 5 ]; then
    ok "S21 tela sem jargão: 0 ocorrência na árvore; $JARG_MUT no mutante com o jargão replantado"
else
    erro "S21 tela sem jargão: árvore=$JARG_LIMPO (esperado 0), mutante=$JARG_MUT (esperado >= 5) — ocorrências:"
    /usr/bin/grep -rnE 'UDR7_ARM_ALLOWED|known_hosts|upsc device\.serial|\(202\)|\.serviceDown\("' "$JARG_DIR" | head -10
fi
rm -rf "$JARG_M"

# S14 — abertura num pty de 80 colunas: asserção estrutural (o quadro bate com a
# LG_MASK do próprio script, bordas incluídas) + snapshot do quadro final.
# Só num pty a camada visual vê TTY; sem ele degrada para texto e o snapshot não diria nada.
SNAP_DIR="$RAIZ/tests/snapshots"; mkdir -p "$SNAP_DIR"
SNAP_OUT="$(mktemp)"
if ! "$PY" - "$ONE" > "$SNAP_OUT" <<'EOF'
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

# Cerca estrutural (P0, 2026-09-01). Duas asserções, e cada uma prova uma coisa:
#  (1) BORDAS da máscara vazias — o caso extremo: desenho colado na borda, sem
#      vizinho de fora, e halo e traço somem naquele lado. Não olha o pty. Cerca
#      ESTREITA por natureza: o flood fill classifica a linha anti-aliased como '.',
#      então a borda fica vazia mesmo com margem zero. Quem garante a margem
#      publicada é a S15 (o bloco tem de ser a saída do gerador com os defaults) e,
#      dentro do gerador, conferir(), que exige folga >= margem nos quatro lados.
#  (2) render × máscara — prova que lg_render/lg_cel respeitam a máscara (pega
#      regressão do runtime: recuo, substituição de classe). NÃO prova o conteúdo da
#      máscara: o quadro final é derivado dela, então os dois lados mudam juntos.
# Que o fragmento GERADO ainda venha do gerador é a cena S15, abaixo.
src = open(script, encoding="utf-8").read()
W = int(re.search(r"^LG_W=(\d+)$", src, re.M)[1])
H = int(re.search(r"^LG_H=(\d+)$", src, re.M)[1])
bloco = src[src.index("LG_MASK=("):]
bloco = bloco[:bloco.index("\n)\n")]
mask = re.findall(r"^'([.srb]+)'$", bloco, re.M)   # b = auréola do fundo do ícone
assert len(mask) == H and all(len(l) == W for l in mask), "LG_MASK não é LG_W x LG_H"
assert set(mask[0]) == {"."} and set(mask[-1]) == {"."}, "borda horizontal da máscara não é vazia"
assert all(l[0] == "." and l[-1] == "." for l in mask), "borda vertical da máscara não é vazia"
linhas = text.split("\n")[:H // 2]          # as H/2 linhas do logo, ANTES do rstrip final
assert len(linhas) == H // 2, f"logo com {len(linhas)} linhas, esperado {H // 2}"
for cy, linha in enumerate(linhas):
    celulas = linha[2:2 + W].ljust(W)        # lg_render imprime 2 espaços de recuo
    for x in range(W):
        esperado = mask[2 * cy][x] != "." or mask[2 * cy + 1][x] != "."
        assert (celulas[x] != " ") == esperado, f"célula ({cy},{x}) não bate com a máscara"

print("\n".join(l.rstrip() for l in text.splitlines()).rstrip())
EOF
then
    erro "S14 abertura: asserção estrutural (máscara × pty) reprovou"
elif [ "${GATE_UPDATE:-0}" = "1" ] || [ ! -f "$SNAP_DIR/abertura-80-utf8.txt" ]; then
    cp "$SNAP_OUT" "$SNAP_DIR/abertura-80-utf8.txt"
    ok "S14 abertura: snapshot (re)gravado em tests/snapshots/abertura-80-utf8.txt"
elif diff -q "$SNAP_OUT" "$SNAP_DIR/abertura-80-utf8.txt" >/dev/null; then
    ok "S14 abertura: quadro final idêntico ao snapshot (pty 80 col)"
else
    erro "S14 abertura: quadro final divergiu do snapshot (GATE_UPDATE=1 regrava se a mudança for intencional)"
    diff "$SNAP_OUT" "$SNAP_DIR/abertura-80-utf8.txt" | head -6
fi
rm -f "$SNAP_OUT"

# S15 — o bloco GERADO no instalador é byte a byte o que tools/gera-logo.py produz.
# Sem isto, uma LG_MASK editada à mão passaria por todas as outras cenas (o quadro
# final é derivado da própria máscara — ver S14).
FRAG_OUT="$(mktemp)"; FRAG_NO_SCRIPT="$(mktemp)"
if "$RAIZ/tools/gera-logo.py" > "$FRAG_OUT" 2>/dev/null; then
    "$PY" - "$ONE" > "$FRAG_NO_SCRIPT" <<'EOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
ini = src.index("# ── GERADO por tools/gera-logo.py")
fim = src.index("\n", src.index("\nLG_HY=(") + 1) + 1
sys.stdout.write(src[ini:fim])
EOF
    if diff -q "$FRAG_OUT" "$FRAG_NO_SCRIPT" >/dev/null; then
        ok "S15 logo: o bloco GERADO é idêntico à saída de tools/gera-logo.py"
    else
        erro "S15 logo: o bloco GERADO divergiu do gerador (editado à mão? regere e cole)"
        diff "$FRAG_OUT" "$FRAG_NO_SCRIPT" | head -6
    fi
else
    erro "S15 logo: tools/gera-logo.py falhou (asserções do gerador?)"
fi
rm -f "$FRAG_OUT" "$FRAG_NO_SCRIPT"

# S16 — a abertura num terminal de 256 CORES (sem COLORTERM), que é o Terminal.app
# de fábrica. S14 sempre roda com COLORTERM=truecolor e por isso nunca tocou o ramo
# de 256 cores de lg_init — onde um `printf -v LG_FGA[y]` (recusado pelo bash 3.2 do
# macOS com "not a valid identifier") deixava o gradiente inteiro vazio: o escudo
# saía SEM COR NENHUMA e com uma linha de erro na tela do usuário.
if "$PY" - "$ONE" <<'EOF'
import os, pty, sys, fcntl, termios, struct
script = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ.clear()
    os.environ.update({"TERM": "xterm-256color", "LC_ALL": "en_US.UTF-8", "LANG": "en_US.UTF-8",
                       "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/tmp", "UI_NO_ANIM": "1"})
    os.execv("/bin/bash", ["/bin/bash", script, "--demo-frame", "-1"])   # bash 3.2 de propósito
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
texto = out.decode("utf-8", "replace")
assert "not a valid identifier" not in texto, "bash 3.2 recusou um alvo de printf -v"
assert "\x1b[38;5;" in texto, "nenhuma cor de 256 no quadro: o gradiente saiu vazio"
EOF
then
    ok "S16 abertura em 256 cores (bash 3.2, sem COLORTERM): com cor e sem erro"
else
    erro "S16 abertura em 256 cores: saiu sem cor ou com erro do bash 3.2"
fi

if [ "$FALHAS" -eq 0 ]; then
    printf 'GATE: VERDE\n'
    exit 0
fi
printf 'GATE: VERMELHO (%d falhas)\n' "$FALHAS"
exit 1
