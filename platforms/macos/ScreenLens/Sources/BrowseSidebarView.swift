import AppKit

// MARK: - Sidebar Filter

struct SidebarFilter {
    var dateStart: String?    // ISO8601, inclusive
    var dateEnd: String?      // ISO8601, exclusive
    var application: String?  // exact match

    var isEmpty: Bool {
        dateStart == nil && dateEnd == nil && application == nil
    }
}

// MARK: - Sidebar Item

class SidebarItem {
    enum Kind {
        case header(String)
        case allScreenshots
        case year(Int)
        case month(year: Int, month: Int)
        case day(year: Int, month: Int, day: Int)
        case app(String)
    }

    let kind: Kind
    let title: String
    let count: Int
    var children: [SidebarItem] = []

    var isHeader: Bool {
        if case .header = kind { return true }
        return false
    }

    var isExpandable: Bool {
        !children.isEmpty
    }

    init(kind: Kind, title: String, count: Int, children: [SidebarItem] = []) {
        self.kind = kind
        self.title = title
        self.count = count
        self.children = children
    }

    /// Produce a SidebarFilter for this item's selection.
    var filter: SidebarFilter {
        switch kind {
        case .allScreenshots, .header:
            return SidebarFilter()
        case .year(let y):
            return SidebarFilter(
                dateStart: String(format: "%04d-01-01T00:00:00Z", y),
                dateEnd: String(format: "%04d-01-01T00:00:00Z", y + 1)
            )
        case .month(let y, let m):
            let nextMonth = m == 12 ? 1 : m + 1
            let nextYear = m == 12 ? y + 1 : y
            return SidebarFilter(
                dateStart: String(format: "%04d-%02d-01T00:00:00Z", y, m),
                dateEnd: String(format: "%04d-%02d-01T00:00:00Z", nextYear, nextMonth)
            )
        case .day(let y, let m, let d):
            // Compute next day using Calendar
            var comps = DateComponents()
            comps.year = y; comps.month = m; comps.day = d
            let cal = Calendar(identifier: .gregorian)
            if let date = cal.date(from: comps),
               let next = cal.date(byAdding: .day, value: 1, to: date) {
                let nc = cal.dateComponents([.year, .month, .day], from: next)
                return SidebarFilter(
                    dateStart: String(format: "%04d-%02d-%02dT00:00:00Z", y, m, d),
                    dateEnd: String(format: "%04d-%02d-%02dT00:00:00Z", nc.year!, nc.month!, nc.day!)
                )
            }
            return SidebarFilter(
                dateStart: String(format: "%04d-%02d-%02dT00:00:00Z", y, m, d),
                dateEnd: String(format: "%04d-%02d-%02dT00:00:00Z", y, m, d + 1)
            )
        case .app(let name):
            return SidebarFilter(application: name)
        }
    }
}

// MARK: - Browse Sidebar View

class BrowseSidebarView: NSView {
    private var outlineView: NSOutlineView!
    private var scrollView: NSScrollView!
    private var rootItems: [SidebarItem] = []
    private var suppressSelectionCallback = false

    var onSelectionChanged: ((SidebarFilter) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 14
        outlineView.rowSizeStyle = .default
        outlineView.dataSource = self
        outlineView.delegate = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Title"))
        col.isEditable = false
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
    }

    // MARK: - Reload

    func reload(dateGroups: [DateGroupRow], appGroups: [AppGroupRow]) {
        let totalCount = dateGroups.reduce(0) { $0 + $1.count }

        var items: [SidebarItem] = []

        // All Screenshots
        items.append(SidebarItem(kind: .allScreenshots, title: "All Screenshots", count: totalCount))

        // BY DATE header
        let dateTree = buildDateTree(from: dateGroups)
        let dateHeader = SidebarItem(kind: .header("BY DATE"), title: "BY DATE", count: 0, children: dateTree)
        items.append(dateHeader)

        // BY APPLICATION header
        let appChildren = appGroups.map { SidebarItem(kind: .app($0.name), title: $0.name, count: $0.count) }
        let appHeader = SidebarItem(kind: .header("BY APPLICATION"), title: "BY APPLICATION", count: 0, children: appChildren)
        items.append(appHeader)

        rootItems = items

        suppressSelectionCallback = true
        outlineView.reloadData()

        // Expand headers by default
        for item in rootItems where item.isHeader {
            outlineView.expandItem(item)
        }

        // Select "All Screenshots" by default if nothing selected
        if outlineView.selectedRow < 0 {
            let row = outlineView.row(forItem: rootItems.first)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        suppressSelectionCallback = false
    }

    private func buildDateTree(from rows: [DateGroupRow]) -> [SidebarItem] {
        // Group by year, then month, then day — rows are already DESC sorted
        var yearMap: [Int: [DateGroupRow]] = [:]
        for r in rows {
            yearMap[r.year, default: []].append(r)
        }

        let monthSymbols = DateFormatter().monthSymbols!

        var years: [SidebarItem] = []
        for y in yearMap.keys.sorted(by: >) {
            let yearRows = yearMap[y]!
            let yearCount = yearRows.reduce(0) { $0 + $1.count }

            // Group by month
            var monthMap: [Int: [DateGroupRow]] = [:]
            for r in yearRows {
                monthMap[r.month, default: []].append(r)
            }

            var months: [SidebarItem] = []
            for m in monthMap.keys.sorted(by: >) {
                let monthRows = monthMap[m]!
                let monthCount = monthRows.reduce(0) { $0 + $1.count }

                let days: [SidebarItem] = monthRows.sorted(by: { $0.day > $1.day }).map { r in
                    let dayTitle = dayLabel(year: r.year, month: r.month, day: r.day)
                    return SidebarItem(kind: .day(year: r.year, month: r.month, day: r.day), title: dayTitle, count: r.count)
                }

                let monthName = (m >= 1 && m <= 12) ? monthSymbols[m - 1] : "Month \(m)"
                months.append(SidebarItem(kind: .month(year: y, month: m), title: monthName, count: monthCount, children: days))
            }

            years.append(SidebarItem(kind: .year(y), title: "\(y)", count: yearCount, children: months))
        }

        return years
    }

    private func dayLabel(year: Int, month: Int, day: Int) -> String {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps) else { return "\(day)" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"
        return fmt.string(from: date)
    }
}

// MARK: - NSOutlineViewDataSource

extension BrowseSidebarView: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootItems.count }
        guard let si = item as? SidebarItem else { return 0 }
        return si.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootItems[index] }
        return (item as! SidebarItem).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarItem)?.isExpandable ?? false
    }
}

// MARK: - NSOutlineViewDelegate

extension BrowseSidebarView: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarItem)?.isHeader ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let si = item as? SidebarItem else { return false }
        return !si.isHeader
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let si = item as? SidebarItem else { return nil }

        if si.isHeader {
            let id = NSUserInterfaceItemIdentifier("HeaderCell")
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.font = .systemFont(ofSize: 11, weight: .semibold)
                tf.textColor = .secondaryLabelColor
                tf.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(tf)
                c.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = si.title
            return cell
        }

        let id = NSUserInterfaceItemIdentifier("DataCell")
        let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? SidebarCellView ?? SidebarCellView(identifier: id)
        cell.configure(title: si.title, count: si.count)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? SidebarItem else { return }
        onSelectionChanged?(item.filter)
    }
}

// MARK: - Sidebar Cell View (title + count badge)

private class SidebarCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        textField = titleLabel

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -4),

            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, count: Int) {
        titleLabel.stringValue = title
        countLabel.stringValue = count > 0 ? "\(count)" : ""
    }
}
