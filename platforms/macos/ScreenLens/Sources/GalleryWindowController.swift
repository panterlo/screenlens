import AppKit

/// Native gallery window for browsing, searching, and filtering screenshots.
class GalleryWindowController: NSWindowController {

    private var modePopup: NSPopUpButton!
    private var datePopup: NSPopUpButton!
    private var browseSidebar: BrowseSidebarView!
    private var collectionView: NSCollectionView!
    private var detailView: ScreenshotDetailView!
    private var emptyLabel: NSTextField!
    private var splitView: NSSplitView!
    var database: ScreenLensDatabase?
    private var annotationEditorWC: AnnotationEditorWindowController?
    private var sidebarFilter = SidebarFilter()

    convenience init(database: ScreenLensDatabase?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenLens"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 400)
        window.toolbarStyle = .unified

        self.init(window: window)
        self.database = database
        setupToolbar()
        setupUI()
        loadRecent()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        loadRecent()
    }

    // MARK: - NSToolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "GalleryToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window?.toolbar = toolbar
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Split view: browse sidebar | grid | detail
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        // Left: browse sidebar
        browseSidebar = BrowseSidebarView()
        browseSidebar.onSelectionChanged = { [weak self] filter in
            self?.sidebarFilter = filter
            self?.performSearch()
        }

        // Center: collection view
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 240, height: 210)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            ScreenshotCell.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("ScreenshotCell")
        )

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true

        // Empty state
        emptyLabel = NSTextField(labelWithString: "No screenshots found")
        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        scrollView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        // Right: detail sidebar
        detailView = ScreenshotDetailView()
        detailView.onAnnotate = { [weak self] screenshot in
            self?.openAnnotationEditor(for: screenshot)
        }

        let detailContainer = NSVisualEffectView()
        detailContainer.material = .sidebar
        detailContainer.blendingMode = .behindWindow
        detailContainer.state = .active
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailView)
        NSLayoutConstraint.activate([
            detailView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailView.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
        ])

        splitView.addArrangedSubview(browseSidebar)
        splitView.addArrangedSubview(scrollView)
        splitView.addArrangedSubview(detailContainer)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)   // sidebar: fixed
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)    // grid: flexible
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 2)   // detail: fixed
        splitView.delegate = self
        contentView.addSubview(splitView)

        // Layout
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            detailContainer.widthAnchor.constraint(equalToConstant: 280),
        ])

        // Set initial divider positions after layout
        DispatchQueue.main.async { [weak self] in
            self?.splitView.setPosition(220, ofDividerAt: 0)
        }
    }

    // MARK: - Data

    private var screenshots: [Screenshot] = []

    private func loadRecent() {
        if !sidebarFilter.isEmpty {
            // Sidebar has an active filter — use searchFiltered even with empty text
            do {
                screenshots = try database?.searchFiltered(text: "", filters: GalleryFilters(), sidebarFilter: sidebarFilter) ?? []
            } catch {
                NSLog("Failed to load filtered screenshots: \(error)")
                screenshots = []
            }
        } else {
            do {
                screenshots = try database?.listRecent() ?? []
            } catch {
                NSLog("Failed to load recent screenshots: \(error)")
                screenshots = []
            }
        }
        reloadGrid()
        refreshSidebar()
    }

    @objc private func searchChanged(_ sender: Any?) {
        performSearch()
    }

    @objc private func filterChanged(_ sender: Any?) {
        performSearch()
    }

    private var currentFilters: GalleryFilters {
        let mode: CaptureMode?
        switch modePopup?.indexOfSelectedItem {
        case 1: mode = .fullscreen
        case 2: mode = .window
        case 3: mode = .region
        default: mode = nil
        }

        let dateRange: DateRange?
        switch datePopup?.indexOfSelectedItem {
        case 1: dateRange = .today
        case 2: dateRange = .lastWeek
        case 3: dateRange = .lastMonth
        default: dateRange = nil
        }

        return GalleryFilters(mode: mode, dateRange: dateRange, appName: nil)
    }

    private func performSearch() {
        // Read search text from the NSSearchToolbarItem
        let query: String
        if let searchItem = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "gallerySearch" }) as? NSSearchToolbarItem {
            query = searchItem.searchField.stringValue
        } else {
            query = ""
        }
        let filters = currentFilters

        if query.isEmpty && filters.isEmpty && sidebarFilter.isEmpty {
            loadRecent()
            return
        }

        do {
            screenshots = try database?.searchFiltered(text: query, filters: filters, sidebarFilter: sidebarFilter) ?? []
        } catch {
            NSLog("Search failed: \(error)")
            screenshots = []
        }
        reloadGrid()
    }

    private func reloadGrid() {
        collectionView.reloadData()
        emptyLabel.isHidden = !screenshots.isEmpty
    }

    private func refreshSidebar() {
        do {
            let dateGroups = try database?.fetchDateGroups() ?? []
            let appGroups = try database?.fetchAppGroups() ?? []
            browseSidebar.reload(dateGroups: dateGroups, appGroups: appGroups)
        } catch {
            NSLog("Failed to refresh sidebar: \(error)")
        }
    }

    // MARK: - Annotation Editor

    private func openAnnotationEditor(for screenshot: Screenshot) {
        guard let db = database else { return }
        let image = NSImage(contentsOfFile: screenshot.filepath)
        guard let image = image else { return }

        annotationEditorWC = AnnotationEditorWindowController(
            screenshot: screenshot, image: image, database: db
        )
        annotationEditorWC?.showWindow(nil)
    }
}

