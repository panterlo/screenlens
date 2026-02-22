import AppKit

class ScreenshotDetailView: NSView {
    private let imagePreview = NSImageView()
    private let dateLabel = NSTextField(labelWithString: "")
    private let modeLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private let urlButton = NSButton(title: "", target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "")
    private let dimensionsLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let extractedTextScroll = NSScrollView()
    private let extractedTextView = NSTextView()
    private let tagsLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "Open in Preview", target: nil, action: nil)
    private let annotateButton = NSButton(title: "Annotate", target: nil, action: nil)

    var onAnnotate: ((Screenshot) -> Void)?
    private var currentScreenshot: Screenshot?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        imagePreview.imageScaling = .scaleProportionallyUpOrDown
        imagePreview.translatesAutoresizingMaskIntoConstraints = false

        let metaStack = NSStackView()
        metaStack.orientation = .vertical
        metaStack.alignment = .leading
        metaStack.spacing = 4
        metaStack.translatesAutoresizingMaskIntoConstraints = false

        for label in [dateLabel, modeLabel, appLabel, sizeLabel, dimensionsLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }

        urlButton.isBordered = false
        urlButton.font = .systemFont(ofSize: 11)
        urlButton.contentTintColor = .linkColor
        urlButton.target = self
        urlButton.action = #selector(openURL)

        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.maximumNumberOfLines = 4

        tagsLabel.font = .systemFont(ofSize: 11)
        tagsLabel.textColor = .systemBlue

        extractedTextView.isEditable = false
        extractedTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        extractedTextView.textContainerInset = NSSize(width: 4, height: 4)
        extractedTextScroll.documentView = extractedTextView
        extractedTextScroll.hasVerticalScroller = true
        extractedTextScroll.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [openButton, annotateButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        openButton.target = self
        openButton.action = #selector(openInPreview)
        annotateButton.target = self
        annotateButton.action = #selector(annotateClicked)

        metaStack.addArrangedSubview(imagePreview)
        metaStack.addArrangedSubview(summaryLabel)
        metaStack.addArrangedSubview(tagsLabel)
        metaStack.addArrangedSubview(makeSeparator())
        metaStack.addArrangedSubview(dateLabel)
        metaStack.addArrangedSubview(modeLabel)
        metaStack.addArrangedSubview(appLabel)
        metaStack.addArrangedSubview(urlButton)
        metaStack.addArrangedSubview(sizeLabel)
        metaStack.addArrangedSubview(dimensionsLabel)
        metaStack.addArrangedSubview(makeSeparator())
        metaStack.addArrangedSubview(extractedTextScroll)
        metaStack.addArrangedSubview(buttonStack)

        let scrollView = NSScrollView()
        scrollView.documentView = metaStack
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            imagePreview.heightAnchor.constraint(equalToConstant: 200),
            imagePreview.widthAnchor.constraint(equalTo: metaStack.widthAnchor),
            extractedTextScroll.heightAnchor.constraint(equalToConstant: 100),
            extractedTextScroll.widthAnchor.constraint(equalTo: metaStack.widthAnchor),
        ])
    }

    private func makeSeparator() -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        return sep
    }

    func configure(with screenshot: Screenshot) {
        currentScreenshot = screenshot
        imagePreview.image = NSImage(contentsOfFile: screenshot.filepath)

        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        if let date = ISO8601DateFormatter().date(from: screenshot.capturedAt) {
            dateLabel.stringValue = "Date: \(fmt.string(from: date))"
        } else {
            dateLabel.stringValue = "Date: \(screenshot.capturedAt)"
        }

        modeLabel.stringValue = "Mode: \(screenshot.mode.displayName)"
        appLabel.stringValue = "App: \(screenshot.application ?? "Unknown")"

        if let url = screenshot.sourceUrl, !url.isEmpty {
            urlButton.title = url
            urlButton.isHidden = false
        } else {
            urlButton.isHidden = true
        }

        let sizeKB = screenshot.sizeBytes / 1024
        sizeLabel.stringValue = "Size: \(sizeKB) KB"

        if let w = screenshot.width, let h = screenshot.height {
            dimensionsLabel.stringValue = "Dimensions: \(w) × \(h)"
        } else {
            dimensionsLabel.stringValue = "Dimensions: —"
        }

        summaryLabel.stringValue = screenshot.summary ?? "No analysis yet"
        tagsLabel.stringValue = screenshot.tagList.isEmpty ? "" : screenshot.tagList.joined(separator: ", ")
        extractedTextView.string = screenshot.extractedText ?? ""
    }

    func clear() {
        currentScreenshot = nil
        imagePreview.image = nil
        summaryLabel.stringValue = ""
        tagsLabel.stringValue = ""
        dateLabel.stringValue = ""
        modeLabel.stringValue = ""
        appLabel.stringValue = ""
        urlButton.isHidden = true
        sizeLabel.stringValue = ""
        dimensionsLabel.stringValue = ""
        extractedTextView.string = ""
    }

    @objc private func openURL() {
        if let url = currentScreenshot?.sourceUrl, let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func openInPreview() {
        if let path = currentScreenshot?.filepath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    @objc private func annotateClicked() {
        if let s = currentScreenshot { onAnnotate?(s) }
    }
}
