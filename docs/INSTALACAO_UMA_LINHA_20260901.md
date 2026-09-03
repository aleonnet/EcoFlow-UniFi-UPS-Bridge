# Instalação em uma linha — `river-bridge-install.sh` (2026-09-01)

Um arquivo, um comando, a senha uma vez. Padrão da casa (haos-install.sh / ont-setup.sh):
`curl … | bash -s -- [opções]`, idempotente (0 fez · 100 já estava), abertura animada
degradável, prompts lidos de `/dev/tty` (funciona pelo cano), trabalho privilegiado
concentrado numa única chamada `sudo scripts/install.sh` logo após primar o `sudo`.

## Remoto (repositório PÚBLICO desde 2026-09-01 — `gh repo edit --visibility public`, ordem do dono)

```bash
curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s --
```

Verificado em 2026-09-01 após a publicação: o script pelo `raw` responde e roda em `--dry-run`;
o tarball `archive/refs/heads/main.tar.gz` baixa, extrai (`--strip-components=1`) e instala o
serviço num prefixo de teste (stubs de brew/launchctl, exit 0). Flags úteis: `--dry-run`
(só o plano), `--no-app` (só o serviço), `--install-deps` (instala o Homebrew se faltar).

## Local (árvore já na máquina — bancada, ou sem rede)

```bash
~/river-bridge-deploy/river-bridge-install.sh --src ~/river-bridge-deploy
```

O mesmo arquivo, o mesmo fluxo; `--src` só troca o download pela árvore indicada.

## O que ele faz (5 fases, barra de fases, calha)

| Fase | Faz | "já estava" |
|---|---|---|
| 01 Pré-voo | macOS, `curl/tar/shasum`, Homebrew (portão; `--install-deps` instala o oficial em `NONINTERACTIVE`), Swift (no canal release, sem Swift é só informação: o app vem pronto) | — |
| 02 Código-fonte | **canal release (default, desde 2026-09-02):** lê `SHA256SUMS` em `releases/latest/download` (a tag vem do prefixo do tarball, `river-unifi-bridge-<tag>/`; medido em 2026-09-02 que o redirect do GitHub vai para a CDN de assets, sem a tag no caminho), pina o tarball e o app; **qualquer falha → canal main com aviso**. Depois: baixa o tarball (`.parcial` → `mv`), `sha256` contra o pino (`RUB_SRC_SHA256` ou o `SHA256SUMS`), extrai em `~/Library/Caches/river-unifi-bridge/src-<sha>` | cache com o mesmo sha |
| 03 Serviço | **`sudo scripts/install.sh --consent-homebrew`** — brew `nut` + `python@3.13`, código, **desinstalador em `$PREFIX/scripts`**, venv, `bridge.env` (preservado), LaunchDaemon; **código novo com plist igual → `kickstart`** | `install.sh` devolve 100 |
| 04 App | canal release e arm64: baixa `River-Bridge.app.zip`, confere o sha (**divergente = exit 3, nada instalado**), extrai com `ditto -xk` em `app-<sha>`; senão `tools/build-app.sh` (Swift, no alvo). Instala em `~/Applications/River Bridge.app` se o binário mudou (fecha/reabre se estava aberto) | binário idêntico (`cmp`) |
| 05 Verificação | espera a API local, lê `/v1/version` e `/v1/health` (NUT, UDR7, UniFi) | — |

Saída: 0 (fez algo) · 100 (nada a fazer) · 2 uso · 3 validação · 4 dependência · 10 rede ·
130 cancelado · 1 falha. Relatório em `~/Library/Application Support/river-unifi-bridge/installer-last-run.log`,
com a linha `fonte=release vX.Y.Z` / `fonte=main <sha12>` / `fonte=local <dir>` dizendo de onde veio o
código — a mesma linha aparece na caixa do fecho. Reexecutar é seguro: cada fase confere o estado.

O `SHA256SUMS` prova que o download chegou íntegro e que tarball e app são da **mesma** release;
não protege contra um GitHub comprometido (mesma origem TLS). Os assets têm nome sem versão para o
instalador achá-los por `releases/latest/download/<asset>` só com `curl`; quem os produz é
`tools/release.sh` (na máquina de desenvolvimento, sem CI). O app da release é ad-hoc: `curl` não
grava `com.apple.quarantine` (medido em 2026-09-02) e `ditto` só preservaria uma marca que o
arquivo de origem tivesse.

## Senha uma vez — por quê funciona

`garantir_sudo` (molde haos-install.sh:487-504): `sudo -n true` → se não há cache, `sudo -v <
/dev/tty` **uma vez**; em seguida a única chamada privilegiada é `sudo scripts/install.sh`, que
faz tudo que exige root (inclusive o `kickstart`). O app compila e instala como o usuário. Não há
keepalive porque não há segundo `sudo` depois de minutos. O instalador nunca guarda, ecoa ou
repassa a senha.

## Flags

