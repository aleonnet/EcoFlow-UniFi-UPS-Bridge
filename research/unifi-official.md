# UniFi UPS Tower — Documentação Pública (Fase 0, Etapa 1)

> **Escopo:** pesquisa APENAS em fontes públicas na web. Nenhuma captura de tráfego,
> firmware ou código próprio da Ubiquiti foi observada nesta etapa.
> **Data de consulta de todas as afirmações:** 2026-08-31.
> **Classificação:** `[CONFIRMADO]` = observado literalmente em doc/página/thread pública;
> `[INFERIDO]` = dedução forte a partir de evidência pública; `[HIPÓTESE]` = plausível, sem confirmação.
>
> **Aviso de qualidade da fonte:** o portal `community.ui.com` (releases e threads) é uma SPA
> que NÃO renderiza via WebFetch ("Loading Ubiquiti Community"). O conteúdo desses links foi
> obtido por meio de snippets de busca e espelhos (releasebot.io, reviews de terceiros), o que
> reduz a confiabilidade de citações literais. Marcado como tal onde aplicável.

---

## 1. Help Center (help.ui.com)

- `[CONFIRMADO]` Existe o artigo oficial **"UniFi - Device Adoption"** que descreve o mecanismo
  geral de adoção de devices UniFi (não específico do UPS).
  URL: https://help.ui.com/hc/en-us/articles/360012622613-UniFi-Device-Adoption — 2026-08-31.
- `[CONFIRMADO]` A adoção padrão exige **TCP 8080** e **UDP 10001** abertos entre o UniFi Host e os
  devices; devices não aparecem como *Pending Adoption* se essas portas estiverem bloqueadas
  (snippet do artigo Device Adoption). Mesma URL — 2026-08-31.
- `[CONFIRMADO]` **UDP 10001** é usado para *Layer 2 broadcast discovery* (não cruza VLAN sem
  multicast relay); o device envia broadcast UDP em 10001 para descobrir o controlador.
  URL: https://help.ui.com/hc/en-us/articles/360012622613-UniFi-Device-Adoption e
  https://community.ui.com/questions/Ports-used-for-Unifi-Adoption/70c35f31-755f-46ae-b495-1de689fdb312 — 2026-08-31.
- `[INFERIDO]` Não foi localizado um artigo dedicado do Help Center especificamente sobre "UniFi UPS"
  / "UPS Tower" com conteúdo acessível (buscas `site:help.ui.com` retornaram apenas artigos
  genéricos: Device Adoption, SNMP Monitoring, Power Redundancy, Getting Started). A documentação
  de setup do UPS parece concentrada em blog/store/community, não em artigo de suporte indexável.
  Buscas em 2026-08-31.
- `[CONFIRMADO]` Existe o artigo **"SNMP Monitoring in UniFi Network"** — SNMP no UniFi é global
  (sem toggle por device) e serve para monitorar devices UniFi por ferramentas externas
  (Zabbix/PRTG/Nagios), NÃO para exibir devices de terceiros dentro da UI do UniFi.
  URL: https://help.ui.com/hc/en-us/articles/33502980942615-SNMP-Monitoring-in-UniFi-Network — 2026-08-31.

**Nota de método:** o artigo Device Adoption retornou HTTP 403 no WebFetch direto; conteúdo obtido
via snippets de busca. Marcar validação L2/inform como pendente de leitura direta (Etapa 2+).

---

## 2. Release Notes (community.ui.com / espelhos)

- `[CONFIRMADO]` Existe uma linha de firmware **"UniFi UPS"** versionada de forma independente
  (produto próprio nos releases): versões públicas identificadas — **1.4.12** (16/out/2025),
  1.4.13, 1.4.18, 1.4.30 e **1.5.0** (data reportada 12/jun/2026; um snippet alternativo citou
  "~18/ago/2026" — divergência não resolvida).
  URLs: https://community.ui.com/releases/UniFi-UPS-1-5-0/891cfaca-1e0e-4d9b-8c05-cc4f56eb368c ;
  https://community.ui.com/releases/UniFi-UPS-1-4-12/6c047e49-2098-49e9-88d6-f257e7493fd8 — 2026-08-31.
  *(Conteúdo detalhado do changelog não acessível — SPA não renderizou.)*
- `[CONFIRMADO]` Release do app **UniFi Android 10.39.6** (24/ago/2026): "Fixed an issue where the
  Replacement Device button was missing for UPS Tower." Indica que o UPS Tower é tratado como device
  gerenciável de primeira classe na UI (tem fluxo de "Replacement Device").
  URL: https://releasebot.io/updates/ubiquiti — 2026-08-31.
