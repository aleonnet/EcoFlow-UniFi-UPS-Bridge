---
status: proposto
---

# Dispositivos protegidos por instância (0.3.0) — 2026-09-03

Plano aprovado: `~/.claude/plans/este-foi-o-prompt-binary-sedgewick.md` (banca
`plan-sha256 5435643bc1a65ba63f8afbe25b9a6dea44892753ea2ecbdbbb0331c10554dbe4`, APPROVED). Este
registro nasce `proposto` e vira `aceito` quando o bloco da seção 5 (medição no Mac mini) estiver
colado com os comandos rodados no ato.

## 1. O que muda para quem usa

Até a 0.2.0 o app mostrava uma lista fixa com um único dispositivo (o UDR7), configurado por 17
chaves planas no `.env`. A partir da 0.3.0:

- Em **Ajustes → Dispositivos protegidos**, "Adicionar dispositivo…" abre uma folha em duas
  etapas: o **tipo** (Console UniFi (UDR7) ou Computador ou servidor via SSH) e o formulário do
  tipo, com nome sugerido único. A lista mostra N instâncias com ícone do tipo, nome, estado,
  interruptor e chevron para a folha.
- Cada instância tem folha própria (nome, armamento, máquina e chave, limiares; o host SSH tem
  ainda o comando de desligamento, de lista fechada), cartão em **Saúde**, chip nos **Eventos** e
  entrada na legenda do gráfico. Remover é pelo rodapé da folha, com confirmação; armada, não remove.
- O **número de série esperado** e o **corte físico** do River saem da folha do dispositivo e vão
  para **Ajustes → River**: são fatos do UPS, um só para todas as instâncias.
- O UDR7 que já está no Mac mini **continua funcionando sem nenhuma edição manual**: vira a
  instância `udr7` no primeiro boot.

## 2. Decisões (as 16 do plano, ratificadas pela aprovação)

| # | Decisão |
|---|---|
| D1 | Instâncias em `<RUB_STATE_DIR>/devices.json` (0600, escrita atômica; leitura recusa uid/permissão errados). |
| D2 | `devices.json` é a verdade. Das 17 chaves do bloco 6, 14 viram **espelho** da instância `udr7`; o boot **nunca** escreve o `.env`; PUTs (legado ou `/v1/devices/udr7`) gravam nos dois. Divergência no boot → `devices.json` vence, com `legacy_key_shadowed` no log (nomes, nunca valores). |
| D3 | Trava `UDR7_ARM_ALLOWED` continua **global e somente arquivo**; o **ensaio é por instância**, padrão ligado. |
| D4 | `protect.py` não se move; nenhuma das 7 âncoras do gate muda de texto; `ProtectionConfig.shutdown_command` entra nos pinos. |
| D5 | Registro de tipos **estático em código** (`TYPES = {"udr7_ssh", "ssh_host"}`); tipos novos não ganham chave no `.env`. |
| D6 | Eventos por tipo (`UDR7_*`, `SSH_HOST_*`); toda ação leva `device` e `device_name`; coluna `device` no histórico (ALTER idempotente). |
| D7 | Comando do host SSH em **lista fechada** (8 comandos, cada um com fonte); argv em lista, `--` antes do destino, nunca shell local. |
| D8 | Ids gerados pelo daemon (`sshhost_<8 hex>`), imutáveis; a instância migrada tem id literal `udr7` e os três arquivos de estado de hoje, byte a byte. |
| D9 | Nome único (strip + casefold): 409 `nome_duplicado`; o app avisa antes; `uniqueLabels` (ordinal) para estados vindos de fora. |
| D10 | PUT legado `UDR7_*`/`PROTECT_*` em `/v1/config` **aceito e redirecionado** à instância `udr7` nesta release (o app 0.2.0 precisa desarmar durante a atualização). Remoção: B18. |
| D11 | App contra serviço sem `/v1/devices`: linha cinza "rode o instalador" e "Adicionar…" desabilitado. |
| D12 | Instalador **recusa atualizar** (sai 3, sem kickstart, sem tocar no plist) com `*_armed.json` presente. |
| D13 | Sem flag `secret` (a chave é um caminho; a cerca é o arquivo 0600). `DELETE /v1/devices/udr7` permitido quando desarmado. |
| D14 | Rótulos "Console UniFi (UDR7)" / "Computador ou servidor via SSH"; nomes sugeridos "UDR7", "Servidor SSH", "Servidor SSH 2"…; remover só pela folha. |
| D15 | Versão **0.3.0**. |
| D16 | Série esperada e corte físico do River são do **núcleo** (`CORE_FROZEN_KEYS`, congeladas com qualquer instância armada); `from_instance` os lê do `cfg` para toda instância. |