// MARK: - NSSplitViewDelegate

extension GalleryWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 { return 160 }  // sidebar min width
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 { return 300 }  // sidebar max width
        return proposedMaximumPosition
    }
}

// MARK: - NSCollectionViewDataSource

extension GalleryWindowController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        screenshots.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier("ScreenshotCell"),
            for: indexPath
        )
        if let cell = item as? ScreenshotCell, indexPath.item < screenshots.count {
            cell.configure(with: screenshots[indexPath.item])
            cell.onDoubleClick = { [weak self] screenshot in
                self?.openAnnotationEditor(for: screenshot)
            }
            cell.onContextMenu = { [weak self] screenshot, event in
                self?.buildContextMenu(for: screenshot)
            }
        }
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension GalleryWindowController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, indexPath.item < screenshots.count else {
            detailView.clear()
            return
        }
        detailView.configure(with: screenshots[indexPath.item])
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        if collectionView.selectionIndexPaths.isEmpty {
            detailView.clear()
        }
    }
}

// MARK: - NSToolbarDelegate

private extension NSToolbarItem.Identifier {
    static let modeFilter = NSToolbarItem.Identifier("modeFilter")
    static let dateFilter = NSToolbarItem.Identifier("dateFilter")
    static let gallerySearch = NSToolbarItem.Identifier("gallerySearch")
}

extension GalleryWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.modeFilter, .dateFilter, .flexibleSpace, .gallerySearch]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.modeFilter, .dateFilter, .flexibleSpace, .gallerySearch]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .modeFilter:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["All Modes", "Fullscreen", "Window", "Region"])
            popup.target = self
            popup.action = #selector(filterChanged(_:))
            popup.sizeToFit()
            modePopup = popup
            item.view = popup
            item.label = "Mode"
            return item

        case .dateFilter:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["Any Time", "Today", "Last 7 Days", "Last 30 Days"])
            popup.target = self
            popup.action = #selector(filterChanged(_:))
            popup.sizeToFit()
            datePopup = popup
            item.view = popup
            item.label = "Date"
            return item

        case .gallerySearch:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField.placeholderString = "Search screenshots..."
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            return item

        default:
            return nil
        }
    }
}

// MARK: - Context Menu

extension GalleryWindowController {
    func buildContextMenu(for screenshot: Screenshot) -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open in Preview", action: #selector(contextOpenInPreview(_:)), keyEquivalent: "")
        openItem.representedObject = screenshot
        openItem.target = self
        menu.addItem(openItem)

        let annotateItem = NSMenuItem(title: "Annotate", action: #selector(contextAnnotate(_:)), keyEquivalent: "")
        annotateItem.representedObject = screenshot
        annotateItem.target = self
        menu.addItem(annotateItem)

        let copyItem = NSMenuItem(title: "Copy Image", action: #selector(contextCopyImage(_:)), keyEquivalent: "")
        copyItem.representedObject = screenshot
        copyItem.target = self
        menu.addItem(copyItem)

        let exportItem = NSMenuItem(title: "Export PNG...", action: #selector(contextExportPNG(_:)), keyEquivalent: "")
        exportItem.representedObject = screenshot
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.representedObject = screenshot
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func contextOpenInPreview(_ sender: NSMenuItem) {
        guard let screenshot = sender.representedObject as? Screenshot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: screenshot.filepath))
    }

    @objc private func contextAnnotate(_ sender: NSMenuItem) {
        guard let screenshot = sender.representedObject as? Screenshot else { return }
        openAnnotationEditor(for: screenshot)
    }

    @objc private func contextCopyImage(_ sender: NSMenuItem) {
        guard let screenshot = sender.representedObject as? Screenshot else { return }
        guard let image = NSImage(contentsOfFile: screenshot.filepath),
              let tiff = image.tiffRepresentation else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
    }

    @objc private func contextExportPNG(_ sender: NSMenuItem) {
        guard let screenshot = sender.representedObject as? Screenshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = screenshot.filename
        panel.beginSheetModal(for: window!) { response in
            if response == .OK, let url = panel.url {
                try? FileManager.default.copyItem(
                    at: URL(fileURLWithPath: screenshot.filepath), to: url)
            }
        }
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let screenshot = sender.representedObject as? Screenshot else { return }
        // Defer so the context menu fully dismisses before the alert appears
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.window != nil else { return }
            let alert = NSAlert()
            alert.messageText = "Delete Screenshot?"
            alert.informativeText = "This will permanently remove the screenshot and its file from disk."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            do {
                try self.database?.deleteScreenshot(id: screenshot.id)
                try? FileManager.default.removeItem(atPath: screenshot.filepath)
                self.loadRecent()
                self.detailView.clear()
            } catch {
                NSLog("Failed to delete screenshot: \(error)")
            }
        }
    }
}

