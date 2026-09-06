# Handoff — 0.8.0 → 0.8.2 em uma noite: a UX pedida na abertura, e o leitor que o NUT recusava

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

## 5. Próximo passo, na ordem

1. **Dono:** arrastar a 0.8.1 para o Lixo no mini. **Eu:** medir que nada ficou
   (`pgrep -fl river-bridge`, `ls "/Library/Application Support/river-unifi-bridge"`,
   `launchctl print system/com.river.unifi-bridge`) — é a aceitação 1 do plano da 0.8.0.
   (Por que o Lixo antes de instalar por cima: substituir pelo Finder põe o pacote antigo
   no Lixo e o novo no lugar; o vigia não dispara nesse caso por desenho, mas o estado
   antigo ficaria. O teste limpo é Lixo → medir → instalar.)
2. **Dono:** baixar a 0.8.2, arrastar, abrir, Permitir. **Eu:** `pgrep -fl "usbhid-ups|river-bridge-upsd"`
   como root, `LIST UPS` e `LIST VAR river-bridge` por `nc 127.0.0.1 3493`, `tail` do diário
   (agora com bytes), `GET /v1/health` com `cabo.lendo == true`.
3. Então as aceitações 5, 7, 7b, 8, 9 do plano da 0.8.0 (travas, cabo com o PowerManager,
   rede), o Home Assistant (login do dono ou os valores da tela), e o Lixo de novo.

## 6. Prompts prontos

Funcionou:
> "Lixo feito" / "instalei a 0.8.2" — e eu meço.

Falhou:
> "não leu; captura: [imagem]" — eu leio o diário (`/Library/Logs/river-unifi-bridge.log`,
> agora com o motivo do leitor) antes de qualquer hipótese.
