---
status: proposto
data: 2026-09-06
frente: B39 — o segundo River, lido por Bluetooth (0.11.0)
supera: —
---

# 0.11.0 — o segundo River por Bluetooth: o programa lê, o serviço publica

**Ordem do dono:** *"Excelente. Prossiga com as outras frentes"* (2026-09-06, depois da 0.10.0). A frente seguinte
no backlog era a B39: o River da sala, que não tem cabo no Mac mini, lido pelo rádio Bluetooth e publicado
como o River do escritório já é — na tela, no NUT e, por ele, no Home Assistant.

**Resultado pretendido:** em Ajustes › *Rivers por Bluetooth* o dono entra na conta EcoFlow uma vez, procura
o River da sala, dá-lhe um nome e liga "Ler por Bluetooth". A partir daí: um cartão dele na tela Energia
(carga, na tomada ou na bateria, entrada e saída em watts, "via Bluetooth · há 2 s"), um cartão na tela
Saúde, eventos de queda e restauração dele na linha do tempo, e um aparelho `river-ble-<série>` no servidor
do no-break para o Home Assistant. Nada disto mexe na proteção: o segundo River é **fonte de leitura**,
não alvo de desligamento.

## Context

### O que foi medido hoje (2026-09-06, 17h20–17h55), e é o que sustenta o desenho

| # | Medição (comando no *Impact sweep*) | Resultado | Consequência |
|---|---|---|---|
| M1 | Varredura BLE de 8 s nesta máquina, com o **Python do pacote** (`Contents/Resources/python/bin/python3`, 3.13.15) + `bleak` 3.0.2 | **dois River 3 Plus no ar**: `EF-R3P70046` série `R631ZBBAWH270046` (−42 dBm; é o do escritório, a mesma série do quadro serial `tests/fixtures/river_serial_frame.hex`) e `EF-R3PF0298` série `R631Z61AXJ1F0298` (−94 dBm); ambos com prefixo `R631` e `flags=62` → cifra tipo 7 (ECDH) | o modelo é coberto pela biblioteca (`river3_plus.Device`, `SN_PREFIX = (R631, R634, R635)`); o segundo River **existe no rádio** desta máquina, fraco |
| M2 | O mesmo `import` antes de assinar as rodas | `ImportError … code signature … mapping process and mapped file (non-platform) have different Team IDs` | o Python do pacote tem *hardened runtime* com validação de biblioteca: **toda `.so` de roda tem de ser reassinada com o nosso Developer ID** — que é exatamente o que `tools/build-app.sh` já faz com `find … -name '*.so'` (`assinar_de_dentro_para_fora`); reassinadas, 194 Mach-O, a varredura rodou |
| M3 | A mesma varredura **no Mac mini, por ssh** (sem app responsável na sessão gráfica) | `BleakBluetoothNotAvailableError: Bluetooth is not authorized … DENIED_BY_UNKNOWN` | **o serviço (root, sem sessão) não pode ler o rádio**. Confirma a pesquisa da B39 com medição |
| M4 | Um app mínimo assinado com Developer ID e `NSBluetoothAlwaysUsageDescription`, aberto por `open`, cujo **filho** é o Python do pacote rodando a varredura (`prova-ble/`) — nesta máquina | `rc=0`, 23 aparelhos em 12,1 s; nenhum diálogo apareceu na captura de tela | o consentimento de Bluetooth é atribuído ao **processo responsável** (o app); o filho herda. É o caminho do desenho |
| M5 | O mesmo app-prova aberto **na sessão gráfica do mini** (`ssh … open`) | o filho ficou **parado mais de 5 min** sem resposta; `screencapture` por ssh é recusado (sem Gravação de Tela) | consistente com o diálogo de consentimento **pendente na tela do mini** — ninguém para clicar. O dono verá "River Bridge BLE Prova quer usar o Bluetooth"; ao permitir, `/private/tmp/river-ble-prova/saida.txt` dirá se o rádio do mini **alcança** o River da sala. É a única incógnita que pode afundar a frente, e só se mede lá |
| M6 | `eflib` (a biblioteca de `rabits/ha-ef-ble`, commit `ef02d81`, v1.1.1, 2026-09-04, Apache-2.0) copiada como pacote de topo e importada com o Python do pacote | `import ok`, 117 membros públicos em `river3_plus.Device`; **nenhum** `import homeassistant`; 100 arquivos, 16.588 linhas (956 K são os protobuf gerados) | dá para embutir sem o Home Assistant. Dependências (PyPI, lidas no ato): `bleak>=3.0.2` (no macOS puxa `pyobjc-core`, `pyobjc-framework-corebluetooth`, `pyobjc-framework-libdispatch`), `bleak-retry-connector`, `ecdsa~=0.19`, `protobuf~=6.30`, `pycryptodome~=3.23`; 41 MB instalados, dos quais **16 MB são `PyObjCTest`** (testes do PyObjC) e 10 MB `objc` |
| M7 | Leitura de `eflib/connection.py` (`_run_auth`, `_ecdh_key_exchange`, `_get_key_info_req`, `_auto_authentication`, `_gen_session_key`) e `eflib/login.py` | a autenticação é ECDH (SECP160r1) + tabela embutida (`keydata.py`) + `md5(user_id + série)`. **O único segredo do dono é o User ID da conta EcoFlow**, obtido uma vez por `POST https://api.ecoflow.com/auth/login` (e-mail + senha, `login.py`) ou copiado do app da EcoFlow. Nenhuma *login key* em arquivo (isso era o `ef-ble-reverse`, não a integração) | a senha nunca é guardada: entra uma vez, sai o User ID |

### O que o repositório tem hoje, lido inteiro para este plano

