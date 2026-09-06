# 0.9.0 — a folha do River (tudo o que a serial entrega), o cartão da proteção sem apavorar, e Compartilhar… os registros

status: aceito
data: 2026-09-06 (aprovado pelo dono em 2026-09-06, após a 2.ª rodada da revisão fria)
supera (como arquivo de plano desta sessão): o plano da 0.8.0, cuja cópia canônica é `docs/plans/2026-09-05-1905-a-ux-determinada-inteira-0-8-0.md` (executado e fechado; bancada em `docs/plans/2026-09-05-2330-handoff-0-8-2-o-leitor-recusado-pelo-nut.md`).
frente: três ordens do dono em 2026-09-06 —
1. **B49** (proposta aprovada: *"De acordo com a proposta."*): *"Garanta que leiamos todos [os campos do r3pcomms] e proponha uma folha de detalhe"*; escopo confirmado por ele: tempo para carga completa, temperaturas separadas, capacidade de projeto, entrada solar/DC publicada; **sem** flags.
2. Cartão da proteção: *"Porque você gosta de apavorar na UX... que porra é alcance não verificado?"* → *"Inclua a correção proposta no plano"* (a proposta: etiqueta "Armada" + "ainda não passou por uma queda real"; some o aviso da trava aberta com proteção armada; margem em português; varredura de "arquivo do serviço"/"veja o guia").
3. *"uma feature para compartilhar os logs… que possa salvar e compartilhar em .csv compactado"* (captura: botão **Compartilhar…** com o ícone de partilha). Respostas dele (AskUserQuestion, 2026-09-06): pacote = **eventos + amostras (CSV) + diário do serviço**; lugar = **barra de Eventos, ao lado do recorte de tempo**.

## Context

**O que a porta serial entrega e o que lemos hoje** (`src/river_unifi_bridge/river_serial.py`, lido inteiro; quadro real de `tests/fixtures/river_serial_frame.hex` decodificado segmento a segmento em 2026-09-06):

| tipo | hoje | conteúdo (r3pcomms `_r3pcomms.py:176-262`, clonado e lido em 2026-09-06) | valor no quadro real |
|---|---|---|---|
| 3 | **não lido** | capacidade de projeto, `<I`, mAh | 12800 |
| 4 | só o 2.º byte | quatro temperaturas `<BBBB` °C; **[1] = bateria, [0] = sistema** (o arquivo de Home Assistant do autor, `doc/configuration.yaml:212,228`); [2] e [3] sem nome | (34, 34, 25, 25) |
| 7/8/9/12/14/16/17/18 | lidos | watts (float) | 110.6 / 110.6 / 110.6 / 0 / −110.6 / 0 / 0 / 0 |
| 12 | lido, **não publicado ao NUT** | entrada solar/DC (W) | 0.0 |
| 13 | não lido | `<L`/10, "Line Frequency?" (incerto no r3pcomms) | 60.0 |
| 15 | lido | frequência (`<HH`, 1.º) | 60 |
| 22 | lido | série | R631ZBBAWH270046 |
| 23 | **não lido** | tempo para carga completa, `<H` minutos; bytes `33 17` = "não está carregando" (r3pcomms `:245`) | bytes `33 17` (aparelho a 100 %) |
| 25 | não lido | "Model/Mfg. Batch/Date?" — incerto no próprio r3pcomms | `29010002` |

**Correção de crença minha (registrada aqui porque estava na proposta aprovada):** a proposta dizia *"firmware só se um comando HID próprio não disputar o cabo"*. **Não existe firmware em fonte nenhuma**: o r3pcomms não lê firmware nem pela serial nem pelo HID (`hid_get` lê carga %, tempo restante e flags — `_r3pcomms.py:329-376`); a linha "Version: 3.1.3" do README é a versão do programa deles (`__main__.py:35`). Firmware **sai** da folha, e a linha B49 do backlog é emendada com a data. Flags ficam fora por decisão do dono.

**O NUT (nomes lidos em `docs/nut-names.txt` do projeto NUT, baixado em 2026-09-06):** `battery.capacity.nominal` = "Nominal battery capacity (Ah)" (linha 693) → 12,8; `battery.temperature` (698) já publicada; `ups.temperature` = "UPS temperature" (228) — hoje repete a da bateria, passa a ser o sensor do sistema; **não há nome** para tempo-até-carga-completa nem para entrada solar/DC (`input.realpower` é a soma; não inventamos nome: "os nomes não são escolha nossa", `nut_publicacao.py`). Esses dois vão só à API e à tela.

**O cartão da proteção** (`macos/RiverBridge/Sources/RiverBridgeCore/DeviceStateText.swift:38`, `RiverBridgeApp/Plugins/Udr7/Udr7Plugin.swift:60-63`, `src/river_unifi_bridge/protect.py:545-562,573-585,631`): `armado_nao_verificado` é o estado de **toda instância armada sem desligamento em curso nesta queda** — `_state_for` (`protect.py:573-575`) devolve `enviado` só enquanto `_latched and _sent_this_outage`, e na restauração `_reset_outage()` (`:631` → `:585`) zera os dois e o estado **volta** a `armado_nao_verificado`. Ou seja: o nome não codifica histórico ("nunca houve queda") nem alcance; codifica "armada agora". A tela traduz ao pé da letra "alcance não verificado", **falso** — o alcance é provado pelo "Testar conexão" (`alcance_verificado: true` no mini, medido hoje). O histórico já está no cartão pela linha "último: …" (o último evento da instância). `lock_open` é emitido sempre que a trava está aberta (`protect.py:552`), inclusive armada, quando é o esperado; o texto ainda fala em "arquivo do serviço (veja o guia)", de antes da 0.8.0 (as travas são interruptores em Ajustes › Travas). `margin_unknown` = `udr7_discharge_seconds_per_pct <= 0`: a taxa de descarga só é medida numa queda real.

