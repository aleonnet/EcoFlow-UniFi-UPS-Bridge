# 0.8.0 — a UX que o dono determinou, inteira: Lixo remove tudo, NUT dentro do App, travas na tela, cabo sem botão, disco assinado e notarizado

status: aceito
data: 2026-09-05
frente: ordem do dono (2026-09-05, sessão desta noite) — *"me entregue 100% do que eu pedi e ao final commit push e teste no macmini toda a UX"*. As ordens originais, citadas nos planos da 0.7.0:
*"INSTALADOR DO MAC OS COM DRAG'N'DROP E UM MOVER PARA LIXEIRA QUE REMOVE TUDO"*, *"experiência padrão Apple"*, *"ao fechar o River Bridge ele libera para o App PowerManager usar… não precisa de botão na UI"*, *"o HAOS deve ter tudo que o App tem… também os comandos desligar reboot"*, *"o App tem que ser User friendly e não para nerds"*.
Decisões do dono nesta sessão (AskUserQuestion, 2026-09-05): NUT **embutido no pacote**; as **três travas viram interruptores** no App com confirmação; **Developer ID + notarização** (o dono cria o certificado agora); cabo: *"uma forma de checar o App PowerManager sem ficar travado… sem complexidade desnecessária, avalie o melhor cenário"* — decisão minha abaixo (D4).

## Context

A 0.7.0 entregou o desenho técnico (driver do NUT, DMG, tela Serviço) mas **não** a UX determinada, conferido no código em 2026-09-05:

| Ordem do dono | O que a 0.7.0 faz | Onde |
|---|---|---|
| Lixo remove tudo | Lixo não remove nada; botão "Remover completamente" + aviso | `ServicoDoSistema.swift:117-160`, `ServicoGroup.swift:48` |
| Cabo sem botão, automático | botão Entregar/Retomar continua; automático nasce **desligado** (`RIVER_CABO_AUTOMATICO=0`) e a detecção casa o daemon permanente da EcoFlow (medido no mini: `…/Contents/MacOS/PowerManager_1.0.0.16.app/Contents/PowerManagerService/PowerManagerService`) | `SettingsView.swift:72-100`, `config.py:98`, `cabo_automatico.py:46` |
| Experiência Apple | LEIA-ME manda rodar `brew install nut` no terminal; assinatura ad-hoc pede "Abrir Assim Mesmo" | `build-dmg.sh:62`, `build-app.sh` (codesign `-`) |
| HAOS com as ordens | travas só no arquivo (`FILE_ONLY_KEYS`); fechadas por padrão as ordens **nem são anunciadas**; abrir a porta para a rede exige editar `upsd.conf` à mão | `config.py:334`, `api.py:130-140`, runbook §2 |
| Telas validadas | nenhuma captura lida em 05/09 | handoff 0.7.0 §5 |

Resultado pretendido: arrastar → aprovar nos Ajustes do Sistema → usar. Sem terminal em nenhum passo. Jogar no Lixo desfaz tudo. O Home Assistant recebe sensores e ordens ligando interruptores na tela. O PowerManager da EcoFlow abre e funciona sem o dono apertar nada.

## Risk band

**critical** — muda como o serviço que desliga equipamentos nasce, se remove e quem pode mandar nele; toca hardware real (River, roteador) na bancada. Regras: diagnóstico ponta a ponta, cada cerca nova refutada por mutante, bancada no Mac mini com cada passo medido no ato, revisão fria sobre o DIFF depois de C6 e antes da release.

## Decisões (D)