- **O laço do serviço** (`service.py:358-619`): uma leitura do NUT por ciclo, a proteção decide primeiro, a
  serial completa, `shared.update_snapshot(snap.to_dict())`, `history.record_sample`, `ponte.atualizar(snap, plugins)`.
  O dicionário do estado é `UpsSnapshot.to_dict()` (`model.py:120-165`) e é o que o SSE manda tal qual
  (`api.py:583-614`: `payload = snapshot or _empty_state(...)`). A tela decodifica cada campo como opcional.
- **O contrato de plugins** (`plugins/base.py`, `plugins/__init__.py`) é de **dispositivo protegido**: `observe`,
  `armed`, `authorize`, `apply_patch`, estados `ESTADOS` de `protect.py`, cartão "· proteção" na Saúde, chip por
  instância, `load.off` no NUT. Um River lido por rádio não desliga nada e não se arma: encaixá-lo ali seria
  contrato mentindo (`armed` sempre falso, `observe` vazio) e faria os testes de partição e o `everyStateTheServiceCanPublishHasABadge`
  cobrá-lo por estados que ele não tem. **Fica fora do registro de tipos, de propósito** — módulo próprio, rotas próprias.
- **A ponte do NUT** (`nut_servico.py`): um `DriverDoNut` por aparelho, `ups.conf` reescrito só entre as marcas
  (`nut_conf.py`), o servidor reiniciado **só quando a declaração muda** (`_declarar`), `DATASTALE` quando o
  no-break cala. O nome do aparelho obedece a `NOME_DE_APARELHO` (`[A-Za-z0-9][A-Za-z0-9._-]{0,31}`).
- **Os nomes do NUT** (`nut_publicacao.py`, `docs/nut-names.txt`): `ups.status`, `battery.charge`, `battery.runtime`,
  `battery.charge.low`, `battery.temperature`, `input.realpower`, `ups.realpower`, `outlet.n.*`, `device.*`.
- **O estado partilhado** (`state.py`): `_version` sobe em `update_snapshot`/`add_event`/`record_failure`; o SSE
  manda o estado a cada versão nova; `health()` é a cadeia + `plugins` + `cabo`.
- **O vocabulário fechado de eventos** (`eventos.py`) e as duas cercas: `tests/fixtures/eventos.json` = o que o
  código declara (`test_o_arquivo_de_eventos_e_o_que_o_codigo_declara`), e o Swift prova ter frase para cada nome
  (`EventosContractTests.swift`, `DeviceTypeRegistry.qualquerEvento`). A varredura regex por `add_event(`/`record_event(`
  com nome em maiúsculas cobre `src/river_unifi_bridge/**/*.py` — **a `eflib` embutida não casa o padrão** (grep no ato: vazio).
- **A remoção** (`remocao.apagar_tudo`): apaga o diretório de estado **inteiro** por `listdir` — um arquivo novo lá
  dentro sai junto, sem lista a manter.
- **O app**: `TelemetryStore.apply` (`TelemetryStore.swift:194-205`) faz `beat &+= 1` a **cada** estado aplicado —
  é o pulso do logo; `refreshHealth` a cada 5 s; `AppPrefs` só guarda idioma e tema; **não há Keychain nem
  `Process` de longa duração** no app (o `ditto` do Compartilhar… é pontual). `RiverBridgeApp.swift` usa
  `@NSApplicationDelegateAdaptor(ReopenDelegate.self)` — é onde entra o `applicationWillTerminate`.
- **O empacotador** (`tools/build-app.sh`): `pip install --no-compile --target libs aiohttp`, o Python fixado
  (3.13.15+20260901), reassinatura de todo Mach-O em `python/`, `libs/`, `nut/`; o `Info.plist` é escrito por
  heredoc (`:51`); provas por `PlistBuddy`. O instalador de linha de comando (`scripts/install.sh:333`) instala
  **só `aiohttp`** no venv do Homebrew — o leitor BLE **não** existe nesse caminho (não há app lá), e nada dele é importado pelo serviço.
- **Tamanho hoje:** `libs/` 3,9 MB; o pacote 95 MB.

### Correções de crença registradas neste levantamento
- A B39 dizia "exige gerar uma *login key*". Isso é o script do `ef-ble-reverse`; a integração usa só o
  **User ID** (M7). A linha do backlog é emendada com a data.
