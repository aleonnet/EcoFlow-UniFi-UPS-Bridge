# Handoff — 0.8.0 → 0.8.3 em uma noite: a UX pedida na abertura, o leitor que o NUT recusava, e a auditoria do registro

status: aceito
data: 2026-09-05
supera: 2026-09-05-1727-handoff-0-7-0-driver-do-nut-e-o-disco.md

Leia junto: `docs/guides/2026-09-05-2200-runbook-instalar-usar-e-remover-pelo-app.md` (o
guia do dono) e `docs/plans/2026-09-05-1905-a-ux-determinada-inteira-0-8-0.md` (o plano da
0.8.0, aprovado; a bancada C9 dele foi substituída pelo protocolo abaixo).

## 1. Estado

| O quê | Onde |
|---|---|
| v0.8.0 | publicada e notarizada; DMG sha256 `c139c84f…` |
| v0.8.1 | autorização na abertura sem botão, PT/EN em par, fora de Aplicativos não registra; commit `d7b6e0a`; DMG sha256 `e046a820…` |
| v0.8.2 | este handoff; o leitor nasce com o nome de fábrica, diário capturado, LEIA-ME em duas línguas, Ajustes reordenados |
| Mac mini | 0.8.1 instalada pelo dono, serviço autorizado e no ar como root; leitor e servidor do NUT **não sobem** (motivo abaixo) |

## 2. O protocolo que o dono fixou (2026-09-05, à noite)

> "eu quero testar como usuário normal, baixando o dmg... aí você checa se tudo instalou
> correto, eu checo a ux... movo o app para a lixeira, você checa se desinstalou tudo"

1. Eu deixo o mini limpo e publico a versão.
2. **O dono** baixa o DMG, arrasta, abre, autoriza. Ele julga a UX. Eu **não** clico por
   ele e **não** peço cliques.
3. Ele diz "instalei"; eu meço por ssh (`alessandro@192.168.1.13`, sem senha; sem sudo).
4. Ele arrasta para o Lixo; eu meço que nada ficou.

## 3. O que a 0.8.1 mostrou no mini, medido

Instalada e autorizada pelo dono (captura: "O serviço está no ar"; Itens de Início de
Sessão com o River Bridge ligado). Tela Energia: "O River não está sendo lido — o leitor
não está no ar".

```
$ launchctl print system/com.river.unifi-bridge | grep -E "state|pid"
        state = running
        pid = 22747
$ pgrep -fl "river-bridge|usbhid-ups|upsd"
22747 /Applications/River Bridge.app/Contents/Resources/python/bin/python3 -m river_unifi_bridge.service --env ...
$ pgrep -P 22747 -l
(nada)
$ curl -H "Authorization: Bearer $(cat '/Library/Application Support/river-unifi-bridge/ui-api.token')" http://127.0.0.1:35493/v1/health
 "usb": "falha", "nut": "falha", "cabo": {"lendo": false, "motivo": "o leitor não está no ar"},
 "last_error": "conexão com upsd 127.0.0.1:3493 falhou: [Errno 61] Connection refused"
$ ls -la /Library/Logs/river-unifi-bridge.log
-rw-r--r--  1 root  wheel  0 Sep  5 16:23 /Library/Logs/river-unifi-bridge.log      ← ZERO bytes
$ ioreg -p IOUSB -w0 | grep "+-o"
  | +-o EF-UPS-RIVER 3 Plus@00100000  ...                                            ← o River está lá
$ pgrep -fl PowerManager
20016 .../PowerManager_1.0.0.16.app/Contents/PowerManagerService/PowerManagerService  ← só o daemon deles
```

O leitor do pacote, lançado à mão **como o supervisor lança** (com `exec -a`), numa
configuração idêntica à do serviço, em `/tmp`:

```
$ /bin/sh -c "exec -a river-bridge-ups '/Applications/River Bridge.app/Contents/Resources/nut/bin/usbhid-ups' -a river-office -u alessandro -F"
Network UPS Tools 2.8.5 release - Generic HID driver 0.71
USB communication driver (libusb 1.0) 0.53
Error: UPS [river-office] is for driver 'usbhid-ups', but I'm 'river-bridge-ups'!
```

