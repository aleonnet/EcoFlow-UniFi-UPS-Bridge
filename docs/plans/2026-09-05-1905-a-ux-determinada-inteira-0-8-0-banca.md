# Revisão fria do plano 2026-09-05-1905-a-ux-determinada-inteira-0-8-0.md

status: aceito
data: 2026-09-05

Cópia canônica da revisão (`~/.claude/plans/leia-todo-o-c-digo-prancy-sundae.banca.md`), amarrada ao plano pelo nome.

```
plan: leia-todo-o-c-digo-prancy-sundae.md
round: 2
sections-round1: Context | Risk band | Decisões (D) | Impact sweep (commands run now) | Changes, per file | Scope | Acceptance (EARS) | Ordem de commits | Bancada no Mac mini (C9, medida por mim, na ordem) | Atos do dono (fora do meu alcance, nomeados) | Verification (after the last commit) | Refutation | Out of scope | Overnight policy | Open questions

Rodada 1 (cold-reviewer, 2026-09-05): REJECTED — B1 gatilho "arquivo que sumiu" apagaria tudo numa atualização; A1–A5; N1–N4. Todos corrigidos no plano.
Rodada 2 (cold-reviewer, 2026-09-05): REJECTED — B2 relançamento de dentro do Lixo não se removia com a segunda condição; B3 `launchctl bootout` desprendido morre com o grupo de processos (launchd.plist(5), AbandonProcessGroup); A6 saídas velhas no impact sweep. Os três corrigidos no plano (gatilho na partida; `start_new_session=True`; linhas velhas apagadas), classificados pelo próprio revisor como correção de uma linha, sem crescer o plano.

Escalação: a contagem de bloqueadores não caiu entre as rodadas (1 → 2); a casa não tem 3.ª rodada. Bloqueadores que não caíram: nenhum permanece aberto no texto do plano; o que resta é a decisão de aceitar as correções da rodada 2 sem uma rodada nova. Alternativa com fonte: nenhuma outra — as duas correções seguem o manual do sistema (launchd.plist(5)) e o próprio defeito medido no Mac mini em 2026-09-05 (serviço vivo de dentro do Lixo).

owner: aprovado em 2026-09-05 pelo dono (AskUserQuestion: "Aprovo o plano com as correções"), aceitando as correções da rodada 2 sem rodada nova.
VERDICT: APPROVED
```
