# Pesquisa de parâmetros UPS — RIVER 3 Plus, UniFi UPS e SOTA (2026-08-31)

Motivo: os defaults de alarme da spec (queda 3 s, restauração 5 s, comm 20 s,
bateria 15%) foram fixados sem fonte — invenção. Este documento substitui o
palpite por fatos com referência. Regra aplicada: **todo número tem URL de
fonte; [P] = primária (doc oficial/man page/código oficial), [S] = secundária
(fórum/review); o que não foi encontrado está listado como NÃO ENCONTRADO,
nunca preenchido.**

---

## 1. EcoFlow RIVER 3 Plus × NUT — o que o aparelho REALMENTE expõe

- Suporte entrou no **NUT 2.8.3** (subdriver `ecoflow-hid` do `usbhid-ups`,
  USB `3746:ffff`, modelo `EF-UPS-R3P`), nível 3 na HCL, marcado
  **experimental** no master. [P]
  [NEWS.adoc](https://raw.githubusercontent.com/networkupstools/nut/master/NEWS.adoc) ·
  [issue #2735](https://github.com/networkupstools/nut/issues/2735) ·
  [PR #2740](https://github.com/networkupstools/nut/pull/2740) ·
  [PR #2837](https://github.com/networkupstools/nut/pull/2837)
- Variáveis mapeadas ([P — ecoflow-hid.c v2.8.3](https://raw.githubusercontent.com/networkupstools/nut/v2.8.3/drivers/ecoflow-hid.c)):
  `battery.charge`, `battery.charge.low` (**= Discharge Limit do app EcoFlow**;
  a estação **corta a carga sozinha nesse limite +1%**), `battery.charge.warning`
  (**fixo 10% no River 3+**), `battery.runtime` (dispositivo manda MINUTOS,
  driver converte p/ segundos), `battery.runtime.low` (**fixo 600, em minutos,
  SEM conversão — inconsistência de unidade**), `battery.voltage(.nominal)`,
  `ups.power.nominal` (286), `ups.beeper.status`, status OL/OB/CHRG/DISCHRG/
  FullyCharged/RB/Overload etc.
- **Dump real** de um River 3 Plus (NUT 2.8.4, [P — issue #3068](https://github.com/networkupstools/nut/issues/3068)):
  **NÃO existem** `input.voltage`, `ups.load`, `ups.realpower`, `output.voltage`,
  `ups.temperature`. Telemetria elétrica só no driver companion
  `ecoflow-hid-aux-cdc.c` (porta serial CDC), **apenas no master, não lançado**. [P]
- **BUG CRÍTICO: o status `LB` nunca dispara** no River 3 Plus — carga 27% <
  low 50% e descarga até 0% sem LB; confirmado pelo mantenedor jimklimov
  ("nobody added code to report LB based on charge/voltage being under
  threshold, and the device does not internally report such status"). Issue
  aberto. **Consequência: alarme de bateria baixa TEM de ser comparação nossa
  `battery.charge` × limiar, nunca o LB do NUT.** [P — issue #3068]
- Controles via NUT: **nenhum funciona** (beeper/shutdown/reboot por `upscmd`
  não operam; comentado no driver). [P]
- UPS oficial EcoFlow: comutação **<10 ms** ("standby UPS"), carga total
  **≤600 W** nas saídas AC (X-Boost indisponível em bypass), 286 Wh LiFePO4.
  [P — [página oficial](https://www.ecoflow.com/us/river-3-plus-portable-power-station) ·
  [manual PDF](https://www.santansolar.com/wp-content/uploads/EcoFlow-RIVER-3-Plus-Portable-Power-Station_User-Manual_250430.pdf)]
- App EcoFlow (nomes do manual): **Charging/Discharging Limit**, velocidade de
  carga AC, **AC Timeout** (a saída AC desliga sozinha se "idle" — manual manda
  pôr em **never** para carga crítica), Output Port Memory, X-Boost, Scheduled
  Task. [P — manual] Aviso de queda = luz frontal (~30 s), sem push; "Low
  battery reminder" fixo em 20%. [S — [apollomaniacs](https://www.apollomaniacs.com/knowhow_ups_ecoflow_river3_plus_en.htm)]

### Checklist do dia do hardware (derivado, executável)
1. `AC Timeout = never` e conferir Discharge Limit no app (ele define
   `battery.charge.low` e o ponto de corte da carga).
2. `upsc` completo no ato → registrar o dump real (inclusive se
   `battery.charge.warning`=10 e `runtime.low`=600 confirmam).
3. Verificar unidade de `battery.runtime` (minutos×segundos) na versão do NUT
   instalada (2.8.4 do brew converte; confirmar no dump).
4. Testar se o macOS tenta reivindicar o HID UPS nativamente (conflito com o
   driver NUT).

---

## 2. UniFi UPS (Tower / 2U / 2U Pro) — a régua da integração

- Linha "UniFi Uninterruptible Power"; firmware "UniFi UPS"; lançada out/2025
  (fw 1.4.12). [P — [blog](https://blog.ui.com/article/introducing-uninterruptible-power) ·
  [release](https://community.ui.com/releases/UniFi-UPS-1-4-12/6c047e49-2098-49e9-88d6-f257e7493fd8)]
- **Totalidade de controles expostos ao usuário** (Network App + fw):
  - **Safe Shutdown Trigger Point em MINUTOS de autonomia restante** +
    **Auto-Recovery power cycle delay** — configuráveis só desde Network
    10.4.57 + fw 1.4.30 (mai/2026); antes: **10 s fixos** após a queda. [P —
    [RSS releases Network](https://community.ui.com/rss/releases/UniFi-Network-Application/e6712595-81bb-4829-8e42-9e2630fabcfe)]
  - **Buzzer** on/off (Network 10.2.93 + fw 1.4.24+); alarme sonoro em bateria
    surgiu no fw 1.4.23; Auto Power Cycle 10 s→60 s no 1.4.23. [P]
  - **Servidor NUT embarcado** on/off, com **ID/hostname, porta e credenciais
    opcionais** configuráveis. [S — StorageReview; P — store: "NUT
    compatibility for third-party devices"]
  - Sensibilidade de tensão High/Medium/Low, EPO, tomadas individuais
    nomeáveis/controláveis, telemetria por tomada — **só no 2U Pro**. [S/P]
  - **Não existem**: limiar por % de bateria (feature request aberto), teste de
    bateria/calibração, histórico/gráfico de consumo (request aberto), alerta
    de energia restaurada (request aberto). [S]
- **Ouro para a Fase 0**: o UPS UniFi fala **NUT** — servidor embarcado que se
  identifica como "Network UPS Tools upsd 2.8.0", TCP 3493, com desvios
  documentados (responde `BEGIN LIST UPS "myups"`; expõe `battery.low` fora da
  spec; sem `battery.runtime.low`). [S —
  [HA issue #154469](https://github.com/home-assistant/core/issues/154469)]
  Pareamento de shutdown oficial: só UNVR/UNAS; exige conta do console owner. [P/S]
- A lógica de shutdown deles mudou 3× em 2026 (10 s fixos → 60 s → gatilho por
  autonomia configurável), sempre acoplando fw do UPS × versão da Network App —
  **emulação nossa deve tratar o comportamento como alvo móvel**. [P — releases]

---

## 3. Benchmarks SOTA — defaults DOCUMENTADOS

### NUT ([P — man pages oficiais](https://networkupstools.org/docs/man/upsmon.conf.html))
| Parâmetro | Default | Papel |
|---|---|---|
| upsmon POLLFREQ / POLLFREQALERT | 5 s / 5 s | polling normal / em bateria |
| upsmon **DEADTIME** | **15 s** | sem dados → UPS "dead" (≈ nosso COMM_LOST) |
| upsmon HOSTSYNC / FINALDELAY | 15 s / 5 s | sincronização / pausa final |
| upsmon NOCOMMWARNTIME / RBWARNTIME | 300 s / 43200 s | repetição de avisos |
| [ups.conf](https://networkupstools.org/docs/man/ups.conf.html) `pollinterval` | **2 s** | polling do driver |
| [usbhid-ups](https://networkupstools.org/docs/man/usbhid-ups.html) `lowbatt` fallback | **30%** | quando o dispositivo não dita (`DEFAULT_LOWBATT "30"`) |
| usbhid-ups `pollfreq` | 30 s | atualização completa HID |
| Critério de shutdown | **OB + LB simultâneos** → FSD | LB vem de bits HID do dispositivo |
| `default.*` / `override.*` | — | fallback quando ausente / força mesmo presente |

### apcupsd 3.14.14 ([P — manual + conf de fábrica + código](http://web.archive.org/web/20240321025441/http://www.apcupsd.org/manual/manual.html))
| Diretiva | Default | Papel |
|---|---|---|
| **ONBATTERYDELAY** | **6 s** | debounce do evento "onbattery" (≈ nosso POWER_LOSS_DELAY) |
| BATTERYLEVEL | 5% | shutdown por % restante |
| MINUTES | 3 min | shutdown por runtime restante |
| TIMEOUT | 0 (off) | shutdown por tempo em bateria |
| POLLTIME | 60 s (→1 s em bateria) | polling |
| ANNOY / ANNOYDELAY | 300 s / 60 s | avisos a usuários logados |
| KILLDELAY | 0 (off) | corte da saída do UPS |

### Outros
| Software | Fato | Fonte |
|---|---|---|
| PowerChute SS/BE | shutdown default por Low Battery/runtime; "OS shutdown time" 180 s; **sem limiar por %** | [P — guias Schneider] |
| Synology DSM 7 | default: Standby quando o UPS sinaliza bateria baixa; tempo customizável; bateria baixa SEMPRE vence | [P — [KB](https://kb.synology.com/en-us/DSM/help/DSM/AdminCenter/system_hardware_ups?version=7)] |
| QNAP QTS 4.2 | regra fixa: **<15% → proteção em 30 s** | [P — [doc](https://docs.qnap.com/operating-system/qts/4.2.x/cat1/en-us/ups.htm)] |
| Home Assistant NUT | polling **60 s**, porta 3493 | [P — [doc](https://www.home-assistant.io/integrations/nut/) + coordinator.py] |
| macOS pmset | `haltlevel` (%), `haltafter` (min), `haltremain` (min) — defaults NÃO documentados | [P — man pmset] |

---

## 4. Inventário COMPLETO — do universo do mercado para nós

> Correção metodológica (2026-08-31, apontada pelo dono): a primeira versão
> desta seção partia dos NOSSOS 5 parâmetros e buscava âncora para cada um —
> enquadramento enviesado. Esta tabela parte da TOTALIDADE encontrada na
> pesquisa e mapeia contra a bridge. "N/A hardware" sempre traz o porquê.

| # | Parâmetro (classe) | Quem tem / default documentado | Nós hoje | Veredicto p/ nosso cenário |
|---|---|---|---|---|
| **A — Coleta** | | | | |
| 1 | Poll normal | NUT `pollinterval` 2 s; upsmon 5 s; usbhid-ups 30 s; apcupsd 60 s; HA 60 s; QNAP 15 s | ✅ 2 s | mantém (âncora ups.conf) |
| 2 | Poll acelerado EM BATERIA | upsmon POLLFREQALERT 5 s; apcupsd →1 s; QNAP →5 s | ❌ | **ADICIONAR** — padrão em 3 referências |
| **B — Detecção/alarme** | | | | |
| 3 | Debounce "entrou em bateria" | apcupsd ONBATTERYDELAY 6 s | ✅ 3 s | ajustar → 6 s |
| 4 | Notificação de restauração | ninguém debouncia; UniFi nem alerta | ✅ 5 s | ajustar → 0 s |
| 5 | Comunicação perdida | upsmon DEADTIME 15 s | ✅ 20 s | ajustar → 15 s |
| 6 | Repetição do aviso sem-comm | upsmon NOCOMMWARNTIME 300 s | ❌ | avaliar (política de re-aviso) |
| 7 | Aviso "trocar bateria" (RB) + repetição | upsmon RBWARNTIME 12 h; driver EcoFlow mapeia NeedReplacement (mas ativa no Discharge Limit — não confiável) | ❌ | exibir honesto; sem alarme repetido até medir |
| 8 | Bateria baixa por **%** | usbhid-ups fallback 30%; QNAP fixo 15%; EcoFlow reminder fixo 20%; apcupsd 5% (shutdown) | ✅ 15% | ajustar → 30% (LB do NUT nunca dispara no River — comparação é nossa) |
| 9 | Bateria baixa por **AUTONOMIA (min)** | **eixo dominante do mercado**: UniFi (único gatilho deles), apcupsd MINUTES 3, PowerChute runtime limit, pmset haltremain | ❌ | **ADICIONAR** — mas só após medir a qualidade do runtime do River (driver: estimativa p/ capacidade cheia, quirk de 40 h) |
| 10 | Bateria baixa por **tempo em bateria** | apcupsd TIMEOUT 0 (off); pmset haltafter; PowerChute "after N on battery" | ❌ | avaliar (3º eixo; apcupsd embarca desligado) |
| **C — Ação (shutdown/orquestração)** | | | | |
| 11 | Critério de shutdown do host | upsmon OB+LB→FSD; apcupsd 1º-de(%,min,tempo); UniFi minutos; Synology standby; pmset | ❌ (READ_ONLY) | decisão de produto pendente (dono) |
| 12 | Tempo p/ SO desligar / sync | PowerChute 180 s; upsmon FINALDELAY 5 s + HOSTSYNC 15 s | ❌ | junto com o 11 |
| 13 | Corte da saída do UPS pós-shutdown | apcupsd KILLDELAY 0; Synology "shut down UPS"; upsmon powerdown | — | **N/A hardware**: `upscmd` não funciona no River (driver, [P]) |
| 14 | Auto-recovery / power-cycle delay | UniFi 60 s (configurável) | — | **N/A hardware**: idem 13 |
| 15 | Religar condicionado (ondelay/offdelay) | usbhid-ups 30 s/20 s | — | **N/A hardware**: idem 13 |
| **D — Notificação ao humano** | | | | |
| 16 | Buzzer/luz on/off | UniFi buzzer on/off; River: luz só pelo app EcoFlow | — | **N/A via NUT** (beeper cmds não funcionam); registrar no app EcoFlow |
| 17 | Notificação no desktop | apcupsd ANNOY 300 s/ANNOYDELAY 60 s (era multi-usuário); UniFi alerta "on battery" | ❌ (só timeline) | **ADICIONAR** — notificação macOS nos eventos críticos |
| **E — Dados/histórico** | | | | |
| 18 | Retenção | sem default de mercado (UniFi não tem histórico; HA delega ao recorder) | ✅ 7 d | mantém PROVISÓRIO-SEM-FONTE |
| 19 | Histórico/gráficos | UniFi: feature request aberto | ✅ | vantagem nossa; mantém |
| **F — Exposição NUT (p/ UDR7)** | | | | |
| 20 | NUT server: ID, porta, credenciais | UniFi expõe os 3 na UI | ⚠️ parcial (.env NUT_*, upsd.users manual) | relevante na Fase 0/3 |
| **G — Lado do aparelho (app EcoFlow)** | | | | |
| 21 | Discharge/Charge Limit, AC Timeout, veloc. carga, X-Boost, Port Memory | app EcoFlow (manual oficial) | — | não é nosso; checklist do hardware + exibir `battery.charge.low` honesto |
| **H — Não aplicáveis com fonte** | | | | |
| 22 | Sensibilidade de tensão | UniFi 2U Pro H/M/L; apcupsd SENSITIVITY | — | **N/A hardware**: River não expõe tensão de entrada |
| 23 | Teste/calibração de bateria | nem a UniFi tem | — | N/A |
| 24 | MINSUPPLIES (multi-UPS) | upsmon ≥1 | — | N/A (1 UPS) |

### 4b. Comparativo dos 5 existentes (mantido por rastreabilidade)

| Nosso parâmetro | Valor atual (inventado) | Âncora SOTA com fonte | Proposta |
|---|---|---|---|
| Queda de energia (debounce) | 3 s | apcupsd ONBATTERYDELAY **6 s** [P] — único debounce de "on battery" com default documentado | **6 s** |
| Energia restaurada (debounce) | 5 s | **NENHUM precedente**: NUT/apcupsd notificam restauração imediatamente; UniFi nem alerta | **0 s (imediato)**; parâmetro continua existindo para quem quiser histerese |
| Comunicação perdida | 20 s | upsmon **DEADTIME 15 s** [P] | **15 s** |
| Bateria baixa (alerta) | 15% | usbhid-ups fallback `lowbatt` **30%** [P]; EcoFlow reminder fixo 20% [S]; QNAP 15% [P]; apcupsd 5% (shutdown, não alerta) [P] | **30%** (fallback NUT), com nota: no River o corte físico acontece no Discharge Limit do app — alerta deve ficar ACIMA dele |
| Intervalo de leitura | 2 s | ups.conf `pollinterval` **2 s** [P] | **2 s (mantém — agora com fonte)** |
| Retenção de histórico | 7 dias | sem default de mercado (UniFi não tem histórico; HA delega ao recorder) | mantém 7 d marcado PROVISÓRIO-SEM-FONTE |

## 5. Síntese da tabela invertida

Dos 24 parâmetros do universo: **5 já existem** (todos precisando de ajuste de
default ou nota), **4 são candidatos a ADICIONAR** (poll em bateria, limiar por
autonomia, notificação macOS, política de re-aviso), **2 são decisão de produto**
(shutdown do host + tempo de desligamento), **6 são N/A por hardware com fonte**
(controles que o River não aceita via NUT / telemetria que não expõe), e o resto
é lado-do-app ou multi-UPS. Ou seja: o conjunto atual NÃO coincide com o
mercado — é um subconjunto pequeno, e o eixo dominante do mercado (autonomia em
minutos) está ausente.

## NÃO ENCONTRADO (consolidado)
- Dump de River 3 Plus SEM overrides confirmando defaults de charge.low/warning/runtime.low (defaults vêm do código do driver + dump do Delta 3 Plus).
- Default numérico do Safe Shutdown Trigger Point da UniFi; estado default do buzzer; credenciais NUT de fábrica.
- Defaults de haltlevel/haltafter/haltremain do macOS.
- Valor default do "runtime limit" no PowerChute.
- Artigo oficial help.ui.com sobre o UPS UniFi (não existe).
- Doc EcoFlow mencionando NUT (só citam o "EcoFlow Power Manager" proprietário).
