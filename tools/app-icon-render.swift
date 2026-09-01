// app-icon-render.swift — renders the River Bridge master icon (1024pt, retina-scaled
// by AppKit) to the PNG path given as argv[1]. Single source of truth for the icon:
// tools/make-app-icon.sh (AppIcon.icns) and tools/gera-logo.py (terminal logo) both
// run this file, so the installer's opening always shows the real app icon.
// Renders the 1024x1024 master icon with AppKit. English comments per house rule.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let full = NSRect(origin: .zero, size: size)
// Apple's squircle-ish mask (the system re-masks, but full-bleed must look right).
let squircle = NSBezierPath(roundedRect: full.insetBy(dx: 60, dy: 60), xRadius: 210, yRadius: 210)

// Deep energy gradient: near-black navy -> teal, the app's night palette.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.12, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.32, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.65, blue: 0.55, alpha: 1),
])!
gradient.draw(in: squircle, angle: 65)

// Aurora glow pooling at the bottom.
let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.15, green: 0.9, blue: 0.7, alpha: 0.55),
    NSColor.clear,
])!
squircle.addClip()
glow.draw(in: NSRect(x: 112, y: 60, width: 800, height: 500), relativeCenterPosition: .zero)

// Shield glyph, big and translucent with a specular top light.
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .medium)
if let shield = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: shield.size)
    tinted.lockFocus()
    NSColor.white.withAlphaComponent(0.92).set()
    let r = NSRect(origin: .zero, size: shield.size)
    shield.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    let target = NSRect(x: (1024 - tinted.size.width) / 2,
                        y: (1024 - tinted.size.height) / 2 - 10,
                        width: tinted.size.width, height: tinted.size.height)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.1, green: 0.95, blue: 0.75, alpha: 0.8)
    shadow.shadowBlurRadius = 60
    shadow.set()
    tinted.draw(in: target)
}

// Specular highlight band across the top of the squircle.
let spec = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.28),
    NSColor.white.withAlphaComponent(0.0),
])!
spec.draw(in: NSRect(x: 60, y: 620, width: 904, height: 344), angle: -90)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render do ícone falhou")
}
try png.write(to: out)
