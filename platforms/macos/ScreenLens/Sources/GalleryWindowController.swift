import AppKit

/// Native gallery window for browsing, searching, and filtering screenshots.
class GalleryWindowController: NSWindowController {

    private var searchField: NSSearchField!
    private var filterBar: FilterBarView!
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

        self.init(window: window)
        self.database = database
        setupUI()
        loadRecent()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Search bar
        searchField = NSSearchField()
        searchField.placeholderString = "Search screenshots..."
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        contentView.addSubview(searchField)

        // Filter bar
        filterBar = FilterBarView()
        filterBar.onFiltersChanged = { [weak self] _ in self?.performSearch() }
        contentView.addSubview(filterBar)

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

        // No extra container — BrowseSidebarView has its own scroll view

        // Center: collection view
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 240, height: 240)
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

        let detailContainer = NSView()
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
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            filterBar.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            filterBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            filterBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            splitView.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 8),
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

    @objc private func searchChanged() {
        performSearch()
    }

    private func performSearch() {
        let query = searchField.stringValue
        let filters = filterBar.currentFilters

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

// MARK: - ScreenshotCell (double-click support via subclass)

class ScreenshotCellView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }
}

class ScreenshotCell: NSCollectionViewItem {
    private let thumbnailView = NSImageView()
    private let modeIcon = NSImageView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let tagsLabel = NSTextField(labelWithString: "")
    var onDoubleClick: ((Screenshot) -> Void)?
    private var screenshot: Screenshot?

    override func loadView() {
        let cellView = ScreenshotCellView()
        cellView.wantsLayer = true
        cellView.layer?.cornerRadius = 8
        cellView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cellView.onDoubleClick = { [weak self] in
            if let s = self?.screenshot { self?.onDoubleClick?(s) }
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
        ])
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 2 : 0
            view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
        }
    }

    func configure(with screenshot: Screenshot) {
        self.screenshot = screenshot
        thumbnailView.image = NSImage(contentsOfFile: screenshot.filepath)
        modeIcon.image = NSImage(systemSymbolName: screenshot.mode.sfSymbol, accessibilityDescription: screenshot.mode.displayName)
        summaryLabel.stringValue = screenshot.summary ?? "No analysis yet"

        // "App · Date" meta line
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