Revisão fria do plano, rodada 1 (2026-09-06): **três bloqueadores, todos de levantamento meu** — (B1) li o retorno padrão de `_state_for` e não o reset da restauração, e escrevi "ainda não passou por uma queda real" como significado do estado; (B2) classifiquei os acertos de `git grep "arquivo do serviço"` por nome de arquivo sem abrir a linha, e `SettingsView.swift:327-328` é uma **dica de tela** (`.comDica` → `.help`), não comentário; (B3) afirmei que `health_udr7.json` carregava o estado armado sem abrir o fixture (está em `fonte_nao_real`/`dry_run`). Classe do que faltou: **função inteira + fixture aberto**, não a linha que confirma a hipótese. Corrigidos abaixo; avisos W1–W5 incorporados.

**Registros hoje:** o serviço grava `samples(ts, state, charge, runtime, load, power_w)` e `events(ts, type, detail, device)` no SQLite (`history.py:18-33`), expostos só agregados (`/v1/history`) e como JSON (`/v1/events/log`); o diário `/Library/Logs/river-unifi-bridge.log` é `-rw-r--r-- root` (16 MB no mini, legível pelo app). O app não tem ShareLink nem exportação (grep vazio). O pacote do app **não é sandboxed** (sem entitlements em `tools/build-app.sh`), então `ditto -c -k` por `Process` é o zip do Finder.

Resultado pretendido: clicar no anel abre a folha do River com tudo o que ele publica; o cartão da proteção diz a verdade em português; "Compartilhar…" na barra de Eventos gera um `.zip` com `eventos.csv`, `amostras.csv` e `diario.log` e abre Salvar / a folha de compartilhar do macOS.

## Risk band

**high** — muda o contrato do estado (fixtures partilhadas Python↔Swift), publica variáveis novas no NUT (o Home Assistant as lê), toca a tela do anel e a barra de Eventos; nada muda no que desliga aparelhos. Regras: fixtures regenerados no mesmo commit, cada cerca refutada por mutante, bancada no mini medida no ato, revisão fria sobre o DIFF antes da release.

## Decisões (D)

