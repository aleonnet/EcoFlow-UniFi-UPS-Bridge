---
status: proposto
data: 2026-09-06
frente: B39 — o segundo River, lido por Bluetooth (0.11.0)
supera: —
---

# 0.11.0 — o segundo River por Bluetooth: o programa lê, o serviço publica

**Ordem do dono:** *"Excelente. Prossiga com as outras frentes"* (2026-09-06, depois da 0.10.0). A frente seguinte
no backlog era a B39: o River da sala, que não tem cabo no Mac mini, lido pelo rádio Bluetooth e publicado
como o River do escritório já é — na tela, no NUT e, por ele, no Home Assistant. **Aviso do dono (2026-09-06,
20h50):** o River da sala de 220 V foi devolvido; o de 127 V chega em 2026-09-07. A medição de alcance (M5) e a
bancada esperam o aparelho novo.

**Resultado pretendido:** em Ajustes › *Rivers por Bluetooth* o dono entra na conta EcoFlow uma vez, procura
o River da sala, dá-lhe um nome e liga "Ler por Bluetooth". A partir daí: um cartão dele na tela Energia
(carga, na tomada ou na bateria, entrada e saída em watts, "via Bluetooth · há 2 s"), um cartão na tela
Saúde, eventos de queda e restauração dele na linha do tempo, e um aparelho `river-ble-<série>` no servidor
do no-break para o Home Assistant. Nada disto mexe na proteção: o segundo River é **fonte de leitura**,
não alvo de desligamento.

## Context

### Estado da árvore em que este plano nasce (medido ao escrever a rodada 2)

`git log --oneline -1` ao gravar esta rodada → `496a3e7` (fecho da 0.10.1), sobre `7a090e8` (plano proposto, rodada 1),
`8d78433` (**0.10.1**: o widget entra pelo `NSExtensionMain`) e `816806e` (fecho da 0.10.0); `git status --porcelain`
vazio. **A 0.10.1 é uma release própria, publicada antes de C0** (v0.10.1 publicada às 21h10 e instalada no mini às
21h17 — `pluginkit` 0.10.1, serviço 0.10.1, UDR7 de volta a armado). C0 nasce sobre `496a3e7`. C0 desta frente começa sobre a árvore da 0.10.1 fechada — nunca sobre árvore suja (bloqueador B8 da
rodada 1: o plano dizia "limpo em 50642d3" com doze arquivos modificados).

### O que foi medido hoje (2026-09-06, 17h20–17h55), e é o que sustenta o desenho

| # | Medição (comando no *Impact sweep*) | Resultado | Consequência |
|---|---|---|---|
| M1 | Varredura BLE nesta máquina com o **Python do pacote** (`Contents/Resources/python/bin/python3`, 3.13.15) + `bleak` 3.0.2; saída guardada em `scratchpad/prova-ble/saida-local-30s.txt` (30 s; mtime do arquivo 18h00) | **dois River 3 Plus no ar**: `EF-R3P70046` série `R631ZBBAWH270046` (−47 dBm; é o do escritório, a mesma série do quadro serial `tests/fixtures/river_serial_frame.hex`) e `EF-R3PF0298` série `R631Z61AXJ1F0298` (−91 dBm; **o dono devolveu o River da sala de 220 V** — este pode ser ele ainda na casa, ou outro aparelho; a série do de 127 V só se conhece amanhã); ambos com prefixo `R631` e `flags=62` → cifra tipo 7 (ECDH) | o modelo é coberto pela biblioteca (`river3_plus.Device`, `SN_PREFIX = (R631, R634, R635)`) |
| M2 | O mesmo `import` antes de assinar as rodas | `ImportError … code signature … mapping process and mapped file (non-platform) have different Team IDs` | o Python do pacote tem *hardened runtime* com validação de biblioteca: **toda `.so` de roda tem de ser reassinada com o nosso Developer ID** — que é exatamente o que `tools/build-app.sh` já faz com `find … -name '*.so'` (`assinar_de_dentro_para_fora`); reassinadas, 194 Mach-O, a varredura rodou |
| M3 | A mesma varredura **no Mac mini, por ssh** (sem app responsável na sessão gráfica) | `BleakBluetoothNotAvailableError: Bluetooth is not authorized … DENIED_BY_UNKNOWN` | **o serviço (root, sem sessão) não pode ler o rádio**. Confirma a pesquisa da B39 com medição |
| M4 | Um app mínimo assinado com Developer ID e `NSBluetoothAlwaysUsageDescription`, aberto por `open`, cujo **filho** é o Python do pacote rodando a varredura (`prova-ble/`, saída `saida-1.txt`) — nesta máquina | `rc=0`, 23 aparelhos em 12,1 s; nenhum diálogo apareceu na captura de tela | o consentimento de Bluetooth é atribuído ao **processo responsável** (o app); o filho herda. É o caminho do desenho |
| M5 | O mesmo app-prova aberto **na sessão gráfica do mini** (`ssh … open`) | o filho ficou parado 923 s (diálogo de consentimento na tela do mini) até alguém permitir; depois varreu: `rc=0`, e nos 8 s e nos 30 s seguintes viu **só o River do escritório** (−35/−41 dBm) — `river-ble-prova/saida-8s.txt` e `saida.txt` no mini | o consentimento funciona no mini como aqui. O alcance ao River da sala **não foi medido**: o aparelho foi devolvido; mede-se com o de 127 V, amanhã |
| M6 | `eflib` (a biblioteca de `rabits/ha-ef-ble`, commit `ef02d81`, v1.1.1, 2026-09-04, Apache-2.0) copiada como pacote de topo e importada com o Python do pacote | `import ok`, 117 membros públicos em `river3_plus.Device`; **nenhum** `import homeassistant`; 100 arquivos, 16.588 linhas (956 K são os protobuf gerados). **`eflib/__init__.py` importa `bleak` e `.devices` na primeira linha útil** (`:5-10`): importar qualquer submódulo — `eflib.login` inclusive — exige `bleak` instalado (rodada 1, B4) | dá para embutir sem o Home Assistant; o venv de desenvolvimento precisa das mesmas dependências (D11) |
| M7 | Leitura de `eflib/connection.py` (`_run_auth`, `_ecdh_key_exchange`, `_get_key_info_req`, `_auto_authentication`, `_gen_session_key`) e `eflib/login.py` | a autenticação é ECDH (SECP160r1) + tabela embutida (`keydata.py`) + `md5(user_id + série)`. **O único segredo do dono é o User ID da conta EcoFlow**, obtido uma vez por `POST https://api.ecoflow.com/auth/login` (e-mail + senha, `login.py:44-70,121`, `EcoFlowLogin(session).login(identifier, password, region) → LoginResult(user_id)`) ou copiado do app da EcoFlow. Nenhuma *login key* em arquivo (isso era o `ef-ble-reverse`, não a integração) | a senha nunca é guardada: entra uma vez, sai o User ID |

