// Dropdown following Apple's Battery menu anatomy: title + right-aligned
// status, source/autonomy lines, sectioned rows with dividers, hover
// highlight, preference toggle, footer actions. System theme — no custom
// background here; the OS paints the menu chrome.

import RiverBridgeCore
import SwiftUI

struct MenuBarPopover: View {
    var store: TelemetryStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarShowsPercent") private var showsPercent = true
    @AppStorage("showsDockIcon") private var showsDockIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: Espaco.fio) {
            // Title row — like "Battery                    On Hold: 80%"
            HStack {
                Text("River Bridge").font(.headline)
                Spacer()
                if store.phase == .live {
                    Text(store.chargeText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, Espaco.medio)
            .padding(.top, Espaco.micro)

            Group {
                Text(L10n.t("Fonte: ", "Source: ") + store.stateLabel)
                if store.phase == .live {
                    Text(L10n.t("Autonomia: ", "Runtime: ") + store.runtimeText)
                }
                if case .serviceDown(let reason) = store.phase {
                    Text(reason)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Espaco.medio)

            divider

            Text(L10n.t("Telemetria", "Telemetry"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Espaco.medio)
                .padding(.vertical, Espaco.fio)

            metricRow("bolt.fill", L10n.t("Carga", "Load"), store.powerText)
            metricRow("gauge.with.needle", L10n.t("Uso", "Usage"), store.loadText)
            metricRow("powerplug.fill", L10n.t("Saída", "Output"), store.outputVoltageText)

            divider

            MenuRow(
                symbol: showsPercent ? "checkmark.circle.fill" : "circle",
                title: L10n.t("Mostrar percentual na barra", "Show percentage in menu bar")
            ) {
                showsPercent.toggle()
            }
            MenuRow(
                symbol: showsDockIcon ? "checkmark.circle.fill" : "circle",
                title: L10n.t("Mostrar ícone no Dock", "Show Dock icon")
            ) {
                showsDockIcon.toggle()
                DockIcon.apply(show: showsDockIcon)
            }

            divider

            MenuRow(symbol: "rectangle.expand.diagonal", title: L10n.t("Abrir painel…", "Open panel…")) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuRow(symbol: "power", title: L10n.t("Sair do River Bridge", "Quit River Bridge")) {
                NSApp.terminate(nil)
            }
        }
        .padding(Espaco.mini)
        .frame(width: 300)
    }

    private var divider: some View {
        Divider().padding(.vertical, Espaco.micro).padding(.horizontal, Espaco.medio)
    }

    private func metricRow(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.body)
        .padding(.horizontal, Espaco.medio)
        .padding(.vertical, Espaco.micro)
    }
}

/// A row that behaves like a real menu item: full-width hover highlight.
private struct MenuRow: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.body)
            .padding(.horizontal, Espaco.medio)
            .padding(.vertical, Espaco.mini)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Raio.mini)
                .fill(hovering ? Color.primary.opacity(0.1) : .clear)
        )
        .onHover { hovering = $0 }
    }
}
