# research/findings.md — fatos medidos do projeto

Gramática: **[FATO]** = medido com comando no ato · **[CONFIRMAR]** = hipótese com
plano de verificação · **[LIMITE]** = restrição conhecida · **PENDENTE** = ainda não
medido. Nada de inferência sem marca.

## Ambiente (2026-08-31)

- [FATO] Máquina de dev: MacBook Pro M3 Max, macOS 26.6.2 (25G83), arm64; Xcode 26.6
  (17F113), Swift 6.3.3. Comandos: `sw_vers`, `uname -m`, `xcodebuild -version`,
  `swift --version`.
- [FATO] Mac mini alvo responde ping em `192.168.1.13` (2026-08-31, `ping -c1`).
- [FATO] Acesso SSH ao mini: chave `id_ed25519` com passphrase no Keychain, carregada
  com `/usr/bin/ssh-add --apple-load-keychain` (forma documentada em
  `ABHOME-infra/HANDOVER-LLM-HAOS.md:224-225`); alias `macmini.home.arpa`.
- [FATO 2026-08-31, ssh no ato] Mac mini: macOS **26.6.2** (25G83), **arm64** →
  MenuBarExtra disponível; deployment target do app pode igualar o dev (26.x).
- [FATO 2026-08-31] **Auto-login: OFF** (`sysadminctl -autologin status`) → a premissa
  "LaunchAgent gui/$uid sobrevive a reboot" NÃO se sustenta hoje; decisão
  LaunchAgent × LaunchDaemon × habilitar auto-login DEVOLVIDA AO DONO (§7A.6).
  Precedente da casa: a VM do HAOS usa LaunchAgent gui/$uid — mesmo limite.
- [FATO 2026-08-31] Python do mini: 3.9.6 (sistema); brew presente em
  `/opt/homebrew/bin/brew` → instalador (Fase 6a) precisa prover Python ≥ 3.13.
- [FATO 2026-08-31] `pmset -g batt`: "AC Power"; varredura `system_profiler
  SPUSBDataType`: **nenhum device EcoFlow/RIVER conectado** ao mini.
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