- A B39 dizia "o River Bridge (programa, na sessão) lê … com a biblioteca de rabits". Confirmado por medição
  (M3/M4), não só por fórum.

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
| D1 | **Quem lê o rádio é o programa (sessão do usuário), num processo filho Python** — o interpretador do pacote rodando `python3 -m river_unifi_bridge.ble_leitor`, com a `eflib` embutida. O app é só o supervisor: sobe o filho quando o serviço responde, relança com recuo (5 s, 15 s, 60 s; 5 quedas em 10 min → para e avisa), encerra ao sair (`applicationWillTerminate` → `terminate()`; e o filho sai sozinho ao ver EOF na entrada padrão — pai morto, filho morre). O `Info.plist` do app ganha `NSBluetoothAlwaysUsageDescription` (PT: "O River Bridge lê o River da sala pelo Bluetooth para mostrar carga e consumo dele."). | M3 (root não lê), M4 (o filho do app lê), M2 (roda reassinada funciona). Python e não Swift porque o protocolo (ECDH, cifra, protobuf de 19 famílias) já existe pronto e testado pela comunidade; reescrevê-lo em Swift seria a frente inteira |
| D2 | **A verdade mora no serviço.** Armazém `<state_dir>/ble.json` (0600, `_write_private_json`/`_read_private_json` de `protect.py`, os mesmos de `devices.json`): `{"version": 1, "user_id": "…"\|null, "rivers": [{"id": "ble_<8 hex>", "serie", "nome", "ativo", "created_at", "updated_at"}]}`. O filho **não guarda nada**: pergunta ao serviço quem ler e com que User ID, e devolve as leituras ao serviço. O app não persiste nada (sem Keychain, sem UserDefaults novo). | Um único dono do estado, como a casa já faz com dispositivos; a remoção apaga o diretório inteiro (`apagar_tudo`), então `ble.json` sai junto sem lista nova; o "Apagar estado" da tela idem |
| D3 | **Rotas** (ficha pelo middleware `auth`, como toda rota): `GET /v1/ble` → `{"conta": {"tem_user_id": bool}, "rivers": [ {…instância, "estado", "motivo", "lida_em", "idade_s", "leitura"} ]}`; `PUT /v1/ble/conta` `{"user_id"}` (forma `[0-9]{6,20}`; medido: o User ID da EcoFlow é numérico) / `DELETE /v1/ble/conta`; `GET /v1/ble/credencial` → `{"user_id"}` (para o filho); `POST /v1/ble/rivers` `{"serie","nome"}` → 201; `PUT /v1/ble/rivers/{id}` `{"nome"?, "ativo"?}`; `DELETE /v1/ble/rivers/{id}`; `PUT /v1/ble/rivers/{id}/leitura` `{"estado", "motivo"?, "leitura"?}` → 204 (do filho, ≤ 1 por 2 s por River). **Recusas** (400/404/409, `{"erro","motivo"}` como as de dispositivos): série fora da forma `[A-Z0-9]{16}` (`serie_invalida`); série igual à do River do escritório (`identity.serial` do último estado, ou `UDR7_EXPECTED_SERIAL`) → 409 `mesmo_river` — publicar duas vezes o mesmo aparelho, por cabo e por rádio, faria o Home Assistant ver dois no-breaks com um só; série repetida → 409 `serie_repetida`; nome repetido (strip+casefold) → 409 `nome_duplicado`; nome fora de `NAME_PATTERN` → 400. | Espelha `devices.py` (ids gerados `<prefixo>_<8 hex>`, nome único); a recusa do "mesmo River" é a cerca da classe "a ponte não pode discordar de si mesma" (`recusa_do_vigia_espelho`) |
| D4 | **A leitura no estado e no SSE**: `ble_rivers` entra no *payload* do estado — montado **na API**, não no `UpsSnapshot`: `_h_state` e `_h_events` fazem `{**(snapshot or _empty_state(...)), "ble_rivers": self.fontes.publicaveis(agora)}`, e `_empty_state` também o traz (`[]`). Cada `PUT …/leitura` aceito chama `shared.bump()` (método novo: só `_version += 1`) para o SSE mandar o estado novo. A leitura fica viva mesmo com o River do escritório mudo (o laço do NUT falhando): as duas fontes são independentes. `UpsSnapshot.to_dict()` e o fixture `state_online` **não mudam**; `state_nulls` é regenerado (ganha `"ble_rivers": []`). Histórico (`record_sample`) continua só do River do escritório — o do segundo é B51. | Merge na API porque `update_snapshot` só acontece com leitura boa do NUT; se a leitura BLE viajasse dentro do snapshot, o River da sala congelaria toda vez que o do escritório calasse |
| D5 | **A leitura** (dicionário do filho, chaves fixas; ausente = `null`, nunca zero): `serie, modelo, carga_pct, na_tomada (bool: plugged_in_ac), entrada_w (input_power), saida_w (output_power), entrada_ac_w (ac_input_power), entrada_dc_w (dc_input_power), tomada_ac_w (ac_output_power), saida_12v_w, usb_a_w, usb_c_w, bateria_w (pow_get_bms: >0 carregando, <0 descarregando), autonomia_s (cms_dsg_rem_time × 60, só na bateria), tempo_para_carga_s (cms_chg_rem_time × 60, só carregando), temperatura_c (bms_max_cell_temp), limite_descarga_pct (cms_min_dsg_soc), limite_carga_pct (cms_max_chg_soc), erro (errcode ≠ 0), bateria_extra_pct (battery_1_battery_level, Plus)`. Fonte de cada campo: `eflib/devices/river3.py:49-95` e `river3_plus.py:22-27` (lidos hoje). **Estados** do River lido: `procurando` (varredura sem achar), `conectando`, `lendo`, `sem_leitura` (> 30 s sem PUT — o serviço decide, pelo relógio dele), `sem_bluetooth` (TCC negado: `BleakBluetoothNotAvailableError`), `recusado` (autenticação recusada: User ID errado ou River não vinculado à conta), `parado` (`ativo=false` ou sem User ID), `erro` (qualquer outra exceção, `motivo` = tipo + 200 caracteres). | Cada nome vira uma frase na tela; "sem_bluetooth" ganha o botão que abre Privacidade › Bluetooth (`x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth`) |
| D6 | **NUT**: um `DriverDoNut` por River **ativo**, nome `river-ble-<5 últimos da série, minúsculas>` (ex.: `river-ble-f0298`; cabe em `NOME_DE_APARELHO` e no limite do caminho do soquete), declarado no `ups.conf` com `desc` = o nome do dono; `DATASTALE` em `sem_leitura`/`parado`/erros; recolhido (e a declaração reescrita → servidor reiniciado) só ao **remover ou desativar** — nunca por oscilação de leitura. Variáveis (`variaveis_do_river_ble`, nomes de `nut-names.txt`): `device.type ups`, `device.mfr EcoFlow`, `device.model` (`River 3 Plus`…, de `Device.device`), `device.serial`, `ups.status` = `OL`/`OB` por `na_tomada` + `CHRG`/`DISCHRG` por `bateria_w` (nunca `LB`: não inventamos), `battery.charge`, `battery.charge.low` (limite de descarga), `battery.runtime` (só na bateria), `battery.temperature`, `input.realpower`, `ups.realpower`, `outlet.count 4` + `outlet.n.{id,desc,realpower,switchable=no}` (a mesma tabela `TOMADAS`), `driver.name river-bridge`, `driver.version`. **Sem comandos** (`load.off` não existe aqui: B53). | A publicação é a mesma do River do escritório, com a mesma regra "ausente não vira zero" |
| D7 | **Eventos** (vocabulário fechado, `eventos.DO_SERVICO`): `RIVER_BLE_QUEDA`, `RIVER_BLE_ENERGIA_VOLTOU`, `RIVER_BLE_SEM_LEITURA`, `RIVER_BLE_LEITURA_VOLTOU`, com `device=<id do River>` e `detail` = nome. Queda/volta com os **mesmos atrasos** do laço principal (`power_loss_delay_seconds`, `restore_delay_seconds`) numa `TransicaoDoRiverBle` pura (relógio injetado) em `fontes_ble.py`; "sem leitura" após os 30 s de D5, "leitura voltou" na primeira leitura depois. Chips na barra de Eventos: um por River BLE (`EventChipSpec` ganha `rivers:`), com a cor da família de energia. | O ponto da frente é saber que o River da sala caiu; sem evento, a tela só mostraria o número mudar |
| D8 | **Login**: `ble_leitor login` lê `{"email","senha","regiao"}` da **entrada padrão** (nunca argv — `ps` mostra argv), chama `eflib.login.EcoFlowLogin` (aiohttp, já no pacote), e grava o User ID no serviço por `PUT /v1/ble/conta`; devolve `{"ok": true}` ou `{"erro": "…"}`; a senha vive só no processo, até ele sair. Alternativa na tela: "Informar o User ID…" (campo). `ble_leitor scan` → 8 s de varredura → lista `[{serie, nome_ble, sinal_dbm, modelo}]` só de aparelhos EcoFlow (fabricante `0xB5B5`), **sem** o River do escritório (série do estado) e sem os já adicionados. O filho recebe `RUB_API_PORT` e `RUB_API_TOKEN` por **ambiente** (mesma confiança que a ficha 0600 do dono). | A senha da conta não pode aparecer em `ps`, em registro nem em disco; o User ID é a credencial que fica, e fica no serviço (D2) |
| D9 | **O filho** (`ble_leitor.py`, `asyncio`): a cada 10 s `GET /v1/ble` + `GET /v1/ble/credencial`; para cada River ativo mantém uma tarefa: varredura por série (`BleakScanner` com filtro por `manufacturer_data[0xB5B5]`), `NewDevice`, `connect(user_id)`, `wait_until_authenticated_or_error`, `register_callback` → a cada atualização monta a leitura (D5) e faz `PUT …/leitura` **no máximo a cada 2 s** (o River envia `DisplayPropertyUpload` a ~1 Hz); desconexão → estado `procurando` e nova tentativa com recuo 5 → 60 s; River desativado/removido → `disconnect` e fim da tarefa. **Só toca o rádio (importa `bleak`) quando há pelo menos um River ativo com User ID** — sem isso não há diálogo de consentimento para quem não usa a função. Registro em `~/Library/Logs/River Bridge/bluetooth.log` (rotação em 1 MB, 3 arquivos), escrito pelo app a partir de stdout/stderr do filho. | "One BLE connection at a time" da EcoFlow: enquanto lemos, o app do celular não fala com esse River por Bluetooth (fala pela nuvem); o interruptor "Ler por Bluetooth" solta o rádio quando o dono quiser |
| D10 | **App** — (a) `Bluetooth/LeitorBluetooth.swift` (`@MainActor @Observable`, supervisor + `rodar(subcomando:entrada:)` para login/scan); (b) `Dashboard/RiversPorBluetooth.swift`: uma fileira de cartões logo abaixo do fluxo, só quando `bleRivers` não é vazio — nome, anel pequeno de carga (o mesmo `EnergyRing` em tamanho compacto), "Na tomada"/"Na bateria", entrada/saída em W, rodapé "via Bluetooth · há N s" / "Procurando…" / "Bluetooth não autorizado" (botão) / "Sem leitura há N min" / "Recusado: confira a conta"; (c) `Settings/BluetoothGroup.swift` (molde: `HomeAssistantGroup`): conta (estado + "Entrar na conta EcoFlow…" → folha e-mail/senha/região com `SecureField` → login; "Informar o User ID…"; "Esquecer a conta"), lista de Rivers (nome, série, interruptor Ler, Remover com confirmação), "Procurar Rivers…" → folha com a lista da varredura (nome BLE, série, sinal) e "Adicionar" com nome; (d) Saúde: um cartão por River BLE ativo ("River da sala · Bluetooth", selo do estado); (e) `Models.swift`: `UpsState.bleRivers: [RiverBluetooth]?` + `RiverBluetooth` (tudo opcional); (f) `TelemetryStore.apply`: `beat` só quando `timestamp` do River do escritório mudou — senão o logo pulsaria também a cada leitura BLE; (g) `DeviceTypeRegistry.qualquerEvento` com as quatro frases novas (PT/EN); `EventChipSpec.all(devices:rivers:)`. Zero cor/número solto (S55); textos no molde HIG já em uso. Seam `--seam-ble tests/fixtures/ble.json` para as capturas. | Só o que tem consumidor; a folha de detalhe do River BLE (como a `RiverDetailSheet`) fica para depois (B52) |
| D11 | **Empacotamento**: `build-app.sh` instala também `bleak>=3.0.2 bleak-retry-connector ecdsa~=0.19 protobuf~=6.30 pycryptodome~=3.23` (pinos da própria `ha-ef-ble/pyproject.toml`), **remove `libs/PyObjCTest`** (16 MB de testes do PyObjC, sem consumidor) e escreve `NSBluetoothAlwaysUsageDescription` no `Info.plist`; provas: `PlistBuddy Print :NSBluetoothAlwaysUsageDescription` não vazio; `codesign -dv libs/CoreBluetooth/_CoreBluetooth.cpython-313-darwin.so` com `TeamIdentifier=8A47D8UNV2`; `libs/PyObjCTest` ausente; e a prova de arranque continua contando zero arquivos novos. `eflib` embutida em `src/river_unifi_bridge/eflib/` tal qual (commit, data e licença em `src/river_unifi_bridge/eflib/VENDOR.md` + `LICENSE` da Apache-2.0 ao lado), importada **só** pelo `ble_leitor` (lazy). `pyproject.toml`: `[project.optional-dependencies] ble = […]` — o serviço em si continua com `aiohttp` como única dependência. | M2, M6; o instalador de linha de comando não muda |
| D12 | Versão **0.11.0**. | Contrato de estado novo, rotas novas, processo novo |

