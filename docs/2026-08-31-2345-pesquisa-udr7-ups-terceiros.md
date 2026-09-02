---
status: aceito
---

# UDR7/UniFi OS enxerga UPS de terceiros? — Pesquisa definitiva (2026-08-31)

Pergunta do dono: a UI do UDR7 oferece algum lugar para consumir um UPS de
terceiros? Regra: fato com URL; [P]=fonte primária Ubiquiti; [S]=secundária;
NÃO ENCONTRADO jamais preenchido.

## VEREDITO

**Não. Nenhum console UniFi OS (UDR7 incluído) tem mecanismo nativo para
enxergar ou consumir um UPS de terceiros.** O NUT da Ubiquiti opera numa
direção só — o UniFi UPS é *servidor* NUT para terceiros consumirem, nunca o
console como *cliente* — e o Safe Shutdown oficial exige um UPS Ubiquiti, que
desliga os pareados via SSH.

## Evidência

1. **UI oficial**: o artigo de redundância de energia cobre só hardware
   próprio (SmartPower RPS, USW Mission Critical, UniFi Power Backup) — nada
   de UPS externo. [P] https://help.ui.com/hc/en-us/articles/360042834933-Power-Redundancy
   Nenhuma tela "NUT client"/"External UPS" em help.ui.com, release notes ou
   capturas de usuários (NÃO ENCONTRADO).
2. **A direção do NUT é confirmada em texto oficial**: "Built-in NUT server
   capability extending safe shutdown support to third-party servers" — o UPS
   deles serve terceiros. [P] https://ui.com/integrations/power-tech/ups-solutions ·
   https://blog.ui.com/article/introducing-uninterruptible-power
3. **Safe Shutdown Pairing** (UniFi OS ≥4.4.3): só lista dispositivos
   Ubiquiti (UNVR/UNAS; consoles chegando por early-access) e o mecanismo é o
   UPS empurrar shutdown via SSH com credenciais fornecidas. [S]
   https://community.ui.com/questions/UPS-2U-Safe-Shutdown-Pairing/a6e8855f-f71d-4d5a-9130-941956bc28d4
4. **"Improved NUT Client reporting to the Network Application"** (UPS fw
   1.4.30) [P: https://community.ui.com/releases/UniFi-UPS-1-4-30/4a8d4915-c4f8-4f54-8a04-0d66190456b1]:
   interpretação (inferência declarada) — o UPS reporta ao console os NUT
   *clients* de terceiros conectados A ELE; nenhuma fonte afirma cliente NUT
   nativo no console.
5. **USB**: UDR7 NÃO tem porta USB (1×SFP+, 4×2.5GbE, microSD). [P]
   https://techspecs.ui.com/unifi/cloud-gateways/udr7 — sem caminho USB-UPS
   em console algum (pedidos da comunidade sem atendimento). [S]
6. **Cliente NUT no console — pedidos negados**: feature request no UDM Pro
   sem atendimento; issues no unifios-utilities fechadas "not planned". [S]
   https://community.ui.com/questions/Please-add-a-NUT-client-to-UDM-Pro-for-graceful-shutdown/15abe09f-0b39-4d73-bbc3-a2e45d48c5ab ·
   https://github.com/unifi-utilities/unifios-utilities/issues/528
7. **Spoof/emulação de UniFi UPS**: NÃO ENCONTRADO nenhum projeto público
   (existem emuladores do protocolo inform para APs/switches, nenhum para UPS).

## Adendos da segunda frente (convergiu no mesmo veredito)

- **UDR7 e elegibilidade**: roda a linha "UniFi OS – Dream Routers" 4.x
  (≥4.4.3 atendido) com Network 10.x — ou seja, PODE gerenciar um UniFi UPS
  adotado; os recursos de UPS da Network 10.x ("UPS integrations also gain a
  new battery threshold configuration") referem-se só ao UPS Ubiquiti. [P]
  https://community.ui.com/releases/UniFi-OS-Dream-Router-7-4-1-21/519ec9ff-8ef1-4275-b59d-c4e21f02004a ·
  https://blog.ui.com/article/introducing-unifi-network-10-4
- **Adoção é via protocolo inform, não NUT**: emular só um NUT server não
  torna nada "adotável"; seria preciso emular um dispositivo UniFi completo.
  [S] https://www.hostifi.com/blog/how-to-adopt-the-unifi-ups-to-a-remote-unifi-controller
- **SNMP no UniFi é agente, não gerente** — serve para Zabbix/PRTG monitorarem
  os UniFi, não para o console monitorar UPS. [P]
  https://help.ui.com/hc/en-us/articles/33502980942615-SNMP-Monitoring-in-UniFi-Network
- Curiosidade útil para a Fase futura: o NUT do UPS Tower usa credencial
  default `nut`/`nut`. [S]
  https://community.ui.com/questions/UPS-Tower-NUT-server-configuration/daa92174-91fb-40ac-bbe5-19f77195eae6

## Caminhos reais (esforço/risco crescente)

| # | Caminho | Como | Risco |
|---|---|---|---|
| 1 | **NUT externo + SSH poweroff** (padrão da comunidade) | nosso upsmon no mini, em OB+LB/limiar, faz SSH no console e roda `ubnt-systool poweroff` — nada instalado no UniFi | credencial/chave SSH resetada em firmware update (detectável por health-check) [S] https://gist.github.com/Freekers/c8e4b75e02bf26e68c4ee6da5a6b2392 |
| 2 | nut-client via apt DENTRO do console (é Debian) | upsmon no próprio UDR apontando ao nosso upsd | apagado em firmware update; exige unifi-on-boot [S] https://github.com/WhiskeyTang0F0xtr0t/unifi |
| 3 | Comprar um UniFi UPS | integração nativa total | não usa o River (troca o problema) |
| 4 | Emular UniFi UPS (inform) | engenharia reversa do zero | sem precedente público; alto |

## Consequência para o projeto (Fase 3 redefinida)

"O UDR7 ver o River" **não tem caminho nativo documentado** (a matriz §30 da Fase 0
segue com H06/H10 UNKNOWN — ausência de evidência, não prova de impossibilidade). O
objetivo de negócio real — **o UDR7 protegido pelo River** — tem o caminho 1 descrito
por **uma fonte [S]** (o gist acima: alvo UDM Pro, usuário `root`, autenticação por
**senha** via `sshpass`); para o UDR7 e para login por chave são hipóteses H11a/H11b
(`research/hypotheses.md`). Visibilidade fica no nosso app + HA (NUT de verdade);
proteção do console vira AÇÃO da bridge (shutdown gracioso via SSH no evento certo) como
**fase experimental separada** (spec §2.5; plano Fase 3'-EXP, 2026-09-01). Emulação
(caminho 4) só se o dono decidir bancar reverso sem garantia.

*Correção de 2026-09-01: esta seção dizia "inviável nativamente" e "battle-tested";
ambas excediam a evidência (uma fonte secundária, outro modelo). Versão anterior íntegra
em `_archive/PESQUISA_UDR7_UPS_TERCEIROS_20260831_pre-correcao.md`.*
