# Matriz de Hipóteses H01–H17 (spec §9)

> **Regra absoluta:** o estado permanece **UNKNOWN** até haver **evidência reproduzível**
> (captura de tráfego, firmware ou teste real). Documentação pública pode **fortalecer** ou
> **enfraquecer** uma hipótese, mas NUNCA a promove a TRUE/FALSE. Toda evidência com URL + data.
> **Data de consulta desta rodada:** 2026-08-31.
>
> Legenda da coluna Tendência (só orientação, não veredito):
> `↑` fortalecida por doc pública · `↓` enfraquecida por doc pública · `→` inalterada / sem evidência.

---

## Evidências iniciais (ponto de partida herdado da spec)

- **E0-A — Blog oficial de lançamento.** "Instant adoption in UniFi Network"; "Built-in NUT server
  support for third-party systems and clients". O NUT é apresentado apenas na direção **UPS →
  terceiros** (o UPS é o servidor NUT); nenhuma menção a UPS de terceiros aparecendo na UI do UniFi.
  URL: https://blog.ui.com/article/introducing-uninterruptible-power — 2026-08-31.
  Relevante para: **H01, H06, H10**.
- **E0-B — Feature request "UDMP as a NUT client".** Indício forte de **ausência de suporte nativo**
  para o console UniFi consumir um UPS de terceiros via NUT.
  URL: https://community.ui.com/questions/UDMP-as-a-NUT-Network-UPS-Tools-client/15680458-6fe3-4ac8-bf4b-c8e1e7ecd6f6 — 2026-08-31.
  Relevante para: **H10**.

---

## Tabela H01–H10 (UniFi nativo)

| ID | Enunciado | Estado | Tend. | Evidência pública (URL + data 2026-08-31) |
|----|-----------|--------|-------|--------------------------------------------|
| **H01** | O UPS Tower usa o protocolo **UniFi Inform tradicional** (HTTP POST `/inform`, payload AES) para comunicar com o controlador. | **UNKNOWN** | → | Inform tradicional documentado para APs/gateways (POST `/inform`, AES-128-CBC/GCM, header `TNBU`): github.com/jk-5/unifi-inform-protocol; github.com/fxkr/unifi-protocol-reverse-engineering. **Nenhuma fonte confirma que o UPS use inform**; ele tem firmware "UniFi UPS" próprio e é adotado (LED "waiting for adoption": techspecs.ui.com/unifi/integrations/ups-tower-us). Indeciso entre H01/H02/H03 sem captura. |
| **H02** | O UPS usa um **WebSocket próprio** (transporte do UniFi OS) em vez do inform clássico. | **UNKNOWN** | → | UniFi OS moderno usa WebSocket para eventos (github.com/NickWaterton/Unifi-websocket-interface). Plausível, mas **sem evidência** de que o UPS use WS para o canal de gerência. Só captura decide. |
| **H03** | O UPS usa **MQTT interno** do UniFi OS. | **UNKNOWN** | → | Sem qualquer evidência pública de MQTT no canal UPS↔controlador. (MQTT aparece só em pontes de terceiros: unifi2mqtt.) Mantido como alternativa aberta. |
| **H04** | O UniFi Network **valida manufacturer/model** do device na adoção (rejeita device desconhecido). | **UNKNOWN** | → | Sem doc pública sobre validação de identidade específica. Existência de emuladores de AP/gateway (ZAP-Quebec/unifi-fake-device, qvr/unifi-gateway) sugere que APs clássicos podiam ser simulados, mas isso **não** cobre o UPS nem versões atuais do UniFi OS. Requer teste. |
| **H05** | O UniFi Network **valida certificado por device** (identidade criptográfica) na adoção. | **UNKNOWN** | → | Modelo inform clássico troca chave AES via SSH na adoção (github.com/jk-5/unifi-inform-protocol) — isso é chave simétrica de sessão, não prova certificado por device. Comportamento atual do UniFi OS **desconhecido** publicamente. |
| **H06** | O device type **"UPS" pode ser emulado** para aparecer como device gerenciável na UI. | **UNKNOWN** | ↓ | UPS aparece como device de 1ª classe (badges de power protection; botão "Replacement Device" — releasebot.io/updates/ubiquiti; Android 10.39.6). Emular exigiria falar o protocolo/estado exatos do UPS, **não documentados** publicamente. Nenhum emulador público cobre o tipo UPS. Enfraquecida por complexidade, não refutada. |
| **H07** | A **UI de UPS depende de adoção real** (o painel de UPS só existe para um device adotado). | **UNKNOWN** | ↑ | Reviews: "all status information is only available inside the UniFi controller"; dashboard mostra bateria/carga/runtime/firmware/IP/MAC (networkdevicesinc.com/...; storagereview.com/...). Toda telemetria depende do device adotado — **consistente** com H07, mas não a prova (não testa se um device forjado adotado dispara a mesma UI). |
| **H08** | O **Alarm Manager aceita eventos** originados de um UPS emulado. | **UNKNOWN** | → | Sem qualquer documentação pública sobre o comportamento do Alarm Manager com UPS (real ou emulado). Só teste responde. |
| **H09** | O **graceful shutdown exige trust/device identity** (o comando de shutdown pareado só funciona entre devices UniFi legítimos). | **UNKNOWN** | ↑ | Safe Shutdown Pairing é **restrito a UNAS/UNVR** (devices UniFi); "command it to shut down gracefully" (networkdevicesinc.com/...). Graceful Shutdown exige **UniFi OS ≥ 4.4.3** (store.ui.com/us/en/products/ups-tower-us). Sugere caminho fechado/pareado UniFi-only — **consistente** com H09, sem prova de mecanismo de trust. |
| **H10** | Existe **API de integração de device de terceiros** que permite criar/registrar um UPS na UI do UniFi. | **UNKNOWN** | ↓ | Site Manager API oficial é leitura/inventário (List Hosts/Sites/Devices), **sem endpoint de UPS/power e sem criação de device** nas buscas (developer.ui.com/site-manager-api/listhosts/; getting-started). NUT é unidirecional (UPS→terceiros). Feature "UDMP as NUT client" **não** existe (E0-B). Fortemente enfraquecida, mas não refutada (referência completa da API não lida — páginas JS). |