Dependências (lidas no ato): `ha-ef-ble/pyproject.toml:10-17` pina `ecdsa~=0.19`, `protobuf~=6.30`,
`pycryptodome~=3.23` e lista `bleak` e `bleak-retry-connector` **sem pino**; `bleak>=3.0.2` vem do
`Requires-Dist` do `bleak-retry-connector` 4.7.0; no macOS o `bleak` puxa `pyobjc-core`,
`pyobjc-framework-corebluetooth`, `pyobjc-framework-libdispatch` (PyPI JSON, `requires_dist`);
`bluetooth-adapters` é só Linux. Instalado: **45 MB**, dos quais 16 MB são `PyObjCTest` (testes do PyObjC) e
10 MB `objc`.

### O que o repositório tem hoje, lido inteiro para este plano

- **O laço do serviço** (`service.py:358-619`): uma leitura do NUT por ciclo; na leitura boa a proteção decide
  primeiro, a serial completa, `shared.update_snapshot(snap.to_dict())`, `history.record_sample`,
  `ponte.atualizar(snap, plugins)` (`:555-565`); **na falha do NUT** (`:528-537`) só `_handle_poll_failure` e
  `ponte.marcar_sem_dados()` — `ponte.atualizar` **não** é chamado, e com ele nem `_declarar`. O dicionário do
  estado é `UpsSnapshot.to_dict()` (`model.py:132-171`) e é o que o SSE manda tal qual (`api.py:583-614`:
  `payload = snapshot or _empty_state(...)`; `_h_state` idem, `:577-581`). A tela decodifica cada campo como opcional.
- **A ponte do NUT** (`nut_servico.py`, lida inteira): `atualizar(snap, plugins)` (`:126-131`) publica o River,
  reconcilia os dispositivos e chama `_declarar(snap)` (`:133-160`), que **volta cedo** se `not self.ups_conf or
  self._river is None` e monta a descrição do River com `snap.model`; o servidor do no-break é reiniciado só
  quando a declaração muda (`nut_conf.atualizar` → `mudou`). `DATASTALE` quando o no-break cala
  (`marcar_sem_dados`). O nome do aparelho obedece a `NOME_DE_APARELHO` (`[A-Za-z0-9][A-Za-z0-9._-]{0,31}`);
  o soquete `/Library/Application Support/river-unifi-bridge/nut-state/river-bridge-river-ble-f0298` tem 86
  bytes ≤ `LIMITE_DO_CAMINHO` = 100 (`nut_driver.py:79,86`; pasta de estado do pacote em `build-app.sh:255,275`).
- **A cerca do espelho** (`config.py:276-300`, `recusa_do_vigia_espelho`): recusa `NUT_UPS` igual ao aparelho do
  River publicado por nós ou a um id de dispositivo protegido; chamada em `load_config` (só com o aparelho) e
  no boot (`service.py:384-387`, com `dispositivos={plugin.id}`) e no `PUT /v1/config`. **Não conhece
  `river-ble-*`** (rodada 1, B2).
- **O contrato de plugins** (`plugins/base.py`, `plugins/__init__.py`) é de **dispositivo protegido**: `observe`,
  `armed`, `authorize`, `apply_patch`, estados `ESTADOS` de `protect.py`, cartão "· proteção" na Saúde, chip por
  instância, `load.off` no NUT. Um River lido por rádio não desliga nada e não se arma: encaixá-lo ali seria
  contrato mentindo. **Fica fora do registro de tipos, de propósito** — módulo próprio, rotas próprias.
- **Os nomes do NUT** (`nut_publicacao.py`; a lista é `docs/nut-names.txt` **do projeto NUT**, baixada para o
  scratchpad em 2026-09-06 — não existe no nosso repositório): `ups.status`, `battery.charge`,
  `battery.runtime`, `battery.charge.low`, `battery.temperature`, `input.realpower`, `ups.realpower`,
  `outlet.n.*`, `device.*`; os 18 nomes de D6 existem lá.
- **O estado partilhado** (`state.py`): `_version` sobe em `update_snapshot`/`add_event`/`record_failure`; o SSE
  manda o estado a cada versão nova; `snapshot` é `None` até a primeira leitura boa (`:110-112`) e
  `_empty_state` publica `identity.serial: null` (`api.py:96`); `health()` é a cadeia + `plugins` + `cabo`.
- **A série do River do escritório** existe em três lugares, nenhum garantido: `identity.serial` do último
  estado bom (`None` antes da 1.ª leitura), `UDR7_EXPECTED_SERIAL` (`config.py`, default `""`), e o quadro
  serial. Nada a persiste (rodada 1, B3).
- **O vocabulário fechado de eventos** (`eventos.py`) e as duas cercas: `tests/fixtures/eventos.json` = o que o
  código declara (`test_o_arquivo_de_eventos_e_o_que_o_codigo_declara`), e o Swift prova ter frase para cada nome
  (`EventosContractTests.swift`, `DeviceTypeRegistry.qualquerEvento`). A varredura regex por `add_event(`/`record_event(`
  com nome em maiúsculas cobre `src/river_unifi_bridge/**/*.py` — **a `eflib` embutida não casa o padrão** (grep no ato: vazio).
  `history.record_event(event_type, detail, ts, device)` (`history.py:122-123`) já leva `device`.
- **Os chips da linha do tempo** (`DevicePlugins.swift:531-580`, `EventChipSpec`): `Kind` = `queda | restaurada |
  bateria | comunicacao | device(id:type:)`; `matches` do `.device` cai em `DeviceTypeRegistry.type(forEventType:)`;
  `all(devices:)` tem **quatro consumidores** (`EventsTimeline.swift:38`, `DashboardWindow.swift:215` e `:256`,
  `DeviceInstanceTests.swift:148,154,200` — `all(devices: []).count == 4`). O `BridgeEvent` do SSE
  (`Models.swift:151-163`) tem `device` e **não tem `detail`**; `DeviceNames.name(forEvent:)` devolve `""` para
  evento sem tipo de dispositivo (rodada 1, B7 e W2).
- **A remoção** (`remocao.apagar_tudo`, `:124-138`): apaga o diretório de estado **inteiro** por `listdir`.
- **O app**: `TelemetryStore.apply` (`TelemetryStore.swift:194-205`) faz `beat &+= 1` a **cada** estado aplicado;
  `refreshHealth` a cada 5 s; `AppPrefs` só guarda idioma e tema; **não há Keychain nem `Process` de longa
  duração**; `ReopenDelegate` (`RiverBridgeApp.swift:13-22`) não tem `applicationWillTerminate` — é onde entra.
  O app **não** é sandbox (só o widget: `build-app.sh:135-150`), coerente com M4 (`system()` num app Developer ID).
