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
    /// A leitura da configuração não voltou (serviço parado ou sem resposta).
    /// Enquanto for verdade, os controles desta tela não valem nada e dizem isso.
    @State private var configFailed = false
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
    // O River como APARELHO (0.5.0): quem está com o cabo, o aviso de bateria
    // fraca dele, e os dois diálogos de confirmação.
    @State private var estadoDoCabo: EstadoDoCabo?
    @State private var avisoBateriaAparelho: Int?
    // O que o dono arrastou, ainda não enviado. Sem isto, cada passo do
    // arrastar virava uma gravação no aparelho — dezenas de idas ao River para
    // uma única mudança (revisão fria da 0.5.0).
    @State private var avisoEditado: Int?
    @State private var confirmacaoRiver: RiverConfirmation.Ato?
    @State private var riverFeedback: String?
    @State private var riverBaseline: [String: String] = [:]
    /// A versão do serviço que responde (GET /v1/version); nil enquanto não chegou.
    @State private var serviceVersion: String?
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }

    /// A linha que diz quem está com o cabo e oferece a troca. A exclusividade do
    /// aparelho é física; escondê-la seria mentir para o dono.
    @ViewBuilder
    private func linhaDoCabo(_ cabo: EstadoDoCabo) -> some View {
        let comEles = cabo.pausado == true
        HStack(spacing: 10) {
            Image(systemName: comEles ? "cable.connector.slash" : "cable.connector")
                .frame(width: 26)
                .foregroundStyle(comEles ? Cor.atencao : Cor.neutro)
            VStack(alignment: .leading, spacing: 2) {
                Text(comEles
                     ? L10n.t("O River está com o aplicativo da EcoFlow",
                              "The EcoFlow app has the River")
                     : L10n.t("O River está com este serviço", "This service has the River"))
                    .font(.system(.body, design: .rounded))
                if let motivo = cabo.motivo, comEles == false, cabo.lendo == false {
                    Text(motivo).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(comEles ? L10n.t("Retomar", "Take back")
                           : L10n.t("Entregar…", "Hand over…")) {
                if comEles {
                    Task { await mudarCabo("retomar") }
                } else {
                    confirmacaoRiver = .liberarCabo
                }
            }
            .buttonStyle(.glass)
        }
    }

    private func mudarCabo(_ acao: String) async {
        guard let endpoint = ApiEndpoint.discover() else {
            riverFeedback = L10n.t("Serviço parado — nada mudou.", "Service down — nothing changed.")
            return
        }
        do {
            estadoDoCabo = try await APIClient(endpoint: endpoint).riverCabo(acao: acao)
            riverFeedback = nil
        } catch let APIError.badStatus(_, body) {
            riverFeedback = ProtectionRefusal.text(body)
        } catch {
            riverFeedback = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
    }

    private func desligarRiver() async {
        guard let endpoint = ApiEndpoint.discover() else {
            riverFeedback = L10n.t("Serviço parado — nada foi enviado.", "Service down — nothing was sent.")
            return
        }
        do {
            try await APIClient(endpoint: endpoint).riverDesligar()
            riverFeedback = L10n.t("Desligamento enviado ao River.", "Shutdown sent to the River.")
        } catch let APIError.badStatus(_, body) {
            riverFeedback = ProtectionRefusal.text(body)
        } catch {
            riverFeedback = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
    }

    private func salvarAvisoDoAparelho(_ porcento: Int) async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        do {
            let atual = try await APIClient(endpoint: endpoint).riverAvisoBateriaBaixa(porcento)
            // O que vale na tela é o que o APARELHO devolveu, não o que foi pedido.
            if let atual, let n = Int(atual) { avisoBateriaAparelho = n }
            avisoEditado = nil
            riverFeedback = nil
        } catch let APIError.badStatus(_, body) {
            riverFeedback = ProtectionRefusal.text(body)
        } catch {
            riverFeedback = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
    }

    /// Digitar dezesseis caracteres à mão era a parte estúpida da cerca, não a
    /// cerca: o aparelho diz o próprio número, e um toque o registra. O ato
    /// continua sendo do dono — e é ele que a proteção vai exigir para armar.
    @ViewBuilder
    private var linhaDoSerialLido: some View {
        let lido = store.latest?.identity?.serial ?? ""
        let atual = expectedSerial.trimmingCharacters(in: .whitespaces)
        if !lido.isEmpty && lido != atual {
            HStack {
                Text(L10n.t("O River conectado agora diz ser este: \(lido)",
                            "The River connected right now says it is this: \(lido)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(L10n.t("Usar este", "Use this")) { expectedSerial = lido }
                    .buttonStyle(.glass)
            }
        }
    }

    private func carregarRiver() async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        estadoDoCabo = try? await APIClient(endpoint: endpoint).riverCabo()
        if let low = store.latest?.battery?.chargeLowPercent {
            avisoBateriaAparelho = Int(low)
        }
    }

    /// O nome do aparelho no nosso servidor — é o que o aplicativo da EcoFlow
    /// precisa digitar no modo remoto. Vem do serviço, nunca escrito à mão aqui.
    private var riverNutName: String {
        store.latest?.identity?.name ?? "river-office"
    }

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
                // O serviço vem PRIMEIRO: enquanto ele não estiver no ar,
                // ninguém está vigiando a energia, e nenhum outro ajuste desta
                // tela tem efeito nenhum.
                ServicoGroup()
                // Logo depois do serviço: é a conta que ele criou, e o dono só
                // precisa dela quando o serviço já está no ar.
                HomeAssistantGroup()
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

                if configFailed {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Cor.atencao)
                        Text(L10n.t("Sem resposta do serviço — os valores abaixo não foram carregados.",
                                    "No answer from the service — the values below were not loaded."))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L10n.t("Tentar de novo", "Try again")) {
                            Task { await loadCurrent() }
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Cor.atencao.opacity(0.12)))
                }

                SettingsRows.group(L10n.t("Alarmes", "Alarms")) {
                    SettingsRows.presetRow("bolt.slash.fill", L10n.t("Queda de energia", "Power loss"),
                              value: $powerLossDelay, presets: [0, 3, 6, 10, 30, 60])
                    .comDica(L10n.t("Quanto tempo o River precisa ficar na bateria antes de o serviço tratar isso como queda de energia. Serve para piscadas curtas não virarem alarme.",
                                "How long the River must stay on battery before the service treats it as a power loss. Keeps brief flickers from becoming alarms."))
                    SettingsRows.divider
                    SettingsRows.presetRow("bolt.badge.checkmark.fill", L10n.t("Energia restaurada", "Power restored"),
                              value: $restoreDelay, presets: [0, 5, 10, 30, 60])
                    .comDica(L10n.t("Quanto tempo a energia precisa estar de volta antes de o serviço declarar que voltou. Zero avisa na hora.",
                                "How long power must be back before the service declares it restored. Zero announces it at once."))
                    SettingsRows.divider
                    SettingsRows.presetRow("antenna.radiowaves.left.and.right.slash", L10n.t("Comunicação perdida", "Comm lost"),
                              value: $commLossDelay, presets: [5, 15, 30, 60, 300])
                    .comDica(L10n.t("Quanto tempo sem resposta do River até a tela dizer que perdemos contato com ele.",
                                "How long without an answer from the River until the screen says we lost contact with it."))
                    SettingsRows.divider
                    SettingsRows.sliderRow("battery.25percent", L10n.t("Bateria baixa", "Low battery"),
                              value: $lowBattery, range: 5...50, unit: "%", accent: accent)
                    .comDica(L10n.t("Em que nível de bateria o SERVIÇO registra o alerta de bateria baixa. É o alerta desta tela, não um ajuste do aparelho.",
                                "At what battery level the SERVICE records its low-battery alert. This is this app's alert, not a device setting."))
                }
                .disabled(configFailed)   // sem os valores do serviço, editar seria escrever no escuro

                SettingsRows.group(L10n.t("Coleta", "Sampling")) {
                    SettingsRows.presetRow("timer", L10n.t("Intervalo de leitura", "Poll interval"),
                              value: $pollInterval, presets: [1, 2, 5, 10, 30, 60])
                    .comDica(L10n.t("De quanto em quanto tempo o serviço lê o River. Mais curto reage mais rápido a uma queda; mais longo pesa menos na máquina.",
                                "How often the service reads the River. Shorter reacts faster to an outage; longer is lighter on the machine."))
                }
                .disabled(configFailed)   // sem os valores do serviço, editar seria escrever no escuro

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
                    .comDica(L10n.t("Por quanto tempo os números e os eventos ficam guardados neste Mac. O que passa disso é apagado sozinho, uma vez por hora.",
                                 "How long readings and events are kept on this Mac. Anything older is deleted automatically, once an hour."))
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
                                .foregroundStyle(Cor.perigo)
                                .frame(minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                    .comDica(L10n.t("Apaga a linha do tempo guardada neste Mac. Os números dos gráficos continuam; só os eventos saem.",
                                 "Clears the timeline stored on this Mac. The chart readings stay; only the events go."))
                }
                .disabled(configFailed)   // sem os valores do serviço, editar seria escrever no escuro

                SettingsRows.group(L10n.t("River", "River")) {
                    SettingsRows.textRow("barcode", L10n.t("Número de série esperado do River", "Expected River serial number"),
                                         $expectedSerial, placeholder: "R3P…", estreito: DeviceSheetMetrics.isNarrow(width: hostSize.width))
                    linhaDoSerialLido
                    .comDica(L10n.t("O número de série do SEU River. O serviço só arma a proteção se a leitura vier deste aparelho — é o que impede armar contra um simulador ou contra o no-break errado.",
                                "Your River's serial number. The service only arms protection when the reading comes from this device — it is what prevents arming against a simulator or the wrong UPS."))
                    SettingsRows.divider
                    SettingsRows.sliderRow("battery.0percent", L10n.t("Corte físico da saída", "Physical output cutoff"),
                                           value: $cutoff, range: 0...48, unit: "%",
                                           zeroLabel: L10n.t("não configurado", "not set"), accent: accent,
                                           estreito: DeviceSheetMetrics.isNarrow(width: hostSize.width))
                    .comDica(L10n.t("O nível em que o River corta a saída sozinho, se você o configurou no aplicativo dele. O serviço usa esse número para calcular quanto tempo ainda resta e nunca prometer mais autonomia do que existe.",
                                "The level at which the River cuts its output on its own, if you set that in its own app. The service uses this number to work out how much time is left and never promise more runtime than exists."))
                    if riverChanged {
                        HStack {
                            Text(L10n.t("Vale para todos os dispositivos protegidos.", "Applies to every protected device."))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.t("Salvar", "Save")) { Task { await saveRiver() } }
                                .buttonStyle(.glassProminent).tint(accent)
                        }
                    }
                    if let aviso = avisoBateriaAparelho {
                        SettingsRows.divider
                        SettingsRows.sliderRow(
                            "bell.badge", L10n.t("Aviso de bateria fraca do aparelho",
                                                 "Device low-battery reminder"),
                            value: Binding(get: { avisoEditado ?? aviso },
                                           set: { avisoEditado = $0 }),
                            range: 0...50, unit: "%",
                            zeroLabel: L10n.t("desligado", "off"), accent: accent,
                            estreito: DeviceSheetMetrics.isNarrow(width: hostSize.width))
                        .comDica(L10n.t("O nível em que o PRÓPRIO River avisa que a bateria está baixa. É gravado dentro do aparelho, e é o mesmo ajuste que o aplicativo da EcoFlow mostra.",
                                     "The level at which the River ITSELF warns that the battery is low. It is written into the device, and it is the same setting the EcoFlow app shows."))
                        // Só vai ao aparelho quando o dono manda: o mesmo molde
                        // da linha do corte, logo acima.
                        if let novo = avisoEditado, novo != aviso {
                            HStack {
                                Text(L10n.t("Gravado no próprio River.", "Written into the River itself."))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(L10n.t("Salvar", "Save")) {
                                    Task { await salvarAvisoDoAparelho(novo) }
                                }
                                .buttonStyle(.glassProminent).tint(accent)
                            }
                        }
                    }
                    if let cabo = estadoDoCabo, cabo.lendo != nil {
                        SettingsRows.divider
                        linhaDoCabo(cabo)
                            .comDica(L10n.t("O River aceita um leitor por vez. Aqui você entrega o cabo ao aplicativo da EcoFlow — e o toma de volta quando quiser.",
                                         "The River accepts one reader at a time. Here you hand the cable over to the EcoFlow app — and take it back whenever you want."))
                    }
                    SettingsRows.divider
                    HStack(spacing: 10) {
                        Image(systemName: "power")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("Desligar o River", "Turn the River off"))
                                .font(.system(.body, design: .rounded))
                            Text(L10n.t("Corta a energia de tudo o que estiver ligado nele.",
                                        "Cuts power to everything plugged into it."))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            confirmacaoRiver = .desligarRiver
                        } label: {
                            Text(L10n.t("Desligar…", "Turn off…"))
                                .foregroundStyle(Cor.perigo)
                                .frame(minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                    .comDica(L10n.t("Desliga a saída do próprio River: tudo o que estiver ligado nele perde energia na hora. Só funciona com a trava aberta no arquivo do serviço e com nenhuma proteção armada.",
                                 "Switches the River's own output off: everything plugged into it loses power at once. It only works with the lock open in the service file and no protection armed."))
                    if let riverFeedback {
                        Text(riverFeedback)
                            .font(.caption).foregroundStyle(Cor.atencao)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(configFailed)   // sem os valores do serviço, editar seria escrever no escuro

                // O aparelho fala por dois caminhos ao mesmo tempo: o padrão de
                // no-break, que dá bateria e situação, e a porta serial, que dá
                // consumo por tomada. Esta seção mostra o que chega por ela, e
                // como emprestar o aparelho para o aplicativo do fabricante.
                if store.temTomadas {
                    SettingsRows.group(L10n.t("Consumo por tomada", "Draw per outlet")) {
                        ForEach(Array(store.tomadas.enumerated()), id: \.offset) { indice, item in
                            if indice > 0 { SettingsRows.divider }
                            HStack(spacing: 10) {
                                Image(systemName: "powerplug")
                                    .frame(width: 26)
                                    .foregroundStyle(.secondary)
                                Text(item.rotulo)
                                    .font(.system(.body, design: .rounded))
                                Spacer()
                                Text(item.valor)
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                            }
                        }
                        SettingsRows.divider
                        Text(L10n.t("Lido direto do River pela porta do próprio cabo. O aplicativo da EcoFlow pode acompanhar ao mesmo tempo: em \"Communication mode\", escolha Remote e aponte para este Mac, aparelho \(riverNutName), endereço 127.0.0.1, porta 3493.",
                                    "Read straight from the River over its own cable port. The EcoFlow app can watch at the same time: in \"Communication mode\" pick Remote and point it at this Mac, device \(riverNutName), address 127.0.0.1, port 3493."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                                .tint(Cor.atencao)
                        }
                        Spacer()
                        if let devicesFeedback {
                            Label(devicesFeedback, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(Cor.atencao)
                        } else if let feedback {
                            Label(feedback, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(Cor.atencao)
                                .contentTransition(.opacity)
                        } else if let notice {
                            Label(notice, systemImage: "checkmark.circle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                    }
                }

                // As versões ficam no rodapé de Ajustes (o lugar dos utilitários de barra
                // de menus: o painel "Sobre" do macOS só mostraria a do app; aqui a pessoa
                // vê as DUAS e se estão alinhadas — dono, 2026-09-03).
                versionFooter
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .task {
            if let endpoint = ApiEndpoint.discover() {
                serviceVersion = try? await APIClient(endpoint: endpoint).version().version
            }
            // "novo…" não depende de rede: aplica antes das chamadas ao serviço
            // (medido em 2026-09-03: a primeira chamada pode levar segundos e a
            // captura fotografava a tela sem a folha). Os ids esperam a lista.
            applySeamSheet()
            await loadCurrent()
            await store.refreshDevices()
            await carregarRiver()
            applySeamSheet()
        }
        // Os dois atos que mexem na energia dos equipamentos pedem confirmação,
        // no mesmo molde do armamento da proteção.
        .confirmacao(Binding(
            get: {
                confirmacaoRiver.map { ato in
                    let texto = RiverConfirmation(ato: ato)
                    return PedidoDeConfirmacao(
                        titulo: texto.title, detalhe: texto.message,
                        rotuloDaAcao: texto.confirmLabel, destrutivo: true
                    ) {
                        Task {
                            switch ato {
                            case .liberarCabo: await mudarCabo("liberar")
                            case .desligarRiver: await desligarRiver()
                            }
                        }
                    }
                }
            },
            set: { if $0 == nil { confirmacaoRiver = nil } }))
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
        .confirmacao(Binding(
            get: {
                pendingArm.map { item in
                    let arming = ArmConfirmation(name: deviceName(item),
                                                 mode: .enableWithRehearsalOff)
                    return PedidoDeConfirmacao(
                        titulo: arming.title, detalhe: arming.message,
                        rotuloDaAcao: arming.confirmLabel, destrutivo: true
                    ) { Task { await putEnable(item, on: true) } }
                }
            },
            set: { if $0 == nil { pendingArm = nil } }))
        // Auto-save (owner 2026-08-31): every change PUTs after a short
        // debounce — no save button, like System Settings. All keys on this
        // screen are hot-reload; the daemon still validates every value.
        // Exception (Fase 3'-EXP): the protection group saves explicitly —
        // its text fields would otherwise PUT half-typed hosts and serials.
        // Clearing follows the owner's ask ("anteriores a uma data"): scoped,
        // destructive, always confirmed; a bare "delete all" needs the
        // explicit Tudo choice. The daemon refuses DELETE without `to`.
        .escolha(Binding(
            get: {
                guard showClearDialog else { return nil }
                return EscolhaDeConfirmacao(
                    titulo: L10n.t("Limpar eventos gravados?", "Clear stored events?"),
                    detalhe: L10n.t("Remove eventos do log do serviço. As métricas do gráfico não são afetadas.",
                                    "Removes events from the service log. Chart metrics are not affected."),
                    saidas: [
                        .init(rotulo: L10n.t("Anteriores a 7 dias", "Older than 7 days"), destrutivo: true) {
                            Task { await clearEvents(to: Int(Date.now.addingTimeInterval(-7 * 86400).timeIntervalSince1970)) }
                        },
                        .init(rotulo: L10n.t("Anteriores a 30 dias", "Older than 30 days"), destrutivo: true) {
                            Task { await clearEvents(to: Int(Date.now.addingTimeInterval(-30 * 86400).timeIntervalSince1970)) }
                        },
                        .init(rotulo: L10n.t("Anteriores a uma data…", "Older than a date…")) {
                            showClearDatePick = true
                        },
                        .init(rotulo: L10n.t("Tudo", "Everything"), destrutivo: true) {
                            Task { await clearEvents(to: Int(Date.now.timeIntervalSince1970)) }
                        },
                    ])
            },
            set: { if $0 == nil { showClearDialog = false } }))
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
                    .tint(Cor.perigo)
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

    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text("River Bridge \(appVersion) · " + L10n.t("Serviço", "Service") + " " + (serviceVersion ?? L10n.t("sem resposta", "no answer")))
                .font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()
            if let serviceVersion, serviceVersion != appVersion {
                Text(L10n.t("Versões diferentes — rode o instalador para alinhar app e serviço.",
                            "Versions differ — run the installer to align app and service."))
                    .font(.caption).foregroundStyle(Cor.atencao)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

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
            // `detail == nil`: o serviço respondeu, mas ainda não disse nada sobre
            // ESTE dispositivo. Habilitado, o interruptor convidava a armar no
            // escuro — e nascia desligado, dando a impressão de proteção parada.
            .disabled(store.health == nil || detail == nil || optimistic[instance.id] != nil)
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

    /// Lê a configuração VIVA do serviço. Enquanto ela não chega, a tela não
    /// pode mostrar os valores de fábrica como se fossem os do serviço: era o
    /// que acontecia — a chamada falhava em silêncio e os padrões ficavam ali,
    /// com aparência de verdade. Sem resposta, a faixa avisa e os controles
    /// ficam desabilitados; a tela tenta de novo a cada vez que aparece.
    private func loadCurrent() async {
        guard !loaded else { return }
        guard let endpoint = ApiEndpoint.discover() else {
            configFailed = true
            return
        }
        guard let response = try? await APIClient(endpoint: endpoint).config() else {
            configFailed = true
            return
        }
        configFailed = false
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
            // O serviço apagou; a tela tem de esquecer no mesmo ato. Sem isto a
            // lista continuava lá até chegar um evento novo.
            store.forgetEvents(upTo: Date(timeIntervalSince1970: TimeInterval(cutoff)))
            feedback = nil
            notice = removed == 1 ? L10n.t("1 evento removido.", "1 event removed.") : "\(removed) " + L10n.t("eventos removidos.", "events removed.")
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)
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
            feedback = ProtectionRefusal.text(body)
        } catch {
            feedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
        }
    }

    private func restart() async {
        guard let endpoint = ApiEndpoint.discover() else { return }
        do {
            try await APIClient(endpoint: endpoint).restartService()
            notice = L10n.t("Reinício do serviço agendado.", "Service restart scheduled.")
            restartRequired = false
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)   // 409 armado: disarm first, or kickstart from the terminal
        } catch {
            feedback = L10n.t("Falha no reinício: ", "Restart failed: ") + error.localizedDescription
        }
    }
}
