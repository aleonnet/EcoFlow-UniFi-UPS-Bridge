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

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                group("Alarmes") {
                    stepperRow("bolt.slash.fill", "Queda de energia",
                               value: $powerLossDelay, range: 0...600, unit: "s")
                    divider
                    stepperRow("bolt.badge.checkmark.fill", "Energia restaurada",
                               value: $restoreDelay, range: 0...600, unit: "s")
                    divider
                    stepperRow("antenna.radiowaves.left.and.right.slash", "Comunicação perdida",
                               value: $commLossDelay, range: 0...600, unit: "s")
                    divider
                    sliderRow("battery.25percent", "Bateria baixa",
                              value: $lowBattery, range: 5...50, unit: "%")
                }

                group("Coleta") {
                    stepperRow("timer", "Intervalo de leitura",
                               value: $pollInterval, range: 1...60, unit: "s")
                }

                group("Histórico") {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        Text("Manter histórico").font(.system(.body, design: .rounded))
                        Spacer()
                        Picker("", selection: $retentionDays) {
                            Text("7 dias").tag(7)
                            Text("30 dias").tag(30)
                            Text("90 dias").tag(90)
                            Text("1 ano").tag(365)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    divider
                    HStack(spacing: 10) {
                        Image(systemName: "trash")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        Text("Eventos gravados").font(.system(.body, design: .rounded))
                        Spacer()
                        Button("Limpar eventos…", role: .destructive) {
                            showClearDialog = true
                        }
                        .buttonStyle(.glass)
                        .tint(.red)
                    }
                }

                // Auto-save is SILENT on success (macOS/iOS settings
                // convention — owner 2026-08-31): only errors and the
                // pending-restart action ever appear here.
                if restartRequired || feedback != nil || notice != nil {
                    HStack(spacing: 12) {
                        if restartRequired {
                            Button("Reiniciar serviço para aplicar") { Task { await restart() } }
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
        .confirmationDialog("Limpar eventos gravados?", isPresented: $showClearDialog,
                            titleVisibility: .visible) {
            Button("Anteriores a 7 dias", role: .destructive) {
                Task { await clearEvents(to: Int(Date.now.addingTimeInterval(-7 * 86400).timeIntervalSince1970)) }
            }
            Button("Anteriores a 30 dias", role: .destructive) {
                Task { await clearEvents(to: Int(Date.now.addingTimeInterval(-30 * 86400).timeIntervalSince1970)) }
            }
            Button("Anteriores a uma data…") { showClearDatePick = true }
            Button("Tudo", role: .destructive) {
                Task { await clearEvents(to: Int(Date.now.timeIntervalSince1970)) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Remove eventos do log do serviço. As métricas do gráfico não são afetadas.")
        }
        .sheet(isPresented: $showClearDatePick) {
            VStack(spacing: 14) {
                Text("Apagar eventos anteriores a…")
                    .font(.system(.headline, design: .rounded))
                DatePicker("", selection: $clearBefore, in: ...Date.now,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Button("Cancelar") { showClearDatePick = false }
                    Spacer()
                    Button("Apagar", role: .destructive) {
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

    private func stepperRow(_ symbol: String, _ label: String,
                            value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(label).font(.system(.body, design: .rounded))
            Spacer()
            Text("\(value.wrappedValue) \(unit)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
        .animation(.snappy(duration: 0.2), value: value.wrappedValue)
    }

    private func sliderRow(_ symbol: String, _ label: String,
                           value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(label).font(.system(.body, design: .rounded))
            Spacer()
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
            .frame(width: 170)
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
            feedback = "Serviço parado — nada removido."
            return
        }
        do {
            let removed = try await APIClient(endpoint: endpoint).deleteEvents(to: cutoff)
            feedback = nil
            notice = removed == 1 ? "1 evento removido." : "\(removed) eventos removidos."
        } catch let APIError.badStatus(_, body) {
            feedback = "Recusado: \(body)"
        } catch {
            feedback = "Falha ao limpar: \(error.localizedDescription)"
        }
    }

    private func save() async {
        guard let endpoint = ApiEndpoint.discover() else {
            feedback = "Serviço parado — nada salvo."
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
            feedback = "Recusado: \(body)"
        } catch {
            feedback = "Falha ao salvar: \(error.localizedDescription)"
        }
    }

    private func restart() async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        do {
            try await APIClient(endpoint: endpoint).restartService()
            feedback = "Reinício agendado (202)."
            restartRequired = false
        } catch {
            feedback = "Falha no reinício: \(error.localizedDescription)"
        }
    }
}