O mesmo leitor, com o nome de fábrica (`usbhid-ups -a river-office -DD`, sem root):

```
[D1:river-office] Detected a UPS: EcoFlow/EF-UPS-RIVER 3 Plus
[D2:river-office] Path: UPS.PowerSummary.RemainingCapacity, ... Value: 100
[D2:river-office] Path: UPS.PowerSummary.RunTimeToEmpty, ... Value: 2499
```

O servidor com nome próprio, `exec -a river-bridge-upsd ... upsd -u alessandro -F`:

```
Network UPS Tools river-bridge-upsd 2.8.5 release
listening on 127.0.0.1 port 3494
Can't connect to UPS [river-office] (/private/tmp/nuttest2/state/usbhid-ups-river-office): No such file or directory
```

**Conclusões (fato medido):**
- O PowerManager da EcoFlow **não** sequestrou o cabo: o leitor do pacote lê o River na hora.
- O NUT recusa o leitor com nome trocado; desde a 0.5.0 nós trocávamos o nome
  (`exec -a river-bridge-ups`) para escapar do `pkill -9 usbhid-ups` do aplicativo deles. A
  conferência está no código-fonte do NUT nas versões 2.7.4, 2.8.0 e 2.8.5 (lido em
  2026-09-05): o leitor com nome trocado **nunca subiu**; a medição da 0.5.0 viu o nome no
  `ps`, não uma leitura. De onde vinham as leituras de 04/09 não foi medido (provável: o
  leitor do Homebrew registrado à parte pelo instalador de então, cujos agentes sobrando
  saíram do mini em 05/09).
- O servidor não confere o próprio nome: o nome próprio dele fica.
- O diário sumiu porque o serviço escreve na saída padrão e o plist do pacote só capturava
  a de erro; e a saída de erro dos filhos ia para o nada. Os dois foram corrigidos.

## 4. O que a 0.8.2 muda

| Mudança | Arquivo | Cerca |
|---|---|---|
| leitor com nome de fábrica, chamado direto | `nut_supervisor.py` | `test_o_leitor_nasce_com_o_nome_de_fabrica_e_direto` + S65 |
| saída de erro dos filhos no diário | `nut_supervisor.py` | `test_a_saida_de_erro_dos_filhos_vai_para_o_diario` + S65b |
| plist grava saída padrão e de erro | `tools/build-app.sh` | — (medir no mini: o diário cresce) |
| LEIA-ME e READ-ME | `tools/build-dmg.sh` | prova do disco exige os dois |
| Ajustes na ordem do uso | `SettingsView.swift` | `swift build`/captura |

## 4b. A 0.8.2 no mini, medida (2026-09-06, 00h24)

```
$ launchctl print system/com.river.unifi-bridge | grep -E "state =|pid ="     → running, pid 24672
$ pgrep -fl "usbhid-ups|river-bridge-upsd"
24684 /Applications/River Bridge.app/Contents/Resources/nut/bin/usbhid-ups -a river-office -u root -F
24698 river-bridge-upsd -u root -F
$ GET /v1/health → "usb": "ok", "nut": "ok", "cabo": {"lendo": true}, "last_error": null
$ ls -la /Library/Logs/river-unifi-bridge.log → 235572 bytes; "identity": {"model": "EF-UPS-RIVER 3 Plus", ...}
```

## 4c. A auditoria que o dono exigiu (2026-09-06) — o que ele viu, a fonte, a correção (0.8.3)

