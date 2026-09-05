// A folha dos dispositivos que o motor SSH protege — o Console UniFi (UDR7) e o
// Computador/servidor via SSH são VARIANTES dela: os mesmos grupos escritos à
// mão (máquina e chave, limiares), mais o que só cada tipo tem (o MAC de
// religamento no UDR7; o comando de desligamento, de lista fechada, no host).
//
// Modo NOVO: nome sugerido único, defaults do catálogo, sem linha de armamento
// (a instância nasce desligada e em ensaio; armar é ato separado). Modo EDIÇÃO:
// o nome viaja num PUT próprio antes dos campos (é aceito com a proteção
// armada; os campos podem voltar 409), e cada PUT é pulado quando não há diff.

import RiverBridgeCore
import SwiftUI

struct SshDeviceSheet: View {
    enum Variant { case udr7, sshHost }

    let variant: Variant
    let mode: DeviceSheetMode
    var store: TelemetryStore
    var hostSize: CGSize
    var onBack: (() -> Void)?
    var onClose: (_ createdID: String?) -> Void

    @State private var name = ""
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUser = "root"
    @State private var sshKey = ""
    @State private var wolMac = ""
    @State private var shutdownCommand = "shutdown -h now"
    @State private var shutdown = 0
    @State private var dischargeSecPerPct = "0"
    @State private var runtimeMinutes = "0"
    @State private var minOutage = "0"
    @State private var confirmSeconds = "6"
    @State private var armAllowed = false
    @State private var baseline: [String: String] = [:]
    @State private var baselineName = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var feedback: String?
    @State private var notice: String?
    @State private var showArmDialog = false
    // Acesso ao console (0.6.0): o serviço cria a chave, confere a identidade e
    // instala — o dono não abre terminal nenhum.
    @State private var acesso: AcessoPreparado?
    @State private var senhaDoConsole = ""
    @State private var alcance: AcessoTestado?
    @State private var ocupadoNoAcesso = false
    @State private var identidadeDivergente = false