- **O empacotador** (`tools/build-app.sh`): `pip install --no-compile --target libs aiohttp`, o Python fixado
  (3.13.15+20260901), reassinatura de todo Mach-O em `python/`, `libs/`, `nut/`; o `Info.plist` por heredoc
  (`:51`); provas por `PlistBuddy`. O instalador de linha de comando (`scripts/install.sh:333`) instala
  **só `aiohttp`** — o leitor BLE não existe nesse caminho (não há app lá) e nada dele é importado pelo serviço.
  O venv de desenvolvimento nasce com `pip install -e '.[dev]'` (`README.md:142`); o gate roda `"$PY" -m pytest`
  nele (`gate.sh:94`).
- **`release.sh --check`** amarra seis arquivos (`tools/release.sh:59-64`): `pyproject.toml`,
  `src/river_unifi_bridge/__init__.py`, `scripts/install.sh`, `scripts/uninstall.sh`, `tools/build-app.sh`,
  `river-bridge-install.sh` — os dois de `scripts/` e o instalador em uma linha entram no escopo (rodada 1, B6).
- **Cenas do gate**: a maior é **S79** (0.10.1, o `NSExtensionMain` do widget); as desta frente são S80–S85 e S1c.
- **Tamanho hoje:** `libs/` 3,9 MB; o pacote 95 MB.

### Correções de crença registradas neste levantamento
- A B39 dizia "exige gerar uma *login key*". Isso é o script do `ef-ble-reverse`; a integração usa só o
  **User ID** (M7). A linha do backlog foi emendada com a data.
- A B39 dizia "o River Bridge (programa, na sessão) lê … com a biblioteca de rabits". Confirmado por medição (M3/M4).
- Rodada 1 da revisão fria: oito bloqueadores, todos de levantamento meu (tabela em `…-0-11-0-banca.md`).
  Classe dominante: **função inteira do consumidor até o `return` cedo** (`_declarar`, `recusa_do_vigia_espelho`)
  e **grep no repo inteiro por consumidor** (`EventChipSpec.all`). Corrigidos abaixo (D3, D4, D6, D7, D10, D11).

## Risk band

**high** — processo novo de longa duração na sessão do usuário (filho do app) falando com um rádio; consentimento
de privacidade do macOS; credencial de conta (User ID) guardada pelo serviço; um armazém novo; aparelhos novos
declarados no `ups.conf` (reinício do servidor do no-break ao entrar/sair); o contrato `/v1/state` ganha um campo;
uma biblioteca de terceiros de 16 mil linhas embutida. **Nada muda no que desliga aparelhos** e nada toca o
leitor de fábrica do River do escritório. Regras: fixtures regenerados no mesmo commit; cada cerca nova com
mutante; revisão fria do diff; bancada no mini medida no ato; a proteção continua lendo só o `usbhid-ups`.

## Decisões (D)

