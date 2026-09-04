# Mapa da documentação — River Bridge

Canônico vivo (sem data no nome: a identidade é o papel). **Primeiro arquivo a abrir ao
retomar trabalho**, conforme a norma de documentação no `~/.claude/CLAUDE.md` global,
seção "Documentação (vale para todos os projetos)".

Nome de documento datado: `aaaa-mm-dd-hhmm-descricao.md`, front matter `status:` com o
vocabulário do MADR 4.0.0 (`proposto | rejeitado | aceito | obsoleto | superado por <arquivo>`).
Revisar é criar arquivo NOVO e marcar o antigo como `superado por` — o antigo fica.

## Gramática de evidência (usada nos documentos desta árvore)

`[P]` primária (a origem: código do fabricante, especificação, medição no aparelho) ·
`[S]` secundária (wiki, gist, blog — **nunca vira `[P]` por repetição**) ·
`[M]` medido no repositório ou no equipamento, com o comando registrado no ato ·
**`[P-estático]`** leitura do código do fabricante **sem execução** (adicionada em 2026-09-02,
depois de uma leitura de código ter sido apresentada como se fosse medição) — **não é `[M]`,
e nunca autoriza dizer que algo funciona** ·
`HIPÓTESE Hnn` (`research/hypotheses.md`) · `PROVISÓRIO-SEM-FONTE` · `ANALOGIA` · `INFERIDO`.

Nenhum número entra num documento sem marca.

## Papéis (Roadworthy, desde 2026-09-02)

Os diretórios por papel estão declarados em `../.roadworthy/docs.json` (vocabulário de
`status:` em português). Os documentos anteriores ficam onde estão; os novos entram no papel.

| Papel | Onde | O que vive lá |
|---|---|---|
| mapa | este arquivo | o primeiro a abrir |
| decisões | `decisions/` | registros datados com Confirmação |
| planos | `plans/` | frentes vivas e handoffs (o handoff mais novo pelo nome é o estado) |
| concluídos | `plans/done/` | planos encerrados, um por linha no `README.md` de lá |
| histórico | `history/` | frentes fechadas, movidas por `close-front.sh` |
| referência | `reference/` | canônicos vivos, sem data no nome |
| guias | `guides/` | runbooks |
| arquivo | `archive/` | fora das checagens, declarado |

Gates da casa: `../.roadworthy/gates`. Checagem da árvore: `docs-check.sh docs --since 2026-09-01`.

## A árvore

