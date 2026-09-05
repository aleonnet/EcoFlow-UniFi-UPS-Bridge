# 0.7.0 — instalar arrastando o App, e remover jogando no Lixo

status: proposto
data: 2026-09-05
frente: ordem do dono — *"PRECISAMOS CONVERTER ENTÃO EM UM INSTALADOR DO MAC OS COM DRAG'N'
DROP E UM MOVER PARA LIXEIRA QUE REMOVE TUDO… NÃO PRECISA REMOVER O MÉTODO ATUAL, PODEMOS TER
AMBOS"* — e a exigência que veio junto: *"é colocar a porra que fazemos DENTRO do framework
conhecido do instalador (que CLARO você deve pesquisar), pois tentativa e erro é proibido"*.

## 1. O problema, medido

Hoje o serviço mora **fora** do App: `/usr/local/river-unifi-bridge` (18 MB no Mac mini,
medido), registrado em `/Library/LaunchDaemons/com.river.unifi-bridge.plist`. Jogar o App no
Lixo não remove nada disso — o serviço continua subindo a cada reinício. E instalar exige
`curl | bash` com senha de administrador.

## 2. O framework, pesquisado na fonte oficial (com citação)

O caminho da Apple para isto é o **Service Management** com `SMAppService` (macOS 13+):

- **Onde o serviço mora:** *"The property list name must correspond to a property list in the
  calling app's `Contents/Library/LaunchDaemons` directory"*
  ([`daemon(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:))).
- **Por que é melhor que hoje:** *"the advantages of this approach include containing your
  `LaunchDaemon` and `LaunchAgent` property lists in a fully codesigned app bundle that neither
  the system nor a third party can modify without breaking the code signature… Users can also
  see which app is providing the launch daemons or launch agents by choosing System Settings >
  General > Login Items"*
  ([artigo do exemplo oficial](https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api)).
- **O que registrar exige:** *"If the service corresponds to a LaunchDaemon, the system won't
  bootstrap the LaunchDaemon until an admin approves the LaunchDaemon in System Preferences"*
  ([`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register())).
- **Desinstalar de dentro do App:** *"Unregisters the service so the system no longer launches
  it… the system terminates it"*
  ([`unregister()`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister())).
- **O rastro depois de apagar o App:** *"The login item may remain visible in the System
  Settings > General > Login Items for some time. This is expected because the system removes
  deleted items as part of its maintenance processes overnight"* (mesmo artigo). **Não é
  defeito: é limpeza adiada, documentada.**

### Medido por mim neste MacBook, com um App de teste (já desfeito)

| Passo | Resultado |
|---|---|
| estado antes | `notFound` |
| `register()` como usuário comum, **sem `sudo`, sem pedir senha** | devolve erro `Operation not permitted` **e** o estado passa a `requiresApproval` |
| o serviço chegou a rodar? | **não** — falta a aprovação |
| `unregister()` | sem erro; estado volta a `notRegistered` |

**Consequência de desenho, e é a mais importante desta frente:** `register()` **devolvendo erro
é o caminho NORMAL**. O App tem de tratar isso como estado ("falta ligar o interruptor"), com um
botão que abre os Ajustes do Sistema, e nunca como falha.

### O Python dentro do pacote, medido

