// Settings (UI-3): edits go through PUT /v1/config — the daemon validates
// with the same allowlist as its .env parser; the UI never touches the file.
// Hot keys apply live; the rest arms the "Reiniciar serviço" button (202).

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

    var body: some View {
        Form {
            Section("Alarmes") {
                Stepper("Queda de energia: \(powerLossDelay) s", value: $powerLossDelay, in: 0...600)
                Stepper("Energia restaurada: \(restoreDelay) s", value: $restoreDelay, in: 0...600)
                Stepper("Comunicação perdida: \(commLossDelay) s", value: $commLossDelay, in: 0...600)
                LabeledContent("Bateria baixa: \(lowBattery)%") {
                    Slider(value: Binding(
                        get: { Double(lowBattery) },
                        set: { lowBattery = Int($0) }
                    ), in: 5...50, step: 1)
                    .frame(width: 180)
                }
            }
            Section("Coleta") {
                Stepper("Intervalo de leitura: \(pollInterval) s", value: $pollInterval, in: 1...60)
            }
            Section {
                HStack {
                    Button("Salvar alterações") { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                    if restartRequired {
                        Button("Reiniciar serviço") { Task { await restart() } }
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
            } footer: {
                Text("Valores fora de faixa são recusados pelo serviço — a mesma validação do arquivo de configuração.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(4)
        .task { await loadCurrent() }
    }

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
