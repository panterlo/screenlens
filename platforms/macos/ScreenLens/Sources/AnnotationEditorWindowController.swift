import AppKit

/// Window controller for the non-destructive annotation editor.
/// Opens on double-click from gallery. Auto-saves annotations as JSON to the DB.
class AnnotationEditorWindowController: NSWindowController {

    private var toolbar: AnnotationToolbar!
    private var canvas: AnnotationCanvasView!
    private let screenshot: Screenshot
    private let image: NSImage
    private let database: ScreenLensDatabase

    init(screenshot: Screenshot, image: NSImage, database: ScreenLensDatabase) {
        self.screenshot = screenshot
        self.image = image
        self.database = database

        // Size window to image, capped at 80% of screen
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let maxW = screen.width * 0.8
        let maxH = screen.height * 0.8
        let scale = min(maxW / image.size.width, maxH / image.size.height, 1.0)
        let winW = max(image.size.width * scale, 600)
        let winH = max(image.size.height * scale + 44, 400) // +44 for toolbar

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate — \(screenshot.filename)"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
        loadAnnotations()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        toolbar = AnnotationToolbar()
        toolbar.onToolChanged = { [weak self] tool in
            self?.canvas.currentTool = tool
        }
        toolbar.onColorChanged = { [weak self] color in
            self?.canvas.currentColor = color
            self?.canvas.updateSelectedColor(color)
        }
        toolbar.onLineWidthChanged = { [weak self] width in
            self?.canvas.currentLineWidth = width
            self?.canvas.updateSelectedLineWidth(width)
        }
        toolbar.onFontSizeChanged = { [weak self] size in
            self?.canvas.currentFontSize = size
            self?.canvas.updateSelectedFontSize(size)
        }
        toolbar.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        contentView.addSubview(toolbar)

        canvas = AnnotationCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.setImage(image)
        canvas.onAnnotationsChanged = { [weak self] annotations in
            self?.saveAnnotations(annotations)
        }
        canvas.onSelectionChanged = { [weak self] annotation in
            if let fontSize = annotation?.style.fontSize {
                self?.toolbar.setDisplayedFontSize(fontSize)
            }
        }
        contentView.addSubview(canvas)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window?.makeFirstResponder(canvas)
    }

    private func loadAnnotations() {
        canvas.annotations = screenshot.annotationList
    }

    private func saveAnnotations(_ annotations: [Annotation]) {
        do {
            try database.updateAnnotations(id: screenshot.id, annotations: annotations)
        } catch {
            NSLog("Failed to save annotations: \(error)")
        }
    }

    private func handleAction(_ action: AnnotationAction) {
        switch action {
        case .undo:
            canvas.undo()
        case .redo:
            canvas.redo()
        case .delete:
            canvas.deleteSelected()
        case .copyAnnotated:
            copyAnnotated()
        case .exportPNG:
            exportPNG()
        }
    }

    private func copyAnnotated() {
        guard let flattened = canvas.renderFlattenedImage(),
              let tiff = flattened.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        pb.setData(tiff, forType: .tiff)
    }

    private func exportPNG() {
        guard let flattened = canvas.renderFlattenedImage(),
              let tiff = flattened.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = screenshot.filename.replacingOccurrences(of: ".png", with: "_annotated.png")
        panel.beginSheetModal(for: window!) { response in
            if response == .OK, let url = panel.url {
                try? png.write(to: url)
            }
        }
    }
}
