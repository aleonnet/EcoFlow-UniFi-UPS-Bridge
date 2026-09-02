// A folha de configuração do UDR7. Era o grupo "Proteção do UDR7" dentro de
// Ajustes; virou folha quando o dispositivo passou a ser um plugin com nome
// próprio. O campo NOME abre a folha: é a primeira coisa que a pessoa decide.
//
// Salvamento em DOIS PUTs, e a ordem importa: o nome primeiro, sozinho. Ele é
// aceito com a proteção armada (é hot e não está em PROTECTION_KEYS), enquanto o
// resto pode voltar 409. Num PUT único, um limiar recusado levaria o rename
// junto. Cada PUT é PULADO quando o seu lado do diff está vazio.

import RiverBridgeCore
import SwiftUI

struct Udr7SettingsSheet: View {
    var store: TelemetryStore
    var hostSize: CGSize
    var onClose: () -> Void

    @State private var name = ""
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
    @State private var armAllowed = false
    @State private var baseline: [String: String] = [:]
    @State private var loaded = false
    @State private var feedback: String?
    @State private var notice: String?
    @State private var showArmDialog = false

    /// Pisos: a janela-mãe pode encolher até 414×480, então a folha tem de caber
    /// em 374×440. São eles que decidem quando as linhas empilham.
    static let minLargura: CGFloat = 340
    static let minAltura: CGFloat = 380
    /// Abaixo desta largura, rótulo e campo empilham — é o mesmo ponto de corte
    /// que a barra de filtros usa, e o que um telefone exigiria.
    static let larguraEstreita: CGFloat = 420

    private var largura: CGFloat {
        max(Self.minLargura, min(600, hostSize.width - 40))
    }
    private var altura: CGFloat {
        max(Self.minAltura, min(640, hostSize.height - 40))
    }
    private var estreito: Bool { largura < Self.larguraEstreita }

