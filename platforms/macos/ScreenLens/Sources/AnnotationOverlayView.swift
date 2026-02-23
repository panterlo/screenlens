import AppKit

/// Transparent overlay that renders annotations on top of the image.
/// Passes all hit-tests through to the canvas beneath.
class AnnotationOverlayView: NSView {

    var annotations: [Annotation] = []
    var selectedAnnotationId: String?
    var hiddenAnnotationId: String?
    var creationPreview: Annotation?
    var imageRect: NSRect = .zero       // aspect-fit rect of the image in view coords
    var imageSize: NSSize = .zero       // original image pixel dimensions

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ aPoint: NSPoint) -> NSView? { nil }

    // MARK: - Coordinate conversion

    private var scale: CGFloat {
        guard imageSize.width > 0 && imageRect.width > 0 else { return 1 }
        return imageRect.width / imageSize.width
    }

    /// Convert image-pixel point to view point.
    func imageToView(_ p: NSPoint) -> NSPoint {
        NSPoint(x: imageRect.origin.x + p.x * scale,
                y: imageRect.origin.y + p.y * scale)
    }

    /// Convert image-pixel rect to view rect.
    func imageRectToView(_ r: NSRect) -> NSRect {
        NSRect(x: imageRect.origin.x + r.origin.x * scale,
               y: imageRect.origin.y + r.origin.y * scale,
               width: r.width * scale, height: r.height * scale)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard imageRect.width > 0 else { return }
        let s = scale

        // Save graphics state and clip to image area
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: imageRect).addClip()

        // Translate so image origin = drawing origin
        let transform = NSAffineTransform()
        transform.translateX(by: imageRect.origin.x, yBy: imageRect.origin.y)
        transform.concat()

        for annotation in annotations {
            if annotation.id == hiddenAnnotationId { continue }
            AnnotationRenderer.draw(annotation, scale: s)
            if annotation.id == selectedAnnotationId {
                drawSelectionHandles(for: annotation, scale: s)
            }
        }

        if let preview = creationPreview {
            AnnotationRenderer.draw(preview, scale: s)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Returns handle center positions in scaled coordinates (relative to image origin, already multiplied by scale).
    /// For rectangles/text: 4 corners [minX-minY, maxX-minY, maxX-maxY, minX-maxY].
    /// For arrows: 2 endpoints [start, end].
    func handlePositions(for annotation: Annotation, scale s: CGFloat) -> [NSPoint] {
        switch annotation.type {
        case .arrow:
            if let line = annotation.geometry.line {
                return [
                    NSPoint(x: line.start.x * s, y: line.start.y * s),
                    NSPoint(x: line.end.x * s, y: line.end.y * s),
                ]
            }
        case .rectangle, .text:
            if let r = annotation.geometry.rect {
                let vr = NSRect(x: r.origin.x * s, y: r.origin.y * s,
                                width: r.width * s, height: r.height * s)
                return [
                    NSPoint(x: vr.minX, y: vr.minY),
                    NSPoint(x: vr.maxX, y: vr.minY),
                    NSPoint(x: vr.maxX, y: vr.maxY),
                    NSPoint(x: vr.minX, y: vr.maxY),
                ]
            }
        }
        return []
    }

    private func drawSelectionHandles(for annotation: Annotation, scale s: CGFloat) {
        let handleSize: CGFloat = 8
        let points = handlePositions(for: annotation, scale: s)

        for p in points {
            let handleRect = NSRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2,
                                    width: handleSize, height: handleSize)
            NSColor.white.setFill()
            NSBezierPath(rect: handleRect).fill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: handleRect)
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}
