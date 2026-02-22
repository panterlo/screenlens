import AppKit

enum AnnotationTool: String {
    case select, arrow, rectangle, highlight, text
}

/// Canvas view that hosts the image and annotation overlay. Handles all mouse interaction.
class AnnotationCanvasView: NSView {

    let imageView = NSImageView()
    let overlayView = AnnotationOverlayView()

    var annotations: [Annotation] = [] { didSet { overlayView.annotations = annotations; overlayView.needsDisplay = true } }
    var selectedAnnotationId: String? { didSet { overlayView.selectedAnnotationId = selectedAnnotationId; overlayView.needsDisplay = true } }
    var currentTool: AnnotationTool = .select
    var currentColor: NSColor = .systemRed
    var onAnnotationsChanged: (([Annotation]) -> Void)?

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var dragStart: NSPoint = .zero
    private var isDragging = false
    private var dragOriginalPosition: NSPoint = .zero  // for move operations
    private var movingAnnotationIndex: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override var acceptsFirstResponder: Bool { true }

    func setImage(_ image: NSImage) {
        imageView.image = image
        overlayView.imageSize = image.size
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateImageRect()
    }

    private func updateImageRect() {
        guard let image = imageView.image else { return }
        let viewSize = bounds.size
        let imgSize = image.size
        guard viewSize.width > 0 && viewSize.height > 0 && imgSize.width > 0 && imgSize.height > 0 else { return }

        let scaleX = viewSize.width / imgSize.width
        let scaleY = viewSize.height / imgSize.height
        let scale = min(scaleX, scaleY)

        let w = imgSize.width * scale
        let h = imgSize.height * scale
        let x = (viewSize.width - w) / 2
        let y = (viewSize.height - h) / 2

        overlayView.imageRect = NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Coordinate conversion

    private func viewToImage(_ point: NSPoint) -> NSPoint {
        let ir = overlayView.imageRect
        guard ir.width > 0 else { return point }
        let scale = overlayView.imageSize.width / ir.width
        return NSPoint(x: (point.x - ir.origin.x) * scale,
                       y: (point.y - ir.origin.y) * scale)
    }

    // MARK: - Undo / Redo

    private func pushUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
        selectedAnnotationId = nil
        onAnnotationsChanged?(annotations)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedAnnotationId = nil
        onAnnotationsChanged?(annotations)
    }

    func deleteSelected() {
        guard let id = selectedAnnotationId else { return }
        pushUndo()
        annotations.removeAll { $0.id == id }
        selectedAnnotationId = nil
        onAnnotationsChanged?(annotations)
    }

    // MARK: - Hit testing

    private func hitTestAnnotation(at viewPoint: NSPoint) -> Int? {
        let imgPoint = viewToImage(viewPoint)
        let tolerance: CGFloat = 10

        // Iterate in reverse (top-most first)
        for i in annotations.indices.reversed() {
            let a = annotations[i]
            switch a.type {
            case .arrow:
                if let line = a.geometry.line {
                    let dist = distanceFromPointToLine(imgPoint, lineStart: line.start, lineEnd: line.end)
                    if dist < tolerance { return i }
                }
            case .rectangle, .text:
                if let r = a.geometry.rect {
                    let expanded = r.insetBy(dx: -tolerance, dy: -tolerance)
                    if expanded.contains(imgPoint) { return i }
                }
            }
        }
        return nil
    }

    private func distanceFromPointToLine(_ p: NSPoint, lineStart: NSPoint, lineEnd: NSPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(p.x - lineStart.x, p.y - lineStart.y) }
        let t = max(0, min(1, ((p.x - lineStart.x) * dx + (p.y - lineStart.y) * dy) / lengthSq))
        let projX = lineStart.x + t * dx
        let projY = lineStart.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imgPoint = viewToImage(viewPoint)
        dragStart = imgPoint
        isDragging = true
        movingAnnotationIndex = nil

