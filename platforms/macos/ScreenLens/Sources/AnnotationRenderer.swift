import AppKit

/// Shared rendering logic for annotations — used by both the overlay (view coords) and export flattening (image coords).
enum AnnotationRenderer {

    /// Draw a single annotation into the current graphics context.
    /// `scale` converts from image-pixel coords to the target coordinate system.
    static func draw(_ annotation: Annotation, scale: CGFloat = 1.0) {
        let color = NSColor(hexString: annotation.style.color).withAlphaComponent(annotation.style.opacity)
        let lineWidth = annotation.style.lineWidth * scale

        switch annotation.type {
        case .arrow:
            guard let line = annotation.geometry.line else { return }
            let start = NSPoint(x: line.start.x * scale, y: line.start.y * scale)
            let end = NSPoint(x: line.end.x * scale, y: line.end.y * scale)
            drawArrow(from: start, to: end, color: color, lineWidth: lineWidth)

        case .rectangle:
            guard let r = annotation.geometry.rect else { return }
            let rect = NSRect(x: r.origin.x * scale, y: r.origin.y * scale,
                              width: r.width * scale, height: r.height * scale)
            drawRectangle(rect, fill: annotation.style.fill ?? .outline, color: color, lineWidth: lineWidth)

        case .text:
            guard let r = annotation.geometry.rect else { return }
            let rect = NSRect(x: r.origin.x * scale, y: r.origin.y * scale,
                              width: r.width * scale, height: r.height * scale)
            let fontSize = (annotation.style.fontSize ?? 16) * scale
            drawText(annotation.text ?? "", in: rect, color: color, fontSize: fontSize)
        }
    }

    private static func drawArrow(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        color.setStroke()

        // Shaft
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()

        // Arrowhead
        let headLength: CGFloat = max(12 * (lineWidth / 3), 8)
        let headAngle: CGFloat = .pi / 6
        let angle = atan2(end.y - start.y, end.x - start.x)

        let arrow = NSBezierPath()
        arrow.lineWidth = lineWidth
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)))
        arrow.line(to: end)
        arrow.line(to: NSPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)))
        arrow.stroke()
    }

    private static func drawRectangle(_ rect: NSRect, fill: RectangleFill, color: NSColor, lineWidth: CGFloat) {
        switch fill {
        case .outline:
            color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            path.stroke()
        case .solid:
            color.setFill()
            NSBezierPath(rect: rect).fill()
        case .highlight:
            color.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: rect).fill()
        }
    }

    private static func drawText(_ text: String, in rect: NSRect, color: NSColor, fontSize: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(in: rect)
    }

    /// Render full image + all annotations into a new NSImage at original resolution.
    static func renderFlattenedImage(image: NSImage, annotations: [Annotation]) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        for annotation in annotations {
            draw(annotation, scale: 1.0)
        }
        result.unlockFocus()
        return result
    }
}
