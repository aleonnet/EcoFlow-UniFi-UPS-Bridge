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
    /// Só o que a LISTA precisa: qual folha está aberta, o override enquanto um
    /// PUT está em voo, e o dispositivo cuja confirmação de armar está na tela.
    /// Dev seam: `--seam-plugin udr7` já abre a folha desse dispositivo, para a
    /// captura conseguir fotografá-la (molde: DashboardWindow.initialSection).
    @State private var openPlugin: DevicePluginDescriptor? = {
        guard let id = AppPrefs.seamValue("--seam-plugin") else { return nil }
        return DevicePluginRegistry.plugin(id: id)
    }()
    @State private var optimistic: [String: Bool] = [:]
    @State private var pendingArm: DevicePluginDescriptor?
    @State private var devicesFeedback: String?
    @State private var hostSize: CGSize = CGSize(width: 1000, height: 880)

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // HIG: steppers are for SMALL ranges; for a large range with a
                // handful of sensible values, a picker fits mouse AND finger
                // (developer.apple.com/design/human-interface-guidelines/steppers).
                SettingsRows.group(L10n.t("Aparência e idioma", "Appearance & language")) {
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
                    SettingsRows.divider
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

                SettingsRows.group(L10n.t("Alarmes", "Alarms")) {
                    SettingsRows.presetRow("bolt.slash.fill", L10n.t("Queda de energia", "Power loss"),
                              value: $powerLossDelay, presets: [0, 3, 6, 10, 30, 60])
                    SettingsRows.divider
                    SettingsRows.presetRow("bolt.badge.checkmark.fill", L10n.t("Energia restaurada", "Power restored"),
                              value: $restoreDelay, presets: [0, 5, 10, 30, 60])
                    SettingsRows.divider
                    SettingsRows.presetRow("antenna.radiowaves.left.and.right.slash", L10n.t("Comunicação perdida", "Comm lost"),
                              value: $commLossDelay, presets: [5, 15, 30, 60, 300])
                    SettingsRows.divider
                    SettingsRows.sliderRow("battery.25percent", L10n.t("Bateria baixa", "Low battery"),
                              value: $lowBattery, range: 5...50, unit: "%", accent: accent)
                }

                SettingsRows.group(L10n.t("Coleta", "Sampling")) {
                    SettingsRows.presetRow("timer", L10n.t("Intervalo de leitura", "Poll interval"),
                              value: $pollInterval, presets: [1, 2, 5, 10, 30, 60])
                }

                SettingsRows.group(L10n.t("Histórico", "History")) {
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
                    SettingsRows.divider
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

                SettingsRows.group(L10n.t("Dispositivos protegidos", "Protected devices")) {
                    ForEach(Array(DevicePluginRegistry.all.enumerated()), id: \.element.id) { indice, plugin in
                        if indice > 0 { SettingsRows.divider }
                        deviceRow(plugin)
                    }
                }

                // Auto-save is SILENT on success (macOS/iOS settings
                // convention — owner 2026-08-31): only errors and the
                // pending-restart action ever appear here.
                if restartRequired || feedback != nil || notice != nil || devicesFeedback != nil {
                    HStack(spacing: 12) {
                        if restartRequired {
                            Button(L10n.t("Reiniciar serviço para aplicar", "Restart service to apply")) { Task { await restart() } }
                                .buttonStyle(.glass)
                                .tint(.orange)
                        }
                        Spacer()
                        if let devicesFeedback {
                            Label(devicesFeedback, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        } else if let feedback {
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
        // A largura da JANELA-MÃE, medida aqui: a folha é NSWindow própria, então
        // medir dentro dela seria circular. Molde: DashboardWindow.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { hostSize = $0 }
        .sheet(item: $openPlugin) { item in
            if let ui = DevicePluginUIRegistry.plugin(id: item.id) {
                ui.settingsSheet(store: store, hostSize: hostSize) { openPlugin = nil }
            }
        }
        // `isPresented` DERIVADO de pendingArm: cancelar ou Esc zera o estado
        // pelo próprio binding, sem sobrar um booleano fantasma ligado.
        .confirmationDialog(
            pendingArm.map { ArmConfirmation(name: store.deviceNames.name(for: $0),
                                             mode: .enableWithRehearsalOff).title } ?? "",
            isPresented: Binding(get: { pendingArm != nil },
                                 set: { if !$0 { pendingArm = nil } }),
            titleVisibility: .visible, presenting: pendingArm
        ) { item in
            let arming = ArmConfirmation(name: store.deviceNames.name(for: item),
                                         mode: .enableWithRehearsalOff)
            Button(arming.confirmLabel, role: .destructive) {
                Task { await putEnable(item, on: true) }
            }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: { item in
            Text(ArmConfirmation(name: store.deviceNames.name(for: item),
                                 mode: .enableWithRehearsalOff).message)
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

    // MARK: - Dispositivos protegidos

    /// Uma linha por dispositivo do registro: ícone, o nome que o usuário deu,
    /// o estado, o interruptor e o chevron que abre a folha.
    ///
    /// O interruptor tem UMA fonte de verdade — o health. Com `store.health` nil
    /// (serviço parado, ou antes do primeiro poll) a linha fica desligada e
    /// desabilitada, em vez de inventar um segundo lugar de onde ler. O override
    /// `optimistic` existe SÓ enquanto o PUT está em voo e é ele próprio o
    /// marcador de "em voo" — nada de um `inFlight` paralelo para dessincronizar.
    @ViewBuilder
    private func deviceRow(_ plugin: DevicePluginDescriptor) -> some View {
        let detail = store.health?.pluginDetail(id: plugin.id)
        let ligado = optimistic[plugin.id] ?? (detail?.enabled ?? false)
        let badge = DevicePluginUIRegistry.plugin(id: plugin.id)?.badge(state: detail?.state)
        HStack(spacing: 10) {
            Image(systemName: plugin.symbol)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Button {
                openPlugin = plugin
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.deviceNames.name(for: plugin))
                            .font(.system(.body, design: .rounded))
                        if let badge {
                            Text(badge.0).font(.caption).foregroundStyle(badge.1)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Toggle("", isOn: Binding(
                get: { ligado },
                set: { novo in Task { await toggleDevice(plugin, on: novo) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(store.health == nil || optimistic[plugin.id] != nil)
        }
    }

    /// Ligar com o ensaio DESLIGADO (ou desconhecido) arma de verdade: pede
    /// confirmação e NÃO escreve nada antes dela. Desligar é desarme puro —
    /// sempre aceito pelo daemon — e vai direto, de forma otimista.
    private func toggleDevice(_ plugin: DevicePluginDescriptor, on: Bool) async {
        let dryRun = store.health?.pluginDetail(id: plugin.id)?.dryRun
        if DevicePluginRegistry.toggleNeedsConfirmation(on: on, dryRun: dryRun) {
            pendingArm = plugin
            return
        }
        await putEnable(plugin, on: on)
    }

    private func putEnable(_ plugin: DevicePluginDescriptor, on: Bool) async {
        guard let endpoint = ApiEndpoint.discover() else {
            devicesFeedback = L10n.t("Serviço parado — nada mudou.", "Service down — nothing changed.")
            return
        }
        optimistic[plugin.id] = on
        do {
            _ = try await APIClient(endpoint: endpoint).putConfig([plugin.enableKey: on ? "1" : "0"])
            devicesFeedback = nil
            // Atualiza o health ANTES de limpar o override: limpar primeiro faria
            // o `get` voltar ao health velho e o interruptor piscar ao contrário.
            await store.refreshHealth()
        } catch let APIError.badStatus(_, body) {
            devicesFeedback = ProtectionRefusal.text(body)
        } catch {
            devicesFeedback = L10n.t("Falha: ", "Failed: ") + error.localizedDescription
        }
        optimistic[plugin.id] = nil
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
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)   // 409 armado: disarm first, or kickstart from the terminal
        } catch {
            feedback = L10n.t("Falha no reinício: ", "Restart failed: ") + error.localizedDescription
        }
    }
}