| # | Decisão | Fundamento |
|---|---|---|
| D1 | **Quem lê o rádio é o programa (sessão do usuário), num processo filho Python** — o interpretador do pacote rodando `python3 -m river_unifi_bridge.ble_leitor`, com a `eflib` embutida. O app é só o supervisor: sobe o filho quando o serviço responde, relança com recuo (5 s, 15 s, 60 s; 5 quedas em 10 min → para e avisa), encerra ao sair (`ReopenDelegate.applicationWillTerminate` → `terminate()`; e o filho sai sozinho ao ver EOF na entrada padrão — pai morto, filho morre). O `Info.plist` do app ganha `NSBluetoothAlwaysUsageDescription` (PT: "O River Bridge lê o River da sala pelo Bluetooth para mostrar carga e consumo dele."). | M3 (root não lê), M4 (o filho do app lê), M2 (roda reassinada funciona). Python e não Swift porque o protocolo (ECDH, cifra, protobuf de 19 famílias) já existe pronto e testado pela comunidade |
| D2 | **A verdade mora no serviço.** Armazém `<state_dir>/ble.json` (0600, `_write_private_json`/`_read_private_json` de `protect.py`, os mesmos de `devices.json`): `{"version": 1, "user_id": "…"\|null, "serie_do_escritorio": "…"\|null, "rivers": [{"id": "ble_<8 hex>", "serie", "nome", "ativo", "created_at", "updated_at"}]}`. **`serie_do_escritorio`** é gravada pelo laço a cada leitura boa do NUT cuja `identity.serial` exista e seja diferente da guardada (uma escrita por mudança, não por volta) — é a fonte persistente da recusa de D3 quando o serviço acabou de subir. O filho **não guarda nada**; o app não persiste nada. | Um único dono do estado; a remoção apaga o diretório inteiro (`apagar_tudo`), então `ble.json` sai junto |
| D3 | **Rotas** (ficha pelo middleware `auth`): `GET /v1/ble` → `{"conta": {"tem_user_id": bool}, "rivers": [ {…instância, "estado", "motivo", "lida_em", "idade_s", "leitura"} ]}`; `PUT /v1/ble/conta` `{"user_id"}` (forma `[0-9]{6,20}`) / `DELETE /v1/ble/conta`; `GET /v1/ble/credencial` → `{"user_id"}` (para o filho); `POST /v1/ble/rivers` `{"serie","nome"}` → 201; `PUT /v1/ble/rivers/{id}` `{"nome"?, "ativo"?}`; `DELETE /v1/ble/rivers/{id}`; `PUT /v1/ble/rivers/{id}/leitura` `{"estado", "motivo"?, "leitura"?}` → 204 (do filho, ≤ 1 por 2 s por River). **Recusas** (`{"erro","motivo"}`): série fora de `[A-Z0-9]{16}` → 400 `serie_invalida`; **a série do River do escritório**, lida de **três fontes na ordem** — `identity.serial` do último estado bom, `serie_do_escritorio` do armazém, `UDR7_EXPECTED_SERIAL` — → 409 `mesmo_river`; **as três vazias** (serviço recém-subido, River do escritório desligado, `.env` sem a chave, armazém sem histórico) → 409 `serie_do_escritorio_desconhecida` ("o serviço ainda não leu o River do escritório; ligue-o e tente de novo") — a rota **nunca** aceita sem saber quem é o River do cabo; série repetida → 409 `serie_repetida`; nome repetido (strip+casefold) → 409 `nome_duplicado`; nome fora de `NAME_PATTERN` → 400. **A cerca do espelho** (`recusa_do_vigia_espelho`) passa a recusar também `NUT_UPS` com o prefixo `river-ble-` (em `load_config` e no `PUT /v1/config`) — a proteção não pode ler um aparelho que nós publicamos, seja o do cabo, o de um dispositivo ou o de um River por rádio. | Espelha `devices.py`; B2 e B3 da rodada 1 |
| D4 | **A leitura no estado e no SSE**: `ble_rivers` entra no *payload* — montado **na API**, não no `UpsSnapshot`: `_h_state` e `_h_events` fazem `{**(snapshot or _empty_state(...)), "ble_rivers": self.fontes.publicaveis(agora)}`, e `_empty_state` também o traz (`[]`). Cada `PUT …/leitura` aceito chama `shared.bump()` (método novo: só `_version += 1`). `UpsSnapshot.to_dict()` e o fixture `state_online` **não mudam**; `state_nulls` é regenerado (`"ble_rivers": []`); o teste Swift `decodeNullsFixtureStaysNil` não afirma nada sobre chaves extras (lido). Histórico (`record_sample`) continua só do River do escritório — o do segundo é B51. | Merge na API porque `update_snapshot` só acontece com leitura boa do NUT |
| D5 | **A leitura** (dicionário do filho; ausente = `null`, nunca zero), **atributo do `Device` da `eflib` → chave**, todos de `eflib/devices/river3.py:50-101` e `river3_plus.py:22-27`: `serie` (`serial_number`), `modelo` (`device`: "River 3 Plus"/"(270)"/"Wireless"), `carga_pct` ← `battery_level`, `na_tomada` ← `plugged_in_ac`, `entrada_w` ← `input_power`, `saida_w` ← `output_power`, `entrada_ac_w` ← `ac_input_power`, `entrada_dc_w` ← `dc_input_power`, `tomada_ac_w` ← `ac_output_power`, `saida_12v_w` ← `dc12v_output_power`, `usb_a_w` ← `usba_output_power`, `usb_c_w` ← `usbc_output_power`, `bateria_w` ← `battery_input_power − battery_output_power` (os dois são ≥ 0, `:79-80`; positivo = carregando), `autonomia_s` ← `remaining_time_discharging × 60` (minutos, `sensor.py:245,496-497`; só na bateria), `tempo_para_carga_s` ← `remaining_time_charging × 60` (só carregando), `temperatura_c` ← `cell_temperature`, `limite_descarga_pct` ← `battery_charge_limit_min`, `limite_carga_pct` ← `battery_charge_limit_max`, `erro` ← `error_occurred`, `bateria_extra_pct` ← `battery_1_battery_level` (Plus). **Estados**: `procurando`, `conectando`, `lendo`, `sem_leitura` (> 30 s sem PUT — o serviço decide, pelo relógio dele), `sem_bluetooth` (`BleakBluetoothNotAvailableError`, `bleak/exc.py:46,57`), `recusado` (autenticação recusada), `parado` (`ativo=false` ou sem User ID), `erro` (tipo + 200 caracteres). | W1 da rodada 1: são atributos, não nomes protobuf |
| D6 | **NUT**: um `DriverDoNut` por River **ativo**, nome `river-ble-<5 últimos da série, minúsculas>`, declarado no `ups.conf` com `desc` = o nome do dono. **A declaração deixa de depender do River do escritório**: `PonteDoNut` ganha `atualizar_ble(fontes)` (publica cada River ativo e marca `DATASTALE` por estado) e `_declarar` passa a `declarar_tudo()`, chamado **em toda volta do laço** — na leitura boa e na falha do NUT —, montando a lista com o River (descrição = último `snap.model` guardado em `self._modelo_do_river`, ou "River") quando `self._river` existe, os dispositivos, e os Rivers BLE ativos; a guarda `self._river is None` continua (sem pasta de estado do NUT ninguém publica, nem o BLE). Recolhido (e a declaração reescrita → servidor reiniciado) só ao **remover ou desativar** — nunca por oscilação. Variáveis (`variaveis_do_river_ble`): `device.type ups`, `device.mfr EcoFlow`, `device.model`, `device.serial`, `ups.status` = `OL`/`OB` por `na_tomada` + `CHRG` se `bateria_w > 0` / `DISCHRG` se `< 0` (nunca `LB`), `battery.charge`, `battery.charge.low` (limite de descarga), `battery.runtime` (só na bateria), `battery.temperature`, `input.realpower`, `ups.realpower`, `outlet.count 4` + `outlet.n.{id,desc,realpower,switchable=no}` (a tabela `TOMADAS`), `driver.name river-bridge`, `driver.version`. **Sem comandos** (B53). | B1 da rodada 1: `_declarar` só rodava com `snap` |
| D7 | **Eventos** (`eventos.DO_SERVICO`): `RIVER_BLE_QUEDA`, `RIVER_BLE_ENERGIA_VOLTOU`, `RIVER_BLE_SEM_LEITURA`, `RIVER_BLE_LEITURA_VOLTOU`, com `device=<id do River>` (o SSE e o histórico já carregam `device`). Queda/volta com os **mesmos atrasos** do laço principal numa `TransicaoDoRiverBle` pura (relógio injetado) em `fontes_ble.py`; "sem leitura" após os 30 s de D5. **O nome na frase** vem do `device`: `NomesDosRiversBle.nome(device:rivers:)` (Core, puro) procura o id em `bleRivers` do último estado; River já removido → "River por Bluetooth". Chips: `EventChipSpec.Kind` ganha `.riverBle(id:)`; `all(devices:rivers:)` (o parâmetro novo tem padrão `[]`, então os três testes existentes continuam verdes e `count == 4` sem Rivers); `matches` do `.riverBle` = tipo em `types` **e** `device == id`; os quatro consumidores mudam (`EventsTimeline.swift:38`, `DashboardWindow.swift:215` e `:256` passam `store.latest?.bleRivers ?? []`; `DeviceInstanceTests` ganha `umChipPorRiverBle`). **A legenda do histograma** (`LegendaDeEventos.rotulo`, `LegendaDeEventos.swift:46-54`, 0.8.7) rotula evento sem tipo de dispositivo por `qualquerEvento(tipo)?.short(name: "")` — com dois Rivers BLE as barras dos dois teriam o mesmo rótulo; `chaves(eventos:nomes:dispositivos:emPortugues:)` ganha `rivers:` e o rótulo dos `RIVER_BLE_*` passa pelo `NomesDosRiversBle` (teste `LegendaDeEventosTests.doisRiversBleTemRotulosDistintos`; W4 da rodada 2). | B7 e W2 da rodada 1 |
| D8 | **Login**: `ble_leitor login` lê `{"email","senha","regiao"}` da **entrada padrão** (nunca argv), chama `eflib.login.EcoFlowLogin(session).login(...)` e grava o User ID por `PUT /v1/ble/conta`; devolve `{"ok": true}` ou `{"erro": "…"}`; a senha vive só no processo. Alternativa na tela: "Informar o User ID…". `ble_leitor scan` → 8 s → `[{serie, nome_ble, sinal_dbm, modelo}]` só EcoFlow (`MANUFACTURER_KEY = 0xB5B5`, `devicebase.py:56`), sem o River do escritório e sem os já adicionados. O filho recebe `RUB_API_PORT` e `RUB_API_TOKEN` por **ambiente**. | A senha não pode aparecer em `ps`, em registro nem em disco |
| D9 | **O filho** (`ble_leitor.py`, `asyncio`): a cada 10 s `GET /v1/ble` + `GET /v1/ble/credencial`; por River ativo uma tarefa: varredura por série, `NewDevice` (`eflib/__init__.py:40`), `connect(user_id=)`, `wait_until_authenticated_or_error`, `register_callback` (`devicebase.py:314-316,381-392,447`) → monta a leitura (D5) e faz `PUT …/leitura` **no máximo a cada 2 s**; desconexão → `procurando` e recuo 5 → 60 s; desativado/removido → `disconnect`. **Só importa `eflib`/`bleak` quando há pelo menos um River ativo com User ID** (o `login` importa só `eflib.login` — que, por M6, também carrega `bleak`; por isso o `login` roda no mesmo Python do pacote, onde ele existe). Registro em `~/Library/Logs/River Bridge/bluetooth.log` (rotação 1 MB × 3), escrito pelo app a partir de stdout/stderr do filho. | "One BLE connection at a time" da EcoFlow: enquanto lemos, o app do celular fala com esse River pela nuvem; o interruptor "Ler por Bluetooth" solta o rádio |
| D10 | **App** — (a) `Bluetooth/LeitorBluetooth.swift` (`@MainActor @Observable`, supervisor + `rodar(subcomando:entrada:)`); (b) `Dashboard/RiversPorBluetooth.swift`: fileira de cartões abaixo do fluxo, só quando `bleRivers` não é vazio — nome, anel pequeno de carga (`EnergyRing` compacto), "Na tomada"/"Na bateria", entrada/saída em W, rodapé "via Bluetooth · há N s" / "Procurando…" / "Bluetooth não autorizado" (botão para `x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth`) / "Sem leitura há N min" / "Recusado: confira a conta"; (c) `Settings/BluetoothGroup.swift` (molde: `HomeAssistantGroup`): conta, lista de Rivers (nome, série, interruptor Ler, Remover com confirmação), "Procurar Rivers…" → folha com a varredura e "Adicionar" com nome; (d) Saúde: um cartão por River BLE ativo; (e) `Models.swift`: `UpsState.bleRivers: [RiverBluetooth]?` + `RiverBluetooth` (tudo opcional, com `id`); (f) `TelemetryStore.apply`: `beat` só quando `timestamp` do River do escritório mudou; (g) `DeviceTypeRegistry.qualquerEvento` com as quatro frases (PT/EN) e `NomesDosRiversBle`; (h) `ReopenDelegate.applicationWillTerminate`. Zero cor/número solto (S55). Seam `--seam-ble tests/fixtures/ble.json`. | Só o que tem consumidor; a folha de detalhe fica para B52 |
| D11 | **Empacotamento e desenvolvimento**: `build-app.sh` instala também `bleak>=3.0.2 bleak-retry-connector ecdsa~=0.19 protobuf~=6.30 pycryptodome~=3.23`, **remove `libs/PyObjCTest`** (16 MB de testes do PyObjC) e escreve `NSBluetoothAlwaysUsageDescription` no `Info.plist`; provas: `PlistBuddy Print :NSBluetoothAlwaysUsageDescription` não vazio; `codesign -dv libs/CoreBluetooth/_CoreBluetooth.cpython-313-darwin.so` com `TeamIdentifier=8A47D8UNV2`; `libs/PyObjCTest` ausente (sem `cmd | grep -q` sob `pipefail`: capturar e conferir — lição da S79). `eflib` embutida em `src/river_unifi_bridge/eflib/` tal qual (`VENDOR.md` com commit, data e licença + `LICENSE`), importada **só** pelo `ble_leitor` (lazy). `pyproject.toml`: `[project.optional-dependencies] ble = [as cinco acima]`; **o venv de desenvolvimento passa a `pip install -e '.[dev,ble]'`** (`README.md:142` e o guia), e o gate ganha **S1c**: `"$PY" -c "import bleak, eflib"` → `[ERRO] dependências de desenvolvimento do Bluetooth ausentes: .venv/bin/pip install -e '.[dev,ble]'` — assim `test_ble_leitor.py` e o teste do login importam a `eflib` de verdade no venv do gate. O serviço em si continua com `aiohttp` como única dependência de execução. | M2, M6, B4 da rodada 1 |
| D12 | Versão **0.11.0**. | Contrato de estado novo, rotas novas, processo novo |