| # | Decisão | Fundamento |
|---|---|---|
| D1 | **O serviço se retira sozinho quando o pacote vai para o Lixo.** Vigia por `fcntl(F_GETPATH)` num descritor aberto no `Info.plist` do próprio pacote: o caminho atual do vnode acompanha o `mv`. O gatilho tem duas formas: (a) **na partida**, o caminho do pacote (`RUB_PACOTE`) já contém `/.Trash/` → remove na primeira volta, sem olhar mais nada (é o relançamento de dentro do Lixo, o defeito que o dono viu no mini em 05/09); (b) **durante a vida**, o caminho atual passa a conter `/.Trash/` **e** não existe mais pacote no caminho original gravado na partida. Só então a remoção única: parar o leitor, apagar o diretório de estado (chave, senhas, histórico, dispositivos, configuração do NUT), tirar o trecho do `ups.conf` (caminho CLI), lançar `launchctl bootout system/com.river.unifi-bridge` em **sessão nova** (`Popen(..., start_new_session=True)`: launchd.plist(5), *"When a job dies, launchd kills any remaining processes with the same process group ID as the job"* — sem sessão nova o `launchctl` morreria junto com o serviço) e devolver 0 (parada deliberada; `KeepAlive.SuccessfulExit=false` não relança). Se o SIGTERM do bootout chegar antes do `return`, o caminho é o já existente de `service.py` (`_sinal_de_termino` → `KeyboardInterrupt` → `main` devolve 0): a saída é 0 pelos dois caminhos, e `apagar_tudo` já terminou. O diário `/Library/Logs/river-unifi-bridge.log` **fica de propósito**: é a única pista de por que o serviço sumiu. | `F_GETPATH` medido nesta máquina em 2026-09-05 (`fcntl.fcntl(fd, F_GETPATH)` → `/private/etc/hosts`); o teste S61 prova o `mv` real. A segunda condição existe porque **substituir o pacote no lugar** (atualização pelo Finder) pode pôr o antigo no Lixo enquanto o novo ocupa o caminho original — sem ela, toda atualização seria uma desinstalação (bloqueador B1 da revisão fria, rodada 1). "Arquivo que sumiu" **não** dispara nada. O que o macOS faz com o item na lista de Itens de Início depois do Lixo **não é afirmado**: é medido na bancada (passo 6: `launchctl print system/com.river.unifi-bridge` logo depois e no dia seguinte) e registrado no handoff. Se o launchd relançar do Lixo, a forma (a) do gatilho remove na primeira volta: idempotente (bloqueador B2 da rodada 2: com só a forma (b), o pacote "existe" no caminho gravado, que já é o do Lixo, e o serviço viveria de dentro do Lixo). |
| D2 | **NUT embutido** em `Contents/Resources/nut/{bin/usbhid-ups, sbin/upsd, lib/*.dylib}`, copiado do Homebrew 2.8.5 desta máquina com `install_name_tool` para `@executable_path/../lib/`. Configuração e estado do NUT passam a morar **no nosso diretório de estado** (`/Library/Application Support/river-unifi-bridge/nut` e `…/nut-state`) via `NUT_CONFPATH`/`NUT_STATEPATH`. | Medido: `usbhid-ups` depende só de `libusb-1.0.0.dylib`; `upsd` de `libssl.3`/`libcrypto.3` (`otool -L`). Doc primária upsd(8)/nutupsdrv(8): *"NUT_CONFPATH is the path name of the directory that contains upsd.conf and other configuration files"*, *"NUT_STATEPATH is the path name of the directory in which upsd and drivers keep shared state information"*; `-u`: *"Switch to user after startup if started as root"*. Licença GPL-2.0-or-later: binários distribuídos como programas separados (processos próprios, soquete), com `NOTICE-NUT.txt` (versão, fonte) no pacote e no README. Tamanho medido do NUT inteiro no Homebrew: 18 MB; embutimos 2 binários + 3 dylibs. Caminho do soquete: `…/river-unifi-bridge/nut-state/river-bridge-<id>` ≤ 100 bytes com ids de até 26 caracteres (ids gerados têm 16). |
| D3 | **As três travas viram interruptores** em Ajustes › Travas, cada uma com diálogo de confirmação ao LIGAR (desligar é direto). `FILE_ONLY_KEYS` deixa de existir; as três chaves aplicam a quente. Fechar a trava de armamento com proteção armada continua recusado (já é `frozen_key`). | Decisão do dono nesta sessão. As outras cercas ficam: alcance provado, fonte real, nenhuma proteção armada, confirmação por ato. |
| D4 | **Cabo: automático LIGADO por padrão, sem botão.** O aplicativo da EcoFlow abre → o serviço larga; fecha → retoma. Detecção pelo executável da **interface** (regex `/Contents/MacOS/PowerManager$`), que **não** casa o daemon deles. Com proteção armada não larga e avisa. A tela mostra quem está com o cabo, sem botão. A rota `POST /v1/river/cabo` fica (cerca S4am/S4as/S4ao e contrato para scripts); `tools/river-cabo.sh` sai (morto: fala de LaunchAgents que a 0.5.0 aposentou, e é a origem dos dois agentes sobrando no mini). | É o cenário mais simples que atende *"checar o PowerManager sem ficar travado"*: zero clique, zero estado novo, código já existe — só a detecção estava errada e o padrão desligado. **Medido no mini com a interface ABERTA** (2026-09-05, `open -a PowerManager; pgrep -fl`): três processos — daemon `20016 …/Contents/PowerManagerService/PowerManagerService`, interface `21468 …/PowerManager_1.0.0.16.app/Contents/MacOS/PowerManager` (sem argumentos) e um `osascript … sudo …/run.sh with administrator privileges` que a interface dispara ao abrir (pede a senha de administrador do dono); `pgrep -f '/Contents/MacOS/PowerManager$'` devolveu **só 21468**. Fechada, zero. As duas medições anteriores não se contradizem: em 2026-09-04 (`river-cabo.sh`) o aplicativo deles em modo **Local** dizia "connection failed" com o nosso leitor no cabo; em 2026-09-05 (`config.py:92-97`) o nosso serviço seguiu lendo com o aplicativo deles aberto — o que mede o outro sentido. A bancada mede os dois sentidos (aceitação 7 e 7b) e registra o que o aplicativo deles mostra com e sem o cabo. |
| D5 | **Home Assistant pela rede é um interruptor** no grupo Home Assistant: liga/desliga a linha `LISTEN` do `upsd.conf` (só quando o arquivo é o que nós escrevemos; arquivo do dono → recusa 409) e reinicia só o servidor. | Runbook §2 exigia editar arquivo e reiniciar: caminho de nerd. upsd.conf(5): *"This parameter will only be read at startup"* (já citado no runbook). |
| D6 | **Developer ID + hardened runtime + timestamp + notarização + staple**, assinatura de dentro para fora (cada Mach-O: python, `.so`, dylibs, NUT), sem `--deep`. Identidade e perfil do notarytool vêm por variável (`RUB_SIGN_IDENTITY`, `RUB_NOTARY_PROFILE`); sem elas o pacote é ad-hoc (gate, desenvolvimento) e a release **recusa** publicar. | codesign(1): *"runtime — opts signed processes into a hardened runtime environment which includes … library validation"*; `xcrun notarytool submit … --keychain-profile`, `xcrun stapler staple` (medidos nesta máquina). Certificado Developer ID Application ainda **não existe** (medido: só Apple Development e Apple Distribution) — ato do dono, ver §Atos do dono. |
| D7 | Versão **0.8.0**. | Forma nova de instalar/remover, travas na tela, NUT embutido. |

