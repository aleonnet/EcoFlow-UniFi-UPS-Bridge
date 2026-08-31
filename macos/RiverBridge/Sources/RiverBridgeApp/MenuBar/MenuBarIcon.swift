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

            guard live, let fraction,
                  let fill = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: nil)?
                      .withSymbolConfiguration(config) else {
                outline.draw(in: drawRect)
                return true
            }

            // Complementary clips — never both layers in the same region:
            // below the level only the FILL (its knocked-out bolt lets the
            // menu bar show through = contrast); above it only the outline.
            let level = drawRect.height * min(max(fraction, 0), 1)
            let bottom = NSRect(x: drawRect.minX, y: drawRect.minY,
                                width: drawRect.width, height: level)
            let top = NSRect(x: drawRect.minX, y: drawRect.minY + level,
                             width: drawRect.width, height: drawRect.height - level)

            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: bottom).addClip()
            fill.draw(in: drawRect)
            NSGraphicsContext.current?.restoreGraphicsState()

            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: top).addClip()
            outline.draw(in: drawRect)
            NSGraphicsContext.current?.restoreGraphicsState()
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
