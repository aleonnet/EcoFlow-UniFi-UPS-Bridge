# Runbook — Proteção do UDR7 pelo River (Fase 3'-EXP) — 2026-09-01

**Fase experimental separada** (spec §2.5): o daemon, numa queda de energia confirmada e com a
bateria do River cruzando um limiar **acima do corte físico**, faz SSH no console UniFi e roda
`ubnt-systool poweroff`. **Nasce em modo ensaio** e só arma por ato do dono, em 3 passos
(abrir a trava no arquivo → armar no app → fechar a trava). A exceção ao item "executar
destructive command no UDR7" da spec §26 está **PEDIDA e pendente de ratificação do dono**;
até lá o serviço fica em ensaio (`PROTECT_DRY_RUN=1`, `UDR7_ARM_ALLOWED=0`).

Gramática: **[P]** fonte primária · **[S]** secundária · **HIPÓTESE Hnn** (research/hypotheses.md)
· **PROVISÓRIO-SEM-FONTE** · **ANALOGIA** · **INFERIDO**. Nenhum número aqui é palpite sem marca.

## 0. O que a proteção faz — e o que não faz

- **Faz:** em ensaio, registra `UDR7_SHUTDOWN_DRYRUN` no instante em que desligaria (com o
  portão que ainda barraria, `would_block`). Armada, executa **uma** vez por queda:
  `ssh -n -T -F /dev/null -o BatchMode=yes … -o StrictHostKeyChecking=yes
  -o UserKnownHostsFile=<estado>/udr7_known_hosts -i <chave> -p <porta> -- root@<host>
  ubnt-systool poweroff` (argv completo em `protect.ssh_argv`; verificado com `ssh -G`,
  research/findings.md).
- **Não faz:** não religa o console (H13/H14/H16 — ver §5), não desliga o Mac mini
  (BACKLOG B07), não age sem queda confirmada (`POWER_LOSS` do tracker) nem na tomada.
- **Propriedade M1 (verificável por teste e mutação no gate):** só executa quando, no mesmo
  tick, TODAS valem — (1) `driver.name`/`driver.version` presentes e fora da denylist
  `{fake-nut-ups, dummy-ups, dummy, clone, clone-outlet}`; (2) `NUT_HOST` ∈ {127.0.0.1, ::1};
  (3) `device.serial == UDR7_EXPECTED_SERIAL`; (4) `udr7_armed.json` pina a configuração
  corrente; (5) host no `udr7_known_hosts` dedicado; (6) corte e limiar configurados e limiar
  > corte+1; (7) chave 0600 do usuário do serviço; (8) não calibrando; (9) sem desligamento
  pendente de restauração; (10) ensaio desligado. Quem tem o uid do serviço pode tudo — não há
  fronteira de privilégio além do launchd (spec §15, exceção 7).

## 1. Pré-requisitos elétricos e do app EcoFlow

0. **Mac mini e UDR7 ligados na saída AC do River.** Sem isso a política é decorativa.
0b. No app EcoFlow: **AC Timeout = never** [P manual, docs/PESQUISA_PARAMETROS_UPS_20260831.md:45-48]
   e **Output Port Memory ligado** (o manual só nomeia a função; semântica **não encontrada em
   fonte** — parte de H16). Anote o **Discharge Limit** configurado.

## 2. Medir antes de configurar (com o simulador PARADO)

O simulador responde `device.serial: SIM0001` — se estiver rodando, você registraria o serial
errado (o daemon recusa `SIM0001` de propósito: `serial_de_simulador`).

```bash
# no mini, com o River no USB e o NUT real de pé:
upsc <ups>@127.0.0.1 device.serial          # → UDR7_EXPECTED_SERIAL (H15)
upsc <ups>@127.0.0.1 battery.charge.low     # Discharge Limit visto pelo driver (só informativo)
upsc <ups>@127.0.0.1 battery.runtime        # anote a UNIDADE (segundos? minutos?) — PESQUISA_PARAMETROS:24-25
```

- **Corte real (H17):** a pesquisa tem dois [P] contraditórios (corte em Limite+1 % ×
  descarga até 0 %). Meça: com uma carga conhecida (lâmpada), deixe descarregar e anote o `%`
  em que a saída AC cai → `UDR7_CUTOFF_PERCENT`.