## Impact sweep (commands run now, 2026-09-06)

```
git status -sb; git log --oneline -1                          # main, limpo, 50642d3 (0.10.0 fechada nesta sessão)
$PY_PACOTE ble-scan.py (bleak 3.0.2, rodas reassinadas)      # M1: 21 aparelhos; EF-R3P70046 R631ZBBAWH270046 −42; EF-R3PF0298 R631Z61AXJ1F0298 −94; flags=62
$PY_PACOTE ble-scan.py (rodas como vieram do PyPI)           # M2: ImportError … different Team IDs
ssh mini … ble-scan.py                                        # M3: BleakBluetoothNotAvailableError DENIED_BY_UNKNOWN
open "River Bridge BLE Prova.app" (filho = python + scan)     # M4: rc=0, 23 aparelhos em 12.1s (esta máquina)
ssh mini open "River Bridge BLE Prova.app"                    # M5: filho vivo > 5 min sem saída (diálogo pendente na tela do mini)
PYTHONPATH=ble-libs:eflib-vendor $PY_PACOTE -c "import eflib…"   # M6: import ok; SN_PREFIX R631/R634/R635
curl pypi.org/pypi/{bleak,bleak-retry-connector,bluetooth-adapters}/json   # requires_dist (pyobjc-* só em darwin)
grep -rn "homeassistant" eflib/                               # vazio (biblioteca autônoma)
grep -rln 'add_event\|record_event\|_registrar(\|_avisar(' eflib/   # vazio: a cerca regex dos eventos não a cobre
du -sh ble-libs (41M) · PyObjCTest 16M · objc 10M             # D11: PyObjCTest sai
git grep -n "SecItem\|Keychain" macos/RiverBridge/Sources     # vazio (o app não guarda credencial; D2 mantém assim)
grep -n "beat &+= 1" TelemetryStore.swift                     # :205 — a cada estado aplicado (D10f)
sed -n 583,614p api.py                                        # o SSE manda `snapshot or _empty_state` (D4)
grep -n "def record_event" -A3 history.py                     # (event_type, detail, ts, device) — `device` existe (D7)
grep -n "def apagar_tudo" -A30 remocao.py                     # listdir do estado inteiro (D2)
grep -n "NSBluetooth" tools/build-app.sh                      # vazio (D11 acrescenta)
grep -n "pip" scripts/install.sh                              # :333 só aiohttp (o CLI não leva o leitor)
python3 -c "print(list(json.load(open('tests/fixtures/state_online.json'))))"   # identity power outlets battery health source timestamp
grep -n "state_nulls\|state_online" tests/unit/test_fixtures_contract.py   # :20 (_empty_state) :37 (to_dict)
grep -o "| B[0-9]* |" docs/BACKLOG_20260901.md | tail -1      # B50 → novos B51–B54
grep -o "^# S[0-9]*" tools/gate.sh | sort -V | tail -1        # S78 → novas S79–S84
```