## Impact sweep (commands run now)

```
git status -sb; git log --oneline -1          # main, limpo, d64bda5
gh release view v0.7.0                        # publicada, com River-Bridge.dmg
tools/release.sh --check                      # 0.7.0 consistente nos 6 arquivos e CHANGELOG
ssh mini 'launchctl list | grep river'        # com.river.nut-driver e com.river.nut-upsd (rc 78, sobras de 04/09)
ssh mini 'ls /opt/homebrew/etc/nut'           # sem ups.conf/upsd.conf/nut.conf; upsd.users com 3 contas
ssh mini 'brew list --versions nut'           # vazio (não instalado); brew 6.0.21 em /opt/homebrew
ssh mini 'pgrep -fl PowerManager'             # 20016 …/Contents/PowerManagerService/PowerManagerService (root)
ssh mini 'ls …/PowerManager.app/Contents/MacOS'  # PowerManager, PowerManager_1.0.0.16.app, launcher.ini, log
ssh mini 'open -a PowerManager; sleep 5; pgrep -f "/Contents/MacOS/PowerManager$"'   # 21468 (só a interface); fechada: nada
```
Saídas corrigidas na rodada 1 da revisão fria (as linhas eram as do meu levantamento, não as do comando):
```
git grep -n FILE_ONLY_KEYS                    # config.py:334; api.py:27,130; tests/unit/test_config.py:261,270,276; RIVER3PLUS_UNIFI_BRIDGE_SPEC_20260831.md:646-647 (spec na raiz: "somente arquivo")
git grep -n chave_somente_arquivo             # api.py:139; tests/unit/test_api.py:310,465,515; tests/integration/test_udr7_e2e.py:285; docs/reference/api-local.md:18; ProtectionRefusal.swift:24
grep -n '^# S[0-9]' tools/gate.sh | sort -t S -k2 -n | tail -1   # S56 é a maior; S57–S69 não existem
grep -n APLICATIVO_DO_FABRICANTE src/river_unifi_bridge/cabo_automatico.py   # :46
git grep -n 'CABO_LARGADO\|PACOTE_NO_LIXO' -- macos tests   # traduções em RiverBridgeCore/DevicePlugins.swift:154-162; tests/fixtures/eventos.json é comparado byte a byte por tests/unit/test_fixtures_contract.py:148-152
sed -n 1,8p tools/captura-por-janela.sh       # "captura-focada.sh chama activate, e isso rouba o teclado do dono" — a captura de validação é captura-por-janela.sh
ssh mini 'ioreg -p IOUSB'                     # EcoFlow EF_UPS_RIVER 3 Plus presente; /dev/cu.usbmodem102
ssh mini osascript System Events               # Acessibilidade concedida a sshd-keygen-wrapper pelo dono (2026-09-05)
otool -L /opt/homebrew/opt/nut/{bin/usbhid-ups,sbin/upsd}   # libusb; libssl+libcrypto
strings upsd | grep '^NUT_'                   # NUT_STATEPATH NUT_CONFPATH NUT_ALTPIDPATH NUT_PIDPATH
python3 -c 'fcntl F_GETPATH'                  # b'/private/etc/hosts'
security find-identity -v -p codesigning      # Apple Development + Apple Distribution; SEM Developer ID Application
git grep -n liberarCabo                       # SettingsView.swift:94,537; RiverConfirmation.swift; FormattingTests.swift:262
git grep -n 'river/cabo'                      # api.py (GET/POST), test_api.py 978-1002, gate S4am/S4as/S4ao, APIClient.swift, SettingsView.swift
git grep -n comandos_do_river                 # nut_comandos.py:70, nut_servico.py:49-119, service.py:490, test_nut_comandos.py
git grep -n RUB_NUT_PREFIX\|RUB_NUT_ETC\|RUB_NUT_STATE   # supervisor, service, api, bootstrap, install/uninstall, gate (seams já existem)
git grep -n river-cabo -- . ':!docs'          # só o próprio arquivo
cat .roadworthy/scope                         # trava da frente anterior ainda ativa (nunca fechada); alargada com motivo datado para este plano
```

## Changes, per file