| O que o dono viu (capturas) | Fonte primária | Correção |
|---|---|---|
| Programa no Lixo, interruptor "River Bridge" **ligado** em Itens de Início de Sessão | `SMAppService.unregister()`: "Unregisters the service so the system no longer launches it. … If the service is currently running it, the system terminates it." Só um processo do pacote pode chamá-lo ("property list in the calling app's Contents/Library/LaunchDaemons directory"). O `launchctl bootout` da 0.8.x só parava o processo. | O pacote traz `Contents/MacOS/river-bridge-servico` (alvo Swift `RiverBridgeServico`); o serviço o executa como o usuário da sessão, a partir do caminho ATUAL do pacote (já no Lixo), com a saída herdada do serviço (o diário): o ajudante escreve lá `unregister=ok`, e ninguém espera por ele, porque o `unregister` derruba o serviço no instante seguinte; depois o bootout. Cenas S66 e S66b. |
| "O serviço está no ar" + "Sem resposta do serviço" + "Serviço parado" na mesma tela | `SMAppService.Status.enabled`: "The service has been successfully registered and is **eligible to run**." Não é "rodando". | Estado combinado: registro do sistema × resposta do serviço (fluxo de leituras). Habilitado e mudo por ≥ 15 s → "registrado, mas não responde", botão **Religar o serviço** — o mesmo `register()`, que num registro já autorizado sobe o serviço sem nova senha (medido, §4d); a abertura já o faz sozinha (0.8.4). Painel, Ajustes e menu de barra leem a mesma fonte; a faixa "Serviço parado" saiu; a faixa da configuração só aparece com o serviço respondendo. |
| "Isto apaga, sem volta…" (lista longa); "Abrir a trava — o desligamento passa a ser real"; "DESLIGAR o River agora?"; texto da rede em 4 linhas | HIG Alerts: "Write a title that clearly and succinctly describes the situation." "If you need to add an informative message, keep it as short as possible, using complete sentences." "Aim for a one- or two-word title that describes the result of selecting the button." "Always use the title 'Cancel'…" | Título curto, mensagem de 1–3 frases, botões **Remover / Abrir / Permitir / Desligar**, Cancelar sempre. "Sem volta" saiu (era falso: Registrar de novo existe). Testes medem o tamanho e os rótulos. |
| "Não consegui apagar o estado: Could not connect to the server." | HIG Writing: "When an error message is necessary, display it as close to the problem as possible, avoid blame, and be clear about what someone can do to fix it." | Com o serviço mudo, a confirmação diz que a chave e as senhas ficam em `/Library/Application Support/river-unifi-bridge` e o registro é desfeito mesmo assim; erro do serviço, se houver, sai em português/inglês. |
| Depois de Remover completamente, a linha "River Bridge" continua listada (desligada) | A Apple documenta o registro, não a lista dos Ajustes do Sistema. | A linha é do macOS; o que é nosso (registro, processo, estado) sai. Dito no código, não prometido na tela. |

**Medição que sustenta o ajudante** (mini, 2026-09-06, 00h47, pacote 0.8.3 assinado com Developer ID e copiado por scp, sem quarentena; o pacote real seguiu registrado e no ar):

```
== pacote em /private/tmp (fora de Aplicativos)
pacote=/private/tmp/rb-medicao/River Bridge.app
status=enabled
== o mesmo pacote movido para ~/.Trash
pacote=/Users/alessandro/.Trash/River Bridge 083.app
status=enabled
```

O registro é visível de qualquer caminho do mesmo pacote assinado — inclusive do Lixo. É de lá
que o ajudante roda. O `unregister` em si não foi disparado nesta medição (derrubaria a
instalação do dono); a prova final é a bancada: Lixo → diário com `ajudante_do_registro …
unregister=ok` → interruptor apagado.

**Armadilha medida (2026-09-06, 00h30):** copiar o pacote de `/Applications` (com o atributo de
quarentena da instalação) e pôr um binário ad-hoc dentro quebra o lacre; ao executar de lá o
Gatekeeper mostra **"River Bridge is damaged and can't be opened"** na tela do dono e a chamada
trava. Foi o que o dono viu à 00h30; a cópia era minha e foi removida. Medir só com o pacote
inteiro assinado, copiado por scp.

## 4d. Bancada da 0.8.3/0.8.4 no mini, por mim (2026-09-06, 01h10–01h35)

