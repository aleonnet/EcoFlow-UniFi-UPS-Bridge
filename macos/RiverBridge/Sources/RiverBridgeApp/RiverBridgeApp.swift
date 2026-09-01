// River Bridge — menu bar + janela (spec §7A). A UI é cliente do daemon:
// some o daemon, a UI degrada para "serviço parado"; nunca o contrário.
// Janela sem barra de título: o conteúdo (aurora + vidro) vai até a borda.

import RiverBridgeCore
import SwiftUI

@main
struct RiverBridgeApp: App {
    @State private var store = TelemetryStore()
    @State private var prefs = AppPrefs.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(store: store)
                .id(prefs.language)   // rebuild on language change
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

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
        .defaultSize(width: 1000, height: 880)
        .windowStyle(.hiddenTitleBar)
        // A power panel always opens on Energia — never on a restored tab.
        .restorationBehavior(.disabled)
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
            view.material = .underWindowBackground
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