- **Taxa de descarga com a carga real** (mini + UDR7): anote quantos segundos leva 1 % →
  `UDR7_DISCHARGE_SECONDS_PER_PCT`. A Saúde mostra `margin_estimate_s` = (limiar − corte) ×
  taxa; a política avisa `margin_short` se for menor que confirmação + 4 tentativas × 20 s +
  30 s de halt (30 s = PROVISÓRIO-SEM-FONTE) — **aviso, não bloqueio** (a medição envelhece).
- **Limiar:** `UDR7_SHUTDOWN_PERCENT ≥ corte + 2` (+2 = PROVISÓRIO; o daemon bloqueia ≤ corte+1
  com `limiar_abaixo_do_corte`). Confira `margin_estimate_s` na Saúde **antes** do passo 6.
- `UDR7_RUNTIME_MINUTES` fica **0** (eixo desligado) até você confirmar a unidade de
  `battery.runtime`; o valor sugerido depois é 3 min (apcupsd `MINUTES` [P]).
- Se o corte medido for > 48, a faixa da chave (0..48, PROVISÓRIO) precisa ser reaberta no
  código antes de armar — não invente um valor menor.

## 3. Chave SSH dedicada (nunca a chave pessoal)

```bash
# como o usuário do serviço (é a sua conta; o .env é 0600 dela — scripts/install.sh):
ssh-keygen -t ed25519 -f /Users/<svc>/.ssh/river-bridge-udr7 -C river-bridge-udr7
chmod 600 /Users/<svc>/.ssh/river-bridge-udr7
```
`UDR7_SSH_KEY` exige caminho **absoluto** (sem `~`). Chave de arquivo em vez de Keychain: é o
único formato que o `ssh` do sistema consome em `BatchMode` sob launchd (spec §15, exceção 4).

## 4. Habilitar SSH no UniFi OS, instalar a pública e semear o known_hosts

1. UniFi OS → Console Settings → SSH: habilitar (caminho da UI a confirmar no ato; anote a
   versão do UniFi OS).
2. Instalar a pública em `root@<UDR7>` (`~/.ssh/authorized_keys`). **H11b**: login por chave
   para `root` funciona e persiste? (o gist da comunidade usa senha).
3. Semear o known_hosts dedicado — **este é o único primeiro contato com `accept-new`; o
   daemon usa `StrictHostKeyChecking=yes`**:
   ```bash
   STATE="/Users/<svc>/Library/Application Support/river-unifi-bridge"
   ssh -o UserKnownHostsFile="$STATE/udr7_known_hosts" -o StrictHostKeyChecking=accept-new \
       -i /Users/<svc>/.ssh/river-bridge-udr7 -p 22 root@<UDR7> 'command -v ubnt-systool; uname -a'
   chmod 600 "$STATE/udr7_known_hosts"
   ```
   Anote o fingerprint aceito. `command -v ubnt-systool` responde **H11a** (o comando existe no
   UDR7). Se a porta não for 22, o daemon procura a entrada na forma `[host]:porta`.

## 5. Medir o religamento antes de armar (H13 / H14 / H16)

Após um `poweroff` há dois cenários, complementares:
- **(a) a rede volta depois de o River cortar a saída** → o console ficou sem energia →
  religa se **H13** (boota ao receber energia) **e H16** (o River reenergiza a saída sozinho
  após corte por Discharge Limit) forem verdadeiras.
- **(b) a rede volta antes do corte** → console parado **com** energia → só **H14**
  (Wake-on-LAN) ou à mão. Nenhuma fonte confirma WoL como alvo em consoles UniFi.

Medições (com o console em horário tolerável):
- H13: `ssh … root@<UDR7> 'ubnt-systool poweroff'` à mão → cortar e devolver a energia do
  console → cronometrar o boot.
- H16: deixar o River cortar por Discharge Limit com a rede desligada → religar a rede →
  a saída AC volta sozinha?
- H14: com `UDR7_WOL_MAC` configurado, o ensaio registra `UDR7_WOL_DRYRUN` (o que seria
  enviado: magic packet `FF×6 + MAC×16`, UDP 9, broadcast). Envie um à mão
  (`python3 -c 'import socket;…'` ou qualquer ferramenta WoL) com o console parado e veja se
  acorda.