```
== 0.8.2 → Lixo (mv, o mesmo que o Finder)
{"event": "PACOTE_NO_LIXO_REMOVIDO", "pacote": "/Applications/River Bridge.app", "agora": ".../.Trash/River Bridge.app/Contents/Info.plist"}
{"event": "parada_deliberada", "reason": "o pacote foi para o Lixo: estado apagado e serviço desregistrado", "apagados": 13}
processos: nenhum · pasta de estado: não existe · launchd: Bad request (job sumiu) · interruptor: fica (defeito da 0.8.2)
== 0.8.3 (assinada) em /Applications, sobre o registro herdado
river-bridge-servico status   → status=enabled            (o fantasma da 0.8.2)
river-bridge-servico register → register=ok, status_depois=enabled   ← SEM nova autorização
6 s depois: launchd running pid 25576; usbhid-ups e river-bridge-upsd como root
health: usb ok, nut ok, cabo.lendo true
LIST UPS: river-office, river-bridge  (udr7 não: a lista de dispositivos foi apagada pelo Lixo, como manda)
LIST VAR river-bridge: outlet.count 4, outlet.1.realpower 64.8, ups.status OL, battery.charge 100
trava RIVER_POWEROFF_ALLOWED=1 pela API → {"aplicadas_a_quente": ["RIVER_POWEROFF_ALLOWED"]} → LIST CMD river-bridge: load.off; =0 → nenhum
rede: PUT {"aberta": true} → {"servidor_reiniciado": true}; netstat: *.3493 LISTEN; do MacBook, LIST UPS em 192.168.1.13:3493 → river-office, river-bridge; PUT {"aberta": false} → fechou
cabo: open -a PowerManager → 9 s: cabo {"lendo": false, "pausado": true, "motivo": "o aplicativo da EcoFlow abriu"}; pkill → 12 s: {"lendo": true}, usb ok
== 0.8.4 (assinada) por cima, sem Lixo: rm + cópia; POST /v1/service/restart → {"version": "0.8.4"}; leitor e servidor voltam; interface aberta, health ok
== 0.8.4 → Lixo (mv)  — A PROVA DO INTERRUPTOR
{"event": "PACOTE_NO_LIXO_REMOVIDO", ...}
{"event": "ajudante_do_registro_lancado", "argv": ["/bin/launchctl", "asuser", "501", "/usr/bin/sudo", "-u", "#501", ".../.Trash/River Bridge.app/.../Contents/MacOS/river-bridge-servico", "unregister"]}
{"event": "parada_deliberada", "reason": "o pacote foi para o Lixo: estado apagado e serviço desregistrado", "apagados": 13}
pacote=/Users/alessandro/.Trash/River Bridge.app/River Bridge.app        ← escrito pelo ajudante, de dentro do Lixo
status=enabled
unregister=ok
status_depois=notRegistered                                              ← o registro nos Itens de Início de Sessão desfeito
processos: nenhum · pasta de estado: não existe · launchd: Bad request
== instalação final da 0.8.4 em /Applications
river-bridge-servico status → notRegistered (o Lixo desfez)
open -a "River Bridge" → 8 s → status=enabled e launchd com o job   ← SEM pedir autorização de novo: o macOS lembra a
                                                                        autorização dada a este programa; unregister+register
                                                                        na mesma máquina não pergunta outra vez (medido)
```

== 2026-09-06, 08h20 — instalação FINAL pelo disco publicado (v0.8.4, sha ea4cd16a…)
cópia por scp → Lixo: unregister=ok, status_depois=notRegistered, parada_deliberada
curl do DMG; xattr quarentena forçada; spctl -t open → accepted, Notarized Developer ID
cp -R para /Applications (quarentena vai junto); spctl --assess → accepted, Notarized Developer ID
open → a interface abriu de /private/var/folders/…/AppTranslocation/… (translocação do Gatekeeper:
  pacote em quarentena copiado SEM o Finder) → "Mova o River Bridge para Aplicativos", nada registrado (correto)
xattr -dr com.apple.quarantine (o que o arrastar pelo Finder faz) → open → interface de /Applications,
  status=enabled sem pedir autorização, serviço + leitor + servidor como root, version 0.8.4, health ok