## Changes, per file

**Serviço (Python)**
- `src/river_unifi_bridge/fontes_ble.py` (**novo**) — `ArmazemBle` (carrega/grava `ble.json`; `user_id`, `rivers`, ids `ble_<8 hex>`, validações de D3), `RiverBle` (dataclass), `LeituraBle` (última leitura + `lida_em` + estado informado pelo filho), `estado_publicavel(agora)` (aplica os 30 s e `ativo`/sem User ID), `TransicaoDoRiverBle` (queda/volta/sem leitura com relógio injetado), `nome_no_nut(serie)`, `variaveis_do_river_ble(river, leitura, estado)`, `status_do_nut(leitura)` (`OL/OB` + `CHRG/DISCHRG`).
- `src/river_unifi_bridge/api.py` — as rotas de D3; `_h_state`/`_h_events` mesclam `ble_rivers`; `_empty_state` ganha `"ble_rivers": []`; recusa `mesmo_river` lê `identity.serial` do último estado e `cfg.udr7_expected_serial`.
- `src/river_unifi_bridge/state.py` — `bump()`.
- `src/river_unifi_bridge/service.py` — cria o `ArmazemBle` (fora de `--once`), passa-o ao `ApiServer` e à `PonteDoNut`; a cada volta `fontes.avancar(agora)` (transições → eventos por `shared.add_event`/`history.record_event(..., device=id)`) e `ponte.atualizar_ble(fontes)`.
- `src/river_unifi_bridge/nut_servico.py` — `atualizar_ble(fontes)`: abre/recolhe `river-ble-*`, publica, `DATASTALE` por estado; `_declarar` inclui os ativos.
- `src/river_unifi_bridge/eventos.py` — os quatro nomes em `DO_SERVICO`.
- `src/river_unifi_bridge/ble_leitor.py` (**novo**) — `main(argv)` com subcomandos `ler` (padrão), `login`, `scan`; `leitura_de(device)` e `status_de(exc)` puros; o laço de D9 com `procurar`, `conectar`, `dormir`, `api` injetáveis (o teste roda sem rádio); `eflib` importada só dentro das funções que tocam o rádio.
- `src/river_unifi_bridge/eflib/` (**novo, embutido**) + `VENDOR.md` + `LICENSE`.
- `pyproject.toml` — extra `ble`; versão 0.11.0. `src/river_unifi_bridge/__init__.py` — 0.11.0.
- Testes: `tests/unit/test_fontes_ble.py`, `tests/unit/test_ble_leitor.py` (mapeamento com um `Device` de mentira; laço com varredura/conexão falsas: reconexão, desativação, PUT no máximo a cada 2 s; `login` com servidor aiohttp de teste), `tests/unit/test_api.py` (rotas, as quatro recusas, `ble_rivers` no estado e no SSE), `tests/unit/test_nut_publicacao.py`/`test_nut_servico.py` (variáveis, `DATASTALE`, recolhimento só ao remover), fixtures `state_nulls.json` (regenerado), `eventos.json` (regenerado), `ble.json` (**novo**, para `--seam-ble` e `ModelsDecodingTests`).