**Serviço (Python)**
- `src/river_unifi_bridge/cabo_automatico.py` — `APLICATIVO_DO_FABRICANTE = r"/Contents/MacOS/PowerManager$"`; docstring com a anatomia medida do pacote deles. Reuso: `_procurar_padrao` (pgrep -f é regex).
- `src/river_unifi_bridge/config.py` — `RIVER_CABO_AUTOMATICO` default `True`; remove `FILE_ONLY_KEYS`; `UDR7_ARM_ALLOWED`, `RIVER_POWEROFF_ALLOWED`, `DEVICE_CMD_ALLOWED` entram em `HOT_RELOAD_KEYS`; nova chave nenhuma.
- `src/river_unifi_bridge/api.py` — `_authorize` sem o bloco file-only; rotas novas `GET/PUT /v1/nut/rede` (D5) usando `nut_bootstrap.rede_aberta/abrir_para_a_rede` + `supervisor.reiniciar_servidor`; `_apagar_o_que_criamos` vira `remocao.apagar_tudo(state_dir, ups_conf)` (fonte única com D1); texto de recusa `desligamento_bloqueado`/`ORDEM_RECUSADA` passa a dizer "ligue a trava em Ajustes › Travas".
- `src/river_unifi_bridge/nut_comandos.py` — mesmas frases; `comandos_do_river(cfg)` inalterado.
- `src/river_unifi_bridge/nut_servico.py` — `comandos_do_river` aceita callable (avaliado a cada `atualizar`), para a trava ligada na tela virar `ADDCMD` sem reinício.
- `src/river_unifi_bridge/service.py` — passa `lambda: comandos_do_river(cfg)`; instancia `VigiaDoPacote` (D1) quando `RUB_PACOTE` está no ambiente; chama `vigia.conferir()` a cada volta; na remoção: `ponte.encerrar()`, `supervisor.encerrar()`, `remocao.apagar_tudo`, `remocao.desregistrar()`, `return EXIT_OK` com `parada_deliberada`.
- `src/river_unifi_bridge/remocao.py` (**novo**) — `VigiaDoPacote(pacote)`: guarda o caminho original, abre o fd em `<pacote>/Contents/Info.plist` no `__init__`, `caminho_atual()` via `F_GETPATH`, `deve_remover()` = `"/.Trash/" in original or ("/.Trash/" in caminho_atual() and not os.path.isdir(original))`; `apagar_tudo(state_dir, ups_conf)` (o diário em `/Library/Logs` fica); `desregistrar(label, spawn=subprocess.Popen)` lança `launchctl bootout system/<label>` com `start_new_session=True` e não espera.
- `src/river_unifi_bridge/nut_supervisor.py` — `_comando` recebe `env`: quando `RUB_NUT_ETC`/`RUB_NUT_STATE` existem, os filhos nascem com `NUT_CONFPATH`, `NUT_STATEPATH`, `NUT_ALTPIDPATH`.
- `src/river_unifi_bridge/nut_bootstrap.py` — `rede_aberta(etc) -> bool|None` e `abrir_para_a_rede(etc, aberto)`: só reescreve um `upsd.conf` cujo conteúdo é exatamente uma das duas formas nossas (`LISTEN 127.0.0.1 3493` / `LISTEN 0.0.0.0 3493`); qualquer outra → `ConfiguracaoDoDono` (409 na rota).
- `src/river_unifi_bridge/eventos.py` — `PACOTE_NO_LIXO = "PACOTE_NO_LIXO_REMOVIDO"` em `DO_SERVICO`; `tests/fixtures/eventos.json` regenerado no mesmo commit (o contrato compara a lista byte a byte).
- `RIVER3PLUS_UNIFI_BRIDGE_SPEC_20260831.md:646-647` — a frase "trava somente arquivo" ganha a emenda datada (a spec é o contrato; a norma da casa emenda, não reescreve).
- `src/river_unifi_bridge/__init__.py`, `pyproject.toml` — 0.8.0.

**Empacotamento**
- `tools/build-app.sh` — (a) `NUT_VERSAO="2.8.5"`: copia `usbhid-ups`, `upsd` e as 3 dylibs de `/opt/homebrew/opt/nut` e deps; `install_name_tool`; prova `otool -L` sem `/opt/homebrew` e `nut/sbin/upsd -V` == versão; `NOTICE-NUT.txt` (GPL-2.0-or-later, fonte `https://github.com/networkupstools/nut/releases/tag/v2.8.5`). (b) `servico.sh`: exporta `RUB_NUT_PREFIX="$AQUI/nut"`, `RUB_NUT_ETC="$ESTADO/nut"`, `RUB_NUT_STATE="$ESTADO/nut-state"`, `RUB_PACOTE="$AQUI/../.."`; cria as pastas 0700. (c) assinatura de dentro para fora com `RUB_SIGN_IDENTITY` (default `-`): `find` de Mach-O (`file | grep Mach-O`) em `Resources/python`, `Resources/libs`, `Resources/nut`, cada um `codesign --force --options runtime --timestamp --sign "$ID"` (sem `--timestamp` quando ad-hoc), depois o executável e o pacote; `codesign --verify --deep --strict` continua. Mantém os dois textos que S44 confere.
- `tools/build-dmg.sh` — LEIA-ME sem a linha do brew e com "arrastar para o Lixo remove tudo"; assina o DMG; com `RUB_NOTARY_PROFILE`: `xcrun notarytool submit --wait` tem de responder `Accepted`, `xcrun stapler staple`, prova `spctl -a -t open --context context:primary-signature -v` → `source=Notarized Developer ID`.
- `tools/release.sh` — exige `RUB_SIGN_IDENTITY` (Developer ID) e `RUB_NOTARY_PROFILE` para publicar; `--ad-hoc` explícito para o modo antigo; 0.8.0.
- `tools/river-cabo.sh` — **removido**.
- `tools/gate.sh` — cenas novas S57–S64 (ver Refutação).

