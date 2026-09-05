# API local daemon ↔ app — contrato vivo (desde a 0.3.0)

Substitui `../API_LOCAL_20260831.md` (até a 0.2.0). Transporte: HTTP/1.1 em
`127.0.0.1:${UI_API_PORT}` (padrão 35493); `Authorization: Bearer <token>`, token em
`~/Library/Application Support/river-unifi-bridge/ui-api.token` (0600). Sem token válido: 401.
Recusas de negócio: `{"erro": "<mensagem>", "motivo": "<código>"}`.

## Rotas

| Método | Rota | O que faz |
|---|---|---|
| GET | `/v1/version` | `{"version": "0.6.0"}` |
| GET | `/v1/state` | snapshot corrente (nunca valores inventados; `null` honesto) |
| GET | `/v1/events` | SSE: `event: state` e `event: event` (bridge + eventos de dispositivo; estes levam `device` e `device_name` no payload). Desde a 0.4.0 cada evento leva `seq`, um número que só cresce: o servidor entrega a partir do último `seq` enviado, então a fila cheia (100) deixou de congelar a entrega no centésimo evento, e o app usa o `seq` como identidade da linha |
| GET | `/v1/events/log?from=&to=&types=&limit=&device=` | histórico persistido; `device` filtra pelo id da instância; cada linha traz `device` (`null` para eventos do bridge e para os gravados antes da 0.3.0) |
| GET | `/v1/health` | elos da cadeia + `plugins[]` (`id`, `type`, `name`, `state`, `detail`); o alias `udr7`/`udr7_detail` espelha a instância `udr7` e é **permanente** (o instalador o lê). Desde a 0.4.0 a lista sai **desde o boot** e sobrevive à falha de leitura do UPS (ela é configuração, não telemetria), e há `last_tick_error`: erro de SOFTWARE no ciclo (um dispositivo que levantou exceção), separado de `last_error`, que é do NUT |
| GET | `/v1/config` | as 31 chaves da allowlist, em minúsculas (0.4.0: saíram `UNIFI_HOST`, `UNIFI_VERIFY_TLS`, `EMULATE_MODEL`, `READ_ONLY`, que não tinham consumidor — 33 → 29; entraram `RIVER_SERIAL_ENABLED` e `RIVER_SERIAL_PORT`, da leitura pela porta serial — 29 → 31; `.env` instalado com chave aposentada só gera aviso) |
| PUT | `/v1/config` | validar → autorizar → gravar `.env` → aplicar a quente. Chaves `UDR7_*`/`PROTECT_*` (via legada, D10) são traduzidas para a instância `udr7` e gravadas nos dois. Desde a 0.8.0 as três travas (`UDR7_ARM_ALLOWED`, `RIVER_POWEROFF_ALLOWED`, `DEVICE_CMD_ALLOWED`) são interruptores da tela e **aplicam a quente**; fechar a de armamento com uma instância armada → 409 `armado` (o antigo 400 `chave_somente_arquivo` deixou de existir) |
| GET | `/v1/nut/rede` | `{"aberta": <bool\|null>, "propria": <bool>}` — o servidor do no-break escuta na rede local? `aberta: null` (e `propria: false`) quando o `upsd.conf` não é o que o serviço escreveu |
| PUT | `/v1/nut/rede` | `{"aberta": true\|false}` → `{"aberta", "mudou", "servidor_reiniciado"}`. Reescreve só um `upsd.conf` nosso (`LISTEN 127.0.0.1 3493` ↔ `LISTEN 0.0.0.0 3493`) e reinicia **só o servidor**; arquivo do dono → 409 `configuracao_do_dono` |
| POST | `/v1/service/restart` | recusa 409 `armado` com qualquer instância armada; 503 `servidor_sem_laco` quando o servidor não tem laço para agendar a saída (antes era um `assert`, que virava 500 mudo) |
| DELETE | `/v1/events/log?from=&to=` | limpa o histórico gravado E a fila de eventos da memória, que é o que o SSE entrega a quem conecta — sem isso os eventos apagados voltavam na reconexão. `to` é obrigatório |
| GET | `/v1/device-types` | catálogo: `{"types": [{id, label_pt, label_en, default_name, event_prefix, fields: […], states: […]}]}`. `states` é o vocabulário FECHADO que a proteção publica em `state` (0.4.0): o app confere que sabe desenhar todos, porque estado sem selo apareceria como dispositivo bloqueado e sem explicação |
| GET | `/v1/devices` | `{"devices": [<instância>]}` |
| POST | `/v1/devices` | `{type, name, enabled?, dry_run?, fields?}` → 201 `{"device": <instância>}` |
| GET | `/v1/devices/{id}` | `{"device": <instância>}` |
| PUT | `/v1/devices/{id}` | `{name?, enabled?, dry_run?, fields?}` (tudo opcional; `type` e `id` imutáveis) → 200 `{"device": <instância>}` |
| DELETE | `/v1/devices/{id}` | 204; apaga `<id>_armed.json` e `<id>_runtime.json`, mantém `<id>_known_hosts` |
| POST | `/v1/devices/{id}/acesso/preparar` | o serviço cria a chave dele (se faltar) e registra a identidade do aparelho; devolve `chave_publica`, `impressao_da_chave` e `impressao_do_console`. **A chave privada não sai por rota nenhuma.** Identidade diferente da registrada → 409 `identidade_divergente`; para aceitar de propósito, `{"aceitar_identidade": true}` |
| POST | `/v1/devices/{id}/acesso/instalar` | `{"senha": "…"}` — usa a senha do console **uma vez** para instalar a chave e já testa. A senha não é gravada, não é registrada e não volta na resposta |
| POST | `/v1/devices/{id}/acesso/testar` | roda os comandos de leitura do tipo pelo **mesmo `ssh`** que executa o desligamento; devolve `{"alcance": bool, "resposta": {probe, model, firmware}}` e, quando alcança, grava a prova em `<id>_acesso.json` |
| POST | `/v1/devices/{id}/acesso/esquecer` | apaga chave, identidade e prova |
| GET | `/v1/river/cabo` | quem está com o River: `{"lendo": <bool\|null>, "pausado": <bool>, "motivo": <texto\|null>}`. `lendo: null` = este serviço não cuida do leitor |
| POST | `/v1/river/cabo` | **sem botão na tela desde a 0.8.0** (o cabo vai e volta sozinho com o aplicativo da EcoFlow); a rota fica como contrato para scripts e para as cercas. `{"acao": "liberar"\|"retomar"}` → o mesmo objeto. `liberar` para o leitor e o servidor do no-break, para que o aplicativo da EcoFlow consiga abrir o aparelho (a interface de no-break aceita **um** leitor por vez); `retomar` os traz de volta |
| POST | `/v1/river/desligar` | desliga o **próprio River**, cortando a energia de tudo o que está nele. Três cercas: `RIVER_POWEROFF_ALLOWED` aberta (interruptor em Ajustes › Travas, desde a 0.8.0), nenhuma proteção armada, e a confirmação da tela. A trava do próprio driver (`driver.flag.allow_killpower`) é aberta pelo tempo do comando e fechada num `finally` |
| PUT | `/v1/river/aparelho` | `{"battery_charge_low": 0..50}` → grava `battery.charge.low` no aparelho e **confere lendo de volta**; devolve `{"battery_charge_low": <valor lido de volta do aparelho>}`. É o "Low battery reminder" do aplicativo deles: medido no ato em 2026-09-04, o próprio driver o descreve como *"Remaining battery level when UPS switches to LB (percent)"* — é o nível em que o aparelho **avisa**, não o limite físico de descarga (esse fica no aplicativo deles, de 0 % a 100 %, e o no-break não o expõe) |

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