| # | Decisão | Fundamento |
|---|---|---|
| D1 | **Leitor serial**: tipo 3 → `capacidade_projeto_mah` (`<I`); tipo 4 → `temperaturas_c` (quatro, `<BBBB`), `temperatura_c` = [1] (bateria, como hoje), `temperatura_sistema_c` = [0]; tipo 23 → `tempo_para_carga_min` (`<HH`, 1.ª metade; a 2.ª é 0 no quadro real e fica registrada, não publicada), `None` quando os 2 primeiros bytes são `33 17`; tipos 13 e 25 **não** entram (incertos no r3pcomms). **Grau de certeza do tipo 23, declarado:** a sentinela é leitura do r3pcomms (comentário com interrogação, `_r3pcomms.py:246`) **confirmada pelo nosso quadro real** (aparelho a 100 % na tomada, não carregando → bytes `33 17`); o valor em minutos com o aparelho carregando **não foi medido** por nós — é linha da bancada na primeira queda real (B42/B43). O cabeçalho do módulo e `api-local.md` dizem isso; a tela não carrega proveniência. | Tabela acima; fonte primária lida. `+ 0.0`/`None` seguem a regra "dado ausente não vira zero". O dono pediu o tempo para carga completa explicitamente; entra com a certeza declarada, não escondida. |
| D2 | **Estado (API/SSE)**: o bloco `outlets` (que já é "o que a serial publica": entrada, solar, frequência) ganha `design_capacity_mah`, `time_to_full_minutes`, `battery_temperature_c`, `system_temperature_c`, `temperatures_c` (lista de 4). `battery.temperature_c` continua alimentado por [1]. `_empty_state` não muda (`outlets: null`). Fixtures `state_online`/`state_nulls` inalterados no conteúdo (não têm `outlets`); o fixture de `outlets` em `docs/reference/api-local.md` e o teste `test_the_dict_that_goes_to_the_app` mudam. | Sem seção nova no §7.3; o Swift decodifica campos novos como opcionais (regra do `Models.swift`: "every telemetry field is Optional"). |
| D3 | **NUT**: `battery.capacity.nominal` = mAh/1000 com 1 casa; `ups.temperature` = sistema ([0]) e `battery.temperature` = bateria ([1]); nada para tempo-até-cheio nem solar. | nut-names 693/698/228; nome inventado o Home Assistant ignora e a casa proíbe. |
| D4 | **Folha do River** (`RiverBridgeApp/Dashboard/RiverDetailSheet.swift`, novo): abre ao clicar no anel (`Button(.plain)` em volta de `EnergyRing`, `.help("Detalhes do River")`, rótulo de acessibilidade), `.sheet(isPresented:)` na `EnergiaSection` com `hostSize` medido por `onGeometryChange` (o mesmo desenho de `SettingsView.swift:49,173`); tamanho `DeviceSheetMetrics.size(host:)`; cabeçalho (ícone `minus.plus.batteryblock.fill`, modelo, série), corpo rolável com quatro grupos e linhas rótulo/valor (variante estreita por `DeviceSheetMetrics.isNarrow`), rodapé só com **Fechar** (`.cancelAction`). Grupos e linhas (PT/EN em par): **Aparelho** — modelo, série, capacidade (mAh); **Potência** — entrada da rede, entrada solar/DC, tomada 120 V, saída 12 V, USB-A, USB-C, total; **Bateria** — nível, autonomia, tempo para carga completa ("—" quando não está carregando, com nota "só aparece enquanto carrega"), temperatura da bateria, temperatura do sistema; **Rede** — frequência, situação (na tomada/na bateria). Todo valor vem do `TelemetryStore` (formatadores puros, "—" quando ausente ou serviço parado, guarda `lendoAgora`). Zero cor/número solto (S55): só `Espaco`, `Raio`, `Cor`, `Theme`. Seam `--folha-river` abre a folha na partida para a captura. | Proposta aprovada pelo dono; moldura `DeviceSheetFrame` é de edição (Salvar/Remover) — a folha de leitura ganha moldura própria e mínima, com as mesmas métricas. |
| D5 | **Cartão da proteção**: `armado_nao_verificado` → etiqueta **"Armada"** / "Armed" (tom `.perigo`, "está armada de verdade", como a `ArmingRow`), **sem frase extra**: o serviço só sabe "armada agora"; o histórico continua na linha "último: …". `lock_open` só é mostrado quando a instância **não** está armada (regra: `enabled == true && dryRun == false` esconde — coincide com `ProtectionConfig.armed`, `protect.py:223-224`; numa instância barrada por portão com essa configuração o aviso também some, aceito e dito aqui) → "trava de armamento aberta — Ajustes › Travas". `margin_unknown` → "tempo entre o aviso e o corte ainda não medido (só numa queda real)"; `margin_short` → "tempo entre o aviso e o corte curto". Varredura da classe, **por linha aberta** (`git grep -n "arquivo do serviço\|veja o guia\|service file\|see the guide" -- macos/RiverBridge/Sources`): textos de tela a mudar — `DeviceSheetFrame.swift:204-207` (ArmingRow: "A trava de armamento está aberta (Ajustes › Travas)." / "…está fechada. Abra-a em Ajustes › Travas para armar."), `SshDeviceSheet.swift:487-488` ("Proteção ARMADA."), `Udr7Plugin.swift:60-61`, **`SettingsView.swift:327-328`** (dica ⓘ do desligar o River: "Só funciona com a trava aberta em Ajustes › Travas e com nenhuma proteção armada."); comentários que descrevem o passado (`ServicoGroup.swift:27`, `SettingsView.swift:384`, `TravaConfirmation.swift:6`, `ServicoDoSistema.swift:10`) ficam. Guia: `docs/guides/2026-09-03-1720-runbook-host-ssh.md:49` lista o selo velho → emenda datada. | Código lido inteiro (`_state_for` + `_reset_outage`); texto falso é defeito, não estilo. |
| D6 | **Compartilhar…**: o **serviço** exporta CSV (dono do SQLite e das colunas; módulo `csv` da biblioteca padrão): `GET /v1/events/log.csv?from&to` (colunas `ts_iso,ts,tipo,dispositivo,detalhe`, ordem cronológica, sem limite) e `GET /v1/history/samples.csv?from&to` (`ts_iso,ts,estado,carga_pct,autonomia_s,uso_pct,potencia_w`), `Content-Type: text/csv; charset=utf-8`, UTF-8 com BOM (Excel/Numbers abrem certo), `ts_iso` no fuso local do serviço; `web.StreamResponse` como já faz `_h_events` (`api.py:573`); a ficha (token) é o middleware `auth` (`api.py:179-186`), que cobre toda rota registrada — nenhuma chamada a `_authorize` (essa é a cadeia de recusas do `PUT /v1/config`). O **app** (`RiverBridgeCore/ExportacaoDeRegistros.swift`, puro e testável + `RiverBridgeApp/Dashboard/CompartilharRegistros.swift`): botão-menu **Compartilhar…** (`square.and.arrow.up`) na `EventsFilterBar`, à direita da cápsula do recorte, com dois itens — **Salvar como…** e **Compartilhar…**. **Ordem fixa em cada item:** ao clicar, o app monta o pacote (baixa os dois CSV, copia o diário quando legível, escreve `RiverBridge-registros-AAAA-MM-DD-HHMM/` em diretório temporário, roda `/usr/bin/ditto -c -k --sequesterRsrc --keepParent` → `.zip`), com o botão em estado "Preparando…" (`ProgressView`) enquanto isso; só com o `.zip` pronto: Salvar → `NSSavePanel` (nome sugerido) e move; Compartilhar → `NSSharingServicePicker(items: [url]).show(relativeTo:of:preferredEdge:)` ancorado ao botão (é o mesmo painel do ícone de partilha do Finder; `ShareLink` não serve porque exige o item no desenho, antes de existir). O recorte exportado é o da barra (Tudo → `from=0`). Falha de rede → a mesma frase de "Histórico indisponível"; diário ilegível → o zip vai sem ele e o rodapé diz. | Respostas do dono; `ditto -c -k` é o que o Finder usa ("Comprimir"); `NSSharingServicePicker` é a API AppKit do painel de partilha (doc primária lida ao implementar, citada no cabeçalho). CSV no serviço evita reimplementar escape de CSV em Swift. |
| D7 | Versão **0.9.0**. | Contrato de estado e rotas novas, folha nova, exportação nova. |

