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

## 4. Comparativo: nossos parâmetros × mercado

| Nosso parâmetro | Valor atual (inventado) | Âncora SOTA com fonte | Proposta |
|---|---|---|---|
| Queda de energia (debounce) | 3 s | apcupsd ONBATTERYDELAY **6 s** [P] — único debounce de "on battery" com default documentado | **6 s** |
| Energia restaurada (debounce) | 5 s | **NENHUM precedente**: NUT/apcupsd notificam restauração imediatamente; UniFi nem alerta | **0 s (imediato)**; parâmetro continua existindo para quem quiser histerese |
| Comunicação perdida | 20 s | upsmon **DEADTIME 15 s** [P] | **15 s** |
| Bateria baixa (alerta) | 15% | usbhid-ups fallback `lowbatt` **30%** [P]; EcoFlow reminder fixo 20% [S]; QNAP 15% [P]; apcupsd 5% (shutdown, não alerta) [P] | **30%** (fallback NUT), com nota: no River o corte físico acontece no Discharge Limit do app — alerta deve ficar ACIMA dele |
| Intervalo de leitura | 2 s | ups.conf `pollinterval` **2 s** [P] | **2 s (mantém — agora com fonte)** |
| Retenção de histórico | 7 dias | sem default de mercado (UniFi não tem histórico; HA delega ao recorder) | mantém 7 d marcado PROVISÓRIO-SEM-FONTE |

## 5. Classes de parâmetros que o mercado tem e nós NÃO temos (avaliar com o dono)

1. **Ação de shutdown** (upsmon OB+LB; apcupsd %/min/tempo; UniFi minutos de
   autonomia; Synology standby; pmset). Hoje somos READ_ONLY e não desligamos o
   Mac mini. Decisão de produto pendente.
2. **Auto-recovery/power-cycle** — impossível via NUT no River (upscmd não
   funciona). N/A por hardware.
3. **Buzzer/luz** — idem, não controlável via NUT (só no app EcoFlow). N/A.
4. **Teste de bateria/calibração** — nem a UniFi tem. N/A.
5. **Credenciais/ID do nosso servidor NUT** — a UniFi expõe (ID, porta,
   credenciais); relevante quando o UDR7 entrar (Fase 0/3).

## NÃO ENCONTRADO (consolidado)
- Dump de River 3 Plus SEM overrides confirmando defaults de charge.low/warning/runtime.low (defaults vêm do código do driver + dump do Delta 3 Plus).
- Default numérico do Safe Shutdown Trigger Point da UniFi; estado default do buzzer; credenciais NUT de fábrica.
- Defaults de haltlevel/haltafter/haltremain do macOS.
- Valor default do "runtime limit" no PowerChute.
- Artigo oficial help.ui.com sobre o UPS UniFi (não existe).
- Doc EcoFlow mencionando NUT (só citam o "EcoFlow Power Manager" proprietário).
