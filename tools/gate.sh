#!/bin/bash
# gate.sh — portão de qualidade (Fase 2 + Fase 3'-EXP; bash 3.2 compat; saída [OK]/[ERRO]).
# Cenas: sintaxe, unit, integração, mutação de cerca (a cerca TEM de reprovar
# quando o defeito é plantado — convenção da casa).
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PY="${GATE_PYTHON:-$RAIZ/.venv/bin/python}"
FALHAS=0

ok()   { printf '[OK]   %s\n' "$1"; }
# Impressão da configuração REAL do NUT desta máquina, antes de qualquer cena. O
# gate escreve em prefixos de mentira; se algum ambiente esquecer o seam, ele
# escreve AQUI — e a cena S22, no fim, acusa.
NUT_REAL_ETC="${RUB_NUT_ETC_REAL:-/opt/homebrew/etc/nut}"
# O diretório de estado REAL do dono. O instalador escreve a ficha da conta do
# aparelho aqui; uma cena sem RUB_STATE_DIR a escreveria na máquina de quem roda
# o portão (a cena S23, no fim, acusa).
ESTADO_REAL="${RUB_STATE_DIR_REAL:-$HOME/Library/Application Support/river-unifi-bridge}"
impressao_estado_real() {
  { ls -1 "$ESTADO_REAL" 2>/dev/null | sort
    find "$ESTADO_REAL" -maxdepth 1 -type f 2>/dev/null | sort | while read -r arq; do
      printf '%s  %s\n' "$(shasum -a 256 <"$arq" 2>/dev/null | cut -d' ' -f1)" "${arq##*/}"
    done
  } | shasum -a 256 | cut -d" " -f1
}
# Nomes E CONTEÚDO: a versão anterior só via a lista de arquivos, então uma cena
# que reescrevesse `ups.conf` do dono passava batida (revisão fria da 0.5.0).
# Arquivo ilegível entra com impressão vazia — estável entre as duas medições.
impressao_nut_real() {
  { ls -1 "$NUT_REAL_ETC" 2>/dev/null | sort
    find "$NUT_REAL_ETC" -maxdepth 1 -type f 2>/dev/null | sort | while read -r arq; do
      printf '%s  %s\n' "$(shasum -a 256 <"$arq" 2>/dev/null | cut -d' ' -f1)" "${arq##*/}"
    done
  } | shasum -a 256 | cut -d" " -f1
}
# E o diretório onde vivem os SOQUETES dos drivers do NUT. A ponte passou a
# publicar aparelhos ali (0.7.0); uma cena sem o seam RUB_NUT_STATE deixaria na
# instalação real de quem roda o portão um aparelho fantasma que o servidor do
# dono passaria a servir.
NUT_REAL_STATE="${RUB_NUT_STATE_REAL:-/opt/homebrew/var/state/ups}"
impressao_nut_state() { ls -1 "$NUT_REAL_STATE" 2>/dev/null | sort | shasum -a 256 | cut -d" " -f1; }
NUT_REAL_ANTES="$(impressao_nut_real)"
ESTADO_REAL_ANTES="$(impressao_estado_real)"
NUT_STATE_ANTES="$(impressao_nut_state)"
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
# S65 — o leitor do NUT nasce com o nome de fábrica, direto (0.8.2). Mutante:
# volta a lançá-lo por `exec -a river-bridge-ups` (o NUT 2.8.5 recusa: "UPS
# [river-office] is for driver 'usbhid-ups', but I'm 'river-bridge-ups'!",
# medido no Mac mini em 2026-09-05) → o teste TEM de reprovar.
cena_mutacao S65 src/river_unifi_bridge/nut_supervisor.py \
    '[f"{self._prefixo}/bin/usbhid-ups",' \
    '["/bin/sh", "-c", "exec -a river-bridge-ups " + f"{self._prefixo}/bin/usbhid-ups",' \
    tests/unit/test_nut_supervisor.py::test_o_leitor_nasce_com_o_nome_de_fabrica_e_direto
# S65b — a saída de erro dos filhos vai para o diário. Mutante: de volta ao nada.
cena_mutacao S65b src/river_unifi_bridge/nut_supervisor.py \
    'stdout=subprocess.DEVNULL, stderr=None,' 'stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,' \
    tests/unit/test_nut_supervisor.py::test_a_saida_de_erro_dos_filhos_vai_para_o_diario
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
    'self.state.clear_events(ts_to, ts_from=ts_from)' \
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

# S4ai — com o UPS mudo, a tela tem de mostrar o estado NOVO do dispositivo. Sem
# a republicação no caminho de falha, ela congela no estado anterior à queda.
cena_mutacao S4ai src/river_unifi_bridge/service.py \
    'shared.set_plugins(plugin_statuses(plugins))  # mantém na falha' \
    'pass  # mantém na falha' \
    tests/unit/test_service_loop.py::test_health_refreshes_the_device_state_when_the_ups_goes_quiet

# S4aj — DESARMAR NUNCA É RECUSADO, nem com o disco cheio: é o botão de parada do
# dono, e disco cheio é exatamente quando ele o aperta.
# Duas âncoras, dois caminhos de escrita: o arquivo do serviço e a loja de
# dispositivos. O segundo só apareceu na 2.ª rodada da revisão — o desarme
# passava pelo primeiro e morria no outro, com 500 cru na tela.
cena_mutacao S4aj src/river_unifi_bridge/api.py \
    'if not _e_desarme_puro(parsed):
                # Nada foi aplicado ainda' \
    'if True:
                # Nada foi aplicado ainda' \
    tests/unit/test_api.py::test_disarming_is_never_refused_by_a_full_disk