## Impact sweep (commands run now, 2026-09-06)

```
git status -sb; git log --oneline -3                          # limpo; 7a090e8, 8d78433 (0.10.1), 816806e
$PY_PACOTE ble-scan-30.py > prova-ble/saida-local-30s.txt    # M1: 30 aparelhos; EF-R3P70046 −47; EF-R3PF0298 −91; flags=62
$PY_PACOTE ble-scan.py (rodas como vieram do PyPI)           # M2: ImportError … different Team IDs
ssh mini … ble-scan.py                                        # M3: BleakBluetoothNotAvailableError DENIED_BY_UNKNOWN
open "River Bridge BLE Prova.app" (filho = python + scan)     # M4: rc=0, 23 aparelhos em 12.1s (saida-1.txt)
ssh mini open "River Bridge BLE Prova.app"                    # M5: 931 s (diálogo) → rc=0; 8 s e 30 s: só R631ZBBAWH270046
PYTHONPATH=ble-libs:eflib-vendor $PY_PACOTE -c "import eflib…"   # M6: import ok
PYTHONPATH=eflib-vendor .venv/bin/python -c "import eflib.login"  # M6: ModuleNotFoundError: bleak (revisor, rodada 1)
sed -n 1,12p eflib-vendor/eflib/__init__.py                   # importa bleak e .devices no topo
curl pypi.org/pypi/{bleak,bleak-retry-connector,bluetooth-adapters}/json   # requires_dist
sed -n 10,17p ha-ef-ble/pyproject.toml                        # pinos: ecdsa, protobuf, pycryptodome; bleak sem pino
grep -rn "homeassistant" eflib/                               # vazio
grep -rln 'add_event\|record_event\|_registrar(\|_avisar(' eflib/   # vazio
du -sh ble-libs (45M) · PyObjCTest 16M · objc 10M
sed -n 126,160p nut_servico.py                                # atualizar → _declarar(snap); return cedo sem _river
sed -n 528,537p service.py; sed -n 555,565p service.py        # falha do NUT: sem ponte.atualizar
sed -n 276,300p config.py; sed -n 384,387p service.py         # recusa_do_vigia_espelho: aparelho + ids de plugin
grep -n "snapshot" state.py | head; sed -n 90,100p api.py     # snapshot None até a 1.ª leitura; serial null
git grep -n "EventChipSpec.all\|EventChip.all" macos           # EventsTimeline:38; DashboardWindow:215,256; DeviceInstanceTests:148,154,200
sed -n 531,580p DevicePlugins.swift; sed -n 151,163p Models.swift   # Kind sem River BLE; BridgeEvent sem detail
grep -n "beat &+= 1" TelemetryStore.swift                     # :205
grep -n "def record_event" -A3 history.py                     # device existe
grep -n "def apagar_tudo" -A30 remocao.py                     # listdir
sed -n 59,64p tools/release.sh                                # os 6 arquivos da versão
grep -n "pip install -e" README.md                            # :142 '.[dev]'
grep -n "NSBluetooth" tools/build-app.sh                      # vazio
python3 -c "print(list(json.load(open('tests/fixtures/state_online.json'))))"
grep -o "^# S[0-9]*" tools/gate.sh | sort -V | tail -1        # S79 → novas S80–S85 (+ S1c)
grep -o "| B[0-9]* |" docs/BACKLOG_20260901.md | tail -1      # B54 (B51–B54 já no backlog, 7a090e8)
```