## Impact sweep (commands run now, 2026-09-06)

```
git status -sb; git log --oneline -1              # main, limpo, 88168e9 (0.8.7 publicada e instalada no mini)
tools/release.sh --check                          # v0.8.7 consistente nos 6 arquivos e no CHANGELOG
python decodifica tests/fixtures/river_serial_frame.hex   # tipos 2–25 acima; 3=12800; 4=(34,34,25,25); 23=bytes 33 17; 25=29010002
git clone greyltc/r3pcomms (scratchpad)          # _r3pcomms.py:176-262 segmentos; :329-376 hid_get (sem firmware); README:81 "Version" = programa
curl docs/nut-names.txt (NUT master)             # battery.capacity.nominal 693; battery.temperature 698; ups.temperature 228; sem tempo-até-cheio/solar
git grep -n "outlets" src tests macos docs        # model.py:105,153; service.py:232; nut_publicacao.py:80; Models.swift:31-44; TelemetryStore.swift:276-292; api-local.md:66-77; test_river_serial.py:37-44; test_service_loop.py:387-445; test_nut_publicacao.py:62-116
git grep -n "armado_nao_verificado"               # protect.py:75,575,795; plugins/udr7_ssh.py:81; DeviceStateText.swift:38; em tests/fixtures SÓ device_types.json (lista de estados) — nenhum fixture de health carrega o estado armado (health_udr7.json está em fonte_nao_real/dry_run) → fixture novo health_armado.json
sed -n 573,590p src/river_unifi_bridge/protect.py; sed -n 625,635p …   # _state_for: enviado só com _latched and _sent_this_outage; restauração → _reset_outage() zera os dois → volta a armado_nao_verificado
sed -n 320,330p macos/RiverBridge/Sources/RiverBridgeApp/Settings/SettingsView.swift   # :327-328 .comDica(...) "trava aberta no arquivo do serviço" — TEXTO DE TELA (comDica → .help, SettingsRows.swift:249-256)
sed -n 176,186p src/river_unifi_bridge/api.py     # middleware `auth` (ficha) cobre toda rota; `_authorize` (:121) é só a cadeia do PUT /v1/config
grep -n "armado_nao_verificado\|alcance não verificado" docs/guides/*.md   # runbook-host-ssh.md:49 lista o selo velho
git grep -n "arquivo do serviço\|veja o guia\|service file\|see the guide" macos/RiverBridge/Sources   # DeviceSheetFrame.swift:204-207; SshDeviceSheet.swift:487-488; Udr7Plugin.swift:60-61; comentários em ServicoGroup/SettingsView/TravaConfirmation/ServicoDoSistema (ficam)
git grep -n "alcance não verificado\|margem desconhecida" macos/RiverBridge/Tests tests docs   # nenhum teste fixa esses textos
grep -n "ShareLink\|fileExporter\|NSSavePanel\|ditto" macos/RiverBridge/Sources   # vazio (não existe exportação)
grep -n "entitlements\|sandbox" tools/build-app.sh   # vazio: o app não é sandboxed
ssh mini 'ls -la /Library/Logs/river-unifi-bridge.log'   # -rw-r--r-- root wheel 16138716 (legível por qualquer usuário)
grep -n "add_get\|add_put\|add_post" src/river_unifi_bridge/api.py   # rotas 187-210; _h_history 639; _h_events_log ~605
sed -n 18,33p src/river_unifi_bridge/history.py   # samples(ts,state,charge,runtime,load,power_w); events(ts,type,detail,device)
grep -o "^# S[0-9]*" tools/gate.sh | sort -V | tail -1   # S68 é a maior; novas: S69–S74
grep -n "func hoverLift" macos/RiverBridge/Sources    # Theme.swift:110 (o anel já reage ao hover — o clique é o passo natural)
grep -n "hostSize" macos/RiverBridge/Sources/RiverBridgeApp/Settings/SettingsView.swift   # :49 estado, :173 onGeometryChange (molde para a EnergiaSection)
cat .roadworthy/scope                             # escopo da 0.8.0 ainda ativo; substituído em C0 com motivo datado
```

## Changes, per file