- `[CONFIRMADO]` Menção em release notes a "Fixed UPS power protection badges" (UniFi Network
  Application) — existe conceito de *power protection badge* associado a UPS na UI do Network.
  URL: https://releasebot.io/updates/ubiquiti — 2026-08-31.
- `[HIPÓTESE]` A existência de firmware versionado "UniFi UPS" separado do UniFi Network sugere que
  o UPS roda firmware Ubiquiti (linhagem UBNT) e é gerenciado pelo controlador como device adotado,
  e não apenas monitorado por SNMP/NUT externo. Requer confirmação por leitura do changelog e/ou
  captura de tráfego (Etapa 2+).

---

## 3. Produto & Especificações (store.ui.com, techspecs.ui.com, ui.com, blog.ui.com)

### Blog oficial de lançamento
- `[CONFIRMADO]` "Instant adoption in UniFi Network".
- `[CONFIRMADO]` "Built-in NUT server support for third-party systems and clients".
- `[CONFIRMADO]` "Paired shutdown support for UniFi storage appliances, both UNAS and UNVR models".
- `[CONFIRMADO]` "Unified monitoring and control within the UniFi Network interface".
- `[CONFIRMADO]` "Like every UniFi solution, these UPS devices are built to connect smoothly with
  UniFi OS and the UniFi Network application."
  URL: https://blog.ui.com/article/introducing-uninterruptible-power — 2026-08-31.

### Página do produto (store)
- `[CONFIRMADO]` "Supports Graceful Shutdown for UNVR and UNAS, and includes NUT compatibility for
  third-party devices."
- `[CONFIRMADO]` "For Graceful Shutdown functionality, **UniFi OS version 4.4.3 or higher** is required."
  URL: https://store.ui.com/us/en/products/ups-tower-us — 2026-08-31.

### Página de integrações (ui.com)
- `[CONFIRMADO]` UPS 2U (1.440VA/1.000W) e UPS Tower (1.000VA/600W) "integrate seamlessly into the
  UniFi Network application for simple adoption and monitoring".
- `[CONFIRMADO]` "Built-in NUT server capability extending safe shutdown support to third-party
  servers as well."
  URL: https://ui.com/integrations/power-tech/ups-solutions — 2026-08-31.

### Tech Specs (techspecs.ui.com)
- `[CONFIRMADO]` Modelo **UPS-Tower-US**; **(1) porta 100/10 MbE** para conexão de rede;
  (2) portas GbE para surge in/out; botões Power e Factory reset.
- `[CONFIRMADO]` Estados de LED incluem "steady white: waiting for adoption" e
  "steady blue: device adoption and working" — confirma que o UPS Tower passa por **adoção** UniFi.
- `[CONFIRMADO]` 1.000VA/600W, line interactive, bateria chumbo-ácido 12V 9Ah, NDAA compliant.
  URL: https://techspecs.ui.com/unifi/integrations/ups-tower-us — 2026-08-31.

**Síntese das specs:** a única interface de gerência é a **porta Ethernet 10/100** — não há USB de
gerência nem LCD frontal; toda a telemetria vive no controlador UniFi (ver §6, review NAS/StorageReview).

---

## 4. API Oficial (developer.ui.com)

- `[CONFIRMADO]` Existe a **Site Manager API v1.0** oficial, com endpoints como **List Hosts**,
  **List Sites** e **List Devices** (todos aparentemente GET/leitura, orientados a inventário
  multi-site via unifi.ui.com).
  URLs: https://developer.ui.com/site-manager-api/listhosts/ ;
  https://developer.ui.com/site-manager/v1.0.0/listdevices ;
  https://help.ui.com/hc/en-us/articles/30076656117655-Getting-Started-with-the-Official-UniFi-API — 2026-08-31.
- `[INFERIDO]` Nas buscas realizadas, **não** foi encontrado nenhum endpoint público de UPS/power,
  nem endpoint para **criar/registrar** devices de terceiros (a API é de leitura/inventário e
  gestão de devices UniFi já adotados). Conteúdo detalhado dos endpoints não pôde ser lido via
  WebFetch (páginas renderizadas por JS). Buscas em 2026-08-31.
- `[HIPÓTESE]` Não há, pela documentação pública, uma "third-party device integration API" que
  permita a um app externo apresentar um UPS não-Ubiquiti como device gerenciável dentro do UniFi
  Network. Confirmar por leitura direta da referência da API (Etapa 2+).

