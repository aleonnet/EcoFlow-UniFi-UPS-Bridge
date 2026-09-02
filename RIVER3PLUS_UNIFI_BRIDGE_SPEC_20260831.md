# Especificação — EcoFlow RIVER 3 Plus → NUT → UniFi UPS Bridge
**Versão:** 2026-08-31  
**Status:** Especificação de implementação / handoff para LLM  
**Objetivo:** construir uma PoC robusta, local-first e reversível que exponha um EcoFlow RIVER 3 Plus como UPS gerenciável na LAN via NUT e investigue/implemente, se tecnicamente viável, sua apresentação ao UniFi Network/UniFi OS como um UPS equivalente ao UniFi UPS Tower.

---

## 1. Resultado esperado

Implementar esta arquitetura:

```text
              EcoFlow RIVER 3 Plus
                       │
                 USB HID + CDC
                       │
                 Mac mini M4
                       │
            ┌──────────┴──────────┐
            │                     │
         NUT :3493        river-unifi-bridge
            │                     │
       ┌────┴────┐      UniFi adoption/inform*
       │         │                │
       HA       Mac               ▼
                               UDR7
                                │
                         ┌──────┴──────┐
                         │             │
                    Alarm Manager    UPS UI
```

\* **Importante:** “UniFi adoption/inform” é o alvo arquitetural, não uma premissa. O implementador deve descobrir e validar o mecanismo real usado pelo UniFi UPS Tower antes de codificar emulação. Não assumir que o protocolo seja idêntico ao `inform` tradicional de AP/switch/gateway.

A solução deve funcionar em três níveis independentes:

1. **NUT local e funcional** no Mac mini, lendo o RIVER 3 Plus por USB.
2. **Home Assistant + macOS** consumindo o NUT pela LAN.
3. **Bridge UniFi experimental**, tentando fazer o UDR7/UniFi Network reconhecer e exibir o RIVER como UPS compatível, incluindo telemetria e, se o protocolo permitir, Alarm Manager.

O nível 1 deve funcionar mesmo que o nível 3 se prove inviável.

---

# 2. Princípios obrigatórios

## 2.1 Não inventar protocolo

Nenhuma estrutura de pacote, endpoint, campo JSON, device type, header, websocket, porta, token, certificado, caminho de `inform` ou payload UniFi deve ser presumido.

Tudo deve ser classificado como:

- **CONFIRMADO** — observado em documentação, código, tráfego ou hardware real;
- **INFERIDO** — dedução forte, ainda não confirmada;
- **HIPÓTESE** — precisa de experimento.

O código não deve cristalizar hipóteses como se fossem fatos.

## 2.2 Local-first

O caminho crítico de UPS não pode depender de:

- EcoFlow Cloud;
- Internet;
- MQTT da EcoFlow na Internet;
- Home Assistant Cloud;
- serviços externos.

Cloud pode ser usada apenas como fonte auxiliar de pesquisa/comparação, nunca como dependência operacional.

## 2.3 Fail-open para energia

Falha do software, NUT, Home Assistant, bridge ou UniFi **não pode desligar a saída AC do RIVER**.

A função elétrica do UPS deve continuar autônoma.

## 2.4 Reversibilidade

Tudo deve possuir:

- instalador idempotente;
- `--dry-run` quando aplicável;
- backup de arquivos alterados;
- uninstall;
- rollback;
- logs claros;
- nenhuma alteração irreversível no UniFi OS.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* a Fase 3'-EXP cria em runtime, fora do
manifesto do instalador, `udr7_known_hosts`, `udr7_armed.json` e `udr7_runtime.json` no
diretório de estado do daemon, e o runbook cria a chave privada `river-bridge-udr7` e instala
a pública no console. O `uninstall.sh` **avisa** (lista os caminhos e o `.env` armado) e não
remove o que não prova ter criado; a remoção da chave pública no console é passo manual do
runbook. Registrar esses artefatos no manifesto é dívida em `docs/BACKLOG_20260901.md`.

## 2.5 Sem firmware patch inicialmente

Não alterar firmware do RIVER ou UDR7 no MVP.

Qualquer hipótese que exija:

- firmware custom;
- root persistente no UDR7;
- patch binário;
- bypass de assinatura;

deve ser marcada como **fase experimental separada**, e não fazer parte do caminho primário.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* a **Fase 3'-EXP** (desligamento
gracioso do UDR7 via SSH com chave de `root`, `docs/2026-09-01-0817-runbook-protecao-udr7-ssh.md`) **é** essa
fase experimental separada — exige root persistente no UDR7. O caminho primário continua
sendo visibilidade + alerta (app + HA). Nasce em modo ensaio (`PROTECT_DRY_RUN=1`) e só arma
por ato do dono (§7A.5, §22).

---

# 3. Fatos de referência

## 3.1 EcoFlow RIVER 3 Plus

O RIVER 3 Plus possui:

- 286 Wh;
- 600 W AC contínuos;
- LiFePO4;
- UPS <10 ms;
- Wi-Fi;
- Bluetooth;
- porta USB-B de comunicação;
- interface USB HID utilizada pelo NUT;
- interface CDC observável/possivelmente útil para telemetria/protocolo proprietário.

Referências-base a conferir novamente no momento da implementação:

- EcoFlow RIVER 3 Plus:
  - https://www.ecoflow.com/br/river-3-plus-portable-power-station
- Manual:
  - https://manuals.ecoflow.com/us/product/river-3-plus?lang=en_US

## 3.2 Network UPS Tools

O RIVER 3 Plus é suportado pelo NUT através de:

```text
driver = usbhid-ups
```