**Serviço (Python)**
- `src/river_unifi_bridge/river_serial.py` — `_TIPO_CAPACIDADE = 3`, `_TIPO_TEMPO_PARA_CARGA = 23`, `_NAO_CARREGANDO = b"\x33\x17"`; `LeituraRiver` ganha `capacidade_projeto_mah: int | None`, `temperaturas_c: tuple[float, ...] | None`, `temperatura_sistema_c`, `tempo_para_carga_min: int | None`; `interpreta`: tipo 3 (`<I`, tamanho 4), tipo 4 guarda as quatro e deriva [1]/[0], tipo 23 (tamanho 4: sentinela → `None`, senão `<H`); `to_dict` acrescenta `design_capacity_mah`, `time_to_full_minutes`, `battery_temperature_c`, `system_temperature_c`, `temperatures_c`. Cabeçalho: tabela dos tipos com a fonte e a correção sobre firmware.
- `src/river_unifi_bridge/nut_publicacao.py` — `battery.capacity.nominal` (mAh/1000, 1 casa) de `tomadas.get("design_capacity_mah")`; `ups.temperature` passa a sair de `tomadas.get("system_temperature_c")` (ausente: continua `snap.temperature_c`, como hoje) — **`.get`, nunca colchete**: `tests/unit/test_nut_publicacao.py:19-22` monta `TOMADAS` sem as chaves novas e três testes passam por ali; cabeçalho: os dois nomes com a linha do nut-names e a decisão de não inventar nome.
- `tests/fixtures/health_armado.json` (**novo**) + `test_fixtures_contract.py::test_health_armado_fixture_matches_code` — uma instância `udr7` em `armado_nao_verificado`, `enabled: true`, `dry_run: false`, `source: "ok"`, `alcance_verificado: true`, `alcance_modelo`/`alcance_em` (a forma de `ssh_motor.status()`, `:240-242`, como `health_dispositivos.json:27-29`), `warnings: ["lock_open", "margin_unknown"]`, `last_event: "UDR7_ARMED"` — assim a captura mostra o cartão inteiro (o "fonte: …" só aparece com `source`, o "último: …" só com `last_event`: `Udr7Plugin.swift:40-46,67-69`). A lista `plugins` é escrita à mão, como no `health_udr7.json`; o contrato prova que `SharedState.health()` a publica tal qual (com o alias `udr7`/`udr7_detail`), não que `protect.py` a produz — o mesmo estatuto do fixture existente. Alimenta `--seam-health` na captura do cartão e o `ModelsDecodingTests` (Swift decodifica o mesmo arquivo).
- `src/river_unifi_bridge/history.py` — `export_samples_csv(ts_from, ts_to, escreve)` e `export_events_csv(ts_from, ts_to, escreve)`: geradores de linhas por `csv.writer`, ordem cronológica, `ts_iso` local (`datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds")`).
- `src/river_unifi_bridge/api.py` — rotas `GET /v1/events/log.csv` e `GET /v1/history/samples.csv` (a ficha vem do middleware `auth`, `api.py:179-186`, que cobre toda rota registrada — **não** chamar `_authorize`, que é a cadeia de recusas do `PUT /v1/config`; `from`/`to` inteiros, `to` opcional = agora; resposta `web.StreamResponse` `text/csv; charset=utf-8` com BOM; `Content-Disposition: attachment; filename=…`).
- `src/river_unifi_bridge/__init__.py`, `pyproject.toml` — 0.9.0.

**App (Swift)**
- `RiverBridgeCore/Models.swift` — `Outlets` ganha `designCapacityMah: Int?`, `timeToFullMinutes: Int?`, `batteryTemperatureC`, `systemTemperatureC`, `temperaturesC: [Double]?` (sem CodingKeys: `convertFromSnakeCase`).
- `RiverBridgeCore/TelemetryStore.swift` — `folhaDoRiver: FolhaDoRiver?` (struct pura em `RiverBridgeCore/FolhaDoRiver.swift`, novo): os quatro grupos como `[(rotulo, valor)]` já formatados, `nil` sem leitura viva; formatadores novos `mahText`, `celsiusText`, `minutesText` (puros, testados).
- `RiverBridgeCore/DeviceStateText.swift` — `armado_nao_verificado` → ("Armada"/"Armed", `.perigo`).
- `RiverBridgeApp/Plugins/Udr7/Udr7Plugin.swift` — detalhe: `lock_open` só quando **não** (`d.enabled == true && d.dryRun == false`) (`DeviceDetail` expõe `state`, `dryRun`, `enabled`: `Models.swift:104-106`); `margin_unknown`/`margin_short` em português; nenhuma frase nova para `armado_nao_verificado`.
- `RiverBridgeApp/Plugins/DeviceSheetFrame.swift` (ArmingRow), `RiverBridgeApp/Plugins/SshDeviceSheet.swift:487` e `RiverBridgeApp/Settings/SettingsView.swift:327-328` (dica ⓘ) — textos de D5.
- `RiverBridgeApp/Dashboard/RiverDetailSheet.swift` (**novo**) — a folha (D4). `RiverBridgeApp/Dashboard/FlowScene.swift` — o anel vira botão (`onOpenDetail` closure); `RiverBridgeApp/Dashboard/DashboardWindow.swift` (`EnergiaSection`) — `@State folhaDoRiver`, `hostSize` por `onGeometryChange` (a forma já usada em `DashboardWindow.swift:154,224`; em `SettingsView.swift:173` é `GeometryReader` + `onChange(of: geo.size)`), `.sheet`, seam `--folha-river`.
- `RiverBridgeCore/ExportacaoDeRegistros.swift` (**novo**, puro) — nome do pacote (`RiverBridge-registros-AAAA-MM-DD-HHMM`), lista de arquivos, o argv do `ditto`, e o texto do rodapé quando o diário não entrou. `RiverBridgeCore/APIClient.swift` — `eventsLogCSV(from:to:) -> Data`, `samplesCSV(from:to:) -> Data`.
- `RiverBridgeApp/Dashboard/CompartilharRegistros.swift` (**novo**) — o botão-menu com os dois itens, o trabalho assíncrono (baixar, copiar diário, `Process` ditto) com "Preparando…", e só então `NSSavePanel` ou `NSSharingServicePicker` ancorado ao botão (D6). `RiverBridgeApp/Dashboard/EventsTimeline.swift` (`EventsFilterBar`) — o botão à direita da cápsula, recebe `period`/`customFrom`/`customTo` que já tem (`@Binding`, `:335-337`).
- Testes Swift: `FolhaDoRiverTests` (formatadores; "—" sem leitura; tempo-até-cheio nulo quando não carrega), `ExportacaoDeRegistrosTests` (nome, argv do ditto, rodapé), `ModelsDecodingTests` (os campos novos de `outlets` decodificam de um JSON inline), `DeviceInstanceTests.everyStateTheServiceCanPublishHasABadge` (continua verde), teste do texto novo do badge.