**App (Swift)**
- `RiverBridgeApp/Settings/SettingsView.swift` — `linhaDoCabo` só informa (sem botões); remove `mudarCabo`, `.liberarCabo`; insere `TravasGroup()` depois de `HomeAssistantGroup()`.
- `RiverBridgeApp/Settings/TravasGroup.swift` (**novo**) — três `Toggle`; ligar → `.confirmacao(PedidoDeConfirmacao)` com `TravaConfirmation`; grava por `putConfig([chave: "1"|"0"])`; lê de `GET /v1/config`; nota "o Home Assistant vê as ordens depois de recarregar a integração".
- `RiverBridgeApp/Settings/HomeAssistantGroup.swift` — interruptor "Aceitar o Home Assistant pela rede" (`GET/PUT /v1/nut/rede`), com recusa traduzida quando o arquivo é do dono.
- `RiverBridgeCore/TravaConfirmation.swift` (**novo**, testável) — título/mensagem/rótulo das três confirmações.
- `RiverBridgeCore/RiverConfirmation.swift` — sai `.liberarCabo`.
- `RiverBridgeCore/APIClient.swift` — sai `riverCabo(acao:)`; entram `nutRede()` / `nutRede(aberta:)`.
- `RiverBridgeCore/ServicoDoSistema.swift` — `avisoDoLixo` passa a dizer o que é verdade agora ("arrastar para o Lixo remove o serviço e tudo o que ele criou; este botão faz o mesmo sem jogar o programa fora"); `RemocaoCompleta` inalterada.
- `RiverBridgeApp/Settings/ProtectionRefusal.swift` — remove `chave_somente_arquivo`; `armamento_bloqueado`/`desligamento_bloqueado` apontam para Ajustes › Travas; novo `configuracao_do_dono`.
- `RiverBridgeCore/DevicePlugins.swift:154-162` — frase para `PACOTE_NO_LIXO_REMOVIDO` (as três do cabo já estão lá); `EventsTimeline.swift` não muda.
- Testes Swift: `FormattingTests` (sai a de `liberarCabo`), `TravaConfirmationTests` (novo), `EventosContractTests` (vocabulário), `ServicoDoSistemaTests` (aviso do Lixo).

**Instalador de linha de comando** (`scripts/install.sh`, `scripts/uninstall.sh`, `river-bridge-install.sh`) — só a versão 0.8.0; caminho Homebrew continua como está (ordem do dono: "podemos ter ambos").

**Configuração e testes**
- `config/river-unifi-bridge.env.example` — comentários das travas (agora pela tela) e `RIVER_CABO_AUTOMATICO=1`.
- `tests/unit/test_cabo_automatico.py`, `test_config.py`, `test_api.py`, `test_nut_supervisor.py`, `test_nut_bootstrap.py`, `test_nut_servico.py`, `test_remocao.py` (**novo**), `tests/integration/test_udr7_e2e.py:285` — conforme acima.

**Documentação**
- `docs/plans/2026-09-05-HHMM-a-ux-determinada-inteira-0-8-0.md` — este plano (cópia canônica; revisão fria ao lado).
- `docs/guides/2026-09-05-HHMM-runbook-instalar-usar-e-remover-pelo-app.md` — supera `2026-09-05-1327-runbook-o-home-assistant-com-tudo.md`: arrastar, aprovar, travas, Home Assistant pela rede, cabo automático, Lixo.
- `docs/reference/api-local.md` — sem `chave_somente_arquivo`; rotas `/v1/nut/rede`; `POST /v1/river/cabo` marcado "sem botão na tela; contrato para scripts".
- `README.md`, `CHANGELOG.md` (`[0.8.0]`), `docs/README.md` (mapa), `docs/BACKLOG_20260901.md` (B37 fechado; B-novo: agentes sobrando no mini removidos à mão), handoff novo em `docs/plans/`.