---

## 5. Comunidade (community.ui.com, fóruns, Home Assistant)

- `[CONFIRMADO]` NUT server embutido escuta na **porta 3493** (padrão NUT); habilitado por checkbox
  "NUT Server" na config do UPS no UniFi Network.
  URLs: https://community.home-assistant.io/t/unifi-ups-tower-nut-server/940749 ;
  https://community.ui.com/questions/Unifi-UPS-Tower-wont-allow-NUT-clients-to-connect/19460ca6-d057-4de0-beb4-c68438b1b281 — 2026-08-31.
- `[CONFIRMADO]` Relatos de que a **implementação do NUT server no UPS é não-conforme**: rejeita
  comandos `LIST` se o cliente não autenticar antes, diferente do NUT padrão; workarounds incluem
  fixar IP estático do UPS e usar o IP como "ID/Hostname", e atualizar firmware.
  URL: https://community.home-assistant.io/t/unifi-ups-tower-nut-server/940749 — 2026-08-31.
- `[CONFIRMADO]` Existe **feature request "UDMP as a NUT client"** — evidência de que o console
  UniFi (UDM Pro) **não** atua nativamente como cliente NUT para se desligar a partir de um UPS de
  terceiros.
  URL: https://community.ui.com/questions/UDMP-as-a-NUT-Network-UPS-Tools-client/15680458-6fe3-4ac8-bf4b-c8e1e7ecd6f6 — 2026-08-31.
  *(Conteúdo da thread não renderizou via WebFetch; classificação baseada no título/URL da feature request.)*
- `[CONFIRMADO]` Existem threads de **falha de adoção do UPS Tower** ("UPS Tower can't be adopted",
  "UPS Tower - Unable to Adopt"), com workaround de factory reset — confirma que o UPS passa pelo
  mesmo fluxo de adoção dos demais devices e pode falhar por rede/DHCP.
  URLs: https://community.ui.com/questions/UPS-Tower-cant-be-adopted/a5ed67a4-f12d-4866-b0bf-04b5ce1d7607 ;
  https://community.ui.com/questions/UPS-Tower-Unable-to-Adopt/bc5e388d-0e12-4bb3-83e7-85973f6489e2 — 2026-08-31.
- `[INFERIDO]` A direção do NUT é **UPS → terceiros** (o UPS é o *servidor* NUT; NAS/Proxmox são
  clientes). Nenhuma fonte pública indica o caminho inverso (UniFi consumindo um NUT server de
  terceiro). Consistente com a ausência da feature "UDMP as NUT client". 2026-08-31.

---

## 6. Reviews técnicos / Teardowns

- `[CONFIRMADO]` "plug the UPS into your UniFi network, and it appears in the UniFi Network
  Controller for 'simple adoption'" — adoção 1-clique como qualquer device UniFi.
  URL: https://networkdevicesinc.com/community/blog/unifi-ups-2u-tower-review — 2026-08-31.
- `[CONFIRMADO]` **Sem LCD frontal**: "all status information is only available inside the UniFi
  controller" — dependência total do console para telemetria (bateria, carga, runtime, voltagem).
  Mesma URL — 2026-08-31.
- `[CONFIRMADO]` Safe Shutdown Pairing permite ao UPS "command it [UNAS/UNVR] to shut down gracefully
  during a power outage" com "near-instant response times"; pareamento é **apenas para devices UniFi**.
  Mesma URL — 2026-08-31.
- `[CONFIRMADO]` Limitação: após shutdown gracioso, devices "do not automatically power back on when
  utility power is restored" — requer power-cycle manual das tomadas via controlador.
  Mesma URL e https://dongknows.com/ubiquiti-unifi-ups-tower-review/ — 2026-08-31.
- `[CONFIRMADO]` Painel/dashboard na UI mostra "power utilization, battery capacity, model name,
  firmware version, IP address, MAC address, and input voltage".
  URL: https://www.storagereview.com/review/ubiquiti-ups-tower-review-compact-unifi-power-protection-for-home-labs-and-network-closets ;
  https://nascompares.com/review/unifi-ups-tower-review/ — 2026-08-31.
- `[INFERIDO]` Nenhum teardown público de firmware/protocolo do UPS Tower foi localizado (mDNS,
  portas internas além de 3493, formato inform). A engenharia reversa pública disponível é do
  **protocolo inform geral** dos APs/gateways UniFi, não do UPS especificamente. 2026-08-31.

