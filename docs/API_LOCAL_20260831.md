# Contrato da API local daemon ↔ UI (§7A.3) — 2026-08-31

Transporte: HTTP/1.1 em `127.0.0.1:${UI_API_PORT}` (default 35493). TLS e rate
limiting dispensados (exceções registradas na spec §15). Autenticação: header
`Authorization: Bearer <token>`, token em
`~/Library/Application Support/river-unifi-bridge/ui-api.token` (0600; nos testes,
diretório sobreposto por `RUB_STATE_DIR`). Sem token válido: `401`.

| Método | Rota | Resposta |
|---|---|---|
| GET | `/v1/state` | Snapshot §7.3. Sem leitura ainda: mesma forma com `null`s honestos e `power.state="UNKNOWN"` — nunca valores inventados. |
| GET | `/v1/events` | SSE (`text/event-stream`): frames `event: state` (snapshot a cada mudança) e `event: event` (POWER_LOSS, POWER_RESTORED, LOW_BATTERY, COMM_LOST, COMM_RESTORED). |
| GET | `/v1/events/log?from&to&types&limit` | Consulta do log persistido (SQLite), mais recente primeiro. `types` = lista separada por vírgula; `limit` 1..1000 (default 200). Linhas `{ts, type, detail}`. Faixa invertida ou limit fora: `400`. |
| DELETE | `/v1/events/log?from&to` | Remove eventos na faixa `[from, to]`. **`to` é obrigatório** (DELETE sem parâmetro jamais limpa o log; "tudo" = UI envia `to=now`). Resposta `{removidos: n}`. |
| GET | `/v1/history?metric&from&to&bucket` | Métricas: `charge`, `runtime`, `load`, `power_w`. Linhas `{ts, avg, min, max, n}` por bucket (segundos); só amostras não-nulas contam. Inclui `events` recentes. Métrica desconhecida: `400`. |
| GET | `/v1/health` | Cadeia: `usb` (`nao_observavel` até a Fase 1), `nut`, `bridge`, `unifi` (`pendente_fase_3`), `ha` (`nao_observavel`), `last_error`. |
| GET | `/v1/config` | Config efetiva (campos da allowlist §22). |
| PUT | `/v1/config` | Corpo `{CHAVE: valor}`. Validação pela MESMA allowlist do parser (§22); chave desconhecida ou fora de faixa: `400` nomeando a chave. Persiste no `.env` preservando comentários (backup `.bak`). Resposta: `{aplicadas_a_quente: [...], restart_required: bool}`. Quentes: POLL_INTERVAL, delays de alarme, LOW_BATTERY_PERCENT, HISTORY_RETENTION_DAYS. |
| POST | `/v1/service/restart` | `202` drenado; ~0,5 s depois o daemon sai com `exit(75)` → launchd (`KeepAlive={SuccessfulExit: false}`) relança. |
| GET | `/v1/version` | `{version}`. |

Cercas com teste de mutação no gate: bind constante em `127.0.0.1`
(`api.BIND_HOST`); allowlist do PUT; chmod 600 do token.
