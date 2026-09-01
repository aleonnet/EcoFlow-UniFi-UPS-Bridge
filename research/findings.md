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

## Matriz da Fase 0 (§30) — preenchida com o que a pesquisa documental respondeu (2026-09-01)

Gramática deste arquivo: **[CONFIRMAR]** = hipótese com plano de verificação · **PENDENTE** =
não medido. Nada abaixo foi medido no console; é o que a documentação pública e a comunidade
responderam (docs/PESQUISA_UDR7_UPS_TERCEIROS_20260831.md; research/unifi-official.md;
research/hypotheses.md). A Fase 3'-EXP (proteção via SSH) **não depende** desta matriz.

| Questão | Resultado | Evidência | Confiança |
|---|---|---|---|
| Protocolo UPS Tower ↔ UniFi | PENDENTE — não documentado publicamente (H01/H02/H03 UNKNOWN) | unifi-official.md (blog: "instant adoption", NUT só UPS→terceiros) | baixa |
| Discovery | PENDENTE — "instant adoption" sem detalhe de transporte | blog oficial (unifi-official.md) | baixa |
| Adoption | PENDENTE — adoção 1-clique de device UniFi; identidade não documentada (H04/H05) | reviews em unifi-official.md | baixa |
| Authentication | PENDENTE — nenhuma fonte descreve o mecanismo | — | nenhuma |
| Telemetry | [CONFIRMAR] só visível no controlador para device adotado (H07 ↑) | reviews (unifi-official.md:150-160) | média (doc), não medida |
| Alarm transport | PENDENTE — sem documentação pública (H08) | — | nenhuma |
| UPS UI schema | PENDENTE — painel mostra bateria/carga/runtime/firmware/IP/MAC; schema não público | reviews em unifi-official.md | baixa |
| Third-party support | **não documentado**: console não consome UPS de terceiros (NUT do UPS Tower é servidor, não cliente; feature request aberta; H10 ↓) | PESQUISA_UDR7_UPS_TERCEIROS_20260831.md; E0-B em hypotheses.md | média (ausência em fontes oficiais e comunidade), não é prova |
| Emulation viability | PENDENTE — sem emulador público do tipo UPS; exigiria reverso (H06 ↓) | hypotheses.md H06 | baixa |

- [FATO 2026-09-01] `ssh -G` com o argv da proteção: `stricthostkeychecking true`, sem linha `proxycommand` com `ProxyCommand=none`; destino malicioso após `--` → rc 255 (OpenSSH_10.3p1, LibreSSL 3.3.6). Comando: `/usr/bin/ssh -G -n -T -F /dev/null -o BatchMode=yes -o ConnectTimeout=15 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/private/var/folders/cx/svf_z53x1yv_x5tqqb8fjjh00000gn/T/pytest-of-alessandro/pytest-78/test_ssh_G_reflects_argv0/state/udr7_known_hosts -o GlobalKnownHostsFile=/dev/null -o ProxyCommand=none -o PermitLocalCommand=no -o ControlMaster=no -o ControlPath=none -o ForwardAgent=no -o ClearAllForwardings=yes -o LogLevel=ERROR -i /private/var/folders/cx/svf_z53x1yv_x5tqqb8fjjh00000gn/T/pytest-of-alessandro/pytest-78/test_ssh_G_reflects_argv0/river-bridge-udr7 -p 2222 -- root@192.0.2.1 ubnt-systool poweroff` (tests/unit/test_protect.py).