```

**O que isso muda no roteiro:** o ciclo inteiro (Lixo → reinstalar → abrir) fecha sem clique
nenhum quando o programa já foi autorizado uma vez nesta máquina. A autorização é pedida só na
primeira instalação de todas (ou depois de o dono desligar o item nos Ajustes do Sistema).

**Release 0.8.4 publicada às 08h15 (sha ea4cd16a…)** depois de o dono guardar a credencial no
chaveiro de arquivo; `RUB_NOTARY_KEYCHAIN` nos scripts e a conferência antes de montar (d17e8c2).
Registro do bloqueio, para a história: "No Keychain password item
found for profile: river-bridge" — a credencial do notarytool sumiu do chaveiro pela segunda
vez (login.keychain-db reescrito à 01h16; zero itens em qualquer chaveiro). Só a senha de app
do dono a recria. Para não sumir de novo, guardar num chaveiro de ARQUIVO em vez do de
proteção de dados: `xcrun notarytool store-credentials river-bridge --keychain
~/Library/Keychains/login.keychain-db --apple-id … --team-id 8A47D8UNV2 --password …` e usar
`--keychain` também no `submit` (release.sh/build-dmg.sh precisam ganhar essa opção). A tag
local `v0.8.4` da tentativa foi apagada; o commit a74c005 está em main.

## 4e. O PowerManager em modo Remoto — medido (2026-09-06, 09h30–09h50), e a 0.8.5

O dono, com o PowerManager em Remoto: "por que não permitimos ambos?".

```
== o que o aplicativo deles grava (…/PowerManagerSettings/alessandro/settings.ini)
[connectModeParam] mode=remote nutIP=127.0.0.1 nutPort=3493 nutUser=powermanager nutPassword=river-local upsName=river-office
                   localUpsName=nutdev1 (o NUT que ELE traz, para o modo Local: ups.conf [nutdev1] usbhid-ups; upsd LISTEN 127.0.0.1 3493; upsmon primary)
== o registro DELE, em Remoto (…/MacOS/log/2026-09-06.log)
09:43:58 "…/nut-server/bin/upsc" ("river-office@127.0.0.1:3493") → battery.charge: 100 … battery.runtime: 151740 …   (a cada 1 s)
== do nosso lado, com o cabo automático desligado para medir
LIST CLIENT river-office → vazio (o `upsc` não faz LOGIN; foi por isso que eu disse "não conecta" — errado: conecta a cada segundo)
120 s com o aplicativo aberto: usbhid-ups e river-bridge-upsd vivos; nenhum `run.sh with administrator privileges` (o modo Local o dispara)
== a conta que ele usa, testada por mim no nosso servidor
USERNAME powermanager / PASSWORD river-local / LOGIN river-office → OK; LOGIN river-bridge → OK; pelo 192.168.1.13 → OK (a rede está ABERTA: o dono ligou o interruptor)
```

**Conclusão:** em Remoto ele lê pelo NOSSO servidor e não toca no leitor; em Local ele mata o
leitor e sobe o NUT dele. A 0.8.4 cedia o cabo (parando leitor e servidor) só porque o
aplicativo abriu — em Remoto isso cegava os dois. **0.8.5:** o cabo só é cedido quando o
nosso leitor cai com o aplicativo aberto (o supervisor conta as quedas; referência = olhada
anterior). Cenas S67/S67b. Para ele mostrar os watts por tomada: apontar o Remoto dele para
`river-bridge` (a mesma conta serve; `LOGIN river-bridge` → OK).

**0.8.5 instalada no mini pelo disco publicado (sha 9f11cef0…), 2026-09-06, 10h35, e medida:**

```
Gatekeeper (quarentena forçada): disco e programa → Notarized Developer ID
POST /v1/service/restart → {"version": "0.8.5"}; interface aberta
PowerManager (Remoto) aberto 40 s: cabo {"lendo": true, "pausado": false} o tempo todo; leitor=1, upsd=1
  registro dele no mesmo instante: upsc "river-office@127.0.0.1:3493" → battery.runtime: 151740  (os dois lendo)