**App (Swift)**
- `RiverBridgeCore/Models.swift` — `UpsState.bleRivers`, `RiverBluetooth`.
- `RiverBridgeCore/TelemetryStore.swift` — `beat` só com `timestamp` novo do River do escritório; `bleRivers` exposto; seam `--seam-ble`.
- `RiverBridgeCore/APIClient.swift` — `ble()`, `bleConta(userId:)`, `bleEsquecerConta()`, `bleAdicionar(serie:nome:)`, `bleAlterar(id:nome:ativo:)`, `bleRemover(id:)`.
- `RiverBridgeCore/DevicePlugins.swift` — as quatro frases em `qualquerEvento`; `EventChipSpec.all(devices:rivers:)`.
- `RiverBridgeCore/TextoDoRiverBluetooth.swift` (**novo**, puro) — rótulos do cartão ("—" sem leitura, "há N s", os estados de D5 em PT/EN).
- `RiverBridgeApp/Bluetooth/LeitorBluetooth.swift` (**novo**) — supervisor de D1/D9 + `rodar(subcomando:entrada:)`.
- `RiverBridgeApp/RiverBridgeApp.swift` — `ReopenDelegate.applicationWillTerminate` encerra o filho; o supervisor nasce com o `store`.
- `RiverBridgeApp/Dashboard/RiversPorBluetooth.swift` (**novo**); `Dashboard/DashboardWindow.swift` (`EnergiaSection` insere a fileira); `Dashboard/EventsTimeline.swift` (chips com rivers).
- `RiverBridgeApp/Settings/BluetoothGroup.swift` (**novo**) + folhas de login e de varredura; `Settings/SettingsView.swift` (o grupo antes do Home Assistant).
- `RiverBridgeApp/Health/HealthView.swift` — cartões dos Rivers BLE.
- Testes Swift: `ModelsDecodingTests` (`ble.json`), `TextoDoRiverBluetoothTests` (sem leitura → "—"; idade; cada estado tem frase), `EventosContractTests` (continua verde com os nomes novos), `TelemetryStoreTests.oBatimentoNaoPulsaComLeituraSoDoBluetooth`, `EventChipTests` (chip por River BLE).