**Gate, docs, config**
- `tools/gate.sh` — S69 (mutante: tipo 23 ignora a sentinela → `test_time_to_full_is_null_when_not_charging` reprova), S70 (mutante: temperatura do sistema lê [1] → `test_the_four_temperatures_and_their_names` reprova), S71 (mutante: `battery.capacity.nominal` publica mAh em vez de Ah → `test_capacity_comes_out_in_ah` reprova), S72 (mutante: CSV de eventos sem `device` → `test_events_csv_has_the_columns` reprova), S73 Swift (mutante: `DeviceStateText` volta a "alcance não verificado" → `oEstadoArmadoNaoAcusaAlcance` reprova), S74 Swift (mutante: `FolhaDoRiver` mostra "0 min" quando `timeToFullMinutes == nil` → `tempoParaCargaSemLeituraETraco` reprova).
- `docs/reference/api-local.md` — `outlets` com os campos novos (com o grau de certeza do tipo 23); as duas rotas CSV. `docs/BACKLOG_20260901.md` — B49 emendada (firmware não existe em fonte; flags fora por decisão do dono); B-novo: tipos 13/25 ficam sem leitura até fonte. `docs/guides/2026-09-05-2200-runbook-…` — §2 travas: confere que não manda fechar trava "no arquivo"; seção nova "Compartilhar os registros". `docs/guides/2026-09-03-1720-runbook-host-ssh.md:49` — emenda datada: o selo passa a "Armada". `CHANGELOG.md` `[0.9.0]`. `README.md` (uma linha na lista do que a tela mostra). Handoff vivo: §5b com a bancada. Este plano copiado para `docs/plans/2026-09-06-1215-a-folha-do-river-e-compartilhar-os-registros-0-9-0.md` em C0, com a revisão fria ao lado (`…-banca.md`), **e as duas linhas no mapa `docs/README.md`** (norma da casa).
- `.roadworthy/scope` — substituído (motivo datado).

## Scope
```
src/river_unifi_bridge/**
tests/**
tools/gate.sh
tools/build-app.sh
tools/build-dmg.sh
tools/release.sh
macos/RiverBridge/Sources/**
macos/RiverBridge/Tests/**
scripts/install.sh
scripts/uninstall.sh
river-bridge-install.sh
pyproject.toml
README.md
CHANGELOG.md
docs/**
.roadworthy/**
/Users/alessandro/.claude/plans/leia-todo-o-c-digo-prancy-sundae.md
/Users/alessandro/.claude/plans/leia-todo-o-c-digo-prancy-sundae.review.md
/Users/alessandro/.claude/projects/-Users-alessandro-Development-EcoFlow-UniFi-UPS-Bridge/memory/**
```