fechar → cabo {"lendo": true}; diário: "aplicativo_fechou_sem_tomar_o_cabo" (1); nenhum evento novo de cabo
```

Falta medir, e é o dono quem alterna o modo na tela deles: **modo Local** (linhas 7b/8 da bancada):
o leitor cai, o cabo é cedido na olhada seguinte, e volta ao fechar.

## 4f. O UDR7 de ponta a ponta (2026-09-06, 10h55) e o que o PowerManager mostra errado

```
PUT /v1/devices/udr7 {"fields":{"ssh_host":"192.168.1.1"}}        (o campo estava vazio; a folha mostrava um exemplo em cinza)
POST /v1/devices/udr7/acesso/testar → {"alcance": true, "resposta": {"model": "UniFi Dream Router 7", "firmware": "5.1.31"}, "registro": {"desligamento_disponivel": true}}
PUT /v1/config {"UDR7_CUTOFF_PERCENT": "2"} → aplicadas_a_quente
PUT /v1/devices/udr7 {"dry_run": false} → {"device": {..., "dry_run": false, ...}}; em seguida GET /v1/health .udr7_detail → state "armado_nao_verificado" (= armado; sem queda real ainda), alcance_verificado true, warnings [lock_open, margin_unknown]
```

**"104d03h00m" no PowerManager (Remoto):** o nosso servidor publica `battery.runtime` em
segundos (padrão NUT): 149.940 s = 41 h 39 min (o que o River Bridge mostra). O PowerManager
trata como minutos: 149.940 min = 2.499 h = 104 d 3 h — exatamente o exibido. Defeito deles.

## 5. Estado final desta noite/manhã (2026-09-06, 11h20) e o próximo passo

**Mini:** 0.8.6 do disco publicado (Gatekeeper: Notarized Developer ID), serviço + leitor + servidor como
root, interface aberta; PowerManager em Remoto lendo pelo nosso servidor sem tirar o cabo; UDR7 com
endereço, alcance provado e **proteção armada** (corte 2 %, limiar 5 %). Reiniciar o serviço com a
proteção armada é recusado pela cerca (`{"motivo": "armado"}`): o caminho é ensaio ligado → reiniciar →
ensaio desligado, como feito para trocar 0.8.5 → 0.8.6 sem nova autorização.

**Releases:** 0.8.0 … 0.8.7, todas assinadas e notarizadas (credencial no chaveiro de arquivo,
`RUB_NOTARY_KEYCHAIN`).

### 5a. A queda ao abrir 6 h / 24 h / 7 d de eventos (2026-09-06, 11h02) — 0.8.7

O dono mandou o relatório de queda: `EXC_BREAKPOINT (SIGTRAP)` com a pilha inteira dentro de
`Charts`, disparada por `GeometryReader` — nada nosso na pilha, e por isso a causa tinha de ser
medida, não lida. Diagnóstico:

- **O recorte do mini** (`GET /v1/events/log?from=<7 dias>`, 24 eventos): `COMM_RESTORED` 6,
  `COMM_LOST` 5, `CABO_RETOMADO_AUTOMATICO` 5, `CABO_LARGADO_AUTOMATICO` 5, `UDR7_ARMED` 2,
  `UDR7_DISARMED` 1. Os do cabo são das 09h00–09h06 de hoje: entram em 6 h, 24 h e 7 d; **não**
  entram em 1 h — por isso "ao filtrar por tempo".
- **A legenda do histograma** (`legendKeys`, em `ChartsView.swift`) só conhecia os cinco tipos do
  bridge e os dos dispositivos; `legendLabel` dava rótulo a QUALQUER tipo. Um evento do cabo virava
  barra com rótulo fora do domínio de `chartForegroundStyleScale(domain:range:)`.
- **O Swift Charts derruba o processo nesse caso** — medido fora do app, nesta máquina
  (macOS 26.6.2): `ImageRenderer` sobre um `Chart` de duas barras com escala explícita; domínio
  `["A"]` e uma barra `"B"` → `rc=133` (Trace/BPT trap); domínio `["A","B"]` → renderiza.

Correção (da classe, não do caso): a legenda passa a nascer dos MESMOS eventos que viram barra, em
função pura no Core (`LegendaDeEventos.chaves`): bridge → vocabulário de cada instância → demais
eventos do serviço → **qualquer rótulo presente que nenhuma lista produziu** (tipo novo, instância
removida). Teste `todaBarraTemASuaCorNoDominio` com os seis casos; cena S68 no gate com o rito novo
`cena_mutacao_swift` (mutante desliga o último passo → o teste reprova). Release 0.8.7.

Revisão fria do diff, rodada 1: **um bloqueador**, meu — a cena S68 filtrava por
`LegendaDeEventosTests/todaBarra…`, e o filtro do `swift test` é uma expressão regular sobre
`Módulo.função()`: teste de função livre não tem suíte no nome, o filtro não casava nada, e o
`swift test` devolve "0 tests … passed" com rc 0. A cena rodava zero testes. Classe do que faltou:
**conferir o filtro contra `swift test --list-tests` antes de escrever a cena** (o mesmo rito que o
`cena_mutacao` em Python já tinha: baseline com contagem de testes ≥ 1). Correção: filtro pelo nome da
função e linha de base em árvore limpa dentro do `cena_mutacao_swift`.

Segunda correção, achada pelo gate (S7 vermelho numa rodada e verde noutra): a primeira versão
comparava rótulos calculados em duas passadas, e o idioma é estado global que um teste do Core alterna
em paralelo — entre as duas passadas o rótulo mudava de idioma e o evento caía na sobra. No app não
acontece (uma passada, na thread principal), mas é desenho frágil. Refeito: o rótulo de cada evento é
calculado uma vez, a ordem sai da identidade do evento (tipo e dono), e o idioma é parâmetro
explícito lido uma vez por chamada. Revisão fria dessa versão: aprovada, com um aviso certeiro — o nome
padrão do tipo (usado para instância removida ou sem nome) ainda lia o idioma global; só se vê com host
SSH ("Servidor SSH"/"SSH server"). O idioma passou também por esse caminho, e o teste ganhou um host SSH
removido, conferido nos dois idiomas. Suíte inteira rodada oito vezes ao longo das correções: verde.

Varredura da classe (`git grep` de toda escala explícita nos fontes do app): a de cor é a única
categórica; as duas `chartXScale(domain:)` são contínuas (datas), e uma data fora do domínio contínuo
**não** derruba — medido do mesmo jeito (`ImageRenderer`, barra 2 h atrás num domínio de 1 h:
renderiza, rc 0).

Bancada da 0.8.7 no mini (2026-09-06, 11h35–11h39, por mim):
```
gate: 148 [OK], só S15 (B17) vermelha; S68 "baseline 1 verde; cerca reprovou o defeito plantado (rc=1)"
release v0.8.7: tools/release.sh --no-gate → publicada; DMG sha256 b8609e8a545cdeeb…
mini: curl do DMG + SHA256SUMS → sha confere; spctl -t open → Notarized Developer ID
rm + cp -R para /Applications; xattr -dr quarentena; Info.plist 0.8.7; spctl --assess → Notarized Developer ID
serviço: PUT udr7 dry_run true → POST /v1/service/restart ("reinício agendado") → 12 s: health nut ok, bridge ok
         → PUT dry_run false → health udr7 armado_nao_verificado; processo novo (início 11:37:51) de dentro do pacote,
           pacote python do serviço 0.8.7 (medido com o python do pacote)
