# Arquitetura de plugins para o River Bridge — benchmarks e parecer (2026-09-01)

Pergunta do dono: "a gente deveria ter uma arquitetura de plugin para o app — o UDR7 seria um
plugin e, se selecionado, você entra na folha de configurações e o daemon atua. Pesquise os
benchmarks dessa arquitetura expansível/plugin reais; o UDR7 vira o primeiro plugin, faz
sentido? Inclusive o usuário pode dar o nome do device que aparece nos relatórios e gráficos.
Ex.: plugin UniFi UDR7 → nome: Meu UDR."

Fontes primárias acessadas em 2026-09-01 (duas pesquisas independentes; notas brutas com as
citações literais no histórico da sessão). Legenda: **[C]** confirmado literalmente na fonte ·
**[I]** inferido · **[M]** medido no repositório no ato.

## 1. Como os produtos reais modelam "dispositivos protegidos" e extensões

| Produto | Como chama a extensão | Onde vive | Como o usuário configura | Usuário dá nome ao dispositivo? |
|---|---|---|---|---|
| **NUT** (networkupstools.org, man `upsmon.conf`, `ups.conf`, `upssched`) | *driver* por hardware; *cliente* `upsmon` (o protegido); `CMDSCRIPT` (hooks) | drivers **in-tree** ("needs to be added to drivers/Makefile.am") [C]; hooks = scripts externos [C] | arquivos `ups.conf` / `upsmon.conf` / `upssched.conf` [C] | o **UPS**: `[nome]` + `desc=` em `ups.conf` [C]; os clientes protegidos **não** têm nome no servidor — cada um se inscreve sozinho (`MONITOR ups@host … primary\|secondary`) [C] |
| **apcupsd** (manpages `apccontrol(8)`, `apcupsd.conf(5)`) | script de evento em `/etc/apcupsd/<evento>` ("create an executable … with the same name as the event") [C] | scripts **out-of-tree** por convenção de nome; `exit 99` suprime a ação padrão [C] | arquivo `apcupsd.conf` [C] | UPS via `UPSNAME` [C]; clientes `UPSTYPE net` por IP, sem nome [C] |
| **APC PowerChute Network Shutdown 4.3** (guia 990-4595F-001) | agente por host protegido; hosts sem agente = **"SSH Action"** [C] | proprietário | UI web: *Add Action* → "Name: A unique name for each SSH action", IP/FQDN, porta, arquivo de comando; *Configure Events* [C] | sim — o usuário nomeia a **ação** SSH [C] |
| **Eaton IPM 1.30** (guia do usuário) | "Applications" = agentes de shutdown (IPP) em cada host [C] | proprietário | UI web (lista de nós, tela Applications) [C] | sim — "Edit node information … node name, user type, node description" [C] (IPM 2.3 não verificado: eaton.com fora do ar) |
| **Synology DSM 7 / QNAP QTS 5.2** | "network UPS server" / master + clientes | fechado | checkbox + **lista de IPs permitidos** [C] | não — só IPs [C] |
| **Home Assistant** (developers.home-assistant.io) | *integration*: `manifest.json` (+ `config_flow`) [C] | **ambos**: `homeassistant/components` (core) e `custom_components`, com o **mesmo contrato** [C] | UI guiada gerada de `vol.Schema` (config flow + options flow) [C] | sim — `name_by_user` no device registry ("The user configured name of the device.") [C]; que ele apareça em todos os gráficos é comportamento do frontend [I] |
| **Homebridge** (homebridge.github.io, `pluginManager.ts`) | plugin npm `homebridge-*` com keyword `homebridge-plugin` [C] | **out-of-tree** (npm) | formulário gerado de `config.schema.json` (JSON Schema, ng-formworks) [C] | sim — campo `name` no schema do template [C] |
| **Scrypted** (developer.scrypted.app) | plugin npm, seção `scrypted{name,type,interfaces}` no package.json [C] | out-of-tree | UI gerada em runtime de `getSettings(): Setting[]` [C] | não encontrado na doc |
| **Stats** (exelban/stats, app de menu bar em Swift) | *module*: `class CPU: Module` com `module_c{name, icon, defaultState}`, `enabled` [C] | **in-process**, array estático `var modules: [Module] = [CPU(), GPU(), …]` (AppDelegate.swift:26) [C] | cada módulo passa a **própria settings view** no `super.init` [C]; estado `\(name)_state` persistido [C] | n/a (módulos de hardware) |

O que a tabela diz, em uma frase: **os produtos de UPS "de verdade" não têm plugin — têm
agentes autônomos (NUT, apcupsd, PCNS, IPP) ou listas de IP (Synology, QNAP); quem tem
"dispositivo com folha de configuração e nome do usuário" são as plataformas de automação
(Home Assistant, Homebridge), e o modelo delas é in-tree com contrato de plugin.** O mais
próximo do que o dono descreveu é o PCNS: um host sem agente vira uma **ação SSH nomeada**
pelo usuário — que é exatamente o que a proteção do UDR7 é hoje.

## 2. Como um app macOS em Swift se estende hoje (developer.apple.com, GitHub)

- **ExtensionKit / ExtensionFoundation** (macOS 13+): extensões **out-of-process** —
  "App extensions are a way to extend your app's features safely, using code that runs in a
  separate process" [C]; cada uma é um bundle `.appex` com `NSXPCConnection`, entitlements
  de sandbox e um protocolo XPC serializável [C]. Não existe sessão WWDC "Meet ExtensionKit"
  (verificado); o exemplo de referência é comunitário. Paga quando há **código de terceiros**
  a isolar.
- **In-process por protocolo Swift** (Stats): registro estático de módulos, cada um com nome,
  ícone, estado habilitável e a própria view de ajustes [C]. Um arquivo por módulo.