O serviço é Python; hoje o `venv` nasce na instalação, do Homebrew, com internet
(`scripts/install.sh:321-338`). Dentro do App isso não existe — o pacote tem de carregar o
próprio interpretador. Medições feitas no ato, com o
[python-build-standalone](https://gregoryszorc.com/docs/python-build-standalone/main/)
(o mesmo que o `uv` usa; alvo `aarch64-apple-darwin`, arquivo `install_only`):

| Fato | Medida (comando rodado no ato, 2026-09-05) |
|---|---|
| o "python do macOS" é o do Xcode | `/usr/bin/python3 -m pip` imprimiu `/Applications/Xcode.app/Contents/Developer/usr/bin/python3`; versão `3.9.6`. Num Mac sem as ferramentas de desenvolvedor, esse caminho não roda — abre a caixa de instalação |
| o nosso código roda no 3.9.6 | sim: importa e responde `0.6.0`. Ou seja, o `requires-python = ">=3.13"` do projeto é declaração nossa, não piso medido — **embutir não é obrigatório, é escolha** |
| tamanho do Python embutido | 25 MB comprimido · **66 MB expandido** |
| roda de qualquer caminho | **sim** — testado movendo para `…/Um Caminho Com Espaços/River Bridge.app/Contents/Resources/` |
| `ssl` e `sqlite3` funcionam | sim (sqlite 3.53.1) |
| `aiohttp` instalado no pacote | 5,7 MB |
| o nosso serviço importa nele | **sim** — devolveu `0.6.0` |
| licença | permissiva; as versões pós-2023 usam `libedit` e desligam `_gdbm` justamente **para evitar GPL** (documentação do projeto) |

Bundle final estimado: **~75 MB expandido**, ~35 MB no arquivo de download.

## 3. Faixa de risco

**Crítico.** Muda como o serviço que desliga equipamentos nasce, roda e morre. Regras:

- **Nunca dois serviços ao mesmo tempo.** Se a instalação por linha de comando existir na
  máquina, o App **recusa** registrar o dele e explica — dois donos do mesmo cabo é pior que
  nenhum. Cerca própria.
- O caminho antigo (`curl | bash`) **continua funcionando**, sem remoção.
- Remover pelo App é ato com confirmação, e diz o que vai apagar.
- Nada aqui arma proteção nem abre trava.

## 4. Decisões

| # | Decisão | Motivo |
|---|---|---|
| D1 | O pacote passa a carregar **interpretador, dependências e o nosso código** em `Contents/Resources/` (`python/`, `libs/`, `src/`). | Não é obrigatório (o código roda no 3.9.6 do Xcode, medido) — é escolha, e o fundamento é este: o interpretador do sistema é o do Xcode, e um vigia de energia que roda sozinho de madrugada não pode parar porque alguém removeu ou moveu o Xcode. Custa 66 MB no pacote e roda de qualquer caminho, inclusive com espaços (medido). |
| D2 | O serviço é declarado em `Contents/Library/LaunchDaemons/com.river.unifi-bridge.plist` com `BundleProgram`, e **roda como root** (sem `UserName`). | O plist mora dentro do pacote **assinado**: qualquer edição depois da assinatura a quebra, então ele não pode ser personalizado com o usuário de cada máquina — e é isso que hoje o instalador faz (`scripts/install.sh:599`). Rodar como root é o padrão de um serviço de sistema. |
| D8 | Com o serviço como root, o estado sai de `~/Library/Application Support/river-unifi-bridge` para **`/Library/Application Support/river-unifi-bridge`** (0700, root) — **só no caminho do App**. Quem instalou pela linha de comando continua onde está. | Estado de serviço de sistema não mora na pasta de um usuário. E manter os dois caminhos separados evita que uma instalação pise na outra. |
| D9 | O arquivo do token nasce **0640, grupo `admin`**, e o App procura o estado **primeiro na pasta do usuário, depois na do sistema**. | O App roda como o dono (administrador) e precisa ler o token para falar com o serviço; hoje ele só olha a pasta do usuário (`ApiEndpoint.swift:21`). Sem isso, App e serviço não se encontram no caminho novo. |
| D10 | Na primeira subida pelo caminho do App, se existir estado antigo na pasta do usuário e nenhum no sistema, ele é **copiado uma vez** (e o antigo fica, intocado). | Ninguém perde chave, histórico ou dispositivos ao trocar de forma de instalar; e voltar atrás continua possível. |
| D3 | O App ganha a tela **"Serviço"**: estado (não instalado / falta aprovar / no ar), **Instalar**, **Abrir Ajustes do Sistema**, **Remover completamente**. | `register()` erra com estado `requiresApproval` — medido. A tela tem de dizer isso em português, sem sigla. |
| D4 | **Recusa cruzada:** o App não registra o serviço enquanto existir `/Library/LaunchDaemons/com.river.unifi-bridge.plist` (instalação por linha de comando), e o instalador por linha de comando avisa quando o App já está registrado. | Dois serviços disputando o cabo e a porta 35493 é o pior desfecho possível. |
| D5 | **Remover completamente** = `unregister()` + apagar estado (chave, senhas, histórico, dispositivos) + a configuração do NUT que criamos, tudo com confirmação nomeando o que sai. | É o que a Lixeira não faz, e o dono pediu que existisse. |
| D6 | O Python do pacote é **fixado por versão e SHA-256** no empacotador; a release carrega o pacote pronto. | Baixar na hora da instalação traria de volta a dependência de internet que estamos eliminando. |
| D7 | Versão **0.7.0**. | Muda a forma de instalar; convive com a antiga. |

## 5. Mudanças por arquivo

- `tools/build-app.sh`: baixa (com SHA fixado) e embute o Python; instala `aiohttp` em
  `Contents/Resources/libs`; copia `src/`; escreve o plist do serviço em
  `Contents/Library/LaunchDaemons/`; assina o pacote inteiro.
- `tools/release.sh`: passa a publicar o `.app` empacotado com tudo (o `zip` já existe) e um
  `.dmg` com o atalho para `Aplicativos` (o arrastar clássico).
- `macos/.../RiverBridgeCore/ApiEndpoint.swift`: procura o estado na pasta do usuário e, não achando, na do sistema (D9).
- `src/river_unifi_bridge/service.py`: cópia única do estado antigo quando roda no caminho novo (D10).
- `macos/.../RiverBridgeCore/ServicoDoSistema.swift` (novo): embrulha `SMAppService` —
  `estado()`, `instalar()`, `remover()`, `abrirAjustes()`; traduz o estado para frase humana.
- `macos/.../RiverBridgeApp/Settings/ServicoView.swift` (novo): a tela do D3.
- `scripts/install.sh`: aviso quando o App já registrou o serviço (D4).
- `scripts/uninstall.sh`: inalterado (continua servindo o caminho por linha de comando).
- `docs/`: runbook novo dos dois caminhos; `README.md` com as duas formas.

## 6. Cercas novas (cada uma com o defeito plantado que a reprova)

| Cena | O mutante quebra |
|---|---|
| S24 | o pacote sem o Python embutido, ou com um Python que não roda do caminho do pacote |
| S25 | o `.app` sem o plist do serviço em `Contents/Library/LaunchDaemons/`, ou com `BundleProgram` apontando para arquivo que não existe |
| S26 | o serviço do pacote não conseguindo importar o nosso código com o Python do pacote |
| S27 | a assinatura do pacote quebrada depois de embutir tudo (`codesign --verify --deep --strict`) |
| S28 | o App registrando o serviço com a instalação por linha de comando presente (D4) |
| S29 | o token do serviço de sistema ilegível para o App (D9), ou legível para qualquer um |
| S30 | a cópia única do estado antigo virando cópia repetida, ou apagando o original (D10) |
| Swift | `register()` que devolve erro com estado `requiresApproval` sendo mostrado como FALHA, e não como "falta aprovar" |

## 7. Aceitação (EARS)

| # | WHEN | THE SYSTEM SHALL | falha quando |
|---|---|---|---|
| 1 | o pacote é montado | conter Python, `aiohttp`, `src/` e o plist do serviço, e a assinatura verificar | falta qualquer um |
| 2 | o Python do pacote roda a partir do caminho do pacote | importar o nosso serviço e responder a versão | erro de importação |
| 3 | o App instala o serviço numa máquina limpa | estado vira "falta aprovar", **sem pedir senha**, com o botão que abre os Ajustes | pede senha, ou trata o erro como falha |
| 4 | o dono aprova nos Ajustes | o serviço sobe e a tela diz "no ar" | continua parado sem explicação |
| 5 | existe instalação por linha de comando na máquina | o App **recusa** registrar e explica | registra, e passam a existir dois |
| 6 | "Remover completamente" | desinscrever, encerrar, e apagar estado e configuração com confirmação | sobra serviço rodando ou estado sem aviso |
| 7 | o App vai para o Lixo sem "Remover completamente" | nada mais roda (o código foi junto); o item some dos Ajustes na manutenção do sistema | continua rodando |
| 8 | o caminho por linha de comando | continua funcionando exatamente como hoje | qualquer cena antiga vermelha |

## 8. Ordem de commits

| # | Commit |
|---|---|
| C1 | empacotador: Python embutido (SHA fixado), `libs/`, `src/`, plist do serviço — cenas S24–S27 |
| C2 | `ServicoDoSistema.swift` + testes do mapeamento de estado |
| C3 | a tela "Serviço" no App |
| C4 | recusa cruzada nos dois sentidos (D4) — cena S28 |
| C5 | "Remover completamente" |
| C6 | `.dmg` com o atalho para Aplicativos; release |
| C7 | documentos, versão 0.7.0 |
| C8 | bancada do dono: arrastar, aprovar, usar, remover |

Revisão fria sobre o diff depois de C4 e depois de C6.

## 9. Fora de escopo

- Assinatura com Developer ID e notarização (custa dinheiro; a assinatura ad-hoc de hoje
  continua, e o `curl` não grava quarentena — medido em 2026-09-02).
- Intel: o Python embutido é `aarch64`; o projeto já exige Apple Silicon.
- Remover o caminho por linha de comando.