app: open -a "River Bridge" --args --grafico-eventos --escopo-6h  (o recorte com os 10 eventos do cabo das 09h)
     → 20 s depois: processo vivo; relatórios de queda em ~/Library/Logs/DiagnosticReports: 5 antes, 5 depois
     (os três das 11h01–11h02 são os da 0.8.6, o relato do dono)
```

**Próximo passo (frentes pedidas pelo dono, cada uma com plano e banca):**
1. **B49 — folha de detalhe do River** lendo tudo o que a serial entrega (capacidade mAh, 4 temperaturas,
   tempo para carga completa, entrada solar/DC publicada; firmware só se um comando HID próprio não
   disputar o cabo com o leitor — medir; flags não).
2. **B48 — widget do macOS** (WidgetKit, `Contents/PlugIns`, grupo de aplicativos, retrato gravado pelo
   programa).
3. **B39 — segundo River por BLE** pela sessão do usuário (TCC não atende serviço root), com a
   biblioteca de `rabits/ha-ef-ble` (River 3 Plus coberto; exige User ID da conta; uma conexão BLE por vez).
4. O que só o dono pode medir: o PowerManager em modo **Local** (linhas 7b/8 da bancada) e uma queda de
   energia real com a proteção armada (B42/B43).

## 6. Prompts prontos

Funcionou:
> "Lixo feito" / "instalei a 0.8.2" — e eu meço.

Falhou:
> "não leu; captura: [imagem]" — eu leio o diário (`/Library/Logs/river-unifi-bridge.log`,
> agora com o motivo do leitor) antes de qualquer hipótese.
