import AppKit

/// A transparent fullscreen overlay that lets the user drag-select a region.
class RegionSelectorWindow: NSWindow {

    var onRegionSelected: ((NSRect) -> Void)?
    var onCancelled: (() -> Void)?

    private var startPoint: NSPoint = .zero
    private var currentRect: NSRect = .zero
    private var isSelecting = false

    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.contentView = RegionOverlayView(frame: screen.frame)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentRect = .zero
        isSelecting = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        let current = event.locationInWindow
        currentRect = NSRect(
            x: min(startPoint.x, current.x),
            y: min(startPoint.y, current.y),
            width: abs(current.x - startPoint.x),
            height: abs(current.y - startPoint.y)
        )
        if let overlay = contentView as? RegionOverlayView {
            overlay.selectionRect = currentRect
            overlay.needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting else { return }
        isSelecting = false

        if currentRect.width > 5 && currentRect.height > 5 {
            onRegionSelected?(currentRect)
        } else {
            onCancelled?()
        }
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancelled?()
            close()
        }
    }
}

/// Custom view that draws the semi-transparent overlay and selection rectangle.
class RegionOverlayView: NSView {
    var selectionRect: NSRect = .zero

    override func draw(_ dirtyRect: NSRect) {
        // Draw dimmed overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        guard selectionRect.width > 0 && selectionRect.height > 0 else { return }

        // Clear the selected region (make it transparent)
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)

        // Draw border around selection
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2
        path.stroke()

        // Draw dimension label
        let label = String(format: "%d × %d", Int(selectionRect.width), Int(selectionRect.height))
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .backgroundColor: NSColor.black.withAlphaComponent(0.7),
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelPoint = NSPoint(
            x: selectionRect.midX - labelSize.width / 2,
            y: selectionRect.maxY + 4
        )
        label.draw(at: labelPoint, withAttributes: attrs)
    }
}