## Scope
```
src/river_unifi_bridge/**
tests/**
tools/build-app.sh
tools/build-dmg.sh
tools/release.sh
tools/gate.sh
tools/river-cabo.sh
macos/RiverBridge/Sources/**
macos/RiverBridge/Tests/**
config/river-unifi-bridge.env.example
scripts/install.sh
scripts/uninstall.sh
river-bridge-install.sh
pyproject.toml
README.md
CHANGELOG.md
docs/**
RIVER3PLUS_UNIFI_BRIDGE_SPEC_20260831.md
.roadworthy/**
/Users/alessandro/.claude/plans/leia-todo-o-c-digo-prancy-sundae.md
/Users/alessandro/.claude/plans/leia-todo-o-c-digo-prancy-sundae.review.md
/Users/alessandro/.claude/projects/-Users-alessandro-Development-EcoFlow-UniFi-UPS-Bridge/memory/**
```

## Acceptance (EARS)
| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | o pacote instalado é movido para o Lixo | em ≤ 1 volta do laço: parar leitor e servidor do NUT, apagar `/Library/Application Support/river-unifi-bridge`, desregistrar o job e sair 0 | mini: `osascript … Finder delete`; `sleep 5; pgrep -fl river-bridge; ls "/Library/Application Support/river-unifi-bridge"; launchctl print system/com.river.unifi-bridge` | qualquer processo vivo, pasta existente ou job carregado |
| 2 | o pacote é movido para OUTRA pasta (não o Lixo) | nada é apagado | `test_remocao.py::test_mover_fora_do_lixo_nao_remove` (mv em tmp + F_GETPATH) | remoção disparada |
| 2b | o pacote antigo está no Lixo mas há um pacote novo no caminho original (atualização) | nada é apagado | `test_remocao.py::test_substituido_no_lugar_nao_remove` (mv para `…/.Trash/` + mkdir do novo no caminho original) | remoção disparada |
| 2c | o `Info.plist` do pacote some sem passar pelo Lixo | nada é apagado | `test_remocao.py::test_arquivo_apagado_nao_dispara` | remoção disparada |
| 2d | o serviço PARTE com o pacote já dentro do Lixo (relançamento pelo launchd) | remove na primeira volta | `test_remocao.py::test_partida_dentro_do_lixo_dispara` | serviço segue vivo |
| 2e | a remoção lança o `launchctl bootout` | o filho nasce em sessão nova (`start_new_session=True`) | `test_remocao.py::test_bootout_nasce_em_sessao_nova` (spawn de mentira recebe o argumento) | argumento ausente |
| 3 | o serviço sobe pelo pacote numa máquina SEM Homebrew/NUT | leitor e servidor sobem dos binários embutidos como root, com config em `…/river-unifi-bridge/nut` | mini: `pgrep -fl 'river-bridge-ups|river-bridge-upsd'` (user root); `printf 'LIST UPS\n' \| nc 127.0.0.1 3493` lista `river-office`, `river-bridge`, `udr7` | processo ausente ou `LIST UPS` vazio |
| 4 | o pacote é montado | zero referência a `/opt/homebrew` nos Mach-O embutidos; `nut/sbin/upsd -V` = 2.8.5 | `build-app.sh` (prova interna) + gate S60 | `otool -L` com `/opt/homebrew` ou versão diferente |
| 5 | o dono liga uma trava em Ajustes › Travas e confirma | `PUT /v1/config {CHAVE:"1"}` responde `aplicadas_a_quente` contendo a chave; a ordem correspondente passa a existir sem reinício | `test_api.py::test_travas_aplicam_a_quente`; mini: `LIST CMD river-bridge` via nc com conta `homeassistant` mostra `load.off` após ligar `RIVER_POWEROFF_ALLOWED` | 400, `restart_required`, ou comando ausente |
| 6 | a trava de armamento é desligada com proteção armada | 409 `armado` | `test_api.py::test_fechar_trava_armada_e_recusado` | 200 |
| 7 | o aplicativo da EcoFlow (interface) abre | em ≤ 5 s o cabo é largado, evento `CABO_LARGADO_AUTOMATICO`; ao fechar, retomado e `LIST VAR river-office` volta a responder | mini: `open -a PowerManager`; `GET /v1/health .cabo`; `pkill -f '/Contents/MacOS/PowerManager$'` (o `quit` por AppleScript não fecha o aplicativo deles — medido); nc LIST VAR | cabo não larga, ou não volta em 60 s |
| 7b | o aplicativo da EcoFlow abre em modo Local com o cabo (a) no nosso serviço e (b) largado | o que ele mostra em cada caso é registrado no handoff (é a prova de que o empréstimo tem ou não benefício) | mini: `RIVER_CABO_AUTOMATICO=0` no arquivo, abrir, registrar; `=1`, abrir, registrar | sem registro dos dois casos |
| 8 | só o daemon de fundo da EcoFlow está rodando (app fechado) | o cabo NÃO é largado | `test_cabo_automatico.py::test_o_daemon_deles_nao_e_o_aplicativo` (regex contra os dois caminhos medidos) + mini em repouso: `.cabo.lendo == true` | largado |
| 9 | o dono liga "Aceitar o Home Assistant pela rede" | `upsd.conf` passa a `LISTEN 0.0.0.0 3493`, servidor reiniciado; do MacBook `nc 192.168.1.13 3493` responde `LIST UPS` | `test_nut_bootstrap.py::test_abrir_para_a_rede`; medição do MacBook | conexão recusada |
| 10 | o `upsd.conf` não é o que escrevemos | a rota recusa 409 `configuracao_do_dono` e não toca no arquivo | `test_nut_bootstrap.py::test_arquivo_do_dono_nao_e_tocado` | arquivo alterado |
| 11 | o DMG é publicado | assinatura Developer ID com hardened runtime e timestamp em todo Mach-O, notarização `Accepted`, ticket grampeado; no mini, com quarentena forçada, o Gatekeeper aceita | `codesign -dv --verbose=4` (Authority=Developer ID Application, flags runtime), `spctl -a -t open --context context:primary-signature -v DMG` → Notarized Developer ID; mini: `xattr -w com.apple.quarantine …; spctl --assess --type execute` | qualquer um reprovar |
| 12 | o DMG é aberto | o LEIA-ME não menciona terminal nem Homebrew | `grep -c brew LEIA-ME.txt` = 0 | ≥ 1 |
| 13 | a tela Ajustes é fotografada nesta máquina (Serviço, Home Assistant, Travas, River) | as capturas são lidas em imagem e conferidas contra o desenho (paleta única, escala de espaço, sem botão do cabo) | `tools/captura-por-janela.sh` (sem `activate`, que rouba o teclado do dono) + leitura das PNG | defeito visual visto na imagem |
| 14 | a suíte roda | gate verde (S15/B17 continua declarada), pytest, swift test, docs-check, lychee | gates de `.roadworthy/gates` | qualquer vermelho fora de S15 |

