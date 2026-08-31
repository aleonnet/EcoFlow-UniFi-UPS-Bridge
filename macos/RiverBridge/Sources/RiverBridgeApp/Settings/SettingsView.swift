// Settings (UI-3): edits go through PUT /v1/config — the daemon validates
// with the same allowlist as its .env parser; the UI never touches the file.
// Restyled in the app's own language (owner 2026-08-31: the stock form card
// clashed with everything else): eyebrow sections, glass groups, hover.

import RiverBridgeCore
import SwiftUI

struct SettingsView: View {
    var store: TelemetryStore

    @State private var powerLossDelay = 3
    @State private var restoreDelay = 5
    @State private var commLossDelay = 20
    @State private var lowBattery = 15
    @State private var pollInterval = 2
    @State private var loaded = false
    @State private var feedback: String?
    @State private var restartRequired = false
    @State private var saveTask: Task<Void, Never>?

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

                HStack(spacing: 12) {
                    if restartRequired {
                        Button("Reiniciar serviço") { Task { await restart() } }
                            .buttonStyle(.glass)
                            .tint(.orange)
                    }
                    Spacer()
                    if let feedback {
                        Text(feedback)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                }

                Text("As mudanças são salvas automaticamente; valores fora de faixa são recusados pelo serviço — a mesma validação do arquivo de configuração.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        .task { await loadCurrent() }
        // Auto-save (owner 2026-08-31): every change PUTs after a short
        // debounce — no save button, like System Settings. All keys on this
        // screen are hot-reload; the daemon still validates every value.
        .onChange(of: [powerLossDelay, restoreDelay, commLossDelay, lowBattery, pollInterval]) {
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
            VStack(spacing: 8) { content() }
                .padding(14)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hoverLift(glow: accent, scale: 1.004)
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
        loaded = true
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
        ]
        do {
            let result = try await APIClient(endpoint: endpoint).putConfig(changes)
            restartRequired = result.restartRequired
            feedback = result.restartRequired
                ? "Salvo — reinício necessário para aplicar tudo."
                : "Salvo e aplicado."
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
