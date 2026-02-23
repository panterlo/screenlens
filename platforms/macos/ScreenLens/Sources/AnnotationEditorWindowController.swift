import AppKit

/// Window controller for the non-destructive annotation editor.
/// Opens on double-click from gallery. Auto-saves annotations as JSON to the DB.
class AnnotationEditorWindowController: NSWindowController {

    private var canvas: AnnotationCanvasView!
    private let screenshot: Screenshot
    private let image: NSImage
    private let database: ScreenLensDatabase

    private var colorButton: NSButton!
    private var currentColor: NSColor = .systemRed
    private var widthSlider: NSSlider!
    private var widthLabel: NSTextField!
    private var fontSizeStepper: NSStepper!
    private var fontSizeLabel: NSTextField!
    private var toolGroup: NSToolbarItemGroup!

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
        let winH = max(image.size.height * scale, 400)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate — \(screenshot.filename)"
        window.center()
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified

        super.init(window: window)
        setupToolbar()
        setupUI()
        loadAnnotations()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NSToolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "AnnotationToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        canvas = AnnotationCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.setImage(image)
        canvas.onAnnotationsChanged = { [weak self] annotations in
            self?.saveAnnotations(annotations)
        }
        canvas.onSelectionChanged = { [weak self] annotation in
            if let fontSize = annotation?.style.fontSize {
                self?.fontSizeStepper.integerValue = Int(fontSize)
                self?.fontSizeLabel.stringValue = "\(Int(fontSize))pt"
            }
        }
        contentView.addSubview(canvas)

        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: contentView.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window?.makeFirstResponder(canvas)
    }

    private func loadAnnotations() {
        checkImageDimensions()
        canvas.annotations = screenshot.annotationList
    }

    private func checkImageDimensions() {
        guard let storedW = screenshot.width, let storedH = screenshot.height else { return }
        // Use pixel dimensions from the bitmap rep, not NSImage.size (which is in points)
        guard let rep = image.representations.first else { return }
        let actualW = rep.pixelsWide
        let actualH = rep.pixelsHigh
        if actualW != storedW || actualH != storedH {
            let alert = NSAlert()
            alert.messageText = "Image Modified Externally"
            alert.informativeText = "The image dimensions have changed since capture (\(storedW)x\(storedH) \u{2192} \(actualW)x\(actualH)). Existing annotations may not align correctly."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func saveAnnotations(_ annotations: [Annotation]) {
        do {
            try database.updateAnnotations(id: screenshot.id, annotations: annotations)
        } catch {
            NSLog("Failed to save annotations: \(error)")
        }
    }

    // MARK: - Tool actions

    @objc private func toolSelected(_ sender: NSToolbarItemGroup) {
        let tools: [AnnotationTool] = [.select, .arrow, .rectangle, .highlight, .text]
        let idx = sender.selectedIndex
        guard idx >= 0, idx < tools.count else { return }
        canvas.currentTool = tools[idx]
    }

    @objc private func showColorPanel(_ sender: Any?) {
        let panel = NSColorPanel.shared
        panel.color = currentColor
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        currentColor = sender.color
        colorButton.image = makeColorSwatchImage(color: sender.color, size: NSSize(width: 16, height: 16))
        canvas.currentColor = sender.color
        canvas.updateSelectedColor(sender.color)
    }

    private func makeColorSwatchImage(color: NSColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 3, yRadius: 3)
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        image.unlockFocus()
        return image
    }

    @objc private func widthSliderChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.integerValue)
        widthLabel.stringValue = "\(sender.integerValue)"
        canvas.currentLineWidth = value
        canvas.updateSelectedLineWidth(value)
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        let value = CGFloat(sender.integerValue)
        fontSizeLabel.stringValue = "\(sender.integerValue)pt"
        canvas.currentFontSize = value
        canvas.updateSelectedFontSize(value)
    }

    @objc private func undoAction(_ sender: Any?) { canvas.undo() }
    @objc private func redoAction(_ sender: Any?) { canvas.redo() }
    @objc private func deleteAction(_ sender: Any?) { canvas.deleteSelected() }

    @objc private func copyAnnotated(_ sender: Any?) {
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

    @objc private func exportPNG(_ sender: Any?) {
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

// MARK: - NSToolbarDelegate

private extension NSToolbarItem.Identifier {
    static let annotationTools = NSToolbarItem.Identifier("annotationTools")
    static let annotationColor = NSToolbarItem.Identifier("annotationColor")
    static let annotationLineWidth = NSToolbarItem.Identifier("annotationLineWidth")
    static let annotationFontSize = NSToolbarItem.Identifier("annotationFontSize")
    static let annotationUndo = NSToolbarItem.Identifier("annotationUndo")
    static let annotationRedo = NSToolbarItem.Identifier("annotationRedo")
    static let annotationDelete = NSToolbarItem.Identifier("annotationDelete")
    static let annotationCopy = NSToolbarItem.Identifier("annotationCopy")
    static let annotationExport = NSToolbarItem.Identifier("annotationExport")
}

extension AnnotationEditorWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .annotationTools,
            .space,
            .annotationColor,
            .annotationLineWidth,
            .annotationFontSize,
            .space,
            .annotationUndo,
            .annotationRedo,
            .annotationDelete,
            .flexibleSpace,
            .annotationCopy,
            .annotationExport,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .annotationTools:
            let symbols = ["cursorarrow", "arrow.up.right", "rectangle", "highlighter", "textformat"]
            let labels = ["Select", "Arrow", "Rectangle", "Highlight", "Text"]

            let images = symbols.enumerated().map { (i, sym) in
                NSImage(systemSymbolName: sym, accessibilityDescription: labels[i])!
            }

            let group = NSToolbarItemGroup(itemIdentifier: itemIdentifier, images: images, selectionMode: .selectOne, labels: labels, target: self, action: #selector(toolSelected(_:)))
            group.selectedIndex = 0
            group.label = "Tools"
            toolGroup = group
            return group

        case .annotationColor:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            // Use a simple button that shows a color swatch and opens the shared color panel
            let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
            btn.bezelStyle = .toolbar
            btn.isBordered = true
            btn.image = makeColorSwatchImage(color: .systemRed, size: NSSize(width: 16, height: 16))
            btn.target = self
            btn.action = #selector(showColorPanel(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 36),
                btn.heightAnchor.constraint(equalToConstant: 24),
            ])
            colorButton = btn
            item.view = btn
            item.label = "Color"
            item.toolTip = "Annotation Color"
            return item

        case .annotationLineWidth:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let slider = NSSlider(value: 3, minValue: 1, maxValue: 10, target: self, action: #selector(widthSliderChanged(_:)))
            slider.isContinuous = true
            slider.numberOfTickMarks = 10
            slider.allowsTickMarkValuesOnly = true
            slider.controlSize = .small
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
            widthSlider = slider

            let label = NSTextField(labelWithString: "3")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 22).isActive = true
            widthLabel = label

            let wrapper = NSStackView(views: [slider, label])
            wrapper.orientation = .horizontal
            wrapper.spacing = 4
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.setContentCompressionResistancePriority(.required, for: .horizontal)
            wrapper.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
            item.view = wrapper
            item.label = "Width"
            item.toolTip = "Line Width"
            return item

        case .annotationFontSize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let stepper = NSStepper()
            stepper.minValue = 8
            stepper.maxValue = 72
            stepper.increment = 2
            stepper.integerValue = 16
            stepper.controlSize = .small
            stepper.target = self
            stepper.action = #selector(fontSizeStepperChanged(_:))
            stepper.translatesAutoresizingMaskIntoConstraints = false
            fontSizeStepper = stepper

            let label = NSTextField(labelWithString: "16pt")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 34).isActive = true
            fontSizeLabel = label

            let wrapper = NSStackView(views: [stepper, label])
            wrapper.orientation = .horizontal
            wrapper.spacing = 4
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.setContentCompressionResistancePriority(.required, for: .horizontal)
            item.view = wrapper
            item.label = "Font"
            item.toolTip = "Font Size"
            return item

        case .annotationUndo:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
            item.label = "Undo"
            item.target = self
            item.action = #selector(undoAction(_:))
            return item

        case .annotationRedo:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")
            item.label = "Redo"
            item.target = self
            item.action = #selector(redoAction(_:))
            return item

        case .annotationDelete:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
            item.label = "Delete"
            item.target = self
            item.action = #selector(deleteAction(_:))
            return item

        case .annotationCopy:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Copy Annotated")
            item.label = "Copy Annotated"
            item.target = self
            item.action = #selector(copyAnnotated(_:))
            return item

        case .annotationExport:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export PNG")
            item.label = "Export PNG"
            item.target = self
            item.action = #selector(exportPNG(_:))
            return item

        default:
            return nil
        }
    }
}