## Ordem de commits
| # | Commit | Cercas |
|---|---|---|
| C0 | plano em `docs/plans/`, revisão fria do plano ao lado, `.roadworthy/scope` | — |
| C1 | cabo: detecção pela interface, padrão ligado, tela sem botão, `river-cabo.sh` fora | S57 |
| C2 | travas na tela: config/api/ponte + `TravasGroup` + textos | S58, S58b |
| C3 | NUT embutido: `build-app.sh`, `servico.sh`, supervisor com `NUT_*` | S59, S60 |
| C4 | Lixo remove tudo: `remocao.py` + vigia no laço + eventos | S61, S62 |
| C5 | Home Assistant pela rede: bootstrap + rotas + interruptor | S63 |
| C6 | assinatura e notarização: `build-app.sh`, `build-dmg.sh`, `release.sh` | S64 |
| — | **revisão fria sobre o diff C1–C6** (cold-reviewer; bloqueadores corrigidos antes de seguir) | — |
| C7 | capturas lidas e ajustes de tela; runbook novo; api-local; README; LEIA-ME | — |
| C8 | CHANGELOG 0.8.0, versão nos 6 arquivos, handoff; `tools/release.sh v0.8.0` (gate+pytest+swift+notarização), push | — |
| C9 | **bancada no Mac mini** (abaixo), resultados no handoff, commit + push | — |

## Bancada no Mac mini (C9, medida por mim, na ordem)
1. Sobras de 04/09: `launchctl bootout gui/501/com.river.nut-driver` e `…nut-upsd`; `rm ~/Library/LaunchAgents/com.river.nut-*.plist` (agentes de usuário, sem sudo).
2. `curl -fL …/latest/download/River-Bridge.dmg`; `hdiutil attach`; `cp -R` para `/Applications` (pasta gravável por admin); `xattr -w com.apple.quarantine` numa cópia de prova e `spctl --assess` → aceito (aceitação 11); `open -a "River Bridge"`.
3. Clique em **Instalar o serviço** por `osascript` (Acessibilidade concedida). **Ato do dono:** aprovar em Ajustes do Sistema › Itens de Início de Sessão (pede a senha de administrador; é a única mão que não é minha).
4. Aceitações 3, 5, 7, 8, 9 via ssh e nc; `GET /v1/health` com a ficha de `/Library/Application Support/river-unifi-bridge/ui-api.token` (0640 admin).
5. Home Assistant (`http://haos.home.arpa/`): adicionar a integração NUT em `river-bridge` e em `udr7` pelo navegador (Playwright) **se o dono me der o login do HA na hora**; senão, os valores ficam copiados na tela e o passo é do dono. Sensores com watts por tomada e as ações de dispositivo.
6. Aceitação 1 (Lixo): `launchctl print system/com.river.unifi-bridge` logo depois e **no dia seguinte** (o que o macOS faz com o item de Itens de Início não é afirmado, é medido); em seguida reinstalar do DMG para deixar o mini no estado final; esvaziar o Lixo.
6b. Aceitação 7b: abrir o PowerManager em modo Local com e sem o cabo largado e registrar o que ele mostra. Aviso: a interface dele pede a senha de administrador do dono ao abrir (dispara `sudo …/run.sh`); eu fecho o pedido, não digito nada.
7. Handoff com cada comando e saída.

