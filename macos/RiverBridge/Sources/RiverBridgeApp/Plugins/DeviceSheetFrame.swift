// A moldura comum de toda folha de dispositivo: cabeçalho (ícone do tipo, o
// nome DIGITADO, o badge, a legenda do tipo), o corpo rolável que cada tipo
// preenche à mão, e o rodapé (feedback, Remover…, Cancelar/Fechar,
// Adicionar/Salvar). O tamanho vem de DeviceSheetMetrics — os mesmos números
// que o teste do Core lê, para a folha caber na janela mínima de 414×480.
//
// Um sheet por vez (HIG): a confirmação de remover é um confirmationDialog
// DENTRO desta moldura, porque a folha é uma NSWindow própria.

import RiverBridgeCore
import SwiftUI

struct DeviceSheetFrame<Content: View>: View {
    let mode: DeviceSheetMode
    let type: DeviceTypeDescriptor
    let typedName: String
    let currentName: String
    let badge: (String, Color)?
    let hostSize: CGSize
    var feedback: String?
    var notice: String?
    var canSave: Bool
    var hasChanges: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    var onBack: (() -> Void)?
    var onRemove: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var showRemoveDialog = false

    private var size: CGSize { DeviceSheetMetrics.size(host: hostSize) }
    private var accent: Color { Theme.accentColor(onBattery: false, lowBattery: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) { content() }
                    .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: DeviceSheetMetrics.minWidth, idealWidth: size.width, maxWidth: size.width,
               minHeight: DeviceSheetMetrics.minHeight, idealHeight: size.height, maxHeight: size.height)
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(L10n.t("Remover \(currentName)?", "Remove \(currentName)?"),
                            isPresented: $showRemoveDialog, titleVisibility: .visible) {
            Button(L10n.t("Remover", "Remove"), role: .destructive) { onRemove?() }
            Button(L10n.t("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("Os eventos gravados continuam no histórico. A chave SSH e o known_hosts semeados por você não são apagados.",
                        "Recorded events stay in the history. The SSH key and the known_hosts you seeded are not deleted."))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: type.symbol)
                .font(.title2)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                // O nome DIGITADO manda no cabeçalho: a pessoa vê o que está
                // prestes a salvar, não o que já está salvo.
                Text(typedName.trimmingCharacters(in: .whitespaces).isEmpty ? currentName : typedName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                if let badge, !mode.isNew {
                    Text(badge.0).font(.caption).foregroundStyle(badge.1)
                } else {
                    Text(type.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// O aviso ocupa a linha de cima, em toda a largura; os botões ficam
    /// inteiros na de baixo (com o aviso ao lado, "Remover dispositivo…"
    /// quebrava em duas linhas — captura de 2026-09-03).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let feedback {
                Label(feedback, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice {
                Label(notice, systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
            Spacer()
            if onRemove != nil, !mode.isNew {
                // HIG destructive-in-a-list: texto vermelho, não um bloco cheio.
                Button(role: .destructive) { showRemoveDialog = true } label: {
                    Text(L10n.t("Remover dispositivo…", "Remove device…"))
                        .foregroundStyle(.red)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            if let onBack, mode.isNew {
                Button(L10n.t("Voltar", "Back")) { onBack() }
                    .buttonStyle(.glass)
            }
            Button(mode.isNew ? L10n.t("Cancelar", "Cancel") : L10n.t("Fechar", "Close")) { onClose() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button(mode.isNew ? L10n.t("Adicionar", "Add") : L10n.t("Salvar", "Save")) { onSave() }
                .buttonStyle(.glassProminent)
                .tint(accent)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// A linha de armamento de uma instância: o estado do ensaio (vindo do health,
/// nunca de uma cópia local), a trava do dono, e o botão que desliga o ensaio
/// SÓ depois de uma confirmação — nunca um Toggle ligado ao estado.
struct ArmingRow: View {
    let dryRun: Bool
    let enabled: Bool
    let armAllowed: Bool
    let onTurnOffRehearsal: () -> Void
    let onTurnOnRehearsal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: dryRun ? "theatermasks.fill" : "bolt.shield.fill")
                .frame(width: 26)
                .foregroundStyle(dryRun ? Color.secondary : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(dryRun ? L10n.t("Modo ensaio", "Rehearsal mode")
                            : L10n.t("ARMADA — desliga o aparelho de verdade", "ARMED — really shuts the device down"))
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
                Button(role: .destructive) { onTurnOffRehearsal() } label: {
                    Text(L10n.t("Desligar modo ensaio…", "Turn rehearsal off…"))
                        .foregroundStyle(armAllowed && enabled ? Color.red : Color.secondary)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!armAllowed || !enabled)
            } else {
                Button(L10n.t("Ligar modo ensaio", "Turn rehearsal on")) { onTurnOnRehearsal() }
                    .buttonStyle(.glass)
            }
        }
    }
}
