# API local daemon ↔ app — contrato vivo (desde a 0.3.0)

Substitui `../API_LOCAL_20260831.md` (até a 0.2.0). Transporte: HTTP/1.1 em
`127.0.0.1:${UI_API_PORT}` (padrão 35493); `Authorization: Bearer <token>`, token em
`~/Library/Application Support/river-unifi-bridge/ui-api.token` (0600). Sem token válido: 401.
Recusas de negócio: `{"erro": "<mensagem>", "motivo": "<código>"}`.

## Rotas

| Método | Rota | O que faz |
|---|---|---|
| GET | `/v1/version` | `{"version": "0.3.0"}` |
| GET | `/v1/state` | snapshot corrente (nunca valores inventados; `null` honesto) |
| GET | `/v1/events` | SSE: `event: state` e `event: event` (bridge + eventos de dispositivo; estes levam `device` e `device_name` no payload) |
| GET | `/v1/events/log?from=&to=&types=&limit=&device=` | histórico persistido; `device` filtra pelo id da instância; cada linha traz `device` (`null` para eventos do bridge e para os gravados antes da 0.3.0) |
| GET | `/v1/health` | elos da cadeia + `plugins[]` (`id`, `type`, `name`, `state`, `detail`); o alias `udr7`/`udr7_detail` espelha a instância `udr7` e é **permanente** (o instalador o lê) |
| GET | `/v1/config` | as 33 chaves da allowlist, em minúsculas |
| PUT | `/v1/config` | validar → autorizar → gravar `.env` → aplicar a quente. Chaves `UDR7_*`/`PROTECT_*` (via legada, D10) são traduzidas para a instância `udr7` e gravadas nos dois; `UDR7_ARM_ALLOWED` → 400 `chave_somente_arquivo` |
| POST | `/v1/service/restart` | recusa 409 `armado` com qualquer instância armada |
| GET | `/v1/device-types` | catálogo: `{"types": [{id, label_pt, label_en, default_name, event_prefix, fields: [{name, type, default, required, bounds?, pattern?, enum?}]}]}` |
| GET | `/v1/devices` | `{"devices": [<instância>]}` |
| POST | `/v1/devices` | `{type, name, enabled?, dry_run?, fields?}` → 201 `{"device": <instância>}` |
| GET | `/v1/devices/{id}` | `{"device": <instância>}` |
| PUT | `/v1/devices/{id}` | `{name?, enabled?, dry_run?, fields?}` (tudo opcional; `type` e `id` imutáveis) → 200 `{"device": <instância>}` |
| DELETE | `/v1/devices/{id}` | 204; apaga `<id>_armed.json` e `<id>_runtime.json`, mantém `<id>_known_hosts` |

## A instância (`<instância>`)

```json
{"id": "sshhost_3fa9c1d2", "type": "ssh_host", "name": "NAS da sala",
 "enabled": false, "dry_run": true,
 "fields": {"ssh_host": "192.0.2.5", "ssh_port": 22, "ssh_user": "admin",
            "ssh_key": "/Users/x/.ssh/river-bridge-sshhost_3fa9c1d2",
            "shutdown_percent": 25, "discharge_seconds_per_pct": 0, "runtime_minutes": 0,
            "min_outage_seconds": 0, "confirm_seconds": 6, "retry_max": 3,
            "shutdown_command": "sudo -n shutdown -h now"},
 "created_at": "2026-09-03T00:00:00-0300", "updated_at": "2026-09-03T00:00:00-0300",
 "armed": false, "state": "desabilitado"}
```

Tipos: `udr7_ssh` (campos do motor SSH + `wol_mac`; eventos `UDR7_*`) e `ssh_host` (campos do
motor + `shutdown_command`, de lista fechada; eventos `SSH_HOST_*`). A série esperada e o corte do
River **não** são campos de instância: `UDR7_EXPECTED_SERIAL` e `UDR7_CUTOFF_PERCENT` em `/v1/config`.

## Recusas das rotas de dispositivos

| Status | `motivo` | Quando |
|---|---|---|
| 400 | `validacao` | campo fora da regra (`erro` nomeia o campo), `type`/`id` no PUT, campo desconhecido |
| 400 | `tipo_desconhecido` | POST com `type` fora do registro |
| 400 | `armar_no_post` | POST com `enabled: true` e `dry_run: false` (armar é ato separado, pelo PUT) |
| 404 | `dispositivo_ausente` | id inexistente |
| 409 | `nome_duplicado` | nome já usado (strip + casefold) |
| 409 | `armado` | PUT em campo congelado com a instância armada; DELETE de armada; reinício com alguma armada |
| 409 | `armamento_bloqueado` | armar com a trava fechada |
| 409 | `sem_snapshot` | armar sem leitura corrente do NUT |
| 409 | `fonte_nao_real` | armar com fonte sintética ou serial ≠ esperado |
| 501 | `sem_loja` | serviço rodando sem loja de instâncias (só em `--once`) |

Regras de armamento (qualquer tipo): armar = `enabled: true` + `dry_run: false`; exige trava
global aberta, snapshot com `comm_ok`, fonte não sintética e serial da leitura igual ao serial
esperado. Desarme puro (`dry_run: true` ou `enabled: false`) é sempre aceito. O nome pode mudar
com a instância armada; qualquer outro campo, não.

Fixtures partilhadas com o app: `tests/fixtures/device_types.json`, `devices_tres.json`,
`health_dispositivos.json` (o Swift as decodifica em `DeviceInstanceTests`).