### Protocolo inform UniFi (contexto geral, NÃO específico do UPS)
- `[CONFIRMADO]` Devices UniFi enviam **HTTP POST binário para `/inform`** (~a cada 10s), payload
  cifrado (**AES-128-CBC**, ou **AES-GCM** em firmwares novos); header mágico `TNBU`; adoção via
  SSH executando `syswrapper.sh set-adopt http://<controller>:port/inform <chave-hex>`.
  URLs: https://github.com/jk-5/unifi-inform-protocol ;
  https://github.com/jeffreykog/unifi-inform-protocol ;
  https://github.com/fxkr/unifi-protocol-reverse-engineering ;
  https://github.com/JohnKiller/TNBU — 2026-08-31.
- `[CONFIRMADO]` Existem **emuladores de device** que fazem inform requests a um controlador
  (ex.: ZAP-Quebec/unifi-fake-device, qvr/unifi-gateway, trueserve/openUF) — prova de que é
  tecnicamente possível simular um device UniFi perante o controlador (para APs/gateways).
  URLs: https://github.com/ZAP-Quebec/unifi-fake-device ; https://github.com/qvr/unifi-gateway ;
  https://github.com/trueserve/openUF — 2026-08-31.
- `[HIPÓTESE]` **Não está confirmado** que o UPS Tower use o mesmo protocolo inform tradicional;
  pode usar um transporte próprio (WebSocket/MQTT interno do UniFi OS). Toda a base de emuladores
  públicos é de APs/gateways clássicos, anterior ao UPS. Decidir apenas com captura de tráfego real
  do UPS ou análise de firmware (Etapa 2+).

---

## 7. O que a Etapa 1 responde da matriz §30

| Dimensão | Resposta pública | Certeza |
|---|---|---|
| **Discovery** | L2 broadcast UDP **10001** + adoção 8080; UPS aparece como "waiting for adoption" (LED branco). Confirmado que o UPS passa por adoção UniFi. | CONFIRMADO (fluxo geral) / HIPÓTESE (que seja idêntico ao dos APs) |
| **Adoption** | Adoção 1-clique no UniFi Network, como device de 1ª classe (tem "Replacement Device", badges de power protection). Pode falhar por rede (threads de "can't be adopted"). | CONFIRMADO |
| **Auth** | Modelo geral inform usa chave AES trocada na adoção via SSH. Específico do UPS: **desconhecido**. | INFERIDO (geral) / HIPÓTESE (UPS) |
| **Telemetry** | UI mostra bateria, carga, runtime, voltagem, firmware, IP, MAC. Sem LCD — telemetria só existe no controlador. Firmware "UniFi UPS" versionado à parte. | CONFIRMADO |
| **Protocolo** | Não confirmado para o UPS (inform tradicional? WS/MQTT interno?). NUT server na porta 3493 é caminho **de saída** (UPS→terceiros). | HIPÓTESE |
| **Third-party (entrada)** | **Nenhuma evidência pública** de que UniFi apresente UPS não-Ubiquiti como device gerenciável. NUT é unidirecional (UPS é servidor). Feature "UDMP as NUT client" **não** existe nativamente. API oficial é leitura/inventário, sem endpoint de UPS/power nem criação de device. | CONFIRMADO (ausência documental) |

**Requisito duro descoberto:** Graceful Shutdown exige **UniFi OS ≥ 4.4.3**
(https://store.ui.com/us/en/products/ups-tower-us — 2026-08-31).

---

## 8. O que SÓ as Etapas 2–6 podem responder

1. **Protocolo real do UPS Tower** (H01/H02/H03): captura de tráfego device↔controlador para
   distinguir inform tradicional vs. WebSocket/MQTT interno do UniFi OS. Fontes públicas não decidem.
2. **Validação de identidade na adoção** (H04/H05): o Network valida manufacturer/model e/ou
   certificado por device? Exige teste de emulação contra um controlador real ou leitura de firmware.
3. **Emulabilidade do device type "UPS"** (H06/H07): a UI de UPS depende de adoção real com o
   payload/estado esperado? Só um experimento de emulação responde.
4. **Alarm Manager com UPS emulado** (H08): comportamento não documentado publicamente.
5. **Trust exigido para graceful shutdown** (H09): saber se o comando de shutdown pareado exige
   identidade/certificado de device UniFi legítimo. Requer teste.
6. **Existência de qualquer via de "criar UPS via API"** (H10): confirmar por leitura completa da
   referência da Site Manager API e da Network API (páginas JS não lidas nesta etapa).
