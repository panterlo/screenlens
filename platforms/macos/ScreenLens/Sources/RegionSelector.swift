import AppKit

/// A transparent fullscreen overlay that lets the user drag-select a region.
class RegionSelectorWindow: NSWindow {

    var onRegionSelected: ((NSRect) -> Void)?
    var onCancelled: (() -> Void)?

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
        self.backgroundColor = .clear
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        let overlay = RegionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        overlay.selectorWindow = self
        self.contentView = overlay
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancelled?()
            close()
        }
    }

    func finishSelection(_ rect: NSRect) {
        if rect.width > 5 && rect.height > 5 {
            onRegionSelected?(rect)
        } else {
            onCancelled?()
        }
        // Defer close to next run loop iteration — we're still inside the
        // content view's mouseUp, so closing now would deallocate mid-call.
        DispatchQueue.main.async { [self] in
            close()
        }
    }
}

/// Custom view that draws the semi-transparent overlay, handles mouse events,
/// and draws the selection rectangle.
class RegionOverlayView: NSView {
    weak var selectorWindow: RegionSelectorWindow?
    var selectionRect: NSRect = .zero
    private var startPoint: NSPoint = .zero
    private var isSelecting = false

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        isSelecting = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(startPoint.x, current.x),
            y: min(startPoint.y, current.y),
            width: abs(current.x - startPoint.x),
            height: abs(current.y - startPoint.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting else { return }
        isSelecting = false
        // Convert from view coordinates back to window coordinates for the capture
        selectorWindow?.finishSelection(selectionRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw dimmed overlay with selection region cut out
        let overlayPath = NSBezierPath(rect: bounds)
        if selectionRect.width > 0 && selectionRect.height > 0 {
            overlayPath.append(NSBezierPath(rect: selectionRect).reversed)
        }
        NSColor.black.withAlphaComponent(0.3).setFill()
        overlayPath.fill()

        guard selectionRect.width > 0 && selectionRect.height > 0 else { return }

        // Draw border around selection
        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.lineWidth = 2
        borderPath.stroke()

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
