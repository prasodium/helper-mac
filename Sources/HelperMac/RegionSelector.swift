import AppKit

/// Full-screen "drag to select" overlay, like the system screenshot tool.
/// It shows a frozen copy of the screen so what you select is what you get.
@MainActor
final class RegionSelector {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CGImage?, Never>?

    /// Returns the cropped region, or nil if the user pressed Esc / clicked without dragging.
    func select(from image: CGImage, on screen: NSScreen) async -> CGImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            self.continuation = continuation
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image)
            view.onFinish = { [weak self] cropped in self?.finish(cropped) }
            window.contentView = view
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            NSCursor.crosshair.push()
        }
    }

    private func finish(_ image: CGImage?) {
        NSCursor.pop()
        window?.orderOut(nil)
        window = nil
        continuation?.resume(returning: image)
        continuation = nil
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    let image: CGImage
    var onFinish: ((CGImage?) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(image, in: bounds)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)
        guard let rect = selection, rect.width > 1, rect.height > 1 else { return }
        // Punch the selection back to the bright original.
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()

        let label = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        let tag = NSRect(x: rect.minX, y: max(rect.minY - size.height - 8, 2), width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: tag, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: tag.minX + 5, y: tag.minY + 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let rect = selection, rect.width > 8, rect.height > 8 else { onFinish?(nil); return }
        // View points -> image pixels (the view's y axis points up, images' down).
        let sx = CGFloat(image.width) / bounds.width
        let sy = CGFloat(image.height) / bounds.height
        let crop = CGRect(x: rect.minX * sx, y: (bounds.height - rect.maxY) * sy,
                          width: rect.width * sx, height: rect.height * sy).integral
        onFinish?(image.cropping(to: crop))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } // Esc
    }
}