    private var descriptor: DevicePluginDescriptor { .udr7 }
    private var detail: Udr7Detail? { store.health?.pluginDetail(id: descriptor.id) }
    /// Estado vindo do HEALTH, nunca de uma cópia local: o badge do cartão e esta
    /// folha mostram a mesma coisa porque leem a mesma fonte.
    private var dryRun: Bool { detail?.dryRun ?? true }
    private var enabled: Bool { detail?.enabled == true }
    private var currentName: String { store.deviceNames.name(for: descriptor) }
    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsRows.group(L10n.t("Dispositivo", "Device")) {
                        SettingsRows.textRow("tag", L10n.t("Nome", "Name"), $name,
                                             placeholder: descriptor.defaultName, estreito: estreito)
                    }
                    SettingsRows.group(L10n.t("Armamento", "Arming")) { armingRow }
                    SettingsRows.group(L10n.t("Console e chave", "Console and key")) {
                        SettingsRows.textRow("network", L10n.t("Console (host)", "Console (host)"), $sshHost, placeholder: "192.168.1.1", estreito: estreito)
                        SettingsRows.divider
                        SettingsRows.textRow("number", L10n.t("Porta SSH", "SSH port"), $sshPort, placeholder: "22", numeric: true, estreito: estreito)
                        SettingsRows.divider
                        SettingsRows.textRow("person.fill", L10n.t("Usuário SSH", "SSH user"), $sshUser, placeholder: "root", estreito: estreito)
                        SettingsRows.divider
                        SettingsRows.textRow("key.fill", L10n.t("Chave privada (caminho absoluto)", "Private key (absolute path)"),
                                             $sshKey, placeholder: "/Users/…/.ssh/river-bridge-udr7", estreito: estreito)
                        SettingsRows.divider
                        SettingsRows.textRow("barcode", L10n.t("Serial do River (upsc device.serial)", "River serial (upsc device.serial)"),
                                             $expectedSerial, placeholder: "R3P…", estreito: estreito)
                    }
                    SettingsRows.group(L10n.t("Limiares", "Thresholds")) {
                        SettingsRows.sliderRow("battery.0percent", L10n.t("Corte físico do River", "River physical cutoff"),
                                               value: $cutoff, range: 0...48, unit: "%",
                                               zeroLabel: L10n.t("não configurado", "not set"), accent: accent, estreito: estreito)
                        SettingsRows.divider
                        SettingsRows.sliderRow("power.circle", L10n.t("Desligar o console em", "Shut the console down at"),
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
                        SettingsRows.divider
                        SettingsRows.textRow("wake", L10n.t("MAC para religar (WoL, opcional)", "Wake MAC (WoL, optional)"),
                                             $wolMac, placeholder: "aa:bb:cc:dd:ee:ff", estreito: estreito)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        // A folha cabe DENTRO da janela-mãe no menor tamanho dela (414×480), com
        // 20 pt de folga em cada eixo — antes o minWidth era 380 contra 374 de
        // espaço útil, e a ALTURA não era limitada de forma nenhuma: a folha
        // vazava para fora da janela (visto pelo dono em 2026-09-01).
        .frame(minWidth: Self.minLargura, idealWidth: largura, maxWidth: largura,
               minHeight: Self.minAltura, idealHeight: altura, maxHeight: altura)
        .interactiveDismissDisabled(!changes().isEmpty)
        .task { await load() }
        .confirmationDialog(arming.title, isPresented: $showArmDialog, titleVisibility: .visible) {
            Button(arming.confirmLabel, role: .destructive) { Task { await setDryRun(false) } }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(arming.message)
        }
    }

    private var arming: ArmConfirmation {
        ArmConfirmation(name: currentName, mode: .turnOffRehearsal)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: descriptor.symbol)
                .font(.title2)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                // O nome DIGITADO manda no cabeçalho: a pessoa vê o que está
                // prestes a salvar, não o que já está salvo.
                Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? currentName : name)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                if let badge = Udr7Plugin().badge(state: detail?.state) {
                    Text(badge.0).font(.caption).foregroundStyle(badge.1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var armingRow: some View {
        HStack(spacing: 10) {
            Image(systemName: dryRun ? "theatermasks.fill" : "bolt.shield.fill")
                .frame(width: 26)
                .foregroundStyle(dryRun ? Color.secondary : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(dryRun ? L10n.t("Modo ensaio", "Rehearsal mode")
                            : L10n.t("ARMADA — desliga o console de verdade", "ARMED — really shuts the console down"))
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
                // Botão + confirmação, NUNCA um Toggle ligado ao estado: o toggle
                // faria o PUT antes de a pessoa confirmar.
                Button(role: .destructive) { showArmDialog = true } label: {
                    Text(L10n.t("Desligar modo ensaio…", "Turn rehearsal off…"))
                        .foregroundStyle(armAllowed && enabled ? Color.red : Color.secondary)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!armAllowed || !enabled)
            } else {
                Button(L10n.t("Ligar modo ensaio", "Turn rehearsal on")) {
                    Task { await setDryRun(true) }      // desarme: sempre aceito
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let feedback {
                Label(feedback, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.t("Fechar", "Close")) { onClose() }
                .buttonStyle(.glass)
            Button(L10n.t("Salvar", "Save")) { Task { await save() } }
                .buttonStyle(.glassProminent)
                .tint(accent)
                // `loaded` no disabled: sem ele, o botão nasce habilitado com os
                // campos ainda vazios e o baseline vazio, e um clique salvaria
                // placeholders por cima da configuração real.
                .disabled(!loaded || changes().isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Valores e diff

    /// Os valores do formulário em forma de .env. PROTECT_DRY_RUN não está aqui:
    /// viaja sozinho, pela regra de desarme puro do daemon.
    private func values() -> [String: String] {
        var out: [String: String] = [descriptor.nameKey: name.trimmingCharacters(in: .whitespaces)]
        let porChave: [String: String] = [
            "UDR7_SSH_HOST": sshHost, "UDR7_SSH_PORT": sshPort, "UDR7_SSH_USER": sshUser,
            "UDR7_SSH_KEY": sshKey, "UDR7_EXPECTED_SERIAL": expectedSerial, "UDR7_WOL_MAC": wolMac,
            "UDR7_CUTOFF_PERCENT": String(cutoff), "UDR7_SHUTDOWN_PERCENT": String(shutdown),
            "UDR7_DISCHARGE_SECONDS_PER_PCT": dischargeSecPerPct,
            "UDR7_RUNTIME_MINUTES": runtimeMinutes, "UDR7_MIN_OUTAGE_SECONDS": minOutage,
            "UDR7_CONFIRM_SECONDS": confirmSeconds,
        ]
        // Itera sheetKeys, não o dicionário: o descritor é quem declara o que a
        // folha edita, e uma chave nova lá aparece aqui sem edição.
        for key in descriptor.sheetKeys {
            if let value = porChave[key] { out[key] = value.trimmingCharacters(in: .whitespaces) }
        }
        return out
    }

    private func changes() -> [String: String] {
        values().filter { baseline[$0.key] != $0.value }
    }

    // MARK: - IO

    private func load() async {
        guard !loaded, let endpoint = ApiEndpoint.discover() else { return }
        guard let response = try? await APIClient(endpoint: endpoint).config() else { return }
        let cfg = response.config
        name = cfg["udr7_name"]?.stringValue ?? ""
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
        baseline = values()
        loaded = true
    }

    private func save() async {
        guard let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado — nada salvo.", "Service down — nothing saved.")
            return
        }
        let client = APIClient(endpoint: endpoint)
        let split = ProtectionSave.split(changes: changes(), nameKey: descriptor.nameKey)
        var nameSaved = false

        if let novo = split.name {
            do {
                _ = try await client.putConfig([descriptor.nameKey: novo])
                baseline[descriptor.nameKey] = novo
                nameSaved = true
                await store.refreshHealth()
            } catch let APIError.badStatus(_, body) {
                feedback = ProtectionRefusal.text(body)
                return                                  // nome recusado é falha total
            } catch {
                feedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
                return
            }
        }

        guard !split.rest.isEmpty else {
            if nameSaved { notice = L10n.t("Nome salvo.", "Name saved."); feedback = nil }
            return
        }
        do {
            let result = try await client.putConfig(split.rest)
            for (key, value) in split.rest { baseline[key] = value }
            feedback = nil
            notice = "\(split.rest.count) " + L10n.t("chave(s) salva(s).", "key(s) saved.")
            if result.restartRequired {
                notice! += " " + L10n.t("Reinicie o serviço para aplicar.", "Restart the service to apply.")
            }
            await store.refreshHealth()
            if let margem = detail?.marginEstimateS {
                notice! += " " + L10n.t("Margem estimada ≈ \(margem) s.", "Estimated margin ≈ \(margem) s.")
            }
        } catch let APIError.badStatus(_, body) {
            feedback = nameSaved
                ? ProtectionSave.partialFeedback(refused: Array(split.rest.keys),
                                                 motivo: ProtectionRefusal.motivo(body))
                : ProtectionRefusal.text(body)
        } catch {
            feedback = L10n.t("Falha ao salvar: ", "Save failed: ") + error.localizedDescription
        }
    }

    private func setDryRun(_ on: Bool) async {
        guard let endpoint = ApiEndpoint.discover() else {
            feedback = L10n.t("Serviço parado.", "Service down.")
            return
        }
        do {
            _ = try await APIClient(endpoint: endpoint).putConfig(["PROTECT_DRY_RUN": on ? "1" : "0"])
            feedback = nil
            notice = on ? L10n.t("Modo ensaio ligado — proteção desarmada.", "Rehearsal on — protection disarmed.")
                        : L10n.t("Proteção ARMADA. Feche a trava no arquivo do serviço (passo 8 do runbook).",
                                 "Protection ARMED. Close the lock in the service file (runbook step 8).")
            await store.refreshHealth()
        } catch let APIError.badStatus(_, body) {
            feedback = ProtectionRefusal.text(body)
        } catch {
            feedback = L10n.t("Falha: ", "Failed: ") + error.localizedDescription
        }
    }
}