**Regra:** desligar o modo ensaio só depois de **H13 ou H14** medida verdadeira. Se ambas
falsas, o caminho de base é **religar à mão** — decisão sua, registrada em
research/hypotheses.md. Ambas falsas e você aceitando religar à mão também é uma decisão
válida; escreva-a.

## 6. Armar (3 passos) e desarmar

6. Abrir a trava: no `.env` do serviço (`/usr/local/river-unifi-bridge/etc/bridge.env`, 0600
   da sua conta) `UDR7_ARM_ALLOWED=1` → `sudo launchctl kickstart -k system/com.river.unifi-bridge`.
   A Saúde passa a avisar `lock_open`.
7. No app → Ajustes → Proteção do UDR7: preencher host, porta, usuário, chave, serial, corte,
   limiar, taxa; **Salvar proteção**; conferir na Saúde `armado_nao_verificado` só depois do
   passo seguinte. **Desligar modo ensaio…** (confirmação). O serviço só aceita se: trava
   aberta, leitura corrente do River **registrado** (serial) e fonte não sintética
   (`409 armamento_bloqueado` / `sem_snapshot` / `fonte_nao_real` explicam a recusa). Ao
   armar, grava `udr7_armed.json` (pinos de toda a configuração) e emite `UDR7_ARMED`.
8. **Fechar a trava:** `UDR7_ARM_ALLOWED=0` no `.env` → `sudo launchctl kickstart -k
   system/com.river.unifi-bridge`. A Saúde para de avisar `lock_open`. (Com a proteção armada
   o `POST /v1/service/restart` responde `409 armado` — por isso o kickstart.)

- **Desarmar:** "Ligar modo ensaio" no app — **sempre aceito**, mesmo com a trava fechada
  (remove `udr7_armed.json`, emite `UDR7_DISARMED`). Enquanto armado, as demais chaves
  `PROTECT_*`/`UDR7_*`/`NUT_*` e o reinício pela API ficam congelados (`409 armado`).
- **Rearmar** exige a trava aberta de novo (passos 6–8).

## 7. Operação, recuperação e desinstalação

- Saúde `udr7` (enum fechado, docs/API_LOCAL_20260831.md): `dry_run` · `armado_nao_verificado`
  (o daemon não prova alcance — não há probe) · `enviado` · portões `fonte_nao_real`,
  `fonte_nao_local`, `corte_nao_configurado`, `limiar_nao_configurado`,
  `limiar_abaixo_do_corte`, `config_incompleta`, `chave_insegura`, `host_desconhecido`,
  `calibrando`, `armamento_ausente`, `config_trocada`, `aguardando_restauracao`.
- `armamento_ausente` (ex.: `.env` editado à mão para `PROTECT_DRY_RUN=0` e reiniciado):
  ligue o modo ensaio pelo app, abra a trava, arme pelo app, feche a trava.
- `config_trocada`: alguma chave pinada mudou fora do fluxo (arquivo à mão). Desarme e arme de
  novo.
- `aguardando_restauracao`: houve um `SENT` e o daemon ainda não viu energia voltar
  (`udr7_runtime.json`); limpa no primeiro `ONLINE`.
- **Firmware update do UniFi OS** (H12a/H12b): pode apagar `authorized_keys` e/ou trocar a
  host key. Sintoma: `UDR7_SHUTDOWN_FAILED` com `host_key_mudou`/`host_desconhecido`. Refaça o
  passo 4 (apague a linha antiga do `udr7_known_hosts` antes de semear).
- **Desinstalar:** `scripts/uninstall.sh` **avisa** e não remove (não criou): apague à mão
  `udr7_known_hosts`, `udr7_armed.json`, `udr7_runtime.json` no diretório de estado, a chave
  privada e **a pública no console** (`authorized_keys` do `root`). O `.env` é preservado pelo
  instalador — se estiver armado, desarme antes de reinstalar.

## 8. Chaves (spec §22 bloco 6) — defaults e fontes

