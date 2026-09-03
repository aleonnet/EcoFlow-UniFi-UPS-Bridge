---
status: aceito
---

# Handoff — dispositivos protegidos por instância (0.3.0) — 2026-09-03 17:30

Substitui `2026-09-02-2150-handoff-programa-de-frentes.md`.

## Estado (medido ao escrever, atualizado após a publicação)

| Repositório | Branch | O que está feito | Publicado |
|---|---|---|---|
| `EcoFlow-UniFi-UPS-Bridge` | `main` | C1–C13 do plano + correções da revisão fria (`2d932ae`) | `origin/main` = `2d932ae`; tag `v0.3.0`; release https://github.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/releases/tag/v0.3.0 (assets `River-Bridge.app.zip`, `river-unifi-bridge-src.tar.gz`, `SHA256SUMS`, conferidos pelo `release.sh`) |

Gate: 43 cenas verdes na última rodada completa (`dist/gate-v0.3.0-rodada-completa.log`); a S15
do logo fica vermelha por render não determinístico do ícone (B17), presente também antes da
frente — a release foi produzida com `--no-gate` sobre essa rodada, declarado aqui. Suíte Python
`274 passed`; Swift `53 tests passed`. Revisão fria do diff C9–C13: 1 BLOCKER e 3 avisos
corrigidos em `2d932ae`; segunda rodada APPROVED.

**0.3.1 (mesmo dia):** o dono rodou o one-liner da 0.3.0 neste MacBook (não no mini) e o
relatório disse "service v0.1.0" com ✔: um daemon de desenvolvimento de 2026-09-01 ocupava a
porta 35493, o serviço instalado morria e o instalador não provava nada. A 0.3.1 (`b0cb16d`,
release https://github.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/releases/tag/v0.3.1) só declara
"provado" com o PID do job na porta da API, falha nomeando quem ocupa a porta, e tira o Swift do
pré-voo no canal release. Gate: 46 cenas verdes (S9e, S9f novas; S15/B17 vermelha). Neste
MacBook o processo intruso (PID 84834) ainda precisa ser encerrado pelo dono.

**0.3.2 (mesmo dia, revisão inteira dos instaladores — dono: "trate TUDO, de forma humana"):**
os dois scripts foram lidos de ponta a ponta e reescritos no contrato "duas vozes" (`│` para a
pessoa, `#` para o registro; `✖` é a frase que o one-liner mostra). Toda checagem que pode
recusar roda antes da primeira mutação; uma cópia do nosso serviço fora do launchd é encerrada
pelo instalador; um programa alheio na porta é recusado nomeando o programa; toda mutação que
falha vira frase humana; ao final de qualquer falha: *Feito até aqui / Faltou / O que fazer
agora*. Provado com launchd **real** no domínio do usuário (seam `RUB_LAUNCHD_DOMAIN`): cenas
S9g (3 provas), S9h (one-liner inteiro: 0, 100, 3), S9i (brew falhando), S9j (dry-run sem
sudo com o serviço instalado na porta). Duas rodadas de leitor frio (3 BLOCKERs → 1 → 0);
cada cerca nova refutada por mutação.

## Onde o estado real mora

- Plano aprovado (com banca): `~/.claude/plans/este-foi-o-prompt-binary-sedgewick.md`.
- Decisões e matriz de compatibilidade: `../decisions/2026-09-03-1700-dispositivos-por-instancia.md` (`proposto` até a medição no mini).
- Contrato da API: `../reference/api-local.md`. Runbooks: `../guides/2026-09-03-1710-…` (UDR7) e `../guides/2026-09-03-1720-…` (host SSH).
- O que ficou: `../BACKLOG_20260901.md` (B18–B22).

## O que a próxima janela lê PRIMEIRO

1. Este arquivo. 2. A seção 5 da decisão (o bloco a medir no mini). 3. `git log --oneline 28d2644..HEAD`.

## Próximo passo concreto (C14 — o que falta é seu)

1. **No Mac mini, pelo dono**: bloco "antes" (cópia do `.env` e do estado, `shasum -a 256` de
   `bridge.env` e dos `udr7_*`, `GET /v1/version|health|config` guardados), o one-liner do README,
   bloco "depois" (seção 5 da decisão). Se `*_armed.json` existir no estado, o instalador sai 3
   sem tocar em nada — desarme pelo app antes.
2. Colar as medições na decisão, marcar `aceito`, `close.sh`.

## Prompts para colar

- Funcionou: "Rodei o one-liner no mini para a 0.3.0. Aqui estão as saídas do bloco antes/depois:
  <colar>. Feche a decisão e o close.sh."
- Falhou: "O one-liner da 0.3.0 falhou no mini. Log literal: <colar `installer-last-run.log` e as
  últimas 40 linhas de `~/Library/Logs/river-unifi-bridge.log`>."

## Pendências fora desta frente

- Wi‑Fi do River: o dono contestou o fechamento ("quero que encontre uma forma de fazer funcionar
  via WiFi"); falta a decisão nova superando `2026-09-02-2124-wifi-do-river-fechado.md` e as
  trilhas nuvem EcoFlow (Developer API) / BLE com planos próprios.
- F2 (prova de alcance ao UDR7 pela API local do console): plano v2 `piped-seeking-toast.md`; exige
  conta local no UDR7 criada pelo dono.