## Atos do dono (fora do meu alcance, nomeados)
- Criar o certificado **Developer ID Application** (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application) — o Team ID que aparecer é o que `RUB_SIGN_IDENTITY` usa.
- Guardar a credencial do notarytool: `! xcrun notarytool store-credentials river-bridge --apple-id <apple id> --team-id <TEAM> --password <senha de app>` (a senha de app nasce em appleid.apple.com; eu nunca a vejo).
- Aprovar o serviço nos Ajustes do Sistema do mini (senha de administrador).
- Login do Home Assistant, se quiser que eu execute os passos 5/6 do runbook pelo navegador.

## Verification (after the last commit)
- `tools/gate.sh` → todas as cenas verdes, S15 vermelha declarada (B17), S57–S64 verdes
- `.venv/bin/pytest` → verde
- `cd macos/RiverBridge && swift test` → verde
- `docs-check.sh docs --since 2026-09-01` e `lychee --offline --root-dir . docs/` → limpos
- `tools/release.sh --check` → 0.8.0 consistente
- `gh release view v0.8.0` → DMG, zip, código, SHA256SUMS
- Bancada C9 com as saídas coladas no handoff

## Refutation
- **S57** `cabo_automatico.py`: mutante volta `APLICATIVO_DO_FABRICANTE` ao prefixo `/Applications/PowerManager.app/Contents/MacOS/` → `test_o_daemon_deles_nao_e_o_aplicativo` reprova (o caminho do daemon casa).
- **S58** `api.py`: mutante restaura a recusa file-only → `test_travas_aplicam_a_quente` reprova (400). **S58b** `nut_servico.py`: mutante congela `comandos_do_river` na construção → `test_trava_ligada_vira_addcmd_sem_reinicio` reprova.
- **S59** `nut_supervisor.py`: mutante deixa de passar `NUT_CONFPATH`/`NUT_STATEPATH` → `test_nut_supervisor.py::test_os_filhos_nascem_com_os_caminhos_do_pacote` reprova. **S60** texto do `build-app.sh`: precisa conter a prova `otool -L … grep -c /opt/homebrew` e `upsd -V` (molde S44).
- **S61** `remocao.py`: mutante ignora `/.Trash/` → `test_no_lixo_dispara` reprova (mv real em tmp para `…/.Trash/x`). **S62** mutante dispara em qualquer mv → `test_mover_fora_do_lixo_nao_remove` reprova. **S62b** mutante tira a segunda condição (pacote novo no caminho original) → `test_substituido_no_lugar_nao_remove` reprova. **S62c** `service.py`: mutante chama `desregistrar` antes de `apagar_tudo` → teste com `launchctl` de mentira que registra a ordem reprova. **S62d** `remocao.py`: mutante tira a forma (a) do gatilho → `test_partida_dentro_do_lixo_dispara` reprova. **S62e** mutante tira `start_new_session=True` → `test_bootout_nasce_em_sessao_nova` reprova.
- **S63** `nut_bootstrap.py`: mutante reescreve qualquer `upsd.conf` → `test_arquivo_do_dono_nao_e_tocado` reprova.
- **S64** texto do `build-app.sh`: precisa conter `--options runtime` e a assinatura de cada Mach-O antes do pacote; mutante com `--deep` como único passo reprova.

## Out of scope
- Trocar o instalador de linha de comando (continua com o NUT do Homebrew).
- Ligar/desligar tomadas do River (B35); energia acumulada (B34); BLE/nuvem (B39).
- Capturas de pixel no mini (sem permissão de gravação de tela lá); as capturas de pixel são desta máquina, o comportamento é medido no mini.
- O que o macOS faz com o item na lista de Itens de Início depois do Lixo é dele, não nosso; o plano não afirma prazo, só mede (bancada, passo 6).

## Overnight policy
- Decidido à noite, com fonte: nomes de variável do NUT, regex do executável do PowerManager (medida no mini), ordem de assinatura (codesign(1)), textos das telas (molde do design system). Registrado no diário e ratificado de manhã.
- Reservado ao dono: push, release e notarização (publicação externa), qualquer ato no Mac mini que remova ou instale (bancada C9), abrir travas em máquina real, e o certificado/credenciais. Domínios deste plano reservados: `C8`, `C9`, `tools/release.sh`.

## Open questions
Histórico da revisão fria (cold-reviewer, 2026-09-05):
- **Rodada 1: REJECTED** — B1 (gatilho "arquivo que sumiu" apagaria tudo numa atualização) + A1–A5 + N1–N4. Classe do que faltou no meu levantamento: pensar o ciclo de vida do pacote inteiro (atualização, relançamento), não só o Lixo.
- **Rodada 2: REJECTED** — B2 (relançamento de dentro do Lixo não se removia com a segunda condição) e B3 (`bootout` desprendido morre com o grupo de processos; launchd.plist(5) `AbandonProcessGroup`) + A6. Os dois foram corrigidos acima como resíduo mecânico de uma linha, como o próprio revisor os classificou. A casa não tem 3.ª rodada: a contagem de bloqueadores não caiu (1 → 2), então a aprovação é **decisão do dono** ao aprovar este plano; a linha `owner:` entra no arquivo de revisão em C0.
- Fora isso, nenhuma pergunta que bloqueie. Login do Home Assistant para os passos 5/6 da bancada: se não vier, o passo é do dono com os valores copiados da tela (registrado na bancada).