| Chave | Default | Fonte / marca |
|---|---|---|
| PROTECT_UDR7 | 0 | nasce desligada |
| PROTECT_DRY_RUN | 1 | cerca M1 |
| UDR7_ARM_ALLOWED | 0 | trava; somente arquivo |
| UDR7_SSH_HOST | vazio | alvo do poweroff; regex sem `_`/IPv6 (decisão) |
| UDR7_SSH_PORT | 22 | ssh_config(5) "Port … The default is 22" |
| UDR7_SSH_USER | root | [S] gist Freekers (UDM Pro) — H11a; 32 caracteres = PROVISÓRIO (useradd(8) diz 256) |
| UDR7_SSH_KEY | vazio | caminho absoluto |
| UDR7_EXPECTED_SERIAL | vazio | medido (H15); `SIM0001` recusado |
| UDR7_CUTOFF_PERCENT | 0 = não configurado | medido (H17); faixa 0..48 PROVISÓRIO |
| UDR7_SHUTDOWN_PERCENT | 0 = não configurado | sem default por desenho; ≥ corte+2 |
| UDR7_DISCHARGE_SECONDS_PER_PCT | 0 = desconhecido | medido |
| UDR7_RUNTIME_MINUTES | 0 = eixo desligado | após confirmar unidade; 3 = apcupsd MINUTES [P] |
| UDR7_MIN_OUTAGE_SECONDS | 0 | cada segundo custa margem; anti-blip é a confirmação |
| UDR7_CONFIRM_SECONDS | 6 | ANALOGIA apcupsd ONBATTERYDELAY [P] |
| UDR7_RETRY_MAX | 3 | PROVISÓRIO; 1 tentativa por tick, ≤ 20 s cada (ANALOGIA upsmon HOSTSYNC 15 + FINALDELAY 5) |
| UDR7_WOL_MAC | vazio | H14; só envia após um `SENT` (ensaio: `UDR7_WOL_DRYRUN`) |

Seam de teste declarado: `RUB_SSH_BINARY` (env do processo) aponta o binário `ssh`; o plist
do LaunchDaemon não o define, o valor efetivo aparece em `udr7_detail.ssh_binary` e é pinado
ao armar (spec §15, exceção 6).

## 9. Estado em 2026-09-01 (fim da execução em modo madrugada)

- Código: P0–P10 executados e commitados (gate `tools/gate.sh` VERDE, 21 cenas, 164 testes
  Python + 20 Swift; E2E prova DRYRUN com o simulador, 409 ao tentar armar com fonte sintética,
  e `SENT` 1× contra um stub de `ssh` com fonte real-parecida). Nada foi enviado a nenhum
  console: o único `ssh` executado em teste é `ssh -G` (não conecta).
- MacBook: daemon local em ensaio (`scratchpad/demo.env`) + simulador `apagao` → `DRYRUN`
  ↔ `REARMED` a cada 140 s; capturas focadas de Saúde/Ajustes/Energia validadas.
- Mac mini (`macmini.home.arpa`): simulador religado em `apagao` (python 3.13, porta 3493);
  `~/Applications/River Bridge.app` atualizado; árvore do repo em `~/river-bridge-deploy/`
  com `pos-install-fase3exp.sh`. **O daemon instalado ainda é o anterior** — o código em
  `/usr/local/river-unifi-bridge` é root:wheel e `sudo` pede senha. Para instalar (dono), em
  UMA linha, senha uma vez (instalador da casa — docs/INSTALACAO_UMA_LINHA_20260901.md):
  ```bash
  ssh macmini.home.arpa
  ~/river-bridge-deploy/river-bridge-install.sh --src ~/river-bridge-deploy   # serviço + app + kickstart
  ~/river-bridge-deploy/pos-install-fase3exp.sh      # liga a proteção EM ENSAIO (PUT)
  ```
  (a forma remota `curl … | bash` só funciona quando o repositório estiver público — hoje é privado.)
  Depois: `DRYRUN ↔ REARMED` a cada ciclo do `apagao`, Saúde `udr7 = fonte_nao_real`,
  `dry_run = true`, `unifi = sem_caminho_nativo_documentado`. Nada armado: `PROTECT_DRY_RUN=1`,
  `UDR7_ARM_ALLOWED=0`.
- Pendente do dono: ratificar (ou não) a exceção à §26; decidir religamento (H13/H14/H16);
  quando o River chegar, seguir §2–§6 deste runbook.