## Acceptance (EARS)
| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|---|---|---|---|
| 1 | o quadro real do fixture é interpretado | `capacidade_projeto_mah == 12800`, `temperaturas_c == (34,34,25,25)`, `temperatura_c == 34` (bateria, [1]), `temperatura_sistema_c == 34` ([0]), `tempo_para_carga_min is None` (bytes 33 17) | `test_river_serial.py::test_frame_from_the_real_device_decodes` (ampliado) | qualquer valor diferente |
| 2 | um quadro sintético traz tipo 23 = 90 min e tipo 4 = (21,30,25,25) | `tempo_para_carga_min == 90`, bateria 30, sistema 21 | `test_time_to_full_is_null_when_not_charging` + `test_the_four_temperatures_and_their_names` (quadros montados com `monta`+CRC, como os testes de corrupção já fazem) | valor errado ou índice trocado |
| 3 | a serial respondeu | `LIST VAR river-bridge` traz `battery.capacity.nominal 12.8`, `battery.temperature <[1]>`, `ups.temperature <[0]>`; sem serial, nenhuma das três muda de comportamento | `test_nut_publicacao.py::test_capacity_comes_out_in_ah`, `::test_the_two_temperatures_have_their_own_sensors`; mini: `printf 'LIST VAR river-bridge\n' \| nc 127.0.0.1 3493` | variável ausente ou em mAh |
| 4 | `GET /v1/state` com serial | `outlets` traz os cinco campos novos; `GET /v1/events/log.csv` e `/v1/history/samples.csv` respondem `text/csv` com cabeçalho e linhas cronológicas | `test_api.py::test_state_publishes_the_serial_details`, `::test_events_csv_has_the_columns`, `::test_samples_csv_has_the_columns`; mini: `curl … log.csv \| head -3` | campo ausente, ordem errada, sem BOM |
| 5 | o anel é clicado (ou `--folha-river`) | a folha abre dentro da janela (414×480 mínima inclusive) com os quatro grupos e "—" onde não há leitura; Fechar/Esc fecha | captura nesta máquina com `tools/captura-por-janela.sh` em PT e EN, lida em imagem; teste `FolhaDoRiverTests` | folha vaza da janela, número inventado, texto cortado |
| 6 | o serviço está parado | a folha (se aberta) mostra "—" em tudo e o botão Compartilhar… avisa "Histórico indisponível…" sem gerar arquivo | `FolhaDoRiverTests::semLeituraVivaTudoETraco`; teste de `CompartilharRegistros` com `APIClient` de mentira que falha | valor velho na tela; zip parcial sem aviso |
| 7 | Compartilhar… › Salvar… no recorte Tudo | um `.zip` com `eventos.csv`, `amostras.csv`, `diario.log`; `unzip -l` lista os três; o CSV abre no Numbers com acentos certos | mini: `--seam` não cabe (é ato de tela) → medido nesta máquina contra o serviço do mini por túnel ssh (`ssh -L 35493:127.0.0.1:35493` + ficha) OU no mini por `osascript` (Acessibilidade concedida); `unzip -l`; `file eventos.csv` = UTF-8 with BOM | arquivo faltando; diário ausente sem a nota |
| 8 | a instância está armada (`armado_nao_verificado`) | o cartão diz "Armada" e o detalhe traz fonte, margem em português e "último: …"; **sem** "alcance não verificado", **sem** "trava … arquivo do serviço", **sem** "trava aberta" (armada) | `oEstadoArmadoNaoAcusaAlcance` (Core) + captura da aba Saúde com `--seam-health tests/fixtures/health_armado.json` (fixture novo, gerado pelo código) lida em imagem; `git grep -n "arquivo do serviço\|veja o guia\|service file\|see the guide" -- macos/RiverBridge/Sources` só devolve linhas de comentário (`//`), conferidas uma a uma | texto velho em qualquer string de tela |
| 9 | o gate roda | verde (S15/B17 declarada), S69–S74 verdes; pytest, swift test, lychee | gates | qualquer vermelho fora de S15 |
| 10 | a 0.9.0 é publicada e instalada no mini | serviço 0.9.0 (ensaio ligado → reiniciar → desligado; UDR7 volta a armada), folha aberta pelo seam sem queda por 20 s, `LIST VAR` com as três variáveis, `log.csv` responde | bancada abaixo | qualquer passo diferente |

## Ordem de commits
| # | Commit | Cercas |
|---|---|---|
| C0 | plano em `docs/plans/`, revisão fria ao lado, `.roadworthy/scope` | — |
| C1 | serial: tipos 3/4/23 + `to_dict` + testes | S69, S70 |
| C2 | NUT e API: variáveis novas, `outlets` novo, api-local | S71 |
| C3 | CSV: `history.py` + duas rotas + testes | S72 |
| C4 | app: modelos, `FolhaDoRiver`, folha, anel clicável, seam, testes | S74 |
| C5 | app: cartão da proteção e varredura dos textos | S73 |
| C6 | app: Compartilhar… (Core puro + tela + APIClient) | — (teste do Core) |
| — | **revisão fria sobre o diff C1–C6**; bloqueadores corrigidos | — |
| C7 | capturas lidas (folha PT/EN, 414 pt, Saúde, barra de Eventos) e ajustes | — |
| C8 | CHANGELOG 0.9.0, versão nos 6 arquivos, docs, backlog, `tools/release.sh v0.9.0 --no-gate` após gate verde, push | — |
| C9 | bancada no mini + handoff §5b + memória; commit + push | — |

## Bancada no Mac mini (C9, por mim)
1. `curl` do DMG + `SHA256SUMS`; `spctl -t open`; `rm` + `cp -R` para `/Applications`; `xattr -dr`; `Info.plist` 0.9.0.
2. `PUT udr7 dry_run true` → `POST /v1/service/restart` → 12 s → health ok → `PUT dry_run false` → `udr7 armado_nao_verificado`.
3. `printf 'LIST VAR river-bridge\n' | nc` → `battery.capacity.nominal`, `battery.temperature`, `ups.temperature` (valores diferentes entre si quando o quadro os traz); `GET /v1/state` → `outlets` com os cinco campos; `time_to_full_minutes` **null** esperado (aparelho a 100 % na tomada) — valor real só numa carga após queda (B42/B43, do dono).
4. `curl …/v1/events/log.csv?from=0 | head -3`; `…/samples.csv | wc -l`.
5. `open -a "River Bridge" --args --folha-river` → 20 s vivo, sem relatório de queda novo; `--secao saude` idem.
6. Compartilhar…: pelo `osascript` (clicar o botão e Salvar em `~/Desktop`) → `unzip -l`; senão, o mesmo nesta máquina por túnel, registrado como tal.

## Verification (after the last commit)
- `tools/gate.sh` (GATE_SKIP_XCODEBUILD=1) → todas verdes, S15 declarada; `.venv/bin/pytest`; `cd macos/RiverBridge && swift test` (3 vezes, idioma global); `lychee --offline --root-dir . docs/`; `tools/release.sh --check` → 0.9.0; `gh release view v0.9.0`; bancada C9 colada no handoff.