**Empacotador, gate, docs**
- `tools/build-app.sh` — D11 (dependências, `PyObjCTest` fora, `NSBluetoothAlwaysUsageDescription`, três provas).
- `tools/gate.sh` — S79 (mutante: `POST /v1/ble/rivers` aceita a série do River do escritório → `test_refuses_the_office_river_serial` reprova), S80 (mutante: `estado_publicavel` ignora os 30 s → `test_a_reading_older_than_30s_is_stale` reprova), S81 (mutante: `status_do_nut` troca `OL`/`OB` → `test_status_on_battery_is_ob` reprova), S82 Swift (mutante: `TextoDoRiverBluetooth.carga(nil)` devolve "0 %" → `semLeituraETraco` reprova), S83 Swift (mutante: `apply` volta a pulsar sempre → `oBatimentoNaoPulsaComLeituraSoDoBluetooth` reprova), S84 (prova de texto do `build-app.sh`: as três provas de D11 existem, como a S78 faz com o widget).
- `docs/reference/api-local.md` — as rotas de D3, `ble_rivers` no estado, os estados de D5. `docs/decisions/2026-09-06-1800-o-bluetooth-e-lido-pela-sessao-do-usuario.md` (**novo**, `aceito` ao aprovar): M3/M4 como fundamento. `docs/guides/2026-09-05-2200-runbook-…` — seção "O River da sala por Bluetooth" (conta, procurar, permitir o Bluetooth, o que acontece com o app da EcoFlow). `README.md` (linha). `CHANGELOG.md` `[0.11.0]`. `docs/BACKLOG_20260901.md` — B39 emendada (login key não existe; medições M1–M7; ao fechar: FEITO), B51 (histórico do 2.º River), B52 (folha de detalhe e widget com o 2.º River), B53 (ordens por Bluetooth: ligar/desligar saídas, limites — a `eflib` as tem), B54 (atualização de firmware da EcoFlow pode mudar o protocolo; a integração avisa). Este plano + `-banca.md` no mapa `docs/README.md`. Handoff vivo: §5d com a bancada.
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
| 1 | `POST /v1/ble/rivers` com a série do River do escritório, uma série repetida, um nome repetido ou uma série fora da forma | recusar com 409 `mesmo_river` / 409 `serie_repetida` / 409 `nome_duplicado` / 400 `serie_invalida`, sem gravar | `test_api.py::test_refuses_the_office_river_serial`, `::test_refuses_a_repeated_serial`, `::test_refuses_a_repeated_name`, `::test_refuses_a_malformed_serial`; S79 | qualquer 2xx ou `ble.json` alterado |
| 2 | o filho manda `PUT …/leitura` e depois cala 30 s | `GET /v1/state.ble_rivers[0].estado` = `lendo` com `idade_s` < 30 e depois `sem_leitura`; o NUT recebe `DATASTALE`; evento `RIVER_BLE_SEM_LEITURA` uma vez e `RIVER_BLE_LEITURA_VOLTOU` na leitura seguinte | `test_fontes_ble.py::test_a_reading_older_than_30s_is_stale` (relógio injetado), `test_nut_servico.py::test_ble_river_goes_stale_not_removed`; S80 | estado vivo além de 30 s; aparelho recolhido por oscilação; evento repetido |
| 3 | a leitura diz `na_tomada=false` por mais que `POWER_LOSS_DELAY_SECONDS` e depois `true` por mais que `RESTORE_DELAY_SECONDS` | `RIVER_BLE_QUEDA` e `RIVER_BLE_ENERGIA_VOLTOU` com `device=<id>`; `ups.status` = `OB DISCHRG` e depois `OL CHRG` | `test_fontes_ble.py::test_power_loss_and_restore_follow_the_delays`, `::test_status_on_battery_is_ob`; S81 | evento antes do atraso, sem `device`, ou `OL` na bateria |
| 4 | a tela recebe um estado com `ble_rivers` | o cartão mostra nome, carga, estado e "há N s"; sem leitura mostra "—" e a frase do estado; os quatro eventos têm frase PT/EN; o logo **não** pulsa com leitura só do Bluetooth | `TextoDoRiverBluetoothTests`, `EventosContractTests`, `TelemetryStoreTests.oBatimentoNaoPulsaComLeituraSoDoBluetooth`; S82, S83; capturas PT/EN e 414 pt com `--seam-ble` lidas em imagem | número inventado; nome cru de evento; pulso a cada leitura BLE |
| 5 | o app abre com o serviço no ar e um River ativo com User ID | o filho sobe (um processo `python3 … ble_leitor`), o macOS pede o Bluetooth **uma vez** em nome do River Bridge; negado → estado `sem_bluetooth` com o botão de Privacidade; o app sai → o filho some | bancada no mini (`pgrep -fl ble_leitor`; `GET /v1/ble`); `test_ble_leitor.py::test_the_child_exits_on_stdin_eof` | filho órfão após sair; diálogo em nome de "python3"; leitor tocando o rádio sem River ativo |
| 6 | Ajustes › Rivers por Bluetooth › Entrar na conta com credenciais válidas | `GET /v1/ble.conta.tem_user_id` = true; a senha não aparece em `ps`, no registro nem em disco (`grep -r` na pasta de estado e no log) | bancada no mini (o dono digita); `test_ble_leitor.py::test_login_reads_credentials_from_stdin_and_puts_the_user_id` (servidor aiohttp de teste) | senha em argv/log/disco; User ID não gravado |
| 7 | Procurar Rivers… no mini | a lista traz `R631Z61AXJ1F0298` (o River da sala) com sinal, sem o do escritório | bancada no mini — **é a medição de alcance** | lista vazia com o River ligado a poucos metros (alcance insuficiente → frente parada, ver Open questions) |
| 8 | River adicionado e ativo no mini | `printf 'LIST VAR river-ble-f0298\n' \| nc 127.0.0.1 3493` traz `ups.status`, `battery.charge`, `input.realpower`, `outlet.count 4`; o Home Assistant vê o aparelho; `LIST UPS` traz `river-bridge`, `river-ble-f0298` e o do escritório | bancada no mini | variável ausente; aparelho ausente |
| 9 | o River da sala é tirado da tomada (dono presente) | cartão "Na bateria" em ≤ 2 s + `POWER_LOSS_DELAY` s; evento na linha do tempo com o chip dele; o UDR7 **não** reage (a proteção lê só o escritório) | bancada no mini, com o dono | UDR7 reagindo; evento ausente |
| 10 | o gate roda | verde (S15/B17 e o que o fecho da 0.10.0 registrar), S79–S84 verdes; pytest; swift test; docs-check; lychee | gates | qualquer vermelho fora do já declarado |
| 11 | 0.11.0 publicada e instalada no mini | serviço 0.11.0; `ble.json` 0600 root; app sobe, filho sobe; pacote ≤ 95 + 30 MB (medido, com `PyObjCTest` fora); prova de arranque zero arquivos novos | bancada abaixo | qualquer passo diferente |

## Ordem de commits
| # | Commit | Cercas |
|---|---|---|
| C0 | plano em `docs/plans/`, revisão fria, decisão em `docs/decisions/`, `.roadworthy/scope`, backlog B39 emendada + B51–B54 | — |
| C1 | `eflib` embutida + `VENDOR.md` + `LICENSE`; extra `ble` no `pyproject`; `build-app.sh` (dependências, `PyObjCTest` fora, `Info.plist`, provas) | S84 |
| C2 | `fontes_ble.py` + `state.bump` + rotas + `ble_rivers` no estado/SSE + fixtures + testes | S79, S80 |
| C3 | eventos + transições + ponte do NUT (`atualizar_ble`) + testes | S81 |
| C4 | `ble_leitor.py` (ler/login/scan) + testes sem rádio | — (testes) |
| C5 | app: modelos, store (`beat`), `APIClient`, frases de eventos, chips, `TextoDoRiverBluetooth` + testes | S82, S83 |
| C6 | app: supervisor do filho, cartões (Energia, Saúde), grupo de Ajustes, folhas de login/varredura, seam | — |
| — | **revisão fria sobre o diff C1–C6** | — |
| C7 | capturas lidas (Energia com a fileira, Ajustes › Bluetooth, folha da varredura, Saúde, 414 pt, PT/EN) e ajustes | — |
| C8 | CHANGELOG, versão nos 6 arquivos, docs, runbook, `tools/release.sh v0.11.0 --no-gate` após gate verde, push | — |
| C9 | bancada no mini + handoff §5d + memória; commit + push | — |