## Changes, per file

**Serviço (Python)**
- `src/river_unifi_bridge/fontes_ble.py` (**novo**) — `ArmazemBle` (carrega/grava `ble.json`; `user_id`, `serie_do_escritorio`, `rivers`, ids `ble_<8 hex>`, validações de D3), `RiverBle`, `LeituraBle`, `estado_publicavel(agora)`, `TransicaoDoRiverBle`, `nome_no_nut(serie)`, `variaveis_do_river_ble(river, leitura, estado)`, `status_do_nut(leitura)`, `serie_do_escritorio(estado, armazem, cfg)` (as três fontes, na ordem de D3).
- `src/river_unifi_bridge/config.py` — `recusa_do_vigia_espelho` recusa `nut_ups.startswith("river-ble-")` (`PREFIXO_BLE`); `load_config` e o `PUT` herdam.
- `src/river_unifi_bridge/api.py` — as rotas de D3; `_h_state`/`_h_events` mesclam `ble_rivers`; `_empty_state` ganha `"ble_rivers": []`.
- `src/river_unifi_bridge/state.py` — `bump()`.
- `src/river_unifi_bridge/service.py` — cria o `ArmazemBle` (fora de `--once`), passa-o ao `ApiServer` e à `PonteDoNut`; na leitura boa grava `serie_do_escritorio` quando mudou; **em toda volta** (leitura boa e falha) `fontes.avancar(agora)` → eventos, e `ponte.atualizar_ble(fontes)` + `ponte.declarar_tudo()`.
- `src/river_unifi_bridge/nut_servico.py` — `atualizar_ble(fontes)`; `_declarar(snap)` vira `declarar_tudo()` com `self._modelo_do_river` (atualizado em `atualizar`); `_reconciliar` inalterado.
- `src/river_unifi_bridge/eventos.py` — os quatro nomes em `DO_SERVICO`.
- `src/river_unifi_bridge/ble_leitor.py` (**novo**) — `main(argv)` com `ler` (padrão), `login`, `scan`; `leitura_de(device)` e `status_de(exc)` puros; o laço de D9 com `procurar`, `conectar`, `dormir`, `api` injetáveis; `eflib` importada dentro das funções.
- `src/river_unifi_bridge/eflib/` (**novo, embutido**) + `VENDOR.md` + `LICENSE`.
- `pyproject.toml` — extra `ble`; 0.11.0. `src/river_unifi_bridge/__init__.py`, `scripts/install.sh`, `scripts/uninstall.sh`, `river-bridge-install.sh`, `tools/build-app.sh` — 0.11.0.
- Testes: `tests/unit/test_fontes_ble.py` (armazém, recusas — **três testes de `mesmo_river`, um por fonte, cada um com as outras duas vazias, e um da recusa `serie_do_escritorio_desconhecida`** —, 30 s, transições, variáveis, `status_do_nut`), `tests/unit/test_config.py` (`NUT_UPS=river-ble-x` recusado no arquivo e no PUT), `tests/unit/test_ble_leitor.py` (mapeamento com um `Device` de mentira; laço com varredura/conexão falsas: reconexão com recuo, desativação, PUT ≤ 1/2 s, saída por EOF; `login` com servidor aiohttp de teste chamando a `eflib.login` real), `tests/unit/test_api.py` (rotas, `ble_rivers` no estado e no SSE), `tests/unit/test_nut_servico.py` (`DATASTALE`, recolhimento só ao remover, **declaração com o NUT mudo**), fixtures `state_nulls.json` (regenerado), `eventos.json` (regenerado), `ble.json` (**novo**).

**App (Swift)**
- `RiverBridgeCore/Models.swift` — `UpsState.bleRivers`, `RiverBluetooth` (com `id`).
- `RiverBridgeCore/TelemetryStore.swift` — `beat` só com `timestamp` novo; seam `--seam-ble`.
- `RiverBridgeCore/APIClient.swift` — `ble()`, `bleConta(userId:)`, `bleEsquecerConta()`, `bleAdicionar(serie:nome:)`, `bleAlterar(id:nome:ativo:)`, `bleRemover(id:)`.
- `RiverBridgeCore/DevicePlugins.swift` — as quatro frases; `EventChipSpec.Kind.riverBle(id:)`, `all(devices:rivers:)`, `matches`; `NomesDosRiversBle`.
- `RiverBridgeCore/LegendaDeEventos.swift` — `chaves(…, rivers:)` e o rótulo dos `RIVER_BLE_*` com o nome do River (W4); `ChartsView.swift` passa `store.latest?.bleRivers ?? []`.
- `RiverBridgeCore/TextoDoRiverBluetooth.swift` (**novo**, puro).
- `RiverBridgeApp/Bluetooth/LeitorBluetooth.swift` (**novo**); `RiverBridgeApp/RiverBridgeApp.swift` (`applicationWillTerminate`, o supervisor nasce com o `store`).
- `RiverBridgeApp/Dashboard/RiversPorBluetooth.swift` (**novo**); `Dashboard/DashboardWindow.swift` (a fileira; `EventChip.all(devices:rivers:)` nas duas chamadas); `Dashboard/EventsTimeline.swift` (`:38` e a frase com o nome).
- `RiverBridgeApp/Settings/BluetoothGroup.swift` (**novo**) + folhas; `Settings/SettingsView.swift`.
- `RiverBridgeApp/Health/HealthView.swift` — cartões dos Rivers BLE.
- Testes Swift: `ModelsDecodingTests` (`ble.json`), `TextoDoRiverBluetoothTests`, `EventosContractTests`, `TelemetryStoreTests.oBatimentoNaoPulsaComLeituraSoDoBluetooth`, `DeviceInstanceTests.umChipPorRiverBle` (+ os três existentes continuam), `NomesDosRiversBleTests`.