## Estado (`/v1/state`) — o que é nulo de verdade

Campo ausente na leitura sai `null`, nunca zero nem invenção. Antes da primeira leitura, o
estado vazio publica `low_battery` e `overload` como `null` (0.4.0; antes vinham `false`, o que
afirmava "não há alarme" sem ter lido nada).

Nem todo no-break publica tudo pelo perfil de no-break. O River 3 Plus manda carga, autonomia,
tensão e situação, e **não manda potência nem uso** por esse caminho (medido em 2026-09-04; ver
`../decisions/2026-09-04-0110-river-3-plus-o-que-o-cabo-entrega.md`).

### `outlets` — consumo por tomada (0.4.0)

Quando o aparelho tem uma segunda porta que publique consumo (o River 3 Plus tem: a porta
serial do mesmo cabo), o serviço a lê a cada ciclo e publica:

```json
"outlets": {"total_w": 110.6, "input_w": 110.6, "input_ac_w": 110.6,
            "input_solar_dc_w": 0.0, "ac_w": 110.6, "dc_w": 0.0,
            "usb_a_w": 0.0, "usb_c_w": 0.0, "line_frequency_hz": 60.0}
```

`outlets` é `null` quando ninguém respondeu — e aí `power.output_power_w` também é `null`, e a
tela mostra "—". `source.usb_cdc` diz se a leitura desta volta veio da porta serial. As duas
leituras convivem: o NUT segue na interface de no-break enquanto esta acontece.