    private var type: DeviceTypeDescriptor { variant == .udr7 ? .udr7 : .sshHost }
    private var instance: DeviceInstance? { mode.instance }
    /// Estado vindo do HEALTH, nunca de uma cópia local: o badge do cartão e esta
    /// folha mostram a mesma coisa porque leem a mesma fonte.
    private var detail: DeviceDetail? { instance.flatMap { store.health?.pluginDetail(id: $0.id) } }
    private var dryRun: Bool { detail?.dryRun ?? true }
    private var enabled: Bool { detail?.enabled ?? false }
    private var currentName: String {
        if let instance { return store.deviceNames.name(forDevice: instance.id, type: type) }
        return DeviceNames.suggestedName(type: type, existing: store.devices)
    }
    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }
    /// A lista fechada do catálogo do serviço — e SEMPRE com a seleção atual
    /// dentro: um seletor cuja seleção não está entre as opções (o catálogo
    /// ainda não chegou, ou o serviço tem uma lista diferente) redesenha vazio
    /// e puxa a rolagem da folha.
    private var commands: [String] {
        let catalogo = store.deviceTypes.first { $0.id == type.id }?
            .fields.first { $0.name == "shutdown_command" }?.enumValues ?? []
        return catalogo.contains(shutdownCommand) ? catalogo : catalogo + [shutdownCommand]
    }

    /// Nome repetido é recusado pelo serviço (409 nome_duplicado); a folha avisa
    /// ANTES e não envia — o mesmo `already_configured` do Home Assistant.
    private var duplicateName: Bool {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        return !wanted.isEmpty && store.devices.contains {
            $0.id != instance?.id && $0.name.trimmingCharacters(in: .whitespaces).lowercased() == wanted
        }
    }

    private var canSave: Bool {
        loaded && !busy && !duplicateName && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (mode.isNew || !changedFields().isEmpty || nameChanged)
    }

    var body: some View {
        DeviceSheetFrame(
            mode: mode, type: type, typedName: name, currentName: currentName,
            badge: DevicePluginUIRegistry.plugin(typeID: type.id)?.badge(state: detail?.state),
            hostSize: hostSize,
            feedback: duplicateName ? L10n.t("Já existe um dispositivo com este nome.", "A device with this name already exists.") : feedback,
            notice: notice, canSave: canSave, hasChanges: !changedFields().isEmpty || nameChanged,
            onClose: { onClose(nil) }, onSave: { Task { await save() } },
            onBack: onBack, onRemove: mode.isNew ? nil : { Task { await remove() } }
        ) { estreito in
            // `estreito` é a largura REAL da folha, medida pela moldura.
            SettingsRows.group(L10n.t("Dispositivo", "Device")) {
                SettingsRows.textRow("tag", L10n.t("Nome", "Name"), $name,
                                     placeholder: type.defaultName, estreito: estreito)
            }
            if !mode.isNew {
                SettingsRows.group(L10n.t("Armamento", "Arming")) {
                    ArmingRow(dryRun: dryRun, enabled: enabled, armAllowed: armAllowed,
                              alcanceProvado: alcanceProvado, estreito: estreito,
                              onTurnOffRehearsal: { showArmDialog = true },
                              onTurnOnRehearsal: { Task { await setDryRun(true) } })
                }
            }
            SettingsRows.group(variant == .udr7 ? L10n.t("Console e chave", "Console and key")
                                                 : L10n.t("Máquina e chave", "Machine and key")) {
                SettingsRows.textRow("network", variant == .udr7 ? L10n.t("Console (host)", "Console (host)")
                                                                   : L10n.t("Endereço (host)", "Address (host)"),
                                     $sshHost, placeholder: variant == .udr7 ? "192.168.1.1" : "192.168.1.20", estreito: estreito)
                SettingsRows.divider
                SettingsRows.textRow("number", L10n.t("Porta SSH", "SSH port"), $sshPort, placeholder: "22", numeric: true, estreito: estreito)
                SettingsRows.divider
                SettingsRows.textRow("person.fill", L10n.t("Usuário SSH", "SSH user"), $sshUser, placeholder: "root", estreito: estreito)
                SettingsRows.divider
                SettingsRows.textRow("key.fill", L10n.t("Chave privada (caminho absoluto)", "Private key (absolute path)"),
                                     $sshKey, placeholder: "/Users/…/.ssh/river-bridge-\(instance?.id ?? type.id)", estreito: estreito)
            }
            if !mode.isNew {
                SettingsRows.group(L10n.t("Acesso ao console", "Console access")) {
                    grupoDeAcesso(estreito: estreito)
                }
            }
            if variant == .sshHost {
                SettingsRows.group(L10n.t("Desligamento", "Shutdown")) {
                    // Só o molde de linhas entra numa folha: a versão escrita à mão
                    // hifenizava o rótulo e deixava o cartão vazio a 414 pt (dono, 2026-09-03).
                    SettingsRows.pickerRow("power", L10n.t("Comando de desligamento", "Shutdown command"),
                                           caption: L10n.t("Roda por SSH como o usuário acima.", "Runs over SSH as the user above."),
                                           selection: $shutdownCommand, options: commands,
                                           monospaced: true, estreito: estreito)
                }
            }
            SettingsRows.group(L10n.t("Limiares", "Thresholds")) {
                SettingsRows.sliderRow("power.circle", variant == .udr7 ? L10n.t("Desligar o console em", "Shut the console down at")
                                                                          : L10n.t("Desligar em", "Shut down at"),
                                       value: $shutdown, range: 0...50, unit: "%",
                                       zeroLabel: L10n.t("não configurado", "not set"), accent: accent, estreito: estreito)
                SettingsRows.divider
                SettingsRows.textRow("stopwatch", L10n.t("Descarga medida (s por 1 %)", "Measured discharge (s per 1 %)"),
                                     $dischargeSecPerPct, placeholder: "0", numeric: true, estreito: estreito)
                SettingsRows.divider
                SettingsRows.textRow("clock", L10n.t("Ou autonomia ≤ (min, 0 = desligado)", "Or runtime ≤ (min, 0 = off)"),
                                     $runtimeMinutes, placeholder: "0", numeric: true, estreito: estreito)
                SettingsRows.divider
                SettingsRows.textRow("hourglass", L10n.t("Queda mínima (s)", "Minimum outage (s)"),
                                     $minOutage, placeholder: "0", numeric: true, estreito: estreito)
                SettingsRows.divider
                SettingsRows.textRow("checkmark.seal", L10n.t("Confirmar por (s)", "Confirm for (s)"),
                                     $confirmSeconds, placeholder: "6", numeric: true, estreito: estreito)
                if variant == .udr7 {
                    SettingsRows.divider
                    SettingsRows.textRow("wake", L10n.t("MAC para religar (WoL, opcional)", "Wake MAC (WoL, optional)"),
                                         $wolMac, placeholder: "aa:bb:cc:dd:ee:ff", estreito: estreito)
                }
            }
        }
        .task { await load() }
        .confirmacao(Binding(
            get: {
                guard showArmDialog else { return nil }
                return PedidoDeConfirmacao(
                    titulo: arming.title, detalhe: arming.message,
                    rotuloDaAcao: arming.confirmLabel, destrutivo: true
                ) { Task { await setDryRun(false) } }
            },
            set: { if $0 == nil { showArmDialog = false } }))
    }

    private var arming: ArmConfirmation {
        ArmConfirmation(name: currentName, mode: .turnOffRehearsal)
    }

    // MARK: - Valores e diff (nomes de campo do serviço, sem prefixo)

    /// O serviço já provou que fala com este aparelho? Vem do health, para a tela
    /// saber ANTES do clique — e é confirmado na hora pelo botão de testar.
    private var alcanceProvado: Bool {
        if let alcance { return alcance.alcance }
        return detail?.alcanceVerificado ?? false
    }

    // --- acesso ao console ---------------------------------------------------
    @ViewBuilder
    private func grupoDeAcesso(estreito: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let alcance, alcance.alcance, let r = alcance.resposta {
                Label(L10n.t("Conexão provada: \(r.model ?? "") · \(r.firmware ?? "")",
                             "Connection proven: \(r.model ?? "") · \(r.firmware ?? "")"),
                      systemImage: "checkmark.seal.fill")
                    .font(.callout).foregroundStyle(.green)
            } else if let alcance, let motivo = alcance.motivo {
                Label(motivo, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t("O serviço precisa provar que alcança este aparelho antes de armar a proteção. Ele cria a chave sozinho; você só informa a senha do console uma vez.",
                            "The service must prove it reaches this device before protection can be armed. It creates the key itself; you only give the console password once."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let acesso {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("Identidade do console: \(acesso.impressaoDoConsole)",
                                "Console identity: \(acesso.impressaoDoConsole)"))
                    Text(L10n.t("Chave do serviço: \(acesso.impressaoDaChave)",
                                "Service key: \(acesso.impressaoDaChave)"))
                }
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            // Dois passos, nesta ordem, de propósito: a identidade do aparelho
            // aparece ANTES de a senha ir para ele. Mandar a senha para um
            // console visto pela primeira vez e conferir depois seria conferir
            // tarde (revisão fria da 0.6.0).
            if acesso == nil {
                HStack(spacing: 8) {
                    Button(L10n.t("Conferir o aparelho…", "Check the device…")) {
                        Task { await prepararAcesso(aceitandoIdentidade: false) }
                    }
                    .buttonStyle(.glassProminent).tint(accent)
                    .disabled(sshHost.isEmpty || ocupadoNoAcesso)
                    Button(L10n.t("Testar conexão", "Test connection")) { Task { await testarAcesso() } }
                        .disabled(sshHost.isEmpty || ocupadoNoAcesso)
                    Spacer()
                    if ocupadoNoAcesso { ProgressView().controlSize(.small) }
                }
            } else {
                SecureField(L10n.t("Senha do console (usada uma vez)", "Console password (used once)"),
                            text: $senhaDoConsole)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button(L10n.t("Instalar a chave", "Install the key")) {
                        Task { await instalarChave() }
                    }
                    .buttonStyle(.glassProminent).tint(accent)
                    .disabled(senhaDoConsole.isEmpty || ocupadoNoAcesso)
                    Button(L10n.t("Testar conexão", "Test connection")) { Task { await testarAcesso() } }
                        .disabled(ocupadoNoAcesso)
                    Spacer()
                    if ocupadoNoAcesso { ProgressView().controlSize(.small) }
                }
            }
            if identidadeDivergente {
                // Só aparece quando o aparelho se apresentou diferente: aceitar
                // é ato consciente, com a impressão digital à vista.
                Button(L10n.t("Aceitar a identidade nova…", "Accept the new identity…")) {
                    Task { await prepararAcesso(aceitandoIdentidade: true) }
                }
                .buttonStyle(.glass).tint(.orange)
                .disabled(ocupadoNoAcesso)
            }
            if acesso != nil || alcance != nil {
                Button(L10n.t("Esquecer este acesso", "Forget this access")) {
                    Task { await esquecerAcesso() }
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary).font(.caption)
                .disabled(ocupadoNoAcesso)
            }
            Text(L10n.t("Para desligar este aparelho usamos SSH. Habilitar SSH em equipamentos Ubiquiti pode anular a garantia, segundo os termos do próprio fabricante.",
                        "We use SSH to shut this device down. Enabling SSH on Ubiquiti equipment may void the warranty, per the manufacturer's own terms."))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func prepararAcesso(aceitandoIdentidade: Bool) async {
        guard let endpoint = ApiEndpoint.discover(), let id = instance?.id else { return }
        ocupadoNoAcesso = true
        defer { ocupadoNoAcesso = false }
        do {
            acesso = try await APIClient(endpoint: endpoint)
                .acessoPreparar(id: id, aceitarIdentidade: aceitandoIdentidade)
            identidadeDivergente = false
            feedback = nil
        } catch let APIError.badStatus(_, body) {
            identidadeDivergente = ProtectionRefusal.motivo(body) == "identidade_divergente"
            feedback = ProtectionRefusal.text(body)
        } catch {
            feedback = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
    }

    private func instalarChave() async {
        guard let endpoint = ApiEndpoint.discover(), let id = instance?.id else { return }
        ocupadoNoAcesso = true
        defer { ocupadoNoAcesso = false }
        do {
            alcance = try await APIClient(endpoint: endpoint)
                .acessoInstalar(id: id, senha: senhaDoConsole)
            senhaDoConsole = ""              // usada uma vez, e some da tela
            feedback = nil
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)
        } catch {
            feedback = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
    }

    private func esquecerAcesso() async {
        guard let endpoint = ApiEndpoint.discover(), let id = instance?.id else { return }
        ocupadoNoAcesso = true
        defer { ocupadoNoAcesso = false }
        do {
            try await APIClient(endpoint: endpoint).acessoEsquecer(id: id)
            acesso = nil; alcance = nil; identidadeDivergente = false
            feedback = nil
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)
        } catch {
            feedback = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
    }

    private func testarAcesso() async {
        guard let endpoint = ApiEndpoint.discover(), let id = instance?.id else { return }
        ocupadoNoAcesso = true
        defer { ocupadoNoAcesso = false }
        do {
            alcance = try await APIClient(endpoint: endpoint).acessoTestar(id: id)
            feedback = nil
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)
        } catch {
            feedback = L10n.t("Não consegui falar com o serviço.", "Could not reach the service.")
        }
    }

    private func fieldValues() -> [String: String] {
        var porCampo: [String: String] = [
            "ssh_host": sshHost, "ssh_port": sshPort, "ssh_user": sshUser, "ssh_key": sshKey,
            "shutdown_percent": String(shutdown), "discharge_seconds_per_pct": dischargeSecPerPct,
            "runtime_minutes": runtimeMinutes, "min_outage_seconds": minOutage,
            "confirm_seconds": confirmSeconds,
        ]
        if variant == .udr7 { porCampo["wol_mac"] = wolMac }
        if variant == .sshHost { porCampo["shutdown_command"] = shutdownCommand }
        var out: [String: String] = [:]
        // Itera os campos do TIPO, não o dicionário: o descritor é quem declara o
        // que a folha edita, e um campo que ela não desenha nunca entra no PUT.
        for key in type.fieldKeys {
            if let value = porCampo[key] { out[key] = value.trimmingCharacters(in: .whitespaces) }
        }
        return out
    }

    private func changedFields() -> [String: String] {
        fieldValues().filter { baseline[$0.key] != $0.value }
    }

    private var nameChanged: Bool {
        name.trimmingCharacters(in: .whitespaces) != baselineName
    }

    // MARK: - IO

    /// A recusa em texto humano; se o serviço diz que a instância já não existe,
    /// recarrega a lista (é o que o texto promete).
    private func refused(_ body: String) async -> String {
        if ProtectionRefusal.motivo(body) == "dispositivo_ausente" { await store.refreshDevices() }
        return ProtectionRefusal.text(body)
    }

    private func load() async {
        guard !loaded else { return }
        if let instance {
            name = instance.name
            let f = instance.fields
            sshHost = f["ssh_host"]?.stringValue ?? sshHost
            sshPort = f["ssh_port"]?.stringValue ?? sshPort
            sshUser = f["ssh_user"]?.stringValue ?? sshUser
            sshKey = f["ssh_key"]?.stringValue ?? sshKey
            wolMac = f["wol_mac"]?.stringValue ?? wolMac
            shutdownCommand = f["shutdown_command"]?.stringValue ?? shutdownCommand
            shutdown = f["shutdown_percent"]?.intValue ?? shutdown
            dischargeSecPerPct = f["discharge_seconds_per_pct"]?.stringValue ?? dischargeSecPerPct
            runtimeMinutes = f["runtime_minutes"]?.stringValue ?? runtimeMinutes
            minOutage = f["min_outage_seconds"]?.stringValue ?? minOutage
            confirmSeconds = f["confirm_seconds"]?.stringValue ?? confirmSeconds
        } else {
            name = DeviceNames.suggestedName(type: type, existing: store.devices)
            if let catalog = store.deviceTypes.first(where: { $0.id == type.id }) {
                sshPort = catalog.defaultValue(for: "ssh_port")?.stringValue ?? sshPort
                sshUser = catalog.defaultValue(for: "ssh_user")?.stringValue ?? sshUser
                confirmSeconds = catalog.defaultValue(for: "confirm_seconds")?.stringValue ?? confirmSeconds
                shutdownCommand = catalog.defaultValue(for: "shutdown_command")?.stringValue ?? shutdownCommand
            }
        }
        // A trava é global e só de arquivo: a folha só a mostra.
        if let endpoint = ApiEndpoint.discover(),
           let response = try? await APIClient(endpoint: endpoint).config() {
            armAllowed = response.config["udr7_arm_allowed"]?.boolValue ?? armAllowed
        }
        baseline = fieldValues()
        baselineName = name.trimmingCharacters(in: .whitespaces)
        loaded = true
        // Dev seam: `--seam-recusa <motivo>` mostra no rodapé o texto humano da
        // recusa, para a captura fotografar sem precisar de um serviço que recuse.
        if let motivo = AppPrefs.seamValue("--seam-recusa") {
            feedback = ProtectionRefusal.text("{\"motivo\": \"\(motivo)\"}")
        }
    }

    private func save() async {
        guard let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado — nada salvo.", "Service down — nothing saved.")
            return
        }
        let client = APIClient(endpoint: endpoint)
        busy = true
        defer { busy = false }
        let novoNome = name.trimmingCharacters(in: .whitespaces)
        if mode.isNew {
            do {
                let created = try await client.createDevice(type: type.id, name: novoNome, fields: fieldValues())
                await store.refreshDevices()
                await store.refreshHealth()
                onClose(created.id)
            } catch let APIError.badStatus(_, body) {
                feedback = await refused(body)
            } catch {
                feedback = L10n.t("Falha ao adicionar: ", "Add failed: ") + error.localizedDescription
            }
            return
        }
        guard let instance else { return }
        // O nome viaja num PUT próprio, antes do resto (ProtectionSave.split):
        // é aceito com a proteção armada; os campos podem voltar 409.
        var pending = changedFields()
        if nameChanged { pending["name"] = novoNome }
        let (nome, rest) = ProtectionSave.split(changes: pending, nameKey: "name")
        var nameSaved = false
        if let nome {
            do {
                _ = try await client.updateDevice(id: instance.id, name: nome)
                baselineName = nome
                nameSaved = true
                await store.refreshDevices()
                await store.refreshHealth()
            } catch let APIError.badStatus(_, body) {
                feedback = await refused(body)
                return                                  // nome recusado é falha total
            } catch {
                feedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
                return
            }
        }
        guard !rest.isEmpty else {
            if nameSaved { notice = L10n.t("Nome salvo.", "Name saved."); feedback = nil }
            return
        }
        do {
            _ = try await client.updateDevice(id: instance.id, fields: rest)
            for (key, value) in rest { baseline[key] = value }
            feedback = nil
            notice = "\(rest.count) " + L10n.t("campo(s) salvo(s).", "field(s) saved.")
            await store.refreshDevices()
            await store.refreshHealth()
            if let margem = detail?.marginEstimateS {
                notice! += " " + L10n.t("Margem estimada ≈ \(margem) s.", "Estimated margin ≈ \(margem) s.")
            }
        } catch let APIError.badStatus(_, body) {
            feedback = nameSaved
                ? ProtectionSave.partialFeedback(refused: Array(rest.keys), motivo: ProtectionRefusal.motivo(body))
                : await refused(body)
        } catch {
            feedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
        }
    }

    private func setDryRun(_ on: Bool) async {
        guard let instance, let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado.", "Service down.")
            return
        }
        do {
            _ = try await APIClient(endpoint: endpoint).updateDevice(id: instance.id, dryRun: on)
            feedback = nil
            notice = on ? L10n.t("Modo ensaio ligado — proteção desarmada.", "Rehearsal on — protection disarmed.")
                        : L10n.t("Proteção ARMADA. Feche a trava no arquivo do serviço.",
                                 "Protection ARMED. Close the lock in the service file.")
            await store.refreshDevices()
            await store.refreshHealth()
        } catch let APIError.badStatus(_, body) {
            feedback = await refused(body)
        } catch {
            feedback = L10n.t("Falha: ", "Failed: ") + error.localizedDescription
        }
    }

    private func remove() async {
        guard let instance, let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado — nada removido.", "Service down — nothing removed.")
            return
        }
        do {
            try await APIClient(endpoint: endpoint).deleteDevice(id: instance.id)
            await store.refreshDevices()
            await store.refreshHealth()
            onClose(nil)
        } catch let APIError.badStatus(_, body) {
            feedback = await refused(body)     // 409 armado: desarme antes
        } catch {
            feedback = L10n.t("Falha ao remover: ", "Remove failed: ") + error.localizedDescription
        }
    }
}
