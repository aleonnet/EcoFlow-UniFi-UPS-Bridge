---
status: proposto
data: 2026-09-06
frente: revisão fria do plano `2026-09-06-1800-o-segundo-river-por-bluetooth-0-11-0.md`
---

# Revisão fria do plano da 0.11.0 (o segundo River por Bluetooth)

Revisor: `roadworthy:cold-reviewer` (só leitura; vê o plano e o repositório, não o raciocínio). O arquivo
amarrado pelo nome, com `sections-round1` e o veredito, vive fora de `docs/` por causa da norma de nomes:
`~/.claude/plans/2026-09-06-1800-o-segundo-river-por-bluetooth-0-11-0.review.md`.

## Rodada 1 (2026-09-06, ~18h30) — REJECTED, oito bloqueadores, todos de levantamento meu

| # | O que faltou ler ou medir | Classe |
|---|---|---|
| B1 | `PonteDoNut.atualizar`/`_declarar` só declaram com `snap` e com o River do escritório no ar: um River BLE ativado com o do escritório mudo não entraria no `ups.conf` | função inteira do consumidor (`_declarar` até o `return` cedo) |
| B2 | `recusa_do_vigia_espelho` compara `NUT_UPS` só com o aparelho do River e os ids de plugin: `river-ble-*` ficava fora da cerca | cerca existente não estendida ao nome novo |
| B3 | `mesmo_river` sem fonte quando o NUT nunca respondeu e o `.env` não tem a série esperada | decisão mensurável devolvida como frase |
| B4 | `import eflib.login` puxa `bleak` pelo `eflib/__init__.py`; o venv do gate não o tem | import transitivo não medido no venv |
| B5 | S79 já existe (0.10.1, nascida nesta mesma sessão) | numeração escrita antes do último commit |
| B6 | Scope sem `scripts/**` e `river-bridge-install.sh`, que o `release.sh --check` amarra | escopo copiado do plano anterior |
| B7 | `EventChipSpec.all(devices:)` tem consumidores em `DashboardWindow.swift` e em três testes; `Kind` sem caso para River BLE | grep no repo inteiro por consumidor |
| B8 | Context dizia árvore limpa em 50642d3; havia uma 0.10.1 não commitada (12 arquivos) | estado declarado sem `git status` no ato |

Avisos W1–W3 (nomes de atributo da `eflib` vs. nomes protobuf; o nome do River na frase do evento; o teste de
`mesmo_river` tem de nascer com o `.env` vazio) e notas N1–N5 entram na rodada 2 sem rodada própria.

## Rodada 2 (2026-09-06, ~21h15) — APPROVED

Os oito bloqueadores caíram, cada um conferido no código pelo revisor (função inteira, `git grep` pelos consumidores,
`compileall` da `eflib` embutida, a regex dos eventos sobre ela). Avisos e notas da rodada 1 caíram. Um aviso novo,
aplicado no ato sem rodada: **W4** — a legenda do histograma (`LegendaDeEventos.swift:46-54`) rotula evento sem tipo
de dispositivo sem nome; com dois Rivers BLE as barras ficariam iguais → `chaves(…, rivers:)` e o rótulo pelo
`NomesDosRiversBle` (D7, Changes). Duas notas mecânicas aplicadas: o HEAD ao gravar é `496a3e7` (N6) e a hora do
arquivo da varredura é 18h00 (N7).

O plano segue **`proposto`** até a palavra do dono (as três perguntas abertas são dele, e o River de 127 V chega em
2026-09-07).
