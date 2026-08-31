// The menu bar icon IS the charge level: the UPS shield fills bottom-up like
// a tank (bolt.shield.fill clipped to the charge fraction over the outline).
// Template image — follows the OS menu bar theme, light or dark.

import AppKit

enum MenuBarIcon {
    static func image(fraction: Double?, live: Bool) -> NSImage {
        let size = NSSize(width: 19, height: 17)
        let image = NSImage(size: size, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let outlineName = live ? "bolt.shield" : "shield.slash"
            guard let outline = NSImage(systemSymbolName: outlineName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return false }
            let drawRect = centered(outline.size, in: rect)
            outline.draw(in: drawRect)

            if live, let fraction,
               let fill = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: nil)?
                   .withSymbolConfiguration(config) {
                NSGraphicsContext.current?.saveGraphicsState()
                let clip = NSRect(
                    x: drawRect.minX, y: drawRect.minY,
                    width: drawRect.width,
                    height: drawRect.height * min(max(fraction, 0), 1)
                )
                NSBezierPath(rect: clip).addClip()
                fill.draw(in: drawRect)
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func centered(_ inner: NSSize, in outer: NSRect) -> NSRect {
        NSRect(
            x: outer.midX - inner.width / 2,
            y: outer.midY - inner.height / 2,
            width: inner.width, height: inner.height
        )
    }
}