        if currentTool == .select {
            if let idx = hitTestAnnotation(at: viewPoint) {
                selectedAnnotationId = annotations[idx].id
                movingAnnotationIndex = idx
                dragOriginalPosition = imgPoint
            } else {
                selectedAnnotationId = nil
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imgPoint = viewToImage(viewPoint)

        if currentTool == .select {
            // Move selected annotation
            if let idx = movingAnnotationIndex {
                let dx = imgPoint.x - dragOriginalPosition.x
                let dy = imgPoint.y - dragOriginalPosition.y
                if dx != 0 || dy != 0 {
                    if undoStack.last != annotations { pushUndo() }
                    moveAnnotation(at: idx, dx: dx, dy: dy)
                    dragOriginalPosition = imgPoint
                    onAnnotationsChanged?(annotations)
                }
            }
            return
        }

        // Preview creation
        let preview = makeAnnotation(from: dragStart, to: imgPoint)
        overlayView.creationPreview = preview
        overlayView.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        overlayView.creationPreview = nil

        let viewPoint = convert(event.locationInWindow, from: nil)
        let imgPoint = viewToImage(viewPoint)

        if currentTool == .select {
            movingAnnotationIndex = nil
            return
        }

        // Minimum drag distance check
        let dist = hypot(imgPoint.x - dragStart.x, imgPoint.y - dragStart.y)
        guard dist > 3 else { return }

        if currentTool == .text {
            promptForText { [weak self] text in
                guard let self = self, let text = text, !text.isEmpty else { return }
                self.pushUndo()
                var annotation = self.makeAnnotation(from: self.dragStart, to: imgPoint)
                annotation.text = text
                self.annotations.append(annotation)
                self.selectedAnnotationId = annotation.id
                self.onAnnotationsChanged?(self.annotations)
            }
        } else {
            pushUndo()
            let annotation = makeAnnotation(from: dragStart, to: imgPoint)
            annotations.append(annotation)
            selectedAnnotationId = annotation.id
            onAnnotationsChanged?(annotations)
        }

        overlayView.needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.charactersIgnoringModifiers == "\u{7F}" { // Delete/Backspace
            deleteSelected()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { redo() } else { undo() }
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Annotation creation

    private func makeAnnotation(from start: NSPoint, to end: NSPoint) -> Annotation {
        let style = AnnotationStyle(
            color: currentColor.hexString,
            lineWidth: currentTool == .highlight ? 0 : 3,
            opacity: currentTool == .highlight ? 0.3 : 1.0,
            fill: currentTool == .highlight ? .highlight : (currentTool == .rectangle ? .outline : nil),
            fontSize: currentTool == .text ? 16 : nil
        )

        let geometry: AnnotationGeometry
        let type: AnnotationType

        switch currentTool {
        case .arrow:
            type = .arrow
            geometry = AnnotationGeometry(startX: start.x, startY: start.y, endX: end.x, endY: end.y)
        case .rectangle, .highlight:
            type = .rectangle
            let r = normalizedRect(from: start, to: end)
            geometry = AnnotationGeometry(x: r.origin.x, y: r.origin.y, width: r.width, height: r.height)
        case .text:
            type = .text
            let r = normalizedRect(from: start, to: end)
            geometry = AnnotationGeometry(x: r.origin.x, y: r.origin.y, width: r.width, height: max(r.height, 30))
        case .select:
            type = .arrow // shouldn't happen
            geometry = AnnotationGeometry()
        }

        return Annotation(type: type, geometry: geometry, style: style)
    }

    private func normalizedRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        let w = abs(b.x - a.x)
        let h = abs(b.y - a.y)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func moveAnnotation(at index: Int, dx: CGFloat, dy: CGFloat) {
        var a = annotations[index]
        switch a.type {
        case .arrow:
            a.geometry.startX = (a.geometry.startX ?? 0) + dx
            a.geometry.startY = (a.geometry.startY ?? 0) + dy
            a.geometry.endX = (a.geometry.endX ?? 0) + dx
            a.geometry.endY = (a.geometry.endY ?? 0) + dy
        case .rectangle, .text:
            a.geometry.x = (a.geometry.x ?? 0) + dx
            a.geometry.y = (a.geometry.y ?? 0) + dy
        }
        annotations[index] = a
    }

    // MARK: - Text input

    private func promptForText(completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Enter annotation text"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        field.placeholderString = "Type here..."
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        completion(response == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    // MARK: - Export

    func renderFlattenedImage() -> NSImage? {
        guard let image = imageView.image else { return nil }
        return AnnotationRenderer.renderFlattenedImage(image: image, annotations: annotations)
    }
}