| Documento | Status | O que é |
|---|---|---|
| `2026-08-31-2345-pesquisa-udr7-ups-terceiros.md` | aceito | Por que um console UniFi não consome um UPS de terceiros — o veredito que originou a estratégia de agir de fora |
| `2026-09-01-0817-runbook-protecao-udr7-ssh.md` | superado por `guides/2026-09-03-1710-…` | Runbook da proteção do UDR7 na era das 17 chaves planas do `.env` (0.1.0–0.2.0) |
| `2026-09-01-2243-pesquisa-ssh-sota-udr7.md` | superado por `2026-09-02-0105-…` | SSH é o caminho para desligar o UDR7? **A conclusão "API para saber, SSH para agir" está ERRADA** — ver o documento que o supera |
| `2026-09-02-0105-pesquisa-api-local-console-udr7.md` | proposto | A rota de desligamento local do console (a do botão **Shut Down**), medida e lida no aparelho; o que fecha as portas da via nativa; e o que continua sendo premissa |
| `decisions/2026-09-02-2123-validacao-estado-e-programa-de-frentes.md` | aceito | **Validação medida** do repositório e do Mac mini contra os três objetivos do dono; correções de registro; o programa de frentes F0–F6 |
| `decisions/2026-09-02-2124-wifi-do-river-fechado.md` | aceito | Wi‑Fi do River só fala com a nuvem: frente fechada; nuvem-para-visibilidade e BLE viram frentes próprias |
| `plans/2026-09-02-2150-handoff-programa-de-frentes.md` | superado por `plans/2026-09-03-1730-…` | Handoff do programa de frentes (F0 e F1 executados, release 0.2.0) |
| `decisions/2026-09-03-1700-dispositivos-por-instancia.md` | proposto | **Dispositivos protegidos por instância** (0.3.0): as 16 decisões, a matriz de compatibilidade com a 0.2.0, o que foi medido nesta máquina e o bloco a medir no mini |
| `guides/2026-09-03-1710-runbook-protecao-udr7-por-instancia.md` | aceito | **Runbook** da proteção do UDR7 como instância: preparar, medir, armar em 3 passos, desarmar, recuperar, reverter para a 0.2.0 |
| `guides/2026-09-03-1720-runbook-host-ssh.md` | aceito | **Runbook** do tipo "Computador ou servidor via SSH": chave por instância, `known_hosts`, `sudoers`, ensaio e armamento |
| `decisions/2026-09-04-0110-river-3-plus-o-que-o-cabo-entrega.md` | aceito | **O River 3 Plus medido**: o que o cabo entrega e o que não entrega (com o driver do NUT como fonte), a porta serial que traz potência e tomadas, o que aproveitamos do `r3pcomms` (MIT), como o app da EcoFlow mata leitores com root, e os três modos de convivência |
| `decisions/2026-09-04-1130-o-servico-manda-no-river.md` | aceito | **A 0.5.0**: o serviço passa a cuidar do leitor do no-break (e por que), os três atos sobre o aparelho com as cercas de cada um, o que `battery.charge.low` é de verdade (medido no ato) e por que tomada não entra |
| `reference/api-local.md` | — | **Contrato vivo** da API local daemon ↔ app: todas as rotas, inclusive `/v1/devices` e `/v1/device-types` |
| `plans/2026-09-03-1730-handoff-dispositivos-por-instancia.md` | superado por `plans/2026-09-03-1413-…` | Handoff da 0.3.0–0.3.2 (dispositivos por instância, instaladores revistos) |
| `plans/2026-09-03-1413-handoff-0-3-3-folhas-na-janela.md` | superado por `plans/2026-09-04-0140-…` | Handoff da 0.3.3 (folhas contidas na janela) |
| `plans/2026-09-04-0140-handoff-0-4-0-e-frente-do-river.md` | superado por `plans/2026-09-04-1140-…` | **Handoff vivo**: 0.4.0 com os vinte consertos, o River 3 Plus medido no Mac mini, o que está instalado à mão lá, e a frente do River (B30–B41) |
| `plans/2026-09-04-1140-handoff-0-5-0-o-servico-manda-no-river.md` | aceito | **Handoff vivo**: a 0.5.0 entregue, os seis bloqueadores da revisão fria já corrigidos, o que ficou fora com o motivo, e a bancada que falta no Mac mini |
| `API_LOCAL_20260831.md` | superado por `reference/api-local.md` | Contrato da API local até a 0.2.0 (sem as rotas de dispositivos) |
| `INSTALACAO_UMA_LINHA_20260901.md` | — | O instalador em uma linha: contrato 0/100, abertura, fecho |
| `PESQUISA_ARQUITETURA_PLUGINS_20260901.md` | — | Benchmarks da arquitetura de plugins e o parecer que originou a frente |
| `PESQUISA_ECOFLOW_WIFI_20260901.md` | — | O River 3 Plus tem Wi-Fi local? (varredura de fontes) |
| `PESQUISA_PARAMETROS_UPS_20260831.md` | — | De onde vem cada parâmetro de tempo e limiar |
| `BACKLOG_20260901.md` | — | Dívidas e limites declarados, com o motivo de cada um |
| `BANCA_PLANO_20260831.md` | — | Registro das bancas do plano (encerradas em 2026-08-31) |

Os documentos sem `status:` são anteriores à adoção da norma (2026-09-01) e mantêm o nome
antigo; ganham o padrão quando forem revisados — revisão cria arquivo novo, não renomeia.

## Fora desta árvore

- `../RIVER3PLUS_UNIFI_BRIDGE_SPEC_20260831.md` — a especificação do sistema
- `../research/hypotheses.md` — as hipóteses numeradas (H11a, H13, H14, H16…)
- `../research/findings.md` — o que foi medido e fechado
- `../CHANGELOG.md` — o que mudou, por versão
- `../_archive/` — versões pré-correção, mantidas pelo mesmo princípio do `superado por`

## Verificação de links

```bash
lychee --offline --root-dir . docs/
```
