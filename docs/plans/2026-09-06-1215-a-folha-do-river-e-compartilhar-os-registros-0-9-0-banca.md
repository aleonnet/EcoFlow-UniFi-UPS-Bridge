# Revisão fria do plano da 0.9.0 (a folha do River, o cartão da proteção, Compartilhar… os registros)

status: aceito
data: 2026-09-06
plano: `2026-09-06-1215-a-folha-do-river-e-compartilhar-os-registros-0-9-0.md`

Revisor: agente `cold-reviewer` (Roadworthy), só leitura, sobre o plano e o repositório; duas rodadas.

## Rodada 1 — REJECTED

Bloqueadores (todos de levantamento meu; a classe do que faltou: função inteira + fixture aberto, não a linha que confirma a hipótese):

- **B1** — o plano dizia que `armado_nao_verificado` significa "ainda sem uma queda real". O código (`src/river_unifi_bridge/protect.py:573-575`, `:577-586`, `:631`) devolve `enviado` só enquanto `_latched and _sent_this_outage` e, na restauração, `_reset_outage()` zera os dois: o estado **volta** a `armado_nao_verificado` depois de uma queda real. A frase nova seria tão falsa quanto "alcance não verificado". Correção: etiqueta "Armada" sem frase extra; o histórico fica na linha "último: …".
- **B2** — a varredura de "arquivo do serviço" classificou `SettingsView.swift:327-328` como comentário; é uma dica de tela (`.comDica` → `.help`, `SettingsRows.swift:249-256`). Correção: entra na lista de textos a mudar.
- **B3** — nenhum fixture de health carrega o estado armado (`health_udr7.json` está em `fonte_nao_real`/`dry_run`); a captura proposta não provaria nada. Correção: fixture novo `health_armado.json` com contrato.

Avisos incorporados: W1 (grau de certeza do tipo 23 declarado), W2 (`.get` na publicação — `test_nut_publicacao.py:19-22` monta `TOMADAS` sem as chaves novas), W3 (`NSSharingServicePicker` depois do pacote pronto; `ShareLink` exige o item no desenho), W4 (`runbook-host-ssh.md:49` e o mapa `docs/README.md`), W5 (a ficha é o middleware `auth`, `api.py:179-186`; `_authorize` é a cadeia do `PUT /v1/config`). Notas: `SettingsView.swift:173` é `GeometryReader`+`onChange`; regra do `lock_open` explicitada.

## Rodada 2 — APPROVED

Zero bloqueadores. Verificado pelo revisor: B1 (descrição do estado exata; nada no plano deriva histórico do estado), B2 (11 acertos do grep, todos classificados certo), B3 (o par `SharedState.set_plugins` → `health()` publica o fixture tal qual; o Swift decodifica `DeviceDetail` com os campos). Dois avisos mecânicos aplicados no ato: a linha do `api.py` ainda citava `_authorize`; o fixture ganha `source`, `last_event`, `alcance_modelo`, `alcance_em` para a captura mostrar o cartão inteiro. Duas notas registradas no plano.

## Confirmação

O veredito amarrado ao nome do plano está em `~/.claude/plans/leia-todo-o-c-digo-prancy-sundae.review.md` (`round: 2`, `VERDICT: APPROVED`, linha `owner:`). Aprovação do dono: 2026-09-06, pelo ExitPlanMode do Claude Code.
