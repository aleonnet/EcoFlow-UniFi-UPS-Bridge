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

    // Dispositivos protegidos por INSTÂNCIA (2026-09-03). Só o que a LISTA
    // precisa: qual folha está aberta (nova ou de uma instância), o override
    // enquanto um PUT está em voo, e a instância cuja confirmação de armar está
    // na tela. Dev seam: `--seam-folha <id>` abre a folha dessa instância e
    // `--seam-folha novo:<tipo>` a folha de um dispositivo novo desse tipo, para
    // a captura fotografá-las (molde: DashboardWindow.initialSection).
    @State private var seamSheet: String? = AppPrefs.seamValue("--seam-folha")
    @State private var openSheet: DeviceSheetMode?
    @State private var showAdd = false
    @State private var addInitialType: DeviceTypeDescriptor?
    /// A instância recém-criada, acesa por ~1,2 s ao voltar da folha (o mesmo
    /// brilho do hoverLift): a pessoa vê ONDE a linha nova entrou.
    @State private var highlightID: String?
    @State private var optimistic: [String: Bool] = [:]
    @State private var pendingArm: DeviceInstance?
    @State private var devicesFeedback: String?
    @State private var hostSize: CGSize = CGSize(width: 1000, height: 880)
    // As duas chaves do River que são do NÚCLEO, não de instância nenhuma (D16):
    // salvas explicitamente (texto), nunca pelo auto-save dos presets.
    @State private var expectedSerial = ""
    @State private var cutoff = 0
    @State private var riverBaseline: [String: String] = [:]

    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    var body: some View {
        // A largura da JANELA-MÃE vem de um GeometryReader, que mede o espaço
        // OFERECIDO. Medir na própria rolagem mentia: a 414 pt ela media 563,5,
        // empurrada por linhas largas desenhadas com a largura inicial, e a folha
        // "cabia" em 523 e vazava da janela (medido em 2026-09-03).
        GeometryReader { geo in
            conteudo.onChange(of: geo.size, initial: true) { hostSize = geo.size }
        }
    }

    private var conteudo: some View {
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

                SettingsRows.group(L10n.t("River", "River")) {
                    SettingsRows.textRow("barcode", L10n.t("Número de série esperado (upsc device.serial)", "Expected serial (upsc device.serial)"),
                                         $expectedSerial, placeholder: "R3P…", estreito: DeviceSheetMetrics.isNarrow(width: hostSize.width))
                    SettingsRows.divider
                    SettingsRows.sliderRow("battery.0percent", L10n.t("Corte físico da saída", "Physical output cutoff"),
                                           value: $cutoff, range: 0...48, unit: "%",
                                           zeroLabel: L10n.t("não configurado", "not set"), accent: accent,
                                           estreito: DeviceSheetMetrics.isNarrow(width: hostSize.width))
                    if riverChanged {
                        HStack {
                            Text(L10n.t("Vale para todos os dispositivos protegidos.", "Applies to every protected device."))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.t("Salvar", "Save")) { Task { await saveRiver() } }
                                .buttonStyle(.glassProminent).tint(accent)
                        }
                    }
                }

                SettingsRows.group(L10n.t("Dispositivos protegidos", "Protected devices")) {
                    if case .unsupported(let why) = store.deviceSupport {
                        Text(L10n.t("O serviço instalado (\(why)) não gerencia dispositivos — rode o instalador para atualizar.",
                                    "The installed service (\(why)) does not manage devices — run the installer to update."))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if store.devices.isEmpty {
                        Text(L10n.t("Nenhum dispositivo protegido.", "No protected devices."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(Array(store.devices.enumerated()), id: \.element.id) { indice, instance in
                        if indice > 0 { SettingsRows.divider }
                        deviceRow(instance)
                    }
                    if !store.devices.isEmpty { SettingsRows.divider }
                    addRow
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
        .task {
            // "novo…" não depende de rede: aplica antes das chamadas ao serviço
            // (medido em 2026-09-03: a primeira chamada pode levar segundos e a
            // captura fotografava a tela sem a folha). Os ids esperam a lista.
            applySeamSheet()
            await loadCurrent()
            await store.refreshDevices()
            applySeamSheet()
        }
        .onChange(of: store.devices) { applySeamSheet() }
        .sheet(item: $openSheet) { item in
            if let type = item.type, let ui = DevicePluginUIRegistry.plugin(typeID: type.id) {
                ui.settingsSheet(mode: item, store: store, hostSize: hostSize, onBack: nil) { _ in openSheet = nil }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddDeviceSheet(store: store, hostSize: hostSize, initialType: addInitialType) { created in
                showAdd = false
                addInitialType = nil
                if let created { highlight(created) }
            }
        }
        // `isPresented` DERIVADO de pendingArm: cancelar ou Esc zera o estado
        // pelo próprio binding, sem sobrar um booleano fantasma ligado.
        .confirmationDialog(
            pendingArm.map { ArmConfirmation(name: deviceName($0), mode: .enableWithRehearsalOff).title } ?? "",
            isPresented: Binding(get: { pendingArm != nil },
                                 set: { if !$0 { pendingArm = nil } }),
            titleVisibility: .visible, presenting: pendingArm
        ) { item in
            let arming = ArmConfirmation(name: deviceName(item), mode: .enableWithRehearsalOff)
            Button(arming.confirmLabel, role: .destructive) {
                Task { await putEnable(item, on: true) }
            }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: { item in
            Text(ArmConfirmation(name: deviceName(item), mode: .enableWithRehearsalOff).message)
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

    private func deviceName(_ instance: DeviceInstance) -> String {
        store.deviceNames.name(forDevice: instance.id, type: DeviceTypeRegistry.type(id: instance.type))
    }

    /// O seam `--seam-folha` só pode abrir a folha depois de a lista existir;
    /// aplica-se uma vez, na primeira carga que a satisfaz.
    private func applySeamSheet() {
        guard let seam = seamSheet else { return }
        if seam == "novo" {
            showAdd = true; seamSheet = nil
        } else if seam.hasPrefix("novo:"), let type = DeviceTypeRegistry.type(id: String(seam.dropFirst(5))) {
            addInitialType = type; showAdd = true; seamSheet = nil
        } else if let instance = store.devices.first(where: { $0.id == seam }) {
            openSheet = .edit(instance); seamSheet = nil
        }
    }

    private func highlight(_ id: String) {
        withAnimation(.spring(duration: 0.25)) { highlightID = id }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.4)) { if highlightID == id { highlightID = nil } }
        }
    }

    /// "Adicionar dispositivo…" ao fim do grupo — o molde de Mail › Contas e de
    /// Ajustes do Sistema › Impressoras. Desabilitada quando o serviço instalado
    /// não gerencia dispositivos (D11), com o motivo na linha cinza acima.
    private var addRow: some View {
        let ok: Bool = {
            if case .unsupported = store.deviceSupport { return false }
            return true
        }()
        return Button {
            addInitialType = nil
            showAdd = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .frame(width: 26)
                    .foregroundStyle(ok ? accent : Color.secondary)
                Text(L10n.t("Adicionar dispositivo…", "Add device…"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(ok ? Color.primary : Color.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ok)
    }

    /// Uma linha por INSTÂNCIA: ícone do tipo, o nome que o usuário deu, o
    /// estado, o interruptor e o chevron que abre a folha. O tipo não ganha
    /// legenda na linha (o ícone já o distingue; duas instâncias do mesmo tipo se
    /// distinguem pelo nome, que é único) — fica no `.help()` e no cabeçalho da folha.
    ///
    /// O interruptor tem UMA fonte de verdade — o health. Com `store.health` nil
    /// (serviço parado, ou antes do primeiro poll) a linha fica desligada e
    /// desabilitada, em vez de inventar um segundo lugar de onde ler. O override
    /// `optimistic` existe SÓ enquanto o PUT está em voo e é ele próprio o
    /// marcador de "em voo" — nada de um `inFlight` paralelo para dessincronizar.
    @ViewBuilder
    private func deviceRow(_ instance: DeviceInstance) -> some View {
        let type = DeviceTypeRegistry.type(id: instance.type)
        let detail = store.health?.pluginDetail(id: instance.id)
        let ligado = optimistic[instance.id] ?? (detail?.enabled ?? false)
        let badge = DevicePluginUIRegistry.plugin(typeID: instance.type)?.badge(state: detail?.state)
        HStack(spacing: 10) {
            Image(systemName: type?.symbol ?? "shield.lefthalf.filled")
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Button {
                openSheet = .edit(instance)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deviceName(instance))
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
            .help(type?.label ?? instance.type)
            .disabled(DevicePluginUIRegistry.plugin(typeID: instance.type) == nil)
            Spacer()
            Toggle("", isOn: Binding(
                get: { ligado },
                set: { novo in Task { await toggleDevice(instance, on: novo) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(store.health == nil || optimistic[instance.id] != nil)
        }
        .scaleEffect(highlightID == instance.id ? 1.02 : 1)
        .shadow(color: accent.opacity(highlightID == instance.id ? 0.30 : 0), radius: 14)
    }

    /// Ligar com o ensaio DESLIGADO (ou desconhecido) arma de verdade: pede
    /// confirmação e NÃO escreve nada antes dela. Desligar é desarme puro —
    /// sempre aceito pelo daemon — e vai direto, de forma otimista.
    private func toggleDevice(_ instance: DeviceInstance, on: Bool) async {
        let dryRun = store.health?.pluginDetail(id: instance.id)?.dryRun
        if DeviceTypeRegistry.toggleNeedsConfirmation(on: on, dryRun: dryRun) {
            pendingArm = instance
            return
        }
        await putEnable(instance, on: on)
    }

    private func putEnable(_ instance: DeviceInstance, on: Bool) async {
        guard let endpoint = ApiEndpoint.discover() else {
            devicesFeedback = L10n.t("Serviço parado — nada mudou.", "Service down — nothing changed.")
            return
        }
        optimistic[instance.id] = on
        do {
            _ = try await APIClient(endpoint: endpoint).updateDevice(id: instance.id, enabled: on)
            devicesFeedback = nil
            // Atualiza a lista e o health ANTES de limpar o override: limpar
            // primeiro faria o `get` voltar ao estado velho e o interruptor piscar.
            await store.refreshDevices()
            await store.refreshHealth()
        } catch let APIError.badStatus(_, body) {
            devicesFeedback = ProtectionRefusal.text(body)
        } catch {
            devicesFeedback = L10n.t("Falha: ", "Failed: ") + error.localizedDescription
        }
        optimistic[instance.id] = nil
    }

    // MARK: - River (núcleo)

    private var riverChanged: Bool {
        loaded && (riverBaseline["UDR7_EXPECTED_SERIAL"] != expectedSerial.trimmingCharacters(in: .whitespaces)
                   || riverBaseline["UDR7_CUTOFF_PERCENT"] != String(cutoff))
    }

    private func saveRiver() async {
        guard let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado — nada salvo.", "Service down — nothing saved.")
            return
        }
        let changes = ["UDR7_EXPECTED_SERIAL": expectedSerial.trimmingCharacters(in: .whitespaces),
                       "UDR7_CUTOFF_PERCENT": String(cutoff)]
        do {
            _ = try await APIClient(endpoint: endpoint).putConfig(changes)
            riverBaseline = changes
            feedback = nil
            await store.refreshHealth()
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)     // 409 armado: desarme antes
        } catch {
            feedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
        }
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
        expectedSerial = cfg["udr7_expected_serial"]?.stringValue ?? expectedSerial
        cutoff = cfg["udr7_cutoff_percent"]?.intValue ?? cutoff
        riverBaseline = ["UDR7_EXPECTED_SERIAL": expectedSerial, "UDR7_CUTOFF_PERCENT": String(cutoff)]
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
