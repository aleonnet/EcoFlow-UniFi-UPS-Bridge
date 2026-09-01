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

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // HIG: steppers are for SMALL ranges; for a large range with a
                // handful of sensible values, a picker fits mouse AND finger
                // (developer.apple.com/design/human-interface-guidelines/steppers).
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
            .padding(.top, 6)
        }
        .task { await loadCurrent() }
        // Auto-save (owner 2026-08-31): every change PUTs after a short
        // debounce — no save button, like System Settings. All keys on this
        // screen are hot-reload; the daemon still validates every value.
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func sliderRow(_ symbol: String, _ label: String,
                           value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
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
            Text("\(value.wrappedValue)\(unit)")
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
        loaded = true
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
        } catch {
            feedback = L10n.t("Falha no reinício: ", "Restart failed: ") + error.localizedDescription
        }
    }
}