**Empacotador, gate, docs**
- `tools/build-app.sh` — D11.
- `tools/gate.sh` — S1c (venv com `bleak`/`eflib`), S80 (mutante: `serie_do_escritorio` deixa de olhar o **estado vivo** → `test_refuses_the_office_serial_seen_live` reprova; o teste nasce com armazém e `.env` vazios), S81 (mutante: `estado_publicavel` ignora os 30 s → `test_a_reading_older_than_30s_is_stale`), S82 (mutante: `status_do_nut` troca `OL`/`OB` → `test_status_on_battery_is_ob`), S83 Swift (`TextoDoRiverBluetooth.carga(nil)` → "0 %" → `semLeituraETraco`), S84 Swift (`apply` pulsa sempre → `oBatimentoNaoPulsaComLeituraSoDoBluetooth`), S85 (prova de texto do `build-app.sh`: as três provas de D11, como S78).
- `README.md:142` e o guia de desenvolvimento — `pip install -e '.[dev,ble]'`.
- `docs/reference/api-local.md`, `docs/decisions/2026-09-06-1800-o-bluetooth-e-lido-pela-sessao-do-usuario.md` (→ `aceito` ao aprovar), runbook (seção "O River da sala por Bluetooth"), `README.md`, `CHANGELOG.md` `[0.11.0]`, backlog (B39 → FEITO ao fechar), mapa `docs/README.md` (status dos dois arquivos → aceito), handoff §5e.
- `.roadworthy/scope` — o desta frente (escrito em 2026-09-06 18h; ignorado pelo git).

## Scope
```
src/river_unifi_bridge/**
tests/**
tools/gate.sh
tools/build-app.sh
tools/build-dmg.sh
tools/release.sh
scripts/**
river-bridge-install.sh
macos/RiverBridge/Sources/**
macos/RiverBridge/Tests/**
macos/RiverBridge/Package.swift
pyproject.toml
README.md
CHANGELOG.md
docs/**
.roadworthy/**
/Users/alessandro/.claude/plans/2026-09-06-1800-o-segundo-river-por-bluetooth-0-11-0.review.md
/Users/alessandro/.claude/projects/-Users-alessandro-Development-EcoFlow-UniFi-UPS-Bridge/memory/**
```

## Acceptance (EARS)
| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|---|---|---|---|
| 1 | `POST /v1/ble/rivers` com a série do River do escritório (vinda do estado vivo, ou só do armazém, ou só do `.env`), com as três fontes vazias, com série repetida, nome repetido ou série fora da forma | 409 `mesmo_river` (três testes, um por fonte) / 409 `serie_do_escritorio_desconhecida` / 409 `serie_repetida` / 409 `nome_duplicado` / 400 `serie_invalida`, sem gravar | `test_fontes_ble.py::test_refuses_the_office_serial_seen_live`, `::_persisted`, `::_from_env`, `::test_refuses_when_the_office_serial_is_unknown`, `::test_refuses_a_repeated_serial`, `::test_refuses_a_repeated_name`, `::test_refuses_a_malformed_serial`; S80 | qualquer 2xx ou `ble.json` alterado |
| 2 | `NUT_UPS=river-ble-f0298` no `.env` ou no `PUT /v1/config` | recusa com o motivo do espelho (arquivo: `ConfigError`; PUT: 4xx) | `test_config.py::test_the_mirror_fence_covers_ble_rivers` | aceito |
| 3 | o filho manda `PUT …/leitura` e depois cala 30 s | `estado` `lendo` → `sem_leitura`; NUT `DATASTALE`; `RIVER_BLE_SEM_LEITURA` uma vez e `RIVER_BLE_LEITURA_VOLTOU` na leitura seguinte | `test_fontes_ble.py::test_a_reading_older_than_30s_is_stale`, `test_nut_servico.py::test_ble_river_goes_stale_not_removed`; S81 | estado vivo além de 30 s; aparelho recolhido por oscilação; evento repetido |
| 4 | um River BLE ativo e **o NUT do escritório mudo** (falha de leitura) | o River BLE continua declarado no `ups.conf` e publicado (`DATAOK` enquanto lido) | `test_nut_servico.py::test_ble_rivers_are_declared_while_the_office_river_is_silent` (laço com `poll_once` falhando) | aparelho ausente da declaração |
| 5 | `na_tomada=false` por mais que `POWER_LOSS_DELAY_SECONDS` e depois `true` por mais que `RESTORE_DELAY_SECONDS` | `RIVER_BLE_QUEDA` e `RIVER_BLE_ENERGIA_VOLTOU` com `device=<id>`; `ups.status` `OB DISCHRG` → `OL CHRG` | `test_fontes_ble.py::test_power_loss_and_restore_follow_the_delays`, `::test_status_on_battery_is_ob`; S82 | evento antes do atraso, sem `device`, ou `OL` na bateria |
| 6 | a tela recebe um estado com `ble_rivers` | cartão com nome, carga, estado e "há N s"; sem leitura "—" e a frase do estado; os quatro eventos com frase PT/EN **e o nome do River** (ou "River por Bluetooth" se removido); um chip por River; o logo **não** pulsa com leitura só do Bluetooth | `TextoDoRiverBluetoothTests`, `NomesDosRiversBleTests`, `EventosContractTests`, `DeviceInstanceTests.umChipPorRiverBle`, `TelemetryStoreTests.oBatimentoNaoPulsaComLeituraSoDoBluetooth`; S83, S84; capturas PT/EN e 414 pt com `--seam-ble` lidas em imagem | número inventado; nome cru; chip ausente; pulso a cada leitura BLE |
| 7 | o app abre com o serviço no ar e um River ativo com User ID | o filho sobe, o macOS pede o Bluetooth **uma vez** em nome do River Bridge; negado → `sem_bluetooth` com o botão; o app sai → o filho some | bancada no mini (`pgrep -fl ble_leitor`; `GET /v1/ble`); `test_ble_leitor.py::test_the_child_exits_on_stdin_eof` | filho órfão; diálogo em nome de "python3"; rádio tocado sem River ativo |
| 8 | Entrar na conta com credenciais válidas | `tem_user_id: true`; a senha não aparece em `ps`, no registro nem em disco | bancada (o dono digita); `test_ble_leitor.py::test_login_reads_credentials_from_stdin_and_puts_the_user_id` (servidor aiohttp de teste, `eflib.login` real, no venv com o extra `ble`) | senha em argv/log/disco; User ID não gravado |
| 9 | Procurar Rivers… no mini com o River de 127 V ligado na sala | a lista traz a série dele com sinal, sem o do escritório | bancada — **é a medição de alcance** (só com o aparelho de amanhã) | lista vazia com o River ligado → frente parada, decisão do dono |
| 10 | River adicionado e ativo no mini | `LIST VAR river-ble-<série>` com `ups.status`, `battery.charge`, `input.realpower`, `outlet.count 4`; `LIST UPS` com os três aparelhos; o Home Assistant vê o novo | bancada | variável/aparelho ausente |
| 11 | o River da sala é tirado da tomada (dono presente) | cartão "Na bateria" em ≤ 2 s + atraso; evento com o nome e o chip dele; o UDR7 **não** reage | bancada, com o dono | UDR7 reagindo; evento ausente |
| 12 | o gate roda | verde fora do já declarado (S15/B17); S1c, S80–S85 verdes; pytest; swift test; docs-check; lychee | gates | qualquer vermelho novo |
| 13 | 0.11.0 publicada e instalada no mini | serviço 0.11.0; `ble.json` 0600 root; filho sobe; pacote medido (≤ 95 + 30 MB, `PyObjCTest` fora); prova de arranque zero arquivos novos | bancada | qualquer passo diferente |

