// Settings (UI-3): edits go through PUT /v1/config — the daemon validates
// with the same allowlist as its .env parser; the UI never touches the file.
// Restyled in the app's own language (owner 2026-08-31: the stock form card
// clashed with everything else): eyebrow sections, glass groups, hover.

import RiverBridgeCore
import SwiftUI

struct SettingsView: View {
    var store: TelemetryStore

    // Placeholders match the daemon's researched defaults (config.py) until
    // loadCurrent() replaces them with the live values.
    @State private var powerLossDelay = 6
    @State private var restoreDelay = 0
    @State private var commLossDelay = 15
    @State private var lowBattery = 30
    @State private var pollInterval = 2
    @State private var retentionDays = 7
    @State private var loaded = false
    @State private var feedback: String?
    @State private var notice: String?
    @State private var restartRequired = false
    @State private var saveTask: Task<Void, Never>?
    @State private var showClearDialog = false
    @State private var showClearDatePick = false
    @State private var clearBefore = Date.now
    @State private var prefs = AppPrefs.shared

    // Fase 3'-EXP — UDR7 protection (explicit Save: text fields must never PUT
    // half-typed values; the daemon freezes these keys while armed).
    @State private var protectEnabled = false
    @State private var dryRun = true
    @State private var armAllowed = false
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUser = "root"
    @State private var sshKey = ""
    @State private var expectedSerial = ""
    @State private var wolMac = ""
    @State private var cutoff = 0
    @State private var shutdown = 0
    @State private var dischargeSecPerPct = "0"
    @State private var runtimeMinutes = "0"
    @State private var minOutage = "0"
    @State private var confirmSeconds = "6"
    @State private var protectionBaseline: [String: String] = [:]
    @State private var protectionFeedback: String?
    @State private var protectionNotice: String?
    @State private var showDisarmDialog = false

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // HIG: steppers are for SMALL ranges; for a large range with a
                // handful of sensible values, a picker fits mouse AND finger
                // (developer.apple.com/design/human-interface-guidelines/steppers).
                group(L10n.t("Aparência e idioma", "Appearance & language")) {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.lefthalf.filled")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("Tema", "Theme"))
                            .font(.system(.body, design: .rounded))
                            .fixedSize()
                        Spacer()
                        Picker("", selection: Bindable(prefs).themeMode) {
                            Text(L10n.t("Automático", "Auto")).tag(AppPrefs.ThemeMode.auto)
                            Text(L10n.t("Claro", "Light")).tag(AppPrefs.ThemeMode.light)
                            Text(L10n.t("Escuro", "Dark")).tag(AppPrefs.ThemeMode.dark)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    divider
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("Idioma", "Language"))
                            .font(.system(.body, design: .rounded))
                            .fixedSize()
                        Spacer()
                        Picker("", selection: Bindable(prefs).language) {
                            Text(L10n.t("Sistema", "System")).tag(AppPrefs.Language.system)
                            Text("Português (BR)").tag(AppPrefs.Language.ptBR)
                            Text("English (US)").tag(AppPrefs.Language.enUS)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                group(L10n.t("Alarmes", "Alarms")) {
                    presetRow("bolt.slash.fill", L10n.t("Queda de energia", "Power loss"),
                              value: $powerLossDelay, presets: [0, 3, 6, 10, 30, 60])
                    divider
                    presetRow("bolt.badge.checkmark.fill", L10n.t("Energia restaurada", "Power restored"),
                              value: $restoreDelay, presets: [0, 5, 10, 30, 60])
                    divider
                    presetRow("antenna.radiowaves.left.and.right.slash", L10n.t("Comunicação perdida", "Comm lost"),
                              value: $commLossDelay, presets: [5, 15, 30, 60, 300])
                    divider
                    sliderRow("battery.25percent", L10n.t("Bateria baixa", "Low battery"),
                              value: $lowBattery, range: 5...50, unit: "%")
                }

                group(L10n.t("Coleta", "Sampling")) {
                    presetRow("timer", L10n.t("Intervalo de leitura", "Poll interval"),
                              value: $pollInterval, presets: [1, 2, 5, 10, 30, 60])
                }

                group(L10n.t("Histórico", "History")) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("Manter histórico", "Keep history"))
                            .font(.system(.body, design: .rounded))
                            .fixedSize()
                        Spacer()
                        Picker("", selection: $retentionDays) {
                            Text(L10n.t("7 dias", "7 days")).tag(7)
                            Text(L10n.t("30 dias", "30 days")).tag(30)
                            Text(L10n.t("90 dias", "90 days")).tag(90)
                            Text(L10n.t("1 ano", "1 year")).tag(365)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    divider
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("Eventos gravados", "Stored events"))
                            .font(.system(.body, design: .rounded))
                            .fixedSize()
                        Spacer()
                        // HIG destructive-in-a-list: red TEXT, not a filled
                        // block (the solid capsule clashed — owner's print).
                        Button(role: .destructive) {
                            showClearDialog = true
                        } label: {
                            Text(L10n.t("Limpar eventos…", "Clear events…"))
                                .foregroundStyle(.red)
                                .frame(minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                }

                group(L10n.t("Proteção do UDR7 (experimental)", "UDR7 protection (experimental)")) {
                    toggleRow("shield.lefthalf.filled", L10n.t("Proteger o UDR7", "Protect the UDR7"), $protectEnabled)
                    divider
                    HStack(spacing: 10) {
                        Image(systemName: dryRun ? "theatermasks.fill" : "bolt.shield.fill")
                            .frame(width: 26)
                            .foregroundStyle(dryRun ? Color.secondary : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dryRun ? L10n.t("Modo ensaio", "Rehearsal mode") : L10n.t("ARMADA — desliga o console de verdade", "ARMED — really shuts the console down"))
                                .font(.system(.body, design: .rounded))
                                .fixedSize()
                            Text(armAllowed
                                 ? L10n.t("Trava aberta (UDR7_ARM_ALLOWED=1). Feche-a no arquivo do serviço depois de armar.",
                                          "Lock open (UDR7_ARM_ALLOWED=1). Close it in the service file after arming.")
                                 : L10n.t("Trava fechada: para armar, UDR7_ARM_ALLOWED=1 no arquivo do serviço e reinicie.",
                                          "Lock closed: to arm, set UDR7_ARM_ALLOWED=1 in the service file and restart."))
                                .font(.caption)
                                .foregroundStyle(armAllowed ? Color.orange : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if dryRun {
                            Button(role: .destructive) {
                                showDisarmDialog = true
                            } label: {
                                Text(L10n.t("Desligar modo ensaio…", "Turn rehearsal off…"))
                                    .foregroundStyle(armAllowed && protectEnabled ? Color.red : Color.secondary)
                                    .frame(minHeight: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .disabled(!armAllowed || !protectEnabled)
                        } else {
                            Button(L10n.t("Ligar modo ensaio", "Turn rehearsal on")) {
                                Task { await setDryRun(true) }   // disarm: always accepted
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    divider
                    textRow("network", L10n.t("Console (host)", "Console (host)"), $sshHost, placeholder: "192.168.1.1")
                    divider
                    textRow("number", L10n.t("Porta SSH", "SSH port"), $sshPort, placeholder: "22", numeric: true)
                    divider
                    textRow("person.fill", L10n.t("Usuário SSH", "SSH user"), $sshUser, placeholder: "root")
                    divider
                    textRow("key.fill", L10n.t("Chave privada (caminho absoluto)", "Private key (absolute path)"), $sshKey,
                            placeholder: "/Users/…/.ssh/river-bridge-udr7")
                    divider
                    textRow("barcode", L10n.t("Serial do River (upsc device.serial)", "River serial (upsc device.serial)"),
                            $expectedSerial, placeholder: "R3P…")
                    divider
                    sliderRow("battery.0percent", L10n.t("Corte físico do River", "River physical cutoff"),
                              value: $cutoff, range: 0...48, unit: "%",
                              zeroLabel: L10n.t("não configurado", "not set"))
                    divider
                    sliderRow("power.circle", L10n.t("Desligar o console em", "Shut the console down at"),
                              value: $shutdown, range: 0...50, unit: "%",
                              zeroLabel: L10n.t("não configurado", "not set"))
                    divider
                    textRow("stopwatch", L10n.t("Descarga medida (s por 1 %)", "Measured discharge (s per 1 %)"),
                            $dischargeSecPerPct, placeholder: "0", numeric: true)
                    divider
                    textRow("clock", L10n.t("Ou autonomia ≤ (min, 0 = desligado)", "Or runtime ≤ (min, 0 = off)"),
                            $runtimeMinutes, placeholder: "0", numeric: true)
                    divider
                    textRow("hourglass", L10n.t("Queda mínima (s)", "Minimum outage (s)"), $minOutage, placeholder: "0", numeric: true)
                    divider
                    textRow("checkmark.seal", L10n.t("Confirmar por (s)", "Confirm for (s)"), $confirmSeconds, placeholder: "6", numeric: true)
                    divider
                    textRow("wake", L10n.t("MAC para religar (WoL, opcional)", "Wake MAC (WoL, optional)"), $wolMac,
                            placeholder: "aa:bb:cc:dd:ee:ff")
                    divider
                    HStack(spacing: 12) {
                        if let protectionFeedback {
                            Label(protectionFeedback, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let protectionNotice {
                            Label(protectionNotice, systemImage: "checkmark.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.t("Salvar proteção", "Save protection")) { Task { await saveProtection() } }
                            .buttonStyle(.glassProminent)
                            .tint(accent)
                            .disabled(protectionChanges().isEmpty)
                    }
                }

                // Auto-save is SILENT on success (macOS/iOS settings
                // convention — owner 2026-08-31): only errors and the
                // pending-restart action ever appear here.
                if restartRequired || feedback != nil || notice != nil {
                    HStack(spacing: 12) {
                        if restartRequired {
                            Button(L10n.t("Reiniciar serviço para aplicar", "Restart service to apply")) { Task { await restart() } }
                                .buttonStyle(.glass)
                                .tint(.orange)
                        }
                        Spacer()
                        if let feedback {
                            Label(feedback, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .contentTransition(.opacity)
                        } else if let notice {
                            Label(notice, systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                    }
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .task { await loadCurrent() }
        // Turning rehearsal OFF is the one destructive act on this screen: it
        // is a Button + confirmation (never a Toggle bound to state, which would
        // PUT before the person confirms). The PUT carries ONLY this key.
        .confirmationDialog(L10n.t("Desligar o modo ensaio e ARMAR a proteção?", "Turn rehearsal off and ARM the protection?"),
                            isPresented: $showDisarmDialog, titleVisibility: .visible) {
            Button(L10n.t("Armar — pode desligar o UDR7 numa queda", "Arm — may shut the UDR7 down in an outage"), role: .destructive) {
                Task { await setDryRun(false) }
            }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("O serviço só arma com a trava aberta, leitura corrente do River registrado e fonte não sintética. Siga o runbook (docs/UDR7_PROTECAO_SSH_20260901.md).",
                        "The service only arms with the lock open, a current reading from the registered River and a non-synthetic source. Follow the runbook (docs/UDR7_PROTECAO_SSH_20260901.md)."))
        }
        // Auto-save (owner 2026-08-31): every change PUTs after a short
        // debounce — no save button, like System Settings. All keys on this
        // screen are hot-reload; the daemon still validates every value.
        // Exception (Fase 3'-EXP): the protection group saves explicitly —
        // its text fields would otherwise PUT half-typed hosts and serials.
        // Clearing follows the owner's ask ("anteriores a uma data"): scoped,
        // destructive, always confirmed; a bare "delete all" needs the
        // explicit Tudo choice. The daemon refuses DELETE without `to`.
        .confirmationDialog(L10n.t("Limpar eventos gravados?", "Clear stored events?"),
                            isPresented: $showClearDialog,
                            titleVisibility: .visible) {
            Button(L10n.t("Anteriores a 7 dias", "Older than 7 days"), role: .destructive) {
                Task { await clearEvents(to: Int(Date.now.addingTimeInterval(-7 * 86400).timeIntervalSince1970)) }
            }
            Button(L10n.t("Anteriores a 30 dias", "Older than 30 days"), role: .destructive) {
                Task { await clearEvents(to: Int(Date.now.addingTimeInterval(-30 * 86400).timeIntervalSince1970)) }
            }
            Button(L10n.t("Anteriores a uma data…", "Older than a date…")) { showClearDatePick = true }
            Button(L10n.t("Tudo", "Everything"), role: .destructive) {
                Task { await clearEvents(to: Int(Date.now.timeIntervalSince1970)) }
            }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("Remove eventos do log do serviço. As métricas do gráfico não são afetadas.",
                        "Removes events from the service log. Chart metrics are not affected."))
        }
        .sheet(isPresented: $showClearDatePick) {
            VStack(spacing: 14) {
                Text(L10n.t("Apagar eventos anteriores a…", "Delete events older than…"))
                    .font(.system(.headline, design: .rounded))
                DatePicker("", selection: $clearBefore, in: ...Date.now,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Button(L10n.t("Cancelar", "Cancel")) { showClearDatePick = false }
                    Spacer()
                    Button(L10n.t("Apagar", "Delete"), role: .destructive) {
                        showClearDatePick = false
                        let cutoff = Int(Calendar.current.startOfDay(for: clearBefore).timeIntervalSince1970) - 1
                        Task { await clearEvents(to: cutoff) }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                }
            }
            .padding(20)
            .frame(width: 340)
        }
        .onChange(of: [powerLossDelay, restoreDelay, commLossDelay, lowBattery, pollInterval, retentionDays]) {
            guard loaded else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                await save()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            guard loaded else { return }   // never write defaults over an unloaded config
            Task { await save() }
        }
    }

    // MARK: - Building blocks in the house language

    private var divider: some View {
        Divider().padding(.leading, 46)
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow()
            // No hover on big containers — hover belongs to interactive
            // elements only (owner 2026-08-31, print do bloco aceso).
            VStack(spacing: 8) { content() }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                // Material, NOT glassEffect: neighbouring glass shapes merge
                // their backdrop into a gray wash when the window is key
                // (measured 2026-08-31). House grammar: glass is for the
                // CONTROL layer; content panels sit on material.
        }
    }

    /// HIG-fit for mouse AND finger: a menu picker over sensible presets
    /// (values anchored in the SOTA research). A custom value already in the
    /// .env stays selectable — it joins the list instead of vanishing.
    private func presetRow(_ symbol: String, _ label: String,
                           value: Binding<Int>, presets: [Int]) -> some View {
        let options = presets.contains(value.wrappedValue)
            ? presets
            : (presets + [value.wrappedValue]).sorted()
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize()
            Spacer()
            Picker("", selection: value) {
                ForEach(options, id: \.self) { v in
                    Text("\(v) s").tag(v)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func toggleRow(_ symbol: String, _ label: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize()
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func textRow(_ symbol: String, _ label: String, _ text: Binding<String>,
                         placeholder: String, numeric: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: numeric ? .monospaced : .default))
                .multilineTextAlignment(numeric ? .trailing : .leading)
                .frame(minWidth: numeric ? 70 : 150, maxWidth: numeric ? 90 : 260)
                .autocorrectionDisabled()
        }
    }

    private func sliderRow(_ symbol: String, _ label: String,
                           value: Binding<Int>, range: ClosedRange<Int>, unit: String,
                           zeroLabel: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            // The LABEL never wraps (owner's print at min width) — the
            // slider is the flexible element, with a floor that keeps it
            // usable for both pointer and finger (native Slider = the HIG
            // control for continuous ranges on every input).
            Text(label)
                .font(.system(.body, design: .rounded))
                .fixedSize()
            Spacer(minLength: 8)
            Text(value.wrappedValue == 0 && zeroLabel != nil ? zeroLabel! : "\(value.wrappedValue)\(unit)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            .tint(accent)
            .frame(minWidth: 90, maxWidth: 170)
        }
        .animation(.snappy(duration: 0.2), value: value.wrappedValue)
    }

    // MARK: - IO (unchanged contract: everything via the daemon's API)

    private func loadCurrent() async {
        guard !loaded, let endpoint = ApiEndpoint.discover() else { return }
        guard let response = try? await APIClient(endpoint: endpoint).config() else { return }
        let cfg = response.config
        powerLossDelay = cfg["power_loss_delay_seconds"]?.intValue ?? powerLossDelay
        restoreDelay = cfg["restore_delay_seconds"]?.intValue ?? restoreDelay
        commLossDelay = cfg["comm_loss_delay_seconds"]?.intValue ?? commLossDelay
        lowBattery = cfg["low_battery_percent"]?.intValue ?? lowBattery
        pollInterval = cfg["poll_interval_seconds"]?.intValue ?? pollInterval
        retentionDays = cfg["history_retention_days"]?.intValue ?? retentionDays
        protectEnabled = cfg["protect_udr7"]?.boolValue ?? protectEnabled
        dryRun = cfg["protect_dry_run"]?.boolValue ?? dryRun
        armAllowed = cfg["udr7_arm_allowed"]?.boolValue ?? armAllowed
        sshHost = cfg["udr7_ssh_host"]?.stringValue ?? sshHost
        sshPort = cfg["udr7_ssh_port"]?.stringValue ?? sshPort
        sshUser = cfg["udr7_ssh_user"]?.stringValue ?? sshUser
        sshKey = cfg["udr7_ssh_key"]?.stringValue ?? sshKey
        expectedSerial = cfg["udr7_expected_serial"]?.stringValue ?? expectedSerial
        wolMac = cfg["udr7_wol_mac"]?.stringValue ?? wolMac
        cutoff = cfg["udr7_cutoff_percent"]?.intValue ?? cutoff
        shutdown = cfg["udr7_shutdown_percent"]?.intValue ?? shutdown
        dischargeSecPerPct = cfg["udr7_discharge_seconds_per_pct"]?.stringValue ?? dischargeSecPerPct
        runtimeMinutes = cfg["udr7_runtime_minutes"]?.stringValue ?? runtimeMinutes
        minOutage = cfg["udr7_min_outage_seconds"]?.stringValue ?? minOutage
        confirmSeconds = cfg["udr7_confirm_seconds"]?.stringValue ?? confirmSeconds
        protectionBaseline = protectionValues()
        loaded = true
    }

    // MARK: - Fase 3'-EXP protection group (explicit save, diff against baseline)

    /// Current form values in .env form. PROTECT_DRY_RUN is deliberately NOT here:
    /// it travels alone, through setDryRun (the daemon's pure-disarm rule).
    private func protectionValues() -> [String: String] {
        [
            "PROTECT_UDR7": protectEnabled ? "1" : "0",
            "UDR7_SSH_HOST": sshHost.trimmingCharacters(in: .whitespaces),
            "UDR7_SSH_PORT": sshPort.trimmingCharacters(in: .whitespaces),
            "UDR7_SSH_USER": sshUser.trimmingCharacters(in: .whitespaces),
            "UDR7_SSH_KEY": sshKey.trimmingCharacters(in: .whitespaces),
            "UDR7_EXPECTED_SERIAL": expectedSerial.trimmingCharacters(in: .whitespaces),
            "UDR7_WOL_MAC": wolMac.trimmingCharacters(in: .whitespaces),
            "UDR7_CUTOFF_PERCENT": String(cutoff),
            "UDR7_SHUTDOWN_PERCENT": String(shutdown),
            "UDR7_DISCHARGE_SECONDS_PER_PCT": dischargeSecPerPct.trimmingCharacters(in: .whitespaces),
            "UDR7_RUNTIME_MINUTES": runtimeMinutes.trimmingCharacters(in: .whitespaces),
            "UDR7_MIN_OUTAGE_SECONDS": minOutage.trimmingCharacters(in: .whitespaces),
            "UDR7_CONFIRM_SECONDS": confirmSeconds.trimmingCharacters(in: .whitespaces),
        ]
    }

    private func protectionChanges() -> [String: String] {
        protectionValues().filter { protectionBaseline[$0.key] != $0.value }
    }

    /// Turns the daemon's refusal into the interface's voice (motivo -> text).
    private func refusalText(_ body: String) -> String {
        struct Refusal: Decodable { var erro: String?; var motivo: String? }
        let parsed = try? JSONDecoder().decode(Refusal.self, from: Data(body.utf8))
        switch parsed?.motivo {
        case "armamento_bloqueado":
            return L10n.t("Trava fechada: UDR7_ARM_ALLOWED=1 no arquivo do serviço e reinicie.",
                          "Lock closed: set UDR7_ARM_ALLOWED=1 in the service file and restart.")
        case "armado":
            return L10n.t("Armada: ligue o modo ensaio antes de mudar estas chaves ou reiniciar.",
                          "Armed: turn rehearsal on before changing these keys or restarting.")
        case "fonte_nao_real":
            return L10n.t("Fonte recusada: a leitura corrente não é do River registrado (serial) ou é sintética.",
                          "Source refused: the current reading is not the registered River (serial) or is synthetic.")
        case "sem_snapshot":
            return L10n.t("Sem leitura corrente do NUT — não há como verificar a fonte.",
                          "No current NUT reading — the source cannot be verified.")
        case "chave_somente_arquivo":
            return L10n.t("Essa chave só muda no arquivo do serviço.", "That key only changes in the service file.")
        default:
            return L10n.t("Recusado: ", "Refused: ") + (parsed?.erro ?? body)
        }
    }

    private func saveProtection() async {
        guard let endpoint = ApiEndpoint.discover() else {
            protectionFeedback = L10n.t("Serviço parado — nada salvo.", "Service down — nothing saved.")
            return
        }
        let changes = protectionChanges()
        guard !changes.isEmpty else { return }
        do {
            let result = try await APIClient(endpoint: endpoint).putConfig(changes)
            protectionBaseline = protectionValues()
            protectionFeedback = nil
            protectionNotice = "\(changes.count) " + L10n.t("chave(s) salva(s).", "key(s) saved.")
            if result.restartRequired { restartRequired = true }
            if let chain = try? await APIClient(endpoint: endpoint).health(),
               let margin = chain.udr7Detail?.marginEstimateS {
                protectionNotice! += " " + L10n.t("Margem estimada ≈ \(margin) s.", "Estimated margin ≈ \(margin) s.")
            }
        } catch let APIError.badStatus(_, body) {
            protectionFeedback = refusalText(body)
        } catch {
            protectionFeedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
        }
    }

    private func setDryRun(_ on: Bool) async {
        guard let endpoint = ApiEndpoint.discover() else {
            protectionFeedback = L10n.t("Serviço parado.", "Service down.")
            return
        }
        do {
            _ = try await APIClient(endpoint: endpoint).putConfig(["PROTECT_DRY_RUN": on ? "1" : "0"])
            dryRun = on
            protectionFeedback = nil
            protectionNotice = on ? L10n.t("Modo ensaio ligado — proteção desarmada.", "Rehearsal on — protection disarmed.")
                                  : L10n.t("Proteção ARMADA. Feche a trava no arquivo do serviço (passo 8 do runbook).",
                                           "Protection ARMED. Close the lock in the service file (runbook step 8).")
        } catch let APIError.badStatus(_, body) {
            protectionFeedback = refusalText(body)
        } catch {
            protectionFeedback = L10n.t("Falha: ", "Failed: ") + error.localizedDescription
        }
    }

    private func clearEvents(to cutoff: Int) async {
        guard let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado — nada removido.", "Service down — nothing removed.")
            return
        }
        do {
            let removed = try await APIClient(endpoint: endpoint).deleteEvents(to: cutoff)
            feedback = nil
            notice = removed == 1 ? L10n.t("1 evento removido.", "1 event removed.") : "\(removed) " + L10n.t("eventos removidos.", "events removed.")
        } catch let APIError.badStatus(_, body) {
            feedback = L10n.t("Recusado: ", "Refused: ") + body
        } catch {
            feedback = L10n.t("Falha ao limpar: ", "Clear failed: ") + error.localizedDescription
        }
    }

    private func save() async {
        guard let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado — nada salvo.", "Service down — nothing saved.")
            return
        }
        let changes = [
            "POWER_LOSS_DELAY_SECONDS": String(powerLossDelay),
            "RESTORE_DELAY_SECONDS": String(restoreDelay),
            "COMM_LOSS_DELAY_SECONDS": String(commLossDelay),
            "LOW_BATTERY_PERCENT": String(lowBattery),
            "POLL_INTERVAL_SECONDS": String(pollInterval),
            "HISTORY_RETENTION_DAYS": String(retentionDays),
        ]
        do {
            let result = try await APIClient(endpoint: endpoint).putConfig(changes)
            restartRequired = result.restartRequired
            feedback = nil   // success is silent; the restart button is the notice
        } catch let APIError.badStatus(_, body) {
            feedback = L10n.t("Recusado: ", "Refused: ") + body
        } catch {
            feedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
        }
    }

    private func restart() async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        do {
            try await APIClient(endpoint: endpoint).restartService()
            feedback = L10n.t("Reinício agendado (202).", "Restart scheduled (202).")
            restartRequired = false
        } catch let APIError.badStatus(_, body) {
            feedback = refusalText(body)   // 409 armado: disarm first, or kickstart from the terminal
        } catch {
            feedback = L10n.t("Falha no reinício: ", "Restart failed: ") + error.localizedDescription
        }
    }
}
