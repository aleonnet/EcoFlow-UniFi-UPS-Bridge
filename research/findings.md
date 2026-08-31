# research/findings.md — fatos medidos do projeto

Gramática: **[FATO]** = medido com comando no ato · **[CONFIRMAR]** = hipótese com
plano de verificação · **[LIMITE]** = restrição conhecida · **PENDENTE** = ainda não
medido. Nada de inferência sem marca.

## Ambiente (2026-08-31)

- [FATO] Máquina de dev: MacBook Pro M3 Max, macOS 26.6.2 (25G83), arm64; Xcode 26.6
  (17F113), Swift 6.3.3. Comandos: `sw_vers`, `uname -m`, `xcodebuild -version`,
  `swift --version`.
- [FATO] Mac mini alvo responde ping em `192.168.1.13` (2026-08-31, `ping -c1`).
- [FATO] SSH não-interativo ao mini NEGADO para esta máquina
  (`Permission denied (publickey,...)`, BatchMode) — sem chave configurada.
- **PENDENTE (bloqueado em acesso — dono):** `sw_vers`, `uname -m` e
  `sysadminctl -autologin status` no mini. Comando pronto para o dono rodar no mini
  (ou conceder chave SSH):

  ```bash
  sw_vers; uname -m; sysadminctl -autologin status
  ```

  Impacto: deployment target do app (§7A) e premissa de auto-login do LaunchAgent
  `gui/$uid` (§7A.6) ficam abertos até essa medição.
- **PENDENTE (dono):** disponibilidade física do EcoFlow RIVER 3 Plus.
- [FATO] Homebrew publica NUT 2.8.5 (https://formulae.brew.sh/formula/nut, consultado
  2026-08-31) ≥ piso 2.8.4 exigido pelo suporte EcoFlow
  (https://github.com/networkupstools/nut/issues/2735).

## Rede (fonte: ABHOME-rede/ARQUITETURA_20260828.md — doc, CONFIRMAR ao vivo na Fase 1)

- [CONFIRMAR] Mac mini Ethernet `192.168.1.13` (`macmini.home.arpa`), Wi-Fi `.14`.
- [CONFIRMAR] Home Assistant PRODUÇÃO roda em VM VirtualBox `192.168.1.15` DENTRO do
  próprio Mac mini (bridge sobre Ethernet). Relevante: se o mini cair, o HA cai junto —
  a cadeia de alerta de energia (§6) tem o mini como ponto único; registrar no desenho
  da Fase 1.

## Matriz da Fase 0 (§30) — a preencher

| Questão | Resultado | Evidência | Confiança |
|---|---|---|---|
| Protocolo UPS Tower ↔ UniFi | | | |
| Discovery | | | |
| Adoption | | | |
| Authentication | | | |
| Telemetry | | | |
| Alarm transport | | | |
| UPS UI schema | | | |
| Third-party support | | | |
| Emulation viability | | | |