## Ordem de commits
| # | Commit | Cercas |
|---|---|---|
| C0 | (feito em 7a090e8 como *proposto*) plano, banca, decisão, backlog; ao aprovar: `status: aceito` nos três arquivos e no mapa, `.roadworthy/scope` | — |
| C1 | `eflib` embutida + `VENDOR.md` + `LICENSE`; extra `ble`; README/guia (`.[dev,ble]`); S1c; `build-app.sh` (dependências, `PyObjCTest` fora, `Info.plist`, provas) | S1c, S85 |
| C2 | `fontes_ble.py` (armazém, série do escritório, recusas) + `config.py` (espelho) + `state.bump` + rotas + `ble_rivers` + fixtures + testes | S80, S81 |
| C3 | eventos + transições + ponte do NUT (`atualizar_ble`, `declarar_tudo`) + laço + testes | S82 |
| C4 | `ble_leitor.py` (ler/login/scan) + testes sem rádio | — (testes) |
| C5 | app: modelos, store (`beat`), `APIClient`, frases, nomes, chips, `TextoDoRiverBluetooth` + testes | S83, S84 |
| C6 | app: supervisor, cartões, grupo de Ajustes, folhas, seam, `applicationWillTerminate` | — |
| — | **revisão fria sobre o diff C1–C6** | — |
| C7 | capturas lidas e ajustes | — |
| C8 | CHANGELOG, versão nos 6 arquivos, docs, `tools/release.sh v0.11.0 --no-gate` após gate verde, push | — |
| C9 | bancada no mini (com o River de 127 V) + handoff §5e + memória; commit + push | — |

## Bancada no Mac mini (C9) — com o River de 127 V (2026-09-07 ou depois)
1. `curl` do DMG + `SHA256SUMS`; `spctl`; instalar; `Info.plist` 0.11.0 e `NSBluetoothAlwaysUsageDescription`.
2. Reiniciar o serviço; `GET /v1/ble` → conta vazia, `rivers: []`; `ble.json` ausente ou só com `serie_do_escritorio`.
3. (Dono) Entrar na conta EcoFlow. Eu meço: `tem_user_id: true`; `ls -la ble.json` → `-rw------- root`; o dono confirma que a senha não aparece no registro.
4. (Dono) Procurar Rivers… → **medição de alcance** → Adicionar → Ler ligado. Eu meço: `pgrep -fl ble_leitor`; o diálogo do Bluetooth (dono permite); `GET /v1/state | jq .ble_rivers`; `LIST VAR`; `LIST UPS`.
5. (Dono) tirar da tomada → cartão, evento com o nome, `OB`; religar → `OL`, evento.
6. Sair do app → `pgrep` vazio; 30 s → `DATASTALE`; abrir → `lendo`. Desligar o River do escritório 1 min → o BLE continua declarado e lido (aceitação 4, medido).
7. Desligar "Ler por Bluetooth" → aparelho recolhido (uma reinicialização do servidor, registrada); o app da EcoFlow volta a falar por Bluetooth (dono confirma).

## Verification (after the last commit)
- `GATE_SKIP_XCODEBUILD=1 tools/gate.sh` → verde fora do já declarado, S1c e S80–S85 verdes; `.venv/bin/pytest`; `cd macos/RiverBridge && swift test` (3 vezes); `docs-check.sh docs --since 2026-09-01`; `lychee --offline --root-dir . docs/`; `tools/release.sh --check` → 0.11.0; `gh release view v0.11.0`; bancada no handoff.

## Refutation
- S80 `fontes_ble.py`: mutante em `serie_do_escritorio(...)` tira a fonte do **estado vivo** → `test_refuses_the_office_serial_seen_live` (armazém e `.env` vazios, série só no estado) reprova. Os outros dois testes cobrem as outras fontes um a um (sem cena: o mutante de cada um é a mesma classe; S80 prova o mecanismo).
- S81: `LIMITE_SEM_LEITURA_S = 30` → `10**9` → `test_a_reading_older_than_30s_is_stale` reprova.
- S82: `"OB" if not na_tomada else "OL"` invertido → `test_status_on_battery_is_ob` reprova.
- S83 Swift: `TextoDoRiverBluetooth.carga(nil)` → `"0 %"` → `semLeituraETraco` reprova.
- S84 Swift: `apply` volta a `beat &+= 1` incondicional → `oBatimentoNaoPulsaComLeituraSoDoBluetooth` reprova.
- S85: prova de texto de `build-app.sh` (as três provas de D11), como S78.
- S1c: não é cerca de código — é a condição para as cercas de `test_ble_leitor.py` rodarem no venv do gate.
- O laço do filho (`ble_leitor`) não tem cena de mutação: as cercas são testes com varredura/conexão de mentira; uma S-cena exigiria o rádio.

## Out of scope
- Histórico e gráficos do segundo River (B51); folha de detalhe e widget com ele (B52); ordens por Bluetooth (B53).
- Proteção a partir do segundo River: ele é fonte de leitura; a política continua lendo o `usbhid-ups`.
- Outros modelos EcoFlow (só River 3 / 3 Plus na lista de varredura).
- Um repetidor Bluetooth se o alcance do mini não bastar (decisão do dono).

## Overnight policy
- Decidido à noite, com fonte: nomes do NUT, mapeamento dos atributos (`river3.py`/`river3_plus.py`), limiares (30 s, recuo 5→60 s — declarados, medidos na bancada), textos PT/EN, pinos.
- Reservado ao dono: push e release; atos no mini que instalem/removam; **entrar na conta EcoFlow**; permitir o Bluetooth; tirar o River da tomada; julgamento visual.

## Open questions
- [NEEDS CLARIFICATION: o River de 127 V que chega amanhã será **vinculado à sua conta EcoFlow** no app antes da bancada? Sem vínculo a autenticação é recusada pelo aparelho.]
- [NEEDS CLARIFICATION: aceita que, enquanto o Mac mini lê o River da sala, o app da EcoFlow no celular **perca o caminho Bluetooth** com ele (continua pela nuvem/Wi-Fi)? O interruptor "Ler por Bluetooth" devolve o rádio.]
- [NEEDS CLARIFICATION: aceita digitar e-mail e senha da conta EcoFlow **uma vez** no River Bridge do mini, indo só ao servidor da EcoFlow para obter o User ID? Alternativa: colar o User ID do app da EcoFlow.]
- Alcance: mede-se com o River de 127 V ligado na sala (aceitação 9). Se o rádio do mini não o vir, a decisão (aproximar, outro Mac, repetidor) é sua.