## Refutation
- S69 `river_serial.py`: mutante `if dados[:2] == _NAO_CARREGANDO` → `if False` → `test_time_to_full_is_null_when_not_charging` reprova (fixture real, bytes 33 17 → 5939 min viraria número).
- S70: mutante `temperatura_sistema_c = float(t[0])` → `t[1]` → `test_the_four_temperatures_and_their_names` reprova (quadro sintético 21/30).
- S71 `nut_publicacao.py`: mutante `/ 1000` removido → `test_capacity_comes_out_in_ah` reprova.
- S72 `history.py`: mutante tira a coluna `dispositivo` → `test_events_csv_has_the_columns` reprova.
- S73 Swift (`cena_mutacao_swift`): `DeviceStateText` `"Armada"` → `"Armada — alcance não verificado"` → `oEstadoArmadoNaoAcusaAlcance` reprova.
- S74 Swift: `FolhaDoRiver.minutesText(nil)` devolve `"0 min"` → `tempoParaCargaSemLeituraETraco` reprova.

## Out of scope
- Firmware (não existe em fonte) e flags (decisão do dono); tipos 13 e 25 (incertos no r3pcomms) — B-novo no backlog.
- Widget (B48) e BLE do segundo River (B39): frentes seguintes.
- Ligar/desligar tomadas (B35); energia acumulada (B34).
- Medir um valor real de tempo-até-carga-completa (exige o River abaixo de 100 % — só numa queda real ou no ato do dono).

## Overnight policy
- Decidido à noite, com fonte: nomes do NUT (nut-names.txt), índices das temperaturas (configuration.yaml do r3pcomms), colunas dos CSV, textos PT/EN (molde HIG já em uso), argv do ditto (`man ditto`).
- Reservado ao dono: push, release (publicação externa), qualquer ato no mini que instale/remova, ensaio↔armado no UDR7, e o julgamento visual final das capturas. Domínios reservados: `C8`, `C9`, `tools/release.sh`.

## Open questions
Nenhuma que bloqueie. Decisões do dono já colhidas (pacote e lugar do Compartilhar…).

Histórico da revisão fria (cold-reviewer, 2026-09-06):
- **Rodada 1: REJECTED** — B1 (o estado armado volta a `armado_nao_verificado` após a restauração; "ainda não passou por uma queda real" seria falso), B2 (dica de tela em `SettingsView.swift:327-328` classificada como comentário), B3 (nenhum fixture de health carrega o estado armado; a captura não provaria nada) + W1–W5 + 3 notas. Todos corrigidos acima: etiqueta "Armada" sem frase extra; a dica entra na varredura; fixture novo `health_armado.json` gerado pelo código; tipo 23 com o grau de certeza declarado; `.get` na publicação; `NSSharingServicePicker` depois do pacote pronto; guia do host SSH e mapa `docs/README.md` na lista; middleware `auth` nomeado certo; `onGeometryChange` vs `GeometryReader` corrigido; regra do `lock_open` explicitada.
- **Rodada 2: APPROVED** — zero bloqueadores; dois avisos mecânicos aplicados no ato (a linha do `api.py` ainda citava `_authorize`; o fixture `health_armado.json` ganha `source`, `last_event`, `alcance_modelo`, `alcance_em` para a captura mostrar o cartão inteiro) e duas notas (o fixture é escrito à mão como o `health_udr7`, o contrato prova a publicação, não a produção — dito acima; `Udr7Plugin.swift:60-61` para `lock_open`). O arquivo `.review.md` com `VERDICT: APPROVED`, `round: 2` e `sections-round1` nasce em C0.
Revisão fria do DIFF (C1–C6, cold-reviewer, 2026-09-06):
- **Rodada 1: REJECTED** — B1 (o caminho "serviço parado" do Compartilhar sem teste: o `APIClient` nascia dentro da tela), B2 (`store` carregado por três telas sem leitor), W1 (pasta temporária nunca apagada), W2 (CSV inteiro em memória, o plano prometia fluxo), notas (nota da carga sem serial; cenas S73/S74 entre o comentário e a chamada de S68). Corrigidos: o pacote nasce no Core com as dependências injetadas (falha de rede → nada no disco, testado), sem o `store`, pastas anteriores apagadas na exportação seguinte, CSV em fluxo com contrapressão — medido no mini no ato: 192.786 amostras em 5,6 dias (uma a cada 2,5 s), ≈ 65 bytes por linha → meio gigabyte na retenção máxima de 365 dias.
- **Rodada 2: REJECTED com um bloqueador a menos (2 → 1)** — B1 novo: cliente que desconecta no meio do CSV deixava a thread produtora presa num `put` sem leitor, com a conexão do SQLite aberta (medido pelo revisor: um worker do executor por desconexão). Resíduo mecânico do desenho já escolhido: o consumidor avisa a thread (`threading.Event`) e drena a fila no `finally`; teste `test_a_client_that_leaves_mid_csv_does_not_pin_a_thread` (6.000 linhas, lê 64 bytes e fecha; o contador de exportações em curso volta a zero) e cena S75 (mutante: o consumidor deixa de drenar). W1: falha do ditto/disco deixa de ser anunciada como falha de rede. Contagem de bloqueadores caiu; aplicado sem terceira rodada (regra 5 da casa).

