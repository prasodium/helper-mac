import AppKit

// Renders the Helper app icon (a macOS-style rounded square with a sparkle)
// into an .iconset folder: swift scripts/make-icon.swift <out.iconset>

func render(size: Int) -> Data {
    let px = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's icon grid: the artwork fills ~80% of the canvas.
    let inset = px * 0.098
    let rect = NSRect(x: inset, y: inset, width: px - inset * 2, height: px - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -px * 0.012), blur: px * 0.03,
                                                   color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    NSGradient(colors: [NSColor(red: 0.36, green: 0.55, blue: 1.0, alpha: 1), NSColor(red: 0.45, green: 0.27, blue: 0.95, alpha: 1)])!
        .draw(in: path, angle: -60)

    let config = NSImage.SymbolConfiguration(pointSize: px * 0.46, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let s = tinted.size
        tinted.draw(in: NSRect(x: (px - s.width) / 2, y: (px - s.height) / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