**Piso de versão (CONFIRMADO 2026-08-31):** o suporte ao RIVER 3 Plus exige **NUT ≥ 2.8.4**
(https://github.com/networkupstools/nut/issues/2735). O Homebrew entrega 2.8.5 em
2026-08-31 (https://formulae.brew.sh/formula/nut). Há issue aberta de não-detecção em
outra plataforma (https://github.com/networkupstools/nut/issues/3306) — a detecção deve
ser verificada no hardware real, nunca presumida.

O objetivo do MVP é usar o NUT como **fonte normalizada e confiável de estado UPS**.

Referências:

- NUT:
  - https://networkupstools.org/
- `usbhid-ups`:
  - https://networkupstools.org/docs/man/usbhid-ups.html
- HCL / source:
  - https://github.com/networkupstools/nut

## 3.3 UniFi UPS Tower

O UniFi UPS Tower:

- é gerenciado pela rede;
- integra-se ao UniFi;
- possui NUT server para terceiros;
- suporta graceful shutdown de equipamentos UniFi compatíveis;
- aparece nativamente na experiência UPS/Power do UniFi.

Referências:

- Produto:
  - https://store.ui.com/us/en/products/ups-tower-us
- Technical Specs:
  - https://techspecs.ui.com/unifi/integrations/ups-tower-us
- Power / UPS:
  - https://ui.com/integrations/power-tech/ups-solutions

**Ponto crítico:** o fato de o UPS Tower expor NUT para terceiros **não implica** que o UniFi aceite UPS de terceiros como NUT client. Essa direção deve ser comprovada separadamente.

---

# 4. Hardware alvo

## 4.1 Escritório — MVP

- EcoFlow RIVER 3 Plus
- Mac mini M4
- UDR7
- Home Assistant na LAN
- conexão USB-B do RIVER ao Mac mini

Não exigir hardware adicional para o MVP.

## 4.2 Expansão futura

A arquitetura deve suportar mais de um UPS:

```text
ups-office
ups-rack
```

Cada instância deve possuir:

- ID lógico;
- serial/USB identity;
- hostname;
- nome amigável;
- zona;
- políticas independentes.

Não assumir que o segundo RIVER estará fisicamente próximo ao Mac mini.

**Fora do MVP:** um segundo RIVER distante do Mac mini implica um segundo host NUT e um
mecanismo de registro/descoberta de instâncias que esta spec **não define**. O MVP cobre
exclusivamente `ups-office` no Mac mini; multi-UPS é fase futura com desenho próprio —
nenhum código do MVP deve antecipá-lo além do ID lógico na configuração.

---

# 5. Componente A — NUT no Mac mini

## 5.1 Objetivo

Transformar o RIVER 3 Plus conectado por USB em um UPS IP padrão disponível na LAN.

```text
RIVER
  │ USB
  ▼
usbhid-ups
  │
  ▼
upsd
  │
  ▼
TCP 3493
```

## 5.2 Instalação

Preferência:

```bash
brew install nut
```

**Exceção consciente à convenção da casa:** o ABHOME-infra evita Homebrew ativamente
(`ABHOME-haos-macmini/haos-install.sh:524`; `ont-stick-setup/README.md:15-16`). O NUT,
porém, não tem canal de distribuição battle-tested no macOS fora do brew — compilar da
fonte contraria "simples, incremental, reversível" (§2.4). Portanto o Homebrew é aceito
**apenas para o NUT**, como dependência **detectada e consentida** pelo instalador:
avisar e pedir confirmação, nunca instalar em silêncio.

O instalador deve **validar `NUT >= 2.8.4`** (piso do suporte EcoFlow, ver §3.2) com o
comando rodado no ato (ex.: `upsd -V`), falhando com exit code de dependência se abaixo.

O instalador deve detectar automaticamente:

- Apple Silicon;
- caminho Homebrew;
- versão do macOS;
- versão do NUT;
- localização real dos arquivos de configuração;
- UID/GID do serviço;
- device USB correspondente ao RIVER.

Não hardcodar caminhos sem validação.

## 5.3 Descoberta USB

Criar script:

```text
bin/river-usb-detect
```

Saída mínima:

```text
manufacturer
product
serial
vendor_id
product_id
HID interfaces
CDC interfaces
IORegistry path
```

Fontes possíveis no macOS:

```bash
system_profiler SPUSBDataType
ioreg
system_profiler
```

e, se disponível:

```bash
nut-scanner
```

## 5.4 Configuração NUT

Arquivo gerado deve usar os IDs realmente detectados.

Modelo conceitual:

```ini
[river-office]
    driver = usbhid-ups
    port = auto
    vendorid = <detectado>
    productid = <detectado>
    desc = "EcoFlow RIVER 3 Plus - Office"
```

Não assumir IDs sem confirmação do hardware.

## 5.5 Estado mínimo requerido

O bridge precisa abstrair, quando o dispositivo fornecer:

```text
ups.status
battery.charge
battery.runtime
battery.voltage
ups.load
input.voltage
output.voltage
ups.realpower
ups.power
ups.temperature
battery.temperature
ups.alarm
device.model
device.serial
driver.version
```

Campos ausentes são permitidos.

Nunca inventar valores.

## 5.6 Normalização de estado

Estados NUT devem ser normalizados:

```text
OL       ONLINE
OB       ON_BATTERY
LB       LOW_BATTERY
CHRG     CHARGING
DISCHRG  DISCHARGING
OVER     OVERLOAD
RB       REPLACE_BATTERY
CAL      CALIBRATING
OFF      OUTPUT_OFF
BYPASS   BYPASS
```

Permitir combinações.

## 5.7 Rede

`upsd`:

- escutar apenas interfaces necessárias;
- preferencialmente LAN/VLAN de management;
- não expor à Internet;
- firewall explícito;
- autenticação separada para HA e clientes NUT;
- usuário read-only para telemetria.

Porta padrão:

```text
TCP 3493
```

## 5.8 macOS como cliente NUT

O próprio Mac mini poderá executar `upsmon`.

Política inicial:

```text
ON_BATTERY → apenas log/notificação
LOW_BATTERY → graceful shutdown
COMM_LOST → alerta
ONLINE_RESTORED → cancelar shutdown pendente
```

Nenhum shutdown automático deve ser habilitado antes de testes controlados.

## 5.9 Consumidor UPS nativo do macOS

**HIPÓTESE a testar na Fase 1:** o macOS possui suporte nativo a UPS USB HID (ícone de
UPS/Energy Saver, política própria de shutdown via `pmset`). Isso cria dois riscos que
esta spec deve tratar antes de habilitar `upsmon`:

1. **Concorrência no device:** kernel/power management e `usbhid-ups` disputando a mesma
   interface HID;
2. **Política dupla de shutdown:** o macOS pode desligar a máquina por conta própria em
   paralelo ao `upsmon` (§5.8).

Passo obrigatório da Fase 1: inventariar quem mais enxerga o UPS no macOS
(`pmset -g batt`, `pmset -g ups`, Energy Saver) com o RIVER conectado, registrar o
observado em `research/findings.md`, e **conciliar as duas políticas** (desativar a nativa
ou o `upsmon`) antes de qualquer shutdown automático. Nada disso foi observado ainda —
não presumir comportamento.

---

# 6. Componente B — Home Assistant

## 6.1 Integração

Usar integração NUT oficial do Home Assistant apontando para:

```text
host: <mac-mini>
port: 3493
ups: river-office
```

## 6.2 Entidades desejadas

Criar entidades normalizadas, independentemente do nome bruto do NUT:

```text
sensor.river_office_battery
sensor.river_office_runtime
sensor.river_office_load
sensor.river_office_input_voltage
sensor.river_office_output_voltage
sensor.river_office_power
binary_sensor.river_office_on_battery
binary_sensor.river_office_low_battery
binary_sensor.river_office_communication
```

## 6.3 Automação inicial

Somente observação:

```text
queda AC
→ registrar timestamp
→ alertar

AC restaurada
→ registrar duração
→ alertar

battery < 25%
→ alerta

battery < 15%
→ alerta crítico
```

Shutdown automático será ativado somente após validação.

---

# 7. Componente C — `river-unifi-bridge`

## 7.1 Objetivo

Criar um daemon local que:

1. consuma NUT;
2. opcionalmente leia USB CDC/HID diretamente para dados que o NUT não expõe;
3. normalize telemetria;
4. descubra como o UniFi UPS Tower apresenta essa telemetria ao UniFi;
5. emule apenas o mínimo necessário para o UDR7/UniFi Network tratar o River como UPS;
6. nunca interfira na alimentação AC por padrão.

Nome:

```text
river-unifi-bridge
```

Linguagem recomendada:

```text
Python 3.13+
```

Alternativa aceitável:

```text
Go
```

Escolher Go se o protocolo exigir daemon binário mais simples, concorrência e distribuição single-file.

## 7.2 Arquitetura interna

```text
                       river-unifi-bridge
                               │
                ┌──────────────┼──────────────┐
                │              │              │
             nut.py          usb.py        unifi/
                │              │              │
             NUT 3493       HID/CDC       protocol
                │              │              │
                └──────┬───────┘              │
                       ▼                      │
                  Normalized UPS             │
                       │                      │
                       └──────────────┬───────┘
                                      ▼
                              UniFi adapter
```

## 7.3 Modelo interno

Criar objeto normalizado:

```json
{
  "identity": {
    "name": "river-office",
    "manufacturer": "EcoFlow",
    "model": "RIVER 3 Plus",
    "serial": null
  },
  "power": {
    "state": "ONLINE",
    "input_present": true,
    "input_voltage_v": null,
    "output_voltage_v": null,
    "output_power_w": null,
    "load_percent": null
  },
  "battery": {
    "charge_percent": null,
    "runtime_seconds": null,
    "voltage_v": null,
    "temperature_c": null
  },
  "health": {
    "communication_ok": true,
    "low_battery": false,
    "overload": false,
    "alarm": []
  },
  "source": {
    "nut": true,
    "usb_hid": true,
    "usb_cdc": false
  },
  "timestamp": "RFC3339"
}
```

`null` é obrigatório para dados desconhecidos.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* `source` ganha `driver_name` e
`driver_version` (de `driver.name`/`driver.version` do NUT; `null` quando ausentes) e
`battery` ganha `charge_low_percent` (de `battery.charge.low`). `battery.charge_percent`
fora de [0, 100] é publicado como `null` (token em `unknown_status_tokens`).

---

# 7A. Componente D — "River Bridge.app" (UI nativa macOS)

*Adicionado em 2026-08-31 por decisão do dono; arquitetura aprovada por banca
adversarial de 3 rodadas (veredito em `docs/BANCA_PLANO_20260831.md`).*

## 7A.1 Requisito do dono (NÃO rebaixar)

UI **nativa** macOS no Mac mini, "mind-blowing, animações, gauges, gráficos, à la
Apple", formato **menu bar + janela**, cobrindo 4 frentes: dashboard ao vivo, saúde da
integração (cadeia USB → NUT → bridge → UniFi/HA), configuração e instalação guiada.
Critério de aceite subjetivo: o dono olha e diz "parece um app da Apple". Objetivos de
apoio: 60fps medidos com Instruments, dark/light sem regressão, VoiceOver nos valores
principais, Reduce Motion respeitado.

## 7A.2 Linguagem e posição arquitetural

**Swift + SwiftUI** (toolchain medido na máquina de dev em 2026-08-31: Xcode 26.6,
Swift 6.3.3). Diretório `macos/RiverBridge/`.

**Regra dura:** a UI é CLIENTE do daemon, nunca segundo cérebro. Não fala com
NUT/USB/UniFi diretamente — só com a API local do daemon. Matar a UI não afeta nada;
matar o daemon degrada a UI para "serviço parado" (fail-open §2.3 preservado).

## 7A.3 Transporte daemon ↔ UI

HTTP/1.1 em **127.0.0.1** + SSE (`aiohttp` no daemon — dependência declarada no
pyproject; `URLSession.bytes` no app). Novo `src/river_unifi_bridge/api.py`:

```text
GET  /v1/state      snapshot do modelo §7.3 (null obrigatório)
GET  /v1/events     SSE: state | health | event
GET  /v1/history    ?metric&from&to&bucket
GET  /v1/health     cadeia USB→NUT→bridge→UniFi (+ HA se observável)
GET  /v1/config     config efetiva, secrets redigidos
PUT  /v1/config     só chaves da allowlist; resposta declara hot-reload vs restart
POST /v1/service/restart
GET  /v1/version
```

- Bind fixo em loopback (cerca no código); token bearer gerado no 1º boot em
  `~/Library/Application Support/river-unifi-bridge/ui-api.token`, chmod 600, nunca em
  argv/log.
- **Contrato de relançamento** (launchd `KeepAlive={SuccessfulExit: false}`): restart
  pedido → 202 drenado + `exit(75)` agendado fora do handler → relança; erro transiente
  → exit ≠ 0 → relança; erro de configuração repetível → grava causa em arquivo de
  estado + `exit(0)` = parada deliberada, não relança; modo CLI usa os exit codes da
  casa. Os três comportamentos são cerca de gate (`launchctl print`).

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* o SSE implementado emite `event: state`
e `event: event`; **não há frame `health`** — o app consulta `/v1/health` por polling
(5 s). O elo `unifi` do health responde `sem_caminho_nativo_documentado`; o elo novo `udr7`
(enum fechado) e `udr7_detail` estão em `docs/API_LOCAL_20260831.md`.

## 7A.4 Histórico para gráficos

O **daemon** guarda (roda 24/7; a UI é intermitente): `src/river_unifi_bridge/history.py`,
SQLite da stdlib (WAL) em Application Support, tabelas `samples`/`events`, retenção
`HISTORY_RETENTION_DAYS` (default 7). A API agrega em buckets; a UI nunca lê o SQLite.

## 7A.5 Configuração pela UI

Sempre via API, nunca no arquivo: PUT validado contra a MESMA allowlist do parser;
edição do `.env` linha-a-linha preservando comentários e blocos (aborta em formato
inesperado); escrita atômica `mkstemp(dir=<diretório do alvo>)` + fsync + `os.replace`
+ backup `.bak`. Configs do NUT ficam FORA da UI (exibidas read-only na tela de saúde).

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* exceções e regras novas do `PUT /v1/config`:
- `UDR7_ARM_ALLOWED` é **somente arquivo** (`FILE_ONLY_KEYS`): PUT → `400
  chave_somente_arquivo`. É a trava de armamento — abrir/fechar exige editar o `.env` e
  reiniciar o serviço (2º e 3º passos do runbook).
- Predicado `armado = PROTECT_UDR7 ∧ ¬PROTECT_DRY_RUN`. Transição para armado exige
  `UDR7_ARM_ALLOWED=1` (senão `409 armamento_bloqueado`) e snapshot corrente com
  `comm_ok`, driver fora da denylist e `identity.serial == UDR7_EXPECTED_SERIAL`
  (senão `409 sem_snapshot` / `409 fonte_nao_real`).
- Enquanto armado, qualquer chave de `PROTECTION_KEYS` (`PROTECT_*`, `UDR7_*`, `NUT_*`)
  → `409 armado`, **exceto o desarme**: PUT contendo somente `PROTECT_UDR7`/
  `PROTECT_DRY_RUN` com predicado resultante falso é sempre aceito. `POST
  /v1/service/restart` armado → `409 armado`.
- A autorização roda **antes** da escrita do `.env`; um 4xx nunca deixa rastro no arquivo.
- `UDR7_SSH_HOST` e as demais chaves `UDR7_*`/`PROTECT_*` são hot-reload (`UNIFI_HOST`
  segue restart-required e não é usada pela proteção).

## 7A.6 Instalação guiada

O app roda `scripts/install.sh` como usuário (sem escalação; LaunchAgents `gui/$uid` +
brew do usuário). Instalador ganha `--json-progress` e `--consent-homebrew` (sem a
flag, passo brew falha com exit 4; a flag só é passada após tela de consentimento com o
comando exato). Botão permanente "Abrir no Terminal". Uninstall guiado decide pelo
manifesto, nunca pela UI.

**Decisão do dono (2026-08-31, após sondagem):** o mini está com auto-login OFF
([FATO] `sysadminctl -autologin status`), e um monitor de UPS precisa voltar sozinho
após queda de energia. Portanto **NUT + bridge rodam como LaunchDaemon** (domínio
system, sobem no boot sem login; plists com `UserName` para não rodar como root
desnecessariamente — validar semântica no build). O instalador pede senha de admin
uma vez para gravar em `/Library/LaunchDaemons`. O app da UI continua por sessão de
login (comportamento normal de app). Gates de serviço usam `launchctl print system/...`.

## 7A.6b Versão iPhone e acesso remoto (decisão do dono, 2026-08-31)

A UI ganhará versão iPhone. Fundações já entregues: Core 100% portável (Foundation +
CoreGraphics, zero AppKit) e layout adaptativo (largura compacta → fluxo vertical com
a MESMA geometria provada por teste). O app iOS nasce junto com o projeto Xcode da
Fase 6a/UI-4 (necessário de todo modo para assinatura e instalação no aparelho).

**Conectividade (não altera a cerca §7A.3):** o daemon permanece loopback-only; o
Mac mini publica a API via **`tailscale serve`** apenas na tailnet da casa (Tailscale
já é infraestrutura da casa — ABHOME-rede). O iPhone acessa de qualquer lugar,
criptografado, com o mesmo token bearer; nada é exposto na LAN nem na Internet.
Rejeitado: bind na LAN + TLS (mexeria na cerca aprovada e só funcionaria em casa).

## 7A.7 YAGNI v1 (cortes)

Edição de configs NUT pela UI; multi-UPS; notificações macOS (HA já alerta — evitar
política dupla, mesmo racional do §5.9); widgets; auto-update; localização além de
pt-BR; mais de 2 gráficos de série temporal (bateria %, potência W) + 1 timeline de
eventos; WebSocket; TLS em loopback; qualquer ação da UI que toque a saída AC.

---

# 8. Pesquisa obrigatória — protocolo UniFi UPS

Esta é a parte mais importante da PoC.

## 8.1 Pergunta

Descobrir exatamente:

> Como o UniFi UPS Tower é descoberto, adotado, autenticado e monitorado pelo UniFi Network/UniFi OS?

Não assumir resposta.

## 8.2 Ordem de investigação

### Etapa 1 — documentação pública

Pesquisar:

- Ubiquiti Help Center;
- release notes UniFi OS;
- release notes UniFi Network;
- docs do UPS Tower;
- docs de Alarm Manager;
- graceful shutdown;
- NUT server;
- API local;
- API Site Manager;
- API Network;
- referências a UPS em changelogs.

Salvar tudo em:

```text
research/unifi-official.md
```

Cada afirmação deve conter URL e data.

### Etapa 2 — UI do UDR7

Usar browser devtools com:

```text
Network
Fetch/XHR
WebSocket
EventStream
```

Abrir:

```text
UniFi OS
Network
UPS/Power UI
Alarm Manager
Devices
```

Registrar:

```text
endpoint
method
headers relevantes
payload
response
websocket messages
event names
schema
```

Não salvar senha/token no repositório.

**Limitação conhecida desta etapa:** sem um UPS Tower fisicamente presente, a UI de
UPS/Power pode nem renderizar (telas condicionadas à existência do device). Se for o
caso, registrar isso como fato em `research/findings.md` e tratar a **Etapa 3 (bundle
JS) como fonte primária** — o código da UI existe no bundle mesmo sem hardware.

### Etapa 3 — bundle JavaScript

Inspecionar os bundles da UI do UniFi para strings:

```text
ups
battery
runtime
graceful
shutdown
power
inform
adopt
alarm
nut
ups_tower
```

Objetivo:

- descobrir endpoint;
- nomes de objetos;
- device type;
- schemas;
- estados;
- event topics;
- feature flags.

### Etapa 4 — UniFi OS local

Somente leitura inicialmente.

Inventariar:

```text
processes
containers
packages
ports
sockets
services
logs
databases
```

Buscar referências a UPS.

Nenhum arquivo deve ser alterado nesta etapa.

### Etapa 5 — firmware/software público

Se legalmente/publicamente disponível, inspecionar:

- firmware do UPS Tower;
- pacotes UniFi relacionados;
- JS da Network Application;
- strings;
- schemas;
- protobufs;
- OpenAPI;
- binaries usando `strings`.

Não contornar criptografia ou proteção de acesso.

### Etapa 6 — captura com UPS Tower real

Se houver acesso futuro a um UPS Tower:

```text
UPS Tower
    │
 managed switch mirror/SPAN
    │
 capture
    ▼
 Wireshark/tcpdump
```

Capturar:

```text
boot
discovery
adoption
steady state
power loss
power restore
low battery
alarm
shutdown pairing
reboot
```

Essa é a fonte definitiva.

---

# 9. Hipóteses a provar/refutar

Criar:

```text
research/hypotheses.md
```

Com tabela:

| ID | Hipótese | Estado | Evidência |
|---|---|---|---|
| H01 | UPS usa UniFi Inform tradicional | UNKNOWN | |
| H02 | UPS usa WebSocket próprio | UNKNOWN | |
| H03 | UPS usa MQTT interno | UNKNOWN | |
| H04 | Network valida manufacturer/model | UNKNOWN | |
| H05 | Network valida certificado por device | UNKNOWN | |
| H06 | device type UPS pode ser emulado | UNKNOWN | |
| H07 | UPS UI depende de adoção real | UNKNOWN | |
| H08 | Alarm Manager aceita eventos de UPS emulado | UNKNOWN | |
| H09 | graceful shutdown exige trust/device identity | UNKNOWN | |
| H10 | third-party device API permite criar UPS | UNKNOWN | |

Nunca mudar `UNKNOWN` para `TRUE/FALSE` sem evidência reproduzível.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* hipóteses da proteção do UDR7 (detalhe e
fontes em `research/hypotheses.md`):

| ID | Hipótese | Estado |
|---|---|---|
| H11a | `ubnt-systool poweroff` existe e é gracioso no **UDR7** (fonte: gist para UDM Pro) | UNKNOWN |
| H11b | login SSH por **chave** para `root` funciona e persiste no UDR7 (o gist usa senha) | UNKNOWN |
| H12a | firmware update apaga `authorized_keys` | UNKNOWN |
| H12b | firmware update troca a host key | UNKNOWN (INFERIDO) |
| H13 | o UDR7 boota sozinho ao receber energia após `poweroff` | UNKNOWN |
| H14 | o UDR7 acorda por Wake-on-LAN após `poweroff` | UNKNOWN (sem fonte) |
| H15 | o River expõe `device.serial` estável via NUT ≥ 2.8.4 (dump conhecido é 2.7.4) | UNKNOWN (INFERIDO) |
| H16 | o River reenergiza a saída AC sozinho quando a rede volta após corte por Discharge Limit | UNKNOWN |
| H17 | o ponto real de corte da saída AC (a pesquisa tem dois [P] contraditórios) | UNKNOWN |

**Evidência inicial já coletada (2026-08-31, não fecha nenhuma hipótese):**

- Blog oficial Ubiquiti (https://blog.ui.com/article/introducing-uninterruptible-power):
  UPS Tower tem "Instant adoption in UniFi Network" (protocolo de device UniFi) e
  "Built-in NUT server support for third-party systems and clients" — NUT descrito
  **apenas na direção UPS→terceiros**. Nenhuma menção a UPS third-party na UI.
  Relevante para H01, H06, H10.
- "UDM como NUT client" existe como feature request não atendida na comunidade
  (https://community.ui.com/questions/UDMP-as-a-NUT-Network-UPS-Tools-client/15680458-6fe3-4ac8-bf4b-c8e1e7ecd6f6)
  — indício de que o console **não** atua como NUT client nativamente. Relevante para H10.

Copiar estes registros para `research/hypotheses.md` na Fase 0 como ponto de partida.

---

# 10. Estratégias de integração UniFi

O implementador deve testar nesta ordem.

## Estratégia A — API/extensibility oficial

Procurar primeiro uma maneira oficialmente suportada de registrar:

```text
third-party UPS
power device
external device
integration device
```

Se existir, usar esta opção.

**Prioridade máxima.**

## Estratégia B — emulação de device protocol

Se não houver API oficial:

```text
river-unifi-bridge
        │
        ▼
emula device-side protocol
        │
        ▼
UniFi accepts/adopts
```

Critério:

- zero patch no UDR7;
- bridge descartável;
- reinicialização do bridge não quebra Network;
- identidade separada;
- nenhuma colisão com devices reais.

## Estratégia C — plugin/app local UniFi

Se emulação não for possível, investigar se UniFi OS suporta componente local/extensão que:

```text
lê NUT
→ injeta dashboard/alarmes
```

Sem substituir serviços nativos.

## Estratégia D — integração externa sem UPS UI

Fallback somente se A/B/C forem tecnicamente impossíveis.

**Correção de direção (2026-08-31, INFERIDO — confirmar na Fase 0):** a documentação
pública do Alarm Manager
(https://help.ui.com/hc/en-us/articles/27721287753239-UniFi-Alarm-Manager-Customize-Alerts-Integrations-and-Automations-Across-UniFi)
descreve webhooks como **saída** (ação disparada por eventos internos UniFi), não como
entrada de eventos externos. Não foi encontrada API pública de ingestão de eventos no
Alarm Manager. Portanto o fallback realista é:

```text
NUT
→ HA
→ alertas/automções no próprio HA
```

com o UniFi, no máximo, como origem de webhooks para o HA (direção UniFi → fora), nunca
como destino de eventos do RIVER.

Esse fallback **não coloca o RIVER no UniFi** e **não atende integralmente ao objetivo**;
deve ser explicitamente rotulado como tal. Se a Fase 0 encontrar mecanismo real de
ingestão no Alarm Manager, esta seção volta ao desenho original com a evidência anexada.

---

# 11. Alarm Manager

Objetivo:

```text
RIVER ONLINE
RIVER ON BATTERY
RIVER LOW BATTERY
RIVER COMMUNICATION LOST
RIVER COMMUNICATION RESTORED
RIVER OVERLOAD
RIVER AC RESTORED
```

Mapear cada estado para o mecanismo real do UniFi.

Não criar eventos falsos.

Debounce sugerido:

```text
power loss      2–5 s
power restored  5 s
comm lost       15–30 s
low battery     imediato após estado confirmado
```

Todos os limites devem ser configuráveis.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* defeito conhecido D-A — o tracker emite
`LOW_BATTERY` por percentual **sem exigir ON_BATTERY** (dispara também na tomada, durante a
recarga); a proteção do UDR7 **não** consome esse evento (tem condição própria com queda
confirmada). Correção do evento: `docs/BACKLOG_20260901.md`.

---

# 12. UPS UI

Se tecnicamente viável, o River deverá aparecer no UniFi com:

```text
Name
Model
Status
Battery %
Runtime
Load
Input status
Output status
Alarms
Last seen
```

Qualquer campo não disponível deve ficar ausente, nunca fabricado.

O bridge poderá reportar:

```text
manufacturer = EcoFlow
model        = RIVER 3 Plus
```

**Não fingir ser produto Ubiquiti se o protocolo permitir third-party identity.**

Somente em uma PoC isolada, caso absolutamente necessário para testar o protocolo, poderá existir um modo explícito:

```text
--emulate-model
```

Desabilitado por padrão.

---

# 13. USB CDC

O bridge deve investigar a interface CDC separadamente do NUT.

Objetivos:

- identificar framing;
- baud rate, se aplicável;
- mensagens espontâneas;
- comandos;
- protobuf/JSON/binário;
- checksums;
- telemetria adicional;
- controles;
- correlação com EcoFlow App/Power Manager.

Criar ferramenta:

```text
tools/river-cdc-sniffer
```

Modo padrão:

```text
READ ONLY
```

Nenhum comando destrutivo.

Registrar captures binários em:

```text
captures/ecoflow/
```

com timestamp e descrição.

---

# 14. Wi-Fi EcoFlow — linha de pesquisa paralela

Não depender dela para o MVP.

Investigar se o RIVER possui:

```text
local TCP services
mDNS
SSDP
BLE-to-WiFi control plane
local MQTT
local HTTP
local protobuf
UDP discovery
```

Fazer:

```bash
arp
dns-sd
nmap -sT
nmap -sU limitado
mdns browse
packet capture
```

Não realizar scanning agressivo.

Objetivo de longo prazo:

```text
RIVER
  │ Wi-Fi
  ▼
river-unifi-bridge
```

sem USB.

Somente promover essa arquitetura se for comprovadamente:

- local;
- estável;
- autenticável;
- sem cloud;
- reproduzível.

---

# 15. Segurança

Obrigatório:

- NUT não exposto à WAN;
- secrets fora do Git;
- `.env` somente local;
- suporte a Keychain no macOS se houver credenciais;
- logs sem tokens;
- bridge não deve possuir credenciais UniFi de admin completo se scope menor existir;
- TLS quando suportado;
- permitir bind por IP/interface;
- rate limiting;
- structured logging;
- audit log.

**Exceções registradas para a API local da UI (§7A.3), cada uma com racional
(2026-08-31, aprovadas em banca):**

1. **Token em arquivo 0600 em vez de Keychain:** o daemon roda headless sob launchd,
   onde o Keychain pode estar indisponível sem sessão desbloqueada; o token é local,
   loopback-only e regenerável a cada boot.
2. **Rate limiting dispensado nessa API:** loopback autenticado, cliente único.
3. **TLS dispensado nessa API:** tráfego jamais sai de 127.0.0.1; TLS em loopback
   adicionaria gestão de certificado sem reduzir superfície de ataque.

O audit log da §15 cobre a superfície nova: todo `PUT /v1/config` (chaves alteradas,
secrets redigidos) e `POST /v1/service/restart` são registrados.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* exceções da proteção do UDR7:

4. **Chave SSH privada em arquivo (0600) em vez de Keychain:** é o único formato que o
   `ssh` do sistema consome em `BatchMode` sob launchd; dedicada (`river-bridge-udr7`),
   nunca a chave pessoal.
5. **Usuário `root` no console:** único usuário documentado para o comando (fonte [S],
   H11a); não há escopo menor conhecido.
6. **`RUB_SSH_BINARY`** (variável de ambiente lida no import) é o seam de teste que aponta o
   binário `ssh`; o plist do LaunchDaemon (root:wheel, `EnvironmentVariables` explícitas)
   não o define, o valor efetivo aparece em `udr7_detail.ssh_binary` e é pinado no
   armamento.
7. **Fronteira declarada:** quem tem o uid do serviço (token, `.env`, chave, estado) pode
   tudo; o `409` do restart armado é anti-acidente, não fronteira. O ato de armar e cada
   transição do elo `udr7` entram no audit log (`udr7_protection_state`). A linha leva o campo
`plugin` com o id do dispositivo; o nome do evento é `<id>_protection_state`, de modo que o
UDR7 continua gravando exatamente o que o operador já conhece.

---

# 16. Serviço macOS

O bridge e NUT devem sobreviver a reboot.

Preferência:

```text
launchd
```

Entregáveis:

```text
launchd/com.river.nut.plist
launchd/com.river.unifi-bridge.plist
```

**Gerente de serviço único:** launchd com plists próprios. `brew services` **não** deve
ser usado — dois gerentes concorrentes para o mesmo processo é defeito de desenho, e o
padrão da casa é launchd puro.

**Domínio (decisão do dono, 2026-08-31):** **LaunchDaemon** (system) para NUT e bridge
— o mini opera com auto-login OFF e o serviço deve subir no boot sem login (ver §7A.6).
Plists em `/Library/LaunchDaemons`, com `UserName` definido; instalador solicita admin
uma única vez, com registro no manifesto.

**Foreground obrigatório:** há bug confirmado de daemonização do driver NUT em macOS
Apple Silicon (Sonoma/Sequoia + M2, NUT 2.8.2: `upsdrvctl`/`usbhid-ups` falham ao forkar;
funcionam com `-F` — https://github.com/networkupstools/nut/issues/2642; estado em
2.8.5/M4 a confirmar no hardware). Os plists devem rodar driver, `upsd` e bridge em
**foreground**, que é também o modo recomendado pelo launchd.

**Padrão de implementação:** seguir o launchd idempotente de
`ABHOME-haos-macmini/haos-install.sh:1253-1345` — plist escrito em tmp e comparado com
`cmp -s` antes de tocar o arquivo; `launchctl print gui/$uid/<label>` para provar job
carregado (arquivo igual não prova job carregado); `bootstrap`/`bootout` com fallback
para `load -w`; argv direto no plist, sem `sh -c`; trap TERM/INT/HUP para desligamento
limpo com `ExitTimeOut` compatível.

Scripts:

```text
scripts/install.sh
scripts/uninstall.sh
scripts/status.sh
scripts/diagnose.sh
scripts/collect-support.sh
```

Todos idempotentes.

---

# 17. Observabilidade

**Duas camadas, dois padrões (convenção da casa + requisito do daemon):**

1. **Instalador e scripts** seguem o padrão da casa: `last-run.log` (narrativa da
   execução — versão, timestamp, `rc=`, fase, uma linha por passo com duração), escrito
   no trap EXIT ("a execução que morre no meio é a que mais precisa de registro"),
   separado do log bruto das ferramentas. Referência:
   `ABHOME-haos-macmini/haos-install.sh:815-835`.
2. **O daemon** (processo longo, sem precedente na casa) mantém o log estruturado com
   `--log-level` desta seção — requisito original da spec, registrado como novidade
   consciente.

Logs separados:

```text
logs/nut.log
logs/bridge.log
logs/unifi-protocol.log
```

Suportar:

```text
--log-level ERROR|WARN|INFO|DEBUG|TRACE
```

`TRACE` deve mascarar secrets.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* linha de audit `udr7_protection_state`
(`de`/`para`) a cada transição do elo `udr7`, e 10 eventos persistidos:
`UDR7_SHUTDOWN_DRYRUN|_SENT|_FAILED|_BLOCKED`, `UDR7_PROTECTION_REARMED`,
`UDR7_PROTECTION_BLIND`, `UDR7_ARMED`, `UDR7_DISARMED`, `UDR7_WOL_SENT`, `UDR7_WOL_DRYRUN`.

Métricas desejadas:

```text
bridge_up
river_connected
river_on_battery
river_battery_percent
river_runtime_seconds
river_output_power_w
unifi_connected
unifi_adopted
unifi_last_publish_timestamp
```

Opcional:

```text
/prometheus
```

local.

---

# 18. Testes

## 18.1 Testes unitários

Cobrir:

- parser NUT;
- normalização;
- transitions;
- alarm debounce;
- serialização UniFi;
- reconnection;
- missing values;
- invalid payloads.

**Componente D (§7A):**

- unit de `api.py`/`history.py`/`config.py` com **teste de mutação de cada cerca**
  (remover allowlist do PUT → o teste TEM de reprovar; bind 0.0.0.0 → reprovar;
  remover chmod 600 → reprovar);
- contrato: fixtures JSON dourados (incluindo `null`) em `tests/fixtures/`,
  decodificados pelos DOIS lados — pytest e Swift;
- Swift em duas camadas: `Core/` como package SPM (`swift test`) e 2 XCUITests via
  `xcodebuild test` (dashboard com stub; consentimento Homebrew antes da flag) —
  `swift test` não executa XCUITest;
- os três comportamentos do contrato de relançamento (§7A.3) provados com
  `launchctl print`.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* proteção do UDR7 — **mutação parcial**: 8
cenas de gate (denylist, dry-run, serial, autorização do PUT, loopback, pinos, `--` do argv,
desarme) para as 10 condições da propriedade M1 + 3 regras de API; as demais condições têm
teste unitário sem cena. XCUITests continuam fora de escopo (declarado). Nenhum teste
spawna `ssh`: `tests/unit/conftest.py` troca os seams por funções que falham.

## 18.2 Testes de integração

Cenários:

```text
T01 boot com River conectado
T02 boot sem River
T03 conectar USB após boot
T04 remover USB
T05 queda AC
T06 retorno AC
T07 bateria baixa simulada
T08 perda de upsd
T09 restart bridge
T10 restart UDR7
T11 restart UniFi Network
T12 perda LAN
T13 perda Internet
T14 HA offline
T15 EcoFlow Cloud offline
```

## 18.3 Critério fundamental

`T13` e `T15` não podem impedir:

```text
RIVER → NUT → bridge → UniFi local
```

se a integração UniFi for realmente local.

---

# 19. Simulador

Criar:

```text
tools/fake-nut-ups
```

para desenvolver sem derrubar energia.

Estados:

```text
ONLINE
ON_BATTERY
LOW_BATTERY
OVERLOAD
COMM_LOST
```

Permitir:

```bash
./fake-nut-ups --scenario power-loss
```

e payloads reproduzíveis.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* `BASE_VARS` publica `driver.name`
(`fake-nut-ups`), `driver.version` (`fake-nut-ups`) e `battery.charge.low` (`10`, valor
simulado); cenário `apagao` (20 s rede / 100 s bateria 40→3 % sem LB / 20 s rede) para
ensaiar a proteção. O simulador é, por desenho, sempre barrado pela cerca de fonte.

---

# 20. Captura UniFi reproduzível

Criar template:

```text
captures/unifi/
  README.md
  boot/
  adopt/
  online/
  on-battery/
  low-battery/
  restored/
```

Cada capture deve ter:

```text
timestamp
UniFi OS version
Network version
UPS firmware
topology
event
pcap
decoded notes
```

---

# 21. Estrutura do repositório

```text
river-unifi-bridge/
├── README.md
├── SPEC.md
├── LICENSE
├── pyproject.toml
├── src/
│   └── river_unifi_bridge/
│       ├── __init__.py
│       ├── config.py
│       ├── model.py
│       ├── nut.py
│       ├── usb_hid.py
│       ├── usb_cdc.py
│       ├── api.py          # §7A.3 — HTTP 127.0.0.1 + SSE para a UI
│       ├── history.py      # §7A.4 — SQLite de histórico
│       ├── service.py
│       ├── protect.py      # Fase 3'-EXP — política de proteção do UDR7 (raiz do
│       │                   # pacote, não em unifi/: era erro da spec até 2026-09-01)
│       ├── plugins/        # contrato de dispositivo protegido, registro estático
│       │   ├── __init__.py #   PLUGINS, build_plugins, plugin_statuses
│       │   ├── base.py     #   DevicePlugin (ABC)
│       │   └── udr7_ssh.py #   1º plugin: adaptador fino sobre protect.py
│       └── unifi/
│           ├── __init__.py
│           ├── discovery.py
│           ├── protocol.py
│           ├── telemetry.py
│           ├── alarms.py
│           └── adoption.py
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   ├── status.sh
│   ├── diagnose.sh
│   └── collect-support.sh
├── config/
│   ├── ups.conf.example
│   ├── upsd.conf.example
│   ├── upsd.users.example
│   └── river-unifi-bridge.env.example
├── macos/
│   └── RiverBridge/        # §7A — app SwiftUI (Core/ SPM, Features/, testes)
├── launchd/
│   ├── com.river.nut.plist
│   └── com.river.unifi-bridge.plist
├── tools/
│   ├── river-usb-detect
│   ├── river-cdc-sniffer
│   ├── fake-nut-ups
│   └── unifi-inspect
├── research/
│   ├── unifi-official.md
│   ├── hypotheses.md
│   ├── protocol.md
│   └── findings.md
├── captures/
│   ├── ecoflow/
│   └── unifi/
└── tests/
    ├── unit/
    └── integration/
```

---

# 22. Configuração

**Padrão da casa (ABHOME-infra):** configuração em `.env` `CHAVE=valor` com
`.env.example` versionado, arquivo real em modo 600 e fora do git. Parser escrito à mão
com **allowlist de chaves** (aviso com número de linha para chave desconhecida, falha em
obrigatória vazia), como em `ABHOME-macmini/macmini-backup.sh:452-464`. Blocos numerados
e comentário só em linha própria, como em `ont-stick-setup/ont-setup.env.example`.
YAML de runtime não tem precedente na casa e não deve ser introduzido aqui.
O modelo interno JSON (§7.3) não muda.

Exemplo (`river-unifi-bridge.env.example`):

```bash
# ── 1. river ──────────────────────────────
RIVER_NAME=river-office
NUT_HOST=127.0.0.1
NUT_PORT=3493
NUT_UPS=river-office

# ── 2. unifi ──────────────────────────────
UNIFI_HOST=192.168.1.1
UNIFI_VERIFY_TLS=1

# ── 3. bridge ─────────────────────────────
POLL_INTERVAL_SECONDS=2
READ_ONLY=1
EMULATE_MODEL=0

# ── 4. alarms ─────────────────────────────
# Defaults ancorados (docs/PESQUISA_PARAMETROS_UPS_20260831.md, 2026-08-31):
# 6=apcupsd ONBATTERYDELAY · 0=restauração imediata (NUT/apcupsd)
# 15=NUT upsmon DEADTIME · 30=fallback lowbatt do usbhid-ups
POWER_LOSS_DELAY_SECONDS=6
RESTORE_DELAY_SECONDS=0
COMM_LOSS_DELAY_SECONDS=15
LOW_BATTERY_PERCENT=30

# ── 5. ui api (§7A) ───────────────────────
UI_API_ENABLED=1
UI_API_PORT=35493
HISTORY_RETENTION_DAYS=7

# ── 6. proteção udr7 (Fase 3'-EXP) ────────
# Nasce em ensaio. Armar = trava aberta no arquivo + reinício + ato no app.
PROTECT_UDR7=0
PROTECT_DRY_RUN=1
UDR7_ARM_ALLOWED=0
UDR7_SSH_HOST=
UDR7_SSH_PORT=22
UDR7_SSH_USER=root
UDR7_SSH_KEY=
UDR7_EXPECTED_SERIAL=
UDR7_CUTOFF_PERCENT=0
UDR7_SHUTDOWN_PERCENT=0
UDR7_DISCHARGE_SECONDS_PER_PCT=0
UDR7_RUNTIME_MINUTES=0
UDR7_MIN_OUTAGE_SECONDS=0
UDR7_CONFIRM_SECONDS=6
UDR7_RETRY_MAX=3
UDR7_WOL_MAC=
UDR7_NAME=UDR7
```

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v8):* `UDR7_NAME` é o nome que o usuário dá ao dispositivo (1–32 caracteres); aplica a quente e, apesar do prefixo `UDR7_`, **não** entra em `PROTECTION_KEYS` nem nos pinos de armamento — renomear com a proteção armada é permitido. Semântica das chaves do bloco 6 e fontes dos
defaults estão em `docs/2026-09-01-0817-runbook-protecao-udr7-ssh.md` e no `.env.example`. `READ_ONLY`
é chave **sem efeito** no código (nenhuma leitura em `src/`); não foi reaproveitada como
trava de armamento (a trava é `UDR7_ARM_ALLOWED`, somente arquivo); `READ_ONLY=1` pode
conviver com o daemon armado até a aposentadoria da chave (`docs/BACKLOG_20260901.md`).

Nenhuma credencial no `.env.example` versionado; senha nunca em argv (padrão da casa:
stdin, como `ont-stick-setup/lib/unifi-check.py`).

---

# 23. Fases de entrega

## Fase 0 — validação

Entregar:

```text
research/findings.md
```

com resposta factual:

1. qual é o protocolo real do UniFi UPS;
2. ele permite third-party device?
3. exige identidade/certificado Ubiquiti?
4. é possível emular sem patch?
5. quais endpoints/events existem?
6. Alarm Manager aceita eventos?
7. UPS UI é acessível a third party?

## Fase 1 — NUT

Entregar:

```text
RIVER USB
→ Mac mini
→ NUT
→ upsc funcional
→ HA funcional
```

## Fase 2 — Bridge read-only

```text
NUT
→ normalized model
→ logs
→ simulator
```

## Fase 3 — UniFi PoC

```text
bridge
→ UniFi
→ device visible
```

Sem alarm/action inicialmente.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* a Fase 3 como "device visible" **não tem
caminho nativo documentado** (`docs/2026-08-31-2345-pesquisa-udr7-ups-terceiros.md`). Em seu lugar
entra a **Fase 3'-EXP — UDR7 protegido pelo River** (fase experimental separada, §2.5):
desligamento gracioso do console via SSH quando a queda é confirmada e a bateria cruza o
limiar acima do corte físico; ensaio primeiro, armamento por ato do dono, religamento
manual como caminho de base (H13/H14/H16). Runbook: `docs/2026-09-01-0817-runbook-protecao-udr7-ssh.md`.

## Fase 4 — Telemetria

UPS UI com dados reais.

## Fase 5 — Alarm Manager

Power loss / restore / low battery / comm loss.

## Fase 6 — hardening

- launchd;
- reconnect;
- watchdog;
- security;
- diagnostics;
- installer;
- uninstall;
- documentation.

## Fase 7 — Wi-Fi local research

Tentar eliminar USB apenas se houver protocolo local real.

## Trilha UI (Componente D — paralela, não bloqueia as fases acima)

| Fase UI | Entrega | Depende de | Contra fake-nut-ups? |
|---|---|---|---|
| UI-0 | api.py + history.py + doc do contrato | Fase 2 | Sim, 100% |
| UI-1 | menu bar + dashboard (ícone vivo, gráficos, timeline) | UI-0 | Sim |
| UI-2 | saúde da cadeia | UI-0 (elos USB/NUT reais após Fase 1; antes, "não observável") | Parcial |
| UI-3 | configuração | UI-0 + hot-reload | Sim |
| UI-4 | instalação guiada | instalador básico + plists + uninstall mínimo (Fase 6a) | Não |

A Fase 6 divide-se em **6a** (instalador básico + plists launchd + uninstall mínimo,
pré-requisito da UI-4) e **6b** (hardening final). No desfecho "relatório de
inviabilidade" da PoC UniFi, as Fases 4–5 são canceladas e o hardening não fica
bloqueado por elas — o MVP do §24 não depende de sucesso UniFi.

---

# 24. Critérios de aceite

## MVP obrigatório

- [ ] Mac mini detecta RIVER 3 Plus via USB.
- [ ] NUT `usbhid-ups` opera de forma estável.
- [ ] `upsc` retorna telemetria real.
- [ ] `upsd` publica na LAN.
- [ ] Home Assistant consome NUT.
- [ ] Serviço reinicia após reboot.
- [ ] Funciona sem Internet.
- [ ] Sem cloud no caminho crítico.
- [ ] Nenhuma alteração irreversível no UDR7.
- [ ] Diagnóstico coletável em um único comando.

## UniFi PoC

- [ ] protocolo real documentado;
- [ ] mecanismo de discovery/adoption documentado;
- [ ] bridge consegue estabelecer sessão;
- [ ] device aparece no UniFi **ou** relatório prova tecnicamente por que isso não é possível;
- [ ] telemetria é real;
- [ ] nenhum valor sintético apresentado como real.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* os critérios da PoC UniFi **não foram
atingidos** (sem caminho nativo documentado; relatório em
`docs/2026-08-31-2345-pesquisa-udr7-ups-terceiros.md`); a visibilidade nativa sai do caminho
primário. Critério da Fase 3'-EXP: em ensaio com o simulador, `UDR7_SHUTDOWN_DRYRUN` ↔
`UDR7_PROTECTION_REARMED` com `would_block=fonte_nao_real`; armado, só com telemetria de
fonte não-sintética, serial registrado e trava aberta pelo dono.

## UI nativa (Componente D, §7A)

- [ ] Ícone vivo na menu bar reflete estado/bateria reais (— quando daemon parado; nunca fabricado).
- [ ] Dashboard: gauges + 2 gráficos de série temporal + timeline de eventos, dados do daemon.
- [ ] Tela de saúde mostra a cadeia com elos "não observável" honestos.
- [ ] Configuração via PUT /v1/config preserva comentários do .env (round-trip provado em teste).
- [ ] Onboarding: consentimento Homebrew antes de qualquer instalação; 2ª execução reporta "já estava" (100).
- [ ] 60fps nas animações (Instruments), dark/light OK, VoiceOver nos valores principais.
- [ ] Dono confirma: "parece um app da Apple".

## Entregável ideal

- [ ] RIVER aparece como UPS no UniFi;
- [ ] battery %
- [ ] online/on-battery
- [ ] runtime
- [ ] load
- [ ] last seen
- [ ] Alarm Manager
- [ ] HA via NUT
- [ ] Mac graceful shutdown
- [ ] tudo local.

---

# 25. Critério de “não conseguimos”

Não aceitar:

> “Não há documentação, então não dá.”

Antes de concluir inviabilidade, o implementador deve executar:

1. documentação oficial;
2. inspeção UI;
3. DevTools;
4. bundle JS;
5. logs;
6. processos/ports;
7. schemas;
8. firmware/software público;
9. tráfego capturado, se houver hardware;
10. experimento de protocolo.

Somente depois disso a inviabilidade pode ser declarada.

A conclusão deve dizer exatamente **qual barreira técnica foi encontrada**, por exemplo:

```text
server requires per-device certificate signed by Ubiquiti CA
```

ou:

```text
UPS UI only renders DB objects created by proprietary adoption service
```

e anexar evidência.

---

# 26. O que NÃO fazer

Não:

- inventar distância física entre equipamentos;
- inventar planta;
- presumir topologia;
- presumir protocolo UniFi;
- presumir IDs USB;
- hardcodar senha;
- expor NUT à Internet;
- usar EcoFlow cloud como requisito;
- desligar saída AC em testes;
- executar destructive command no UDR7;
- modificar firmware;
- instalar dependências sem listar;
- criar Raspberry Pi/gateway adicional como premissa;
- afirmar impossibilidade sem evidência.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* **exceção PEDIDA ao item "executar
destructive command no UDR7" — PENDENTE DE RATIFICAÇÃO DO DONO.** A ordem do dono em
2026-09-01 ("termina esta porra do plano e executa tudo em modo madrugada. Pela manhã eu
testo") ordena a execução **do plano**; **não** contém autorização literal para o comando
destrutivo. A exceção só vale após ratificação escrita e, mesmo então, sob as condições da
Fase 3'-EXP: ensaio por padrão, trava `UDR7_ARM_ALLOWED` somente arquivo, fonte de
telemetria não-sintética com serial registrado, `armed.json` pinando a configuração, e
desarme sempre possível. Até a ratificação, `PROTECT_DRY_RUN=1` e `UDR7_ARM_ALLOWED=0`.

---

# 27. Saída esperada do LLM implementador

O LLM deve entregar um **repositório git** (histórico atômico, sem trailers de
ferramenta) contendo:

```text
river-unifi-bridge/
```

com:

1. código-fonte;
2. instalador;
3. desinstalador;
4. configs;
5. launchd;
6. testes;
7. simulador;
8. ferramentas de investigação;
9. README;
10. relatório de pesquisa;
11. protocolo descoberto;
12. instruções de captura;
13. rollback.

Também deverá incluir:

```text
QUICKSTART.md
ARCHITECTURE.md
RESEARCH.md
SECURITY.md
TEST-PLAN.md
```

---

# 28. Forma de trabalho esperada

O desenvolvimento deve ocorrer nesta ordem:

```text
OBSERVAR
   ↓
DOCUMENTAR
   ↓
REPRODUZIR
   ↓
IMPLEMENTAR
   ↓
TESTAR
   ↓
AUTOMATIZAR
   ↓
HARDEN
```

Nunca:

```text
CHUTAR
  ↓
CODIFICAR
```

## 28.1 Convenções da casa (ABHOME-infra)

Este projeto segue as convenções do monorepo `/Users/alessandro/Development/ABHOME-infra`
(manual operacional: `ABHOME-infra/CLAUDE.md`). Resumo do que vincula:

- **Idioma:** documentação e saída de script em pt-BR; comentários de código em inglês.
- **Shell:** bash compatível com 3.2 do macOS (sem namerefs, sem arrays associativos,
  sem process substitution em caminho crítico). Python 3 stdlib como auxiliar.
- **Exit codes:** contrato 0 = fez agora · 100 = já estava · 1 = falha; códigos nomeados
  (2 uso, 3 validação, 4 dependência, 10 conexão, 130 cancelado).
- **Reversibilidade:** manifesto `created/preexisting/pending` + uninstall que só remove
  o que prova ter criado, nunca `rm -rf` (`ABHOME-haos-macmini/haos-install.sh:724-758`,
  `:2399-2432`).
- **Docs:** documento vivo com data no nome (`<ASSUNTO>_<aaaammdd>.md`); versão anterior
  íntegra em `_archive/`; camada executiva na frente, referência atrás; marcadores
  [FATO]/[CONFIRMAR]/[LIMITE].
- **Teste:** arnês `tools/gate.sh` com dublês/stubs e teste de idempotência
  ("2ª execução reporta 100"); toda cerca nova passa por teste de mutação
  (plantar o defeito, a cerca TEM de reprovar).
  *Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* na Fase 3'-EXP a mutação é
  **parcial e declarada** (11 cenas para as cercas decisivas, incluindo S4m — o nome do dispositivo não é congelado com o daemon armado — e S4o — o nome não é pino de armamento; as demais só teste) — ver §18.1.
- **Reuso direto identificado (2026-08-31):** molde de instalador
  `ABHOME-macmini/macmini-backup.sh`; launchd idempotente
  `ABHOME-haos-macmini/haos-install.sh:1253-1345`; cliente da API local do UniFi OS
  provado contra UDR7 `ont-stick-setup/lib/unifi-check.py`; molde de package HA
  `ABHOME-haos-macmini/packages/energia_br.yaml`.

---

# 29. North Star

A experiência final desejada é:

```text
              EcoFlow RIVER 3 Plus
                       │
                    USB
                       │
                  Mac mini
                  /      \
              NUT        Bridge
               │            │
               ▼            ▼
              LAN         UniFi
               │            │
       ┌───────┴──────┐    ├── UPS UI
       │              │    └── Alarm Manager
       ▼              ▼
 Home Assistant      macOS
```

Para o usuário, o resultado deve parecer um **UPS de rede nativo**, apesar de o transporte físico inicial do RIVER ser USB.

O objetivo da PoC não é “fazer algo parecido”.

O objetivo é descobrir até onde é possível reproduzir, com hardware EcoFlow, a experiência de gerenciamento de UPS que o UniFi oferece ao seu UPS Tower — mantendo o RIVER como fonte elétrica real, NUT como camada UPS aberta e o UDR7 como plataforma de gerenciamento.

---

# 30. Próxima ação do LLM

Ao receber este documento, executar primeiro:

```text
PHASE 0 — RESEARCH
```

e **não começar pela implementação da emulação**.

A primeira entrega deve ser uma tabela factual:

| Questão | Resultado | Evidência | Confiança |
|---|---|---|---:|
| Protocolo UPS Tower ↔ UniFi | | | |
| Discovery | | | |
| Adoption | | | |
| Authentication | | | |
| Telemetry | | | |
| Alarm transport | | | |
| UPS UI schema | | | |
| Third-party support | | | |
| Emulation viability | | | |

Somente depois de fechar essa matriz deve ser escolhido o adapter UniFi definitivo.

*Adendo Fase 3'-EXP (2026-09-01, plano piped-seeking-toast v5.1, banca 3/3):* a matriz está preenchida em
`research/findings.md` com o que a pesquisa documental respondeu (majoritariamente
`não documentado` / `UNKNOWN`, com evidência e confiança); o adapter UniFi nativo **não**
foi escolhido — a Fase 3'-EXP não depende dele.
