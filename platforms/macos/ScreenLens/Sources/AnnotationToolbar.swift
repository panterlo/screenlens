import AppKit

enum AnnotationAction {
    case undo, redo, delete, copyAnnotated, exportPNG
}

class AnnotationToolbar: NSView {

    var onToolChanged: ((AnnotationTool) -> Void)?
    var onColorChanged: ((NSColor) -> Void)?
    var onLineWidthChanged: ((CGFloat) -> Void)?
    var onFontSizeChanged: ((CGFloat) -> Void)?
    var onAction: ((AnnotationAction) -> Void)?

    private var toolButtons: [NSButton] = []
    private var selectedTool: AnnotationTool = .select
    private var widthLabel: NSTextField!
    private var fontSizeLabel: NSTextField!
    private var fontSizeStepper: NSStepper!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let tools: [(AnnotationTool, String, String)] = [
            (.select, "cursorarrow", "Select"),
            (.arrow, "arrow.up.right", "Arrow"),
            (.rectangle, "rectangle", "Rectangle"),
            (.highlight, "highlighter", "Highlight"),
            (.text, "textformat", "Text"),
        ]

        for (tool, symbol, tip) in tools {
            let btn = makeButton(symbol: symbol, tooltip: tip)
            btn.tag = tools.firstIndex(where: { $0.0 == tool })!
            btn.target = self
            btn.action = #selector(toolClicked(_:))
            toolButtons.append(btn)
        }
        // Highlight first tool
        toolButtons[0].state = .on

        let colorWell = NSColorWell()
        colorWell.color = .systemRed
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 28),
            colorWell.heightAnchor.constraint(equalToConstant: 28),
        ])

        let widthSlider = NSSlider(value: 3, minValue: 1, maxValue: 10, target: self, action: #selector(widthSliderChanged(_:)))
        widthSlider.isContinuous = true
        widthSlider.numberOfTickMarks = 10
        widthSlider.allowsTickMarkValuesOnly = true
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthSlider.widthAnchor.constraint(equalToConstant: 80),
        ])

        widthLabel = NSTextField(labelWithString: "3")
        widthLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        widthLabel.translatesAutoresizingMaskIntoConstraints = false

        fontSizeStepper = NSStepper()
        fontSizeStepper.minValue = 8
        fontSizeStepper.maxValue = 72
        fontSizeStepper.increment = 2
        fontSizeStepper.integerValue = 16
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeStepperChanged(_:))
        fontSizeStepper.translatesAutoresizingMaskIntoConstraints = false

        fontSizeLabel = NSTextField(labelWithString: "16pt")
        fontSizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        fontSizeLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator1 = makeSeparator()

        let undoBtn = makeButton(symbol: "arrow.uturn.backward", tooltip: "Undo")
        undoBtn.target = self
        undoBtn.action = #selector(undoClicked)

        let redoBtn = makeButton(symbol: "arrow.uturn.forward", tooltip: "Redo")
        redoBtn.target = self
        redoBtn.action = #selector(redoClicked)

        let deleteBtn = makeButton(symbol: "trash", tooltip: "Delete")
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteClicked)

        let separator2 = makeSeparator()

        let copyBtn = NSButton(title: "Copy Annotated", target: self, action: #selector(copyClicked))
        copyBtn.bezelStyle = .toolbar
        copyBtn.translatesAutoresizingMaskIntoConstraints = false

        let exportBtn = NSButton(title: "Export PNG", target: self, action: #selector(exportClicked))
        exportBtn.bezelStyle = .toolbar
        exportBtn.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = toolButtons
        views.append(contentsOf: [colorWell, widthSlider, widthLabel, fontSizeStepper, fontSizeLabel, separator1, undoBtn, redoBtn, deleteBtn, separator2, copyBtn, exportBtn])

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func makeButton(symbol: String, tooltip: String) -> NSButton {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.bezelStyle = .toolbar
        btn.isBordered = true
        btn.setButtonType(.toggle)
        btn.toolTip = tooltip
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 32),
            btn.heightAnchor.constraint(equalToConstant: 28),
        ])
        return btn
    }

    private func makeSeparator() -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([sep.widthAnchor.constraint(equalToConstant: 1)])
        return sep
    }

    @objc private func toolClicked(_ sender: NSButton) {
        let tools: [AnnotationTool] = [.select, .arrow, .rectangle, .highlight, .text]
        guard sender.tag < tools.count else { return }
        selectedTool = tools[sender.tag]
        for (i, btn) in toolButtons.enumerated() {
            btn.state = (i == sender.tag) ? .on : .off
        }
        onToolChanged?(selectedTool)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        onColorChanged?(sender.color)
    }

    @objc private func widthSliderChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.integerValue)
        widthLabel.stringValue = "\(sender.integerValue)"
        onLineWidthChanged?(value)
    }

    @objc private func fontSizeStepperChanged(_ sender: NSStepper) {
        let value = CGFloat(sender.integerValue)
        fontSizeLabel.stringValue = "\(sender.integerValue)pt"
        onFontSizeChanged?(value)
    }

    func setDisplayedFontSize(_ size: CGFloat) {
        fontSizeStepper.integerValue = Int(size)
        fontSizeLabel.stringValue = "\(Int(size))pt"
    }

    @objc private func undoClicked() { onAction?(.undo) }
    @objc private func redoClicked() { onAction?(.redo) }
    @objc private func deleteClicked() { onAction?(.delete) }
    @objc private func copyClicked() { onAction?(.copyAnnotated) }
    @objc private func exportClicked() { onAction?(.exportPNG) }
}