---

## Tabela H11–H17 (Fase 3'-EXP — proteção do UDR7 via SSH; adicionada 2026-09-01)

| ID | Enunciado | Estado | Tend. | Evidência (URL + data 2026-09-01) |
|----|-----------|--------|-------|-----------------------------------|
| **H11a** | `ubnt-systool poweroff` existe no **UDR7** e desliga graciosamente; o usuário é `root`. | **UNKNOWN** | → | Fonte **única e secundária**: gist Freekers (alvo **UDM Pro**), https://gist.github.com/Freekers/c8e4b75e02bf26e68c4ee6da5a6b2392 — `root`, `ubnt-systool poweroff`. Nada específico do UDR7. Medição: runbook passo 4 (`command -v ubnt-systool`). |
| **H11b** | Login SSH por **chave pública** para `root` funciona no UDR7 e persiste. | **UNKNOWN** | → | O gist usa **senha** (`sshpass`); chave é premissa nossa (§15 exceção 4). Medição: runbook passo 4. |
| **H12a** | Firmware update do UniFi OS apaga `authorized_keys`. | **UNKNOWN** | ↑ | docs/PESQUISA_UDR7_UPS_TERCEIROS_20260831.md:67-68 [S] ("credencial/chave SSH resetada em firmware update"). Mitigação: re-semear após update (runbook). |
| **H12b** | Firmware update troca a host key do console. | **UNKNOWN** | → | **INFERIDO** (nenhuma fonte). Efeito coberto: `StrictHostKeyChecking=yes` → `UDR7_SHUTDOWN_FAILED` visível, nunca aceite silencioso. |
| **H13** | O UDR7 boota sozinho ao receber energia após um `poweroff` (cenário: rede volta depois de o River cortar a saída). | **UNKNOWN** | → | research/unifi-official.md:158-160 [CONFIRMADO] fala de UNAS/UNVR pareados ao UPS Tower ("não religam sozinhos"); aplicabilidade ao UDR7 = **INFERIDO**. Medição: runbook passo 5. |
| **H14** | O UDR7 acorda por Wake-on-LAN após `poweroff` (cenário: rede volta antes do corte). | **UNKNOWN** | → | **Nenhuma fonte** aberta em 2026-09-01 confirma WoL como alvo em consoles UniFi (threads da comunidade não carregaram). Mantido a pedido do dono; o daemon só envia após um `SENT` (ensaio: `UDR7_WOL_DRYRUN`). Medição: runbook passo 5. |
| **H15** | O River 3 Plus expõe `device.serial` estável via NUT ≥ 2.8.4. | **UNKNOWN** | ↑ | NUT issue #2735, https://github.com/networkupstools/nut/issues/2735 — dump com `device.serial`/`ups.serial` (redigidos) e `driver.name: usbhid-ups`, **`driver.version 2.7.4`** (caminho genérico, pré-`ecoflow-hid`) → para 2.8.4+ é **INFERIDO**. Medição: runbook passo 1, com o simulador parado. |
| **H16** | O River reenergiza a saída AC sozinho quando a rede volta após corte por Discharge Limit. | **UNKNOWN** | → | Depende de AC Timeout = never (docs/PESQUISA_PARAMETROS_UPS_20260831.md:45-48 [P manual]) e de Output Port Memory — **semântica não encontrada em fonte** (o manual só nomeia). Medição: runbook passo 5. |
| **H17** | Ponto real de corte da saída AC do River (Discharge Limit + 1 %?). | **UNKNOWN** | → | Dois [P] contraditórios: PESQUISA_PARAMETROS:22-23 ("corta em limite+1 %", código do driver) × :33-38 ("descarga até 0 % sem LB", issue #3068). Medição: runbook passo 1 (descarregar com carga conhecida e anotar). |

## Notas de convergência para as próximas etapas

- **H01/H02/H03 são mutuamente exclusivas quanto ao transporte principal** e **nenhuma** tem
  evidência pública decisiva. Prioridade máxima da Etapa 2 (captura de tráfego do UPS real).
- **H06/H10 definem a viabilidade do projeto** (apresentar EcoFlow via NUT como UPS gerenciável).
  A documentação pública **enfraquece ambas** (↓): não há API de criação de device nem NUT de
  entrada; a UI de UPS depende de adoção real (H07 ↑). Isso empurra a solução para
  **emulação de device** (H06) — cujo custo depende de H01/H04/H05.
- **H04/H05 são o gargalo técnico da emulação.** Se o UniFi OS atual valida identidade/certificado
  por device, emular um UPS torna-se caro ou inviável sem chaves legítimas.
- **H09** sinaliza que mesmo emulando a UI, o **graceful shutdown pareado** pode exigir trust que um
  device forjado não possui — a função crítica (desligar o console na falta de energia) pode não
  ser alcançável por emulação.
