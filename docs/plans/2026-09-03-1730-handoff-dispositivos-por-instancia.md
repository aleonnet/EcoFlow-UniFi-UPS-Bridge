---
status: aceito
---

# Handoff — dispositivos protegidos por instância (0.3.0) — 2026-09-03 17:30

Substitui `2026-09-02-2150-handoff-programa-de-frentes.md`.

## Estado (medido ao escrever)

| Repositório | Branch | O que está feito | Não publicado |
|---|---|---|---|
| `EcoFlow-UniFi-UPS-Bridge` | `main` | C1–C13 do plano (daemon, app, instalador, docs, versão 0.3.0) | tudo desde `28d2644` (`origin/main`) — o push é do dono |

Gate: 42 cenas verdes em cada rodada desta frente; a S15 do logo fica vermelha por render não
determinístico do ícone (B17), presente também antes da frente. Suíte Python `274 passed`;
Swift `53 tests passed`. Release **não** produzida ainda.

## Onde o estado real mora

- Plano aprovado (com banca): `~/.claude/plans/este-foi-o-prompt-binary-sedgewick.md`.
- Decisões e matriz de compatibilidade: `../decisions/2026-09-03-1700-dispositivos-por-instancia.md` (`proposto` até a medição no mini).
- Contrato da API: `../reference/api-local.md`. Runbooks: `../guides/2026-09-03-1710-…` (UDR7) e `../guides/2026-09-03-1720-…` (host SSH).
- O que ficou: `../BACKLOG_20260901.md` (B18–B22).

## O que a próxima janela lê PRIMEIRO

1. Este arquivo. 2. A seção 5 da decisão (o bloco a medir no mini). 3. `git log --oneline 28d2644..HEAD`.

## Próximo passo concreto (C14)

1. `git push` (prompt de permissão da sessão — trava do dono).
2. `tools/release.sh v0.3.0` (gate, build do app, tag, tarball, zip, SHA256SUMS, `gh release create`).
3. **No Mac mini, pelo dono**: bloco "antes" (cópia do `.env` e do estado, `shasum`, `GET
   /v1/version|health|config`), o one-liner do README, bloco "depois" (seção 5 da decisão).
   Se `*_armed.json` existir, o instalador sai 3 — desarme pelo app antes.
4. Colar as medições na decisão, marcar `aceito`, `close.sh`.

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
