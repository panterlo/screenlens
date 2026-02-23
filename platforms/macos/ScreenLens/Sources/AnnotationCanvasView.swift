import AppKit

enum AnnotationTool: String {
    case select, arrow, rectangle, highlight, text
}

private enum DragMode {
    case none, move, resize
}

/// Canvas view that hosts the image and annotation overlay. Handles all mouse interaction.
class AnnotationCanvasView: NSView, NSTextFieldDelegate {

    let imageView = NSImageView()
    let overlayView = AnnotationOverlayView()

    var annotations: [Annotation] = [] { didSet { overlayView.annotations = annotations; overlayView.needsDisplay = true } }
    var selectedAnnotationId: String? {
        didSet {
            overlayView.selectedAnnotationId = selectedAnnotationId
            overlayView.needsDisplay = true
            let selected = annotations.first(where: { $0.id == selectedAnnotationId })
            onSelectionChanged?(selected)
        }
    }
    var currentTool: AnnotationTool = .select
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3
    var currentFontSize: CGFloat = 16
    var onAnnotationsChanged: (([Annotation]) -> Void)?
    var onSelectionChanged: ((Annotation?) -> Void)?

    // Inline text editing state
    private var inlineTextField: NSTextField?
    private var editingAnnotationIndex: Int?   // nil = creating new, set = editing existing
    private var pendingTextGeometry: AnnotationGeometry?  // stores geometry during new text creation

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var dragStart: NSPoint = .zero
    private var isDragging = false
    private var dragOriginalPosition: NSPoint = .zero  // for move operations
    private var movingAnnotationIndex: Int?

    // Resize state
    private var dragMode: DragMode = .none
    private var resizingHandleIndex: Int = -1
    private var resizeAnchor: NSPoint = .zero  // fixed opposite corner/endpoint

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

