// "Adicionar dispositivo…": UMA folha em duas etapas (HIG: um sheet por vez,
// nunca dois empilhados). Etapa 1, a lista de tipos — ícone, rótulo e uma
// linha de descrição, do registro estático do app; um tipo que o catálogo do
// serviço instalado não tem aparece em cinza, com o motivo. Etapa 2, o
// formulário do tipo em modo NOVO, desenhado pelo próprio tipo, com "Voltar"
// no rodapé. Ao concluir, a folha fecha e devolve o id criado para a lista
// acender a linha nova.

import RiverBridgeCore
import SwiftUI

struct AddDeviceSheet: View {
    var store: TelemetryStore
    var hostSize: CGSize
    /// `--seam-folha novo:<tipo>` (e o teste de olho) entram já na etapa 2.
    var initialType: DeviceTypeDescriptor?
    var onClose: (_ createdID: String?) -> Void

    @State private var chosen: DeviceTypeDescriptor?
    @State private var started = false

    private var size: CGSize { DeviceSheetMetrics.size(host: hostSize) }
    private var accent: Color {
        Theme.accentColor(onBattery: store.isOnBattery, lowBattery: store.isLowBattery)
    }

    var body: some View {
        Group {
            if let chosen, let ui = DevicePluginUIRegistry.plugin(typeID: chosen.id) {
                ui.settingsSheet(mode: .new(chosen), store: store, hostSize: hostSize,
                                 onBack: { self.chosen = nil }, onClose: onClose)
            } else {
                typeList
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            chosen = initialType
        }
    }

    private var typeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Adicionar dispositivo", "Add device"))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(L10n.t("Escolha o que a ponte deve desligar numa queda.",
                                "Choose what the bridge should shut down in an outage."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(DeviceTypeRegistry.all) { type in
                        typeRow(type)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.t("Cancelar", "Cancel")) { onClose(nil) }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        // Quadro FIXO, o mesmo de DeviceSheetFrame (e pelo mesmo motivo medido).
        .frame(width: size.width, height: size.height)
    }

    /// O catálogo diz o que o serviço INSTALADO sabe construir. Só se ele chegou
    /// e não lista o tipo é que a linha apaga — sem catálogo não há o que afirmar.
    private func available(_ type: DeviceTypeDescriptor) -> Bool {
        store.deviceTypes.isEmpty || store.deviceTypes.contains { $0.id == type.id }
    }

    @ViewBuilder
    private func typeRow(_ type: DeviceTypeDescriptor) -> some View {
        let noCatalogo = available(type)
        let comTela = DevicePluginUIRegistry.plugin(typeID: type.id) != nil
        let ok = noCatalogo && comTela
        let legenda = !noCatalogo
            ? L10n.t("O serviço instalado não tem este tipo.", "The installed service lacks this type.")
            : !comTela ? L10n.t("Este tipo ainda não tem tela neste app.", "This type has no screen in this app yet.")
            : type.blurb
        Button {
            chosen = type
        } label: {
            HStack(spacing: 14) {
                Image(systemName: type.symbol)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.06)))
                    .foregroundStyle(ok ? accent : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(type.label)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(ok ? Color.primary : Color.secondary)
                    Text(legenda)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ok)
        .hoverLift(glow: accent)
    }
}