- **Formulário gerado de schema** (Homebridge): não há biblioteca SwiftUI open-source que
  gere uma folha de ajustes a partir de JSON Schema (busca em 2026-09-01: só validadores).
  Escrever o renderizador custa mais que escrever 3–5 folhas à mão.
- **Plugins dylib de terceiros** em app com Hardened Runtime exigem
  `com.apple.security.cs.disable-library-validation` e herdam os entitlements do host [C] —
  exceção de segurança explícita, desnecessária para código do próprio autor.

## 3. O que o River Bridge já é, medido no código [M]

`git grep -ci udr7` em 2026-09-01: o UDR7 está em **11 arquivos** — daemon `protect.py` 78,
`config.py` 56, `api.py` 7, `service.py` 4, `state.py` 3; app `SettingsView` 41,
`EventsTimeline` 22, `ChartsView` 14, `ModelsDecodingTests` 9, `HealthView` 6, `Models` 4.
São **19 chaves** com prefixo fixo `UDR7_`/`PROTECT_`, **10 tipos de evento** `UDR7_*` com o
rótulo "UDR7" gravado no código dos chips e da legenda (`ChartsView.swift:369-378`), e o elo
`udr7`/`udr7_detail` do health com nome fixo (`state.py:77-78`).

A costura no daemon já é a de um plugin: a política só é chamada em quatro pontos —
`observe` (`service.py:156`), `observe_failure` (`:143`), `status` (`:158`),
`on_config_applied` (`api.py:307`) — mais `drain_transition` (`:134`). O que **não** existe
em lugar nenhum: nome dado pelo usuário ao UDR7. Só o River tem nome (`RIVER_NAME` →
`identity.name`, `api.py:52`); o console aparece como "UDR7" em tudo.

## 4. Parecer

**Faz sentido — com o desenho certo.** O pedido tem duas partes com custos muito diferentes:

1. **"O usuário dá nome ao dispositivo e ele aparece nos relatórios e gráficos"** — isto é o
   `name_by_user` do Home Assistant, é barato e é o que o dono vê. Uma chave `UDR7_NAME`
   (default "UDR7"), devolvida pelo daemon no `udr7_detail` e no `detail` de cada evento
   `UDR7_*`, e o app troca o rótulo fixo pelo nome em chips, legenda, saúde e título do grupo
   de ajustes. Vale fazer **antes** de qualquer arquitetura, porque é o benefício visível e
   não depende dela.
2. **"Arquitetura de plugin com o UDR7 como primeiro plugin"** — recomendo **in-process por
   protocolo, no molde do Stats e do Home Assistant, nunca ExtensionKit nem schema**:
   - **Daemon (Python):** um contrato `Plugin` com os quatro pontos que já existem
     (`observe`, `observe_failure`, `status`, `on_config_applied`) mais `id`, `display_name`
     (o nome do usuário), `config_keys` (as chaves que ele possui, com faixas) e
     `event_types`. `protect.py` vira o primeiro plugin (`plugins/udr7_ssh.py`) sem mudar
     uma linha da política; `config.py` monta a allowlist somando as chaves dos plugins
     registrados; health ganha `plugins: [{id, name, state, detail}]` mantendo `udr7`/
     `udr7_detail` como alias até o app migrar. Registro **estático**, como no Stats — um
     array de classes, não descoberta em disco (nada de código carregado de fora: o daemon
     roda como LaunchDaemon com a chave do console; a superfície de ataque continua zero).
   - **App (Swift):** um protocolo `DevicePlugin` com `id`, `icon`, `name` (do usuário),
     `settingsView`, `healthCard`, `eventTypes` + cores, e um registro estático; a folha de
     Ajustes ganha o grupo **"Dispositivos protegidos"**: lista com toggle por plugin
     (habilitado = `PROTECT_<ID>=1`) e, ao selecionar, a folha daquele plugin — que é a que
     já existe hoje, com o campo "Nome" no topo. Chips e legendas passam a perguntar o nome
     ao plugin.
   - **O que NÃO fazer:** ExtensionKit (processo, XPC, entitlements — custo puro para um
     único autor; a ação já corre fora do app, no daemon), JSON Schema → SwiftUI (sem
     biblioteca; renderizador > folhas), plugins carregados de disco (segurança).
   - **As cercas não mudam:** as dez condições, a trava de armamento, o desarme sempre aceito
     e o simulador nunca armar continuam dentro do plugin do UDR7; o contrato não tem como
     afrouxá-las — é só quem chama quem.

**Candidatos a 2º e 3º plugin, para o contrato não nascer com um caso só:** o próprio Mac
mini (desligamento gracioso do host — B07 do backlog, é o que o gist da comunidade faz) e um
"comando SSH genérico" (qualquer host Linux/BSD com `shutdown -h now`) — o modelo da ação
SSH do PowerChute. Os três compartilham o mesmo contrato e a mesma folha, com campos
diferentes.

**Ordem e custo (estimativa minha, a confirmar no plano):** (1) nome do dispositivo —
~1 chave, 3 arquivos no daemon, 5 no app, meio dia; (2) contrato de plugin no daemon com o
UDR7 movido para dentro — refatoração mecânica com os 164 testes como rede, um dia; (3) o
grupo "Dispositivos protegidos" no app — um dia com capturas; (4) 2º plugin (Mac mini) —
depende de decisão sua sobre desligar o host que roda o HA.

**Riscos declarados:** renomear chaves (`UDR7_*` → `PLUGIN_UDR7_*`) quebraria o `.env` do
mini — manter os nomes atuais e só prefixar os plugins novos; o alias `udr7` no health some
apenas quando o app não o ler mais; capturas focadas continuam sendo o critério da UI.