        // Tracking area for cursor feedback
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ aPoint: NSPoint) -> NSView? {
        // Let clicks reach the inline text field when it's active
        if let tf = inlineTextField {
            let tfPoint = tf.convert(aPoint, from: superview)
            if tf.bounds.contains(tfPoint) {
                return tf.hitTest(aPoint)
            }
        }
        // Ensure all mouse events go to this canvas, not to imageView or overlayView
        let local = convert(aPoint, from: superview)
        return bounds.contains(local) ? self : nil
    }

    func setImage(_ image: NSImage) {
        imageView.image = image
        overlayView.imageSize = image.size
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateImageRect()
        repositionInlineTextField()
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

    // MARK: - Handle hit-testing

    /// Returns the handle index if viewPoint is within tolerance of a selection handle, nil otherwise.
    /// Uses image coordinates with a tolerance larger than hitTestAnnotation (10px) so handles win.
    private func hitTestHandle(at viewPoint: NSPoint) -> Int? {
        guard let selId = selectedAnnotationId,
              let annotation = annotations.first(where: { $0.id == selId }) else { return nil }

        let imgPoint = viewToImage(viewPoint)
        let tolerance: CGFloat = 14  // > annotation body tolerance (10) so handles take priority

        switch annotation.type {
        case .arrow:
            if let line = annotation.geometry.line {
                let points = [line.start, line.end]
                for (i, p) in points.enumerated() {
                    if hypot(imgPoint.x - p.x, imgPoint.y - p.y) <= tolerance {
                        return i
                    }
                }
            }
        case .rectangle, .text:
            if let r = annotation.geometry.rect {
                let corners = [
                    NSPoint(x: r.minX, y: r.minY),
                    NSPoint(x: r.maxX, y: r.minY),
                    NSPoint(x: r.maxX, y: r.maxY),
                    NSPoint(x: r.minX, y: r.maxY),
                ]
                for (i, c) in corners.enumerated() {
                    if hypot(imgPoint.x - c.x, imgPoint.y - c.y) <= tolerance {
                        return i
                    }
                }
            }
        }
        return nil
    }

    /// Returns the anchor point (in image coordinates) for resizing — the opposite corner/endpoint.
    private func anchorForHandle(index: Int, annotation: Annotation) -> NSPoint {
        switch annotation.type {
        case .arrow:
            if let line = annotation.geometry.line {
                // index 0 = start → anchor is end; index 1 = end → anchor is start
                return index == 0 ? line.end : line.start
            }
        case .rectangle, .text:
            if let r = annotation.geometry.rect {
                let corners = [
                    NSPoint(x: r.minX, y: r.minY),  // 0
                    NSPoint(x: r.maxX, y: r.minY),  // 1
                    NSPoint(x: r.maxX, y: r.maxY),  // 2
                    NSPoint(x: r.minX, y: r.maxY),  // 3
                ]
                // Opposite corner: 0↔2, 1↔3
                let oppositeIndex = (index + 2) % 4
                return corners[oppositeIndex]
            }
        }
        return .zero
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        // Commit any active inline edit when clicking outside the text field
        if inlineTextField != nil {
            commitInlineEdit()
            return
        }

        if event.clickCount == 2 && currentTool == .select {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let idx = hitTestAnnotation(at: viewPoint),
               annotations[idx].type == .text {
                editTextAnnotation(at: idx)
                return
            }
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let imgPoint = viewToImage(viewPoint)
        dragStart = imgPoint
        isDragging = true
        movingAnnotationIndex = nil
        dragMode = .none

        if currentTool == .select {
            // 1. Check if clicking a resize handle on the selected annotation
            if let handleIdx = hitTestHandle(at: viewPoint),
               let selId = selectedAnnotationId,
               let annotation = annotations.first(where: { $0.id == selId }) {
                dragMode = .resize
                resizingHandleIndex = handleIdx
                resizeAnchor = anchorForHandle(index: handleIdx, annotation: annotation)
                NSCursor.closedHand.set()
                return
            }

            // 2. Check if clicking an annotation body → move mode
            if let idx = hitTestAnnotation(at: viewPoint) {
                selectedAnnotationId = annotations[idx].id
                movingAnnotationIndex = idx
                dragOriginalPosition = imgPoint
                dragMode = .move
                NSCursor.closedHand.set()
            } else {
                // 3. Click on empty space → deselect
                selectedAnnotationId = nil
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imgPoint = viewToImage(viewPoint)

        if currentTool == .select {
            if dragMode == .resize {
                // Resize selected annotation
                if let selId = selectedAnnotationId,
                   let idx = annotations.firstIndex(where: { $0.id == selId }) {
                    if undoStack.last != annotations { pushUndo() }
                    resizeAnnotation(at: idx, handleIndex: resizingHandleIndex, to: imgPoint)
                    onAnnotationsChanged?(annotations)
                }
            } else if dragMode == .move, let idx = movingAnnotationIndex {
                // Move selected annotation
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
            dragMode = .none
            movingAnnotationIndex = nil
            resizingHandleIndex = -1
            updateCursor(at: viewPoint)
            return
        }

        // Minimum drag distance check
        let dist = hypot(imgPoint.x - dragStart.x, imgPoint.y - dragStart.y)
        guard dist > 3 else { return }

        if currentTool == .text {
            let annotation = makeAnnotation(from: dragStart, to: imgPoint)
            pendingTextGeometry = annotation.geometry
            beginInlineEdit(geometry: annotation.geometry, existingText: "", annotationIndex: nil)
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
        if event.keyCode == 53 { // Escape
            selectedAnnotationId = nil
        } else if event.keyCode == 51 || event.charactersIgnoringModifiers == "\u{7F}" { // Delete/Backspace
            deleteSelected()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { redo() } else { undo() }
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Annotation creation

    func updateSelectedColor(_ color: NSColor) {
        guard let selId = selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == selId }) else { return }
        pushUndo()
        annotations[idx].style.color = color.hexString
        overlayView.needsDisplay = true
        onAnnotationsChanged?(annotations)
    }

    func updateSelectedLineWidth(_ width: CGFloat) {
        guard let selId = selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == selId }) else { return }
        guard annotations[idx].type != .rectangle || annotations[idx].style.fill != .highlight else { return }
        pushUndo()
        annotations[idx].style.lineWidth = width
        overlayView.needsDisplay = true
        onAnnotationsChanged?(annotations)
    }

    func updateSelectedFontSize(_ size: CGFloat) {
        guard let selId = selectedAnnotationId,
              let idx = annotations.firstIndex(where: { $0.id == selId }),
              annotations[idx].type == .text else { return }
        pushUndo()
        annotations[idx].style.fontSize = size
        overlayView.needsDisplay = true
        onAnnotationsChanged?(annotations)
    }

    private func makeAnnotation(from start: NSPoint, to end: NSPoint) -> Annotation {
        let style = AnnotationStyle(
            color: currentColor.hexString,
            lineWidth: currentTool == .highlight ? 0 : currentLineWidth,
            opacity: currentTool == .highlight ? 0.3 : 1.0,
            fill: currentTool == .highlight ? .highlight : (currentTool == .rectangle ? .outline : nil),
            fontSize: currentTool == .text ? currentFontSize : nil
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

    private func resizeAnnotation(at index: Int, handleIndex: Int, to point: NSPoint) {
        var a = annotations[index]
        switch a.type {
        case .arrow:
            if handleIndex == 0 {
                a.geometry.startX = point.x
                a.geometry.startY = point.y
            } else {
                a.geometry.endX = point.x
                a.geometry.endY = point.y
            }
        case .rectangle, .text:
            let newRect = normalizedRect(from: resizeAnchor, to: point)
            a.geometry.x = newRect.origin.x
            a.geometry.y = newRect.origin.y
            a.geometry.width = newRect.width
            a.geometry.height = a.type == .text ? max(newRect.height, 30) : newRect.height
        }
        annotations[index] = a
    }

    // MARK: - Cursor feedback

    override func mouseMoved(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        updateCursor(at: viewPoint)
    }

    private func updateCursor(at viewPoint: NSPoint) {
        guard currentTool == .select else {
            NSCursor.crosshair.set()
            return
        }

        if hitTestHandle(at: viewPoint) != nil {
            NSCursor.crosshair.set()
        } else if selectedAnnotationId != nil, hitTestAnnotation(at: viewPoint) != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Inline text editing

    private func beginInlineEdit(geometry: AnnotationGeometry, existingText: String, annotationIndex: Int?) {
        // Cancel any existing edit first
        if inlineTextField != nil { cancelInlineEdit() }

        guard let imageRect = geometry.rect else { return }
        let viewRect = overlayView.imageRectToView(imageRect)

        editingAnnotationIndex = annotationIndex

        // Hide the annotation being edited so text doesn't render twice
        if let idx = annotationIndex {
            overlayView.hiddenAnnotationId = annotations[idx].id
            overlayView.needsDisplay = true
        }

        let s = overlayView.imageRect.width > 0 ? overlayView.imageRect.width / overlayView.imageSize.width : 1
        let baseFontSize: CGFloat
        if let idx = annotationIndex {
            baseFontSize = annotations[idx].style.fontSize ?? currentFontSize
        } else {
            baseFontSize = currentFontSize
        }
        let font = NSFont.systemFont(ofSize: baseFontSize * s, weight: .bold)

        let tf = NSTextField()
        tf.stringValue = existingText
        tf.font = font
        tf.textColor = currentColor
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = true
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.15)
        tf.focusRingType = .none
        tf.isEditable = true
        tf.isSelectable = true
        tf.placeholderString = "Type text..."
        tf.delegate = self
        tf.frame = viewRect

        // If editing an existing annotation, use its color
        if let idx = annotationIndex {
            tf.textColor = NSColor(hexString: annotations[idx].style.color)
        }

        addSubview(tf)
        window?.makeFirstResponder(tf)
        inlineTextField = tf
    }

    private func commitInlineEdit() {
        guard let tf = inlineTextField else { return }
        let text = tf.stringValue

        if let idx = editingAnnotationIndex {
            // Editing existing annotation
            if !text.isEmpty && text != (annotations[idx].text ?? "") {
                pushUndo()
                annotations[idx].text = text
                onAnnotationsChanged?(annotations)
            }
            overlayView.hiddenAnnotationId = nil
        } else if let geometry = pendingTextGeometry, !text.isEmpty {
            // Creating new annotation
            pushUndo()
            var annotation = Annotation(
                type: .text,
                geometry: geometry,
                style: AnnotationStyle(
                    color: currentColor.hexString,
                    lineWidth: 0,
                    opacity: 1.0,
                    fontSize: currentFontSize
                )
            )
            annotation.text = text
            annotations.append(annotation)
            selectedAnnotationId = annotation.id
            onAnnotationsChanged?(annotations)
        }

        cleanupInlineEdit()
    }

    private func cancelInlineEdit() {
        // Restore hidden annotation without changes
        if editingAnnotationIndex != nil {
            overlayView.hiddenAnnotationId = nil
        }
        cleanupInlineEdit()
    }

    private func cleanupInlineEdit() {
        inlineTextField?.removeFromSuperview()
        inlineTextField = nil
        editingAnnotationIndex = nil
        pendingTextGeometry = nil
        overlayView.needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func repositionInlineTextField() {
        guard let tf = inlineTextField else { return }

        let geometry: AnnotationGeometry?
        if let idx = editingAnnotationIndex {
            geometry = annotations[idx].geometry
        } else {
            geometry = pendingTextGeometry
        }
        guard let geom = geometry, let imageRect = geom.rect else { return }

        let viewRect = overlayView.imageRectToView(imageRect)
        tf.frame = viewRect

        // Update font size for new scale
        let s = overlayView.imageRect.width > 0 ? overlayView.imageRect.width / overlayView.imageSize.width : 1
        let baseFontSize: CGFloat
        if let idx = editingAnnotationIndex {
            baseFontSize = annotations[idx].style.fontSize ?? currentFontSize
        } else {
            baseFontSize = currentFontSize
        }
        tf.font = NSFont.systemFont(ofSize: baseFontSize * s, weight: .bold)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            commitInlineEdit()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            cancelInlineEdit()
            return true
        }
        return false
    }

    private func editTextAnnotation(at index: Int) {
        let current = annotations[index].text ?? ""
        beginInlineEdit(geometry: annotations[index].geometry, existingText: current, annotationIndex: index)
    }

    // MARK: - Export

    func renderFlattenedImage() -> NSImage? {
        guard let image = imageView.image else { return nil }
        return AnnotationRenderer.renderFlattenedImage(image: image, annotations: annotations)
    }
}
