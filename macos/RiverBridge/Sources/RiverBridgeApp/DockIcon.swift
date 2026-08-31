// Dock icon visibility (owner preference, 2026-08-31): .regular shows the
// Dock icon, .accessory makes River Bridge a pure menu bar utility. Applied
// at launch from the stored preference and live from the dropdown toggle.

import AppKit

enum DockIcon {
    static func apply(show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func applyStoredPreference() {
        let show = UserDefaults.standard.object(forKey: "showsDockIcon") as? Bool ?? true
        apply(show: show)
    }
}
