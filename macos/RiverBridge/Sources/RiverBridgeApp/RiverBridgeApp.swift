// River Bridge — menu bar + janela (spec §7A). A UI é cliente do daemon:
// some o daemon, a UI degrada para "serviço parado"; nunca o contrário.
// Janela sem barra de título: o conteúdo (aurora + vidro) vai até a borda.

import RiverBridgeCore
import SwiftUI

/// Dock-icon reopen (owner 2026-08-31), via the documented AppKit hook
/// applicationShouldHandleReopen(_:hasVisibleWindows:): clicking the Dock
/// icon with no visible window reopens the panel. The callback is registered
/// by the menu bar label (always alive) with its openWindow action.
@MainActor
final class ReopenDelegate: NSObject, NSApplicationDelegate {
    static var abrirPainel: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.abrirPainel?() }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

/// Menu bar label wrapper: the one view alive for the app's whole life —
/// the right home for registering the reopen callback.
private struct MenuBarLabelHost: View {
    var store: TelemetryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabel(store: store)
            .onAppear {
                ReopenDelegate.abrirPainel = { openWindow(id: "main") }
            }
    }
}

@main
struct RiverBridgeApp: App {
    @State private var store = TelemetryStore()
    @State private var prefs = AppPrefs.shared
    @NSApplicationDelegateAdaptor(ReopenDelegate.self) private var reopenDelegate

    /// Único mecanismo de seam do app (AppPrefs.seamValue), como os demais.
    private static let seamWidth: CGFloat? = {
        guard let raw = AppPrefs.seamValue("--seam-largura"), let value = Double(raw) else { return nil }
        return CGFloat(value)
    }()
    /// `--seam-altura N`: o par do de largura, para fotografar a janela mínima
    /// (414×480) com uma folha aberta (2026-09-03).
    private static let seamHeight: CGFloat? = {
        guard let raw = AppPrefs.seamValue("--seam-altura"), let value = Double(raw) else { return nil }
        return CGFloat(value)
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(store: store)
                .id(prefs.language)   // rebuild on language change
        } label: {
            MenuBarLabelHost(store: store)
        }
        .menuBarExtraStyle(.window)

        // A janela aparece AO ABRIR o programa. Sem isto, quem abria o River
        // Bridge via só o ícone no Dock e a barra de menu — a tela só surgia
        // depois de um clique no Dock, o que ninguém adivinha (dono, no Mac
        // mini, 2026-09-05).
        Window("River Bridge", id: "main") {
            DashboardWindow(store: store)
                // Min width = iPhone XR width (owner 2026-08-31): shrinking
                // below 520pt flips to the vertical phone layout — the window
                // doubles as an iPhone preview. Floors allow a 414×896 shape.
                .frame(minWidth: 414, minHeight: 480)
                // Translucent window (owner 2026-08-31): the desktop reads
                // through the material, so the control glass floats over a
                // living ground instead of a poster.
                .containerBackground(for: .window) {
                    BehindWindowBlur().ignoresSafeArea()
                }
                .task {
                    store.start()
                    applyAppearance()
                }
                .onChange(of: prefs.themeMode) { applyAppearance() }
        }
        // `--seam-largura N` existe para a CAPTURA: até aqui não havia mecanismo
        // para fotografar a janela estreita (as capturas antigas a 414 pt eram
        // prints do dono). `.restorationBehavior(.disabled)` abaixo faz o default
        // valer em todo lançamento, então o seam pega.
        .defaultSize(width: Self.seamWidth ?? 1000, height: Self.seamHeight ?? 880)
        .windowStyle(.hiddenTitleBar)
        // A power panel always opens on Energia — never on a restored tab.
        .restorationBehavior(.disabled)
        // E ela ABRE ao lançar o programa. Com `.restorationBehavior(.disabled)`
        // não há janela restaurada, e um programa que também vive na barra de
        // menu não abre janela sozinho: quem abria o River Bridge via só o ícone
        // no Dock e nada mais, até clicar no Dock de novo (dono, no Mac mini,
        // 2026-09-05). É o comportamento documentado de `defaultLaunchBehavior`.
        .defaultLaunchBehavior(.presented)
    }

    /// True behind-window translucency. SwiftUI's containerBackground with a
    /// material KEPT THE NSWINDOW OPAQUE — measured with the red-window
    /// probe: leak 0 (owner: "o app ainda não tem transparência"). The AppKit
    /// path that actually works: NSVisualEffectView blending .behindWindow on
    /// a non-opaque, clear-background window.
    private struct BehindWindowBlur: NSViewRepresentable {
        private func makeTransparent(_ view: NSVisualEffectView) {
            DispatchQueue.main.async {
                if let win = view.window {
                    win.isOpaque = false
                    win.backgroundColor = .clear
                }
            }
        }

        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .hudWindow   // o material translúcido de verdade (owner: 55%+under nada mudou a olho)
            view.blendingMode = .behindWindow
            view.state = .active
            makeTransparent(view)
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {
            makeTransparent(view)
        }
    }

    /// ONE theme mechanism, the AppKit one: preferredColorScheme(nil) does
    /// NOT return a window to the system scheme once a non-nil scheme was
    /// applied (owner's bug: Claro -> Auto stuck on Claro). NSApp.appearance
    /// = nil follows the system again immediately; named appearances force.
    private func applyAppearance() {
        switch prefs.themeMode {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