`--dry-run` · `--yes` · `--install-deps` · `--no-app` · `--no-open` · `--release TAG` (release
específica; default `latest`) · `--from-main` (tarball do branch e build local, como até a v0.1.0) ·
`--src DIR` · `--no-anim` · `--demo` · `--demo-frame N` · `--lang pt|en` · `--version` · `--help`.
Seams (bancada/gate): `RUB_CANAL` (`release`|`main`; **`RUB_SRC_URL` explícito implica `main`**,
detectado com `${RUB_SRC_URL+x}` antes do default), `RUB_RELEASE`, `RUB_RELEASE_BASE` (`file://…`
na S18), `RUB_SRC_URL`, `RUB_SRC_DIR`, `RUB_SRC_SHA256`, `RUB_CACHE_DIR`, `RUB_STATE_DIR`,
`RUB_PREFIX`, `RUB_LAUNCHD_DIR`, `RUB_SERVICE_USER`, `RUB_PYTHON`, `RUB_SUDO` (vazio = sem sudo,
para stubs), `RUB_APP_DEST`, `RUB_SKIP_HEALTH`, `UI_NO_ANIM`, `NO_COLOR`.

## Abertura — o escudo do app

Molde: `lib/haos-ui.sh` do haos-install — mesma largura (34 colunas), mesmo ritmo (0,03 s por
quadro) e mesma gramática, com a identidade daqui: lá a casa é **azul** com o circuito **branco**;
aqui o escudo é **claro** com o raio vazado no **verde**, exatamente como no AppIcon — não a
inversão dele. A altura é 40 px (20 linhas de meio-bloco), não os 34 da casa: o escudo é mais alto
que largo, e no canvas quadrado do molde ele sairia bem menor, sem necessidade. A duração dos três
atos (`LG_Q_MONTA` · `LG_Q_TRACO` · `LG_Q_BATE`, hoje 26 · 34 · 20) também não é a da casa:
`LG_Q_MONTA` é derivado pelo gerador do maior atraso de partícula e muda com a altura.

`tools/gera-logo.py` roda o mesmo render do AppIcon (`tools/app-icon-render.swift`, compartilhado
com `tools/make-app-icon.sh`), mede a caixa do **escudo**, recorta ele e a auréola em volta, e
cola o conjunto centrado num canvas 34×40 com **2 px de margem** — a margem não é enfeite: o halo
e o traço só existem em volta do que está dentro do canvas, e onde o desenho encosta na borda eles
somem. A largura sai da razão real do símbolo medida na sonda (0,825). A **auréola** é a novidade:
2 px do fundo do ícone recortados junto com o escudo, seguindo a forma dele. Não é enfeite — é o
contraste dela que dá volume; sem ela o escudo claro fica chapado contra o preto do terminal. Como
ela é desenho e não vazio, a distância do escudo à borda subiu de 3 para 4 px (2 de auréola + 2 de
vazio), e o vazio que sobra basta para o halo (1 px) e o traço. Medido na máscara publicada:
canvas 34×40, desenho 30×35, escudo 26×31, vazio 2/3/2/2. O fragmento embutido no instalador traz
a máscara (`.` vazio · `b` auréola · `s` escudo · `r` raio), as trajetórias e **`LG_RGB`, a cor
real de cada pixel do render** (1 360 entradas, 15,1 KiB); o runtime só monta os escapes uma vez,
em `lg_init`. Esta parte **diverge do molde**: lá o gradiente é calculado por LINHA, o que basta
para a casa chapada do haos; aqui a aproximação por linha borra o raio e engrossa a auréola num
verde chapado (medido: erro médio de 18,6 por canal, máximo de 155). A cor por pixel custa 15 KiB
no script; o custo em tempo não foi isolado (a medição do gradiente por linha foi feita com a
máquina sob carga e não é comparável), e o total medido está bem dentro do teto de 8 s. O
**pisca** da batida acompanha: o raio é verde e pisca em branco `236,242,248` — o inverso do que
estava no ar, porque o raio deixou de ser o elemento claro.

Quatro atos: cada pixel do desenho voa de fora da tela e assenta, de baixo para cima
(constelação); a caneta branca contorna a silhueta — que com auréola é a borda dela, a que se vê —
e se retrai por posição de arco; o escudo **bate como um coração** — tum-tum, pausa — e a cada
batida **o raio pisca em branco**, voltando ao verde entre elas; e assenta com o raio verde
parado. Medido num pty de 80×40 com a máquina em repouso (2026-09-01, 7 execuções): mediana
**5,51 s**, faixa 5,47–5,54 — 823 partículas em 26 quadros de constelação.
Abaixo de `LG_LINHAS + 1` linhas de tela a animação não roda: o laço sobe `LG_LINHAS` a cada
quadro e, numa tela mais baixa, o salto é grampeado no topo e os quadros escorregam. Medido:
21 linhas anima, 20 cai para o quadro único.