Controlam isso `RIVER_SERIAL_ENABLED` (ligada por padrão) e `RIVER_SERIAL_PORT` (`auto`
procura a porta e só aceita o aparelho cuja série bate com a que o no-break informou).

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
| 409 | `alcance_nao_verificado` | armar sem prova recente (30 dias) de que o serviço alcança o aparelho. A prova é o "Testar conexão" da tela, que roda pelo mesmo caminho do comando que desliga |
| 409 | `identidade_divergente` | o aparelho apresentou identidade diferente da registrada |
| 502 | `senha_recusada` / `acesso_falhou` | o console recusou a senha, ou a preparação do acesso falhou |
| 409 | `sem_snapshot` | armar sem leitura corrente do NUT |
| 409 | `fonte_nao_real` | armar com fonte sintética ou serial ≠ esperado |
| 501 | `sem_loja` | serviço rodando sem loja de instâncias (só em `--once`) |
| 400 | `validacao` (em `/v1/config`) | valor **vazio** em chave numérica ou booleana: recusado com `"<CHAVE>: valor vazio"`. Antes o vazio era gravado a quente e o ciclo seguinte comparava texto com número, derrubando o serviço |
| 500 | `arquivo_env` | não foi possível gravar o arquivo de configuração do serviço; **nada foi aplicado** |

## Recusas das rotas do River (0.5.0)

| Status | `motivo` | Quando |
|---|---|---|
| 409 | `cabo_emprestado` | armar qualquer proteção com o River emprestado ao aplicativo da EcoFlow: sem ler bateria, armar é armar às cegas. **Desarmar continua sempre aceito** |
| 409 | `armado_emprestimo` | emprestar o cabo com alguma proteção armada (o serviço ficaria sem ver a queda) |
| 409 | `armado_desligamento` | desligar o River com alguma proteção armada (duas ordens de desligamento ao mesmo tempo) |
| 409 | `desligamento_bloqueado` | a trava do desligamento está fechada no arquivo do serviço |
| 409 | `sem_conta_do_aparelho` | o serviço não tem a conta que manda no aparelho (o instalador a cria em `upsd.users` e guarda a senha em `nut-admin.token`, 0600, no diretório de estado) |
| 501 | `sem_supervisor` | este serviço não cuida do leitor do River (`RIVER_NUT_MANAGED` desligada) |
| 502 | `aparelho_recusou` | o servidor do no-break respondeu recusa; `erro` traz o motivo em português |
| 502 | `sem_servidor` | não foi possível falar com o leitor do River |

Regras de armamento (qualquer tipo): armar = `enabled: true` + `dry_run: false`; exige trava
global aberta, snapshot com `comm_ok`, fonte não sintética e serial da leitura igual ao serial
esperado. Desarme puro (`dry_run: true` ou `enabled: false`) é sempre aceito. O nome pode mudar
com a instância armada; qualquer outro campo, não.

Fixtures partilhadas com o app: `tests/fixtures/device_types.json`, `devices_tres.json`,
`health_dispositivos.json` (o Swift as decodifica em `DeviceInstanceTests`).
