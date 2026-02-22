import AppKit

/// Native gallery window for browsing and searching screenshots.
class GalleryWindowController: NSWindowController {

    private var searchField: NSSearchField!
    private var collectionView: NSCollectionView!
    var database: ScreenLensDatabase?

    convenience init(database: ScreenLensDatabase?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ScreenLens"
        window.center()
        window.isReleasedWhenClosed = false

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

        // Collection view for image grid
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 220, height: 200)
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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        // Layout constraints
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Data

    private var screenshots: [Screenshot] = []

    private func loadRecent() {
        do {
            screenshots = try database?.listRecent() ?? []
        } catch {
            NSLog("Failed to load recent screenshots: \(error)")
            screenshots = []
        }
        collectionView.reloadData()
    }

    @objc private func searchChanged() {
        let query = searchField.stringValue
        if query.isEmpty {
            loadRecent()
        } else {
            do {
                screenshots = try database?.search(text: query) ?? []
            } catch {
                NSLog("Search failed: \(error)")
                screenshots = []
            }
            collectionView.reloadData()
        }
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
        }
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension GalleryWindowController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, indexPath.item < screenshots.count else { return }
        let screenshot = screenshots[indexPath.item]
        NSWorkspace.shared.open(URL(fileURLWithPath: screenshot.filepath))
    }
}

// MARK: - ScreenshotCell

class ScreenshotCell: NSCollectionViewItem {
    private let thumbnailView = NSImageView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let tagsLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumbnailView)

        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summaryLabel)

        tagsLabel.font = .systemFont(ofSize: 10)
        tagsLabel.textColor = .secondaryLabelColor
        tagsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tagsLabel)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            thumbnailView.heightAnchor.constraint(equalToConstant: 140),

            summaryLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 4),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

            tagsLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 2),
            tagsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            tagsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
        ])
    }

    func configure(with screenshot: Screenshot) {
        thumbnailView.image = NSImage(contentsOfFile: screenshot.filepath)
        summaryLabel.stringValue = screenshot.summary ?? "No analysis yet"
        tagsLabel.stringValue = screenshot.tagList.joined(separator: " · ")
    }
}