Degrada em três eixos (TTY · NO_COLOR · UTF-8): sem animação = um quadro parado; sem cor/UTF-8
= só o título. Para ver sem instalar nada: **`./tools/ui-demo.sh`** (`--no-anim` para um quadro
estático, `--logo` só a abertura, `--quadro N` um quadro isolado). Para escolher entre desenhos,
**`--comparar [ref]`** roda a abertura do commit indicado, espera um Enter e roda a de hoje —
nesta ordem, para o desenho novo ser o que fica parado na tela no fim
(padrão: `ed44a8e`, o ícone inteiro em 40×40 com cor por pixel; `d5a68a3` é o escudo em 34×40,
também com cor por pixel). Cada uma roda num processo à parte, e o motivo é o inverso do que
parece: o perigo não são as variáveis que a versão antiga tem a mais, e sim `LG_MIN_LINHAS`,
`LG_FGP` e `LG_BGP`, que existem só na de hoje e sobreviveriam a um `source` da antiga. Entre as
duas o script **não limpa a tela**: o `clear` do macOS apaga o buffer de rolagem, e a primeira
sumiria antes da segunda aparecer.

No gate: **S14** exige as bordas da máscara vazias (o caso extremo: desenho colado na borda) e
confere que o render respeita a máscara, além do snapshot; **S15** exige que o bloco `GERADO` no
instalador seja byte a byte a saída do gerador — é ela, e não a S14, que garante a margem
publicada: um bloco gerado com outra margem reprova. No gerador, `conferir()` exige que a folga
entregue seja ao menos a margem pedida nos quatro lados. **S17** roda uma reexecução num pty com animação e exige que o passo de sucesso (código 100) não apareça com `✖` nem com `(exit 100)`. **S16** roda a abertura num terminal de
**256 cores** (sem `COLORTERM`, que é o Terminal.app de fábrica) e com o `/bin/bash` 3.2 do
macOS: S14 sempre pediu truecolor e por isso nunca tocava esse ramo, onde um `printf -v` com
alvo indexado — que o bash 3.2 recusa — deixava o gradiente inteiro vazio e imprimia erro na
tela do usuário. Mudou o ícone? `./tools/gera-logo.py > /tmp/frag` e cole entre o marcador
`GERADO` e a linha `LG_HY=(` do instalador (`--medir` imprime as dimensões e o custo do
primeiro ato).

## Fecho — o relatório do molde da casa

Como o `relatorio_final` do `haos-install.sh`: título com o tempo na mesma linha ("Feito até
aqui · concluído em 43s" ou "Nada a fazer — tudo já estava no lugar"), caixa do que ficou
instalado (✔ serviço com a versão lida de `/v1/version`, ✔ app, ✔ configuração; `gum` se
houver, texto puro se não), o **norte** — "O River Bridge está na sua barra de menus", e o app
é aberto sozinho (`--no-open` desliga) —, o aviso de que a proteção do UDR7 nasce em ensaio,
e o caminho do relatório desta execução.

## Cercas no gate (`tools/gate.sh`)

S11 sintaxe em bash 3.2 + `--help` pelo cano sob locale C (ASCII puro) · S12 contrato 0 → 100 →
`kickstart` com código novo → download por `file://` (stubs de brew/launchctl, sem root, sem
rede) · S13 dry-run pelo cano sai 0 e não escreve nada · S14 abertura (bordas da máscara vazias · render × máscara · snapshot) · S15 o bloco `GERADO`
é idêntico à saída de `tools/gera-logo.py` · **S18** canal release por `file://` em cinco rodadas
(app pronto do zip com sha conferido e `fonte=release` → reexecução 100 → sha do zip adulterado
sai 3 sem app → release inexistente cai para main com aviso e `fonte=main` → sha do tarball
adulterado sai 3 sem extrair), refutada em 2026-09-02 com uma mutação por rodada (pino do tarball
desligado; sha do zip não conferido; fallback trocado por morte; `cmp` do app removido; `fonte`
mentindo `main`) · **S19** `tools/release.sh --check` sai 0 na árvore e 3 citando `pyproject.toml`
num mutante em 9.9.9 (refutada trocando o `pyproject` da lista pelo `CHANGELOG`) · **S9/S10** o
desinstalador sai instalado em `$PREFIX/scripts` e a cópia instalada remove tudo, inclusive a si
(refutadas em 2026-09-02) · **S20** reexecução num pty de **40 colunas** com animação: todo
quadro do spinner cabe na largura (refutada removendo o corte do rótulo em `ui_spin`). Nasceu do
rastro `│ ⠋ sudo scripts/install.sh…│ ⠙ sudo…` visto no Terminal do Mac mini em 2026-09-02: a
S17 roda em 100 colunas e era cega a janelas estreitas. A causa de fundo era `tput cols` dentro
de `$( )` com o stderr redirecionado — sem terminal para consultar, devolve o padrão 80 — e o
mesmo padrão alimentava a régua, os cabeçalhos de fase e a guarda de tamanho da abertura; agora
todos leem por `ui_cols`/`ui_lines` (via `/dev/tty`).

Também de 2026-09-02, sem cena refutável sem root: `scripts/install.sh` passa a deixar
`$PREFIX/etc` com o dono do serviço (antes era do root, e o daemon não conseguia gravar o
`bridge.env.bak` ao salvar Ajustes — todo PUT de configuração morria em 500 no mini), inclusive
na reexecução, para consertar instalações antigas.
