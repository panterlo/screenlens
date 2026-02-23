import AppKit

class FilterBarView: NSView {
    private let modePopup = NSPopUpButton()
    private let datePopup = NSPopUpButton()

    var onFiltersChanged: ((GalleryFilters) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // Mode filter
        modePopup.addItems(withTitles: ["All Modes", "Fullscreen", "Window", "Region"])
        modePopup.target = self
        modePopup.action = #selector(filterChanged)
        modePopup.translatesAutoresizingMaskIntoConstraints = false

        // Date filter
        datePopup.addItems(withTitles: ["Any Time", "Today", "Last 7 Days", "Last 30 Days"])
        datePopup.target = self
        datePopup.action = #selector(filterChanged)
        datePopup.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [modePopup, datePopup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc private func filterChanged() {
        onFiltersChanged?(currentFilters)
    }

    var currentFilters: GalleryFilters {
        let mode: CaptureMode?
        switch modePopup.indexOfSelectedItem {
        case 1: mode = .fullscreen
        case 2: mode = .window
        case 3: mode = .region
        default: mode = nil
        }

        let dateRange: DateRange?
        switch datePopup.indexOfSelectedItem {
        case 1: dateRange = .today
        case 2: dateRange = .lastWeek
        case 3: dateRange = .lastMonth
        default: dateRange = nil
        }

        return GalleryFilters(mode: mode, dateRange: dateRange, appName: nil)
    }
}