// MARK: - ScreenshotCell (double-click + context menu support via subclass)

class ScreenshotCellView: NSView {
    var onDoubleClick: (() -> Void)?
    var onContextMenu: ((NSEvent) -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return onContextMenu?(event)
    }
}

private let thumbnailCache = NSCache<NSString, NSImage>()
private let thumbnailQueue = DispatchQueue(label: "com.screenlens.thumbnails", qos: .userInitiated, attributes: .concurrent)

class ScreenshotCell: NSCollectionViewItem {
    private let thumbnailView = NSImageView()
    private let modeIcon = NSImageView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let tagsLabel = NSTextField(labelWithString: "")
    var onDoubleClick: ((Screenshot) -> Void)?
    var onContextMenu: ((Screenshot, NSEvent) -> NSMenu?)?
    private var screenshot: Screenshot?
    private var loadingId: String?

    override func loadView() {
        let cellView = ScreenshotCellView()
        cellView.wantsLayer = true
        cellView.layer?.cornerRadius = 8
        cellView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cellView.onDoubleClick = { [weak self] in
            if let s = self?.screenshot { self?.onDoubleClick?(s) }
        }
        cellView.onContextMenu = { [weak self] event in
            guard let s = self?.screenshot else { return nil }
            return self?.onContextMenu?(s, event)
        }
        view = cellView

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumbnailView)

        modeIcon.translatesAutoresizingMaskIntoConstraints = false
        modeIcon.imageScaling = .scaleProportionallyDown
        modeIcon.contentTintColor = .secondaryLabelColor
        view.addSubview(modeIcon)

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 2
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summaryLabel)

        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metaLabel)

        tagsLabel.font = .systemFont(ofSize: 10)
        tagsLabel.textColor = .systemBlue
        tagsLabel.lineBreakMode = .byTruncatingTail
        tagsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tagsLabel)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            thumbnailView.heightAnchor.constraint(equalToConstant: 150),

            modeIcon.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            modeIcon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            modeIcon.widthAnchor.constraint(equalToConstant: 14),
            modeIcon.heightAnchor.constraint(equalToConstant: 14),

            summaryLabel.centerYAnchor.constraint(equalTo: modeIcon.centerYAnchor),
            summaryLabel.leadingAnchor.constraint(equalTo: modeIcon.trailingAnchor, constant: 4),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

            metaLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            metaLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

            tagsLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 2),
            tagsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            tagsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            tagsLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 2 : 0
            view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadingId = nil
        thumbnailView.image = nil
    }

    func configure(with screenshot: Screenshot) {
        self.screenshot = screenshot
        self.loadingId = screenshot.id

        // Load thumbnail async with cache
        let cacheKey = screenshot.id as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            thumbnailView.image = cached
        } else {
            thumbnailView.image = nil
            let path = screenshot.filepath
            let id = screenshot.id
            thumbnailQueue.async { [weak self] in
                guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return }
                let options: [CFString: Any] = [
                    kCGImageSourceThumbnailMaxPixelSize: 480,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ]
                guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
                let thumb = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
                thumbnailCache.setObject(thumb, forKey: cacheKey)
                DispatchQueue.main.async {
                    guard self?.loadingId == id else { return }
                    self?.thumbnailView.image = thumb
                }
            }
        }

        modeIcon.image = NSImage(systemSymbolName: screenshot.mode.sfSymbol, accessibilityDescription: screenshot.mode.displayName)
        summaryLabel.stringValue = screenshot.summary ?? "No analysis yet"

        let app = screenshot.application ?? "Unknown"
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        var dateStr = screenshot.capturedAt
        if let d = ISO8601DateFormatter().date(from: screenshot.capturedAt) {
            dateStr = fmt.string(from: d)
        }
        metaLabel.stringValue = "\(app) · \(dateStr)"

        let tags = screenshot.tagList
        tagsLabel.stringValue = tags.isEmpty ? "" : tags.prefix(4).joined(separator: " · ")
    }
}