## Bancada no Mac mini (C9)
1. (Antes, pelo dono) permitir o Bluetooth para o app-prova que está esperando na tela do mini — `saida.txt` diz se o rádio alcança o River da sala. Se **não** alcança, a frente para em C0 e volta ao dono com a medição (ver Open questions).
2. `curl` do DMG + `SHA256SUMS`; `spctl`; instalar em `/Applications`; `Info.plist` 0.11.0; `NSBluetoothAlwaysUsageDescription` presente.
3. Reiniciar o serviço; `GET /v1/ble` → `{"conta": {"tem_user_id": false}, "rivers": []}`; `ls -la <estado>/ble.json` ausente ainda.
4. (Dono) Ajustes › Rivers por Bluetooth › Entrar na conta EcoFlow (e-mail/senha). Eu meço: `tem_user_id: true`; `ls -la ble.json` → `-rw------- root`; `grep -r "<senha>"` no estado e no log → nada (o dono confirma que a senha não aparece; eu não a conheço).
5. (Dono) Procurar Rivers… → lista (medição de alcance, item 7) → Adicionar "River da sala" → Ler ligado. Eu meço: `pgrep -fl ble_leitor`; o diálogo do Bluetooth (dono permite); `GET /v1/state | jq .ble_rivers` → `lendo`, `idade_s` < 5; `LIST VAR river-ble-f0298`; `LIST UPS`.
6. (Dono) tirar o River da sala da tomada → cartão, evento, `ups.status OB`; religar → `OL`, evento.
7. Sair do app → `pgrep` vazio; 30 s → `DATASTALE` (`LIST VAR` continua, `upsc` diz *stale*); abrir o app → volta a `lendo`.
8. Desligar "Ler por Bluetooth" → aparelho recolhido do `ups.conf` (uma reinicialização do servidor do no-break, registrada), o app da EcoFlow no celular volta a falar por Bluetooth com ele (dono confirma).

## Verification (after the last commit)
- `GATE_SKIP_XCODEBUILD=1 tools/gate.sh` → verde fora do já declarado, S79–S84 verdes; `.venv/bin/pytest`; `cd macos/RiverBridge && swift test` (3 vezes, idioma global); `docs-check.sh docs --since 2026-09-01`; `lychee --offline --root-dir . docs/`; `tools/release.sh --check` → 0.11.0; `gh release view v0.11.0`; bancada colada no handoff.

## Refutation
- S79 `api.py`: mutante tira a comparação com `identity.serial` → `test_refuses_the_office_river_serial` reprova (POST com `R631ZBBAWH270046` passa a 201).
- S80 `fontes_ble.py`: mutante `LIMITE_SEM_LEITURA_S = 30` → `10**9` → `test_a_reading_older_than_30s_is_stale` reprova.
- S81 `fontes_ble.py`: mutante troca `"OB" if not na_tomada else "OL"` → invertido → `test_status_on_battery_is_ob` reprova.
- S82 Swift (`cena_mutacao_swift`): `TextoDoRiverBluetooth.carga(nil)` → `"0 %"` → `semLeituraETraco` reprova.
- S83 Swift: `apply` volta a `beat &+= 1` incondicional → `oBatimentoNaoPulsaComLeituraSoDoBluetooth` reprova.
- S84: prova de texto de `build-app.sh` (as três provas de D11 nomeadas), como a S78.
- O laço do filho (`ble_leitor`) não tem cena de mutação: as cercas são testes com varredura/conexão de mentira (reconexão com recuo, PUT ≤ 1/2 s, saída por EOF); um mutante no recuo seria refutado por `test_reconnect_backoff_grows` — fica registrado como cerca sem cena porque a S-cena exigiria o rádio.

## Out of scope
- Histórico e gráficos do segundo River (B51); folha de detalhe e widget com ele (B52); ordens por Bluetooth (B53).
- Proteção (desligar aparelhos) a partir do segundo River: ele é fonte de leitura; a política continua lendo o `usbhid-ups` do escritório.
- Outros modelos EcoFlow (a `eflib` cobre; só o River 3 / 3 Plus entra na lista de varredura nesta versão).
- Um repetidor Bluetooth se o alcance do mini não bastar (decisão do dono; ver Open questions).

## Overnight policy
- Decidido à noite, com fonte: nomes do NUT (`nut-names.txt`), mapeamento dos campos (`river3.py`/`river3_plus.py`), limiares (30 s de leitura, recuo 5→60 s — declarados, não medidos; medidos na bancada), textos PT/EN no molde HIG, pinos das dependências (`ha-ef-ble/pyproject.toml`).
- Reservado ao dono: push e release; qualquer ato no mini que instale/remova; **entrar na conta EcoFlow** (credenciais dele); permitir o Bluetooth; tirar o River da tomada; julgamento visual das capturas.

## Open questions
- [NEEDS CLARIFICATION: o River `R631Z61AXJ1F0298` (visto a −94 dBm daqui) é o da sala, e está **vinculado à sua conta EcoFlow** no app? Sem vínculo a autenticação é recusada pelo próprio aparelho.]
- [NEEDS CLARIFICATION: aceita que, enquanto o Mac mini lê o River da sala, o app da EcoFlow no celular **perca o caminho Bluetooth** com ele (continua pela nuvem/Wi-Fi)? É limite do aparelho ("one BLE connection at a time"), e o interruptor "Ler por Bluetooth" devolve o rádio.]
- [NEEDS CLARIFICATION: aceita digitar e-mail e senha da conta EcoFlow **uma vez** no River Bridge do mini, indo só ao servidor da EcoFlow (`api.ecoflow.com/auth/login`) para obter o User ID? Alternativa: colar o User ID do app da EcoFlow (Perfil › ID do usuário).]
- Alcance: o app-prova está esperando o seu "Permitir" na tela do mini; a resposta fica em `/private/tmp/river-ble-prova/saida.txt`. Se o rádio do mini não vir o River da sala, esta frente não tem como ler — e a decisão (aproximar, outro Mac, repetidor) é sua.
