---
status: superado por 2026-09-03-1730-handoff-dispositivos-por-instancia.md
---

# Handoff — programa de frentes (release → prova de alcance) — 2026-09-02 21:50

## Estado (medido agora)

| Repositório | Branch | HEAD | Árvore | Não publicado |
|---|---|---|---|---|
| `EcoFlow-UniFi-UPS-Bridge` | `main` | `06fe959` (+ este handoff) | limpa (só `dist/`, ignorado) | **11 commits** à frente de `origin/main` (`70e2926`) |

- F0 (higiene, Roadworthy no repo, validação medida) e F1 commits 1–4 (desinstalador no
  prefixo; `tools/release.sh`; one-liner consome release; versão 0.2.0) **executados**, cada um
  com `tools/gate.sh` verde (31 → 32 → 33 cenas) e as cercas novas refutadas com `refute.sh`.
- `tools/release.sh --dry-run v0.2.0 --no-gate` montou os três assets em `dist/v0.2.0/`
  (`SHA256SUMS`: zip `d1d07582…`, tarball `ac5758fd…`); nenhuma tag criada, nada publicado.
- **F1 passo 5 (publicar) NÃO executado**: o `git push` é a trava do dono, e o tarball da
  release levaria `login-state.png` (1200×1132, commitado em `f47b32a`, ainda **não** em
  `origin/main`) — decisão do dono antes de publicar (ver "Próximo passo").
- Mac mini: daemon em `f0cd86b` (2 commits de `src/` atrás do HEAD de ontem; 4 arquivos), NUT
  2.8.5 com subdriver EcoFlow no binário, `upsd` parado, porta 3493 do simulador, proteção
  `desabilitado`, ensaio ligado. River não chegou. UDR7: porta 22 fechada, 443 aberta.
- Nada armado. Ratificação do desligamento real do UDR7 segue pendente.

## Onde mora o estado real

- `docs/decisions/2026-09-02-2123-validacao-estado-e-programa-de-frentes.md` — a validação
  medida e o programa F0–F6.
- `docs/decisions/2026-09-02-2124-wifi-do-river-fechado.md` — Wi‑Fi fechado; nuvem e BLE amanhã.
- `~/.claude/plans/este-foi-o-prompt-binary-sedgewick.md` (+ `.banca.md`, APPROVED) — o plano.
- `~/.claude/plans/piped-seeking-toast.md` — plano v2 da prova de alcance (F2), ainda sem banca.
- `.roadworthy/gates` e `.roadworthy/evidence.jsonl` — os gates e a evidência do `close.sh`.
- `CHANGELOG.md` `[0.2.0]` — o que entrou hoje.

## Ler primeiro, nesta ordem

1. `docs/README.md` (mapa).
2. Este arquivo.
3. A decisão de validação (acima).
4. `git log -1 && git status` — o disco vence.

## Próximo passo concreto

1. **Dono decide** sobre `login-state.png` (raiz do repo, 1,3 MB): é a tela de login da conta
   Ubiquiti **com o e-mail pessoal do dono preenchido** (lido na imagem em 2026-09-02). Está
   no commit local `f47b32a`, que ainda não foi publicado — um `git rm` no HEAD **não basta**,
   porque o push levaria o histórico com o arquivo. Recomendação: reescrever os 11 commits
   locais tirando o arquivo antes de qualquer push, por exemplo
   `git filter-branch --index-filter 'git rm --cached --ignore-unmatch login-state.png' origin/main..HEAD`
   (reversível pelo reflog; ato destrutivo por classe, portanto só com o sim do dono), e
   acrescentar `*.png` da raiz ao `.gitignore`. O tarball do `--dry-run` em `dist/v0.2.0/` já
   contém o arquivo e deve ser refeito depois.
2. `git push origin main` (prompt de permissão da sessão).
3. `tools/release.sh v0.2.0` — cria a tag, sobe os três assets, confere pela URL
   `releases/latest/download/SHA256SUMS`.
4. **No mini, pelo dono** (o instalador pede a senha do `sudo` num terminal):
   `curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash -s --`
   Esperado: fase 02 "release v0.2.0: tarball e app pinados", fase 04 "app pronto da release
   v0.2.0", fecho com `código: release v0.2.0`, exit 0; reexecução 100; `xattr -lr
   "~/Applications/River Bridge.app" | grep quarantine` vazio; `open` abre; `/v1/version` = 0.2.0.
   Se o app ad-hoc compilado no MacBook **não abrir** no mini (`Killed: 9`), parar e registrar:
   re-assinar após o `mv` quebra o `cmp` — é decisão de desenho, não remendo.
5. Registrar as medições `[M]` em `docs/decisions/2026-09-0x-HHMM-release-e-one-liner.md`
   (nasce `proposto`, vira `aceito`) e fechar F1 com `close.sh`.
6. Depois: F2 — banca do plano v2 (`cold-reviewer`) e execução; pré-requisito do dono: conta
   local no UDR7 para o daemon.

## Prompt para colar

```
Retome pelo handoff docs/plans/2026-09-02-2150-handoff-programa-de-frentes.md (leia docs/README.md
antes). Estado: F0 e F1 (commits 1–4) executados, gate verde, release v0.2.0 montada em dry-run,
NADA publicado. Decisão minha sobre login-state.png: [REMOVER antes de publicar | PUBLICAR como
está]. Depois: git push, tools/release.sh v0.2.0, e eu rodo o one-liner no mini e colo a saída
aqui. Regras: só [M] com o comando no ato; nada arma a proteção do UDR7.
```
