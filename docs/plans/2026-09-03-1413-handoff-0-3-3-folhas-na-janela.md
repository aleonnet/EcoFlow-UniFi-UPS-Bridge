---
status: aceito
---

# Handoff — 0.3.3: folhas de dispositivo dentro da janela — 2026-09-03 14:13

Substitui `2026-09-03-1730-handoff-dispositivos-por-instancia.md` (o estado 0.3.0–0.3.2 mora lá).

## Estado (medido ao escrever)

| Item | Valor |
|---|---|
| `origin/main` | `f634e3c` (0.3.3 = `52eb8cf` + revisão fria `f634e3c`) |
| Release | `v0.3.3` publicada (`tools/release.sh --no-gate v0.3.3`; assets e SHA256SUMS conferidos) |
| Gate declarada | 52 cenas verdes + S15 do logo vermelha (B17, conhecida) — `tools/gate.sh`, log `gate-c19` da sessão |
| `swift test` | 54 verdes |
| Revisão fria do diff | 2 rodadas (`roadworthy:cold-reviewer`): rodada 1 REJECTED (CHANGELOG incompleto, comentários com somas contraditórias, testes dependentes do idioma vivo, comentário do ArmingRow); rodada 2 REJECTED só pelo teste do nome em inglês faltante — corrigido em `f634e3c` (`defaultNamesCoverBothLanguages`). Sem terceira rodada por ordem do dono ("termina logo") |
| Mac mini | continua em 0.2.0 (medição da 0.3.x pelo dono; decisão `2026-09-03-1700-dispositivos-por-instancia.md` segue `proposto`) |
| MacBook do dono | 0.3.2 instalada pelo one-liner às 13:20; a 0.3.3 chega reexecutando o mesmo comando do README |

## O que a 0.3.3 corrige (fatos medidos em 2026-09-03, CGWindowList + captura)

- `hostSize` medido na ScrollView de Ajustes mentia: 563,5 numa janela de 414 (linhas largas do 1º desenho empurravam a rolagem além da janela e realimentavam). Agora `GeometryReader` raiz em `SettingsView` (espaço oferecido): 414/600/1000 medidos.
- Folha com `.frame(min/ideal/max)`: o macOS a dimensiona pelo conteúdo (470 pt em janelas de 414 e de 600) e ignora a largura ideal. Quadro FIXO `.frame(width:height:)` com `DeviceSheetMetrics.size(host:)`: folha 374×380 em janela 414×512 (moldura), 560×556 em 600×700, 600×640 em 1000×880 — contida nas três (`fotografar.sh` da sessão: VAZA no build defeituoso, CONTIDA depois).
- `estreito` decidido pela largura REAL medida dentro da folha (parâmetro do closure do corpo de `DeviceSheetFrame`); corte 560 fixado por captura (420 quebrava o rótulo da chave).
- Linha do comando no molde `pickerRow`; `ArmingRow` empilha; folha ancora no topo; nome sugerido por idioma; instalador: frase "código já estava extraído deste download".

## Lacunas declaradas

- O seletor de comando a 414 pt ficou sob o rodapé na captura rolada (rótulo e legenda inteiros); rolar a folha sem tomar o foco não funcionou.
- Redimensionar a janela-mãe com a folha aberta não foi medido.
- Duas vezes hoje teclas do dono entraram no app de teste ao ativá-lo para captura. Regra: NUNCA `activate`; capturar por id de janela (`screencapture -l`), cópia de ensaio em `/private/tmp` com outro bundle id, lançada com `--abrir-painel`.

## Próximo passo

1. Dono: reexecutar o one-liner no MacBook e conferir as folhas a 414 pt; depois a medição da 0.3.x no Mac mini (bloco da seção 5 da decisão) — a decisão vira `aceito`.
2. Backlog: B16/B17 e o menu de contexto para remover continuam em `docs/BACKLOG_20260901.md`.

## Prompt para colar

> Retome pelo handoff `docs/plans/2026-09-03-1413-handoff-0-3-3-folhas-na-janela.md`. Estado: 0.3.3 publicada (`f634e3c`). Próximo passo: [medição no mini colada aqui / defeito visto na 0.3.3 com captura].