cena_mutacao S4ak src/river_unifi_bridge/api.py \
    'if not _e_desarme_puro(parsed):
                    return self._refuse(500, "arquivo_dispositivos"' \
    'if True:
                    return self._refuse(500, "arquivo_dispositivos"' \
    tests/unit/test_api.py::test_disarming_is_never_refused_by_a_full_disk_with_the_real_wiring

# S4al — desligar o próprio River corta a energia de TUDO o que está nele. A
# trava mora no arquivo do serviço e a API nunca a abre; sem ela, o botão do app
# desligaria o aparelho do dono com um toque.
cena_mutacao S4al src/river_unifi_bridge/api.py \
    'if not self.cfg.river_poweroff_allowed:' \
    'if False:' \
    tests/unit/test_api.py::test_turning_the_river_off_needs_the_file_lock_open

# S4am — emprestar o cabo com proteção armada é ficar cego para a queda: o
# serviço deixaria de ver a bateria acabar justamente com a proteção ligada.
cena_mutacao S4am src/river_unifi_bridge/api.py \
    'if any(plugin.armed for plugin in self.plugins):
                # Motivo PRÓPRIO' \
    'if False:
                # Motivo PRÓPRIO' \
    tests/unit/test_api.py::test_lending_the_cable_is_refused_while_a_protection_is_armed

# S4an — gravação no aparelho que não volta na leitura seguinte NÃO aconteceu: o
# River responde OK e ignora, e a tela mostraria um valor que o aparelho não tem.
cena_mutacao S4an src/river_unifi_bridge/river_cmd.py \
    'if de_volta.strip() != valor.strip():' \
    'if False:' \
    tests/unit/test_river_cmd.py::test_a_write_the_device_silently_ignores_is_reported

# S4ao — pausado é pausado: o vigia não pode ressuscitar o leitor que o dono
# liberou, senão o cabo é tomado de volta do aplicativo da EcoFlow sozinho.
cena_mutacao S4ao src/river_unifi_bridge/nut_supervisor.py \
    'if self._pausado:
                return
            caiu = False' \
    'if False:
                return
            caiu = False' \
    tests/unit/test_nut_supervisor.py::test_pausing_frees_the_cable_and_does_not_resurrect

# S4ap — gravação que não pode ser CONFERIDA falha fechada. O leitor pode cair
# entre a escrita e a leitura de volta; sem isto a tela dizia "salvo" com valor
# nenhum no aparelho.
cena_mutacao S4ap src/river_unifi_bridge/river_cmd.py \
    'if de_volta is None:' \
    'if False:' \
    tests/unit/test_river_cmd.py::test_a_write_that_cannot_be_confirmed_fails_closed

# S4aq — leitor que não sobe (cabo solto) não pode virar tempestade de processos.
# Medido na máquina do dono antes do recuo: 173 processos em 5min44s.
cena_mutacao S4aq src/river_unifi_bridge/nut_supervisor.py \
    'if self._clock() < self._proxima_tentativa:' \
    'if False:' \
    tests/unit/test_nut_supervisor.py::test_a_reader_that_never_comes_up_does_not_become_a_process_storm

# S4ar — serviço que sai leva o leitor junto. Sem isto, o launchd manda SIGTERM
# ao atualizar, o pai morre, e os dois processos do NUT ficam órfãos COM O CABO:
# o serviço seguinte não consegue abrir o aparelho.
cena_mutacao S4ar src/river_unifi_bridge/service.py \
    '        if supervisor is not None:
            supervisor.encerrar()' \
    '        if False:
            supervisor.encerrar()' \
    tests/unit/test_service_loop.py::test_the_reader_is_taken_along_when_the_service_stops

# S4as — armar com o cabo emprestado ao aplicativo da EcoFlow é armar às cegas: a
# última leitura ainda parece boa por alguns segundos depois do empréstimo.
cena_mutacao S4as src/river_unifi_bridge/api.py \
    'if not self.supervisor.estado().pausado_pelo_dono:' \
    'if True:' \
    tests/unit/test_api.py::test_arming_is_refused_while_the_cable_is_lent

# S4at — o serviço leva o leitor junto TAMBÉM quando ele para antes do laço
# (porta ocupada, histórico que não abre). Sem isto, os dois processos do
# no-break ficavam vivos, sem pai, com o cabo.
# O mutante NÃO pode ser a remoção da parada deliberada: sem ela o laço roda para
# sempre e o portão trava (aconteceu, 29 min). O defeito plantado é o `finally`
# deixar de valer para a saída normal — que é exatamente o defeito de origem.
cena_mutacao S4at src/river_unifi_bridge/service.py \
    '    finally:
        if ponte is not None:' \
    '    except BaseException:
        if ponte is not None:' \
    tests/unit/test_service_loop.py::test_the_reader_is_taken_along_when_the_api_cannot_start

# S4au — o recuo só zera quando o par SOBREVIVEU a uma volta inteira. Zerando no
# lançamento, um servidor que morre sempre reiniciava o contador a cada volta:
# 451 lançamentos por hora, sem recuo nenhum.
cena_mutacao S4au src/river_unifi_bridge/nut_supervisor.py \
    'elif self._de_pe():' \
    'elif True:' \
    tests/unit/test_nut_supervisor.py::test_a_server_that_never_survives_also_makes_the_backoff_grow

# S4av — o daemon obedece à mesma costura do NUT que o instalador. Sem ela, uma
# cena do portão lançava o leitor REAL contra o River do dono e tomava o cabo.
cena_mutacao S4av src/river_unifi_bridge/nut_supervisor.py \
    'self._prefixo = prefixo or os.environ.get("RUB_NUT_PREFIX") or PREFIXO_PADRAO' \
    'self._prefixo = prefixo or PREFIXO_PADRAO' \
    tests/unit/test_nut_supervisor.py::test_the_nut_seam_is_respected_by_the_daemon_too

# S4aw — gravar no histórico não pode deixar descritor aberto. `with
# sqlite3.connect(...)` NÃO fecha a conexão (documentação do Python), e sem o
# `close()` o serviço batia no teto de 256 arquivos do launchd em minutos:
# medido no Mac mini, 78 cópias da base abertas e subindo duas por segundo.
cena_mutacao S4aw src/river_unifi_bridge/history.py \
    'conn.close()               # o descritor: só sai daqui' \
    'pass                       # o descritor: só sai daqui' \
    tests/unit/test_history.py::test_every_operation_closes_its_connection

# S4ax — um ciclo sem resposta na porta serial não apaga o consumo da tela. O
# dono viu o bloco "consumo por tomada" aparecer e sumir no Mac mini.
cena_mutacao S4ax src/river_unifi_bridge/service.py \
    'resultado = _leitura_serial_recente(clock)' \
    'resultado = None' \
    tests/unit/test_service_loop.py::test_one_failed_serial_read_does_not_blank_the_outlets

# S4ay — armar exige prova de que o serviço ALCANÇA o console. Sem isto, o
# primeiro contato real com o roteador seria o comando de desligar, numa queda —
# e foi assim que um defeito de caminho sobreviveu meses sem aparecer.
cena_mutacao S4ay src/river_unifi_bridge/plugins/ssh_motor.py \
    '            if not self.alcance_valido():
                # O portão que faltava' \
    '            if False:
                # O portão que faltava' \
    tests/unit/test_api.py::test_arming_is_refused_without_proof_that_we_reach_the_console

# S4az — prova de alcance velha não vale: endereço muda, chave é revogada,
# console é trocado.
cena_mutacao S4az src/river_unifi_bridge/plugins/ssh_motor.py \
    'return (agora - quando) <= ALCANCE_VALIDADE_SEGUNDOS' \
    'return True' \
    tests/unit/test_api.py::test_a_stale_proof_of_reach_does_not_arm

# S4ba — TODAS as identidades que o console oferece são gravadas. Guardar só a
# primeira faz o `ssh` recusar a conexão com "No ED25519 host key is known" (foi
# o que aconteceu no console do dono, com um arquivo que só tinha a RSA).
cena_mutacao S4ba src/river_unifi_bridge/ssh_acesso.py \
    'linhas = [l for l in saida.stdout.decode("utf-8", "replace").splitlines()' \
    'linhas = [l for l in saida.stdout.decode("utf-8", "replace").splitlines()[:2]' \
    tests/unit/test_ssh_acesso.py::test_the_scan_keeps_every_key_type_the_console_offers

# S4bb — o valor de UserKnownHostsFile vai ENTRE ASPAS: o `ssh` o divide por
# espaços, e o estado do macOS mora em "Application Support". Sem as aspas, o
# desligamento do console nunca teria funcionado numa instalação real.
# (aspas simples dentro do texto: por isso as âncoras usam $'...' aqui)
cena_mutacao S4bb src/river_unifi_bridge/protect.py \
    $'f\'UserKnownHostsFile="{known_hosts_path}"\'' \
    $'f"UserKnownHostsFile={known_hosts_path}"' \
    tests/unit/test_protect.py::test_the_known_hosts_path_is_quoted_because_it_has_spaces

# S4bc — a chave PRIVADA não sai por rota nenhuma. O mutante devolve a chave
# inteira em vez da pública, que é o erro que um dia alguém comete achando que
# "é tudo chave".
cena_mutacao S4bc src/river_unifi_bridge/api.py \
    'return {"chave_publica": chave.publica,' \
    'return {"chave_publica": open(plugin.chave_path).read(),' \
    tests/unit/test_api.py::test_the_private_key_never_leaves_the_service

# S4bd — a senha do console é de passagem: usada uma vez e descartada. O mutante
# a devolve na resposta da rota, que é o vazamento mais fácil de cometer.
cena_mutacao S4bd src/river_unifi_bridge/api.py \
    '        resultado = self._acesso_testar(plugin, pc, sa)' \
    '        resultado = {**self._acesso_testar(plugin, pc, sa), "senha": senha}' \
    tests/unit/test_api.py::test_the_console_password_is_used_once_and_never_stored

# S4be — o selo do cabo tem de MEDIR. Até a 0.5.1 era uma constante: dizia "não
# observável" acontecesse o que acontecesse, inclusive com o simulador no ar.
cena_mutacao S4be src/river_unifi_bridge/state.py \
    'usb = _selo_do_cabo(snapshot, comm_ok, last_error)' \
    'usb = "nao_observavel"' \
    tests/unit/test_fixtures_contract.py::test_the_cable_seal_says_what_it_measured

# S4bf — a chave que o serviço instalou tem de sobreviver a um salvamento. Sem
# isto a proteção armava e ficava em "configuração incompleta": na queda de
# energia, nada seria enviado.
cena_mutacao S4bf src/river_unifi_bridge/plugins/ssh_motor.py \
    'new = _com_chave_gerida(' \
    'new = (lambda pc, _c: pc)(' \
    tests/unit/test_plugin_contract.py::test_the_installed_key_survives_saving_and_arming

# S4bg — mexer no acesso ao console com a proteção ARMADA deixaria o dispositivo
# armado e sem como falar com o aparelho, e a tela continuaria dizendo "armada".
cena_mutacao S4bg src/river_unifi_bridge/api.py \
    'if acao != "testar" and plugin.armed:' \
    'if False:' \
    tests/unit/test_api.py::test_touching_the_console_access_is_refused_while_armed

# S4bh — a recusa de identidade divergente vale em QUALQUER porta: o OpenSSH
# marca `[host]:porta` fora da 22, e comparar com o endereço puro fazia a cerca
# não existir ali.
cena_mutacao S4bh src/river_unifi_bridge/ssh_acesso.py \
    'return host if porta == 22 else f"[{host}]:{porta}"' \
    'return host' \
    tests/unit/test_ssh_acesso.py::test_identity_is_checked_on_any_port

# S31 — o vigia não pode virar espelho: apontar a proteção para um aparelho que a
# PRÓPRIA ponte publica fecharia o laço (ela decidiria desligar um roteador com
# base em dados que ela mesma escreveu, e um erro de leitura viraria verdade).
cena_mutacao S31 src/river_unifi_bridge/config.py \
    "    if nut_ups == aparelho:" \
    "    if False:" \
    tests/unit/test_nut_servico.py::test_the_protection_may_not_read_a_device_we_publish

# S31b — dispositivo protegido só entra no NUT com alcance PROVADO. Sem a prova,
# o Home Assistant mostraria uma ordem de desligar que não chega a lugar nenhum.
cena_mutacao S31b src/river_unifi_bridge/nut_servico.py \
    "return bool(alcance and alcance())" \
    "return True" \
    tests/unit/test_nut_servico.py::test_a_device_without_proven_reach_is_not_published \
    tests/unit/test_nut_servico.py::test_a_device_that_loses_its_reach_proof_stops_being_published

# S31c — publicar ANTES da leitura serial entregaria ao Home Assistant a leitura
# sem os watts por tomada, que é justamente o que ele não tinha antes desta versão.
cena_mutacao S31c src/river_unifi_bridge/service.py \
    "ponte.atualizar(snap, plugins)" \
    "pass" \
    tests/unit/test_service_loop.py::test_publishing_happens_after_the_serial_port_is_read

# S31d — sair sem recolher os aparelhos publicados deixa soquetes para trás, e o
# servidor do no-break passa a servir um aparelho fantasma que ninguém alimenta.
cena_mutacao S31d src/river_unifi_bridge/service.py \
    '        if ponte is not None:
            ponte.encerrar()' \
    '        if False:
            ponte.encerrar()' \
    tests/unit/test_service_loop.py::test_leaving_takes_the_published_devices_with_it

# S32 — desligar o River pelo NUT sem a trava de arquivo aberta. A trava é a
# MESMA da tela: nem a rota do app nem o Home Assistant a abrem.
cena_mutacao S32 src/river_unifi_bridge/nut_comandos.py \
    'if not getattr(self.cfg, "river_poweroff_allowed", False):' \
    "if False:" \
    tests/unit/test_nut_comandos.py::test_the_river_is_not_turned_off_with_the_file_lock_shut

# S33 — desligar o River pelo NUT com proteção armada seriam duas ordens de
# desligamento ao mesmo tempo: a automática da queda e a do dono.
cena_mutacao S33 src/river_unifi_bridge/nut_comandos.py \
    'if any(getattr(p, "armed", False) for p in self.plugins):' \
    "if False:" \
    tests/unit/test_nut_comandos.py::test_the_river_is_not_turned_off_while_a_protection_is_armed

# S34 — mandar num dispositivo sem alcance PROVADO. Provar por outro caminho não
# diria nada sobre este, e é este que corta a energia do aparelho de alguém.
cena_mutacao S34 src/river_unifi_bridge/plugins/ssh_motor.py \
    '        if not self.alcance_valido():
            return ("ainda não foi provado que este serviço alcança o aparelho: "' \
    '        if False:
            return ("ainda não foi provado que este serviço alcança o aparelho: "' \
    tests/unit/test_nut_comandos.py::test_a_device_without_proven_reach_never_spawns_an_ssh

# S34b — anunciar uma ordem que o tipo não sabe cumprir. Trocar reiniciar por
# desligar num roteador de produção é o pior desfecho possível.
cena_mutacao S34b src/river_unifi_bridge/nut_comandos.py \
    "return tuple(nome for nome, acao in _ACAO_DO_COMANDO.items() if acao in acoes)" \
    "return tuple(_ACAO_DO_COMANDO)" \
    tests/unit/test_nut_comandos.py::test_only_what_the_type_knows_how_to_do_is_announced

# S35 — leitura serial VENCIDA não pode continuar sendo publicada. Um watt que
# parou no tempo, mostrado como se fosse de agora, é pior que watt nenhum: quem
# lê pelo Home Assistant não tem como saber que o número congelou.
cena_mutacao S35 src/river_unifi_bridge/service.py \
    "if clock() - quando > SERIAL_VALIDADE_SEGUNDOS:" \
    "if False:" \
    tests/unit/test_service_loop.py::test_a_stale_serial_reading_stops_being_published \
    tests/unit/test_service_loop.py::test_one_failed_serial_read_does_not_blank_the_outlets

# --- o que a revisão fria da 0.7.0 achou, cada achado com a sua cerca ---------

# S36 — a RESPOSTA de um comando é para quem perguntou. Como aviso geral, ela
# chegava a quem não pediu e NÃO chegava a quem tinha desligado os avisos: o
# River era desligado e o Home Assistant nunca sabia se a ordem tinha valido.
cena_mutacao S36 src/river_unifi_bridge/nut_driver.py \
    "            if cliente in self._clientes:      # desligou no meio: não há a quem responder
                cliente.enfileira(texto)" \
    "            self._para_todos(texto)" \
    tests/unit/test_nut_driver.py::test_the_answer_goes_to_who_asked_even_with_broadcasts_off \
    tests/unit/test_nut_driver.py::test_the_answer_does_not_go_to_a_client_that_did_not_ask

# S37 — uma variável do NUT é UMA linha. Quebra de linha no valor não é valor
# estranho: é linha nova injetada no protocolo, e o que publicamos vem de fora
# (modelo e firmware saem do que o console respondeu).
cena_mutacao S37 src/river_unifi_bridge/nut_driver.py \
    'limpo = "".join(" " if (ord(c) < 0x20 or ord(c) == 0x7F) else c for c in valor)' \
    "limpo = valor" \
    tests/unit/test_nut_driver.py::test_a_value_with_a_newline_cannot_inject_a_second_line

# S38 — o soquete é 0600. Com 0660, na pasta 0755 de grupo `admin` desta máquina,
# qualquer conta administradora mandaria desligar o River sem ficha e sem rastro.
cena_mutacao S38 src/river_unifi_bridge/nut_driver.py \
    "os.chmod(self.caminho, stat.S_IRUSR | stat.S_IWUSR)" \
    "os.chmod(self.caminho, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IWGRP)" \
    tests/unit/test_nut_driver.py::test_only_who_runs_the_service_can_send_an_order_through_the_socket

# S39 — mandar num dispositivo à mão exige trava de ARQUIVO, como os outros dois
# atos destrutivos da casa. Sem ela, era o único que não tinha nenhuma.
cena_mutacao S39 src/river_unifi_bridge/nut_comandos.py \
    'if cfg is not None and not getattr(cfg, "device_cmd_allowed", False):' \
    "if False:" \
    tests/unit/test_nut_comandos.py::test_a_device_offers_no_order_while_the_file_lock_is_shut

# S39b — e a trava vale também para quem manda direto no soquete, sem perguntar
# antes o que existe. Anunciar de menos é cortesia; recusar é a cerca.
cena_mutacao S39b src/river_unifi_bridge/nut_comandos.py \
    'if not getattr(self.cfg, "device_cmd_allowed", False):' \
    "if False:" \
    tests/unit/test_nut_comandos.py::test_the_lock_is_checked_again_when_the_order_arrives

# S40 — o nome de um dispositivo protegido também é aparelho publicado por nós, e
# a proteção não pode lê-lo. No `.env` isso não dá para conferir: os dispositivos
# vivem na loja.
cena_mutacao S40 src/river_unifi_bridge/config.py \
    "if nut_ups in set(dispositivos):" \
    "if False:" \
    tests/unit/test_nut_servico.py::test_a_protected_device_name_is_refused_as_the_protection_source \
    tests/unit/test_service_loop.py::test_the_service_refuses_to_start_reading_a_device_it_publishes

# S41 — a regra cruzada vale no PUT também. Só no arquivo, a tela gravava a
# configuração ruim, mandava reiniciar, e no reinício o serviço parava de
# propósito — que sob o launchd é a saída que NÃO relança.
cena_mutacao S41 src/river_unifi_bridge/api.py \
    "        if recusa_espelho is not None:" \
    "        if False:" \
    tests/unit/test_api.py::test_the_screen_cannot_write_a_configuration_that_stops_the_service

# S42 — a chave que liga a publicação NÃO aplica a quente; anunciá-la como se
# aplicasse faria a tela dizer que a porta das ordens fechou enquanto os soquetes
# continuavam no ar até o reinício.
cena_mutacao S42 src/river_unifi_bridge/config.py \
    '        "RIVER_SERIAL_PORT",
        # As três travas (0.8.0)' \
    '        "RIVER_SERIAL_PORT",
        "RIVER_NUT_PUBLICA",
        # As três travas (0.8.0)' \
    tests/unit/test_api.py::test_turning_publishing_off_is_not_announced_as_taking_effect_now

# S43 — o trecho que o serviço mantém no `ups.conf` não pode comer o que está
# fora das marcas. A promessa do instalador é que quem configurou o NUT à mão
# continua com a configuração dele — e a seção do leitor de fábrica, que a
# proteção lê, está justamente fora do nosso trecho.
cena_mutacao S43 src/river_unifi_bridge/nut_conf.py \
    "    return texto[:inicio] + novo + texto[fim:]" \
    "    return texto[:inicio] + novo" \
    tests/unit/test_nut_conf.py::test_what_comes_after_our_block_survives_a_rewrite

# S45 — o cabo NÃO é largado com proteção armada. Largar seria ficar cego para a
# queda de energia justamente com o desligamento automático ligado.
cena_mutacao S45 src/river_unifi_bridge/cabo_automatico.py \
    "        if self._ha_protecao_armada():" \
    "        if False:" \
    tests/unit/test_cabo_automatico.py::test_the_cable_is_never_handed_over_while_a_protection_is_armed

# S46 — e o que o dono emprestou pela tela não é retomado pelo automático: o
# programa não discute com o dono no meio de ele usar o aplicativo do fabricante.
cena_mutacao S46 src/river_unifi_bridge/cabo_automatico.py \
    '        if getattr(estado, "pausado_pelo_dono", False):' \
    "        if False:" \
    tests/unit/test_cabo_automatico.py::test_what_the_owner_lent_by_hand_is_not_taken_back_by_us

# S46b — e o cabo VOLTA quando o aplicativo do fabricante some. Sem isto, o
# serviço largaria o cabo uma vez e nunca mais vigiaria a energia.
cena_mutacao S46b src/river_unifi_bridge/cabo_automatico.py \
    "        estado = self._supervisor.retomar()" \
    "        estado = None" \
    tests/unit/test_cabo_automatico.py::test_the_cable_comes_back_when_the_vendor_app_closes \
    tests/unit/test_cabo_automatico.py::test_a_search_that_blows_up_brings_the_cable_back_instead_of_keeping_it

# S67 — o cabo só é cedido quando o aplicativo da EcoFlow o TOMA (o leitor cai),
# não só porque ele abriu: em modo Remoto ele lê pelo nosso servidor e não toca
# no leitor (medido no Mac mini em 2026-09-06). Mutante: cede ao abrir, como
# a 0.8.4 — e os dois ficariam sem leitura.
cena_mutacao S67 src/river_unifi_bridge/cabo_automatico.py \
    "        if self._quedas_do_driver() <= self._quedas_ao_abrir:" \
    "        if False:" \
    tests/unit/test_cabo_automatico.py::test_o_cabo_fica_quando_o_aplicativo_nao_o_pede
# S67b — a queda entre duas olhadas ainda conta (a referência é a olhada anterior).
cena_mutacao S67b src/river_unifi_bridge/cabo_automatico.py \
    "            self._quedas_ao_abrir = self._quedas_na_olhada_anterior" \
    "            self._quedas_ao_abrir = self._quedas_do_driver()" \
    tests/unit/test_cabo_automatico.py::test_uma_queda_entre_duas_olhadas_ainda_conta_como_pedido
# S69 — o tipo 23 da serial (tempo para carga completa) tem uma sentinela de "não
# está carregando" (bytes 33 17). Mutante: ignora a sentinela → o quadro real a
# 100 % viraria "5939 min" na tela e no Home Assistant.
cena_mutacao S69 src/river_unifi_bridge/river_serial.py \
    "            if dados[:2] != _NAO_CARREGANDO:" \
    "            if True:" \
    tests/unit/test_river_serial.py::test_time_to_full_is_null_when_not_charging
# S70 — dos quatro sensores de temperatura, [0] é o sistema e [1] é a bateria
# (0.9.0). Mutante: o sistema passa a ler o sensor da bateria.
cena_mutacao S70 src/river_unifi_bridge/river_serial.py \
    "            leitura.temperatura_sistema_c = float(sensores[_SENSOR_SISTEMA])" \
    "            leitura.temperatura_sistema_c = float(sensores[_SENSOR_BATERIA])" \
    tests/unit/test_river_serial.py::test_the_four_temperatures_and_their_names
# S71 — `battery.capacity.nominal` é em Ah no dicionário do NUT; a serial fala em
# mAh (0.9.0). Mutante: publica os mAh crus → o Home Assistant mostraria 12800 Ah.
cena_mutacao S71 src/river_unifi_bridge/nut_publicacao.py \
    '        _poe(variaveis, "battery.capacity.nominal", _texto(capacidade_mah / 1000, 1))' \
    '        _poe(variaveis, "battery.capacity.nominal", _texto(capacidade_mah, 1))' \
    tests/unit/test_nut_publicacao.py::test_capacity_comes_out_in_ah
# S72 — o CSV de eventos leva o dono do evento (a instância) numa coluna própria
# (0.9.0). Mutante: a coluna some → quem lê o arquivo não sabe de que aparelho é.
cena_mutacao S72 src/river_unifi_bridge/history.py \
    "                writer.writerow((self._iso_local(r[0]), r[0], r[1], r[3], r[2]))" \
    "                writer.writerow((self._iso_local(r[0]), r[0], r[1], None, r[2]))" \
    tests/unit/test_api.py::test_events_csv_has_the_columns
# S75 — o cliente que fecha no meio do CSV não prende a thread produtora (0.9.0;
# revisão fria, medido: sem avisar e drenar, a thread ficava presa num `put` sem
# leitor, com a conexão do SQLite aberta). Mutante: o consumidor deixa de drenar.
cena_mutacao S75 src/river_unifi_bridge/api.py \
    "            cliente_foi.set()" \
    "            pass" \
    tests/unit/test_api.py::test_a_client_that_leaves_mid_csv_does_not_pin_a_thread
# (A drenagem da fila no `finally` do consumidor não tem cena própria: o `put`
# órfão só existe quando a fila está cheia no instante da desconexão, e isso
# não é determinístico — medido em 2026-09-06, o mutante sem drenagem passou.)

# --- 0.8.0: a UX que o dono determinou, inteira -------------------------------

# S57 — o padrão do aplicativo da EcoFlow casa a INTERFACE e não o daemon deles,
# que roda sempre. As duas versões anteriores (o caminho do pacote; o prefixo
# `…/Contents/MacOS/`) casavam o daemon, e o cabo era largado na primeira volta e
# nunca voltava. Medido no Mac mini em 2026-09-05 com a interface aberta.
cena_mutacao S57 src/river_unifi_bridge/cabo_automatico.py \
    'APLICATIVO_DO_FABRICANTE = r"/Contents/MacOS/PowerManager$"' \
    'APLICATIVO_DO_FABRICANTE = r"/Applications/PowerManager.app/Contents/MacOS/"' \
    tests/unit/test_cabo_automatico.py::test_o_daemon_deles_nao_e_o_aplicativo

# S58 — as três travas são interruptores na tela e aplicam a QUENTE. Tirada da
# lista de aplicação a quente, a trava do River voltaria a exigir reinício — o
# interruptor diria "feito" e a ordem não existiria até o dono reiniciar.
# (O plano previa plantar a recusa "somente arquivo" de volta em api.py; esse
# código deixou de existir, então o mutante possível é este, em config.py.)
cena_mutacao S58 src/river_unifi_bridge/config.py \
    '        "UDR7_ARM_ALLOWED",
        "RIVER_POWEROFF_ALLOWED",' \
    '        "UDR7_ARM_ALLOWED",' \
    tests/unit/test_api.py::test_travas_aplicam_a_quente

# S58b — e o aparelho publicado acompanha o interruptor a cada volta: congelar a
# lista de comandos na construção faria o Home Assistant só ver a ordem depois
# de um reinício.
cena_mutacao S58b src/river_unifi_bridge/nut_servico.py \
    'comandos=self._comandos_do_river(), dados_ok=True)' \
    'comandos=(), dados_ok=True)' \
    tests/unit/test_nut_servico.py::test_trava_ligada_vira_addcmd_sem_reinicio

# S59 — com o NUT dentro do pacote, o leitor e o servidor nascem com os caminhos
# do NOSSO diretório (NUT_CONFPATH/NUT_STATEPATH). Sem isso, o servidor procura
# soquetes em /opt/homebrew, onde ninguém escuta, e o Home Assistant não vê nada.
cena_mutacao S59 src/river_unifi_bridge/nut_supervisor.py \
    "                           env=self._ambiente)" \
    "                           env=None)" \
    tests/unit/test_nut_supervisor.py::test_os_filhos_nascem_com_os_caminhos_do_pacote

# S60 — o empacotador PROVA que o NUT embutido roda de dentro do pacote: zero
# referência a /opt/homebrew sobrando e os dois binários respondendo `-V`. Cena
# de texto (molde da S44): montar o pacote leva minuto e meio.
S60_FALHOU=""
grep -q "grep -c '/opt/homebrew'" "$RAIZ/tools/build-app.sh" \
  || S60_FALHOU="a prova de zero referência a /opt/homebrew sumiu"
grep -q '"\$NUT_DEST/sbin/upsd" -V' "$RAIZ/tools/build-app.sh" \
  || S60_FALHOU="${S60_FALHOU:-a prova de que o upsd embutido roda sumiu}"
grep -q 'export RUB_NUT_PREFIX="\$AQUI/nut"' "$RAIZ/tools/build-app.sh" \
  || S60_FALHOU="${S60_FALHOU:-o lançador não aponta o supervisor para o NUT do pacote}"
if [ -z "$S60_FALHOU" ]; then
    ok "S60 empacotador: NUT embutido com prova de relocação e de arranque"
else
    erro "S60 empacotador: $S60_FALHOU"
fi

# S61 — o pacote no Lixo dispara a remoção. É o `F_GETPATH` real respondendo a
# um `mv` real; sem reconhecer o Lixo, o serviço seguiria vivo de dentro dele
# (visto pelo dono no Mac mini, 2026-09-05).
cena_mutacao S61 src/river_unifi_bridge/remocao.py \
    'MARCAS_DO_LIXO = ("/.Trash/", "/.Trashes/")' \
    'MARCAS_DO_LIXO = ("/.Nunca/", "/.Jamais/")' \
    tests/unit/test_remocao.py::test_no_lixo_dispara \
    tests/unit/test_remocao.py::test_partida_dentro_do_lixo_dispara

# S62 — mover para OUTRA pasta não é jogar fora: só o Lixo dispara.
cena_mutacao S62 src/river_unifi_bridge/remocao.py \
    '        if not no_lixo(atual):
            return False' \
    '        if atual is None:
            return False' \
    tests/unit/test_remocao.py::test_mover_fora_do_lixo_nao_remove

# S62b — atualizar não é remover: o pacote antigo no Lixo com o novo no lugar
# NÃO dispara (bloqueador B1 da revisão fria do plano da 0.8.0).
cena_mutacao S62b src/river_unifi_bridge/remocao.py \
    '        return not os.path.isdir(self.original)' \
    '        return True' \
    tests/unit/test_remocao.py::test_substituido_no_lugar_nao_remove

# S62c — apagar ANTES de desregistrar: ao contrário, o launchd derruba o serviço
# no meio da limpeza e a chave do console fica no disco.
cena_mutacao S62c src/river_unifi_bridge/remocao.py \
    '    apagados = apagar(state_dir, ups_conf, log)
    desregistrar_(rotulo, pacote=pacote, log=log)' \
    '    desregistrar_(rotulo, pacote=pacote, log=log)
    apagados = apagar(state_dir, ups_conf, log)' \
    tests/unit/test_remocao.py::test_retirar_apaga_antes_de_desregistrar

# S62d — relançado de dentro do Lixo, remove na primeira volta (bloqueador B2 da
# revisão fria: só a regra "mudou de lugar" não vê diferença na partida).
cena_mutacao S62d src/river_unifi_bridge/remocao.py \
    '        if no_lixo(self.original):
            return True' \
    '        if False:
            return True' \
    tests/unit/test_remocao.py::test_partida_dentro_do_lixo_dispara

# S66 — o registro nos Itens de Início de Sessão é desfeito pelo AJUDANTE do
# pacote (SMAppService.unregister), antes do bootout. Mutante: pula o ajudante
# (o dono viu o interruptor ligado com o programa no Lixo, 2026-09-06).
cena_mutacao S66 src/river_unifi_bridge/remocao.py \
    '    argv = comando_do_ajudante(pacote, uid_da_console())' \
    '    argv = None' \
    tests/unit/test_remocao.py::test_o_ajudante_desregistra_antes_do_bootout
# S66b — o ajudante HERDA a saída do serviço (o diário) e ninguém espera por ele:
# mutante volta a capturar a saída num cano (a resposta morreria com o serviço).
cena_mutacao S66b src/river_unifi_bridge/remocao.py \
    '            spawn(argv, stdout=None, stderr=None, start_new_session=True)' \
    '            spawn(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)' \
    tests/unit/test_remocao.py::test_o_ajudante_desregistra_antes_do_bootout
# S62e — o `launchctl bootout` nasce em sessão nova (launchd.plist(5): o launchd
# mata o grupo de processos do job que morre; bloqueador B3 da revisão fria).
cena_mutacao S62e src/river_unifi_bridge/remocao.py \
    '              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
              start_new_session=True)' \
    '              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
              start_new_session=False)' \
    tests/unit/test_remocao.py::test_bootout_nasce_em_sessao_nova

# S63 — o interruptor da rede só reescreve um `upsd.conf` que seja NOSSO. Um
# arquivo escrito à mão pelo dono é dele: reescrevê-lo por cima apagaria o que
# ele configurou, sem uma linha de registro.
cena_mutacao S63 src/river_unifi_bridge/nut_bootstrap.py \
    '    if atual is None:
        raise ConfiguracaoDoDono(' \
    '    if False:
        raise ConfiguracaoDoDono(' \
    tests/unit/test_nut_bootstrap.py::test_arquivo_do_dono_nao_e_tocado

# S64 — a assinatura é de DENTRO para fora, com o runtime endurecido, e o
# `--deep` não é o único passo: a notarização confere cada Mach-O aninhado, e
# `--deep` não alcança os soltos em Resources (medido: 24 arquivos). Cena de
# texto, como a S44 e a S60.
S64_FALHOU=""
grep -q -- '--options runtime --timestamp' "$RAIZ/tools/build-app.sh" \
  || S64_FALHOU="a assinatura não pede o runtime endurecido com carimbo de tempo"
grep -q 'assinar_de_dentro_para_fora || exit 1' "$RAIZ/tools/build-app.sh" \
  || S64_FALHOU="${S64_FALHOU:-a assinatura de dentro para fora não é chamada}"
grep -q 'codesign --force --deep --sign' "$RAIZ/tools/build-app.sh" \
  && S64_FALHOU="${S64_FALHOU:-voltou o --deep como assinatura do pacote}"
grep -q "status: Accepted" "$RAIZ/tools/build-dmg.sh" \
  || S64_FALHOU="${S64_FALHOU:-o disco não exige a notarização aceita}"
grep -q 'source=Notarized Developer ID' "$RAIZ/tools/build-dmg.sh" \
  || S64_FALHOU="${S64_FALHOU:-o disco não é avaliado pelo Gatekeeper depois de grampeado}"
if [ -z "$S64_FALHOU" ]; then
    ok "S64 assinatura: de dentro para fora, runtime endurecido, notarização exigida e provada"
else
    erro "S64 assinatura: $S64_FALHOU"
fi

# --- o que a 2.ª revisão fria da 0.7.0 achou ---------------------------------

# S47 — marca do nosso trecho que não fecha é RECUSA, não conserto. A versão
# anterior acrescentava o trecho novo e deixava a marca órfã; a volta SEGUINTE do
# laço (dois segundos depois) tomava a órfã como começo e apagava tudo até a
# marca de fim nova — conteúdo do dono, e a seção do leitor de fábrica junto.
cena_mutacao S47 src/river_unifi_bridge/nut_conf.py \
    "    if inicios != fins:" \
    "    if False:" \
    tests/unit/test_nut_conf.py::test_a_half_cut_block_makes_us_keep_our_hands_off

# S47b — e o arquivo que o dono trancou para escrita fica trancado: a troca
# atômica passa pela permissão da PASTA, então sem esta conferência o "não mexa"
# dele era ignorado em silêncio.
cena_mutacao S47b src/river_unifi_bridge/nut_conf.py \
    '    if not os.access(caminho, os.W_OK):
        raise ConfMalformada(
            f"{caminho} está sem permissão de escrita; respeito isso e não mexo nele")
    depois = _troca_o_bloco(antes, bloco(aparelhos))' \
    "    depois = _troca_o_bloco(antes, bloco(aparelhos))" \
    tests/unit/test_nut_conf.py::test_a_file_the_owner_locked_stays_locked

# S48 — link simbólico é seguido, não destruído. Sem isto, quem guarda a
# configuração do NUT num repositório pessoal passava a editar um arquivo que o
# NUT não lê mais, e a edição dele sumia sem uma linha de registro.
cena_mutacao S48 src/river_unifi_bridge/nut_conf.py \
    '    caminho = os.path.realpath(caminho)
    try:
        with open(caminho, encoding="utf-8") as arquivo:
            antes = arquivo.read()
    except OSError:
        return False                      # não existe, ou não é nosso: não criamos' \
    '    try:
        with open(caminho, encoding="utf-8") as arquivo:
            antes = arquivo.read()
    except OSError:
        return False                      # não existe, ou não é nosso: não criamos' \
    tests/unit/test_nut_conf.py::test_a_symlink_is_followed_not_destroyed

# S49 — o corte de um valor comprido não pode cair no MEIO de um par de escape:
# terminando em barra ímpar, a linha do protocolo fica ABERTA e o servidor engole
# a linha seguinte inteira como continuação desta.
cena_mutacao S49 src/river_unifi_bridge/nut_driver.py \
    'if (len(limpo) - len(limpo.rstrip("\\"))) % 2:' \
    "if False:" \
    tests/unit/test_nut_driver.py::test_a_very_long_value_is_cut_without_splitting_an_escape

# S50 — o soquete não pode ser do grupo NEM POR UM INSTANTE: com a máscara antiga
# ele nascia 0770 e só virava 0600 na linha seguinte.
cena_mutacao S50 src/river_unifi_bridge/nut_driver.py \
    "umask_antes = os.umask(0o077)" \
    "umask_antes = os.umask(0o007)" \
    tests/unit/test_nut_driver.py::test_the_socket_is_never_group_writable_not_even_for_an_instant

# S51 — uma ordem por vez. Duas ordens de desligamento correndo juntas num
# roteador de produção não é paralelismo, é confusão — e sem limite cada INSTCMD
# criava uma linha de execução nova que sobrevivia ao encerramento.
cena_mutacao S51 src/river_unifi_bridge/nut_driver.py \
    "            if self._ordem_em_curso is not None:" \
    "            if False:" \
    tests/unit/test_nut_driver.py::test_a_second_order_while_one_is_running_is_refused_not_queued

# S52 — a queixa sobre o `ups.conf` sai UMA vez, não a cada dois segundos: 1.800
# linhas iguais por hora afogariam a queixa que importa.
cena_mutacao S52 src/river_unifi_bridge/nut_servico.py \
    "            if motivo != self._ultima_queixa_do_conf:" \
    "            if True:" \
    tests/unit/test_nut_servico.py::test_a_ups_conf_we_cannot_read_is_complained_about_once_not_every_lap

# S56 — UMA publicação por volta, e a leitura inteira. Duas publicações faziam a
# tela receber, no meio de cada volta, um aparelho "sem potência": o gráfico
# apagava e voltava a cada dois segundos, e o histórico levava duas amostras por
# ciclo, uma delas sem os watts.
cena_mutacao S56 src/river_unifi_bridge/service.py \
    "_process_snapshot(snap, tracker, plugins, shared, history, publicar=False)" \
    "_process_snapshot(snap, tracker, plugins, shared, history)" \
    tests/unit/test_service_loop.py::test_the_screen_gets_one_reading_per_lap_and_it_is_the_whole_one

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

# Mutação em SWIFT: o mesmo rito de `cena_mutacao`, sobre o pacote do app. Copia
# o pacote (sem o .build), planta o defeito e roda SÓ o teste que tem de reprovar.
# Custa uma compilação limpa do Core e dos testes; é o preço de uma cerca provada.
cena_mutacao_swift() {
    local nome="$1" arq="$2" ancora="$3" mutante="$4" filtro="$5"
    # Linha de base: o teste tem de existir e passar na árvore limpa. O filtro
    # do `swift test` é uma expressão regular sobre `Módulo.função()` — um teste
    # de função livre NÃO tem suíte no nome, e um filtro que não casa nada
    # devolve "0 tests … passed" com rc 0 (revisão fria da 0.8.7).
    (cd "$APP_DIR" && swift test --filter "$filtro" >"/tmp/gate_base_$nome.log" 2>&1)
    local n
    n="$(grep -Eo 'with [0-9]+ test' "/tmp/gate_base_$nome.log" | tail -1 | grep -Eo '[0-9]+')"
    if [ -z "$n" ] || [ "$n" -lt 1 ] || grep -q "✘ Test" "/tmp/gate_base_$nome.log"; then
        erro "$nome baseline: o filtro $filtro não seleciona teste verde na árvore limpa — cauda:"
        tail -3 "/tmp/gate_base_$nome.log"; return
    fi
    local M
    M="$(mktemp -d)"
    (cd "$APP_DIR" && tar --exclude=.build --exclude=.swiftpm -cf - .) | (cd "$M" && tar -xf -)
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
    (cd "$M" && swift test --filter "$filtro" >"/tmp/gate_mut_$nome.log" 2>&1)
    local rc=$?
    rm -rf "$M"
    if [ "$rc" -eq 0 ]; then
        erro "$nome mutação: o teste $filtro passou com o defeito plantado"; return
    fi
    if ! grep -q "✘ Test" "/tmp/gate_mut_$nome.log"; then
        erro "$nome mutação: o mutante nem chegou a rodar o teste (rc=$rc) — cauda:"; tail -3 "/tmp/gate_mut_$nome.log"; return
    fi
    ok "$nome mutação (Swift): baseline $n verde; cerca $filtro reprovou o defeito plantado (rc=$rc)"
}

# S68 — toda barra do histograma de eventos tem a sua cor no domínio da escala. O
# Swift Charts derruba o app (SIGTRAP) com um valor fora do domínio explícito —
# medido em 2026-09-06, e foi a queda do dono ao abrir 24 h/7 d de eventos (os
# eventos do cabo não estavam na legenda). Mutante: tira o passo que põe no
# domínio o rótulo que nenhuma lista conhece.
if [ -d "$APP_DIR" ]; then
    cena_mutacao_swift S68 Sources/RiverBridgeCore/LegendaDeEventos.swift \
        "            let posicao = lugar(tipo: evento.tipo, dispositivo: evento.dispositivo, dispositivos: dispositivos) ?? sobra + indice" \
        "            guard let posicao = lugar(tipo: evento.tipo, dispositivo: evento.dispositivo, dispositivos: dispositivos) else { continue }" \
        todaBarraTemASuaCorNoDominio
fi

# S73 — o selo da instância armada é "Armada", e nunca acusa alcance (0.9.0). O
# estado `armado_nao_verificado` é o de toda instância armada; "alcance não
# verificado" era tradução ao pé da letra e falsa. Mutante: o texto velho volta.
if [ -d "$APP_DIR" ]; then
    cena_mutacao_swift S73 Sources/RiverBridgeCore/DeviceStateText.swift \
        '        case "armado_nao_verificado": return (L10n.t("Armada", "Armed"), .perigo)' \
        '        case "armado_nao_verificado": return (L10n.t("Armada — alcance não verificado", "Armed — reach unverified"), .perigo)' \
        oEstadoArmadoNaoAcusaAlcance
fi

# S78 — o empacotador monta o widget como o sistema exige (0.10.0): o .appex em
# PlugIns, o ponto de extensão do WidgetKit, caixa de areia, o grupo de
# aplicativos, e as provas (direitos lidos da assinatura; Team ID = prefixo do
# grupo). Molde S44/S64: o texto do script tem de conter cada peça.
S78_FALTA=""
for peca in 'PlugIns/RiverBridgeWidget.appex' 'com.apple.widgetkit-extension' \
            'com.apple.security.app-sandbox' 'com.apple.security.application-groups' \
            'codesign -d --entitlements :- "$APPEX"' 'GRUPO%%.*}" = "$TEAM_ID"' \
            'assinar "$APPEX" "$DIREITOS_WIDGET"' 'assinar "$APP" "$DIREITOS_APP"' \
            'external _NSExtensionMain (from Foundation)' 'LC_MAIN'; do
    grep -qF -- "$peca" "$RAIZ/tools/build-app.sh" || S78_FALTA="$S78_FALTA | $peca"
done
if [ -z "$S78_FALTA" ]; then
    ok "S78 empacotador: o widget nasce em PlugIns, em caixa de areia, com o grupo, e as provas dos direitos"
else
    erro "S78 empacotador sem:$S78_FALTA"
fi

# S79 — o executável do widget entra pelo NSExtensionMain (0.10.1). Não é prova de
# texto: é o binário que a S6 acabou de construir. Sem a flag de ligação o
# pluginkit registrava o widget e a galeria de widgets nunca o listava (dono, no
# Mac mini, 2026-09-06); medido nos widgets do Dropover, do Excel e do Teams que
# o LC_MAIN deles aponta para o stub de _NSExtensionMain, não para o main do Swift.
S79_BIN="$APP_DIR/.build/debug/RiverBridgeWidget"
if [ -x "$S79_BIN" ]; then
    S79_ENTRADA="$(otool -l "$S79_BIN" | awk '/LC_MAIN/{f=1} f&&/entryoff/{print $2; exit}')"
    S79_MAIN="$(nm "$S79_BIN" | awk '$3=="_main"{print $1}')"
    # `nm | grep -q` NÃO: o grep fecha o cano, o nm morre de SIGPIPE e o pipefail
    # conta isso como falha (medido: a cena nasceu vermelha com o binário certo).
    S79_NM="$(nm -m "$S79_BIN")"
    if grep -q 'external _NSExtensionMain (from Foundation)' <<< "$S79_NM" \
       && [ -n "$S79_ENTRADA" ] && [ -n "$S79_MAIN" ] \
       && [ "$S79_ENTRADA" != "$((0x$S79_MAIN - 0x100000000))" ]; then
        ok "S79 widget: o LC_MAIN entra pelo NSExtensionMain (entrada $S79_ENTRADA ≠ main $((0x$S79_MAIN - 0x100000000)))"
    else
        erro "S79 widget: o executável entra pelo main do Swift, não pelo NSExtensionMain (Package.swift, linkerSettings)"
    fi
else
    erro "S79 widget: binário de depuração ausente ($S79_BIN) — a S6 não o construiu?"
fi

# S76 — o app só pede recarga do widget em mudança de SIGNIFICADO (0.10.0; o
# WidgetKit dá 40–70 recargas por dia). Mutante: pede sempre.
if [ -d "$APP_DIR" ]; then
    cena_mutacao_swift S76 Sources/RiverBridgeCore/RetratoDoWidget.swift \
        '        return mudouFonte || mudouBaixa || mudouServico || cruzouDegrau || mudouIdioma' \
        '        return true' \
        naoRecarregaSemMudanca
fi

# S77 — retrato com mais de meia hora vira traço no widget, nunca valor velho como
# presente (0.10.0). Mutante: o limite passa de 30 min para 30 h.
if [ -d "$APP_DIR" ]; then
    cena_mutacao_swift S77 Sources/RiverBridgeCore/RetratoDoWidget.swift \
        '    public static let limiteDoTraco: TimeInterval = 30 * 60' \
        '    public static let limiteDoTraco: TimeInterval = 30 * 3600' \
        depoisDeMeiaHoraETraco
fi

# S74 — na folha do River, tempo para carga completa sem leitura é traço, nunca
# "0 min" (0.9.0: o serviço publica null quando o aparelho não está carregando).
if [ -d "$APP_DIR" ]; then
    cena_mutacao_swift S74 Sources/RiverBridgeCore/FolhaDoRiver.swift \
        '        guard let minutes else { return "—" }' \
        '        guard let minutes else { return "0 min" }' \
        tempoParaCargaSemLeituraETraco
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
# RUB_NUT_PREFIX/RUB_NUT_ETC são cerca de método: sem elas, a fase da leitura do
# River escreveria na configuração REAL do NUT da máquina que roda o gate.
mkdir -p "$INST/nut/bin" "$INST/nut/sbin" "$INST/nutetc"
printf '#!/bin/sh\nexit 0\n' > "$INST/nut/bin/usbhid-ups"; chmod +x "$INST/nut/bin/usbhid-ups"
printf '#!/bin/sh\nexit 0\n' > "$INST/nut/sbin/upsd"; chmod +x "$INST/nut/sbin/upsd"
INSTALL_ENV="PATH=$INST/bin:/usr/bin:/bin RUB_BREW=$INST/bin/brew RUB_PREFIX=$INST/prefix RUB_LAUNCHD_DIR=$INST/ld RUB_SERVICE_USER=$(id -un) RUB_PYTHON=$RAIZ/.venv/bin/python RUB_SKIP_HEALTH=1 RUB_NUT_PREFIX=$INST/nut RUB_NUT_ETC=$INST/nutetc RUB_API_PORT=35991 RUB_STATE_DIR=$INST/state"

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

# S9k — a leitura do River é do SERVIÇO, e o instalador não deixa LaunchDaemon de NUT.
# Medido em 2026-09-04: agente do usuário não sobe sem alguém logado (o mini
# ficou uma hora sem vigia depois de um reinício). Quem lança o leitor e o
# servidor é o supervisor do serviço (o servidor com nome próprio no `exec -a`;
# o leitor com o nome de fábrica, que o NUT exige — S65); aqui a cena confere que
# NENHUM plist de NUT sobra e que a configuração do dono fica intocada.
# A configuração só é escrita quando falta: o segundo install NÃO a reescreve.
echo "# marca do dono" >> "$INST/nutetc/ups.conf" 2>/dev/null || echo "# marca do dono" > "$INST/nutetc/ups.conf"
env $INSTALL_ENV "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9k.log 2>&1
# Quem mantém o driver no ar é o SERVIÇO (nut_supervisor.py), não o launchd: o
# instalador escreve a configuração, apaga registros antigos e não deixa nenhum
# LaunchDaemon de NUT para trás — dois donos do mesmo cabo seria pior que nenhum.
if [ ! -f "$INST/ld/com.river.nut-driver.plist" ] \
   && [ ! -f "$INST/ld/com.river.nut-upsd.plist" ] \
   && grep -q "^# marca do dono$" "$INST/nutetc/ups.conf" \
   && [ -f "$INST/nutetc/upsd.users" ] \
   && [ -f "$INST/ld/com.river.unifi-bridge.plist" ]; then
    ok "S9k leitura do River: configuração escrita, nenhum LaunchDaemon de NUT, config do dono intocada"
else
    erro "S9k leitura do River: sobrou registro de NUT ou a configuração mudou — cauda:"
    tail -5 /tmp/gate_inst_9k.log; ls -1 "$INST/ld" 2>/dev/null | head -5
fi

# S9m — a conta com que o SERVIÇO manda no aparelho existe, e a senha guardada
# para ele é a MESMA da conta. Sem isto, as ações do aplicativo (lembrete de
# bateria baixa, desligar o River) recebiam "acesso negado" do próprio servidor,
# ou pior: eram tentadas com senha vazia. A ficha é 0600 porque é uma senha.
# Refutada em 2026-09-04: com a gravação da ficha desligada, a cena fica vermelha.
S9M_SENHA="$(awk '/^\[riverbridge\]/{d=1;next} /^\[/{d=0} d && $1=="password"{print $3; exit}' "$INST/nutetc/upsd.users" 2>/dev/null)"
S9M_FICHA="$(cat "$INST/state/nut-admin.token" 2>/dev/null)"
S9M_MODO="$(stat -f '%Lp' "$INST/state/nut-admin.token" 2>/dev/null)"
if [ -n "$S9M_SENHA" ] && [ "$S9M_SENHA" = "$S9M_FICHA" ] && [ "$S9M_MODO" = "600" ] \
   && grep -q '^    actions = SET$' "$INST/nutetc/upsd.users" \
   && [ "$(grep -c '^\[riverbridge\]$' "$INST/nutetc/upsd.users")" = "1" ]; then
    ok "S9m conta do aparelho: criada uma vez, senha e ficha 0600 concordando"
else
    erro "S9m conta do aparelho: conta=${S9M_SENHA:+ok} ficha=${S9M_FICHA:+ok} modo=${S9M_MODO:-ausente} seções=$(grep -c '^\[riverbridge\]$' "$INST/nutetc/upsd.users" 2>/dev/null)"
fi

# S9m2 — a conta do Home Assistant existe, com a permissão de mandar ordens e com
# a senha guardada numa ficha 0600 (é ela que a tela mostra ao dono). Medido no
# código do Home Assistant em 2026-09-05: sem usuário e senha, a integração NUT
# dele nem chega a perguntar quais comandos existem — a conta sem `instcmds`
# acompanharia o River e não ofereceria ordem nenhuma.
S9M2_SENHA="$(awk '/^\[homeassistant\]/{d=1;next} /^\[/{d=0} d && $1=="password"{print $3; exit}' "$INST/nutetc/upsd.users" 2>/dev/null)"
S9M2_FICHA="$(cat "$INST/state/nut-homeassistant.token" 2>/dev/null)"
S9M2_MODO="$(stat -f '%Lp' "$INST/state/nut-homeassistant.token" 2>/dev/null)"
S9M2_CMD="$(awk '/^\[homeassistant\]/{d=1;next} /^\[/{d=0} d && $1=="instcmds"{print $3; exit}' "$INST/nutetc/upsd.users" 2>/dev/null)"
if [ -n "$S9M2_SENHA" ] && [ "$S9M2_SENHA" = "$S9M2_FICHA" ] && [ "$S9M2_MODO" = "600" ] \
   && [ "$S9M2_CMD" = "ALL" ] && [ "$S9M2_SENHA" != "$S9M_SENHA" ] \
   && [ "$(grep -c '^\[homeassistant\]$' "$INST/nutetc/upsd.users")" = "1" ]; then
    ok "S9m2 conta do Home Assistant: criada uma vez, com ordens permitidas, senha própria em ficha 0600"
else
    erro "S9m2 conta do Home Assistant: conta=${S9M2_SENHA:+ok} ficha=${S9M2_FICHA:+ok} modo=${S9M2_MODO:-ausente} instcmds=${S9M2_CMD:-ausente} seções=$(grep -c '^\[homeassistant\]$' "$INST/nutetc/upsd.users" 2>/dev/null)"
fi

# S9b — guarda pré-atualização (D12, 2026-09-03)# S9b — guarda pré-atualização (D12, 2026-09-03): serviço carregado + uma
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
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" RUB_SKIP_HEALTH=0 RUB_API_PORT=35997 "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9e.log 2>&1
RC9E=$?
kill "$OUVINTE_PID" 2>/dev/null; wait "$OUVINTE_PID" 2>/dev/null
if [ "$RC9E" = "3" ] && grep -q "^✖ a porta 35997 já está em uso por outro programa" /tmp/gate_inst_9e.log \
   && grep -q "^#  porta 35997: PID $OUVINTE_PID" /tmp/gate_inst_9e.log && grep -q "^# marca S9e$" "$MARCA"; then
    ok "S9e programa alheio na porta → recusa 3 antes de tocar no código, frase humana + PID só no registro"
else
    erro "S9e programa alheio na porta: rc=$RC9E marca=$(grep -c '^# marca S9e$' "$MARCA") — cauda:"; tail -3 /tmp/gate_inst_9e.log
fi
# resincroniza o código (a marca some) para a S9f ver "código igual"
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" RUB_API_PORT=35997 "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9e2.log 2>&1 || true

# S9f — nada mudou, job "carregado" (stub) mas NINGUÉM na porta: o instalador
# relança (kickstart) e, sem daemon real, a prova falha em 15 s com a frase
# humana — nunca "já instalado" com o serviço morto (revisão fria, 2026-09-03:
# a parada deliberada sai 0 e o KeepAlive não relança).
rm -f "$INST/ld/.kicks"
env $INSTALL_ENV RUB_STATE_DIR="$INST/state" RUB_SKIP_HEALTH=0 RUB_API_PORT=35997 "$RAIZ/scripts/install.sh" --consent-homebrew >/tmp/gate_inst_9f.log 2>&1
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
G9_ENV="PATH=$G9/bin:/usr/bin:/bin:/usr/sbin:/sbin RUB_BREW=$G9/bin/brew RUB_PREFIX=$G9/prefix RUB_LAUNCHD_DIR=$G9/ld RUB_LAUNCHD_DOMAIN=gui/$(id -u) RUB_SERVICE_USER=$(id -un) RUB_PYTHON=$RAIZ/.venv/bin/python RUB_STATE_DIR=$G9/state RUB_LOG_FILE=$G9/daemon.log RUB_NUT_PREFIX=$G9/nut RUB_NUT_ETC=$G9/nutetc"
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
( cd "$G9" && env RUB_STATE_DIR="$G9/state" RUB_NUT_ETC="$G9/nutetc" RUB_NUT_PREFIX="$G9/nut" RUB_NUT_STATE="$G9/nutstate" PYTHONPATH="$G9/prefix/src" HOME="$HOME" "$G9/prefix/venv/bin/python" -m river_unifi_bridge.service --env "$G9/prefix/etc/bridge.env" >"$G9/manual.log" 2>&1 ) &
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
( cd "$G9" && env RUB_STATE_DIR="$G9/state" RUB_NUT_ETC="$G9/nutetc" RUB_NUT_PREFIX="$G9/nut" RUB_NUT_STATE="$G9/nutstate" PYTHONPATH="$G9/prefix/src" HOME="$HOME" "$G9/prefix/venv/bin/python" -m river_unifi_bridge.service --env "$G9/prefix/etc/bridge.env" >"$G9/manual2.log" 2>&1 ) &
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
H9_ENV="PATH=$H9/bin:/usr/bin:/bin:/usr/sbin:/sbin RUB_SUDO= RUB_BREW=$H9/bin/brew RUB_PREFIX=$H9/prefix RUB_LAUNCHD_DIR=$H9/ld RUB_LAUNCHD_DOMAIN=gui/$(id -u) RUB_STATE_DIR=$H9/state RUB_CACHE_DIR=$H9/cache RUB_LOG_FILE=$H9/daemon.log RUB_PYTHON=$RAIZ/.venv/bin/python NO_COLOR=1 LANG=pt_BR.UTF-8 RUB_NUT_PREFIX=$H9/nut RUB_NUT_ETC=$H9/nutetc"
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
RC_UN=$?
# O código de saída ENTRA na cena: a desinstalação recusava a ficha da senha do
# aparelho (fora do prefixo) e saía 1, deixando a senha no disco — e a cena, que
# só olhava arquivos do prefixo, continuava verde (revisão fria da 0.5.0).
if [ "$RC_UN" = "0" ] && [ -f "$INST/prefix/arquivo-do-dono.txt" ] \
   && [ ! -d "$INST/prefix/src" ] && [ ! -d "$INST/prefix/venv" ] \
   && [ ! -e "$INST/prefix/scripts" ] \
   && [ ! -e "$INST/state/nut-admin.token" ] \
   && [ ! -f "$INST/ld/com.river.unifi-bridge.plist" ] \
   && [ ! -f "$INST/ld/.carregado" ]; then
    ok "S10 uninstall (cópia instalada): saiu 0, levou o nosso (ficha da senha inclusive), deixou o alheio"
else
    erro "S10 uninstall — rc=$RC_UN, estado final inesperado:"; find "$INST/prefix" "$INST/ld" "$INST/state" 2>/dev/null | head -8
    tail -3 /tmp/gate_inst_un.log
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
mkdir -p "$OL/bin" "$OL/ld" "$OL/prefix" "$OL/state" "$OL/cache" "$OL/apps" "$OL/nut/bin" "$OL/nut/sbin" "$OL/nutetc"
printf '#!/bin/sh\nexit 0\n' > "$OL/nut/bin/usbhid-ups"; chmod +x "$OL/nut/bin/usbhid-ups"
printf '#!/bin/sh\nexit 0\n' > "$OL/nut/sbin/upsd"; chmod +x "$OL/nut/sbin/upsd"
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
OL_ENV="PATH=$OL/bin:/usr/bin:/bin RUB_BREW=$OL/bin/brew RUB_PREFIX=$OL/prefix RUB_LAUNCHD_DIR=$OL/ld RUB_SERVICE_USER=$(id -un) RUB_PYTHON=$PY RUB_SUDO= RUB_STATE_DIR=$OL/state RUB_CACHE_DIR=$OL/cache RUB_APP_DEST=$OL/apps/app RUB_SKIP_HEALTH=1 RUB_API_PORT=35992 RUB_NUT_PREFIX=$OL/nut RUB_NUT_ETC=$OL/nutetc NO_COLOR=1"
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
mkdir -p "$OL3/nut/bin" "$OL3/nut/sbin"
printf '#!/bin/sh\nexit 0\n' > "$OL3/nut/bin/usbhid-ups"; chmod +x "$OL3/nut/bin/usbhid-ups"
printf '#!/bin/sh\nexit 0\n' > "$OL3/nut/sbin/upsd"; chmod +x "$OL3/nut/sbin/upsd"
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
    mkdir -p "$OL3/$1/ld" "$OL3/$1/prefix" "$OL3/$1/state" "$OL3/$1/cache" "$OL3/$1/apps" "$OL3/$1/nutetc"
    printf 'PATH=%s/bin:/usr/bin:/bin RUB_BREW=%s/bin/brew RUB_PREFIX=%s/%s/prefix RUB_LAUNCHD_DIR=%s/%s/ld RUB_SERVICE_USER=%s RUB_PYTHON=%s RUB_SUDO= RUB_STATE_DIR=%s/%s/state RUB_CACHE_DIR=%s/%s/cache RUB_APP_DEST=%s/%s/apps/app RUB_SKIP_HEALTH=1 RUB_API_PORT=35993 RUB_NUT_PREFIX=%s/nut RUB_NUT_ETC=%s/%s/nutetc NO_COLOR=1' \
        "$OL3" "$OL3" "$OL3" "$1" "$OL3" "$1" "$(id -un)" "$PY" "$OL3" "$1" "$OL3" "$1" "$OL3" "$1" "$OL3" "$OL3" "$1"
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
# `UDR7_ARM_ALLOWED=1`, e não a chave nua: desde a 0.8.0 a chave é o que o app
# grava pelo PUT (interruptor em Ajustes › Travas) e vive numa constante; o
# jargão é a frase "=1 no arquivo", que mandava o dono editar o arquivo.
JARG_TERMOS="UDR7_ARM_ALLOWED=1|known_hosts|upsc device.serial|(202)"
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
    /usr/bin/grep -rnE 'UDR7_ARM_ALLOWED=1|known_hosts|upsc device\.serial|\(202\)|\.serviceDown\("' "$JARG_DIR" | head -10
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

# S54 — nenhum daemon lançado À MÃO por este portão sobe sem as costuras que o
# prendem à pasta da cena. Sem elas ele escreve na instalação REAL de quem roda o
# portão — foi o que a cena S9g.2 fez em 2026-09-05, criando ups.conf, upsd.conf,
# nut.conf e upsd.users em /opt/homebrew/etc/nut. A S22 abaixo pega o RASTRO;
# esta pega a FORMA, antes de o rastro existir.
S54_FORA=0
while IFS= read -r linha; do
    for costura in RUB_STATE_DIR RUB_NUT_ETC RUB_NUT_PREFIX RUB_NUT_STATE; do
        case "$linha" in *"$costura="*) ;; *) S54_FORA=$((S54_FORA + 1)) ;; esac
    done
done <<EOF
$(grep -n -- '-m river_unifi_bridge.service' "$0" | grep -v cena_mutacao)
EOF
if [ "$S54_FORA" = "0" ]; then
    ok "S54 todo daemon do portão sobe preso à pasta da cena (estado, config e soquetes do NUT)"
else
    erro "S54 daemon lançado sem costura: $S54_FORA ausência(s) — escreveria na instalação real"
fi

# S22 — o gate não pode deixar rastro na configuração REAL do NUT desta máquina.
# Sem esta cena, uma cena nova sem o seam do NUT escreve em /opt/homebrew/etc/nut
# e ninguém percebe (foi o que aconteceu em 2026-09-04, no MacBook do dono).
if [ "$(impressao_nut_real)" = "$NUT_REAL_ANTES" ]; then
    ok "S22 configuração real do NUT desta máquina intocada pelo gate"
else
    erro "S22 o gate MEXEU em $NUT_REAL_ETC — alguma cena está sem RUB_NUT_ETC:"
    ls -1 "$NUT_REAL_ETC" 2>/dev/null | grep -v sample | head -5
fi

# S23 — mesmo princípio para o diretório de estado do dono: o instalador passou a
# escrever ali a ficha da conta que manda no aparelho, e uma cena sem o seam
# deixaria essa senha na máquina de quem roda o portão.
if [ "$(impressao_estado_real)" = "$ESTADO_REAL_ANTES" ]; then
    ok "S23 diretório de estado real do dono intocado pelo gate"
else
    erro "S23 o gate MEXEU em $ESTADO_REAL — alguma cena está sem RUB_STATE_DIR:"
    ls -1 "$ESTADO_REAL" 2>/dev/null | head -5
fi

# S24 — e o mesmo para os soquetes dos drivers do NUT. Desde a 0.7.0 a ponte cria
# aparelhos ali; uma cena sem o seam deixaria um aparelho fantasma na instalação
# real de quem roda o portão, e o servidor do dono passaria a servi-lo.
if [ "$(impressao_nut_state)" = "$NUT_STATE_ANTES" ]; then
    ok "S24 soquetes reais do NUT desta máquina intocados pelo gate"
else
    erro "S24 o gate MEXEU em $NUT_REAL_STATE — alguma cena está sem RUB_NUT_STATE:"
    ls -1 "$NUT_REAL_STATE" 2>/dev/null | head -5
fi

# S44 — o empacotador não pode voltar a duas formas que já falharam, as duas
# medidas em 2026-09-05. Esta cena confere o TEXTO do empacotador, não uma
# execução: montar o pacote leva minuto e meio e baixa o Python, e o portão roda
# a cada mudança. A execução de verdade é o próprio `build-app.sh`, que falha
# sozinho quando alguma das duas quebra.
#   1. o pip compilando `.pyc` dentro do pacote — arquivo que entra depois da
#      assinatura e a quebra;
#   2. a prova de arranque comparando com o Info.plist em vez de uma marca tirada
#      na hora — assim ela acusava 645 arquivos do próprio empacotamento como se
#      fossem do serviço, e deixaria passar os que o serviço deixasse de verdade.
S44_FALHOU=""
grep -q 'pip -q install --no-compile' "$RAIZ/tools/build-app.sh" \
  || S44_FALHOU="o pip voltou a compilar .pyc dentro do pacote"
grep -q 'find "\$APP" -newer "\$MARCA"' "$RAIZ/tools/build-app.sh" \
  || S44_FALHOU="${S44_FALHOU:-a prova de arranque não usa uma marca tirada na hora}"
grep -q 'Info.plist" | wc -l' "$RAIZ/tools/build-app.sh" \
  && S44_FALHOU="${S44_FALHOU:-a prova de arranque voltou a comparar com o Info.plist}"
if [ -z "$S44_FALHOU" ]; then
    ok "S44 empacotador: sem .pyc do pip, e a prova de arranque com marca própria"
else
    erro "S44 empacotador: $S44_FALHOU"
fi

# S53 — os elementos comuns da tela têm UMA forma. Diálogo escrito à mão diverge
# sozinho: um destrutivo ganha confirmação e outro não, um aviso é laranja aqui e
# amarelo ali, e ninguém percebe porque não há com o que comparar. Medido em
# 2026-09-05: eram 6 diálogos à mão em 4 arquivos e nenhum componente de aviso.
S53_FONTES="$RAIZ/macos/RiverBridge/Sources"
S53_FORA="$(grep -rln 'confirmationDialog(\|\.alert(' "$S53_FONTES" 2>/dev/null \
            | grep -v 'DesignSystem.swift' \
            | xargs -I{} sh -c 'grep -q "^[^/]*confirmationDialog(\|^[^/]*\.alert(" "{}" && echo "{}"' 2>/dev/null)"
if [ -z "$S53_FORA" ] && [ -f "$S53_FONTES/RiverBridgeApp/DesignSystem.swift" ]; then
    ok "S53 telas: diálogo e aviso só na forma canônica (DesignSystem.swift)"
else
    erro "S53 telas: diálogo escrito fora da forma canônica em: $S53_FORA"
fi

# S55 — ZERO nome de cor e ZERO número de espaço soltos na tela. Medido em
# 2026-09-05, antes: 57 nomes de tinta em 12 arquivos e 94 espaçamentos
# numéricos, em treze valores diferentes. Isso não é um sistema — é a soma de
# decisões tomadas uma a uma, sem nada com que comparar. A paleta mora em
# Theme.swift e a escala em DesignSystem.swift; fora delas, nada.
S55_FONTES="$RAIZ/macos/RiverBridge/Sources"
s55_conta() {  # 1=padrão 2=arquivo a ignorar
  grep -rn "$1" "$S55_FONTES" 2>/dev/null | grep -v "$2" | grep -vc '^\s*//' || true
}
S55_COR="$(grep -rn '\.\(orange\|red\|green\|yellow\|blue\|teal\|gray\|mint\|purple\|indigo\)\b' \
           "$S55_FONTES" 2>/dev/null | grep -v 'Theme.swift' | grep -v '///' | grep -c . || true)"
S55_ESP="$(grep -rn 'spacing: [0-9]\|\.padding(\(\.[a-z]*, \)\?[0-9]\+)\|cornerRadius: [0-9]' \
           "$S55_FONTES" 2>/dev/null | grep -v 'DesignSystem.swift' | grep -c . || true)"
if [ "$S55_COR" = "0" ] && [ "$S55_ESP" = "0" ]; then
    ok "S55 telas: 0 cor solta (paleta em Theme.swift) e 0 espaço solto (escala em DesignSystem.swift)"
else
    erro "S55 telas: $S55_COR cor(es) e $S55_ESP espaço(s) fora da paleta/escala:"
    grep -rn '\.\(orange\|red\|green\|yellow\|blue\|teal\|gray\|mint\|purple\|indigo\)\b' \
      "$S55_FONTES" 2>/dev/null | grep -v 'Theme.swift' | grep -v '///' | head -4
    grep -rn 'spacing: [0-9]\|\.padding(\(\.[a-z]*, \)\?[0-9]\+)\|cornerRadius: [0-9]' \
      "$S55_FONTES" 2>/dev/null | grep -v 'DesignSystem.swift' | head -4
fi

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