## 3. Matriz de compatibilidade

| Combinação | O que acontece |
|---|---|
| daemon 0.3.0 + app 0.3.0 | tudo da seção 1 |
| daemon 0.3.0 + app 0.2.0 | o app segue lendo o alias `udr7`/`udr7_detail` do health e escrevendo `PUT /v1/config` com `UDR7_*`/`PROTECT_*`; o daemon traduz para a instância `udr7` e espelha no `.env` (D10) |
| daemon 0.2.0 + app 0.3.0 | `GET /v1/devices` → 404 → linha cinza e "Adicionar…" desabilitado (D11); Saúde e eventos pelo alias |
| voltar do 0.3.0 para o 0.2.0 (`--release v0.2.0`) | o `.env` está fiel à instância `udr7` (todo PUT espelhou); instâncias além dela ficam sem proteção até voltar à 0.3.0; `devices.json` fica intacto |

## 4. O que foi medido nesta máquina (sessão de 2026-09-03)

Comandos rodados no ato, nesta sessão, na árvore em `main`:

| Comando | Resultado |
|---|---|
| `.venv/bin/pytest` (C1–C7) | `274 passed` |
| `cd macos/RiverBridge && swift test` (após C12) | `Test run with 53 tests in 0 suites passed` |
| `tools/gate.sh` (após C9, C10, C11, C12) | 42 `[OK]` em cada rodada; única falha `S15 logo` (render não determinístico do ícone, B17, presente também no HEAD anterior à frente) |
| `tools/gate.sh` (após C13, com a S9b) | 43 `[OK]`; só a S15 |
| revisão fria do diff C9–C13 (2026-09-03) | 1 BLOCKER (guarda pré-atualização na fase do plist, depois de o código já ter sido trocado) e 3 avisos, corrigidos; segunda rodada: APPROVED; S9b reescrita (código e plist intactos sob armado; reinício na rodada seguinte) e refutada com a guarda desligada (S9b vermelha: rc 0, código trocado, rodada seguinte 100 sem reinício); cenas S8/S9/S9b/S9d isoladas: `FALHAS=0` |
| `tools/release.sh --check` (após C13) | `[OK] release --check: v0.3.0 consistente nos 6 arquivos e no CHANGELOG` |
| refutações (mutante vermelho, restaurado) | S4p, S4q, S4r, S4s, S4t, S4u, S4v, S4w, S4l (motor), fonte de `ssh_host` sem `subprocess`, `chipsFollowInstances`, `fieldKeysMatchTheDaemonCatalogPerType`, `chipMatchesEventsByOwnerAndFallsBackToTheOnlyOneOfItsType` |
| capturas lidas contra o defeito (1000 e 414 pt) | lista com três instâncias; folha do UDR7 (edição) e a 414×480; lista de tipos; formulário novo (UDR7 e host SSH); recusa `armado` no rodapé; folha do host a 414×480; Saúde por instância; sete chips com o do UDR7 ligado; legenda e callout por instância |

## 5. Medição no Mac mini (a colar em C14, pelo dono)

Antes (0.2.0): cópia do `.env` e do diretório de estado; `shasum -a 256` de `bridge.env` e dos
`udr7_*`; `GET /v1/version|health|config` guardados.

Depois (0.3.0, pelo one-liner do README): `/v1/version` = `0.3.0`; `health.udr7` igual ao de
antes e `udr7_detail == plugins[0].detail`; `/v1/devices` com uma instância `udr7` cujos campos
batem com o `config` de antes; `shasum -c` do `.env` e dos `udr7_*` OK (intocados);
`devices.json` 0600 do usuário do serviço; `devices_migrated` **uma** vez no log; após
`kickstart`, ainda uma vez e `devices.json` igual; `PRAGMA table_info(events)` mostra `device`;
o app 0.3.0 lista o UDR7; adicionar um host SSH de teste em **ensaio**; ver o chip novo e a
folha; remover o host.

## 6. Reversibilidade

C1–C13 revertem sozinhos (commits `eb33479`…). O ponto de não retorno é o **primeiro boot da
0.3.0 no mini** (migração), e volta-se com `--release v0.2.0` sem cópia manual (seção 3).

## Confirmação

Fica `proposto` até a seção 5 estar preenchida com os comandos e saídas do mini.
