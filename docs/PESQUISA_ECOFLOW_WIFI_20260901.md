# River 3 Plus via Wi-Fi/rede — varredura das fontes citadas (2026-09-01)

Pergunta do dono: "há fonte que já fez funcionar via Wi-Fi, inclusive conversando
com o UniFi". Método: as 10 fontes citadas na spec/docs lidas POR INTEIRO
(issues do NUT via API com 100% dos comentários; threads Discourse/NodeBB via
JSON com posts_count conferido; manual extraído da SPA) + varredura do
ecossistema completo de integrações EcoFlow. Material bruto para auditoria no
scratchpad da sessão. [P]=fonte lida direta; [S]=extração/relato.

## VEREDITO

**Não existe caminho Wi-Fi LOCAL comprovado para o River 3 Plus.** O rádio
Wi-Fi dele só fala com a cloud da EcoFlow — é o que o manual oficial define
("With Internet… via the internet; Without Internet… via **Bluetooth**") e o
que os participantes do NUT #2735 confirmam ("it would make much more sense if
it could act as a NUT server over the network… **but that doesn't seem to be
the case**"). Os caminhos que JÁ FUNCIONARAM são:

| Caminho | Local? | Comprovado p/ R3P? | Fonte |
|---|---|---|---|
| **USB → host com NUT ≥2.8.3 → NUT na LAN** | ✅ | ✅ (múltiplos relatos: Arch, RPi, Docker, LXC/Proxmox com receita completa, TrueNAS) | NUT #2735/#3306, TrueNAS t/46870 [P] |
| **USB → EcoFlow Power Manager/PowerManagerNUT (oficial) → NUT :3496 na LAN → HA conectou** | ✅ (após setup) | ✅ (peros550: "successful in connecting a Home Assistant NUT integration"; user/pass Ecoflow/Ecoflow) | NUT #2735 [P] |
| **BLE local → HA (rabits/ha-ef-ble) ou → NUT (Ecoflow-BLE-NUTd)** | ✅ (bootstrap 1x de user_id via conta) | ✅ ("River 3 (Plus…)" suportado; rogertheriault: "lots of stats… you can also control the UPS") | github.com/rabits/ha-ef-ble [P] |
| **Wi-Fi → cloud EcoFlow → HA** (ioBroker.ecoflow-mqtt; tolwi branch; Developer API) | ❌ cloud | ✅ (ioBroker desde v1.4.8; JoshuaDodds "tested with River 3 Plus" via Developer API MQTT) | [P] |
| Wi-Fi → LAN direto (sem cloud) | — | ❌ NÃO ENCONTRADO em nenhuma fonte/projeto (o único integrador LAN, vwt12eh8, morreu em 2023 cobrindo só a geração 1; redirecionamento DNS do MQTT nunca chegou a controle local) | [P] |

**"Conversa com o UniFi":** a única fonte citada com UniFi é a thread do HA
Community sobre o **UniFi UPS Tower** — o UPS DA UBIQUITI, que embarca servidor
NUT na :3493 (com bug de auth corrigido por firmware em fev/2026). É o modelo
de referência do que nossa bridge emula para o River — não um caso de EcoFlow
falando com UniFi.

## Achados extras valiosos

- **Watts em tempo real existem LOCALMENTE** — mas pela **serial USB CDC**, não
  pelo HID: greyltc/r3pcomms reverteu o protocolo do Power Manager. Casa com a
  §13 da spec (river-cdc-sniffer) e destrava potência/uso no nosso app.
- **LB**: confirmação tripla de que nunca dispara; o workaround maduro da
  comunidade é `ignorelb` + `override.battery.charge.low` no ups.conf (receita
  completa do QonoS no Proxmox) — entra no installer da Fase 1.
- O Power Manager oficial da EcoFlow é um **fork fechado do NUT 2.8.2**
  (build efsz, porta 3496, credencial Ecoflow/Ecoflow; questão GPL aberta).
- Descritor HID do R3P é malformado ("unbalanced collection") — confirmado em
  Linux e Windows; explica flakiness de detecção.

## Consequência para o ups-rack (decisões do dono)

O River do rack NÃO alcança a LAN sozinho sem cloud. Opções reais, por fonte:
1. **BLE do próprio Mac mini** → daemon BLE→NUT no mini (protocolo do
   ha-ef-ble; projeto Ecoflow-BLE-NUTd é embrião mas o protocolo está provado).
   Zero host novo, 100% local. Limite físico: alcance BLE mini↔rack; limite
   técnico: 1 conexão BLE por vez (bloqueia o app), estabilidade com issues
   abertos.
2. **Cloud como via de VISIBILIDADE** (ioBroker/Developer API) — se o dono
   relaxar a §2.2 para telemetria não-crítica; caminho crítico continuaria
   local (o rack protege eletricamente por conta própria).
3. USB a algum host existente perto do rack (a spec §26 proíbe *presumir*
   gateway novo; usar host que já exista é permitido).
