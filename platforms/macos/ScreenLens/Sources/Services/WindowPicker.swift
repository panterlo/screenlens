import AppKit
import ScreenCaptureKit

/// Visual window picker overlay — hover over windows to highlight, click to select.
class WindowPickerWindow: NSWindow {

    var onWindowSelected: ((SCWindow) -> Void)?
    var onCancelled: (() -> Void)?

    private var overlayView: WindowPickerOverlayView!

    convenience init(screen: NSScreen, windows: [SCWindow]) {
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

        overlayView = WindowPickerOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size)
        )
        overlayView.pickerWindow = self
        overlayView.windows = windows
        overlayView.screenFrame = screen.frame
        self.contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func cancelSelection() {
        onCancelled?()
        DispatchQueue.main.async { self.close() }
    }

    func selectWindow(_ window: SCWindow) {
        onWindowSelected?(window)
        DispatchQueue.main.async { self.close() }
    }
}

class WindowPickerOverlayView: NSView {
    weak var pickerWindow: WindowPickerWindow?
    var windows: [SCWindow] = []
    var screenFrame: CGRect = .zero
    private var highlightedWindow: SCWindow?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    /// Convert SCWindow frame (top-left origin) to view coords (bottom-left origin).
    private func viewRect(for window: SCWindow) -> NSRect {
        let x = window.frame.origin.x - screenFrame.origin.x
        let y = screenFrame.height - (window.frame.origin.y - screenFrame.origin.y) - window.frame.height
        return NSRect(x: x, y: y, width: window.frame.width, height: window.frame.height)
    }

    private func windowAt(point: NSPoint) -> SCWindow? {
        // SCShareableContent returns windows front-to-back, so first match is frontmost
        for window in windows {
            let rect = viewRect(for: window)
            if rect.contains(point) {
                return window
            }
        }
        return nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            pickerWindow?.cancelSelection()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newHighlight = windowAt(point: point)
        if newHighlight?.windowID != highlightedWindow?.windowID {
            highlightedWindow = newHighlight
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let window = windowAt(point: point) {
            pickerWindow?.selectWindow(window)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim the entire screen with highlighted window cut out
        let overlayPath = NSBezierPath(rect: bounds)
        if let highlighted = highlightedWindow {
            let rect = viewRect(for: highlighted)
            if rect.width > 0 && rect.height > 0 {
                overlayPath.append(NSBezierPath(rect: rect).reversed)
            }
        }
        NSColor.black.withAlphaComponent(0.3).setFill()
        overlayPath.fill()

        guard let highlighted = highlightedWindow else { return }
        let rect = viewRect(for: highlighted)

        // Draw highlight border
        NSColor.systemBlue.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 3
        borderPath.stroke()

        // Draw window label
        let ownerName = highlighted.owningApplication?.applicationName ?? "Unknown"
        let title = highlighted.title ?? ""
        let label = title.isEmpty ? ownerName : "\(ownerName) — \(title)"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.85),
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelPoint = NSPoint(
            x: rect.midX - labelSize.width / 2,
            y: rect.maxY + 6
        )
        label.draw(at: labelPoint, withAttributes: attrs)
    }
}
